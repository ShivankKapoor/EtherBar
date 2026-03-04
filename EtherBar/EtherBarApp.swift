//
//  EtherBarApp.swift
//  EtherBar
//
//  Created by Shivank Kapoor on 3/3/26.
//

import SwiftUI
import AppKit

@main
struct EtherBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover = NSPopover()
    var networkMonitor = NetworkMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        popover.contentSize = NSSize(width: 200, height: 60)
        popover.behavior = .transient

        if let button = statusItem?.button {
            button.action = #selector(togglePopover)
            button.target = self
        }

        updateIcon()

        // Observe changes via polling (Observation doesn't KVO into AppKit easily)
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateIcon()
        }
    }

    func updateIcon() {
        let connected = networkMonitor.isEthernetConnected
        guard let button = statusItem?.button else { return }

        let size = NSSize(width: 18, height: 18)

        if connected {
            // Connected: use as template so macOS tints it correctly for light/dark
            if let image = NSImage(named: "ethernet") {
                let copy = image.copy() as! NSImage
                copy.isTemplate = true
                copy.size = size
                button.image = copy
            }
        } else {
            // Disconnected: render as grey (non-template, explicit grey tint)
            let greyImage = NSImage(size: size, flipped: false) { rect in
                guard let source = NSImage(named: "ethernet") else { return false }
                NSGraphicsContext.current?.imageInterpolation = .high
                // Draw the icon in a light grey by using it as a mask
                NSColor(white: 0.75, alpha: 1.0).setFill()
                rect.fill()
                source.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
                return true
            }
            greyImage.isTemplate = false
            button.image = greyImage
        }

        popover.contentViewController = NSHostingController(
            rootView: Text(connected ? "Ethernet Connected" : "No Ethernet")
                .padding()
        )
    }

    @objc func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
