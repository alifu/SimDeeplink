//
//  SimDeeplinkVIew.swift
//  SimDeeplink
//
//  Created by Alif on 16/10/25.
//

import SwiftUI

struct SimDeeplinkView: View {
    @StateObject private var watcher = SimulatorWatcher()
    @State private var isSimulatorSectionEnabled = false
    @State private var deeplinkURL: String = ""
    @State private var output = ""
    
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
                                NSApp.terminate(nil)
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
                
                VStack(alignment: .leading) {
                    Toggle("Enable Simulator Section", isOn: $isSimulatorSectionEnabled)
                        .foregroundStyle(.white)
                    
                    if isSimulatorSectionEnabled {
                        SimulatorSectionView(watcher: watcher)
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal)
                
                HStack {
                    Button(action: {
                        deeplinkURL = ""
                        output = ""
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.white)
                    }
                    
                    TextField("Enter Deeplink URL", text: $deeplinkURL)
                        .foregroundStyle(.white)
                    
                    Button(action: {
                        output = "Loading..."
                        if deeplinkURL.isLink {
                            output = watcher.runDeeplink(url: deeplinkURL)
                        } else {
                            output = "Invalid Deeplink URL"
                        }
                    }) {
                        Text("Execute Deeplink")
                            .foregroundStyle(.white)
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 8)
                .padding(.horizontal)
                
                ZStack {
                    ColorUtils.steelSky
                    
                    TextEditor(text: $output)
                        .frame(maxWidth: .infinity)
                        .scrollContentBackground(.hidden)
                        .background(ColorUtils.steelSky)
                        .foregroundStyle(.white)
                        .disabled(true)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                }
                .padding(0)
            }
        }
        .padding(0)
    }
}

#Preview {
    SimDeeplinkView()
}
