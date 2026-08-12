import Combine
import Foundation
import SwiftUI
import WebKit
import PocketCastsDataModel
import PocketCastsUtils

class PlayLogViewModel: ObservableObject {
    @Published var logs = ""

    private var cancellables = Set<AnyCancellable>()

    init() {
        let notifications: [NSNotification.Name] = [
            Constants.Notifications.playbackStarted,
            Constants.Notifications.playbackPaused,
            Constants.Notifications.playbackEnded
        ]

        notifications.forEach { name in
            NotificationCenter.default.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in Task { await self?.load() } }
                .store(in: &cancellables)
        }
    }

    func load() async {
        let result = await PlayLog.shared.logFileAsString()
        await MainActor.run {
            self.logs = result
        }
    }

    var shareURL: URL? {
        guard let data = logs.data(using: .utf8) else { return nil }
        let date = Date()
        let components = Calendar.current.dateComponents(in: .current, from: date)

        let dateString = String(format: "%04d-%02d-%02d-%02d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("pocketcasts-playlog-\(dateString).txt")
        try? data.write(to: tempURL)
        return tempURL
    }
}

struct PlayLogView: View {
    @StateObject var model: PlayLogViewModel

    @EnvironmentObject var theme: Theme

    var body: some View {
        PlayLogWebView(logContent: model.logs)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Play Log")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let url = model.shareURL {
                    ShareLink(item: url, preview: SharePreview("playlog.txt")) {
                        Image(systemName: "square.and.arrow.up")
                            .bold()
                    }
                }
            }
        }
        .foregroundStyle(theme.primaryIcon01)
        .applyDefaultThemeOptions()
        .ignoresSafeArea()
        .task {
            await model.load()
        }
    }
}

// MARK: - PlayLogWebView

struct PlayLogWebView: UIViewRepresentable {
    let logContent: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let html = buildHTML(from: logContent)
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func buildHTML(from content: String) -> String {
        let lines = content.components(separatedBy: "\n")
            .map { $0.isEmpty ? "<br>" : "<p>\($0)</p>" }
            .joined(separator: "\n")

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
        <style>
            body {
                font-family: -apple-system, Menlo, monospace;
                font-size: 16px;
                padding: 8px;
                margin: 0;
                color: \(cssColor(UIColor.label));
                background-color: transparent;
                -webkit-text-size-adjust: none;
            }
            p {
                margin: 4px 0;
                line-height: 1.4;
            }
            a {
                color: \(cssColor(UIColor.systemBlue));
                text-decoration: underline;
            }
        </style>
        </head>
        <body>
        \(lines)
        </body>
        </html>
        """
    }

    private func cssColor(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.resolvedColor(with: UITraitCollection.current).getRed(&r, green: &g, blue: &b, alpha: &a)
        return "rgba(\(Int(r * 255)), \(Int(g * 255)), \(Int(b * 255)), \(a))"
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("window.scrollTo(0, document.body.scrollHeight);", completionHandler: nil)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url,
                  navigationAction.navigationType == .linkActivated else {
                decisionHandler(.allow)
                return
            }

            guard url.host == "localhost", let fragment = url.fragment else {
                decisionHandler(.cancel)
                return
            }

            let params = parseFragment(fragment)
            guard let timestamp = params["playerJumpTo"],
                  let episodeUuid = params["episode"] else {
                decisionHandler(.cancel)
                return
            }

            let time = SJCommonUtils.colonFormattedString(toTime: timestamp)
            guard time >= 0 else {
                decisionHandler(.cancel)
                return
            }

            // If the tapped episode is already playing, just seek
            if PlaybackManager.shared.currentEpisode?.uuid == episodeUuid {
                PlaybackManager.shared.seekTo(time: time)
            } else if let episode = DataManager.sharedManager.findBaseEpisode(uuid: episodeUuid) {
                PlaybackManager.shared.load(episode: episode, autoPlay: true, overrideUpNext: false)
                // Seek after a short delay to allow the episode to load
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    PlaybackManager.shared.seekTo(time: time)
                }
            }

            decisionHandler(.cancel)
        }

        private func parseFragment(_ fragment: String) -> [String: String] {
            var params: [String: String] = [:]
            for component in fragment.components(separatedBy: "&") {
                let pair = component.components(separatedBy: "=")
                if pair.count == 2 {
                    params[pair[0]] = pair[1]
                }
            }
            return params
        }
    }
}
