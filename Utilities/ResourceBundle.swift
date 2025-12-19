// ResourceBundle.swift
// Custom Bundle accessor for app bundle distribution
// SPM's auto-generated Bundle.module looks at wrong path when distributed

import Foundation

/// Custom resource bundle that works both in development (SPM) and distribution (app bundle)
enum ResourceBundle {
    /// The resource bundle containing app resources
    static let bundle: Bundle = {
        // Priority 1: Look in Contents/Resources/ (app bundle distribution)
        let appBundlePath = Bundle.main.bundlePath + "/Contents/Resources/MacGuard_MacGuard.bundle"
        if let bundle = Bundle(path: appBundlePath) {
            return bundle
        }

        // Priority 2: Look at app root level (alternative placement)
        let rootPath = Bundle.main.bundlePath + "/MacGuard_MacGuard.bundle"
        if let bundle = Bundle(path: rootPath) {
            return bundle
        }

        // Priority 3: Development - SPM build directory
        #if DEBUG
        let debugPath = Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("MacGuard_MacGuard.bundle").path
        if let bundle = Bundle(path: debugPath) {
            return bundle
        }
        #endif

        // Fallback: Use SPM's Bundle.module (works during development)
        return Bundle.module
    }()

    /// Get URL for a resource file
    static func url(forResource name: String, withExtension ext: String, subdirectory: String? = nil) -> URL? {
        return bundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory)
    }
}
