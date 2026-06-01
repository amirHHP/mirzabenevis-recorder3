import SwiftUI

struct TranscriptView: View {
    let words: [TranscriptWord]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if words.isEmpty {
                    emptyState
                } else {
                    wordFlow
                }
            }
            .onChange(of: words.count) { _, _ in
                if let last = words.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("متن رونوشت اینجا نمایش داده می‌شود")
                .foregroundStyle(.secondary)
            Text("دکمه «شروع ضبط» را بزنید")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var wordFlow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("رونوشت (\(words.count) کلمه)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)

            FlowLayout(spacing: 6) {
                ForEach(words) { word in
                    WordChip(word: word)
                        .id(word.id)
                }
            }
            .padding()
        }
    }
}

struct WordChip: View {
    let word: TranscriptWord
    @State private var isHovered = false

    var body: some View {
        Text(word.text)
            .font(.body)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
            )
            .help(String(format: "%.1fs – %.1fs | اطمینان: %.0f%%", word.start, word.end, word.confidence * 100))
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

/// Simple flow layout for word chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
