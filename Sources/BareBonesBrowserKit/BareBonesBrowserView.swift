//
//  BareBonesBrowserView.swift
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

import Foundation
import WebKit
import SwiftUI

private enum BIFROSTDesign {
    static let appBackground = Color(red: 0.984, green: 0.985, blue: 0.988)
    static let chrome = Color(red: 0.963, green: 0.965, blue: 0.972)
    static let surface = Color.white
    static let elevatedSurface = Color(red: 0.992, green: 0.992, blue: 0.996)
    static let border = Color(red: 0.882, green: 0.890, blue: 0.912)
    static let subtleBorder = Color(red: 0.925, green: 0.930, blue: 0.944)
    static let text = Color(red: 0.125, green: 0.114, blue: 0.145)
    static let mutedText = Color(red: 0.430, green: 0.410, blue: 0.485)
    static let faintText = Color(red: 0.565, green: 0.545, blue: 0.615)
    static let purple = Color(red: 0.419, green: 0.129, blue: 0.659)
    static let clear = Color(red: 0.100, green: 0.480, blue: 0.310)
    static let hold = Color(red: 0.735, green: 0.455, blue: 0.120)
    static let refuse = Color(red: 0.700, green: 0.160, blue: 0.200)

    static func verdictColor(_ state: BIFROSTBrowserStatus.State) -> Color {
        switch state {
        case .idle:
            return faintText
        case .noObjection, .abstain:
            return clear
        case .hold:
            return hold
        case .refuse:
            return refuse
        }
    }

    static func answerColor(_ display: BIFROSTAnswerVerdict.Display) -> Color {
        switch display {
        case .noScanFlag:
            return purple
        case .review:
            return hold
        }
    }
}

@MainActor
public protocol BareBonesBrowserUIDelegate {

    func browserDidRequestNewWindow(urlRequest: URLRequest)
}

@MainActor
public struct BareBonesBrowserView: View {

    private let homeURL: URL
    private let configuration: WKWebViewConfiguration
    private let userAgent: String?

    public var uiDelegate: BareBonesBrowserUIDelegate?

    @State private var tabs: [BIFROSTBrowserTab]
    @State private var selectedTabID: BIFROSTBrowserTab.ID
    @State private var showSettings = false
    @State private var bookmarks: [BIFROSTBookmark] = []
    @AppStorage("bifrost.onboarding.completed") private var onboardingCompleted = false
    @State private var showOnboarding = false
    @FocusState private var addressFieldFocused: Bool

    public init(initialURL: URL, 
                homeURL: URL,
                uiDelegate: BareBonesBrowserUIDelegate? = nil,
                configuration: WKWebViewConfiguration,
                userAgent: String? = nil) {
        self.homeURL = homeURL
        self.configuration = configuration
        self.userAgent = userAgent
        self.uiDelegate = uiDelegate

        let initialTab = BIFROSTBrowserTab(
            initialURL: initialURL,
            configuration: configuration,
            userAgent: userAgent
        )
        self._tabs = State(initialValue: [initialTab])
        self._selectedTabID = State(initialValue: initialTab.id)
    }

    public var body: some View {
        VStack(spacing: 0) {
            keyboardShortcutBridge

            BIFROSTTabStrip(
                tabs: tabs,
                selectedTabID: selectedTabID,
                canCloseTabs: tabs.count > 1,
                selectTab: selectTab,
                closeTab: closeTab,
                newTab: { openNewTab(initialURL: nil) }
            )

            if let selectedTab {
                toolbar(for: selectedTab)
                BIFROSTActiveTabSurface(tab: selectedTab)
            } else {
                Text("No open tabs")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear(perform: {
            syncTabDelegates()
            bookmarks = BIFROSTLocalStore.readBookmarks()
            showOnboarding = onboardingCompleted == false
            selectedTab?.loadInitialURLIfNeeded()
        })
        .bifrostOnChange(of: selectedTabID) {
            selectedTab?.loadInitialURLIfNeeded()
        }
        .sheet(isPresented: $showSettings) {
            BIFROSTSettingsView()
        }
        .sheet(isPresented: $showOnboarding) {
            BIFROSTOnboardingView {
                onboardingCompleted = true
                showOnboarding = false
            }
        }
        .background(BIFROSTDesign.appBackground)
    }

    private var selectedTab: BIFROSTBrowserTab? {
        tabs.first(where: { $0.id == selectedTabID }) ?? tabs.first
    }

    private func toolbar(for tab: BIFROSTBrowserTab) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                BIFROSTChromeIconButton(systemName: "chevron.left", help: "Back") {
                    tab.webView.goBack()
                }
                BIFROSTChromeIconButton(systemName: "chevron.right", help: "Forward") {
                    tab.webView.goForward()
                }
                BIFROSTChromeIconButton(systemName: "arrow.clockwise", help: "Reload") {
                    tab.webView.reload()
                }
                BIFROSTChromeIconButton(systemName: "house", help: "Home") {
                    tab.webView.load(url: homeURL)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BIFROSTDesign.clear)

                TextField(
                    "Search or enter website",
                    text: Binding(
                        get: { tab.addressText },
                        set: { tab.addressText = $0 }
                    ),
                    onCommit: { submitAddress(for: tab) }
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(BIFROSTDesign.text)
                .autocorrectionDisabled()
                .focused($addressFieldFocused)
                .onSubmit { submitAddress(for: tab) }

                Button(action: { submitAddress(for: tab) }) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(BIFROSTDesign.mutedText)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Open address")
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(BIFROSTDesign.elevatedSurface)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(BIFROSTDesign.border, lineWidth: 1)
            }
            .layoutPriority(1)

            BIFROSTJudgementStrip(model: tab.model)

            Menu {
                Button("Add current page") {
                    addCurrentBookmark(for: tab)
                }
                if bookmarks.isEmpty == false {
                    Divider()
                }
                ForEach(bookmarks) { bookmark in
                    Button(bookmark.title) {
                        tab.webView.load(url: bookmark.url)
                    }
                }
            } label: {
                Image(systemName: "bookmark")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .menuStyle(.borderlessButton)
            .help("Bookmarks")

            BIFROSTChromeIconButton(systemName: "slider.horizontal.3", help: "Policy, ledger, and blocklist") {
                showSettings = true
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(BIFROSTDesign.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BIFROSTDesign.border)
                .frame(height: 1)
        }
    }

    static func normalizedURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }

        if trimmed.contains(" ") {
            let encodedQuery = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            return URL(string: "https://duckduckgo.com/?q=\(encodedQuery)")
        }

        return URL(string: "https://\(trimmed)")
    }

    private func submitAddress(for tab: BIFROSTBrowserTab) {
        guard let finalURL = Self.normalizedURL(from: tab.addressText) else {
            return
        }
        tab.webView.load(url: finalURL)
    }

    private func selectTab(_ tab: BIFROSTBrowserTab) {
        selectedTabID = tab.id
    }

    private func openNewTab(initialURL: URL?) {
        let tab = makeTab(initialURL: initialURL)
        tabs.append(tab)
        selectedTabID = tab.id
        tab.loadInitialURLIfNeeded()
        focusAddressBar(on: tab)
    }

    @discardableResult
    private func closeSelectedTab() -> Bool {
        guard let selectedTab, tabs.count > 1 else {
            return false
        }

        closeTab(selectedTab)
        return true
    }

    private func closeTab(_ tab: BIFROSTBrowserTab) {
        guard tabs.count > 1 else {
            return
        }

        guard let closingIndex = tabs.firstIndex(where: { $0.id == tab.id }) else {
            return
        }

        tabs.remove(at: closingIndex)
        if selectedTabID == tab.id {
            let replacementIndex = min(closingIndex, tabs.count - 1)
            selectedTabID = tabs[replacementIndex].id
        }
    }

    private func openNewWindow() {
        if let uiDelegate {
            uiDelegate.browserDidRequestNewWindow(urlRequest: URLRequest(url: homeURL))
            return
        }

        openNewTab(initialURL: homeURL)
    }

    private func focusAddressBar() {
        guard let selectedTab else {
            return
        }

        focusAddressBar(on: selectedTab)
    }

    private func focusAddressBar(on tab: BIFROSTBrowserTab) {
        tab.addressText = tab.webView.wkWebView.url?.absoluteString ?? tab.addressText
        addressFieldFocused = true
        DispatchQueue.main.async {
            addressFieldFocused = true
        }
    }

    private func addCurrentBookmark(for tab: BIFROSTBrowserTab) {
        guard let url = tab.webView.wkWebView.url ?? Self.normalizedURL(from: tab.addressText) else {
            return
        }
        let rawTitle = tab.webView.wkWebView.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (rawTitle?.isEmpty == false ? rawTitle : url.host()) ?? url.absoluteString
        bookmarks = BIFROSTLocalStore.addBookmark(title: title, url: url)
    }

    private func makeTab(initialURL: URL?) -> BIFROSTBrowserTab {
        let tab = BIFROSTBrowserTab(
            initialURL: initialURL,
            configuration: configuration,
            userAgent: userAgent
        )
        tab.webView.webViewUIDelegate = self
        return tab
    }

    private func syncTabDelegates() {
        for tab in tabs {
            tab.webView.webViewUIDelegate = self
        }
    }

    private var toolbarBackground: Color {
        #if os(macOS)
        return BIFROSTDesign.surface
        #else
        return BIFROSTDesign.surface
        #endif
    }

    @ViewBuilder
    private var keyboardShortcutBridge: some View {
        #if os(macOS)
        BIFROSTKeyboardShortcutBridge(
            onNewTab: { openNewTab(initialURL: nil) },
            onNewWindow: openNewWindow,
            onFocusAddress: focusAddressBar,
            onReload: { selectedTab?.webView.reload() },
            onCloseTab: closeSelectedTab
        )
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
        #else
        EmptyView()
        #endif
    }
}

@MainActor
private final class BIFROSTBrowserTab: ObservableObject, Identifiable {
    let id = UUID()
    let model: BIFROSTBrowserModel
    var webView: WebView

    @Published var addressText: String
    @Published private(set) var title: String

    private let initialURL: URL?
    private var hasLoadedInitialURL = false
    private var urlObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?

    init(initialURL: URL?, configuration: WKWebViewConfiguration, userAgent: String?) {
        let model = BIFROSTBrowserModel()
        self.model = model
        self.initialURL = initialURL
        self.addressText = initialURL?.absoluteString ?? ""
        self.title = initialURL?.host() ?? "New Tab"
        self.webView = WebView(configuration: configuration, bifrostModel: model)

        if let userAgent {
            webView.wkWebView.customUserAgent = userAgent
        }

        observeWebView()
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false {
            return trimmed
        }

        return webView.wkWebView.url?.host() ?? "New Tab"
    }

    func loadInitialURLIfNeeded() {
        guard hasLoadedInitialURL == false, let initialURL else {
            return
        }

        hasLoadedInitialURL = true
        webView.load(url: initialURL)
    }

    private func observeWebView() {
        urlObservation = webView.wkWebView.observe(\.url, options: [.new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                if let url = webView.url {
                    self.addressText = url.absoluteString
                    if self.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.title = url.host() ?? "New Tab"
                    }
                }
            }
        }

        titleObservation = webView.wkWebView.observe(\.title, options: [.new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                let trimmedTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedTitle?.isEmpty == false {
                    self.title = trimmedTitle ?? "New Tab"
                } else if let host = webView.url?.host() {
                    self.title = host
                }
            }
        }
    }
}

private struct BIFROSTTabStrip: View {
    let tabs: [BIFROSTBrowserTab]
    let selectedTabID: BIFROSTBrowserTab.ID
    let canCloseTabs: Bool
    let selectTab: (BIFROSTBrowserTab) -> Void
    let closeTab: (BIFROSTBrowserTab) -> Void
    let newTab: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tabs) { tab in
                        BIFROSTTabButton(
                            tab: tab,
                            isSelected: tab.id == selectedTabID,
                            canClose: canCloseTabs,
                            select: { selectTab(tab) },
                            close: { closeTab(tab) }
                        )
                    }
                }
                .padding(.leading, 12)
            }

            Button(action: newTab) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(BIFROSTDesign.surface.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .contentShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .help("New tab")
            .padding(.trailing, 12)
        }
        .frame(height: 39)
        .background(tabStripBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BIFROSTDesign.border)
                .frame(height: 1)
        }
    }

    private var tabStripBackground: Color {
        BIFROSTDesign.chrome
    }
}

private struct BIFROSTTabButton: View {
    @ObservedObject var tab: BIFROSTBrowserTab
    let isSelected: Bool
    let canClose: Bool
    let select: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            if isSelected {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(BIFROSTDesign.clear)
            }
            Text(tab.displayTitle)
                .lineLimit(1)
                .truncationMode(.tail)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? BIFROSTDesign.text : BIFROSTDesign.mutedText)

            if canClose {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help("Close tab")
            }
        }
        .frame(width: 176, height: 29)
        .padding(.horizontal, 10)
        .background(isSelected ? BIFROSTDesign.surface : BIFROSTDesign.elevatedSurface.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .top) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(BIFROSTDesign.purple)
                    .frame(height: 2)
                    .padding(.horizontal, 8)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? BIFROSTDesign.border : BIFROSTDesign.subtleBorder.opacity(0.65), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .help(tab.addressText.isEmpty ? tab.displayTitle : tab.addressText)
    }
}

private struct BIFROSTActiveTabSurface: View {
    @ObservedObject private var model: BIFROSTBrowserModel
    private let tab: BIFROSTBrowserTab

    init(tab: BIFROSTBrowserTab) {
        self.tab = tab
        self.model = tab.model
    }

    var body: some View {
        VStack(spacing: 0) {
            if let intervention = model.intervention {
                BIFROSTInterventionBanner(
                    status: intervention,
                    continueOnce: intervention.state == .hold ? { model.continueHeldNavigation() } : nil
                ) {
                    model.dismissIntervention()
                }
            }

            tab.webView
                .id(tab.id)
        }
        .background(BIFROSTDesign.surface)
    }
}

private struct BIFROSTChromeIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BIFROSTDesign.mutedText)
                .frame(width: 30, height: 30)
                .background(BIFROSTDesign.surface.opacity(0.001))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private extension View {
    @ViewBuilder
    func bifrostOnChange<Value: Equatable>(of value: Value, perform action: @escaping () -> Void) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            self.onChange(of: value) {
                action()
            }
        } else {
            self.onChange(of: value) { _ in
                action()
            }
        }
    }
}

#if os(macOS)
private struct BIFROSTKeyboardShortcutBridge: NSViewRepresentable {
    let onNewTab: () -> Void
    let onNewWindow: () -> Void
    let onFocusAddress: () -> Void
    let onReload: () -> Void
    let onCloseTab: () -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.hostView = view
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onNewTab = onNewTab
        context.coordinator.onNewWindow = onNewWindow
        context.coordinator.onFocusAddress = onFocusAddress
        context.coordinator.onReload = onReload
        context.coordinator.onCloseTab = onCloseTab
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onNewTab: onNewTab,
            onNewWindow: onNewWindow,
            onFocusAddress: onFocusAddress,
            onReload: onReload,
            onCloseTab: onCloseTab
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var onNewTab: () -> Void
        var onNewWindow: () -> Void
        var onFocusAddress: () -> Void
        var onReload: () -> Void
        var onCloseTab: () -> Bool
        weak var hostView: NSView?
        private var monitor: Any?

        init(onNewTab: @escaping () -> Void,
             onNewWindow: @escaping () -> Void,
             onFocusAddress: @escaping () -> Void,
             onReload: @escaping () -> Void,
             onCloseTab: @escaping () -> Bool) {
            self.onNewTab = onNewTab
            self.onNewWindow = onNewWindow
            self.onFocusAddress = onFocusAddress
            self.onReload = onReload
            self.onCloseTab = onCloseTab
        }

        deinit {
            removeMonitor()
        }

        func installMonitor() {
            guard monitor == nil else {
                return
            }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      self.hostView?.window?.isKeyWindow == true,
                      event.modifierFlags.contains(.command) else {
                    return event
                }

                switch event.charactersIgnoringModifiers?.lowercased() {
                case "t":
                    self.onNewTab()
                    return nil
                case "n":
                    self.onNewWindow()
                    return nil
                case "l":
                    self.onFocusAddress()
                    return nil
                case "r":
                    self.onReload()
                    return nil
                case "w":
                    return self.onCloseTab() ? nil : event
                default:
                    return event
                }
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
    }
}
#endif

private struct BIFROSTJudgementStrip: View {
    @ObservedObject var model: BIFROSTBrowserModel

    var body: some View {
        HStack(spacing: 8) {
            if let answerVerdict = model.answerVerdict {
                BIFROSTAnswerVerdictPill(verdict: answerVerdict)
                    .fixedSize(horizontal: true, vertical: false)
            } else if model.answerScanning {
                BIFROSTAnswerScanPill()
                    .fixedSize(horizontal: true, vertical: false)
            }

            BIFROSTStatusPill(status: model.status)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

private struct BIFROSTAnswerScanPill: View {
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "rays")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .opacity(pulsing ? 0.35 : 1.0)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulsing)
            Text("ANSWER")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("SCANNING")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.secondary.opacity(0.07))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        }
        .onAppear { pulsing = true }
        .help("BIFROST is reading the answer on this page")
        .accessibilityLabel("BIFROST answer scan in progress")
    }
}

private struct BIFROSTAnswerVerdictPill: View {
    let verdict: BIFROSTAnswerVerdict
    @State private var showEvidence = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
            Text("ANSWER")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color.opacity(0.82))
            Text(verdict.label)
                .lineLimit(1)
                .truncationMode(.tail)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: 300)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.11))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(color.opacity(0.22), lineWidth: 1)
        }
        .contentShape(Capsule())
        .onTapGesture { showEvidence.toggle() }
        .popover(isPresented: $showEvidence, arrowEdge: .bottom) {
            BIFROSTEvidenceCard(
                title: verdict.headline,
                tint: color,
                rows: [
                    ("CATEGORY", verdict.category),
                    ("SCAN RESULT", verdict.label),
                    ("OBSERVATION", verdict.detail),
                    ("NEXT STEP", verdict.action),
                ],
                digestLabel: "INPUT DIGEST",
                digest: verdict.inputHash,
                footer: "Local text-pattern scan only. It does not verify claims or sources. Navigation receipts are separate in Settings → Ledger."
            )
        }
        .help("\(verdict.headline)\n\(verdict.detail)\n\(verdict.action)\nClick for evidence")
        .accessibilityLabel("BIFROST answer scan result \(verdict.label)")
        .accessibilityHint("\(verdict.headline). Click to view evidence.")
    }

    private var color: Color {
        BIFROSTDesign.answerColor(verdict.display)
    }

    private var iconName: String {
        switch verdict.display {
        case .noScanFlag:
            return "magnifyingglass.circle"
        case .review:
            return "exclamationmark.triangle"
        }
    }
}

/// Small read-only evidence drawer shown from a status pill.
private struct BIFROSTEvidenceCard: View {
    let title: String
    let tint: Color
    let rows: [(String, String)]
    let digestLabel: String
    let digest: String
    let footer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "doc.badge.clock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            Divider()

            ForEach(rows.filter { !$0.1.isEmpty }, id: \.0) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.0)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(row.1)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                Text(digestLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(digest)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(tint)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(footer)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
    }
}

private struct BIFROSTStatusPill: View {
    let status: BIFROSTBrowserStatus
    @State private var showReceipt = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
            Text("BIFROST")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color.opacity(0.82))
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(status.state == .idle ? 0.06 : 0.10))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(color.opacity(status.state == .idle ? 0.18 : 0.28), lineWidth: 1)
        }
        .contentShape(Capsule())
        .onTapGesture {
            if status.state != .idle { showReceipt.toggle() }
        }
        .popover(isPresented: $showReceipt, arrowEdge: .bottom) {
            BIFROSTEvidenceCard(
                title: "Page judgement · \(status.headline)",
                tint: color,
                rows: [
                    ("VERDICT", label),
                    ("REASON", status.reason),
                    ("RULE", status.policyId ?? ""),
                    ("CONFIDENCE", status.confidence.map { String(format: "%.2f", $0) } ?? ""),
                ],
                digestLabel: "LUNA RECEIPT",
                digest: status.receiptHash ?? "(no row written for this state)",
                footer: "Verify the navigation chain in Settings → Ledger."
            )
        }
        .help(status.state == .idle ? "\(label)\n\(status.reason)" : "\(label)\n\(status.reason)\nClick for receipt")
        .accessibilityLabel("BIFROST page judgement \(label)")
        .accessibilityHint(status.state == .idle ? status.reason : "\(status.reason). Click to view the receipt.")
    }

    private var label: String {
        switch status.state {
        case .idle:
            return "READY"
        case .noObjection:
            return "CLEAR"
        case .abstain:
            return "QUIET"
        case .hold:
            return "HOLD"
        case .refuse:
            return "REFUSE"
        }
    }

    private var color: Color {
        BIFROSTDesign.verdictColor(status.state)
    }

    private var iconName: String {
        switch status.state {
        case .idle:
            return "shield"
        case .noObjection, .abstain:
            return "checkmark.shield"
        case .hold:
            return "exclamationmark.shield"
        case .refuse:
            return "xmark.shield"
        }
    }
}

private struct BIFROSTInterventionBanner: View {
    let status: BIFROSTBrowserStatus
    let continueOnce: (() -> Void)?
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: status.state == .refuse ? "shield.slash" : "shield.lefthalf.filled")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)

            Text(status.headline)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.12))
                .clipShape(Capsule())

            Text(status.reason)
                .lineLimit(1)
                .truncationMode(.tail)
                .font(.system(size: 12))
                .foregroundStyle(BIFROSTDesign.text)

            if let receiptHash = status.receiptHash {
                Text(receiptHash.prefix(16))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(BIFROSTDesign.faintText)
            }

            Spacer()

            if let continueOnce {
                Button("Continue once", action: continueOnce)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Button("Dismiss", action: dismiss)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(color.opacity(0.075))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(color.opacity(0.18))
                .frame(height: 1)
        }
    }

    private var color: Color {
        status.state == .refuse
            ? BIFROSTDesign.refuse
            : BIFROSTDesign.hold
    }
}

//MARK: - WebViewUIDelegate

extension BareBonesBrowserView: WebViewUIDelegate {

    public func webDidViewRequestNewWindow(with webView: WKWebView,
                                 createWebViewWith configuration: WKWebViewConfiguration,
                                 for navigationAction: WKNavigationAction,
                                 windowFeatures: WKWindowFeatures) -> WKWebView? {

        let tab = makeTab(initialURL: nil)
        tabs.append(tab)
        selectedTabID = tab.id
        return tab.webView.wkWebView
    }
}

#Preview {
    let url = URL(string: "https://duckduckgo.com")!
    return BareBonesBrowserView(initialURL: url,homeURL: url, uiDelegate: nil, configuration: WKWebViewConfiguration())
}
