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

struct OfflineEmulator: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let device: String
    let path: String
    let apiLevel: String
    let skin: String
    let sdcard: String
    let snapshot: String
    
    func toEmulator() -> Emulator {
        Emulator(
            name: self.name,
            serial: "",
            isOnline: false
        )
    }
}

struct AndroidEmulatorComboBox: NSViewRepresentable {
    @Binding var selectedEmulator: Emulator?
    @Binding var items: [Emulator]
    
    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.usesDataSource = true
        comboBox.dataSource = context.coordinator
        comboBox.delegate = context.coordinator
        comboBox.completes = true
        comboBox.isEditable = true
        comboBox.hasVerticalScroller = true
        return comboBox
    }
    
    func updateNSView(_ nsView: NSComboBox, context: Context) {
        context.coordinator.allItems = items
        context.coordinator.filteredItems = items
        nsView.reloadData()
        
        // restore selected item
        if let selected = selectedEmulator,
           let index = items.firstIndex(where: { $0.serial == selected.serial }) {
            nsView.selectItem(at: index)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, NSComboBoxDelegate, NSComboBoxDataSource {
        var parent: AndroidEmulatorComboBox
        var allItems: [Emulator] = []
        var filteredItems: [Emulator] = []
        
        init(parent: AndroidEmulatorComboBox) {
            self.parent = parent
        }
        
        // MARK: - Data Source
        func numberOfItems(in comboBox: NSComboBox) -> Int {
            filteredItems.count
        }
        
        func comboBox(_ comboBox: NSComboBox, objectValueForItemAt index: Int) -> Any? {
            guard index >= 0 && index < filteredItems.count else { return nil }
            let emulator = filteredItems[index]
            let status = emulator.isOnline ? "🟢" : "⚪️"
            return "\(status) \(emulator.name) (\(emulator.serial))"
        }
        
        // MARK: - Delegate
        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            let index = comboBox.indexOfSelectedItem
            guard index >= 0 && index < filteredItems.count else { return }
            let selected = filteredItems[index]
            
            DispatchQueue.main.async {
                self.parent.selectedEmulator = selected
            }
        }
        
        func controlTextDidChange(_ obj: Notification) {
            guard let comboBox = obj.object as? NSComboBox else { return }
            let query = comboBox.stringValue.lowercased()
            
            if query.isEmpty {
                filteredItems = allItems
            } else {
                filteredItems = allItems.filter {
                    $0.name.lowercased().contains(query) ||
                    $0.serial.lowercased().contains(query)
                }
            }
            comboBox.reloadData()
        }
    }
}
