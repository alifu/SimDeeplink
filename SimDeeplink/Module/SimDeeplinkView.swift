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
                    SimulatorView { message in
                        outputSimulator = message
                        output = message
                    }
                    .tabItem {
                        Text("Apple Simulator")
                    }
                    .tag(0)
                    
                    EmulatorView { message in
                        outputEmulator = message
                        output = message
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
        .frame(maxWidth: .infinity)
    }
}
