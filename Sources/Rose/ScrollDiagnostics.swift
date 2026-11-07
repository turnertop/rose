import AppKit
import QuartzCore
import os
import RoseImaging

/// Opt-in callback-gap measurements; this never records the screen or image filenames.
@MainActor
final class ScrollDiagnostics: NSObject {
    static let enabled = ProcessInfo.processInfo.environment["ROSE_PERFORMANCE_LOG"] == "1"
    private let logger = Logger(subsystem: "app.rose.imagevault", category: "scroll")
    private var link: CADisplayLink?
    private var target: TickTarget?
    private var lastScroll = 0.0
    private var previousTick = 0.0
    private var ticks = 0
    private var delayed = 0
    private var maxGap = 0.0
    private var initial = ThumbnailMetrics()

    @MainActor private final class TickTarget: NSObject {
        weak var owner: ScrollDiagnostics?
        @objc func tick(_ sender: CADisplayLink) {
            guard let owner else { sender.invalidate(); return }
            owner.tick(sender)
        }
    }

    deinit { link?.invalidate() }

    func recordScroll(in view: NSView) {
        lastScroll = ProcessInfo.processInfo.systemUptime
        guard link == nil else { return }
        ticks = 0; delayed = 0; maxGap = 0; previousTick = 0
        initial = ThumbnailService.shared.metrics()
        let target = TickTarget(); target.owner = self; self.target = target
        let displayLink = view.displayLink(target: target, selector: #selector(TickTarget.tick(_:)))
        link = displayLink
        displayLink.add(to: .main, forMode: .common)
    }

    @objc private func tick(_ sender: CADisplayLink) {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastScroll > 0.3 {
            sender.invalidate(); link = nil; target = nil
            let current = ThumbnailService.shared.metrics()
            let summary = String(format: "scroll callback ticks=%d delayed=%d max_gap_ms=%.1f memory=%d disk=%d source=%d decode_ms=%.1f cancelled=%d pending=%d",
                ticks, delayed, maxGap * 1000, current.memoryHits - initial.memoryHits,
                current.diskHits - initial.diskHits, current.sourceDecodes - initial.sourceDecodes,
                current.decodeMilliseconds - initial.decodeMilliseconds,
                current.cancelled - initial.cancelled, current.pendingJobs)
            logger.notice("\(summary, privacy: .public)")
            return
        }
        if previousTick > 0 {
            let gap = now - previousTick
            maxGap = max(maxGap, gap)
            if gap > max(0.025, sender.duration * 1.5) { delayed += 1 }
        }
        previousTick = now; ticks += 1
    }
}
