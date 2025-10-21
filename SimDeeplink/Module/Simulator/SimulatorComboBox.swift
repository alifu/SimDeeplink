//
//  SimulatorComboBox.swift
//  SimDeeplink
//
//  Created by Alif on 17/10/25.
//

import SwiftUI
import AppKit

enum SimulatorType: String, CaseIterable {
    case iPhone
    case iPad
    case watch
    case tv
    case unknown
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
        comboBox.usesDataSource = false
        comboBox.delegate = context.coordinator
        comboBox.isEditable = false
        comboBox.hasVerticalScroller = true
        return comboBox
    }
    
    func updateNSView(_ nsView: NSComboBox, context: Context) {
        nsView.removeAllItems()
        
        // Show name + runtime + status
        nsView.addItems(withObjectValues: items.map { sim in
            let bootStatus = sim.isBooted ? "🟢" : "⚪️"
            return "\(bootStatus) \(sim.name) — \(sim.runtime)"
        })
        
        if let selected = selectedSimulator,
           let index = items.firstIndex(where: { $0.udid == selected.udid }) {
            nsView.selectItem(at: index)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, NSComboBoxDelegate {
        var parent: SimulatorComboBox
        
        init(parent: SimulatorComboBox) {
            self.parent = parent
        }
        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            let index = comboBox.indexOfSelectedItem
            guard index >= 0 && index < parent.items.count else { return }
            let selected = parent.items[index]
            
            DispatchQueue.main.async {
                self.parent.selectedSimulator = selected
            }
        }
    }
}


