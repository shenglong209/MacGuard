// IORegistry.swift
// MacGuard - Anti-Theft Alarm for macOS

import IOKit

enum IORegistry {
    static func property<T>(_ key: String, of entry: io_registry_entry_t) -> T? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? T
    }

    static func property<T>(_ key: String, ofServiceMatching className: String) -> T? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(className))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        return property(key, of: service)
    }
}
