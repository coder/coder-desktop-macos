import CoderSDK
import SwiftUI

/// An `ask_user_question` milestone: the agent's clarifying question(s) during planning.
/// When interactive (latest unanswered question, turn finished), the user picks an option
/// (or "Other") per question and submits; the answer is sent back as a normal message,
/// leaving plan mode unchanged. Otherwise it renders read-only.
struct AskQuestionView<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents
    let chatID: UUID
    let step: ToolStep
    let interactive: Bool

    @State private var choices: [Int: Int] = [:] // question index -> option index (-1 = Other)
    @State private var otherText: [Int: String] = [:]
    @State private var submitting = false
    @State private var submitted = false

    private var questions: [AskUserQuestion] {
        (step.call ?? step.result)?.askUserQuestions ?? []
    }

    private var canSubmit: Bool {
        !questions.isEmpty && questions.indices.allSatisfy { idx in
            guard let choice = choices[idx] else { return false }
            return choice != -1 || !(otherText[idx] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(interactive ? "The agent has a question" : "Asked", systemImage: "questionmark.bubble")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(questions.enumerated()), id: \.offset) { idx, question in
                questionView(idx, question)
            }

            if interactive, !submitted {
                Button(action: submit) {
                    if submitting { ProgressView().controlSize(.small) } else { Text("Send answer") }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canSubmit || submitting)
            } else if submitted {
                Text("Answer sent.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func questionView(_ idx: Int, _ question: AskUserQuestion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !question.header.isEmpty, question.header != question.question {
                Text(question.header).font(.caption.weight(.semibold))
            }
            Text(question.question).font(.callout)

            if interactive, !submitted {
                ForEach(Array(question.options.enumerated()), id: \.offset) { optIdx, option in
                    radio(label: option.label, description: option.description,
                          selected: choices[idx] == optIdx) { choices[idx] = optIdx }
                }
                radio(label: "Other", description: "", selected: choices[idx] == -1) { choices[idx] = -1 }
                if choices[idx] == -1 {
                    TextField("Your answer", text: Binding(
                        get: { otherText[idx] ?? "" }, set: { otherText[idx] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            } else {
                ForEach(Array(question.options.enumerated()), id: \.offset) { _, option in
                    Text("• \(option.label)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func radio(label: String, description: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                    if !description.isEmpty {
                        Text(description).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// Formats the answer exactly like the web: single question = the bare answer; multiple =
    /// "{n}. {header}: {answer}" lines.
    private func formattedAnswer() -> String {
        func answer(_ idx: Int, _ q: AskUserQuestion) -> String {
            guard let choice = choices[idx] else { return "" }
            if choice == -1 { return "Other: \((otherText[idx] ?? "").trimmingCharacters(in: .whitespaces))" }
            return q.options.indices.contains(choice) ? q.options[choice].label : ""
        }
        if questions.count == 1 { return answer(0, questions[0]) }
        return questions.enumerated().map { idx, q in
            let header = q.header.isEmpty ? "Question \(idx + 1)" : q.header
            return "\(idx + 1). \(header): \(answer(idx, q))"
        }.joined(separator: "\n")
    }

    private func submit() {
        let text = formattedAnswer()
        guard !text.isEmpty else { return }
        submitting = true
        Task {
            let ok = await agents.answerQuestion(chatID, text: text)
            submitting = false
            if ok { submitted = true }
        }
    }
}
