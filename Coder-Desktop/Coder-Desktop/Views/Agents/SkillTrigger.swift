import CoderSDK
import SwiftUI

/// Compiled once — this runs on every keystroke/selection change. NSRegularExpression is
/// immutable and thread-safe.
private let skillTriggerRegex = try? NSRegularExpression(pattern: "(?:^|\\s)/(\\S*)$")

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

/// One entry in the "/" menu: a personal skill, a workspace skill, or a built-in command. They
/// share a shape so filtering, keyboard selection and insertion work the same for all three.
struct SkillMenuItem: Identifiable, Equatable {
    enum Source: String { case command, personal, workspace }

    let name: String
    let description: String?
    let source: Source
    /// What gets inserted, e.g. "/compact" or "/workspace/deploy".
    let triggerText: String

    var id: String { "\(source.rawValue)/\(name)" }

    /// Workspace skills are always source-qualified, and a personal skill is qualified when a
    /// workspace skill shares its name (or when workspace skills aren't known yet), since a bare
    /// name is ambiguous to `read_skill`. Mirrors the web's `createSkillMenuItem`.
    init(name: String, description: String?, source: Source, qualified: Bool? = nil) {
        self.name = name
        self.description = description
        self.source = source
        let qualify = qualified ?? (source == .workspace)
        triggerText = qualify && source != .command ? "/\(source.rawValue)/\(name)" : "/\(name)"
    }
}

/// Ranks menu items against a query: name-prefix, then name-substring, then
/// description-substring. Ties break alphabetically; the caller's ordering across sources
/// (commands, personal, workspace) is preserved by filtering each group separately.
func filterSkills(_ items: [SkillMenuItem], query: String) -> [SkillMenuItem] {
    let q = query.lowercased()
    func rank(_ s: SkillMenuItem) -> Int {
        let name = s.name.lowercased()
        if name.hasPrefix(q) { return 0 }
        if name.contains(q) { return 1 }
        if (s.description ?? "").lowercased().contains(q) { return 2 }
        return 3
    }
    if q.isEmpty { return items }
    return items.filter { rank($0) < 3 }.sorted { a, b in
        let ra = rank(a), rb = rank(b)
        return ra == rb ? a.name.lowercased() < b.name.lowercased() : ra < rb
    }
}

/// State shared between the editor's coordinator and the SwiftUI menu hosted in the popover.
@MainActor
final class SkillMenuModel: ObservableObject {
    @Published var skills: [SkillMenuItem] = []
    @Published var highlighted = 0
    var onSelect: (SkillMenuItem) -> Void = { _ in }
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
                                    HStack(spacing: 5) {
                                        Text(skill.triggerText).font(.callout.monospaced())
                                        if skill.source == .workspace {
                                            Text("Workspace")
                                                .font(.caption2)
                                                .padding(.horizontal, 4)
                                                .background(
                                                    Color.secondary.opacity(0.15),
                                                    in: RoundedRectangle(cornerRadius: 3)
                                                )
                                                .foregroundStyle(.secondary)
                                        }
                                    }
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
