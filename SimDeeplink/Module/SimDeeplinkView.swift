//
//  SimDeeplinkVIew.swift
//  SimDeeplink
//
//  Created by Alif on 16/10/25.
//

import SwiftUI

struct SimDeeplinkView: View {
    @State private var output = ""
    @State private var outputSimulator = ""
    @State private var outputEmulator = ""
    @State private var selectedTab: Int = 0
    var quitAction: () -> Void
    @StateObject private var toolChecker = SystemToolChecker()
    @FocusState private var isFocused: Bool
    
    var body: some View {
        ZStack(alignment: .top) {
            ColorUtils.oceanDepth
                .ignoresSafeArea(edges: .all)
            
            VStack(alignment: .leading) {
                ZStack {
                    ColorUtils.deepMidnightBlue
                    Text("SimDeeplink")
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing) {
                            Button(action: {
                                quitAction()
                            }) {
                                Text("Exit")
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .frame(height: 40)
                .padding(0)
                
                TabView(selection: $selectedTab) {
                    
                    ZStack {
                        SimulatorView(isActive: $toolChecker.isXcrunAvailable) { message in
                            outputSimulator = message
                            output = message
                        }
                        .blur(radius: toolChecker.isXcrunAvailable ? 0 : 3)
                        .allowsHitTesting(toolChecker.isXcrunAvailable)
                        .overlay {
                            DisabledOverlay(
                                toolChecker: toolChecker,
                                isVisible: !toolChecker.isXcrunAvailable,
                                message: "xcrun is not available.\nPlease install Xcode Command Line Tools."
                            )
                        }
                    }
                    .tabItem {
                        Text("Apple Simulator")
                    }
                    .tag(0)
                    
                    ZStack {
                        EmulatorView(isActive: $toolChecker.isAdbAvailable) { message in
                            outputEmulator = message
                            output = message
                        }
                        .blur(radius: toolChecker.isAdbAvailable ? 0 : 3)
                        .allowsHitTesting(toolChecker.isAdbAvailable)
                        .overlay {
                            DisabledOverlay(
                                toolChecker: toolChecker,
                                isVisible: !toolChecker.isAdbAvailable,
                                message: "ADB is not available.\nPlease install Android Platform Tools."
                            )
                        }
                    }
                    .tabItem {
                        Text("Android Emulator")
                    }
                    .tag(1)
                }
                .padding(.horizontal, 8)
                .onChange(of: selectedTab) { _, newValue in
                    if newValue == 1 {
                        output = outputEmulator
                    } else {
                        output = outputSimulator
                    }
                }
                
                ZStack {
                    ColorUtils.steelSky
                    
                    ScrollView {
                        Text(output)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(.white)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                    }
                    .background(ColorUtils.steelSky)
                }
                .padding(0)
            }
        }
        .padding(0)
        .frame(maxWidth: .infinity)
        .onAppear {
            toolChecker.checkTools()
        }
    }
}
