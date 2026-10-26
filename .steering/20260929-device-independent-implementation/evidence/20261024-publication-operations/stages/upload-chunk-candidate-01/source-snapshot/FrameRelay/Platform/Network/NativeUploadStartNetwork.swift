/// Shares the native default-route observation with Photos. This small adapter
/// grants no transport capability and never constructs an upload SDK owner.
nonisolated struct NativeUploadStartNetwork: OriginalUploadStartNetworkPort {
    private let observation: any PhotoSaveStartNetworkPort
    init(observation: any PhotoSaveStartNetworkPort) { self.observation = observation }
    func currentCondition() -> NetworkCondition { observation.currentCondition() }
}
