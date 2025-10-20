//
//  AppDelegate.swift
//  SimDeeplink
//
//  Created by Alif on 16/10/25.
//

import SwiftUI

class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var window: NSWindow?
    var statusBarItem: NSStatusItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if statusBarItem == nil {
            statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }
        
        if let button = statusBarItem?.button {
            button.action = #selector(statusBarButtonClicked(_:))
            button.target = self
            if let image = NSImage(named: "simdeeplink_bar") {
                image.isTemplate = true
                    image.size = NSSize(width: 18, height: 14)
                    button.image = image
                    button.imagePosition = .imageOnly
            }
        }
        
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if self?.window?.isVisible == true {
                self?.window?.orderOut(nil)
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if statusBarItem != nil {
            NSStatusBar.system.removeStatusItem(statusBarItem!)
            statusBarItem = nil
        }
    }
    
    @objc func quitApp() {
        if let item = statusBarItem {
            NSStatusBar.system.removeStatusItem(item)
            statusBarItem = nil
        }

        // Gracefully end the app
        NSApp.terminate(nil)

        // Safety fallback (ensures no ghost icon)
        exit(0)
    }
    
    @objc func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let windowWidth: CGFloat = 500
        let windowHeight: CGFloat = 450
        
        guard let buttonWindow = sender.window,
              let screen = buttonWindow.screen ?? NSScreen.main else { return }
        
        // Convert button bounds to screen coordinates
        let buttonFrameInWindow = sender.convert(sender.bounds, to: nil)
        let buttonOriginOnScreen = buttonWindow.convertPoint(toScreen: buttonFrameInWindow.origin)
        
        // Force layout refresh
        NSApp.activate(ignoringOtherApps: false)
        buttonWindow.displayIfNeeded()
        
        // --- Base position ---
        var x = buttonOriginOnScreen.x + (sender.frame.width / 2) - (windowWidth / 2)
        var y = buttonOriginOnScreen.y - windowHeight - 4 // default: below menubar
        
        let screenFrame = screen.visibleFrame
        let minX = screenFrame.minX + 10
        let maxX = screenFrame.maxX - windowWidth - 10
        
        // --- Horizontal Clamping ---
        if x < minX { x = minX }
        if x > maxX { x = maxX }
        
        // --- Detect menubar position ---
        let isMenuBarAtTop = buttonOriginOnScreen.y > (screenFrame.midY)
        
        if !isMenuBarAtTop {
            // menubar is at bottom (e.g. user moved it)
            y = buttonOriginOnScreen.y + sender.frame.height + 4
        }
        
        let windowRect = NSRect(x: x, y: y, width: windowWidth, height: windowHeight)
        
        // Build or reuse window
        window = getOrBuildWindow(size: windowRect)
        
        // Toggle visibility
        toggleWindowVisibility(location: NSPoint(x: x, y: y))
    }
    
    func getOrBuildWindow(size: NSRect) -> NSWindow {
        if window == nil {
            let contentView = SimDeeplinkView(quitAction: { [weak self] in
                self?.quitApp()
            })
            let hostingView = NSHostingView(rootView: contentView)
            
            window = KeyWindow(
                contentRect: size,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window?.contentView = hostingView
            window?.isReleasedWhenClosed = false
            window?.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window?.level = .floating
            window?.hasShadow = true
            window?.backgroundColor = .clear  // important for rounded corners
            
            // 💫 Round the corners
            hostingView.wantsLayer = true
            hostingView.layer?.cornerRadius = 12
            hostingView.layer?.masksToBounds = true
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
