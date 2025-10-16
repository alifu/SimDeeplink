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
            Text("Settings or main app window")
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var window: NSWindow?
    var statusBarItem: NSStatusItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusBarItem?.button {
            button.action = #selector(statusBarButtonClicked(_:))
            button.target = self
            button.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil)
        }
        
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if self?.window?.isVisible == true {
                self?.window?.orderOut(nil)
            }
        }
    }
    
    @objc func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let windowWidth: CGFloat = 150
        let windowHeight: CGFloat = 150
        
        guard let buttonWindow = sender.window else { return }
        guard let screen = buttonWindow.screen else { return }

        // Convert the button’s bounds to screen coordinates (fresh every time)
        let buttonFrameInWindow = sender.convert(sender.bounds, to: nil)
        let buttonOriginOnScreen = buttonWindow.convertPoint(toScreen: buttonFrameInWindow.origin)
        
        // macOS coordinate bug workaround:
        // If the app just became active, screen coordinates can lag one frame.
        // Force window updates before positioning.
        NSApp.activate(ignoringOtherApps: false)
        buttonWindow.displayIfNeeded()

        // Calculate Y position directly below the menubar
        let x = buttonOriginOnScreen.x + (sender.frame.width / 2) - (windowWidth / 2)
        let y = buttonOriginOnScreen.y - windowHeight - 4 // small gap
        
        let windowRect = NSRect(x: x, y: y, width: windowWidth, height: windowHeight)

        // Build or reuse window
        window = getOrBuildWindow(size: windowRect)
        
        // Toggle visibility
        toggleWindowVisibility(location: NSPoint(x: x, y: y))
    }


    
    func getOrBuildWindow(size: NSRect) -> NSWindow {
        if window == nil {
            let contentView = SimDeeplinkVIew()
            window = NSWindow(
                contentRect: size,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
//            window?.isOpaque = false
//            window?.backgroundColor = .clear
            window?.contentView = NSHostingView(rootView: contentView)
            window?.isReleasedWhenClosed = false
            window?.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window?.level = .floating
            window?.hasShadow = true
        }
        window?.setFrame(size, display: true)
        return window!
    }

    
    func toggleWindowVisibility(location: NSPoint) {
        // window hasn't been built yet, don't do anything
        if window == nil {
            return
        }
        if window!.isVisible {
            // window is visible, hide it
            window?.orderOut(nil)
        } else {
            // window is hidden. Position and show it on top of other windows
            window?.setFrameOrigin(location)
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func getMenuBarHeight() -> CGFloat? {
        guard let desktopFrame = NSScreen.main?.visibleFrame else {
            return nil
        }
        let screenFrame = NSScreen.main?.frame
        let menuBarHeight = screenFrame!.height - desktopFrame.height
        return menuBarHeight
    }
    
}
