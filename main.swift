// main.swift
// MacGuard - Anti-Theft Alarm for macOS

// Also runs as the headless tamper watchdog (see TamperGuard.swift).
if CommandLine.arguments.contains(Watchdog.argument) {
    Watchdog.run()
} else {
    MacGuardApp.main()
}
