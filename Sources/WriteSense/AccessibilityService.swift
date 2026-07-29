import AppKit
import ApplicationServices
import Foundation

enum CaptureFailure: Error, Equatable {
    case noApplication
    case noFocusedElement
    case secureField
    case sensitiveContext
    case unsupportedField
    case unreadableText
    case emptyText

    var statusMessage: String {
        switch self {
        case .noApplication: return "No supported app detected"
        case .noFocusedElement: return "No focused text field"
        case .secureField: return "Secure field detected — blocked"
        case .sensitiveContext: return "Private browsing detected — blocked"
        case .unsupportedField: return "Unsupported text field"
        case .unreadableText: return "Text field cannot be read safely"
        case .emptyText: return "The current text field is empty"
        }
    }
}

final class AccessibilityService {
    struct Permission {
        static var isTrusted: Bool {
            AXIsProcessTrusted()
        }

        static func request() {
            // Avoid referencing the SDK's mutable global under Swift 6 strict concurrency.
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
    }

    func focusedParagraph(
        for application: NSRunningApplication? = NSWorkspace.shared.frontmostApplication
    ) -> CapturedParagraph? {
        guard case .success(let paragraph) = focusedParagraphResult(for: application) else { return nil }
        return paragraph
    }

    func focusedParagraphResult(
        for application: NSRunningApplication? = NSWorkspace.shared.frontmostApplication
    ) -> Result<CapturedParagraph, CaptureFailure> {
        guard let application,
              let bundleID = application.bundleIdentifier,
              application.processIdentifier != 0 else {
            return .failure(.noApplication)
        }

        let processIdentifier = application.processIdentifier
        let appElement = AXUIElementCreateApplication(processIdentifier)
        if isPrivateBrowsingContext(bundleID: bundleID, appElement: appElement) {
            return .failure(.sensitiveContext)
        }

        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue,
        CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return .failure(.noFocusedElement)
        }

        let element = focusedValue as! AXUIElement
        if isSecureTextElement(element) { return .failure(.secureField) }
        guard isSupportedTextElement(element) else { return .failure(.unsupportedField) }
        guard let text = stringAttribute(kAXValueAttribute, from: element) else {
            return .failure(.unreadableText)
        }

        // Terminal exposes the whole screen buffer. Only operate when it also
        // exposes a cursor/selection range, so analysis is limited to the
        // active command line. Terminal remains suggestion/copy-only.
        if bundleID == "com.apple.Terminal" && selectedRange(from: element) == nil {
            return .failure(.unsupportedField)
        }
        guard !text.isEmpty else { return .failure(.emptyText) }
        guard let range = paragraphRange(in: text, for: element) else {
            return .failure(.unreadableText)
        }

        let paragraph = (text as NSString).substring(with: range)
        guard !paragraph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.emptyText)
        }
        let appName = application.localizedName ?? bundleID
        return .success(CapturedParagraph(
            applicationName: appName,
            applicationBundleID: bundleID,
            fullText: text,
            paragraph: paragraph,
            paragraphRange: TextRange(location: range.location, length: range.length),
            element: element,
            elementFrame: frameAttribute(from: element)
        ))
    }

    func replace(_ suggestion: Suggestion, with replacement: String, in captured: CapturedParagraph) -> Bool {
        replace(
            expected: suggestion.originalText,
            with: replacement,
            at: suggestion.range,
            in: captured
        )
    }

    func replace(expected: String, with replacement: String, at range: TextRange, in captured: CapturedParagraph) -> Bool {
        // Terminal exposes rendered screen cells rather than a writable command
        // line. Never synthesize edits there; callers offer an explicit Copy
        // action instead.
        guard captured.applicationBundleID != "com.apple.Terminal",
              let currentText = stringAttribute(kAXValueAttribute, from: captured.element) else { return false }
        let paragraphRange = currentParagraphRange(in: currentText, near: captured.paragraphRange.location)
        let currentParagraph = (currentText as NSString).substring(with: paragraphRange)
        let targetRange = resolvedRange(for: expected, preferred: range.nsRange, in: currentParagraph)
        guard targetRange.location != NSNotFound else { return false }

        let fullRange = NSRange(
            location: paragraphRange.location + targetRange.location,
            length: targetRange.length
        )
        let mutable = NSMutableString(string: currentText)
        mutable.replaceCharacters(in: fullRange, with: replacement)
        let result = AXUIElementSetAttributeValue(
            captured.element,
            kAXValueAttribute as CFString,
            mutable.copy() as CFTypeRef
        )
        return result == .success
    }

    private func currentParagraphRange(in text: String, near location: Int) -> NSRange {
        let string = text as NSString
        let safeLocation = min(max(0, location), string.length)
        return string.paragraphRange(for: NSRange(location: safeLocation, length: 0))
    }

    private func resolvedRange(for expected: String, preferred: NSRange, in paragraph: String) -> NSRange {
        let string = paragraph as NSString
        if preferred.location != NSNotFound,
           preferred.location + preferred.length <= string.length,
           string.substring(with: preferred) == expected {
            return preferred
        }

        // A previous accepted suggestion may have changed the length of the
        // paragraph. Fall back to the nearest matching text instead of using a
        // stale range from the earlier review.
        var searchStart = 0
        var best = NSRange(location: NSNotFound, length: 0)
        while searchStart < string.length {
            let searchRange = NSRange(location: searchStart, length: string.length - searchStart)
            let found = string.range(of: expected, options: [], range: searchRange)
            guard found.location != NSNotFound else { break }
            if best.location == NSNotFound ||
                abs(found.location - preferred.location) < abs(best.location - preferred.location) {
                best = found
            }
            searchStart = found.location + max(found.length, 1)
        }
        return best
    }

    private func isPrivateBrowsingContext(bundleID: String, appElement: AXUIElement) -> Bool {
        let browserBundleIDs: Set<String> = ["com.apple.Safari", "com.google.Chrome"]
        guard browserBundleIDs.contains(bundleID) else { return false }

        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        ) == .success,
        let windowValue,
        CFGetTypeID(windowValue) == AXUIElementGetTypeID() else { return false }

        let window = windowValue as! AXUIElement
        let title = stringAttribute(kAXTitleAttribute, from: window)?.lowercased() ?? ""
        return title.contains("private browsing") ||
            title.contains("private window") ||
            title.contains("incognito")
    }

    private func isSecureTextElement(_ element: AXUIElement) -> Bool {
        if let role = stringAttribute(kAXRoleAttribute, from: element), role == "AXSecureTextField" {
            return true
        }
        if let subrole = stringAttribute(kAXSubroleAttribute, from: element),
           subrole.localizedCaseInsensitiveContains("secure") ||
            subrole.localizedCaseInsensitiveContains("password") {
            return true
        }
        if let password = boolAttribute("AXIsPassword", from: element), password { return true }
        return false
    }

    private func isSupportedTextElement(_ element: AXUIElement) -> Bool {
        guard let role = stringAttribute(kAXRoleAttribute, from: element) else { return false }
        let supportedRoles = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String,
            "AXSearchField"
        ]
        return supportedRoles.contains(role)
    }

    private func paragraphRange(in text: String, for element: AXUIElement) -> NSRange? {
        let nsText = text as NSString
        let location: Int
        if let selectedRange = selectedRange(from: element) {
            location = min(max(0, selectedRange.location), nsText.length)
        } else {
            location = nsText.length
        }
        return nsText.paragraphRange(for: NSRange(location: location, length: 0))
    }

    private func frameAttribute(from element: AXUIElement) -> CGRect? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgRect else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect) else { return nil }
        return rect
    }

    private func selectedRange(from element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXValueGetTypeID(),
        AXValueGetType(value as! AXValue) == .cfRange else { return nil }

        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func boolAttribute(_ attribute: String, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? Bool
    }
}
