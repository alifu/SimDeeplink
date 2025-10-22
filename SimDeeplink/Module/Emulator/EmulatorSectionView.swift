//
//  EmulatorSectionView.swift
//  SimDeeplink
//
//  Created by Alif on 22/10/25.
//

import SwiftUI

struct EmulatorSectionView: View {
    @ObservedObject var watcher: EmulatorWatcher
    @State private var hasStarted = false
    @State private var selectedEmulator: Emulator?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Emulator").font(.headline)
            
            Button(action: {
                watcher.fetchOfflineEmulators()
            }) {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(.white)
            }
            
            AndroidEmulatorComboBox(
                selectedEmulator: Binding(
                    get: { selectedEmulator ?? nil },
                    set: { newValue in
                        selectedEmulator = watcher.emulators.first { $0 == newValue }
                    }
                ),
                items: $watcher.emulators
            )
            
            Button(action: {
                DispatchQueue.global().async {
                    if let name = selectedEmulator?.name {
                        _ = watcher.bootEmulator(avdName: name)
                    }
                }
            }) {
                Image(systemName: "play.fill")
                    .foregroundStyle(.green)
            }
            .disabled(selectedEmulator == nil)
        }
    }
}
