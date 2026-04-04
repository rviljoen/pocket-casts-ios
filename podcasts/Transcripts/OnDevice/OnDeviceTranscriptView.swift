import SwiftUI

/// Full on-device transcript view: shows word-by-word paragraphs with live
/// highlighting synced to playback. Tapping a paragraph seeks to its start time.
@available(iOS 26.0, *)
struct OnDeviceTranscriptView: View {
    @ObservedObject var viewModel: OnDeviceTranscriptViewModel
    let onClose: () -> Void
    @EnvironmentObject var theme: Theme

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                contentView(proxy: proxy)
                    .padding(.top, headerHeight)

                topBar
                    .zIndex(1)
                    .ignoresSafeArea(.keyboard)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func contentView(proxy: ScrollViewProxy) -> some View {
        switch viewModel.state {
        case .idle:
            EmptyView()

        case .unavailable:
            statusMessage("On-device transcription is not available on this device.")

        case .preparingAssets, .transcribing:
            progressView

        case .completed:
            transcriptScrollView(proxy: proxy)

        case .error(let message):
            statusMessage(message)
        }
    }

    // MARK: - Progress

    private var progressView: some View {
        VStack(spacing: 16) {
            if viewModel.progress > 0 {
                ProgressView(value: viewModel.progress)
                    .tint(theme.playerContrast01)
                    .frame(maxWidth: 260)
            } else {
                ProgressView()
                    .tint(theme.playerContrast01)
            }

            if !viewModel.progressLabel.isEmpty {
                Text(viewModel.progressLabel)
                    .font(size: 14, style: .footnote, weight: .regular)
                    .foregroundStyle(theme.playerContrast02)
            }
        }
        .padding()
    }

    // MARK: - Transcript

    private func transcriptScrollView(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.paragraphs) { paragraph in
                    Button {
                        viewModel.seek(to: paragraph)
                    } label: {
                        paragraphView(paragraph)
                    }
                    .buttonStyle(.plain)
                    .id(paragraph.id)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .onChange(of: viewModel.currentParagraphIndex) { _, newIndex in
            guard let newIndex,
                  newIndex < viewModel.paragraphs.count else { return }
            let paragraph = viewModel.paragraphs[newIndex]
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(paragraph.id, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private func paragraphView(_ paragraph: OnDeviceTranscriptParagraph) -> some View {
        let paragraphIndex = viewModel.paragraphs.firstIndex(where: { $0.id == paragraph.id })
        let isActive = paragraphIndex != nil && viewModel.currentParagraphIndex == paragraphIndex

        VStack(alignment: .leading, spacing: 0) {
            WrappingWordLayout(spacing: 2, lineSpacing: 6) {
                ForEach(paragraph.words) { word in
                    Text(word.displayText + " ")
                        .font(size: 17, style: .body, weight: .regular)
                        .foregroundStyle(wordColor(for: word, paragraphIsActive: isActive))
                        .fixedSize()
                }
            }
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func wordColor(for word: OnDeviceTranscriptWord, paragraphIsActive: Bool) -> Color {
        guard paragraphIsActive, let currentIndex = viewModel.currentWordIndex else {
            return theme.playerContrast02
        }
        return word.id <= currentIndex
            ? theme.playerContrast01
            : theme.playerContrast02
    }

    private func statusMessage(_ message: String) -> some View {
        Text(message)
            .font(size: 15, style: .body, weight: .regular)
            .foregroundStyle(theme.playerContrast02)
            .multilineTextAlignment(.center)
            .padding(32)
    }

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.playerContrast01)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var headerHeight: CGFloat {
        72
    }
}

// MARK: - Wrapping word layout

/// A custom Layout that wraps words onto new lines, matching the prototype's WrappingHStack.
@available(iOS 26.0, *)
struct WrappingWordLayout: Layout {
    var spacing: CGFloat = 2
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            height += rowHeight
            if i < rows.count - 1 { height += lineSpacing }
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            var x = bounds.minX
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + lineSpacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var rowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([])
                rowWidth = 0
            }
            rows[rows.count - 1].append(subview)
            rowWidth += size.width + spacing
        }

        return rows
    }
}
