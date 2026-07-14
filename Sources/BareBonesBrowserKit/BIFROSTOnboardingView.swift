//
//  BIFROSTOnboardingView.swift
//  BIFROST
//
//  Created by JourdanLabs on 06/07/2026.
//  Portions derived from DuckDuckGo BareBonesBrowser under Apache-2.0.
//

import SwiftUI

private enum BIFROSTOnboardingDesign {
    static let background = Color(red: 0.984, green: 0.985, blue: 0.988)
    static let surface = Color.white
    static let border = Color(red: 0.882, green: 0.890, blue: 0.912)
    static let text = Color(red: 0.125, green: 0.114, blue: 0.145)
    static let mutedText = Color(red: 0.430, green: 0.410, blue: 0.485)
    static let purple = Color(red: 0.419, green: 0.129, blue: 0.659)
}

struct BIFROSTOnboardingView: View {
    let finish: () -> Void
    @State private var index = 0

    private let cards = [
        Card(
            icon: "smallcircle.filled.circle",
            title: "Browse first.",
            body: "BIFROST stays quiet until a navigation rule or local answer pattern needs attention."
        ),
        Card(
            icon: "rectangle.and.hand.point.up.left",
            title: "Visible findings.",
            body: "The toolbar shows navigation state and, on supported LLM sites, a local answer-scan result."
        ),
        Card(
            icon: "link",
            title: "Receipts stay local.",
            body: "The opt-in inspector verifies or exports the LUNA chain from this device."
        )
    ]

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 18)

            Image(systemName: cards[index].icon)
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(BIFROSTOnboardingDesign.purple)
                .frame(width: 92, height: 92)
                .background(BIFROSTOnboardingDesign.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(BIFROSTOnboardingDesign.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))

            VStack(spacing: 10) {
                Text(cards[index].title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(BIFROSTOnboardingDesign.text)
                    .multilineTextAlignment(.center)
                Text(cards[index].body)
                    .font(.system(size: 14))
                    .foregroundStyle(BIFROSTOnboardingDesign.mutedText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .frame(maxWidth: 470)

            HStack(spacing: 8) {
                ForEach(cards.indices, id: \.self) { cardIndex in
                    Circle()
                        .fill(cardIndex == index ? BIFROSTOnboardingDesign.purple : BIFROSTOnboardingDesign.border)
                        .frame(width: 7, height: 7)
                }
            }

            HStack(spacing: 12) {
                Button("Skip", action: finish)
                    .buttonStyle(.bordered)
                Button(index == cards.count - 1 ? "Done" : "Next") {
                    if index == cards.count - 1 {
                        finish()
                    } else {
                        index += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(BIFROSTOnboardingDesign.purple)
            }

            Spacer(minLength: 18)
        }
        .padding(30)
        .background(BIFROSTOnboardingDesign.background)
        .frame(minWidth: 500, idealWidth: 560, minHeight: 420)
    }
}

private struct Card {
    let icon: String
    let title: String
    let body: String
}
