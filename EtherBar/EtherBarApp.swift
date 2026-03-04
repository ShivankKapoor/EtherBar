//
//  EtherBarApp.swift
//  EtherBar
//
//  Created by Shivank Kapoor on 3/3/26.
//

import SwiftUI
import AppKit
import Observation

@main
struct EtherBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

// Shared observable state — views observe this directly, no NSHostingView recreation needed
@Observable class AppState {
    var ethernetConnected: Bool = false
    var wifiEnabled: Bool = false
    var ethernetRate: Double = 0
    var wifiRate: Double = 0
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var networkMonitor = NetworkMonitor()
    let trafficMonitor = TrafficMonitor()
    let appState = AppState()
    private var lastEthernetState: Bool? = nil
    private var lastWifiState: Bool? = nil
    private let bgQueue = DispatchQueue(label: "EtherBarBackground", qos: .utility)

    private let ethernetMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var wifiToggleItem = NSMenuItem()
    private var trafficItem = NSMenuItem()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let menu = NSMenu()
        menu.addItem(ethernetMenuItem)
        menu.addItem(NSMenuItem.separator())

        // Traffic view — created once, reads from appState directly
        trafficItem = NSMenuItem()
        let trafficView = NSHostingView(rootView: TrafficBarView(state: appState))
        trafficView.frame = NSRect(x: 0, y: 0, width: 220, height: 80)
        trafficItem.view = trafficView
        menu.addItem(trafficItem)
        menu.addItem(NSMenuItem.separator())

        // WiFi toggle — created once, reads from appState directly
        wifiToggleItem = NSMenuItem()
        let wifiView = NSHostingView(rootView: WiFiToggleView(state: appState, onToggle: { [weak self] in
            self?.toggleWiFi()
        }))
        wifiView.frame = NSRect(x: 0, y: 0, width: 220, height: 28)
        wifiToggleItem.view = wifiView
        menu.addItem(wifiToggleItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit EtherBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu

        _ = trafficMonitor.sample()
        refreshInBackground()

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.bgQueue.async { self?.refreshInBackground() }
        }
    }

    func refreshInBackground() {
        let ethernetState = networkMonitor.isEthernetConnected
        let wifiState = shell("/usr/sbin/networksetup -getairportpower en0").lowercased().contains("on")
        let rates = trafficMonitor.sample()
        let ethernetRate = rates.filter { $0.key != "en0" && $0.key.hasPrefix("en") }.values.reduce(0, +)
        let wifiRate = rates["en0"] ?? 0

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Update observable state — views update themselves automatically
            self.appState.wifiEnabled = wifiState
            self.appState.ethernetConnected = ethernetState
            self.appState.ethernetRate = ethernetRate
            self.appState.wifiRate = wifiRate

            // Resize traffic view to fit only visible rows
            let rows = (ethernetState ? 1 : 0) + (wifiState ? 1 : 0) + (ethernetState && wifiState ? 1 : 0)
            let height = rows > 0 ? CGFloat(rows * 17 + 12) : 2
            self.trafficItem.view?.frame = NSRect(x: 0, y: 0, width: 220, height: height)

            // Only update button/title when connection state changes
            if ethernetState != self.lastEthernetState || wifiState != self.lastWifiState {
                self.lastEthernetState = ethernetState
                self.lastWifiState = wifiState
                self.applyIconUpdate(connected: ethernetState)
            }
        }
    }

    func applyIconUpdate(connected: Bool) {
        guard let button = statusItem?.button else { return }
        if let image = NSImage(named: "ethernet") {
            let copy = image.copy() as! NSImage
            copy.isTemplate = true
            copy.size = NSSize(width: 18, height: 18)
            button.image = copy
        }
        button.alphaValue = connected ? 1.0 : 0.4
        ethernetMenuItem.title = connected ? "Ethernet Connected" : "No Ethernet"
    }

    func toggleWiFi() {
        let turningOn = !appState.wifiEnabled
        let newState = turningOn ? "on" : "off"
        bgQueue.async { [weak self] in
            self?.shell("/usr/sbin/networksetup -setairportpower en0 \(newState)")
            let delay: Double = turningOn ? 3.0 : 0.5
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self?.bgQueue.async { self?.refreshInBackground() }
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
}

// MARK: - WiFi Toggle View

struct WiFiToggleView: View {
    let state: AppState
    let onToggle: () -> Void
    @State private var optimisticState: Bool = false

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
        .onAppear { optimisticState = state.wifiEnabled }
        .onChange(of: state.wifiEnabled) { _, newValue in optimisticState = newValue }
    }
}

// MARK: - Traffic Bar View

struct TrafficBarView: View {
    let state: AppState

    private var total: Double { state.ethernetRate + state.wifiRate }
    private var maxRate: Double { max(state.ethernetRate, state.wifiRate, 1) }
    private var ethernetFraction: Double { state.ethernetRate / maxRate }
    private var wifiFraction: Double { state.wifiRate / maxRate }
    private var ethernetPercent: Double { total > 0 ? state.ethernetRate / total : 0 }
    private var wifiPercent: Double { total > 0 ? state.wifiRate / total : 0 }

    private func rateLabel(_ bps: Double) -> String {
        let mbps = bps * 8 / 1_000_000
        if mbps < 0.1 { return "0 Mbps" }
        if mbps < 10  { return String(format: "%.1f Mbps", mbps) }
        return String(format: "%.0f Mbps", mbps)
    }

    var body: some View {
        VStack(spacing: 5) {
            if state.ethernetConnected {
                UnitTrafficRow(icon: "cable.connector", fraction: ethernetFraction, rate: rateLabel(state.ethernetRate), color: .blue)
            }
            if state.wifiEnabled {
                UnitTrafficRow(icon: "wifi", fraction: wifiFraction, rate: rateLabel(state.wifiRate), color: .green)
            }
            if state.ethernetConnected && state.wifiEnabled {
                PercentSplitRow(ethernetPercent: ethernetPercent, wifiPercent: wifiPercent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, state.ethernetConnected || state.wifiEnabled ? 6 : 0)
    }
}

struct UnitTrafficRow: View {
    let icon: String
    let fraction: Double
    let rate: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .frame(width: 14)
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.8))
                        .frame(width: max(4, geo.size.width * fraction))
                        .animation(.easeOut(duration: 0.4), value: fraction)
                }
            }
            .frame(height: 6)
            Text(rate)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
        }
    }
}

struct PercentSplitRow: View {
    let ethernetPercent: Double
    let wifiPercent: Double

    var body: some View {
        HStack(spacing: 6) {
            // Blank spacer to match the 14pt icon in UnitTrafficRow
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 11))
                .frame(width: 14)
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.green.opacity(0.4))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.blue.opacity(0.8))
                        .frame(width: max(0, geo.size.width * ethernetPercent))
                        .animation(.easeOut(duration: 0.4), value: ethernetPercent)
                }
            }
            .frame(height: 6)
            // Single label on the right matching the 72pt rate label
            Text(String(format: "%.0f%% / %.0f%%", ethernetPercent * 100, wifiPercent * 100))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
        }
    }
}
