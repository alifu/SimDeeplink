//
//  SimDeeplinkApp.swift
//  SimDeeplink
//
//  Created by Alif on 16/10/25.
//

import SwiftUI

@main
struct SimDeeplinkApp: App {
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
