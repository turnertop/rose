import Foundation

public struct JustifiedRow {
    public let items: Range<Int>
    public let frame: CGRect
}

public struct JustifiedGeometry {
    public let frames: [CGRect]
    public let rows: [JustifiedRow]
    public let contentSize: CGSize

    /// Returns only rows intersecting the viewport, keeping scrolling work bounded.
    public func visibleItems(in rect: CGRect) -> [Int] {
        guard !rows.isEmpty, !rect.isEmpty else { return [] }
        var low = 0, high = rows.count
        while low < high {
            let middle = (low + high) / 2
            if rows[middle].frame.maxY <= rect.minY { low = middle + 1 }
            else { high = middle }
        }
        var indices: [Int] = []
        for row in rows.dropFirst(low) {
            if row.frame.minY >= rect.maxY { break }
            for index in row.items where frames[index].intersects(rect) { indices.append(index) }
        }
        return indices
    }
}

/// Calculates native-aspect thumbnail rows using metadata, before any images decode.
public enum JustifiedLayout {
    public static let inset: CGFloat = 4
    public static let horizontalGap: CGFloat = 10
    public static let verticalGap: CGFloat = 13
    public static let cardHorizontalPadding: CGFloat = 8
    public static let cardExtraHeight: CGFloat = 35

    public static func calculate(aspectRatios: [Double], containerWidth: CGFloat,
                                 targetRowHeight: CGFloat) -> JustifiedGeometry {
        let empty = JustifiedGeometry(frames: [], rows: [], contentSize: CGSize(width: max(0, containerWidth.isFinite ? containerWidth : 0), height: 0))
        guard !aspectRatios.isEmpty, containerWidth.isFinite, targetRowHeight.isFinite,
              containerWidth > 2 * inset + cardHorizontalPadding, targetRowHeight > 0 else { return empty }
        let ratios: [CGFloat] = aspectRatios.map {
            $0.isFinite && $0 > 0 ? CGFloat(min($0, 1_000_000)) : 1
        }
        let available = containerWidth - 2 * inset
        var frames: [CGRect] = []
        frames.reserveCapacity(ratios.count)
        var rows: [JustifiedRow] = []
        var start = 0
        var y = inset

        func height(count: Int, sum: CGFloat) -> CGFloat {
            (available - CGFloat(count) * cardHorizontalPadding - CGFloat(count - 1) * horizontalGap) / sum
        }

        while start < ratios.count {
            var end = start
            var sum: CGFloat = 0
            var rowHeight = targetRowHeight
            while end < ratios.count {
                sum += ratios[end]
                end += 1
                let count = end - start
                let fullHeight = height(count: count, sum: sum)
                if fullHeight <= targetRowHeight {
                    if count > 1 {
                        let previousSum = sum - ratios[end - 1]
                        let previousHeight = height(count: count - 1, sum: previousSum)
                        if fullHeight <= 0 || abs(previousHeight - targetRowHeight) < abs(fullHeight - targetRowHeight) {
                            end -= 1
                            sum = previousSum
                            rowHeight = previousHeight
                            break
                        }
                    }
                    rowHeight = fullHeight
                    break
                }
                if end == ratios.count {
                    // An incomplete last row stays left-aligned at the target size.
                    rowHeight = min(targetRowHeight, fullHeight)
                }
            }

            var x = inset
            for index in start..<end {
                let width = ratios[index] * rowHeight + cardHorizontalPadding
                frames.append(CGRect(x: x, y: y, width: width, height: rowHeight + cardExtraHeight))
                x += width + horizontalGap
            }
            rows.append(JustifiedRow(items: start..<end,
                frame: CGRect(x: inset, y: y, width: max(0, x - horizontalGap - inset), height: rowHeight + cardExtraHeight)))
            y += rowHeight + cardExtraHeight + verticalGap
            start = end
        }
        return JustifiedGeometry(frames: frames, rows: rows,
            contentSize: CGSize(width: containerWidth, height: y - verticalGap + inset))
    }
}
