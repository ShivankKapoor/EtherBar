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

    private static let ethernetKey = "ethernetBarColor"
    private static let wifiKey = "wifiBarColor"

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
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(ethernetColor.rawValue, forKey: Self.ethernetKey)
        defaults.set(wifiColor.rawValue, forKey: Self.wifiKey)
    }

    func resetToDefaults() {
        ethernetColor = .blue
        wifiColor = .green
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
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 230)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 230),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "EtherBar Settings"
        win.contentView = hostingView
        win.center()
        win.isReleasedWhenClosed = false
        win.level = .floating
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
