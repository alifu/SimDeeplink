//
//  DisabledOverlay.swift
//  SimDeeplink
//
//  Created by Alif on 27/10/25.
//

import SwiftUI

struct DisabledOverlay: View {
    var toolChecker: SystemToolChecker
    var isVisible: Bool
    var message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.yellow)
                Text(message)
                    .multilineTextAlignment(.center)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding()
                Button {
                    toolChecker.checkTools()
                } label: {
                    Text("Reload")
                }
            }
            .padding()
            .background(Color.black.opacity(0.6))
            .cornerRadius(16)
        }
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: isVisible)
        .allowsHitTesting(isVisible) // prevents interaction when disabled
    }
}

