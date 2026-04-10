import SwiftUI

/// Full on-device transcript view: shows word-by-word paragraphs with live
/// highlighting synced to playback. Tapping a paragraph seeks to its start time.
@available(iOS 26.0, *)
struct OnDeviceTranscriptView: View {
    @ObservedObject var viewModel: OnDeviceTranscriptViewModel
    @EnvironmentObject var theme: Theme

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    contentView(proxy: proxy)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if viewModel.isOutOfSync {
                        syncButton
                            .padding(.horizontal, 12)
                            .padding(.bottom, geometry.safeAreaInsets.bottom + 12)
                            .zIndex(1)
                            .ignoresSafeArea(.keyboard)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func contentView(proxy: ScrollViewProxy) -> some View {
        switch viewModel.state {
        case .idle:
            EmptyView()

        case .queued:
            queueStatusView

        case .unavailable:
            statusMessage("On-device transcription is not available on this device.")

        case .preparingAssets, .transcribing:
            queueStatusView

        case .completed:
            transcriptScrollView(proxy: proxy)

        case .error(let message):
            statusMessage(message)
        }
    }

    // MARK: - Progress

    private func progressView(progress: Double, label: String) -> some View {
        VStack(spacing: 16) {
            if progress > 0 {
                ProgressView(value: progress)
                    .tint(theme.playerContrast01)
                    .frame(maxWidth: 260)
            } else {
                ProgressView()
                    .tint(theme.playerContrast01)
            }

            if !label.isEmpty {
                Text(label)
                    .font(size: 14, style: .footnote, weight: .regular)
                    .foregroundStyle(theme.playerContrast02)
            }
        }
        .padding()
    }

    private var queueStatusView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let activeItem = viewModel.activeQueueItem {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Transcribing now")
                            .font(size: 13, style: .footnote, weight: .semibold)
                            .foregroundStyle(theme.playerContrast02)

                        Text(activeItem.title)
                            .font(size: 20, style: .body, weight: .semibold)
                            .foregroundStyle(theme.playerContrast01)
                            .fixedSize(horizontal: false, vertical: true)

                        progressView(progress: activeItem.progress, label: activeItem.progressLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if !viewModel.queuedQueueItems.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Queued episodes")
                            .font(size: 13, style: .footnote, weight: .semibold)
                            .foregroundStyle(theme.playerContrast02)

                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(viewModel.queuedQueueItems) { item in
                                Text(item.title)
                                    .font(size: 16, style: .body, weight: .regular)
                                    .foregroundStyle(theme.playerContrast01)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 24)
        }
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
            .padding(.horizontal, 10)
            .padding(.vertical, 24)
        }
        .mask {
            transcriptEdgeFadeMask
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { _ in
                    viewModel.userDidStartManualScroll()
                }
                .onEnded { _ in
                    viewModel.userDidStopManualScroll()
                }
        )
        .onChange(of: viewModel.scrollRequest) { _, request in
            guard let request else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(request.paragraphID, anchor: .center)
            }
        }
    }

    private var transcriptEdgeFadeMask: some View {
        GeometryReader { geometry in
            let fadeHeight = min(28.0, geometry.size.height / 6)

            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: fadeHeight)
                Rectangle()
                    .fill(.black)
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: fadeHeight)
            }
        }
    }

    @ViewBuilder
    private func paragraphView(_ paragraph: OnDeviceTranscriptParagraph) -> some View {
        let isActive = viewModel.currentParagraphIndex == paragraph.id

        VStack(alignment: .leading, spacing: 0) {
            if isActive {
                WrappingWordLayout(spacing: 4, lineSpacing: 2) {
                    ForEach(paragraph.words) { word in
                        Text(word.displayText)
                            .font(size: 17, style: .body, weight: .regular)
                            .foregroundStyle(wordColor(for: word))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
            } else {
                Text(paragraph.text)
                    .font(size: 17, style: .body, weight: .regular)
                    .foregroundStyle(paragraphColor(isActive: isActive))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func paragraphColor(isActive: Bool) -> Color {
        isActive ? theme.playerContrast01 : theme.playerContrast02
    }

    private func wordColor(for word: OnDeviceTranscriptWord) -> Color {
        if let currentWordID = viewModel.currentWordID,
           word.id <= currentWordID {
            return theme.playerContrast01
        }
        return theme.playerContrast02
    }

    private func statusMessage(_ message: String) -> some View {
        Text(message)
            .font(size: 15, style: .body, weight: .regular)
            .foregroundStyle(theme.playerContrast02)
            .multilineTextAlignment(.center)
            .padding(32)
    }

    private var syncButton: some View {
        Button(action: viewModel.resyncNow) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.playerContrast01)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
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
