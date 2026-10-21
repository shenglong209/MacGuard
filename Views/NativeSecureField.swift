// NativeSecureField.swift
// MacGuard - Anti-Theft Alarm for macOS

import SwiftUI
import AppKit

/// AppKit secure field: SwiftUI's takes no focus in borderless or freshly shown windows.
struct NativeSecureField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isEnabled = true
    var focusOnAppear = false
    var font: NSFont?
    var onSubmit: (() -> Void)?

    func makeNSView(context: Context) -> NSSecureTextField {
        let textField = NSSecureTextField()
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.bezelStyle = .roundedBezel
        if let font { textField.font = font }
        if focusOnAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                textField.window?.makeFirstResponder(textField)
            }
        }
        return textField
    }

    func updateNSView(_ nsView: NSSecureTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.isEnabled != isEnabled {
            nsView.isEnabled = isEnabled
            // Focus once when a lockout ends; on every update it would select the text
            if isEnabled { DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) } }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NativeSecureField

        init(_ parent: NativeSecureField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)), let onSubmit = parent.onSubmit else { return false }
            onSubmit()
            return true
        }
    }
}
