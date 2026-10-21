// IntruderPhotoSettingsView.swift
// MacGuard - Anti-Theft Alarm for macOS

import SwiftUI

struct IntruderPhotoSettingsView: View {
    @ObservedObject var camera: IntruderCamera

    var body: some View {
        Section {
            Toggle("Photograph whoever triggers the alarm", isOn: Binding(
                get: { camera.setting == .onIntrusion },
                set: { camera.setEnabled($0) }
            ))

            if camera.access == .denied {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Theme.StateColor.triggered)
                        .font(.caption)
                    Text("Camera access denied")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Open Privacy Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(GlassSecondaryButtonStyle())
                }
            }

            HStack {
                Text("Newest \(IntruderPhotoFiles.keep) photos are kept")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Show Photos") { camera.revealPhotos() }
                    .buttonStyle(GlassSecondaryButtonStyle())
            }
        } header: {
            Label("Intruder Photo", systemImage: "camera.fill")
        }
        .onAppear { camera.refreshAccess() }
    }
}
