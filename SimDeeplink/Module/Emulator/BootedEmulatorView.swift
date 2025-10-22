//
//  BootedEmulatorView.swift
//  SimDeeplink
//
//  Created by Alif on 21/10/25.
//

import SwiftUI

struct BootedEmulatorView: View {
    @ObservedObject var watcher: EmulatorWatcher
    @Binding var selectedEmulator: Emulator?

    var body: some View {
        AndroidEmulatorComboBox(
            selectedEmulator: Binding(
                get: { selectedEmulator ?? nil },
                set: { newValue in
                    selectedEmulator = watcher.bootedEmulators.first { $0 == newValue }
                }
            ),
            items: $watcher.bootedEmulators
        )
    }
}
