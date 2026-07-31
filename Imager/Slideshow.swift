import AppKit
import Observation

/// Persisted slideshow preferences, edited in Settings ▸ General.
enum SlideshowSetting {
    static let intervalKey = "slideshow.interval"
    static let loopKey = "slideshow.loop"

    static let defaultInterval: Double = 4
    static let minInterval: Double = 1
    static let maxInterval: Double = 60
    static let defaultLoop = true
}

/// Advances through the folder currently being browsed on a timer.
///
/// Deliberately separate from `ImageModel`: the timer only ever calls `advance()`,
/// so the wrap-around and stopping rules can be exercised directly without waiting
/// on real time or running a window.
@Observable
final class Slideshow {
    private(set) var isRunning = false

    @ObservationIgnored private let model: ImageModel
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var sleepAssertion: NSObjectProtocol?

    init(model: ImageModel, defaults: UserDefaults = .standard) {
        self.model = model
        self.defaults = defaults
    }

    deinit {
        timer?.invalidate()
        if let sleepAssertion { ProcessInfo.processInfo.endActivity(sleepAssertion) }
    }

    // MARK: - Preferences

    /// Seconds between images, clamped to the supported range.
    /// An unset or out-of-range stored value falls back to the default.
    var interval: Double {
        let stored = defaults.double(forKey: SlideshowSetting.intervalKey)
        guard stored > 0 else { return SlideshowSetting.defaultInterval }
        return min(max(stored, SlideshowSetting.minInterval), SlideshowSetting.maxInterval)
    }

    /// Whether to wrap around after the last image rather than stopping.
    var loops: Bool {
        defaults.object(forKey: SlideshowSetting.loopKey) as? Bool ?? SlideshowSetting.defaultLoop
    }

    // MARK: - Running

    /// True when there is a folder of more than one image to run through.
    var canStart: Bool { model.canBrowse }

    func toggle() { isRunning ? stop() : start() }

    func start() {
        guard canStart, !isRunning else { return }
        isRunning = true
        keepDisplayAwake()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.advance()
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        timer?.invalidate()
        timer = nil
        allowDisplaySleep()
    }

    /// Moves to the next image, wrapping or stopping at the end.
    ///
    /// Runs on picks: a show is a sequence of pictures, not of every frame taken to get them.
    ///
    /// Stops rather than advancing when the current image has unsaved edits, so a
    /// running show can never raise the discard confirmation or lose work.
    func advance() {
        guard isRunning else { return }
        guard !model.hasUnsavedEdits else { return stop() }

        let picks = model.pickImages
        guard picks.count > 1,
              let index = model.selectionIndex, model.folderImages.indices.contains(index) else {
            return stop()
        }
        // Showing a frame inside an expanded stack: rejoin the sequence at that stack's pick.
        let showing = model.folderImages[index]
        let here = picks.firstIndex(of: showing)
            ?? model.stack(containing: showing).flatMap { stack in
                picks.firstIndex { $0.lastPathComponent == stack.pick }
            }
        guard let here else { return stop() }

        let next = here + 1
        if next < picks.count {
            model.select(picks[next])
        } else if loops {
            model.select(picks[0])
        } else {
            stop()
        }
    }

    // MARK: - Display sleep

    private func keepDisplayAwake() {
        guard sleepAssertion == nil else { return }
        sleepAssertion = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .userInitiated],
            reason: "Imager slideshow"
        )
    }

    private func allowDisplaySleep() {
        guard let sleepAssertion else { return }
        ProcessInfo.processInfo.endActivity(sleepAssertion)
        self.sleepAssertion = nil
    }
}
