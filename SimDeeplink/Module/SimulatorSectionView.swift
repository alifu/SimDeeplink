//
//  SimulatorSectionView.swift
//  SimDeeplink
//
//  Created by Alif on 17/10/25.
//

import SwiftUI

struct SimulatorSectionView: View {
    @ObservedObject var watcher: SimulatorWatcher
    @State private var hasStarted = false
    @State private var selectedSimulator: Simulator?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Simulator").font(.headline)
            
            SimComboBox(
                selectedSimulator: Binding(
                    get: { selectedSimulator ?? nil },
                    set: { newValue in
                        selectedSimulator = watcher.simulators.first { $0 == newValue }
                    }
                ),
                items: $watcher.simulators
            )
            
            Button(action: {
                watcher.bootSimulator(udid: selectedSimulator!.udid) {
                    watcher.refreshSimulators()
                }
            }) {
                Image(systemName: "play.fill")
                    .foregroundStyle(.green)
            }
            .disabled(selectedSimulator == nil)
        }
        .onChange(of: watcher.isEnabled) { oldValue, newValue in
            if newValue {
                watcher.startWatching()
            } else {
                watcher.stopWatching()
            }
        }
        .onAppear {
            if !hasStarted {
                watcher.startWatching()
                hasStarted = true
            }
        }
        .onDisappear {
            watcher.stopWatching()
        }
    }
}
