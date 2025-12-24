// ActivityLogView.swift
// MacGuard - Anti-Theft Alarm for macOS
// Created: 2025-12-22

import SwiftUI

/// Activity log viewer displayed in a sheet/window
struct ActivityLogView: View {
    @ObservedObject private var logManager = ActivityLogManager.shared
    @State private var selectedCategories: Set<ActivityLogCategory> = Set(ActivityLogCategory.allCases)
    @State private var searchText = ""

    private var filteredEntries: [ActivityLogEntry] {
        var entries = logManager.entries

        // Filter by selected categories (if not all selected)
        if selectedCategories.count < ActivityLogCategory.allCases.count {
            entries = entries.filter { selectedCategories.contains($0.category) }
        }

        if !searchText.isEmpty {
            entries = entries.filter {
                $0.message.localizedCaseInsensitiveContains(searchText)
            }
        }

        return entries
    }

    /// Check if all categories are selected
    private var allCategoriesSelected: Bool {
        selectedCategories.count == ActivityLogCategory.allCases.count
    }

    /// Label for the filter button
    private var filterLabel: String {
        if allCategoriesSelected || selectedCategories.isEmpty {
            return "All"
        } else if selectedCategories.count == 1 {
            return selectedCategories.first!.rawValue
        } else {
            return "\(selectedCategories.count) selected"
        }
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
                Text("Event Log")
                    .font(.headline)

                Spacer()

                // Export menu
                Menu {
                    Button {
                        logManager.copyToClipboard()
                    } label: {
                        Label("Copy to Clipboard", systemImage: "doc.on.clipboard")
                    }

                    Button {
                        logManager.shareLogFile()
                    } label: {
                        Label("Share Log File...", systemImage: "square.and.arrow.up")
                    }

                    Divider()

                    Button(role: .destructive) {
                        logManager.clear()
                    } label: {
                        Label("Clear Log", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 30)
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

                // Category filter menu (multi-select)
                Menu {
                    // All toggle
                    Button {
                        if allCategoriesSelected {
                            selectedCategories.removeAll()
                        } else {
                            selectedCategories = Set(ActivityLogCategory.allCases)
                        }
                    } label: {
                        HStack {
                            if allCategoriesSelected {
                                Image(systemName: "checkmark")
                            }
                            Text("All")
                        }
                    }

                    Divider()

                    // Individual category toggles
                    ForEach(ActivityLogCategory.allCases, id: \.self) { category in
                        Button {
                            if selectedCategories.contains(category) {
                                selectedCategories.remove(category)
                            } else {
                                selectedCategories.insert(category)
                            }
                        } label: {
                            HStack {
                                if selectedCategories.contains(category) {
                                    Image(systemName: "checkmark")
                                }
                                Label(category.rawValue, systemImage: category.icon)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text(filterLabel)
                            .lineLimit(1)
                    }
                    .frame(width: 120)
                }
                .menuStyle(.borderlessButton)
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

            Text("No events yet")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Events will appear here as they occur")
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
    private weak var parentWindow: NSWindow?

    private override init() {
        super.init()
    }

    func show() {
        // Track parent window for refocus
        self.parentWindow = NSApp.keyWindow

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
        newWindow.title = "Event Log"
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.minSize = NSSize(width: 400, height: 300)

        window = newWindow
    }

    private func refocusParent() {
        if let parent = parentWindow, parent.isVisible {
            parent.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        refocusParent()
        // Only revert to accessory if no other windows visible
        let visibleWindows = NSApp.windows.filter { $0.isVisible && $0 != window }
        if visibleWindows.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

#Preview {
    ActivityLogView()
}
