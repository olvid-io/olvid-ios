/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
 *
 *  This file is part of Olvid for iOS.
 *
 *  Olvid is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License, version 3,
 *  as published by the Free Software Foundation.
 *
 *  Olvid is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with Olvid.  If not, see <https://www.gnu.org/licenses/>.
 */

import UIKit

final class ObvCollectionViewLayout: UICollectionViewLayout {
    
    private var needsInitialPrepare = true
    
    private var largestSectionWithValidOrigin: Int? = nil
    private var cachedSectionInfos = [ObvCollectionViewLayoutSectionInfos]()
    private var cachedSupplementaryViewInfos = [ObvCollectionViewLayoutSupplementaryViewInfos]()
    private var cachedItemInfos = [[ObvCollectionViewLayoutItemInfos]]()
    
    private(set) var knownCollectionViewSafeAreaWidth: CGFloat = CGFloat.zero // Computed later
    private var availableWidth: CGFloat = 0.0 // Computed later
    private var sectionWidth: CGFloat = 0.0 // Computed later
    private var sectionXOrigin: CGFloat = 0.0 // Computed later
    private let defaultHeightForSupplementaryView: CGFloat = 20.0
    private let defaultHeightForCell: CGFloat = 59.0
    private let defaultSectionXOrigin: CGFloat = 10.0
    
    var interitemSpacing: CGFloat = 10
    var spaceBetweenSections: CGFloat = 10
    
    weak var delegate: ObvCollectionViewLayoutDelegate?
    
    var deletedIndexPathBeforeUpdate = [IndexPath]()
    var deletedSectionsBeforeUpdate = IndexSet()
    var insertedSectionsAfterUpdate = IndexSet()
    var insertedIndexPathsAfterUpdate = [IndexPath]()
    var movedIndexPaths = [IndexPath: IndexPath]()
    
    var indexPathOfPinnedHeader: IndexPath? = nil
    var sectionHeadersPinToVisibleBounds = true
    
}


// MARK: - Preparing & reseting the layout, returning the content size

extension ObvCollectionViewLayout {
    
    override func prepare() {
        guard let collectionView = collectionView else { return }
        
        guard !needsInitialPrepare else {
            initialPrepare(collectionView: collectionView)
            needsInitialPrepare = false
            return
        }
        
        updateCache()
        
    }
    
    
    func reset() {
        needsInitialPrepare = true
    }
    
    
    private func initialPrepare(collectionView: UICollectionView, forBoundsChange newBounds: CGRect? = nil) {
        
        debugPrint("🥶 Layout considers safeAreaInsets: \(collectionView.safeAreaInsets)")
        knownCollectionViewSafeAreaWidth = (newBounds ?? collectionView.bounds).inset(by: collectionView.safeAreaInsets).width
        
        availableWidth = knownCollectionViewSafeAreaWidth
        sectionXOrigin = defaultSectionXOrigin
        sectionWidth = availableWidth - 2 * defaultSectionXOrigin
        
        // Reset cached information.
        cachedSectionInfos.removeAll()
        cachedSupplementaryViewInfos.removeAll()
        cachedItemInfos.removeAll()
        
        var previousSectionFrame = CGRect.zero
        
        for section in 0..<collectionView.numberOfSections {
            
            // Cache estimated infos for this section
            
            do {
                let topSpace = spaceBetweenSections
                let origin = CGPoint(x: sectionXOrigin, y: previousSectionFrame.maxY + topSpace)
                assert(collectionView.numberOfItems(inSection: section) > 0)
                let sectionHeight = defaultHeightForSupplementaryView + CGFloat(collectionView.numberOfItems(inSection: section)) * (defaultHeightForCell + interitemSpacing)
                let size = CGSize(width: sectionWidth, height: sectionHeight)
                let frame = CGRect(origin: origin, size: size)
                let sectionInfos = ObvCollectionViewLayoutSectionInfos(frame: frame, largestItemWithValidOrigin: collectionView.numberOfItems(inSection: section)-1)
                cachedSectionInfos.append(sectionInfos)
                
                previousSectionFrame = frame
            }
            
            // Cache estimated infos for the supplementary view of this section
            
            let supplementaryViewFrame: CGRect
            
            do {
                let origin = CGPoint.zero
                let size = CGSize(width: sectionWidth, height: defaultHeightForSupplementaryView)
                supplementaryViewFrame = CGRect(origin: origin, size: size)
                let svInfos = ObvCollectionViewLayoutSupplementaryViewInfos(frameInSection: supplementaryViewFrame)
                cachedSupplementaryViewInfos.append(svInfos)
            }
            
            // Cache estimated infos for all the items within this section
            
            var cachedItemInfosInSection = [ObvCollectionViewLayoutItemInfos]()
            var previousElementFrame = supplementaryViewFrame
            
            for _ in 0..<collectionView.numberOfItems(inSection: section) {
                
                let topSpace = interitemSpacing
                let origin = CGPoint(x: 0, y: previousElementFrame.maxY + topSpace)
                let height = defaultHeightForCell
                let size = CGSize(width: sectionWidth, height: height)
                let frame = CGRect(origin: origin, size: size)
                let itemInfos = ObvCollectionViewLayoutItemInfos(frameInSection: frame)
                cachedItemInfosInSection.append(itemInfos)
                
                previousElementFrame = frame
                
            }
            
            cachedItemInfos.append(cachedItemInfosInSection)
            
        }
        
        if collectionView.numberOfSections > 0 {
            largestSectionWithValidOrigin = collectionView.numberOfSections-1
        }
        
        if collectionView.bounds.height < collectionViewContentSize.height {
            collectionView.contentOffset = CGPoint(x: 0, y: collectionViewContentSize.height - collectionView.bounds.height)
        }
        
    }
    
    
    override var collectionViewContentSize: CGSize {
        guard !cachedSectionInfos.isEmpty else { return .zero }
        adjustOriginOfLayoutSectionInfos(untilSection: cachedSectionInfos.count-1)
        guard let lastSectionFrame = cachedSectionInfos.last?.frame else { return .zero }
        return CGSize(width: sectionWidth, height: lastSectionFrame.maxY)
    }
    
}


// MARK: - Deciding and processing layout invalidation

extension ObvCollectionViewLayout {

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView = collectionView else { return false }
        if sectionHeadersPinToVisibleBounds {
            return !newBounds.equalTo(collectionView.bounds)
        } else {
            return !newBounds.size.equalTo(collectionView.bounds.size)
        }
    }
    
    
    override func shouldInvalidateLayout(forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes, withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes) -> Bool {
        if preferredAttributes.frame == originalAttributes.frame {
            return false
        } else {
            return true
        }
    }
    
}


// MARK: - Returning invalidation context

extension ObvCollectionViewLayout {
    
    override func invalidationContext(forBoundsChange newBounds: CGRect) -> UICollectionViewLayoutInvalidationContext {
        let context = super.invalidationContext(forBoundsChange: newBounds)
        if let collectionView = self.collectionView,
            newBounds.width != collectionView.bounds.width {
            initialPrepare(collectionView: collectionView, forBoundsChange: newBounds)
        }
        return context
    }
    
}


// MARK: - Returning layout attributes

extension ObvCollectionViewLayout {
    
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        adjustOriginOfLayoutSectionInfos(untilSection: indexPath.section)
        adjustOriginOfLayoutItemInfos(at: indexPath)
        
        let sectionInfos = cachedSectionInfos[indexPath.section]
        let itemInfos = cachedItemInfos[indexPath.section][indexPath.item]
        let frame = itemInfos.getFrame(using: sectionInfos)
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.frame = frame
        return attributes
    }
    
    
    override func layoutAttributesForSupplementaryView(ofKind elementKind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        assert(indexPath.item == 0)
        
        guard elementKind == UICollectionView.elementKindSectionHeader else { return nil }
        
        adjustOriginOfLayoutSectionInfos(untilSection: indexPath.section)
        
        let topFrame = topFrameForSupplementaryView(atSection: indexPath.section)
        let bottomFrame = bottomFrameForSupplementaryView(atSection: indexPath.section)
        
        let attributes = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, with: indexPath)
        attributes.zIndex = Int.max
        
        guard sectionHeadersPinToVisibleBounds else {
            indexPathOfPinnedHeader = nil
            attributes.frame = topFrame
            return attributes
        }
        
        let spaceAboveSection = spaceBetweenSections
        
        if bottomFrame.origin.y > collectionView!.bounds.origin.y + collectionView!.adjustedContentInset.top + spaceAboveSection {
            attributes.frame = CGRect(origin: CGPoint(x: bottomFrame.origin.x, y: collectionView!.bounds.origin.y + collectionView!.adjustedContentInset.top + spaceAboveSection), size: bottomFrame.size)
        } else {
            attributes.frame = bottomFrame
        }
        
        if attributes.frame.origin.y <= topFrame.origin.y {
            attributes.frame = topFrame
            if indexPathOfPinnedHeader == indexPath {
                indexPathOfPinnedHeader = nil
            }
        } else {
            indexPathOfPinnedHeader = indexPath
        }
        
        return attributes
    }
    
    
    func topFrameForSupplementaryView(atSection section: Int) -> CGRect {
        let sectionInfos = cachedSectionInfos[section]
        let svInfos = cachedSupplementaryViewInfos[section]
        let frame = svInfos.getFrame(using: sectionInfos)
        return frame
    }
    
    
    func bottomFrameForSupplementaryView(atSection section: Int) -> CGRect {
        let sectionInfos = cachedSectionInfos[section]
        let svInfos = cachedSupplementaryViewInfos[section]
        let frame = svInfos.getFrame(using: sectionInfos)
        let newOrigin = CGPoint(x: frame.origin.x, y: frame.origin.y + sectionInfos.frame.size.height - frame.size.height)
        let newFrame = CGRect(origin: newOrigin, size: frame.size)
        return newFrame
    }
    
    
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        var attributesArray = [UICollectionViewLayoutAttributes]()
        
        // Find any section that sits within the query rect
        
        guard let lastIndex = cachedSectionInfos.indices.last,
            let firstMatchIndex = binSearchSectionInfos(rect, start: 0, end: lastIndex) else { return attributesArray }
        
        var sectionsIntersectingRect = [firstMatchIndex]
        
        // Starting from the match, loop up and down through the array until all the sections that intersect the rect have been found
        
        for section in (0..<firstMatchIndex).reversed() {
            let sectionInfos = cachedSectionInfos[section]
            guard sectionInfos.frame.maxY >= rect.minY else { break }
            sectionsIntersectingRect.insert(section, at: 0)
        }
        
        for section in firstMatchIndex..<cachedSectionInfos.count {
            adjustOriginOfLayoutSectionInfos(untilSection: section)
            let sectionInfos = cachedSectionInfos[section]
            guard sectionInfos.frame.minY <= rect.maxY else { break }
            sectionsIntersectingRect.append(section)
        }
        
        // We adjust the origin of all the items in the sections intersecting the rect
        
        for section in sectionsIntersectingRect {
            adjustOriginOfLayoutItemInfos(at: IndexPath(item: cachedItemInfos[section].count-1, section: section))
        }
        
        // At this point sectionsIntersectingRect contains the section number of all the sections intersecting rect
        // Scan all the items within the sections found and keep those that intersect the rect
        
        for section in sectionsIntersectingRect {
            
            let sectionInfos = cachedSectionInfos[section]
            
            // We could do a dichotomic search for headers and items
            
            // Start with the supplementary view
            
            do {
                if let attributes = layoutAttributesForSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: section)) {
                    if attributes.frame.maxY >= rect.minY && attributes.frame.minY <= rect.maxY {
                        attributesArray.append(attributes)
                    }
                }
            }
            
            // Continue with the items
            
            let sectionItemInfos = cachedItemInfos[section]
            
            for item in 0..<sectionItemInfos.count {
                
                let itemInfos = sectionItemInfos[item]
                let frame = itemInfos.getFrame(using: sectionInfos)
                guard frame.maxY >= rect.minY && frame.minY <= rect.maxY else { continue }
                let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: item, section: section))
                attributes.frame = frame
                attributesArray.append(attributes)
                
            }
            
        }

        return attributesArray
        
    }
    
}


// MARK: - Self sizing cells

extension ObvCollectionViewLayout {
    
    override func invalidationContext(forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes, withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutInvalidationContext {

        let context = super.invalidationContext(forPreferredLayoutAttributes: preferredAttributes, withOriginalAttributes: originalAttributes)
        
        let currentIndexPath = preferredAttributes.indexPath

        // Update the cached size of the current element and get the height adjustment (to be used to set both contentOffsetAdjustment and contentSizeAdjustment of the context)
        
        let heightAdjustment: CGFloat
        
        switch originalAttributes.representedElementCategory {
            
        case .cell:
            
            let infos = cachedItemInfos[currentIndexPath.section][currentIndexPath.item]
            let origin = infos.frameInSection.origin
            heightAdjustment = preferredAttributes.frame.size.height - infos.frameInSection.size.height
            let size = CGSize(width: sectionWidth, height: preferredAttributes.frame.size.height)
            let frame = CGRect(origin: origin, size: size)
            let updatedInfos = ObvCollectionViewLayoutItemInfos(frameInSection: frame)
            cachedItemInfos[currentIndexPath.section][currentIndexPath.item] = updatedInfos
            
        case .supplementaryView:
            
            let infos = cachedSupplementaryViewInfos[currentIndexPath.section]
            let origin = infos.frameInSection.origin
            heightAdjustment = preferredAttributes.frame.size.height - infos.frameInSection.size.height
            let size = CGSize(width: sectionWidth, height: preferredAttributes.frame.size.height)
            let frame = CGRect(origin: origin, size: size)
            let updatedInfos = ObvCollectionViewLayoutSupplementaryViewInfos(frameInSection: frame)
            cachedSupplementaryViewInfos[currentIndexPath.section] = updatedInfos
            
        case .decorationView:
            assertionFailure("Unexpected element category")
            return context
            
        @unknown default:
            fatalError()
        }
        
        // Update the section infos
        
        do {
            let sectionInfos = cachedSectionInfos[currentIndexPath.section]
            
            let origin = sectionInfos.frame.origin
            let size = CGSize(width: sectionWidth, height: sectionInfos.frame.size.height + heightAdjustment)
            let frame = CGRect(origin: origin, size: size)
            
            let largestItemWithValidOrigin: Int?
            switch originalAttributes.representedElementCategory {
            case .cell:
                if let currentLargestItemWithValidOrigin = sectionInfos.largestItemWithValidOrigin {
                    largestItemWithValidOrigin = min(currentLargestItemWithValidOrigin, currentIndexPath.item)
                } else {
                    largestItemWithValidOrigin = nil
                }
            case .supplementaryView:
                largestItemWithValidOrigin = nil
            case .decorationView:
                assertionFailure("Unexpected element category")
                return context
            @unknown default:
                fatalError()
            }
            
            let updatedSectionInfos = ObvCollectionViewLayoutSectionInfos(frame: frame, largestItemWithValidOrigin: largestItemWithValidOrigin)
            
            cachedSectionInfos[currentIndexPath.section] = updatedSectionInfos
        }
        
        // Update the index of largest section with valid origin
        
        if largestSectionWithValidOrigin != nil {
            largestSectionWithValidOrigin = min(largestSectionWithValidOrigin!, currentIndexPath.section)
        }
        
        // Adjust the context
        
        context.contentOffsetAdjustment = getContentOffsetAdjustment(from: heightAdjustment, ofElementWithCategoy: originalAttributes.representedElementCategory, atIndexPath: currentIndexPath)
        context.contentSizeAdjustment = CGSize(width: 0.0, height: heightAdjustment)
        
        return context
    }
    
    
    private func getContentOffsetAdjustment(from heightAdjustment: CGFloat, ofElementWithCategoy categoy: UICollectionView.ElementCategory, atIndexPath indexPath: IndexPath) -> CGPoint {
        
        guard let collectionView = collectionView else { return .zero }
        guard let delegate = delegate else { return .zero }
        
        let contentOffsetAdjustment: CGPoint
        
        // Always adjust while the collection is not on screen yet
        guard delegate.collectionViewDidAppear() else {
            return CGPoint(x: 0, y: heightAdjustment)
        }
        
        if collectionViewContentSize.height <= collectionView.bounds.height {
            
            // After self-sizing the cell, the content size happens to be smaller than the collection view bound.
            // We adjust the content offset to to make it (0,0).
            let heightAdjustment = -collectionView.contentOffset.y
            contentOffsetAdjustment = CGPoint(x: 0, y: heightAdjustment)
            
        } else {
            
            switch getElementPositionWithRespectToContentView(elementCategory: categoy, indexPath: indexPath, collectionView: collectionView) {
            case .above:
                contentOffsetAdjustment = CGPoint(x: 0, y: heightAdjustment)
            case .under:
                contentOffsetAdjustment = .zero
            case .visible:
                contentOffsetAdjustment = .zero
            }
            
        }
        
        return contentOffsetAdjustment
        
    }
    
}


// MARK: - Updating cache before collection view updates

extension ObvCollectionViewLayout {
    
    func updateCache() {
        
        // Order mattters
        updateCacheFromDeletedItems()
        updateCacheFromDeletedSections()
        updateCacheFromInsertedSections()
        updateCacheFromInsertedItems()
        updateCacheForMovedItems()
        
        deletedIndexPathBeforeUpdate.removeAll()
        deletedSectionsBeforeUpdate.removeAll()
        insertedSectionsAfterUpdate.removeAll()
        insertedIndexPathsAfterUpdate.removeAll()
        movedIndexPaths.removeAll()
        
    }
    
    
    private func updateCacheFromDeletedItems() {
        
        // Delete cached infos of deleted items in descending order
        
        let deletedIndexPaths = self.deletedIndexPathBeforeUpdate.sorted { $0 > $1 }
        
        for indexPath in deletedIndexPaths {
            
            // Remove the deleted item from the cache
            
            let deletedItemInfos = cachedItemInfos[indexPath.section].remove(at: indexPath.item)
            
            // Update the section infos
            
            do {
                let sectionInfos = cachedSectionInfos[indexPath.section]
                let origin = sectionInfos.frame.origin
                let topSpaceAboveDeletedItem = interitemSpacing
                let size = CGSize(width: sectionInfos.frame.size.width, height: sectionInfos.frame.size.height - topSpaceAboveDeletedItem - deletedItemInfos.frameInSection.height)
                let frame = CGRect(origin: origin, size: size)
                if let largestItemWithValidOrigin = (indexPath.item == 0) ? nil : indexPath.item-1,
                    let previousLargestItemWithValidOrigin = sectionInfos.largestItemWithValidOrigin {
                    let newLargestItemWithValidOrigin = min(previousLargestItemWithValidOrigin, largestItemWithValidOrigin)
                    cachedSectionInfos[indexPath.section] = ObvCollectionViewLayoutSectionInfos(frame: frame, largestItemWithValidOrigin: newLargestItemWithValidOrigin)
                } else {
                    cachedSectionInfos[indexPath.section] = ObvCollectionViewLayoutSectionInfos(frame: frame, largestItemWithValidOrigin: nil)
                }
            }
            
            // Update the largest index of the section with valid origin
            
            if largestSectionWithValidOrigin != nil {
                largestSectionWithValidOrigin = min(largestSectionWithValidOrigin!, indexPath.section)
            }
            
            // Update the from index paths of moved items
            
            for (toIndexPath, fromIndexPath) in movedIndexPaths {
                guard fromIndexPath.section == indexPath.section else { continue }
                guard fromIndexPath.item > indexPath.item else { continue }
                let newFromIndexPath = IndexPath(item: fromIndexPath.item-1, section: fromIndexPath.section)
                movedIndexPaths[toIndexPath] = newFromIndexPath
            }
            
        }
        
    }
    
    
    private func updateCacheFromDeletedSections() {
        
        let deletedSections = Array(self.deletedSectionsBeforeUpdate.sorted { $0 > $1 })
        for deletedSection in deletedSections {
            
            // Delete cached infos about the deleted section and update the index of the largest section with a valid origin
            
            cachedSectionInfos.remove(at: deletedSection)
            cachedSupplementaryViewInfos.remove(at: deletedSection)
            assert(cachedItemInfos[deletedSection].isEmpty)
            cachedItemInfos.remove(at: deletedSection)
            
            if largestSectionWithValidOrigin != nil {
                if deletedSection == 0 {
                    largestSectionWithValidOrigin = nil
                } else {
                    largestSectionWithValidOrigin = min(largestSectionWithValidOrigin!, deletedSection-1)
                }
            }
            
            // Update the from index paths of moved items
            
            for (toIndexPath, fromIndexPath) in movedIndexPaths {
                guard fromIndexPath.section > deletedSection else { continue }
                let newFromIndexPath = IndexPath(item: fromIndexPath.item, section: fromIndexPath.section-1)
                movedIndexPaths[toIndexPath] = newFromIndexPath
            }
            
        }
        
    }
    
    
    private func updateCacheFromInsertedSections() {
        
        // Add cached infos for inserted sections (cells will be added later)
        
        if let lastInsertedSection = self.insertedSectionsAfterUpdate.max() {
            
            let firstInsertedSection = cachedItemInfos.count
            var previousSectionFrame = (cachedItemInfos.count == 0) ? CGRect.zero : cachedSectionInfos.last!.frame
            
            for section in firstInsertedSection...lastInsertedSection {
                
                guard let delegate = delegate else { break }
                
                // Insert infos for the supplementary view of this section (ask for the appropriate size to the delegate)
                
                let height: CGFloat
                do {
                    let indexPath = IndexPath(item: 0, section: section)
                    let layoutAttributes = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, with: indexPath)
                    let size = CGSize(width: sectionWidth, height: defaultHeightForSupplementaryView)
                    layoutAttributes.frame = CGRect(origin: .zero, size: size)
                    let preferredLayoutAttributes = delegate.preferredLayoutAttributesFitting(layoutAttributes)
                    let supplementaryViewFrame = preferredLayoutAttributes.frame
                    let svInfos = ObvCollectionViewLayoutSupplementaryViewInfos(frameInSection: supplementaryViewFrame)
                    cachedSupplementaryViewInfos.append(svInfos)
                    
                    height = preferredLayoutAttributes.frame.size.height
                }
                
                // Cache infos for this section
                
                do {
                    let topSpace = spaceBetweenSections
                    let origin = CGPoint(x: sectionXOrigin, y: previousSectionFrame.maxY + topSpace)
                    let size = CGSize(width: sectionWidth, height: height)
                    let frame = CGRect(origin: origin, size: size)
                    let sectionInfos = ObvCollectionViewLayoutSectionInfos(frame: frame, largestItemWithValidOrigin: nil)
                    cachedSectionInfos.append(sectionInfos)
                    
                    previousSectionFrame = frame
                }
                
                // Prepare array for cache estimated infos
                
                cachedItemInfos.append([])
                
            }
        }
        
        // Update the from index paths of moved items
        
        let insertedSections = Array(self.insertedSectionsAfterUpdate.sorted { $0 < $1 })
        for insertedSection in insertedSections {
            for (toIndexPath, fromIndexPath) in movedIndexPaths {
                guard fromIndexPath.section > insertedSection else { continue }
                let newFromIndexPath = IndexPath(item: fromIndexPath.item, section: fromIndexPath.section+1)
                movedIndexPaths[toIndexPath] = newFromIndexPath
            }
        }
    }
    
    
    private func updateCacheFromInsertedItems() {
        
        // Add cached infos for inserted items in ascending order
        
        let insertedIndexPaths = self.insertedIndexPathsAfterUpdate.sorted { $0 < $1 }
        
        for indexPath in insertedIndexPaths {
            
            guard let delegate = delegate else { break }
            
            // Insert the item into the cache (ask for the appropriate size to the delegate)
            
            let height: CGFloat
            do {
                let layoutAttributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
                let size = CGSize(width: sectionWidth, height: defaultHeightForCell)
                layoutAttributes.frame = CGRect(origin: .zero, size: size)
                let preferredLayoutAttributes = delegate.preferredLayoutAttributesFitting(layoutAttributes)
                let itemFrame = preferredLayoutAttributes.frame
                let itemInfos = ObvCollectionViewLayoutItemInfos(frameInSection: itemFrame)
                cachedItemInfos[indexPath.section].insert(itemInfos, at: indexPath.item)
                
                height = preferredLayoutAttributes.frame.size.height
            }
            
            // Update the section infos
            
            do {
                let sectionInfos = cachedSectionInfos[indexPath.section]
                let origin = sectionInfos.frame.origin
                let topSpaceAboveNewItem = interitemSpacing
                let size = CGSize(width: sectionInfos.frame.size.width, height: sectionInfos.frame.size.height + topSpaceAboveNewItem + height)
                let frame = CGRect(origin: origin, size: size)
                if let largestItemWithValidOrigin = (indexPath.item == 0) ? nil : indexPath.item-1,
                    let previousLargestItemWithValidOrigin = sectionInfos.largestItemWithValidOrigin {
                    let newLargestItemWithValidOrigin = min(previousLargestItemWithValidOrigin, largestItemWithValidOrigin)
                    cachedSectionInfos[indexPath.section] = ObvCollectionViewLayoutSectionInfos(frame: frame, largestItemWithValidOrigin: newLargestItemWithValidOrigin)
                } else {
                    cachedSectionInfos[indexPath.section] = ObvCollectionViewLayoutSectionInfos(frame: frame, largestItemWithValidOrigin: nil)
                }
            }
            
            // Update the largest index of the section with valid origin
            
            if largestSectionWithValidOrigin != nil {
                largestSectionWithValidOrigin = min(largestSectionWithValidOrigin!, indexPath.section)
            }
            
            // Update the from index paths of moved items
            
            for (toIndexPath, fromIndexPath) in movedIndexPaths {
                guard fromIndexPath.section == indexPath.section else { continue }
                guard fromIndexPath.item >= indexPath.item else { continue }
                let newFromIndexPath = IndexPath(item: fromIndexPath.item+1, section: fromIndexPath.section)
                movedIndexPaths[toIndexPath] = newFromIndexPath
            }
            
        }
        
    }
    
    
    private func updateCacheForMovedItems() {
        
        // Step 1: Delete the moved items in descending order and keep a reference to the items to insert
        
        var itemsToInsert = [IndexPath: CGRect]()
        
        do {
            
            let movedIndexPaths = self.movedIndexPaths.sorted { (val1, val2) in val1.value > val2.value }
            
            for (toIndexPath, fromIndexPath) in movedIndexPaths {
                
                // Remove the deleted item from the cache
                
                let deletedItemInfos = cachedItemInfos[fromIndexPath.section].remove(at: fromIndexPath.item)
                itemsToInsert[toIndexPath] = deletedItemInfos.frameInSection
                
                // Update the section infos
                
                do {
                    let sectionInfos = cachedSectionInfos[fromIndexPath.section]
                    let origin = sectionInfos.frame.origin
                    let topSpaceAboveDeletedItem = interitemSpacing
                    let size = CGSize(width: sectionInfos.frame.size.width, height: sectionInfos.frame.size.height - topSpaceAboveDeletedItem - deletedItemInfos.frameInSection.height)
                    let frame = CGRect(origin: origin, size: size)
                    if let largestItemWithValidOrigin = (fromIndexPath.item == 0) ? nil : fromIndexPath.item-1,
                        let previousLargestItemWithValidOrigin = sectionInfos.largestItemWithValidOrigin {
                        let newLargestItemWithValidOrigin = min(previousLargestItemWithValidOrigin, largestItemWithValidOrigin)
                        cachedSectionInfos[fromIndexPath.section] = ObvCollectionViewLayoutSectionInfos(frame: frame, largestItemWithValidOrigin: newLargestItemWithValidOrigin)
                    } else {
                        cachedSectionInfos[fromIndexPath.section] = ObvCollectionViewLayoutSectionInfos(frame: frame, largestItemWithValidOrigin: nil)
                    }
                }
                
                // Update the largest index of the section with valid origin
                
                if largestSectionWithValidOrigin != nil {
                    largestSectionWithValidOrigin = min(largestSectionWithValidOrigin!, fromIndexPath.section)
                }
                
            }
            
        }
        
        // Step 2: Insert the moved items in ascending order
        
        do {
            
            let itemsToInsert = itemsToInsert.sorted { (val1, val2) in val1.key < val2.key }
            
            for (toIndexPath, oldFrameInSection) in itemsToInsert {
                
                // Insert the item into the cache
                
                let height: CGFloat
                do {
                    let itemInfos = ObvCollectionViewLayoutItemInfos(frameInSection: oldFrameInSection)
                    cachedItemInfos[toIndexPath.section].insert(itemInfos, at: toIndexPath.item)
                    
                    height = oldFrameInSection.size.height
                }
                
                // Update the section infos
                
                do {
                    let sectionInfos = cachedSectionInfos[toIndexPath.section]
                    let origin = sectionInfos.frame.origin
                    let topSpaceAboveNewItem = interitemSpacing
                    let size = CGSize(width: sectionInfos.frame.size.width, height: sectionInfos.frame.size.height + topSpaceAboveNewItem + height)
                    let frame = CGRect(origin: origin, size: size)
                    if let largestItemWithValidOrigin = (toIndexPath.item == 0) ? nil : toIndexPath.item-1,
                        let previousLargestItemWithValidOrigin = sectionInfos.largestItemWithValidOrigin {
                        let newLargestItemWithValidOrigin = min(previousLargestItemWithValidOrigin, largestItemWithValidOrigin)
                        cachedSectionInfos[toIndexPath.section] = ObvCollectionViewLayoutSectionInfos(frame: frame, largestItemWithValidOrigin: newLargestItemWithValidOrigin)
                    } else {
                        cachedSectionInfos[toIndexPath.section] = ObvCollectionViewLayoutSectionInfos(frame: frame, largestItemWithValidOrigin: nil)
                    }
                }
                
                // Update the largest index of the section with valid origin
                
                if largestSectionWithValidOrigin != nil {
                    largestSectionWithValidOrigin = min(largestSectionWithValidOrigin!, toIndexPath.section)
                }
                
                // Update the from index paths of moved items
                
                for (toIndexPath, fromIndexPath) in movedIndexPaths {
                    guard fromIndexPath.section == toIndexPath.section else { continue }
                    guard fromIndexPath.item >= toIndexPath.item else { continue }
                    let newFromIndexPath = IndexPath(item: fromIndexPath.item+1, section: fromIndexPath.section)
                    movedIndexPaths[toIndexPath] = newFromIndexPath
                }
                
            }
            
        }
        
        
    }
    
}

// MARK: - Utils: Searching the cachedAttributes array

extension ObvCollectionViewLayout {
    
    /// The returned section always has a valid origin
    private func binSearchSectionInfos(_ rect: CGRect, start: Int, end: Int) -> Int? {
        guard start <= end else {
            return nil
        }
        
        let mid = (start + end) / 2
        adjustOriginOfLayoutSectionInfos(untilSection: mid)
        let frame = cachedSectionInfos[mid].frame
        
        if frame.intersects(rect) {
            return mid
        } else {
            if frame.maxY < rect.minY {
                return binSearchSectionInfos(rect, start: (mid + 1), end: end)
            } else {
                return binSearchSectionInfos(rect, start: start, end: (mid - 1))
            }
        }
        
    }
    
    
    private func getElementPositionWithRespectToContentView(elementCategory: UICollectionView.ElementCategory, indexPath: IndexPath, collectionView: UICollectionView) -> ElementPositionWithRespectToContentView {
        
        let elementFrame: CGRect
        
        switch elementCategory {
            
        case .cell:
            
            if collectionView.indexPathsForVisibleItems.contains(indexPath) {
                return .visible
            }
            let sectionInfos = cachedSectionInfos[indexPath.section]
            let infos = cachedItemInfos[indexPath.section][indexPath.item]
            elementFrame = infos.getFrame(using: sectionInfos)
            
        case .supplementaryView:
            
            if collectionView.indexPathsForVisibleSupplementaryElements(ofKind: UICollectionView.elementKindSectionHeader).contains(indexPath) {
                return .visible
            }
            let sectionInfos = cachedSectionInfos[indexPath.section]
            let infos = cachedSupplementaryViewInfos[indexPath.section]
            elementFrame = infos.getFrame(using: sectionInfos)
            
        case .decorationView:
            
            fatalError()
            
        @unknown default:
            fatalError()
        }
        
        if elementFrame.midY < collectionView.contentOffset.y + collectionView.bounds.height/2 {
            return .above
        } else {
            return .under
        }
        
    }
    
    
    enum ElementPositionWithRespectToContentView {
        case above
        case under
        case visible
    }
}


// MARK: - Utils: Adjusting the origin of elements layout

extension ObvCollectionViewLayout {
    
    
    /// This method adjusts the origin of the cached infos of all the section between the largest one
    /// having a valid origin until the one passed as a parameter (included).
    ///
    /// - Parameter section: The section to adjust.
    private func adjustOriginOfLayoutSectionInfos(untilSection section: Int) {
        
        guard largestSectionWithValidOrigin == nil || section > largestSectionWithValidOrigin! else { return }
        
        // Adjust the origin of all the sections between the first section having a valid origin and the section passed as a parameter
        
        var previousSectionFrame = (largestSectionWithValidOrigin == nil) ? CGRect.zero : cachedSectionInfos[largestSectionWithValidOrigin!].frame
        
        let firstSection = (largestSectionWithValidOrigin == nil) ? 0 : largestSectionWithValidOrigin!+1
        
        for sec in firstSection..<section+1 {
            
            let infos = cachedSectionInfos[sec]
            let topSpace = spaceBetweenSections
            let origin = CGPoint(x: sectionXOrigin, y: previousSectionFrame.maxY + topSpace)
            let size = infos.frame.size
            let sectionFrame = CGRect(origin: origin, size: size)
            let updatedInfos = ObvCollectionViewLayoutSectionInfos(frame: sectionFrame, largestItemWithValidOrigin: infos.largestItemWithValidOrigin)
            cachedSectionInfos[sec] = updatedInfos
            
            previousSectionFrame = sectionFrame
            
        }
        
        largestSectionWithValidOrigin = section
        
    }
    
    
    /// This method adjusts the origin of the cached infos of all the items within the section passed as a parameter,
    /// starting right after the largest valid item, until the item passed as a parameter (included)
    ///
    /// - Parameter indexPath: The index path of the item to adjust.
    private func adjustOriginOfLayoutItemInfos(at indexPath: IndexPath) {
        
        let sectionInfos = cachedSectionInfos[indexPath.section]
        guard sectionInfos.largestItemWithValidOrigin == nil || indexPath.item > sectionInfos.largestItemWithValidOrigin! else { return }
        
        let firstItemToAdjust: Int
        var previousElementFrame: CGRect
        if let item = sectionInfos.largestItemWithValidOrigin {
            previousElementFrame = cachedItemInfos[indexPath.section][item].frameInSection
            firstItemToAdjust = item+1
        } else {
            previousElementFrame = cachedSupplementaryViewInfos[indexPath.section].frameInSection
            firstItemToAdjust = 0
        }
        
        for item in firstItemToAdjust...indexPath.item {
            
            let infos = cachedItemInfos[indexPath.section][item]
            let topSpace = interitemSpacing
            let origin = CGPoint(x: 0, y: previousElementFrame.maxY + topSpace)
            let size = infos.frameInSection.size
            let frame = CGRect(origin: origin, size: size)
            let updatedInfos = ObvCollectionViewLayoutItemInfos(frameInSection: frame)
            cachedItemInfos[indexPath.section][item] = updatedInfos
            
            previousElementFrame = frame
            
        }
        
        cachedSectionInfos[indexPath.section] = ObvCollectionViewLayoutSectionInfos(frame: sectionInfos.frame, largestItemWithValidOrigin: indexPath.item)
    }
    
}
