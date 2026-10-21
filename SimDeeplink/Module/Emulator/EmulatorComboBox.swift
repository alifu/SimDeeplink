//
//  EmulatorComboBox.swift
//  SimDeeplink
//
//  Created by Alif on 21/10/25.
//

import AppKit
import SwiftUI

struct Emulator: Identifiable, Equatable {
    let name: String   // AVD name
    let serial: String // e.g. emulator-5554, empty while the emulator is stopped
    let isOnline: Bool

    /// Stable across refreshes, so a selection survives the list being re-read.
    var id: String { serial.isEmpty ? "avd:\(name)" : serial }

    var title: String {
        let status = isOnline ? "🟢" : "⚪️"
        return serial.isEmpty ? "\(status) \(name)" : "\(status) \(name) (\(serial))"
    }

    init(name: String, serial: String, isOnline: Bool) {
        self.name = name
        self.serial = serial
        self.isOnline = isOnline
    }

    /// An Android entry from `AdbService`: its udid is the adb serial, or `avd:<name>` while stopped.
    init(_ device: Simulator) {
        self.init(
            name: device.name,
            serial: device.udid.hasPrefix(AdbService.avdPrefix) ? "" : device.udid,
            isOnline: device.isBooted
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
           let index = items.firstIndex(where: { $0.id == selected.id }) {
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
            return emulator.title
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
