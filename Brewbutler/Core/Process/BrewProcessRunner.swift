import Foundation

public struct BrewProcessRunner: ProcessRunning {
    public init() {}

    public func run(
        _ request: ProcessRequest,
        onEvent: @escaping @Sendable (ProcessEvent) -> Void
    ) async throws -> ProcessResult {
        let process = try SpawnedProcess.launch(request)
        return await withTaskCancellationHandler {
            await process.wait(onEvent: onEvent)
        } onCancel: {
            process.terminate()
        }
    }
}
