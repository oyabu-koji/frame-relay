import Foundation

/// Separate atomic settings file; loading an unknown/corrupt document never overwrites it.
actor CapturePreferenceStore: ProductCapturePreferencePort {
    private struct Document: Codable {
        let schema: Int
        let preferences: ProductCapturePreferences
    }
    private let url: URL
    init(url: URL) { self.url = url }

    func load() throws -> ProductCapturePreferences {
        guard FileManager.default.fileExists(atPath: url.path) else { return .init() }
        let data = try Data(contentsOf: url)
        struct Header: Decodable { let schema: Int }
        let header: Header
        do { header = try JSONDecoder().decode(Header.self, from: data) }
        catch { throw ProductCapturePreferenceError.corruptStore }
        guard header.schema == 1 else { throw ProductCapturePreferenceError.unknownSchema }
        let document: Document
        do { document = try JSONDecoder().decode(Document.self, from: data) }
        catch { throw ProductCapturePreferenceError.corruptStore }
        guard document.preferences.isValid else { throw ProductCapturePreferenceError.invalidSettings }
        return document.preferences
    }

    func save(_ preferences: ProductCapturePreferences) throws {
        guard preferences.isValid else { throw ProductCapturePreferenceError.invalidSettings }
        if FileManager.default.fileExists(atPath: url.path) { _ = try load() }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Document(schema: 1, preferences: preferences))
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
