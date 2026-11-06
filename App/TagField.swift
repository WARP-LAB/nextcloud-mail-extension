import SwiftUI

/// A field of tags, for FR6's phrases: text typed and ended with Return becomes a tag, shown as a bubble with a
/// button that removes it. A tag can hold several words, such as "see attached". Backspace in the empty field removes
/// the last tag, and the same tag in other case isn't added twice.
struct TagField: View {
    @Binding var tags: [String]
    var prompt: String

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if !tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        TagBubble(text: tag) {
                            tags.removeAll { $0 == tag }
                        }
                    }
                }
            }
            TextField("Add", text: $draft, prompt: Text(prompt))
                .labelsHidden()
                .onSubmit(add)
                .onKeyPress(.delete) {
                    guard draft.isEmpty, !tags.isEmpty else {
                        return .ignored
                    }
                    tags.removeLast()
                    return .handled
                }
                .onDisappear(perform: add)
        }
    }

    private func add() {
        let tag = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        guard !tag.isEmpty, !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else {
            return
        }
        tags.append(tag)
    }
}

private struct TagBubble: View {
    let text: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .lineLimit(1)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove “\(text)”")
            .accessibilityLabel("Remove \(text)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.35)))
    }
}

/// Lays its views out in rows from the trailing edge, as a form's values are, starting a new row when one is full.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = self.rows(subviews, width: proposal.width ?? .infinity)
        let width = rows.map { row in row.reduce(0) { $0 + $1.width } + spacing * CGFloat(row.count - 1) }.max() ?? 0
        let height = rows.reduce(0) { $0 + ($1.map(\.height).max() ?? 0) } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var index = 0
        var top = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var left = bounds.maxX - row.reduce(0) { $0 + $1.width } - spacing * CGFloat(row.count - 1)
            for size in row {
                subviews[index].place(at: CGPoint(x: left, y: top), proposal: ProposedViewSize(size))
                left += size.width + spacing
                index += 1
            }
            top += (row.map(\.height).max() ?? 0) + spacing
        }
    }

    /// The views' sizes, row by row.
    private func rows(_ subviews: Subviews, width: CGFloat) -> [[CGSize]] {
        var rows: [[CGSize]] = [[]]
        var used: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if let last = rows.last, !last.isEmpty, used + spacing + size.width > width {
                rows.append([])
                used = 0
            }
            used += (rows[rows.count - 1].isEmpty ? 0 : spacing) + size.width
            rows[rows.count - 1].append(size)
        }
        return rows.filter { !$0.isEmpty }
    }
}
