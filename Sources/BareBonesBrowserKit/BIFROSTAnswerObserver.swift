//
//  BIFROSTAnswerObserver.swift
//  BIFROST
//
//  Created by JourdanLabs on 06/07/2026.
//  Portions derived from DuckDuckGo BareBonesBrowser under Apache-2.0.
//

import Foundation
import WebKit

final class BIFROSTAnswerObserver: NSObject, WKScriptMessageHandler {
    private weak var model: BIFROSTBrowserModel?
    private let verifier = BIFROSTAnswerVerifier()
    private var lastInputHash: String?

    init(model: BIFROSTBrowserModel) {
        self.model = model
    }

    func reset() {
        lastInputHash = nil
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard
            message.frameInfo.isMainFrame,
            let payload = message.body as? [String: Any]
        else {
            return
        }

        if payload["phase"] as? String == "scan" {
            Task { @MainActor [weak self] in
                self?.model?.beginAnswerScan()
            }
            return
        }

        guard
            let text = payload["text"] as? String,
            let verdict = verifier.evaluate(text),
            verdict.inputHash != lastInputHash
        else {
            return
        }

        lastInputHash = verdict.inputHash
        Task { @MainActor [weak self] in
            self?.model?.publishAnswerVerdict(verdict)
        }
    }
}

enum BIFROSTAnswerObserverScript {
    static let source = #"""
    (() => {
      if (window.__bifrostAnswerObserverInstalled) return;
      window.__bifrostAnswerObserverInstalled = true;

      const host = location.hostname.toLowerCase();

      function visiblePageText() {
        return ((document.body && (document.body.innerText || document.body.textContent)) || '')
          .replace(/\s+/g, ' ')
          .toLowerCase();
      }

      function isLikelyLLMSurface() {
        const pageText = visiblePageText();
        const isGoogleGeminiSurface =
          /(^|\.)google\.com$/.test(host) &&
          (
            pageText.includes('ask gemini') ||
            pageText.includes('gemini can make mistakes') ||
            pageText.includes('about gemini') ||
            pageText.includes('get gemini app')
          );

        return (
        /(^|\.)chatgpt\.com$/.test(host) ||
        /(^|\.)claude\.ai$/.test(host) ||
        /(^|\.)gemini\.google\.com$/.test(host) ||
        isGoogleGeminiSurface ||
        /(^|\.)perplexity\.ai$/.test(host) ||
        /(^|\.)poe\.com$/.test(host) ||
        /(^|\.)copilot\.microsoft\.com$/.test(host) ||
        /(^|\.)grok\.com$/.test(host)
        );
      }

      const selectors = [
        '[data-bifrost-answer]',
        'message-content',
        '[data-message-author-role="assistant"]',
        '[data-testid*="response"]',
        '[data-test-id*="response"]',
        '[data-testid*="conversation-turn"] [class*="markdown"]',
        '[data-testid*="bot-message"]',
        '.markdown.prose',
        '.prose',
        '[class*="model-response"]',
        '[class*="response-container"]',
        '[class*="assistant"]',
        '[class*="response"]'
      ];

      function candidateNodes() {
        const explicit = document.querySelectorAll('[data-bifrost-answer]');
        if (!isLikelyLLMSurface() && explicit.length === 0) return [];
        return Array.from(document.querySelectorAll(selectors.join(',')))
          .filter((node) => {
            const rect = node.getBoundingClientRect();
            const text = (node.innerText || node.textContent || '').trim();
            const lower = text.toLowerCase();
            const looksLikeChromeOnly =
              lower.includes('sign in') &&
              lower.includes('about gemini') &&
              lower.includes('get gemini app') &&
              text.length < 180;
            return rect.width > 80 &&
              rect.height > 20 &&
              text.length >= 80 &&
              !looksLikeChromeOnly;
          });
      }

      let lastText = '';
      let timer = null;
      let scanPending = false;

      function signalScan() {
        if (scanPending) return;
        const nodes = candidateNodes();
        if (!nodes.length) return;
        const latest = nodes[nodes.length - 1];
        const text = (latest.innerText || latest.textContent || '')
          .replace(/\s+/g, ' ')
          .trim();
        if (text.length < 80 || text === lastText) return;
        scanPending = true;
        window.webkit?.messageHandlers?.bifrostAnswer?.postMessage({ phase: 'scan' });
      }

      function collect() {
        timer = null;
        const nodes = candidateNodes();
        if (!nodes.length) {
          scanPending = false;
          return;
        }
        const latest = nodes[nodes.length - 1];
        const text = (latest.innerText || latest.textContent || '')
          .replace(/\s+/g, ' ')
          .trim();
        if (text.length < 80 || text === lastText) {
          scanPending = false;
          return;
        }
        lastText = text;
        scanPending = false;
        window.webkit?.messageHandlers?.bifrostAnswer?.postMessage({
          text,
          href: location.href,
          title: document.title
        });
      }

      function schedule() {
        if (timer) return;
        signalScan();
        timer = setTimeout(collect, 700);
      }

      new MutationObserver(schedule).observe(document.documentElement, {
        childList: true,
        subtree: true,
        characterData: true
      });
      setInterval(collect, 3000);
      schedule();
    })();
    """#

    static let collectOnceSource = #"""
    (() => {
      const host = location.hostname.toLowerCase();
      const pageText = ((document.body && (document.body.innerText || document.body.textContent)) || '')
        .replace(/\s+/g, ' ')
        .toLowerCase();
      const explicit = document.querySelectorAll('[data-bifrost-answer]');
      const isGoogleGeminiSurface =
        /(^|\.)google\.com$/.test(host) &&
        (
          pageText.includes('ask gemini') ||
          pageText.includes('gemini can make mistakes') ||
          pageText.includes('about gemini') ||
          pageText.includes('get gemini app')
        );
      const isLikelyLLMSurface =
        /(^|\.)chatgpt\.com$/.test(host) ||
        /(^|\.)claude\.ai$/.test(host) ||
        /(^|\.)gemini\.google\.com$/.test(host) ||
        isGoogleGeminiSurface ||
        /(^|\.)perplexity\.ai$/.test(host) ||
        /(^|\.)poe\.com$/.test(host) ||
        /(^|\.)copilot\.microsoft\.com$/.test(host) ||
        /(^|\.)grok\.com$/.test(host);

      if (!isLikelyLLMSurface && explicit.length === 0) return null;

      const selectors = [
        '[data-bifrost-answer]',
        'message-content',
        '[data-message-author-role="assistant"]',
        '[data-testid*="response"]',
        '[data-test-id*="response"]',
        '[data-testid*="conversation-turn"] [class*="markdown"]',
        '[data-testid*="bot-message"]',
        '.markdown.prose',
        '.prose',
        '[class*="model-response"]',
        '[class*="response-container"]',
        '[class*="assistant"]',
        '[class*="response"]'
      ];

      const nodes = Array.from(document.querySelectorAll(selectors.join(',')))
        .filter((node) => {
          const rect = node.getBoundingClientRect();
          const text = (node.innerText || node.textContent || '').trim();
          return rect.width > 80 &&
            rect.height > 20 &&
            text.length >= 80;
        });

      if (!nodes.length) return null;
      return (nodes[nodes.length - 1].innerText || nodes[nodes.length - 1].textContent || '')
        .replace(/\s+/g, ' ')
        .trim();
    })();
    """#
}
