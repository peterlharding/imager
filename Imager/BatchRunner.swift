import AppKit
import Observation

/// Runs a batch, reporting progress and staying cancellable.
///
/// The per-image work happens off the main thread in `BatchProcessor`; this type owns only
/// the observable progress and the cancellation. Sequential rather than parallel, so a
/// folder of 24 MP files cannot balloon memory, and the disk is the limit anyway.
@Observable
@MainActor
final class BatchRunner {

    struct Failure: Identifiable {
        let source: URL
        let message: String
        var id: String { source.path }
        var name: String { source.lastPathComponent }
    }

    struct Summary {
        var written = 0
        var failures: [Failure] = []
        var wasCancelled = false
    }

    private(set) var isRunning = false
    private(set) var completed = 0
    private(set) var total = 0
    private(set) var currentName: String?

    /// Set when a run finishes, is cancelled, or ends with failures.
    private(set) var summary: Summary?

    @ObservationIgnored private var task: Task<Void, Never>?

    var progress: Double {
        total > 0 ? Double(completed) / Double(total) : 0
    }

    // MARK: - Running

    func start(sources: [URL], edits: [ImageEdit], format: BatchFormat, destination: URL) {
        guard !isRunning, !sources.isEmpty else { return }

        isRunning = true
        completed = 0
        total = sources.count
        currentName = nil
        summary = nil

        task = Task { [weak self] in
            // The destination came from an open panel, which grants write access; hold it
            // for the whole run rather than per file.
            let scoped = destination.startAccessingSecurityScopedResource()
            defer { if scoped { destination.stopAccessingSecurityScopedResource() } }

            var result = Summary()

            for source in sources {
                if Task.isCancelled {
                    result.wasCancelled = true
                    break
                }
                self?.currentName = source.lastPathComponent

                // The heavy work - decode, filter, encode, write - off the main thread.
                let outcome = await Task.detached(priority: .userInitiated) {
                    BatchProcessor.process(
                        source: source, edits: edits, format: format, destination: destination
                    )
                }.value

                switch outcome {
                case .success:
                    result.written += 1
                case .failure(let failure):
                    result.failures.append(Failure(source: source, message: failure.message))
                }
                self?.completed += 1
            }

            self?.currentName = nil
            self?.isRunning = false
            self?.summary = result
        }
    }

    /// Stops after the image in flight. Cancelling mid-image is not worth the complexity:
    /// one image takes tens of milliseconds.
    func cancel() {
        task?.cancel()
    }

    func reset() {
        guard !isRunning else { return }
        summary = nil
        completed = 0
        total = 0
        currentName = nil
    }
}
