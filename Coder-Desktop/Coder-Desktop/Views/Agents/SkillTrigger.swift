import CoderSDK
import SwiftUI

// Compiled once — this runs on every keystroke/selection change. NSRegularExpression is
// immutable and thread-safe.
nonisolated(unsafe) private let skillTriggerRegex = try? NSRegularExpression(pattern: "(?:^|\\s)/(\\S*)$")

/// Finds an active "/skill" trigger token ending at the caret: a "/" at the start of input
/// or after whitespace, followed by non-whitespace. Returns the token range (slash..caret)
/// and the query after the slash, mirroring the web's `(?:^|\s)/(\S*)$`.
func parseSkillTrigger(in text: String, caret: Int) -> (range: NSRange, query: String)? {
    let ns = text as NSString
    guard caret >= 0, caret <= ns.length else { return nil }
    let upto = ns.substring(to: caret)
    guard let re = skillTriggerRegex else { return nil }
    let full = NSRange(location: 0, length: (upto as NSString).length)
    guard let match = re.firstMatch(in: upto, range: full) else { return nil }
    let queryRange = match.range(at: 1)
    let slash = queryRange.location - 1
    guard slash >= 0 else { return nil }
    let query = (upto as NSString).substring(with: queryRange)
    return (NSRange(location: slash, length: caret - slash), query)
}

/// Ranks skills against a query: name-prefix, then name-substring, then description-substring.
func filterSkills(_ skills: [UserSkill], query: String) -> [UserSkill] {
    let q = query.lowercased()
    func rank(_ s: UserSkill) -> Int {
        let name = s.name.lowercased()
        if name.hasPrefix(q) { return 0 }
        if name.contains(q) { return 1 }
        if (s.description ?? "").lowercased().contains(q) { return 2 }
        return 3
    }
    if q.isEmpty { return skills.sorted { $0.name.lowercased() < $1.name.lowercased() } }
    return skills.filter { rank($0) < 3 }.sorted { a, b in
        let ra = rank(a), rb = rank(b)
        return ra == rb ? a.name.lowercased() < b.name.lowercased() : ra < rb
    }
}

/// State shared between the editor's coordinator and the SwiftUI menu hosted in the popover.
@MainActor
final class SkillMenuModel: ObservableObject {
    @Published var skills: [UserSkill] = []
    @Published var highlighted = 0
    var onSelect: (UserSkill) -> Void = { _ in }
}

/// The "/" skills menu shown in the composer popover.
struct SkillsMenuView: View {
    @ObservedObject var model: SkillMenuModel

    var body: some View {
        Group {
            if model.skills.isEmpty {
                Text("No matching skills").font(.caption).foregroundStyle(.secondary).padding(10)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.skills.enumerated()), id: \.element.id) { idx, skill in
                            Button { model.onSelect(skill) } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("/\(skill.name)").font(.callout.monospaced())
                                    if let desc = skill.description, !desc.isEmpty {
                                        Text(desc).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(idx == model.highlighted ? Color.accentColor.opacity(0.15) : .clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 280)
        .frame(maxHeight: 220)
    }
}
