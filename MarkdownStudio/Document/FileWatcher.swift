import Foundation

/// Watches a file for changes made by other apps. Handles editors that save
/// atomically (write a new file and rename it over the old one) by re-opening
/// the watch after a delete or rename.
final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    nonisolated(unsafe) private var source: DispatchSourceFileSystemObject?
    private var pendingNotify: DispatchWorkItem?
    private var retries = 0

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        start()
    }

    deinit {
        source?.cancel()
    }

    private func start() {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            // The file may be mid-replace; try again shortly.
            guard retries < 20 else { return }
            retries += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.start() }
            return
        }
        retries = 0
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self, unowned source] in
            let events = source.data
            MainActor.assumeIsolated {
                guard let self else { return }
                if events.contains(.delete) || events.contains(.rename) { self.restart() }
                self.scheduleNotify()
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    private func restart() {
        source?.cancel()
        source = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.start() }
    }

    /// Coalesces the burst of events a single save produces.
    private func scheduleNotify() {
        pendingNotify?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pendingNotify = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}
