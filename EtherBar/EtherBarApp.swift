//
//  EtherBarApp.swift
//  EtherBar
//
//  Created by Shivank Kapoor on 3/3/26.
//

import SwiftUI
import AppKit
import Observation
import SystemConfiguration

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
    var ethernetIP: String = "—"
    var wifiIP: String = "—"
    var publicIP: String = "—"
    var ipLocation: String = "—"
    var dns: String = "—"
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var networkMonitor = NetworkMonitor()
    let trafficMonitor = TrafficMonitor()
    let appState = AppState()
    let userSettings = UserSettings()
    private lazy var settingsWindowController = SettingsWindowController(settings: userSettings)
    private var lastEthernetState: Bool? = nil
    private var lastWifiState: Bool? = nil
    private let bgQueue = DispatchQueue(label: "EtherBarBackground", qos: .utility)

    private let ethernetMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var wifiToggleItem = NSMenuItem()
    private var trafficItem = NSMenuItem()
    private var ipInfoItem = NSMenuItem()
    private var ipInfoSeparatorBefore = NSMenuItem.separator()
    private var ipInfoSeparatorAfter = NSMenuItem.separator()
    // Retained so it isn't deallocated after applicationDidFinishLaunching returns
    private var bgTimer: DispatchSourceTimer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let menu = NSMenu()
        menu.addItem(ethernetMenuItem)
        menu.addItem(NSMenuItem.separator())

        // Traffic view — created once, reads from appState directly
        trafficItem = NSMenuItem()
        let trafficView = NSHostingView(rootView: TrafficBarView(state: appState, settings: userSettings))
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

        menu.addItem(ipInfoSeparatorBefore)

        // IP info — created once, reads from appState directly
        ipInfoItem = NSMenuItem()
        let ipInfoView = NSHostingView(rootView: IPInfoView(
            state: appState,
            settings: userSettings,
            onHeightChange: { [weak self] height in
                guard let self else { return }
                let hasContent = height > 1
                // Never hide the item itself — macOS suspends SwiftUI updates on
                // hidden NSMenuItem views, preventing the item from re-appearing.
                // A 1px frame is invisible; separators control the visual gap.
                self.ipInfoItem.view?.frame = NSRect(x: 0, y: 0, width: 220, height: height)
                self.ipInfoSeparatorBefore.isHidden = !hasContent
                self.ipInfoSeparatorAfter.isHidden = !hasContent
            }
        ))
        ipInfoView.frame = NSRect(x: 0, y: 0, width: 220, height: 84)
        ipInfoItem.view = ipInfoView
        menu.addItem(ipInfoItem)

        menu.addItem(ipInfoSeparatorAfter)
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit EtherBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
        menu.delegate = self

        // Resolve interface names on background thread, then start retained timer
        bgQueue.async { [weak self] in
            guard let self else { return }
            self.resolveInterfaces()
            self.interfacesResolved = true
            _ = self.trafficMonitor.sample() // prime baseline sample
            self.refreshInBackground()
            self.startTimer()
        }
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: bgQueue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in self?.refreshInBackground() }
        timer.resume()
        bgTimer = timer // retain so it isn't released
    }

    // MARK: - Interface Resolution

    private var wifiInterface: String = ""
    private var interfacesResolved: Bool = false

    func resolveInterfaces() {
        // Only need to identify the Wi-Fi interface; ethernet rate is derived
        // by summing all en* interfaces that aren't Wi-Fi.
        guard let ifList = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return }
        let wifiType = kSCNetworkInterfaceTypeIEEE80211 as String
        for iface in ifList {
            guard let bsdName = SCNetworkInterfaceGetBSDName(iface) as String?,
                  let ifType  = SCNetworkInterfaceGetInterfaceType(iface) as String? else { continue }
            if ifType == wifiType {
                wifiInterface = bsdName
                break
            }
        }
    }

    // MARK: - Background Refresh

    func refreshInBackground() {
        guard interfacesResolved else { return }

        let ethernetState = networkMonitor.isEthernetConnected

        let wifiState: Bool
        if wifiInterface.isEmpty {
            wifiState = false
        } else {
            wifiState = shell("/usr/sbin/networksetup -getairportpower \(wifiInterface)")
                .lowercased().contains("on")
        }

        let rates = trafficMonitor.sample()

        // Sum all en* interfaces except Wi-Fi — covers built-in, USB, Thunderbolt dongles, etc.
        let ethernetRate: Double = rates
            .filter { $0.key.hasPrefix("en") && $0.key != wifiInterface }
            .values.reduce(0, +)
        let wifiRate = wifiInterface.isEmpty ? 0 : (rates[wifiInterface] ?? 0)

        let ethernetIP = getInterfaceIP(matching: { $0.hasPrefix("en") && $0 != self.wifiInterface })
        let wifiIP = wifiInterface.isEmpty ? "—" : getInterfaceIP(matching: { $0 == self.wifiInterface })
        let dns = getDNS()

        // Fetch public IP + location once immediately, then every 60 seconds
        publicIPRefreshCounter += 1
        if publicIPRefreshCounter == 1 || publicIPRefreshCounter >= 60 {
            publicIPRefreshCounter = 1
            fetchPublicIPInfo()
        }

        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) { [weak self] in
            guard let self else { return }
            self.appState.wifiEnabled = wifiState
            self.appState.ethernetConnected = ethernetState
            self.appState.ethernetRate = ethernetRate
            self.appState.wifiRate = wifiRate
            self.appState.ethernetIP = ethernetIP
            self.appState.wifiIP = wifiIP
            self.appState.dns = dns

            let rows = (ethernetState ? 1 : 0) + (wifiState ? 1 : 0) + (ethernetState && wifiState ? 1 : 0)
            let height = rows > 0 ? CGFloat(rows * 17 + 12) : 2
            self.trafficItem.view?.frame = NSRect(x: 0, y: 0, width: 220, height: height)

            if ethernetState != self.lastEthernetState || wifiState != self.lastWifiState {
                self.lastEthernetState = ethernetState
                self.lastWifiState = wifiState
                self.applyIconUpdate(connected: ethernetState)
            }
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    func applyIconUpdate(connected: Bool) {
        guard let button = statusItem?.button else { return }
        let iconSize = NSSize(width: 18, height: 18)

        if connected {
            if let image = NSImage(named: "ethernet") {
                let copy = image.copy() as! NSImage
                copy.isTemplate = true
                copy.size = iconSize
                button.image = copy
            }
        } else {
            // Composite: ethernet icon + diagonal slash (upper-left → lower-right),
            // matching the macOS WiFi disconnected icon style and stroke weight.
            let disconnectedImage = NSImage(size: iconSize, flipped: false) { rect in
                guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

                // Draw the base ethernet icon
                if let src = NSImage(named: "ethernet") {
                    let copy = src.copy() as! NSImage
                    copy.size = rect.size
                    copy.draw(in: rect)
                }

                let padding: CGFloat = 1.5
                // \ direction: start upper-left, end lower-right
                let start = CGPoint(x: padding, y: rect.height - padding)
                let end   = CGPoint(x: rect.width - padding, y: padding)

                // Cut a clear channel so the slash reads against icon pixels
                ctx.setBlendMode(.clear)
                ctx.setLineCap(.round)
                ctx.setLineWidth(3.5)
                ctx.move(to: start)
                ctx.addLine(to: end)
                ctx.strokePath()

                // Draw the slash line itself
                ctx.setBlendMode(.normal)
                ctx.setStrokeColorSpace(CGColorSpaceCreateDeviceRGB())
                ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
                ctx.setLineWidth(1.75)
                ctx.move(to: start)
                ctx.addLine(to: end)
                ctx.strokePath()

                return true
            }
            disconnectedImage.isTemplate = true
            button.image = disconnectedImage
        }

        button.alphaValue = 1.0
        ethernetMenuItem.title = connected ? "Ethernet Connected" : "No Ethernet"
    }

    // MARK: - Settings

    @objc func openSettings() {
        settingsWindowController.showSettings()
    }

    // MARK: - Wi-Fi Toggle

    func toggleWiFi() {
        guard !wifiInterface.isEmpty else { return }
        let turningOn = !appState.wifiEnabled
        let newState = turningOn ? "on" : "off"
        bgQueue.async { [weak self] in
            guard let self else { return }
            self.shell("/usr/sbin/networksetup -setairportpower \(self.wifiInterface) \(newState)")
            let delay: Double = turningOn ? 3.0 : 0.5
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.bgQueue.async { self.refreshInBackground() }
            }
        }
    }

    // MARK: - Shell Helper

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

    // MARK: - IP Helpers

    private var publicIPRefreshCounter: Int = 0

    func getDNS() -> String {
        guard let store = SCDynamicStoreCreate(nil, "EtherBar" as CFString, nil, nil),
              let info = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any],
              let servers = info["ServerAddresses"] as? [String],
              let primary = servers.first else { return "—" }
        return primary
    }

    func getInterfaceIP(matching predicate: (String) -> Bool) -> String {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return "—" }
        defer { freeifaddrs(ifaddr) }
        var ptr = firstAddr
        while true {
            let flags = Int32(ptr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            if isUp && !isLoopback,
               ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET),
               let name = ptr.pointee.ifa_name,
               predicate(String(cString: name)) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let addrLen = socklen_t(ptr.pointee.ifa_addr.pointee.sa_len)
                if getnameinfo(ptr.pointee.ifa_addr, addrLen,
                               &hostname, socklen_t(hostname.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: hostname)
                }
            }
            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }
        return "—"
    }

    func fetchPublicIPInfo() {
        guard let url = URL(string: "https://ipinfo.io/json") else { return }
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data else { return }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let ip = json["ip"] as? String ?? "—"
            let city = json["city"] as? String ?? ""
            let country = json["country"] as? String ?? ""
            let location: String
            if city.isEmpty && country.isEmpty {
                location = "—"
            } else {
                location = [city, country].filter { !$0.isEmpty }.joined(separator: ", ")
            }
            DispatchQueue.main.async {
                self.appState.publicIP = ip
                self.appState.ipLocation = location
            }
        }
        task.resume()
    }
}

// MARK: - Menu Delegate

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        var visibleCount = 0
        for field in userSettings.ipInfoOrder {
            let mode = userSettings.displayMode(for: field)
            if mode == .hidden { continue }
            if field == .localIP {
                let ethIP  = appState.ethernetIP
                let wifiIP = appState.wifiIP
                if appState.ethernetConnected && appState.wifiEnabled && ethIP != wifiIP && ethIP != "—" && wifiIP != "—" {
                    visibleCount += 2
                } else {
                    visibleCount += 1
                }
            } else {
                visibleCount += 1
            }
        }
        let height: CGFloat = visibleCount > 0 ? CGFloat(visibleCount * 19 + 8) : 1
        let hasContent = height > 1
        ipInfoItem.view?.frame = NSRect(x: 0, y: 0, width: 220, height: height)
        ipInfoSeparatorBefore.isHidden = !hasContent
        ipInfoSeparatorAfter.isHidden = !hasContent
    }
}

// MARK: - WiFi Toggle View

struct WiFiToggleView: View {
    let state: AppState
    let onToggle: () -> Void
    @State private var optimisticState: Bool? = nil

    private var displayState: Bool {
        optimisticState ?? state.wifiEnabled
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
            ActiveToggle(isOn: Binding(
                get: { displayState },
                set: { newValue in
                    optimisticState = newValue
                    onToggle()
                }
            ))
        }
        .padding(.horizontal, 14)
        .frame(height: 28)
        .contentShape(Rectangle())
        .onChange(of: state.wifiEnabled) { _, newValue in
            optimisticState = nil
        }
    }
}

struct ActiveToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        ZStack {
            Capsule()
                .fill(isOn ? Color.accentColor : Color(nsColor: .tertiaryLabelColor))
                .frame(width: 36, height: 20)
            Circle()
                .fill(.white)
                .shadow(radius: 1, y: 1)
                .frame(width: 16, height: 16)
                .offset(x: isOn ? 8 : -8)
                .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isOn)
        }
        .onTapGesture { isOn.toggle() }
    }
}

// MARK: - Traffic Bar View

struct TrafficBarView: View {
    let state: AppState
    let settings: UserSettings

    private var total: Double { state.ethernetRate + state.wifiRate }
    private var maxRate: Double { max(state.ethernetRate, state.wifiRate, 1) }
    private var ethernetFraction: Double { state.ethernetRate / maxRate }
    private var wifiFraction: Double { state.wifiRate / maxRate }
    private var ethernetPercent: Double { total > 0 ? state.ethernetRate / total : 0 }
    private var wifiPercent: Double { total > 0 ? state.wifiRate / total : 0 }

    private func rateLabel(_ bps: Double) -> String {
        let bits = bps * 8
        if bits < 1_000 {
            return "0 Kbps"
        } else if bits < 1_000_000 {
            let kbps = bits / 1_000
            return kbps < 10 ? String(format: "%.1f Kbps", kbps) : String(format: "%.0f Kbps", kbps)
        } else if bits < 1_000_000_000 {
            let mbps = bits / 1_000_000
            return mbps < 10 ? String(format: "%.1f Mbps", mbps) : String(format: "%.0f Mbps", mbps)
        } else {
            let gbps = bits / 1_000_000_000
            return gbps < 10 ? String(format: "%.2f Gbps", gbps) : String(format: "%.1f Gbps", gbps)
        }
    }

    var body: some View {
        VStack(spacing: 5) {
            if state.ethernetConnected {
                UnitTrafficRow(icon: "cable.connector", fraction: ethernetFraction, rate: rateLabel(state.ethernetRate), color: settings.ethernetColor.color)
            }
            if state.wifiEnabled {
                UnitTrafficRow(icon: "wifi", fraction: wifiFraction, rate: rateLabel(state.wifiRate), color: settings.wifiColor.color)
            }
            if state.ethernetConnected && state.wifiEnabled {
                PercentSplitRow(ethernetPercent: ethernetPercent, wifiPercent: wifiPercent, ethernetColor: settings.ethernetColor.color, wifiColor: settings.wifiColor.color)
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
                        .fill(color)
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
    var ethernetColor: Color = .blue
    var wifiColor: Color = .green

    private var hasTraffic: Bool { ethernetPercent + wifiPercent > 0 }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 11))
                .frame(width: 14)
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(hasTraffic ? wifiColor : Color.secondary.opacity(0.15))
                        .animation(.easeOut(duration: 0.4), value: hasTraffic)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(ethernetColor)
                        .frame(width: max(0, geo.size.width * ethernetPercent))
                        .opacity(hasTraffic ? 1 : 0)
                        .animation(.easeOut(duration: 0.4), value: ethernetPercent)
                        .animation(.easeOut(duration: 0.4), value: hasTraffic)
                }
            }
            .frame(height: 6)
            Text(String(format: "%.0f%% / %.0f%%", ethernetPercent * 100, wifiPercent * 100))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
        }
    }
}

// MARK: - IP Info View

struct IPInfoView: View {
    let state: AppState
    let settings: UserSettings
    var onHeightChange: (CGFloat) -> Void = { _ in }
    @State private var revealed: Set<Int> = []

    private var rows: [(label: String, value: String, mode: IPInfoDisplayMode)] {
        var fieldRows: [IPInfoField: [(String, String, IPInfoDisplayMode)]] = [:]

        let ethIP  = state.ethernetIP
        let wifiIP = state.wifiIP
        let bothConnected = state.ethernetConnected && state.wifiEnabled
        let bothDiffer = bothConnected && ethIP != wifiIP && ethIP != "—" && wifiIP != "—"
        if bothDiffer {
            fieldRows[.localIP] = [
                ("Ethernet IP", ethIP,  settings.localIPDisplay),
                ("Wi-Fi IP",    wifiIP, settings.localIPDisplay),
            ]
        } else if state.ethernetConnected && ethIP != "—" {
            fieldRows[.localIP] = [("Local IP", ethIP, settings.localIPDisplay)]
        } else if state.wifiEnabled && wifiIP != "—" {
            fieldRows[.localIP] = [("Local IP", wifiIP, settings.localIPDisplay)]
        } else {
            fieldRows[.localIP] = [("Local IP", "—", settings.localIPDisplay)]
        }
        fieldRows[.publicIP] = [("Public IP", state.publicIP,   settings.publicIPDisplay)]
        fieldRows[.location] = [("Location",  state.ipLocation, settings.locationDisplay)]
        fieldRows[.dns]      = [("DNS",       state.dns,        settings.dnsDisplay)]

        var result: [(String, String, IPInfoDisplayMode)] = []
        for field in settings.ipInfoOrder {
            if let entries = fieldRows[field] {
                result.append(contentsOf: entries)
            }
        }
        return result
    }

    private var modeKey: [IPInfoDisplayMode] { rows.map(\.mode) }

    private var visibleCount: Int { rows.filter { $0.mode != .hidden }.count }

    private var height: CGFloat {
        let n = visibleCount
        return n > 0 ? CGFloat(n * 19 + 8) : 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if row.mode != .hidden {
                    IPInfoRow(
                        label: row.label,
                        value: row.value,
                        isRevealed: row.mode == .alwaysShow || revealed.contains(index),
                        onReveal: { revealed.insert(index) },
                        onHide:   { revealed.remove(index) }
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, visibleCount > 0 ? 6 : 0)
        .onAppear { notifyHeight() }
        .onDisappear { revealed = [] }
        .onChange(of: modeKey) { _, _ in
            revealed = []
            notifyHeight()
        }
    }

    private func notifyHeight() {
        let h = height
        onHeightChange(h)
    }
}

struct IPInfoRow: View {
    let label: String
    let value: String
    var isRevealed: Bool = true
    var onReveal: () -> Void = {}
    var onHide: () -> Void = {}

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            if isRevealed {
                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
            } else {
                Text("tap to reveal")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isRevealed { onReveal() } else { onHide() }
        }
    }
}
