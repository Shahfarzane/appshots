import ApplicationServices
import CoreGraphics
import Foundation

func stableRectString(_ rect: CGRect) -> String {
    "\(round(rect.origin.x * 100) / 100),\(round(rect.origin.y * 100) / 100),\(round(rect.width * 100) / 100),\(round(rect.height * 100) / 100)"
}

func stableFingerprintValue(for node: RuntimeAXNode) -> String {
    if node.role == kAXStaticTextRole as String {
        return ""
    }

    if node.isValueSettable {
        return stringifyValue(node.value)
    }

    let valueRelevantRoles: Set<String> = [
        kAXCheckBoxRole as String,
        kAXRadioButtonRole as String,
        kAXSliderRole as String,
        kAXScrollBarRole as String,
    ]
    switch node.role {
    case let role where valueRelevantRoles.contains(role):
        return stringifyValue(node.value)
    default:
        return ""
    }
}

func stableFingerprintURL(for node: RuntimeAXNode) -> String {
    guard node.role == kAXTextFieldRole as String else {
        return ""
    }
    return node.url?.absoluteString ?? ""
}

func parentIndicesFromDepths(_ depths: [Int]) -> [Int?] {
    var parents: [Int?] = Array(repeating: nil, count: depths.count)
    var stack: [Int] = []
    for i in 0 ..< depths.count {
        while let top = stack.last, depths[top] >= depths[i] {
            stack.removeLast()
        }
        parents[i] = stack.last
        stack.append(i)
    }
    return parents
}

func childIndicesAmongSameRole(
    roles: [String],
    subroles: [String],
    parents: [Int?]
) -> [Int] {
    var counts: [Int: [String: Int]] = [:]
    var result: [Int] = Array(repeating: 0, count: roles.count)
    for i in 0 ..< roles.count {
        let parentKey = parents[i] ?? -1
        let bucketKey = "\(roles[i])|\(subroles[i])"
        let next = counts[parentKey, default: [:]][bucketKey, default: 0]
        result[i] = next
        counts[parentKey, default: [:]][bucketKey] = next + 1
    }
    return result
}

func nodeSignatures(for nodes: [RuntimeAXNode]) -> [CachedNodeSignature] {
    let depths = nodes.map(\.depth)
    let roles = nodes.map(\.role)
    let subroles = nodes.map(\.subrole)
    let parents = parentIndicesFromDepths(depths)
    let childIndices = childIndicesAmongSameRole(
        roles: roles,
        subroles: subroles,
        parents: parents
    )
    return nodes.enumerated().map { i, node in
        CachedNodeSignature(
            depth: node.depth,
            role: node.role,
            subrole: node.subrole,
            title: node.title,
            description: node.description.isEmpty ? nil : node.description,
            identifier: node.identifier,
            childIndexAmongSameRole: childIndices[i]
        )
    }
}
