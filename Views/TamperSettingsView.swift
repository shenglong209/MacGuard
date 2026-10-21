// TamperSettingsView.swift
// MacGuard - Anti-Theft Alarm for macOS

import ServiceManagement
import SwiftUI

struct TamperSettingsView: View {
    @ObservedObject private var tamperGuard = TamperGuard.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Toggle("Alarm if MacGuard is force-quit", isOn: Binding(
                get: { tamperGuard.isEnabled },
                set: { tamperGuard.isEnabled = $0 }
            ))

            switch tamperGuard.status {
            case .off, .active:
                EmptyView()
            case .needsApproval:
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Theme.StateColor.triggered)
                    Text("Allow MacGuard in Login Items to enable")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Open") { SMAppService.openSystemSettingsLoginItems() }
                        .buttonStyle(GlassSecondaryButtonStyle())
                }
            case .unavailable(let reason):
                Text("Watchdog unavailable: \(reason)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear { tamperGuard.syncAgent() }
    }
}
