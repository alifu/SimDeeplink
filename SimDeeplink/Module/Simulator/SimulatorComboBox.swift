//
//  SimulatorComboBox.swift
//  SimDeeplink
//
//  Created by Alif on 17/10/25.
//

import SwiftUI
import AppKit

struct SimulatorComboBox: NSViewRepresentable {
    @Binding var selectedSimulator: Simulator?
    @Binding var items: [Simulator]
    
    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.usesDataSource = true
        comboBox.delegate = context.coordinator
        comboBox.dataSource = context.coordinator
        comboBox.completes = true
        comboBox.isEditable = true
        comboBox.hasVerticalScroller = true
        return comboBox
    }
    
    func updateNSView(_ nsView: NSComboBox, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        // SwiftUI updates this view whenever any field of the screen changes; only a new list may reset the search.
        if coordinator.allItems != items {
            coordinator.allItems = items
            coordinator.filteredItems = items
            nsView.reloadData()
        }
        
        // restore selected item, but never overwrite what the user is typing
        guard nsView.currentEditor() == nil,
              let selected = selectedSimulator,
              let index = coordinator.filteredItems.firstIndex(where: { $0.id == selected.id }),
              nsView.indexOfSelectedItem != index else { return }
        nsView.selectItem(at: index)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, NSComboBoxDelegate, NSComboBoxDataSource {
        var parent: SimulatorComboBox
        var allItems: [Simulator] = []
        var filteredItems: [Simulator] = []
        
        init(parent: SimulatorComboBox) {
            self.parent = parent
        }
        
        // MARK: - NSComboBoxDataSource
        func numberOfItems(in comboBox: NSComboBox) -> Int {
            filteredItems.count
        }
        
        func comboBox(_ comboBox: NSComboBox, objectValueForItemAt index: Int) -> Any? {
            guard index >= 0 && index < filteredItems.count else { return nil }
            let sim = filteredItems[index]
            let bootStatus = sim.isBooted ? "🟢" : "⚪️"
            return "\(bootStatus) \(sim.name) — \(sim.runtime)"
        }
        
        // MARK: - NSComboBoxDelegate
        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            let index = comboBox.indexOfSelectedItem
            guard index >= 0 && index < filteredItems.count else { return }
            let selected = filteredItems[index]
            
            DispatchQueue.main.async {
                self.parent.selectedSimulator = selected
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
                    $0.runtime.lowercased().contains(query)
                }
            }
            comboBox.reloadData()
        }
    }
}
