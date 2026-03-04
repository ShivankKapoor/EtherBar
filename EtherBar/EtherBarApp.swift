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
    private var lastEthernetState: Bool? = nil
    private var lastWifiState: Bool? = nil

    private let ethernetMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var wifiToggleItem = NSMenuItem()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let menu = NSMenu()
        menu.addItem(ethernetMenuItem)
        menu.addItem(NSMenuItem.separator())

        wifiToggleItem = NSMenuItem()
        let wifiView = NSHostingView(rootView: WiFiToggleView(isOn: isWiFiEnabled(), onToggle: { [weak self] in
            self?.toggleWiFi()
        }))
        wifiView.frame = NSRect(x: 0, y: 0, width: 200, height: 28)
        wifiToggleItem.view = wifiView
        menu.addItem(wifiToggleItem)

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
        // Use en0 directly — networksetup -listallhardwareports can miss Wi-Fi when it's off
        let output = shell("/usr/sbin/networksetup -getairportpower en0")
        return output.lowercased().contains("on")
    }

    func toggleWiFi() {
        let turningOn = !isWiFiEnabled()
        let newState = turningOn ? "on" : "off"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.shell("/usr/sbin/networksetup -setairportpower en0 \(newState)")
            // WiFi takes longer to turn on than off — wait accordingly
            let delay: Double = turningOn ? 3.0 : 0.5
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self?.updateIcon()
            }
        }
    }

    @discardableResult
    func shell(_ command: String) -> String {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.launch()
        task.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
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
        ethernetMenuItem.title = connected ? "Ethernet Connected" : "No Ethernet"

        let wifiOn = isWiFiEnabled()
        let wifiView = NSHostingView(rootView: WiFiToggleView(isOn: wifiOn, onToggle: { [weak self] in
            self?.toggleWiFi()
        }))
        wifiView.frame = NSRect(x: 0, y: 0, width: 200, height: 28)
        wifiToggleItem.view = wifiView
    }
}

struct WiFiToggleView: View {
    let isOn: Bool
    let onToggle: () -> Void
    @State private var optimisticState: Bool

    init(isOn: Bool, onToggle: @escaping () -> Void) {
        self.isOn = isOn
        self.onToggle = onToggle
        self._optimisticState = State(initialValue: isOn)
    }

    var body: some View {
        HStack {
            Image(systemName: "wifi")
                .foregroundStyle(.primary)
                .font(.system(size: 12))
            Text("Wi-Fi")
                .foregroundStyle(.primary)
                .font(.system(size: 13))
            Spacer()
            Toggle("", isOn: Binding(
                get: { optimisticState },
                set: { newValue in
                    optimisticState = newValue
                    onToggle()
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .scaleEffect(0.7, anchor: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: 28)
        .contentShape(Rectangle())
        .onChange(of: isOn) { _, newValue in
            optimisticState = newValue
        }
    }
}
