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
    var networkMonitor = NetworkMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        updateIcon()

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateIcon()
        }
    }

    func updateIcon() {
        let connected = networkMonitor.isEthernetConnected
        guard let button = statusItem?.button else { return }

        if let image = NSImage(named: "ethernet") {
            let copy = image.copy() as! NSImage
            copy.isTemplate = true
            copy.size = NSSize(width: 18, height: 18)
            button.image = copy
        }

        // Dim the button when disconnected — keeps layout identical so menu aligns correctly
        button.alphaValue = connected ? 1.0 : 0.4

        // Rebuild menu each time so the text stays current
        let menu = NSMenu()
        let title = connected ? "Ethernet Connected" : "No Ethernet"
        menu.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit EtherBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }
}
