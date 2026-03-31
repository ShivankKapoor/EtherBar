//
//  Settings.swift
//  EtherBar
//
//  Created by EtherBar on 3/30/26.
//

import SwiftUI
import Observation

// MARK: - Color Choices

enum ColorChoice: String, CaseIterable, Identifiable {
    case blue, cyan, green, yellow, orange, red, pink, purple

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue:   return .blue
        case .cyan:   return .cyan
        case .green:  return .green
        case .yellow: return .yellow
        case .orange: return Color(red: 255/255, green: 103/255, blue: 32/255)
        case .red:    return .red
        case .pink:   return .pink
        case .purple: return .purple
        }
    }

    var label: String { rawValue.capitalized }
}

// MARK: - IP Info Display Mode

enum IPInfoDisplayMode: String, CaseIterable {
    case hidden      = "hidden"
    case clickToShow = "clickToShow"
    case alwaysShow  = "alwaysShow"

    var label: String {
        switch self {
        case .hidden:      return "Don't Show"
        case .clickToShow: return "Click to Show"
        case .alwaysShow:  return "Always Show"
        }
    }

    var shortLabel: String {
        switch self {
        case .hidden:      return "Off"
        case .clickToShow: return "Tap"
        case .alwaysShow:  return "Show"
        }
    }
}

// MARK: - Persistent User Settings

@Observable
class UserSettings {
    var ethernetColor: ColorChoice {
        didSet {
            if ethernetColor == wifiColor {
                wifiColor = oldValue
            }
            save()
        }
    }
    var wifiColor: ColorChoice {
        didSet {
            if wifiColor == ethernetColor {
                ethernetColor = oldValue
            }
            save()
        }
    }
    var localIPDisplay: IPInfoDisplayMode  { didSet { save() } }
    var publicIPDisplay: IPInfoDisplayMode { didSet { save() } }
    var locationDisplay: IPInfoDisplayMode { didSet { save() } }
    var dnsDisplay: IPInfoDisplayMode      { didSet { save() } }

    private static let ethernetKey  = "ethernetBarColor"
    private static let wifiKey      = "wifiBarColor"
    private static let localIPKey   = "localIPDisplay"
    private static let publicIPKey  = "publicIPDisplay"
    private static let locationKey  = "locationDisplay"
    private static let dnsKey       = "dnsDisplay"

    init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: Self.ethernetKey),
           let choice = ColorChoice(rawValue: raw) {
            ethernetColor = choice
        } else {
            ethernetColor = .blue
        }
        if let raw = defaults.string(forKey: Self.wifiKey),
           let choice = ColorChoice(rawValue: raw) {
            wifiColor = choice
        } else {
            wifiColor = .green
        }
        localIPDisplay  = IPInfoDisplayMode(rawValue: defaults.string(forKey: Self.localIPKey)  ?? "") ?? .alwaysShow
        publicIPDisplay = IPInfoDisplayMode(rawValue: defaults.string(forKey: Self.publicIPKey) ?? "") ?? .alwaysShow
        locationDisplay = IPInfoDisplayMode(rawValue: defaults.string(forKey: Self.locationKey)  ?? "") ?? .alwaysShow
        dnsDisplay      = IPInfoDisplayMode(rawValue: defaults.string(forKey: Self.dnsKey)       ?? "") ?? .alwaysShow
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(ethernetColor.rawValue,  forKey: Self.ethernetKey)
        defaults.set(wifiColor.rawValue,       forKey: Self.wifiKey)
        defaults.set(localIPDisplay.rawValue,  forKey: Self.localIPKey)
        defaults.set(publicIPDisplay.rawValue, forKey: Self.publicIPKey)
        defaults.set(locationDisplay.rawValue, forKey: Self.locationKey)
        defaults.set(dnsDisplay.rawValue,      forKey: Self.dnsKey)
    }

    func resetToDefaults() {
        ethernetColor   = .blue
        wifiColor       = .green
        localIPDisplay  = .alwaysShow
        publicIPDisplay = .alwaysShow
        locationDisplay = .alwaysShow
        dnsDisplay      = .alwaysShow
    }
}

// MARK: - Settings Window Controller

class SettingsWindowController {
    private var window: NSWindow?
    private let settings: UserSettings

    init(settings: UserSettings) {
        self.settings = settings
    }

    func showSettings() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(settings: settings)
        let hostingView = NSHostingView(rootView: settingsView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 440)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "EtherBar Settings"
        win.contentView = hostingView
        win.center()
        win.isReleasedWhenClosed = false
        win.level = .modalPanel
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }
}

// MARK: - Settings View

struct SettingsView: View {
    let settings: UserSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Traffic Bar Colors")
                .font(.headline)

            ColorPickerSection(
                title: "Ethernet",
                icon: "cable.connector",
                selection: Binding(
                    get: { settings.ethernetColor },
                    set: { settings.ethernetColor = $0 }
                )
            )

            ColorPickerSection(
                title: "Wi-Fi",
                icon: "wifi",
                selection: Binding(
                    get: { settings.wifiColor },
                    set: { settings.wifiColor = $0 }
                )
            )

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Network Info")
                    .font(.subheadline.weight(.medium))
                IPInfoRowPicker(label: "Local IP", selection: Binding(
                    get: { settings.localIPDisplay },
                    set: { settings.localIPDisplay = $0 }
                ))
                IPInfoRowPicker(label: "Public IP", selection: Binding(
                    get: { settings.publicIPDisplay },
                    set: { settings.publicIPDisplay = $0 }
                ))
                IPInfoRowPicker(label: "Location", selection: Binding(
                    get: { settings.locationDisplay },
                    set: { settings.locationDisplay = $0 }
                ))
                IPInfoRowPicker(label: "DNS", selection: Binding(
                    get: { settings.dnsDisplay },
                    set: { settings.dnsDisplay = $0 }
                ))
            }

            Divider()

            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    settings.resetToDefaults()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

struct ColorPickerSection: View {
    let title: String
    let icon: String
    @Binding var selection: ColorChoice

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline.weight(.medium))
            }

            HStack(spacing: 8) {
                ForEach(ColorChoice.allCases) { choice in
                    ColorSwatch(choice: choice, isSelected: selection == choice)
                        .onTapGesture { selection = choice }
                }
            }
        }
    }
}

struct ColorSwatch: View {
    let choice: ColorChoice
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(choice.color)
                .frame(width: 26, height: 26)
            Circle()
                .strokeBorder(isSelected ? Color.primary : Color.clear, lineWidth: 2)
                .frame(width: 30, height: 30)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .contentShape(Circle())
        .accessibilityLabel(choice.label)
    }
}

struct IPInfoRowPicker: View {
    let label: String
    @Binding var selection: IPInfoDisplayMode

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .leading)
            Picker("", selection: $selection) {
                ForEach(IPInfoDisplayMode.allCases, id: \.self) { mode in
                    Text(mode.shortLabel).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}
