import AppKit
import SwiftUI
import WebKit

/// Displays the official YouTube embed whenever the Lofi Girl Music surface is
/// open. The controller retains the web view between SwiftUI appearances.
struct LofiYouTubeWebView: NSViewRepresentable {
    @ObservedObject var player: LofiYouTubePlayer

    func makeCoordinator() -> Coordinator {
        Coordinator(player: player)
    }

    func makeNSView(context: Context) -> WKWebView {
        if let retainedWebView = player.webView {
            context.coordinator.webView = retainedWebView
            player.attach(to: retainedWebView)
            return retainedWebView
        }

        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: Coordinator.messageHandlerName)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.applicationNameForUserAgent = "HocusFocus/1.0"

        let webView = MinimumSizeYouTubeWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = .black
        webView.allowsMagnification = false
        webView.setContentCompressionResistancePriority(.required, for: .horizontal)
        webView.setContentCompressionResistancePriority(.required, for: .vertical)

        context.coordinator.webView = webView
        player.attach(to: webView)
        webView.loadHTMLString(
            player.htmlDocument,
            baseURL: URL(string: "https://app.notchflow.localclone/")
        )
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Commands are sent directly by the observable controller. Rebuilding
        // the page here would interrupt live audio on unrelated SwiftUI updates.
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.player?.detach(from: webView)
        coordinator.webView = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let messageHandlerName = "notchflowYouTube"

        weak var player: LofiYouTubePlayer?
        weak var webView: WKWebView?

        init(player: LofiYouTubePlayer) {
            self.player = player
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == Self.messageHandlerName,
                  let body = message.body as? [String: Any] else { return }
            Task { @MainActor [weak player] in
                player?.receive(message: body)
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            reportNavigationFailure(error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            reportNavigationFailure(error)
        }

        private func reportNavigationFailure(_ error: Error) {
            Task { @MainActor [weak player] in
                player?.receive(message: [
                    "event": "navigationError",
                    "message": error.localizedDescription,
                ])
            }
        }
    }
}

/// YouTube's embedded-player requirements specify a viewport of at least
/// 200×200. The intrinsic size and required compression resistance make an
/// accidental undersized notch integration much less likely.
private final class MinimumSizeYouTubeWebView: WKWebView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: 320, height: 200)
    }
}

/// Convenience wrapper with the minimum legal player footprint encoded in its
/// SwiftUI layout. The expanded notch must reserve at least this much room.
struct LofiYouTubePlayerView: View {
    @ObservedObject var player: LofiYouTubePlayer

    var body: some View {
        LofiYouTubeWebView(player: player)
            .frame(minWidth: 200, idealWidth: 356, minHeight: 200, idealHeight: 200)
            .background(.black)
            .accessibilityLabel("YouTube player for \(player.selectedStation.title)")
    }
}
