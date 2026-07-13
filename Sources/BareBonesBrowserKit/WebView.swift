//
//  WebView.swift
//  BareBonesBrowser
//
//  Created by Federico Cappelli on 06/02/2024.
//  Copyright © 2024 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

import BIFROSTKit
import Foundation
import HEIMDALLKit
import LUNAStore
import SwiftUI
import WebKit

@MainActor
public protocol WebViewUIDelegate {

    func webDidViewRequestNewWindow(with webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView?
}

public struct WebView {

    public typealias View = WKWebView
    let wkWebView: View
    private let bifrostModel: BIFROSTBrowserModel
    private let answerObserver: BIFROSTAnswerObserver

    public var webViewUIDelegate: WebViewUIDelegate?

    public init(configuration: WKWebViewConfiguration, bifrostModel: BIFROSTBrowserModel) {
        self.bifrostModel = bifrostModel
        let observer = BIFROSTAnswerObserver(model: bifrostModel)
        let isolatedConfiguration = configuration.copy() as! WKWebViewConfiguration
        isolatedConfiguration.userContentController = WKUserContentController()
        isolatedConfiguration.userContentController.add(observer, name: "bifrostAnswer")
        isolatedConfiguration.userContentController.addUserScript(
            WKUserScript(
                source: BIFROSTAnswerObserverScript.source,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        self.answerObserver = observer
        self.wkWebView = View(frame: .zero, configuration: isolatedConfiguration)
        self.wkWebView.allowsBackForwardNavigationGestures = true
    }

    func updateView(_ view: View) {
        // SwiftUI state updates should not reload the page. Navigation is explicit.
    }

    public func load(url: URL) {
        let req = URLRequest(url: url)
        load(req)
    }

    public func load(_ urlRequest: URLRequest) {
        Task { @MainActor in
            bifrostModel.clearAnswerVerdict()
        }
        wkWebView.load(urlRequest)
    }

    func goBack() -> Void {
        wkWebView.goBack()
    }

    func goForward() {
        wkWebView.goForward()
    }

    func reload() {
        wkWebView.reload()
    }

}

//MARK: - Coordinator

extension WebView {

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: WebView
        private let answerVerifier = BIFROSTAnswerVerifier()
        private var gateway: BIFROSTGateway?
        private var policySignature: String?
        private var resolvedRequests = Set<String>()
        private var lastAnswerHash: String?

        init(_ parent: WebView) {
            self.parent = parent
        }

        //MARK: - WKNavigationDelegate

        public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        }

        public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            lastAnswerHash = nil
            parent.answerObserver.reset()
            Task { @MainActor in
                parent.bifrostModel.clearAnswerVerdict()
            }
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            scanVisibleAnswer(in: webView)
        }

        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        }

        public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        }

        public func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        }

        public func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            Task { @MainActor in
                guard let gateway = ensureGateway() else {
                    parent.bifrostModel.publish(
                        BIFROSTBrowserStatus(
                            state: .refuse,
                            headline: "REFUSE",
                            reason: "BIFROST could not open its local audit ledger.",
                            policyId: "bifrost.ledger.unavailable",
                            confidence: 1.0,
                            receiptHash: nil
                        )
                    )
                    decisionHandler(.cancel)
                    return
                }

                do {
                    let context = NavigationContext(
                        url: navigationAction.request.url ?? URL(string: "about:blank")!,
                        initiator: nil,
                        method: navigationAction.request.httpMethod ?? "GET",
                        isMainFrame: navigationAction.targetFrame?.isMainFrame ?? true,
                        hasFormSubmission: navigationAction.navigationType == .formSubmitted || navigationAction.navigationType == .formResubmitted,
                        credentialFieldsPresent: false,
                        timestamp: Date()
                    )
                    let fingerprint = Self.fingerprint(context)
                    if resolvedRequests.remove(fingerprint) != nil {
                        let result = try gateway.recordUserAffirmedHold(context)
                        parent.bifrostModel.publish(
                            BIFROSTBrowserStatus(
                                state: .noObjection,
                                headline: "NO_OBJECTION",
                                reason: result.evaluation.verdict.reason,
                                policyId: nil,
                                confidence: result.evaluation.confidence,
                                receiptHash: result.auditRow.rowHash
                            )
                        )
                        decisionHandler(.allow)
                        return
                    }

                    let result = try gateway.evaluate(context)
                    let status = BIFROSTBrowserStatus(result: result)

                    switch result.evaluation.verdict {
                    case .noObjection, .abstain:
                        parent.bifrostModel.publish(status)
                        decisionHandler(.allow)
                    case .hold:
                        parent.bifrostModel.publishHold(status) { [weak self, weak webView] in
                            self?.resolvedRequests.insert(fingerprint)
                            webView?.load(navigationAction.request)
                        }
                        decisionHandler(.cancel)
                    case .refuse:
                        parent.bifrostModel.publish(status)
                        decisionHandler(.cancel)
                    }
                } catch {
                    parent.bifrostModel.publish(
                        BIFROSTBrowserStatus(
                            state: .refuse,
                            headline: "REFUSE",
                            reason: "BIFROST failed closed while sealing the navigation receipt.",
                            policyId: "bifrost.receipt.failure",
                            confidence: 1.0,
                            receiptHash: nil
                        )
                    )
                    decisionHandler(.cancel)
                }
            }
        }

        //MARK: - WKUIDelegate

        public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {

            if navigationAction.targetFrame == nil {
                let newWebView = parent.webViewUIDelegate?.webDidViewRequestNewWindow(with: webView, createWebViewWith: configuration, for: navigationAction, windowFeatures: windowFeatures)
                return newWebView
            }
            return nil
        }

        @MainActor
        private func ensureGateway() -> BIFROSTGateway? {
            if let gateway {
                let currentSignature = BIFROSTLocalStore.policySignature()
                if policySignature == currentSignature {
                    return gateway
                }
            }

            do {
                let currentSignature = BIFROSTLocalStore.policySignature()
                let store = try LUNAStore(databaseURL: BIFROSTLocalStore.ledgerURL())
                let created = BIFROSTGateway(
                    policy: BIFROSTLocalStore.policy(),
                    store: store,
                    onHeldRequest: { _, _ in .userCancelled },
                    onRefusedRequest: { _, _ in }
                )
                gateway = created
                policySignature = currentSignature
                return gateway
            } catch {
                return nil
            }
        }

        private static func fingerprint(_ context: NavigationContext) -> String {
            "\(context.method)|\(context.url.absoluteString)|\(context.isMainFrame)"
        }

        private func scanVisibleAnswer(in webView: WKWebView) {
            webView.evaluateJavaScript(BIFROSTAnswerObserverScript.collectOnceSource) { [weak self] result, _ in
                guard
                    let self,
                    let text = result as? String,
                    let verdict = self.answerVerifier.evaluate(text),
                    verdict.inputHash != self.lastAnswerHash
                else {
                    return
                }

                self.lastAnswerHash = verdict.inputHash
                Task { @MainActor [weak self] in
                    self?.parent.bifrostModel.publishAnswerVerdict(verdict)
                }
            }
        }
    }
}

#if os(macOS)
extension WebView: NSViewRepresentable {
    
    public func makeNSView(context: Context) -> View {
        #if DEBUG
        if #available(macOS 13.3, *) {
            wkWebView.isInspectable = true
        }
        #endif
        wkWebView.navigationDelegate = context.coordinator
        wkWebView.uiDelegate = context.coordinator
        return wkWebView
    }

    public func updateNSView(_ nsView: View, context: Context) {
        updateView(nsView)
    }
}
#else
extension WebView: UIViewRepresentable {
    
    public func makeUIView(context: Context) -> View {
        wkWebView.navigationDelegate = context.coordinator
        wkWebView.uiDelegate = context.coordinator
        return wkWebView
    }

    public func updateUIView(_ uiView: View, context: Context) {
        updateView(uiView)
    }
}
#endif
