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
    /// The qualified form, always searchable even when `triggerText` is bare — so a query typed
    /// against the qualified alias keeps matching if collision state changes mid-trigger.
    let altTriggerText: String

    var id: String { "\(source.rawValue)/\(name)" }

    /// Workspace skills are always source-qualified, and a personal skill is qualified when a
    /// workspace skill shares its name (or when workspace skills aren't known yet), since a bare
    /// name is ambiguous to `read_skill`. Mirrors the web's `createSkillMenuItem`.
    init(name: String, description: String?, source: Source, qualified: Bool? = nil) {
        self.name = name
        self.description = description
        self.source = source
        let qualify = qualified ?? (source == .workspace)
        let qualifiedText = "/\(source.rawValue)/\(name)"
        triggerText = qualify && source != .command ? qualifiedText : "/\(name)"
        altTriggerText = source == .command ? "/\(name)" : qualifiedText
    }
}

/// Ranks menu items against a query typed after the "/": prefix match on the name or either
/// trigger form, then a substring match on those, then a description substring. Matching the
/// trigger forms is what lets a typed qualified query ("workspace/dep") find its skill.
///
/// Equal ranks break by name, then by the caller's original order — which keeps commands ahead
/// of personal skills ahead of workspace skills among otherwise-equal matches. A higher-ranked
/// match from a later group can still sort first; the menu is a flat list, not web's
/// section-partitioned one.
func filterSkills(_ items: [SkillMenuItem], query: String) -> [SkillMenuItem] {
    let q = query.lowercased()
    if q.isEmpty { return items }

    func rank(_ s: SkillMenuItem) -> Int {
        // Compared without the leading slash, since the query is what follows it.
        let candidates = [s.name, s.triggerText, s.altTriggerText]
            .map { $0.hasPrefix("/") ? String($0.dropFirst()) : $0 }
            .map { $0.lowercased() }
        if candidates.contains(where: { $0.hasPrefix(q) }) { return 0 }
        if candidates.contains(where: { $0.contains(q) }) { return 1 }
        if (s.description ?? "").lowercased().contains(q) { return 2 }
        return 3
    }

    return items.enumerated()
        .map { (index: $0.offset, item: $0.element, rank: rank($0.element)) }
        .filter { $0.rank < 3 }
        .sorted { a, b in
            if a.rank != b.rank { return a.rank < b.rank }
            let nameOrder = a.item.name.lowercased().compare(b.item.name.lowercased())
            return nameOrder == .orderedSame ? a.index < b.index : nameOrder == .orderedAscending
        }
        .map(\.item)
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
