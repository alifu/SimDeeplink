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
    @State private var deeplinkDelay: Double = 0
    @State private var delayTask: Task<Void, Never>? = nil
    @State private var output = ""
    @State private var selectedTargetSimulator: Simulator? = nil
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
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Simulator")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    HStack {
                        
                        VStack {
                            HStack {
                                Text("Enable Simulator Section")
                                
                                Spacer()
                                
                                Toggle("", isOn: $isSimulatorSectionEnabled)
                                    .foregroundStyle(.white)
                                    .toggleStyle(.switch)
                                
                            }
                            if isSimulatorSectionEnabled {
                                Divider()
                                SimulatorSectionView(watcher: watcher)
                                    .padding(.vertical, 4)
                            }
                        }
                        
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            .background(Color.black.opacity(0.2))
                            .cornerRadius(8)
                    )
                }
                .padding(.top, 8)
                .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Deeplink")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    HStack {
                        VStack {
                            HStack {
                                TextField("Enter Deeplink URL", text: $deeplinkURL)
                                    .foregroundStyle(.white)
                                
                                Button(action: {
                                    deeplinkURL = ""
                                    output = ""
                                }) {
                                    Image(systemName: "eraser.fill")
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(.top, 4)
                            
                            HStack {
                                Text("Simulator Target")
                                    .foregroundStyle(.white)
                                
                                BootedSimulatorView(watcher: watcher, selectedSimulator: $selectedTargetSimulator)
                                    .padding(.vertical, 4)
                                
                                Button(action: {
                                    watcher.refreshBootedSimulators()
                                }) {
                                    Image(systemName: "arrow.clockwise")
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(.top, 4)
                            
                            HStack {
                                Text("Delay")
                                    .foregroundStyle(.white)
                                
                                HStack(spacing: 0) {
                                    TextField("in Seconds", value: $deeplinkDelay, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 50)
                                        .multilineTextAlignment(.center)
                                        .padding(0)
                                    
                                    Stepper("", value: $deeplinkDelay, in: 0...10, step: 1.0)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    // Cancel any previous pending task
                                    delayTask?.cancel()
                                    output = "Loading..."
                                    
                                    guard deeplinkURL.isLink else {
                                        output = "Invalid Deeplink URL"
                                        return
                                    }
                                    
                                    // Create a new cancelable task
                                    delayTask = Task {
                                        if deeplinkDelay > 0 {
                                            // Countdown loop
                                            for i in stride(from: Int(deeplinkDelay), through: 1, by: -1) {
                                                guard !Task.isCancelled else { return }
                                                await MainActor.run {
                                                    output = "Executing in \(i)s..."
                                                }
                                                try? await Task.sleep(nanoseconds: 1_000_000_000) // wait 1s
                                            }
                                        }
                                        
                                        // Check again in case user canceled mid-countdown
                                        guard !Task.isCancelled else { return }
                                        
                                        // Run the deeplink
                                        await MainActor.run {
                                            output = "Running deeplink..."
                                        }
                                        
                                        let result: String
                                        if let selectedTargetSimulator {
                                            result = watcher.runDeeplink(url: deeplinkURL, target: selectedTargetSimulator.udid)
                                        } else {
                                            result = watcher.runDeeplink(url: deeplinkURL)
                                        }
                                        
                                        await MainActor.run {
                                            output = result
                                        }
                                    }
                                }) {
                                    Text("Execute Deeplink")
                                        .foregroundStyle(.white)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            .background(Color.black.opacity(0.2))
                            .cornerRadius(8)
                    )
                }
                .padding(.top, 8)
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
        .frame(width: 500)
    }
}
