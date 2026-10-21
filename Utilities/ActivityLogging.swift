// ActivityLogging.swift
// MacGuard - Anti-Theft Alarm for macOS

/// Log from any isolation context; hops to the main actor that owns the log.
func logActivity(_ category: ActivityLogCategory, _ message: String) {
    Task { @MainActor in
        ActivityLogManager.shared.log(category, message)
    }
}
