import Foundation
import Observation

@MainActor @Observable final class ProductComposition {
    private let factory: ProductLibraryFactory
    private(set) var library: LibraryModel?
    private(set) var playback: OriginalPlaybackModel?
    private(set) var isOpening = false
    private(set) var openingIssue: String?
    let exploration = ExplorationComposition.makeModel()

    init(factory: ProductLibraryFactory = .shared) { self.factory = factory }

    func open() async {
        guard library == nil, !isOpening else { return }
        isOpening = true
        defer { isOpening = false }
        do {
            let services = try await factory.open()
            let player = OriginalPlaybackModel(playback: AVOriginalPlayback(access: services.access))
            playback = player
            library = LibraryModel(reader: services.reader, commands: OriginalPlaybackLibraryCommands(model: player))
            openingIssue = nil
            await library?.refresh()
        } catch {
            openingIssue = "保存記録を開けません。既存の記録と原本は保持しています。再試行しても開けない場合は、保存領域の状態を確認してください。"
        }
    }

    func enteredBackground() async {
        await playback?.stop()
        await exploration.stop()
    }

    func presentationEnded() async { await library?.refresh() }
}
