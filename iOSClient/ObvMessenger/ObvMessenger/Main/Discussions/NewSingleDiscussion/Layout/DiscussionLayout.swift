/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import os.log

final class DiscussionLayout: UICollectionViewLayout {
    
    /// Largest index among the indexes of the sections having a valid origin and valid item origins inside.
    ///
    /// A section is valid iff
    /// - all its items have a valid origin,
    /// - the previous section, if it exists, is valid.
    /// This implies that all previous sections are valid.
    private var largestValidSection: Int? = nil
    
    private var cachedSectionInfos = [ObvCollectionViewLayoutSectionInfos]()
    private var cachedSupplementaryViewInfos = [ObvCollectionViewLayoutSupplementaryViewInfos]()
    private var cachedItemInfos = [[OlvidCollectionViewLayoutItemInfos]]()
    
    private var knownCollectionViewSafeAreaWidth: CGFloat = CGFloat.zero // Computed later
    private var availableWidth: CGFloat = 0.0 // Computed later
    private var sectionWidth: CGFloat = 0.0 // Computed later
    private var sectionXOrigin: CGFloat = 0.0 // Computed later
    private let defaultHeightForSupplementaryView: CGFloat = 33.5
    private let defaultHeightForCell: CGFloat = 60.0
    private let defaultSectionXOrigin: CGFloat = 10.0

    private var indexPathsBeingDeleted = [IndexPath: CGRect]()

    private var deletedIndexPathBeforeUpdate = [IndexPath]()
    private var deletedSectionsBeforeUpdate = [Int]()
    private var insertedSectionsAfterUpdate = [Int]()
    private var insertedIndexPathsAfterUpdate = [IndexPath]()
    private var movedIndexPaths = [IndexPath: IndexPath]()
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: DiscussionLayout.self))

    var interItemSpacing: CGFloat = 10
    var interSectionSpacing: CGFloat = 10
        
    private let debugSpace = String(repeating: " ", count: 5)
        
    func getCurrentLayoutInfosOfItem(at indexPath: IndexPath) -> (frame: CGRect, usesPreferredAttributes: Bool)? {
        let item = indexPath.item
        let section = indexPath.section
        guard section < cachedSectionInfos.count else { assertionFailure(); return nil }
        let secInfos = cachedSectionInfos[section]
        guard section < cachedItemInfos.count, item < cachedItemInfos[section].count else { assertionFailure(); return nil }
        let itemInfos = cachedItemInfos[section][item]
        return (itemInfos.getFrame(using: secInfos), itemInfos.usesPreferredAttributes)
    }

    private func minOrNil(_ a: Int?, _ b: Int?) -> Int? {
        switch (a, b) {
        case (.none, .none), (.none, .some), (.some, .none):
            return nil
        case (.some(let a), .some(let b)):
            return min(a, b)
        }
    }
}

// MARK: - Providing Layout Information

extension DiscussionLayout {
    
    
    override func prepare() {
        debugPrint("😤 Call to \(#function)")
        os_log("Call to prepare", log: log, type: .info)
        
        guard let collectionView = collectionView else { assertionFailure(); return }
        
        if knownCollectionViewSafeAreaWidth != collectionView.bounds.inset(by: collectionView.safeAreaInsets).width {
            knownCollectionViewSafeAreaWidth = collectionView.bounds.inset(by: collectionView.safeAreaInsets).width
            availableWidth = knownCollectionViewSafeAreaWidth
            sectionXOrigin = defaultSectionXOrigin
            sectionWidth = availableWidth - 2 * defaultSectionXOrigin
            resetCache()
        }

    }

    
    override var collectionViewContentSize: CGSize {
        os_log("Call to collectionViewContentSize", log: log, type: .info)
        guard !cachedSectionInfos.isEmpty else { return .zero }
        adjustRectOfSectionInfos(untilSection: cachedSectionInfos.count-1)
        guard let lastSectionFrame = cachedSectionInfos.last?.frame else { return .zero }
        let result = CGSize(width: sectionWidth, height: lastSectionFrame.maxY)
        debugPrint("😤 \(debugSpace) collectionViewContentSize returns \(result)")
        return result
    }

    

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        os_log("😤 Call to layoutAttributesForElements(in rect: CGRect) with rect: %{public}@", log: log, type: .info, rect.debugDescription)

        debugPrint("🐶 \(Date().epochInMs) Call to layoutAttributesForElements(in rect: CGRect) with rect: \(rect.debugDescription)")

        var attributesArray = [UICollectionViewLayoutAttributes]()
        
        // Find any section that sits within the query rect
        
        guard let lastIndex = cachedSectionInfos.indices.last,
            let firstMatchIndex = binSearchSectionInfos(rect, start: 0, end: lastIndex) else { return attributesArray }
                
        // Starting from the match, loop up and down through the array until all the sections that intersect the rect have been found
        
        let sectionsIntersectingRect: [Int]
        do {
            
            var unsortedSectionsIntersectingRect = Set([firstMatchIndex])
            
            for section in (0..<firstMatchIndex).reversed() {
                let sectionInfos = cachedSectionInfos[section]
                guard sectionInfos.frame.maxY >= rect.minY else { break }
                unsortedSectionsIntersectingRect.insert(section)
            }
            
            for section in firstMatchIndex..<cachedSectionInfos.count {
                adjustRectOfSectionInfos(untilSection: section)
                let sectionInfos = cachedSectionInfos[section]
                guard sectionInfos.frame.minY <= rect.maxY else { break }
                unsortedSectionsIntersectingRect.insert(section)
            }
            
            sectionsIntersectingRect = unsortedSectionsIntersectingRect.sorted()
            
        }

        // At this point sectionsIntersectingRect contains the section number of all the sections intersecting rect.
        // Scan all the items within these sections and keep those that intersect the rect
        
        for section in sectionsIntersectingRect {
                        
            guard section < cachedSectionInfos.count else { continue }
            let sectionInfos = cachedSectionInfos[section]
            
            // Possible improvement: Dichotomic search for headers and items
            
            // Start with the supplementary view
            
            let svInfos = cachedSupplementaryViewInfos[section]
            let frame = svInfos.getFrame(using: sectionInfos)
            if frame.maxY >= rect.minY && frame.minY <= rect.maxY {
                let attributes = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, with: IndexPath(item: 0, section: section))
                attributes.frame = frame
                attributesArray.append(attributes)
            }
                
            // Continue with the items
            
            let sectionItemInfos = cachedItemInfos[section]
            
            for item in 0..<sectionItemInfos.count {
                
                // We determine the attributes *without* querying layoutAttributesForItem to prevent side effects
                let itemInfos = sectionItemInfos[item]
                let frame = itemInfos.getFrame(using: sectionInfos)
                if frame.maxY >= rect.minY && frame.minY <= rect.maxY {
                    let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: item, section: section))
                    attributes.frame = frame
                    attributesArray.append(attributes)
                }
                
            }
            
        }
        
        // Make sure we *never* return attributes for an index path that does not exist in the collection view, since this would crash the app.
        guard let collectionView = collectionView else { return nil }
        let sanitizedAttributes = attributesArray
            .filter({ $0.indexPath.section < collectionView.numberOfSections && $0.indexPath.item < collectionView.numberOfItems(inSection: $0.indexPath.section) })
        
        return sanitizedAttributes
        
    }

    
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        os_log("😤 Call to layoutAttributesForItem(at indexPath: IndexPath) at indexPath: %{public}@", log: log, type: .info, indexPath.debugDescription)

        debugPrint("🐶 Call to layoutAttributesForItem(at indexPath: IndexPath) at indexPath: \(indexPath.debugDescription)")

        guard indexPath.section < cachedItemInfos.count else { return nil }
        guard indexPath.item < cachedItemInfos[indexPath.section].count else { return nil }

        adjustRectOfSectionInfos(untilSection: indexPath.section)
        
        let sectionInfos = cachedSectionInfos[indexPath.section]
        let itemInfos = cachedItemInfos[indexPath.section][indexPath.item]
        let frame = itemInfos.getFrame(using: sectionInfos)
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.frame = frame
        
        debugPrint("😤 \(debugSpace) Returning the following frame for the item at index path \(indexPath): \(attributes.frame)")

        return attributes
    }

    
    override func layoutAttributesForSupplementaryView(ofKind elementKind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        os_log("Call to layoutAttributesForSupplementaryView(ofKind elementKind: String, at indexPath: IndexPath) at indexPath: %{public}@", log: log, type: .info, indexPath.debugDescription)
        debugPrint("😤 Call to \(#function) at indexPath \(indexPath.debugDescription)")

        guard let collectionView = collectionView else { assertionFailure(); return nil }
        debugPrint("😤 \(debugSpace) Number of sections in collection view is \(collectionView.numberOfSections)")
        assert(indexPath.item == 0)
        
        guard elementKind == UICollectionView.elementKindSectionHeader else { return nil }
        
        adjustRectOfSectionInfos(untilSection: indexPath.section)
        
        let topFrame = topFrameForSupplementaryView(atSection: indexPath.section)
        
        let attributes = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, with: indexPath)
        attributes.frame = topFrame

        debugPrint("😤 \(debugSpace) Returning the following frame for the header at index path \(indexPath): \(attributes.frame)")

        return attributes
    }

}


// MARK: - Internal cache management

extension DiscussionLayout {
    
    private func resetCache() {
        debugPrint("😤 Call to \(#function)")

        guard !cachedItemInfos.isEmpty else { return }
        
        insertedSectionsAfterUpdate.append(cachedItemInfos.count-1)
        
        cachedItemInfos.removeAll()
        cachedSectionInfos.removeAll()
        cachedSupplementaryViewInfos.removeAll()
        
        /// We removed all the cachedSectionInfos. The updateCache() method will call the updateCacheFromInsertedSections()
        /// that expects insertedSectionsAfterUpdate to contain all the sections that must be inserted. So we compute this array now.
        guard let collectionView else { assertionFailure(); return }
        if collectionView.numberOfSections > 0 {
            insertedSectionsAfterUpdate = (0..<collectionView.numberOfSections).map({ $0 })
        } else {
            insertedSectionsAfterUpdate = []
        }
        
        updateCache()
        
    }
    
    /* The index paths of the items stored in updateItems have different semantics:
     * For a deleted item, the given indexPath has a "before update" semantic
     * For an inserted item, the given indexPath has a "after update" semantic
     * Moreover, in case of multiple deletions, the first given index path is not taken
     * into account in the following (which makes sense given what was just said).
     * For example, if two consecutive cells are deleted, we could receive
     * [\"D(0,79)\", \"D(0,80)\"]
     * and *not*
     * [\"D(0,79)\", \"D(0,79)\"]
     * The array for the deletions is sorted from the largest to the lowest index path
     * so that we can apply the changes one after the others (remember, deletion have
     * a "before" update semantic).
     * The array for the insertions is sorted from the lowest to the largest index path
     * for similar reasons.
     * We then apply all the deletions, in order, then all the insertions.
     */

    private func updateCache() {
        
        os_log("Call to updateCache", log: log, type: .info)
        debugPrint("😤 Call to \(#function)")

        guard !deletedIndexPathBeforeUpdate.isEmpty ||
                !deletedSectionsBeforeUpdate.isEmpty ||
                !insertedSectionsAfterUpdate.isEmpty ||
                !insertedIndexPathsAfterUpdate.isEmpty ||
                !movedIndexPaths.isEmpty else {
                    debugPrint("😤 \(debugSpace) No need to update cache")
                    return
                }

        debugPrint("😤 \(debugSpace) Updating cache!")

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

        adjustRectOfSectionInfos(untilSection: cachedSectionInfos.count-1)

    }
    
    
    private func updateCacheFromDeletedItems() {
        
        // Delete cached infos of deleted items in descending order
        
        let deletedIndexPaths = self.deletedIndexPathBeforeUpdate.sorted { $0 > $1 }
        
        for indexPath in deletedIndexPaths {
            
            let section = indexPath.section
            let item = indexPath.item
            
            // Remove the deleted item from the cache
            
            guard section < cachedItemInfos.count else { assertionFailure(); continue }
            guard item < cachedItemInfos[section].count else { assertionFailure(); continue }
            guard section < cachedSectionInfos.count else { assertionFailure(); continue }
            let deletedItemInfos = cachedItemInfos[section].remove(at: item)
            let sectionInfo  = cachedSectionInfos[section]
            
            // To perform a nice animation, we store the frame of the deleted item
            
            indexPathsBeingDeleted[indexPath] = deletedItemInfos.getFrame(using: sectionInfo)
            
            // Update the section infos
            
            do {
                let sectionInfos = cachedSectionInfos[section]
                let origin = sectionInfos.frame.origin
                let topSpaceAboveDeletedItem = interItemSpacing
                let size = CGSize(
                    width: sectionInfos.frame.size.width,
                    height: sectionInfos.frame.size.height - topSpaceAboveDeletedItem - deletedItemInfos.frameInSection.height)
                let frame = CGRect(origin: origin, size: size)
                let largestItemWithValidOrigin = (item == 0) ? nil : item-1
                let previousLargestItemWithValidOrigin = sectionInfos.largestItemWithValidOrigin
                let newLargestItemWithValidOrigin = minOrNil(previousLargestItemWithValidOrigin, largestItemWithValidOrigin)
                cachedSectionInfos[section] = ObvCollectionViewLayoutSectionInfos(
                    frame: frame,
                    largestItemWithValidOrigin: newLargestItemWithValidOrigin)
            }
            
            // Update the largest index of the section with valid rect
            
            largestValidSection = section > 0 ? minOrNil(largestValidSection, section-1) : nil

        }
        
        // Update the "from" index paths of moved items
        
        for (toIndexPath, fromIndexPath) in movedIndexPaths {
            let numberOfDeletedItemsBelow = deletedIndexPaths.filter({ $0.section == fromIndexPath.section && $0.item < fromIndexPath.item }).count
            guard fromIndexPath.item - numberOfDeletedItemsBelow >= 0 else { assertionFailure(); continue }
            let newFromIndexPath = IndexPath(item: fromIndexPath.item - numberOfDeletedItemsBelow, section: fromIndexPath.section)
            movedIndexPaths[toIndexPath] = newFromIndexPath
        }
        
    }

    
    private func updateCacheFromDeletedSections() {
        
        let deletedSections = Array(self.deletedSectionsBeforeUpdate.sorted { $0 > $1 })
        
        for section in deletedSections {
            
            // Delete cached infos about the deleted section and update the index of the largest section with a valid origin
            
            guard section < cachedSectionInfos.count else { assertionFailure(); return }
            cachedSectionInfos.remove(at: section)
            cachedSupplementaryViewInfos.remove(at: section)
            cachedItemInfos.remove(at: section)
            
            largestValidSection = section > 0 ? minOrNil(largestValidSection, section-1) : nil

        }
        
        // Update the from index paths of moved items
        
        for (toIndexPath, fromIndexPath) in movedIndexPaths {
            let numberOfSectionsDeletedBelow = deletedSections.filter({ $0 < fromIndexPath.section }).count
            let newFromIndexPath = IndexPath(item: fromIndexPath.item, section: fromIndexPath.section-numberOfSectionsDeletedBelow)
            movedIndexPaths[toIndexPath] = newFromIndexPath
        }

        
    }

    
    private func updateCacheFromInsertedSections() {
        
        guard let collectionView = collectionView else { assertionFailure(); return }
        
        // Add cached infos for inserted sections (cells will be added later)
        
        let sortedInsertedSectionsAfterUpdate = self.insertedSectionsAfterUpdate.sorted { $0 < $1 }
        
        for sectionToInsert in sortedInsertedSectionsAfterUpdate {
            
            let numberOfItemsInInsertedSection = collectionView.numberOfItems(inSection: sectionToInsert)
            assert(numberOfItemsInInsertedSection > 0)

            // Cache estimated infos for this section

            do {
                let previousSectionFrame = (sectionToInsert == 0) ? CGRect.zero : cachedSectionInfos[sectionToInsert-1].frame
                let topSpace = interSectionSpacing
                let origin = CGPoint(x: sectionXOrigin, y: previousSectionFrame.maxY + topSpace)
                let sectionHeight = defaultHeightForSupplementaryView + CGFloat(numberOfItemsInInsertedSection) * (defaultHeightForCell + interItemSpacing)
                let size = CGSize(width: sectionWidth, height: sectionHeight)
                let frame = CGRect(origin: origin, size: size)
                let sectionInfos = ObvCollectionViewLayoutSectionInfos(
                    frame: frame,
                    largestItemWithValidOrigin: numberOfItemsInInsertedSection-1)
                cachedSectionInfos.insert(sectionInfos, at: sectionToInsert)
            }
            
            // Cache estimated infos for the supplementary view of this section

            let supplementaryViewFrame: CGRect
            
            do {
                let origin = CGPoint.zero
                let size = CGSize(width: sectionWidth, height: defaultHeightForSupplementaryView)
                supplementaryViewFrame = CGRect(origin: origin, size: size)
                let svInfos = ObvCollectionViewLayoutSupplementaryViewInfos(frameInSection: supplementaryViewFrame)
                cachedSupplementaryViewInfos.insert(svInfos, at: sectionToInsert)
            }

            // Cache estimated infos for all the items within this section
            
            var cachedItemInfosInSection = [OlvidCollectionViewLayoutItemInfos]()
            var previousElementFrame = supplementaryViewFrame
            
            for _ in 0..<numberOfItemsInInsertedSection {
                
                let topSpace = interItemSpacing
                let origin = CGPoint(x: 0, y: previousElementFrame.maxY + topSpace)
                let height = defaultHeightForCell
                let size = CGSize(width: sectionWidth, height: height)
                let frame = CGRect(origin: origin, size: size)
                let itemInfos = OlvidCollectionViewLayoutItemInfos(frameInSection: frame, usesPreferredAttributes: false)
                cachedItemInfosInSection.append(itemInfos)
                
                previousElementFrame = frame
                
            }
            
            cachedItemInfos.insert(cachedItemInfosInSection, at: sectionToInsert)

        }
        
        // Update the from index paths of moved items
        
        for (toIndexPath, fromIndexPath) in movedIndexPaths {
            let numberOfSectionsInsertedBelow = sortedInsertedSectionsAfterUpdate.filter({ $0 <= fromIndexPath.section }).count
            let newFromIndexPath = IndexPath(item: fromIndexPath.item, section: fromIndexPath.section+numberOfSectionsInsertedBelow)
            movedIndexPaths[toIndexPath] = newFromIndexPath
        }
        
    }
    
    
    private func updateCacheFromInsertedItems() {
        
        // Add cached infos for inserted items in ascending order
        
        let insertedIndexPaths = self.insertedIndexPathsAfterUpdate.sorted { $0 < $1 }
        
        for indexPath in insertedIndexPaths {
            
            // Insert the item into the cache
            
            let height: CGFloat
            do {
                let size = CGSize(width: sectionWidth, height: defaultHeightForCell)
                let frame = CGRect(origin: .zero, size: size)
                let itemInfos = OlvidCollectionViewLayoutItemInfos(frameInSection: frame, usesPreferredAttributes: false)
                cachedItemInfos[indexPath.section].insert(itemInfos, at: indexPath.item)
                
                height = frame.size.height
            }
            
            // Update the section infos
            
            do {
                let sectionInfos = cachedSectionInfos[indexPath.section]
                let origin = sectionInfos.frame.origin
                let topSpaceAboveNewItem = interItemSpacing
                let size = CGSize(
                    width: sectionInfos.frame.size.width,
                    height: sectionInfos.frame.size.height + topSpaceAboveNewItem + height)
                let frame = CGRect(origin: origin, size: size)
                let largestItemWithValidOrigin = (indexPath.item == 0) ? nil : indexPath.item-1
                let previousLargestItemWithValidOrigin = sectionInfos.largestItemWithValidOrigin
                let newLargestItemWithValidOrigin = minOrNil(previousLargestItemWithValidOrigin, largestItemWithValidOrigin)
                cachedSectionInfos[indexPath.section] = ObvCollectionViewLayoutSectionInfos(frame: frame, largestItemWithValidOrigin: newLargestItemWithValidOrigin)
            }
            
            // Update the largest index of the section with valid origin
            
            largestValidSection = indexPath.section > 0 ? minOrNil(largestValidSection, indexPath.section-1) : nil
            
        }
        
        // Update the from index paths of moved items
        
        for (toIndexPath, fromIndexPath) in movedIndexPaths {
            let numberOfItemsInsertedBelow = insertedIndexPaths.filter({ $0.section == fromIndexPath.section && $0.item <= fromIndexPath.item }).count
            let newFromIndexPath = IndexPath(item: fromIndexPath.item+numberOfItemsInsertedBelow, section: fromIndexPath.section)
            movedIndexPaths[toIndexPath] = newFromIndexPath
        }
        
    }
    
    
    private func updateCacheForMovedItems() {
        
        // Step 1: Delete the moved items in descending order and keep a reference to the items to insert
        
        var itemsToInsert = [IndexPath: (frameInSection: CGRect, usesPreferredAttributes: Bool)]()

        do {
            
            let movedIndexPaths = self.movedIndexPaths.sorted { (val1, val2) in val1.value > val2.value }
            
            for (toIndexPath, fromIndexPath) in movedIndexPaths {
                
                // Remove the deleted item from the cache
                
                guard fromIndexPath.section < cachedItemInfos.count && fromIndexPath.item < cachedItemInfos[fromIndexPath.section].count else { assertionFailure(); continue }
                let deletedItemInfos = cachedItemInfos[fromIndexPath.section].remove(at: fromIndexPath.item)
                itemsToInsert[toIndexPath] = (deletedItemInfos.frameInSection, deletedItemInfos.usesPreferredAttributes)
                
                // Update the section infos
                
                do {
                    let sectionInfos = cachedSectionInfos[fromIndexPath.section]
                    let origin = sectionInfos.frame.origin
                    let topSpaceAboveDeletedItem = interItemSpacing
                    let size = CGSize(width: sectionInfos.frame.size.width, height: sectionInfos.frame.size.height - topSpaceAboveDeletedItem - deletedItemInfos.frameInSection.height)
                    let frame = CGRect(origin: origin, size: size)
                    let largestItemWithValidOrigin = (fromIndexPath.item == 0) ? nil : fromIndexPath.item-1
                    let previousLargestItemWithValidOrigin = sectionInfos.largestItemWithValidOrigin
                    let newLargestItemWithValidOrigin = minOrNil(previousLargestItemWithValidOrigin, largestItemWithValidOrigin)
                    cachedSectionInfos[fromIndexPath.section] = ObvCollectionViewLayoutSectionInfos(frame: frame, largestItemWithValidOrigin: newLargestItemWithValidOrigin)
                }

                // Update the largest index of the section with valid rect
                
                largestValidSection = fromIndexPath.section > 0 ? minOrNil(largestValidSection, fromIndexPath.section-1) : nil

            }
            
        }
        
        // Step 2: Insert the moved items in ascending order
        
        do {
            
            let itemsToInsert = itemsToInsert.sorted { (val1, val2) in val1.key < val2.key }
            
            for (toIndexPath, oldInfos) in itemsToInsert {
                
                // Insert the item into the cache
                
                let height: CGFloat
                do {
                    let itemInfos = OlvidCollectionViewLayoutItemInfos(frameInSection: oldInfos.frameInSection, usesPreferredAttributes: oldInfos.usesPreferredAttributes)
                    cachedItemInfos[toIndexPath.section].insert(itemInfos, at: toIndexPath.item)
                    
                    height = oldInfos.frameInSection.size.height
                }
                
                // Update the section infos
                
                do {
                    let sectionInfos = cachedSectionInfos[toIndexPath.section]
                    let origin = sectionInfos.frame.origin
                    let topSpaceAboveNewItem = interItemSpacing
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
                
                largestValidSection = toIndexPath.section > 0 ? minOrNil(largestValidSection, toIndexPath.section-1) : nil

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


// MARK: - Invalidating the Layout

extension DiscussionLayout {
    
    override func invalidateLayout() {
        debugPrint("😤 Call to \(#function)")
        os_log("Call to invalidateLayout", log: log, type: .info)
        super.invalidateLayout()
    }

    
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        debugPrint("😤 Call to \(#function)")
        os_log("Call to shouldInvalidateLayout(forBoundsChange newBounds: CGRect)", log: log, type: .info)
        guard let collectionView = collectionView else { return false }
        return abs(collectionView.bounds.size.width - newBounds.size.width) > 0.1 || abs(collectionView.bounds.size.height - newBounds.size.height) > 0.1
    }

    
    override func shouldInvalidateLayout(forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes, withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes) -> Bool {
        debugPrint("😤 Call to \(#function)")
        os_log("Call to shouldInvalidateLayout(forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes, withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes)", log: log, type: .info)
        debugPrint("😤 \(debugSpace) originalAttributes:  \(originalAttributes.debugDescription)")
        debugPrint("😤 \(debugSpace) preferredAttributes: \(preferredAttributes.debugDescription)")
        
        let shouldInvalidate = abs(preferredAttributes.frame.width - originalAttributes.frame.width) > 0.001 || abs(preferredAttributes.frame.height - originalAttributes.frame.height) > 0.001
        
        // Make sure the cached infos are marked as using the preferred attributes
        if !shouldInvalidate {
            let section = originalAttributes.indexPath.section
            let item = originalAttributes.indexPath.item
            guard section < cachedItemInfos.count else { assertionFailure(); return shouldInvalidate }
            guard item < cachedItemInfos[section].count else { assertionFailure(); return shouldInvalidate }
            let itemInfos = cachedItemInfos[section][item]
            if !itemInfos.usesPreferredAttributes {
                let newItemInfos = OlvidCollectionViewLayoutItemInfos(frameInSection: itemInfos.frameInSection, usesPreferredAttributes: true)
                cachedItemInfos[section][item] = newItemInfos
            }
        }
        
        debugPrint("😤 \(debugSpace) Result: \(shouldInvalidate)")
        return shouldInvalidate
    }

    

    
    override func invalidationContext(forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes, withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutInvalidationContext {

        debugPrint("😤 Call to \(#function)")
        os_log("Call to invalidationContext(forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes, withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes) preferredAttributes.indexPath=%{public}@ originalAttributes.indexPath=%{public}@", log: log, type: .info, preferredAttributes.indexPath.debugDescription, originalAttributes.indexPath.debugDescription)

        let context = super.invalidationContext(
            forPreferredLayoutAttributes: preferredAttributes,
            withOriginalAttributes: originalAttributes)

        let currentIndexPath = preferredAttributes.indexPath

        // Update the cached size of the current element and get the height adjustment (to be used to set both contentOffsetAdjustment and contentSizeAdjustment of the context)
        
        let heightAdjustment: CGFloat
        
        switch originalAttributes.representedElementCategory {
            
        case .cell:
            
            if currentIndexPath.section < cachedItemInfos.count && currentIndexPath.item < cachedItemInfos[currentIndexPath.section].count {
                let infos = cachedItemInfos[currentIndexPath.section][currentIndexPath.item]
                let origin = infos.frameInSection.origin
                heightAdjustment = preferredAttributes.frame.size.height - infos.frameInSection.size.height
                let size = CGSize(width: sectionWidth, height: preferredAttributes.frame.size.height)
                let frame = CGRect(origin: origin, size: size)
                let updatedInfos = OlvidCollectionViewLayoutItemInfos(frameInSection: frame, usesPreferredAttributes: true)
                cachedItemInfos[currentIndexPath.section][currentIndexPath.item] = updatedInfos
            } else {
                assertionFailure()
                heightAdjustment = .zero
            }
                        
        case .supplementaryView:
            
            if currentIndexPath.section < cachedSupplementaryViewInfos.count {
                let infos = cachedSupplementaryViewInfos[currentIndexPath.section]
                let origin = infos.frameInSection.origin
                heightAdjustment = preferredAttributes.frame.size.height - infos.frameInSection.size.height
                let size = CGSize(width: sectionWidth, height: preferredAttributes.frame.size.height)
                let frame = CGRect(origin: origin, size: size)
                let updatedInfos = ObvCollectionViewLayoutSupplementaryViewInfos(frameInSection: frame)
                cachedSupplementaryViewInfos[currentIndexPath.section] = updatedInfos
            } else {
                assertionFailure()
                heightAdjustment = .zero
            }
            
        case .decorationView:
            assertionFailure("Unexpected element category")
            return context
            
        @unknown default:
            assertionFailure("Unknown element category")
            return context
        }

        // Update the section infos
        
        if currentIndexPath.section < cachedSectionInfos.count {
            let sectionInfos = cachedSectionInfos[currentIndexPath.section]
            
            let origin = sectionInfos.frame.origin
            let size = CGSize(width: sectionWidth,
                              height: sectionInfos.frame.size.height + heightAdjustment)
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
                assertionFailure("Unknown element category")
                return context
            }
            
            let updatedSectionInfos = ObvCollectionViewLayoutSectionInfos(
                frame: frame,
                largestItemWithValidOrigin: largestItemWithValidOrigin)
            
            cachedSectionInfos[currentIndexPath.section] = updatedSectionInfos
        } else {
            assertionFailure()
        }

        // Update the index of largest section with valid origin
        
        largestValidSection = currentIndexPath.section > 0 ? minOrNil(largestValidSection, currentIndexPath.section-1) : nil

        // Adjust the content offset. This prevents animation glitches when manually scrolling from bottom towards the top of the discussion.
        // We do not need to compensate if the collection view contains only a few messages (i.e., has a small content height). This check prevents a small animation glitch in that case.

        if collectionViewContentSize.height > collectionView!.bounds.height {
            assert(context.contentOffsetAdjustment == .zero)
            context.contentOffsetAdjustment = CGPoint(x: 0, y: heightAdjustment)
            context.contentSizeAdjustment = CGSize(width: 0.0, height: heightAdjustment)
        }

        return context
    }
}


// MARK: - Returning layout attributes

extension DiscussionLayout {
    
    private func topFrameForSupplementaryView(atSection section: Int) -> CGRect {
        let sectionInfos = cachedSectionInfos[section]
        let svInfos = cachedSupplementaryViewInfos[section]
        let frame = svInfos.getFrame(using: sectionInfos)
        return frame
    }

}


// MARK: - Collection view updates

extension DiscussionLayout {
    
    override func prepare(forCollectionViewUpdates updateItems: [UICollectionViewUpdateItem]) {
        os_log("Call to prepare(forCollectionViewUpdates updateItems: [UICollectionViewUpdateItem])", log: log, type: .info)

        debugPrint("😤 Call to \(#function)")
        debugPrint("😤   \(updateItems.map({ $0.debugDescription })) ")
        
        assert(deletedSectionsBeforeUpdate.isEmpty)
        assert(deletedIndexPathBeforeUpdate.isEmpty)
        assert(insertedSectionsAfterUpdate.isEmpty)
        assert(insertedIndexPathsAfterUpdate.isEmpty)
        assert(movedIndexPaths.isEmpty)

        for item in updateItems {
            switch item.updateAction {
            case .delete:
                guard let indexPath = item.indexPathBeforeUpdate else { assertionFailure(); continue }
                assert(item.indexPathAfterUpdate == nil)
                if indexPath.item == NSNotFound {
                    deletedSectionsBeforeUpdate.append(indexPath.section)
                } else {
                    deletedIndexPathBeforeUpdate.append(indexPath)
                }
            case .insert:
                guard let indexPath = item.indexPathAfterUpdate else { assertionFailure(); continue }
                assert(item.indexPathBeforeUpdate == nil)
                if indexPath.item == NSNotFound {
                    // This indicates that we must insert a section
                    insertedSectionsAfterUpdate.append(indexPath.section)
                } else {
                    // This indicates that we must insert an item
                    insertedIndexPathsAfterUpdate.append(indexPath)
                }
            case .move:
                guard let fromIndexPath = item.indexPathBeforeUpdate else { assertionFailure(); continue }
                guard let toIndexPath = item.indexPathAfterUpdate else { assertionFailure(); continue }
                movedIndexPaths[toIndexPath] = fromIndexPath
            case .reload:
                break
            case .none:
                break
            @unknown default:
                assertionFailure()
            }
        }

        updateCache()
        
        super.prepare(forCollectionViewUpdates: updateItems)

    }
    
    
    override func finalLayoutAttributesForDisappearingItem(at itemIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {

        debugPrint("😤 Call to \(#function) at itemIndex path \(itemIndexPath.debugDescription)")

        /* This method is called for deleted item and for items that moves because of the deletion. To distinguish the two,
         * we check that the current itemIndexPath exists in the indexPathsBeingDeleted set. We return no specific attributes
         * if we cannot find it.
         */
        guard let frame = indexPathsBeingDeleted.removeValue(forKey: itemIndexPath) else {
            debugPrint("😤     Returning nil for itemIndex path \(itemIndexPath.debugDescription)")
            return nil
        }

        let attributes = UICollectionViewLayoutAttributes(forCellWith: itemIndexPath)
        attributes.frame = frame

        attributes.transform = CGAffineTransform.init(scaleX: 0.1, y: 0.1)
        attributes.center = CGPoint(x: (frame.origin.x + frame.size.width) / 2, y: frame.origin.y)
        attributes.alpha = 0
        attributes.zIndex = -1
        debugPrint("😤     Returning \(attributes.debugDescription) for itemIndex path \(itemIndexPath.debugDescription)")
        return attributes
    }

}


// MARK: - Utils: Searching the cachedAttributes array
extension DiscussionLayout {
    
    /// Searches the `cachedSectionInfos` for a section that intersects the rect and returns its index.
    /// The returned section always has a valid origin
    private func binSearchSectionInfos(_ rect: CGRect, start: Int, end: Int) -> Int? {
        guard start <= end else {
            return nil
        }
        
        let mid = (start + end) / 2
        adjustRectOfSectionInfos(untilSection: mid)
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

extension DiscussionLayout {
    
    /// This method adjusts the origin of the cached infos of all the section between the largest one
    /// having a valid origin until the one passed as a parameter (included).
    private func adjustRectOfSectionInfos(untilSection section: Int) {
        
        guard largestValidSection == nil || section > largestValidSection! else { return }
        
        var previousSectionFrame = (largestValidSection == nil) ? CGRect.zero : cachedSectionInfos[largestValidSection!].frame
        
        let firstSection = (largestValidSection == nil) ? 0 : largestValidSection!+1
        
        guard firstSection <= section else { return }
        
        debugPrint("🐶 \(Date().epochInMs) Adjusting from section \(firstSection) until \(section) (included)")
        
        // Adjust the relative origins of the items of all section until the current one (including it)
        
        for sectionOfItemsToAdjust in firstSection...section {
            let lastItem = cachedItemInfos[sectionOfItemsToAdjust].count-1
            adjustRelativeOriginOfLayoutItemInfosInSection(sectionOfItemsToAdjust, untilItem: lastItem)
        }

        // Adjust the origin of all the sections between the first section having a valid origin and the section passed as a parameter

        for sec in firstSection..<section+1 {
            
            let infos = cachedSectionInfos[sec]
            let topSpace = interSectionSpacing
            let origin = CGPoint(x: sectionXOrigin, y: previousSectionFrame.maxY + topSpace)
            let size = infos.frame.size
            let sectionFrame = CGRect(origin: origin, size: size)
            let updatedInfos = ObvCollectionViewLayoutSectionInfos(
                frame: sectionFrame,
                largestItemWithValidOrigin: infos.largestItemWithValidOrigin)
            cachedSectionInfos[sec] = updatedInfos
            
            previousSectionFrame = sectionFrame
            
        }
        
        largestValidSection = section
        
    }

    
    /// This method adjusts the origin of the cached infos of all the items within the section passed as a parameter,
    /// starting right after the largest valid item, until the item passed as a parameter (included)
    ///
    /// - Parameter indexPath: The index path of the item to adjust.
    private func adjustRelativeOriginOfLayoutItemInfosInSection(_ section: Int, untilItem lastItem: Int) {
        
        let sectionInfos = cachedSectionInfos[section]
        guard sectionInfos.largestItemWithValidOrigin == nil || lastItem > sectionInfos.largestItemWithValidOrigin! else { return }
        
        let firstItemToAdjust: Int
        var previousElementFrame: CGRect
        if let item = sectionInfos.largestItemWithValidOrigin {
            previousElementFrame = cachedItemInfos[section][item].frameInSection
            firstItemToAdjust = item+1
        } else {
            previousElementFrame = cachedSupplementaryViewInfos[section].frameInSection
            firstItemToAdjust = 0
        }
        
        debugPrint("🐶 \(Date().epochInMs) In section \(section), adjusting from item \(firstItemToAdjust) until \(lastItem) (included)")

        for item in firstItemToAdjust...lastItem {
            
            let infos = cachedItemInfos[section][item]
            let topSpace = interItemSpacing
            let origin = CGPoint(x: 0, y: previousElementFrame.maxY + topSpace)
            let size = infos.frameInSection.size
            let frame = CGRect(origin: origin, size: size)
            let updatedInfos = OlvidCollectionViewLayoutItemInfos(frameInSection: frame, usesPreferredAttributes: infos.usesPreferredAttributes)
            cachedItemInfos[section][item] = updatedInfos
            
            previousElementFrame = frame
            
        }
        
        cachedSectionInfos[section] = ObvCollectionViewLayoutSectionInfos(frame: sectionInfos.frame, largestItemWithValidOrigin: lastItem)
    }

}


extension UICollectionViewUpdateItem.Action: CustomDebugStringConvertible {
    
    public var debugDescription: String {
        switch self {
        case .insert: return "insert"
        case .delete: return "delete"
        case .reload: return "reload"
        case .move: return "move"
        case .none: return "none"
        @unknown default:
            return "unknown"
        }
    }
}



fileprivate struct OlvidCollectionViewLayoutItemInfos {
    
    let frameInSection: CGRect
    let usesPreferredAttributes: Bool
    
    /// Return the frame of the item in the collection view
    ///
    /// - Parameter sectionInfos: The section infos of the section containing this item
    /// - Returns: The frame of this item in the collection view
    func getFrame(using sectionInfos: ObvCollectionViewLayoutSectionInfos) -> CGRect {
        let origin = CGPoint(x: sectionInfos.frame.origin.x + frameInSection.origin.x,
                             y: sectionInfos.frame.origin.y + frameInSection.origin.y)
        let size = frameInSection.size
        let frame = CGRect(origin: origin, size: size)
        return frame
    }
}
