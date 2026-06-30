import AppKit
import ApplicationServices
import Foundation

func stringifyValue(_ value: Any?) -> String {
    guard let value else {
        return ""
    }

    if let string = value as? String {
        return string
    }
    if let number = value as? NSNumber {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? "1" : "0"
        }
        return number.stringValue
    }
    if let url = value as? URL {
        return url.absoluteString
    }
    if containsAXElement(value) {
        return ""
    }
    if let axValue = cuAXValue(from: value) {
        switch AXValueGetType(axValue) {
        case .cgPoint:
            var point = CGPoint.zero
            guard AXValueGetValue(axValue, .cgPoint, &point) else {
                return ""
            }
            return NSStringFromPoint(point)
        case .cgSize:
            var size = CGSize.zero
            guard AXValueGetValue(axValue, .cgSize, &size) else {
                return ""
            }
            return NSStringFromSize(size)
        case .cfRange:
            var range = CFRange()
            guard AXValueGetValue(axValue, .cfRange, &range) else {
                return ""
            }
            return "{\(range.location), \(range.length)}"
        default:
            return ""
        }
    }
    return String(describing: value)
}

func stringValueOrNil(_ value: Any?) -> String? {
    let valueString = stringifyValue(value)
    return valueString.isEmpty ? nil : valueString
}

private func containsAXElement(_ value: Any) -> Bool {
    if cuAXElement(from: value) != nil {
        return true
    }
    guard let array = value as? NSArray else {
        return false
    }
    return array.contains { item in
        cuAXElement(from: item) != nil
    }
}

func describeValueType(_ value: Any?) -> String? {
    guard let value else {
        return nil
    }
    if value is String {
        return "string"
    }
    if let number = value as? NSNumber {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return "bool"
        }
        if CFNumberIsFloatType(number) {
            return "float"
        }
        return "int"
    }
    return nil
}

func nearlyEqualRects(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 2) -> Bool {
    abs(lhs.origin.x - rhs.origin.x) <= tolerance &&
        abs(lhs.origin.y - rhs.origin.y) <= tolerance &&
        abs(lhs.width - rhs.width) <= tolerance &&
        abs(lhs.height - rhs.height) <= tolerance
}
