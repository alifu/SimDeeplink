//
//  EmulatorComboBox.swift
//  SimDeeplink
//
//  Created by Alif on 21/10/25.
//

import AppKit
import SwiftUI

struct Emulator: Identifiable, Equatable {
    let id = UUID()
    let name: String   // Emulator name or device ID
    let serial: String // e.g. emulator-5554
    let isOnline: Bool
}

struct AndroidEmulatorComboBox: NSViewRepresentable {
    @Binding var selectedEmulator: Emulator?
    @Binding var items: [Emulator]
    
    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.usesDataSource = false
        comboBox.delegate = context.coordinator
        comboBox.isEditable = false
        comboBox.hasVerticalScroller = true
        return comboBox
    }
    
    func updateNSView(_ nsView: NSComboBox, context: Context) {
        nsView.removeAllItems()
        nsView.addItems(withObjectValues: items.map { emulator in
            let status = emulator.isOnline ? "🟢" : "⚪️"
            return "\(status) \(emulator.name) (\(emulator.serial))"
        })
        
        if let selected = selectedEmulator,
           let index = items.firstIndex(where: { $0.serial == selected.serial }) {
            nsView.selectItem(at: index)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, NSComboBoxDelegate {
        var parent: AndroidEmulatorComboBox
        
        init(parent: AndroidEmulatorComboBox) {
            self.parent = parent
        }
        
        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            let index = comboBox.indexOfSelectedItem
            guard index >= 0 && index < parent.items.count else { return }
            let selected = parent.items[index]
            
            DispatchQueue.main.async {
                self.parent.selectedEmulator = selected
            }
        }
    }
}
