// Copyright © 2025 Mastodon gGmbH. All rights reserved.


import SwiftUI
import WebKit

struct WebContentView: UIViewRepresentable {
    private static let contentPool = WKProcessPool()
    
    enum Style {
        case linkPreviewCard
        
        var configurationString: String {
            switch self {
            case .linkPreviewCard:
                "<meta name='viewport' content='width=device-width,user-scalable=no'><style>body { margin: 0; color-scheme: light dark; } body > :only-child { width: 100vw !important; height: 100vh !important }</style>"
            }
        }
    }
    
    let style: Style
    let html: String
    let delegate = WebViewDelegate()

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.processPool = Self.contentPool
        config.websiteDataStore = .nonPersistent() // private/incognito mode
        config.suppressesIncrementalRendering = true
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.uiDelegate = delegate
        webView.navigationDelegate = delegate
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(style.configurationString + html, baseURL: nil)
    }
}

class WebViewDelegate: NSObject {
    
}

extension WebViewDelegate: WKNavigationDelegate, WKUIDelegate {
    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        let isTopLevelNavigation: Bool
        if let frame = navigationAction.targetFrame {
            isTopLevelNavigation = frame.isMainFrame
        } else {
            isTopLevelNavigation = true
        }
        
        if isTopLevelNavigation,
           // ignore form submits and such
           navigationAction.navigationType == .linkActivated || navigationAction.navigationType == .other,
           let url = navigationAction.request.url,
           url.absoluteString != "about:blank" {
            return .cancel
        }
        return .allow
    }

}
