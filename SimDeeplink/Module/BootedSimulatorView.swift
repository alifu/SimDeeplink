//
//  BootedSimulatorView.swift
//  SimDeeplink
//
//  Created by Alif on 20/10/25.
//

import SwiftUI

struct BootedSimulatorView: View {
    @ObservedObject var watcher: SimulatorWatcher
    @Binding var selectedSimulator: Simulator?

    var body: some View {
        SimComboBox(
            selectedSimulator: Binding(
                get: { selectedSimulator ?? nil },
                set: { newValue in
                    selectedSimulator = watcher.bootedSimulators.first { $0 == newValue }
                }
            ),
            items: $watcher.bootedSimulators
        )
    }
}
