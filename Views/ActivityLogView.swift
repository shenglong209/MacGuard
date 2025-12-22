// ActivityLogView.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-22

import SwiftUI

/// Activity log viewer displayed in a sheet/window
struct ActivityLogView: View {
    @ObservedObject private var logManager = ActivityLogManager.shared
    @State private var selectedCategory: ActivityLogCategory?
    @State private var searchText = ""

    private var filteredEntries: [ActivityLogEntry] {
        var entries = logManager.entries

        if let category = selectedCategory {
            entries = entries.filter { $0.category == category }
        }

        if !searchText.isEmpty {
            entries = entries.filter {
                $0.message.localizedCaseInsensitiveContains(searchText)
            }
        }

        return entries
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with filters
            headerView

            Divider()

            // Log entries list
            if filteredEntries.isEmpty {
                emptyStateView
            } else {
                logListView
            }
        }
        .frame(width: 500, height: 400)
        .background {
            VisualEffectView(
                material: .sidebar,
                blendingMode: .behindWindow,
                isEmphasized: true
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack {
                Text("Activity Log")
                    .font(.headline)

                Spacer()

                Button("Clear") {
                    logManager.clear()
                }
                .buttonStyle(GlassSecondaryButtonStyle())
            }

            HStack(spacing: Theme.Spacing.sm) {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
                .background {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.sm)
                        .fill(.quaternary)
                }

                // Category filter
                Picker("", selection: $selectedCategory) {
                    Text("All").tag(nil as ActivityLogCategory?)
                    ForEach(ActivityLogCategory.allCases, id: \.self) { category in
                        Label(category.rawValue, systemImage: category.icon)
                            .tag(category as ActivityLogCategory?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }
        }
        .padding(Theme.Spacing.md)
        .background {
            GlassBackground(material: .headerView, cornerRadius: 0, showBorder: false)
        }
    }

    // MARK: - Log List

    private var logListView: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(filteredEntries) { entry in
                    logEntryRow(entry)
                }
            }
            .padding(Theme.Spacing.sm)
        }
    }

    private func logEntryRow(_ entry: ActivityLogEntry) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Category icon
            Image(systemName: entry.category.icon)
                .font(.caption)
                .foregroundColor(categoryColor(entry.category))
                .frame(width: 16)

            // Timestamp
            Text(entry.formattedTime)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)

            // Message
            Text(entry.message)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.sm)
                .fill(.quaternary.opacity(0.5))
        }
        .help(entry.formattedDate + " - " + entry.message)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text("No activity logs")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Activity will appear here as events occur")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func categoryColor(_ category: ActivityLogCategory) -> Color {
        switch category {
        case .system: return .secondary
        case .armed: return Theme.StateColor.armed
        case .disarmed: return Theme.StateColor.idle
        case .trigger: return Theme.StateColor.triggered
        case .alarm: return Theme.StateColor.alarming
        case .bluetooth: return Theme.Accent.info
        case .input: return Theme.Accent.primary
        case .power: return Theme.Accent.warning
        }
    }
}

// MARK: - Activity Log Window Controller

class ActivityLogWindowController: NSObject, NSWindowDelegate {
    static let shared = ActivityLogWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    func show() {
        if window == nil {
            createWindow()
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func createWindow() {
        let hostingController = NSHostingController(rootView: ActivityLogView())

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        newWindow.contentViewController = hostingController
        newWindow.title = "Activity Log"
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.minSize = NSSize(width: 400, height: 300)

        window = newWindow
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

#Preview {
    ActivityLogView()
}
