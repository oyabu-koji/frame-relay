import Foundation
import Darwin
func accepts(_ url: URL) -> Bool {
    let normalized = url.standardizedFileURL
    return normalized.isFileURL && normalized.resolvingSymlinksInPath().path == normalized.path
}
let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
    .appendingPathComponent("S25-root-path-" + UUID().uuidString, isDirectory: true)
try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false)
let root = base.appendingPathComponent("temporary", isDirectory: true)
precondition(!FileManager.default.fileExists(atPath: root.path))
precondition(accepts(root))
print("absent-directory-path-accepted=true")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
let fd = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
precondition(fd >= 0)
var info = stat()
precondition(fstat(fd, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR)
precondition(Darwin.close(fd) == 0)
print("created-directory-open-no-follow=true")
for parent in [false, true] {
    let link = base.appendingPathComponent(parent ? "parent-link" : "root-link", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: parent ? base : root)
    let candidate = parent ? link.appendingPathComponent("temporary", isDirectory: true) : link
    precondition(!accepts(candidate))
    print("symlink-\(parent ? "parent" : "root")-rejected=true")
}
