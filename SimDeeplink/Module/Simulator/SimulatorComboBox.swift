//
//  SimulatorComboBox.swift
//  SimDeeplink
//
//  Created by Alif on 17/10/25.
//

import SwiftUI
import AppKit

enum SimulatorType: String, CaseIterable {
    case iPhone, iPad, watch, tv, unknown
}

struct Simulator: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let udid: String
    let runtime: String
    let isBooted: Bool
    let type: SimulatorType
}

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
        context.coordinator.allItems = items
        context.coordinator.filteredItems = items
        nsView.reloadData()
        
        // restore selected item if possible
        if let selected = selectedSimulator,
           let index = items.firstIndex(where: { $0.udid == selected.udid }) {
            nsView.selectItem(at: index)
        }
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
