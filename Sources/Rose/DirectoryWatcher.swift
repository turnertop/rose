import Foundation
import CoreServices

/// FSEvents observes every nested directory; the model coalesces bursts before scanning.
final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: ([String]) -> Void

    init(urls: [URL], onChange: @escaping ([String]) -> Void) {
        self.onChange = onChange
        guard !urls.isEmpty else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot)
        stream = FSEventStreamCreate(kCFAllocatorDefault, { _, info, _, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            let changed = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            watcher.onChange(changed)
        }, &context, urls.map(\.path) as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.35, flags)
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
        }
    }

    deinit {
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
    }
}
