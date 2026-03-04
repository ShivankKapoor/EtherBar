//
//  EtherBarApp.swift
//  EtherBar
//
//  Created by Shivank Kapoor on 3/3/26.
//

import SwiftUI
import AppKit
import CoreWLAN

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
    private var lastEthernetState: Bool? = nil
    private var lastWifiState: Bool? = nil

    // Persistent menu items — built once, updated in place
    private let ethernetMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private lazy var wifiMenuItem: NSMenuItem = {
        let item = NSMenuItem(title: "", action: #selector(toggleWiFi), keyEquivalent: "")
        item.target = self
        return item
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        // Build menu once
        let menu = NSMenu()
        menu.addItem(ethernetMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(wifiMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit EtherBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu

        updateIcon()

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }
    }

    func checkForChanges() {
        let ethernetState = networkMonitor.isEthernetConnected
        let wifiState = isWiFiEnabled()

        if ethernetState != lastEthernetState || wifiState != lastWifiState {
            lastEthernetState = ethernetState
            lastWifiState = wifiState
            updateIcon()
        }
    }

    func isWiFiEnabled() -> Bool {
        return CWWiFiClient.shared().interface()?.powerOn() ?? false
    }

    @objc func toggleWiFi() {
        guard let interface = CWWiFiClient.shared().interface() else { return }
        let current = interface.powerOn()
        try? interface.setPower(!current)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
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

        button.alphaValue = connected ? 1.0 : 0.4

        // Update menu items in place — no menu reassignment
        ethernetMenuItem.title = connected ? "Ethernet Connected" : "No Ethernet"
        wifiMenuItem.title = isWiFiEnabled() ? "Turn Wi-Fi Off" : "Turn Wi-Fi On"
    }
}
