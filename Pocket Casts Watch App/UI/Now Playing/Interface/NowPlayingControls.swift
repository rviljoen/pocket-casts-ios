import PocketCastsDataModel
import SwiftUI

struct NowPlayingControls: View {
    @StateObject var viewModel: NowPlayingViewModel
    @Binding var presentView: WatchInterfaceType?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack {
                progressGroup
                    .frame(maxHeight: .infinity)
                plabackGroup
                    .frame(maxHeight: .infinity)
                navigationGroup
                    .frame(maxHeight: .infinity)
                // To take into account the page indicator view
                Spacer().frame(height: Constants.pagingIndicatorHeight)
            }
            .modify { content in
                if #available(watchOS 10.0, *) {
                    content.containerRelativeFrame(.vertical)
                }
            }
        }
        .modify { content in
            if #available(watchOS 9.4, *) {
                content.scrollBounceBehavior(.basedOnSize)
            }
        }
        .ignoresSafeArea(.all, edges: .bottom)
    }

    private var progressGroup: some View {
        VStack(alignment: .center) {
            MarqueeText(text: viewModel.episodeName, font: .dynamic(size: 14))

            HStack(alignment: .top) {
                Text(viewModel.progressTitle)
                    .foregroundColor(viewModel.episodeAccentColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(viewModel.timeRemaining)
                    .fixedSize()
            }
            .font(.dynamic(size: 13))
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    private var plabackGroup: some View {
        HStack {
            SkipButton(imageName: "skipback") {
                viewModel.skip(forward: false)
            } onLongPress: {
                if viewModel.hasChapters {
                    viewModel.changeChapter(next: false)
                } else {
                    viewModel.skip(forward: false)
                }
            }

            Spacer()
            playPauseButton
            Spacer()

            SkipButton(imageName: "skipforward") {
                viewModel.skip(forward: true)
            } onLongPress: {
                if viewModel.hasChapters {
                    viewModel.changeChapter(next: true)
                } else {
                    viewModel.skip(forward: true)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, minHeight: 32, idealHeight: 40, maxHeight: 44)
    }

    private var playPauseButton: some View {
        Button {
            WKInterfaceDevice.current().play(.click)
            viewModel.playPauseTapped()
        } label: {
            ZStack {
//                if #available(watchOS 10.0, *) {
//                    Circle()
//                        .fill(Color.white.opacity(0.12))
//                        .background(.ultraThinMaterial, in: Circle())
//                } else {
//                    Circle()
//                        .fill(Color.white.opacity(0.12))
//                }
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: viewModel.progress)
                    .stroke(viewModel.episodeAccentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(viewModel.isPlaying ? "pause" : "play")
                    .playGroupStlyed()
                    .padding(10)
            }
        }
        .accessibilityLabel(viewModel.isPlaying ? L10n.pause : L10n.play)
        .buttonStyle(.plain)
        .modifier(HandGestureShortcutPrimaryAction())
    }

    private var navigationGroup: some View {
        HStack {
            Button {
                WKInterfaceDevice.current().play(.click)
                presentView = .effects
            } label: {
                Image(viewModel.effectsIconName)
            }

            Spacer()
            VolumeControl(tint: viewModel.episodeAccentColor)
            Spacer()

            Button {
                WKInterfaceDevice.current().play(.click)
                presentView = .upnext
            } label: {
                switch viewModel.upNextCount {
                case 0 ... 8:
                    Image("upnext-\(viewModel.upNextCount)")
                default:
                    Image("upnext-9-plus")
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 2)
    }

    private enum Constants {
        static let pagingIndicatorHeight: CGFloat = 5
    }
}

private extension Image {
    func playGroupStlyed() -> some View {
        resizable()
            .aspectRatio(1, contentMode: .fit)
    }
}

private struct SkipButton: View {
    let imageName: String
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var longPressRecognized = false

    private let longPressDuration: TimeInterval = 0.5

    var body: some View {
        Button {
            guard !longPressRecognized else {
                longPressRecognized = false
                return
            }
            WKInterfaceDevice.current().play(.click)
            onTap()
        } label: {
            Image(imageName, bundle: .watchAssets)
                .playGroupStlyed()
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: longPressDuration)
                .onEnded { _ in
                    longPressRecognized = true
                    WKInterfaceDevice.current().play(.success)
                    onLongPress()
                }
        )
    }
}

struct NowPlayingView_Previews: PreviewProvider {
    static var previews: some View {
        ForEach(PreviewDevice.previewDevices) {
            NowPlayingControls(viewModel: NowPlayingViewModel(), presentView: .constant(nil))
                .previewDevice($0)
        }
    }
}

struct HandGestureShortcutPrimaryAction: ViewModifier {
    public func body(content: Content) -> some View {
        #if compiler(>=6.0)
        if #available(watchOS 11.0, *) {
            content
                .handGestureShortcut(.primaryAction)
        } else {
            content
        }
        #else
            content
        #endif
    }
}
