import AppKit
import RoseCore

/// NSCollectionView still owns cell reuse, selection, hit testing, and keyboard navigation.
/// This layout supplies ordered variable-width rows and queries only visible geometry.
final class JustifiedCollectionLayout: NSCollectionViewLayout {
    private var aspectRatios: [Double] = []
    private var width: CGFloat = 100
    private var targetHeight: CGFloat = 213
    private var geometryDirty = true
    private var geometry = JustifiedLayout.calculate(aspectRatios: [], containerWidth: 100, targetRowHeight: 213)

    func setAspectRatios(_ values: [Double]) {
        guard aspectRatios != values else { return }
        aspectRatios = values
        geometryDirty = true
        invalidateLayout()
    }

    func configure(width: CGFloat, targetHeight: CGFloat) {
        guard self.width != width || self.targetHeight != targetHeight else { return }
        self.width = width; self.targetHeight = targetHeight
        geometryDirty = true
        invalidateLayout()
    }

    override func prepare() {
        super.prepare()
        guard geometryDirty else { return }
        geometry = JustifiedLayout.calculate(aspectRatios: aspectRatios, containerWidth: width, targetRowHeight: targetHeight)
        geometryDirty = false
    }

    override var collectionViewContentSize: NSSize {
        if geometryDirty { prepare() }
        return geometry.contentSize
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        if geometryDirty { prepare() }
        return geometry.visibleItems(in: rect).compactMap { layoutAttributesForItem(at: IndexPath(item: $0, section: 0)) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        if geometryDirty { prepare() }
        guard indexPath.section == 0, geometry.frames.indices.contains(indexPath.item) else { return nil }
        let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
        attributes.frame = geometry.frames[indexPath.item]
        return attributes
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        // Scrolling vertically does not change the row geometry.
        abs(newBounds.width - width) > 0.5
    }
}
