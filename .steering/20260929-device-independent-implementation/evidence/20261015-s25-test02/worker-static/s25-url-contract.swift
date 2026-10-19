import Foundation
let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
    .appendingPathComponent("S25-url-contract-" + UUID().uuidString, isDirectory: true)
try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false)
let supplied = base.appendingPathComponent("temporary", isDirectory: true)
let normalized = supplied.standardizedFileURL
let resolved = normalized.resolvingSymlinksInPath()
print("supplied=\(supplied.absoluteString)")
print("normalized=\(normalized.absoluteString)")
print("resolved=\(resolved.absoluteString)")
print("existingGuard=\(resolved == normalized)")
let canonical = resolved.standardizedFileURL
print("canonicalGuard=\(canonical.resolvingSymlinksInPath() == canonical)")
try FileManager.default.createDirectory(at: supplied, withIntermediateDirectories: false)
print("createdGuard=\(normalized.resolvingSymlinksInPath() == normalized)")
