import Foundation
import RoseCore

func runJustifiedLayoutChecks() throws {
    let ratios = [0.74, 0.56, 0.75, 1.5, 0.79, 0.56, 0.67, 0.66, 0.56, 0.56, 0.56, 0.67]
    let layout = JustifiedLayout.calculate(aspectRatios: ratios, containerWidth: 1000, targetRowHeight: 210)
    let tolerance: CGFloat = 0.00001

    func preservesRatios(_ result: JustifiedGeometry, ratios: [Double]) -> Bool {
        zip(result.frames, ratios).allSatisfy { frame, ratio in
            let imageWidth = frame.width - JustifiedLayout.cardHorizontalPadding
            let imageHeight = frame.height - JustifiedLayout.cardExtraHeight
            return imageHeight > 0 && abs(imageWidth / imageHeight - CGFloat(ratio)) < tolerance
        }
    }

    func staysInside(_ result: JustifiedGeometry) -> Bool {
        result.frames.allSatisfy { frame in
            frame.minX >= JustifiedLayout.inset - tolerance && frame.maxX <= result.contentSize.width - JustifiedLayout.inset + tolerance
                && frame.minY >= 0 && frame.maxY <= result.contentSize.height + tolerance
                && frame.width.isFinite && frame.height.isFinite && frame.width > 0 && frame.height > 0
        }
    }

    try check("Justified Fit retains every image in source order", layout.frames.count == ratios.count && layout.rows.flatMap { Array($0.items) } == Array(ratios.indices))
    try check("Fit cards preserve image proportions inside the caption and border", preservesRatios(layout, ratios: ratios))
    try check("Justified rows stay within the scrollable content", staysInside(layout))
    try check("Each row uses a shared image height", layout.rows.allSatisfy { row in row.items.allSatisfy { abs(layout.frames[$0].height - row.frame.height) < tolerance } })
    try check("Complete Fit rows span the available width", layout.rows.dropLast().allSatisfy { abs($0.frame.maxX - (1000 - JustifiedLayout.inset)) < tolerance })

    var overlaps = false
    for i in layout.frames.indices {
        for j in layout.frames.indices where j > i {
            if layout.frames[i].intersects(layout.frames[j]) { overlaps = true }
        }
    }
    try check("Captions and thumbnail cards never overlap", !overlaps)
    try check("Row spacing leaves captions separate from the following row", zip(layout.rows, layout.rows.dropFirst()).allSatisfy { abs($1.frame.minY - $0.frame.maxY - JustifiedLayout.verticalGap) < tolerance })

    let comparison = JustifiedLayout.calculate(aspectRatios: [0.5, 1.5, 0.75], containerWidth: 800, targetRowHeight: 200)
    try check("Landscape sheets receive proportionally wider cards", abs((comparison.frames[1].width - 8) / (comparison.frames[0].width - 8) - 3) < tolerance)
    let single = JustifiedLayout.calculate(aspectRatios: [0.5], containerWidth: 1400, targetRowHeight: 200)
    try check("A lone final portrait does not grow to fill the window", abs(single.frames[0].height - 235) < tolerance && single.frames[0].width < 200)
    try check("The last incomplete row stays at or below the target height", layout.rows.last.map { $0.frame.height <= 210 + JustifiedLayout.cardExtraHeight + tolerance } == true)
    let panorama = JustifiedLayout.calculate(aspectRatios: [10], containerWidth: 500, targetRowHeight: 200)
    try check("A wide panorama fits without overflowing or cropping", staysInside(panorama) && preservesRatios(panorama, ratios: [10]) && abs(panorama.frames[0].maxX - 496) < tolerance)

    let empty = JustifiedLayout.calculate(aspectRatios: [], containerWidth: 800, targetRowHeight: 200)
    try check("An empty Fit view has no phantom rows or scroll height", empty.frames.isEmpty && empty.rows.isEmpty && empty.contentSize.height == 0)
    let invalid = JustifiedLayout.calculate(aspectRatios: [0, -1, .nan, .infinity], containerWidth: 800, targetRowHeight: 200)
    try check("Invalid cached dimensions use safe square placeholders", invalid.frames.count == 4 && staysInside(invalid) && preservesRatios(invalid, ratios: [1, 1, 1, 1]))
    try check("Invalid viewport dimensions return a safe empty layout", JustifiedLayout.calculate(aspectRatios: [1], containerWidth: 0, targetRowHeight: 200).frames.isEmpty && JustifiedLayout.calculate(aspectRatios: [1], containerWidth: 800, targetRowHeight: 0).frames.isEmpty)

    let resized = [120, 320, 540, 780, 1040, 1400].map { width in
        JustifiedLayout.calculate(aspectRatios: ratios, containerWidth: CGFloat(width), targetRowHeight: 210)
    }
    try check("Resizing keeps all Fit images inside the new window width", resized.allSatisfy { $0.frames.count == ratios.count && staysInside($0) })
    try check("Window resizing preserves image proportions and ordering", resized.allSatisfy { preservesRatios($0, ratios: ratios) && $0.rows.flatMap { Array($0.items) } == Array(ratios.indices) })
    try check("Layout is deterministic before thumbnail decoding", layout.frames == JustifiedLayout.calculate(aspectRatios: ratios, containerWidth: 1000, targetRowHeight: 210).frames)

    let manyRatios = (0..<10_000).map { ratios[$0 % ratios.count] }
    let large = JustifiedLayout.calculate(aspectRatios: manyRatios, containerWidth: 1100, targetRowHeight: 200)
    let viewport = CGRect(x: 0, y: large.contentSize.height / 2, width: 1100, height: 650)
    let visible = large.visibleItems(in: viewport)
    let expected = large.frames.enumerated().compactMap { $0.element.intersects(viewport) ? $0.offset : nil }
    try check("Viewport queries match visible geometry in a 10,000-image layout", visible == expected && !visible.isEmpty)
    try check("Virtualized Fit queries return only nearby images", visible.count < 100 && large.frames.count == manyRatios.count)
    let tail = CGRect(x: 0, y: max(0, large.contentSize.height - 500), width: 1100, height: 500)
    try check("The final images remain reachable by scrolling", large.visibleItems(in: tail).contains(manyRatios.count - 1))
}
