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

final class ObvCollectionView: UICollectionView {
    
    
    override func deleteItems(at indexPaths: [IndexPath]) {
        (collectionViewLayout as? ObvCollectionViewLayout)?.deletedIndexPathBeforeUpdate.append(contentsOf: indexPaths)
        super.deleteItems(at: indexPaths)
    }
    
    
    override func deleteSections(_ sections: IndexSet) {
        (collectionViewLayout as? ObvCollectionViewLayout)?.deletedSectionsBeforeUpdate.formUnion(sections)
        super.deleteSections(sections)
    }
    
    
    override func insertSections(_ sections: IndexSet) {
        (collectionViewLayout as? ObvCollectionViewLayout)?.insertedSectionsAfterUpdate.formUnion(sections)
        super.insertSections(sections)
    }
    
    
    override func insertItems(at indexPaths: [IndexPath]) {
        (collectionViewLayout as? ObvCollectionViewLayout)?.insertedIndexPathsAfterUpdate.append(contentsOf: indexPaths)
        super.insertItems(at: indexPaths)
    }
    
    override func moveItem(at indexPath: IndexPath, to newIndexPath: IndexPath) {
        (collectionViewLayout as? ObvCollectionViewLayout)?.movedIndexPaths[newIndexPath] = indexPath
        super.moveItem(at: indexPath, to: newIndexPath)
    }
    
}


extension ObvCollectionView {
    
    var lastIndexPathIsVisible: Bool {
        guard numberOfSections > 0 else { return true }
        let lastSection = numberOfSections-1
        guard numberOfItems(inSection: lastSection) != 0 else { return true }
        let lastIndexPath = IndexPath(item: numberOfItems(inSection: lastSection)-1, section: lastSection)
        return indexPathsForVisibleItems.contains(lastIndexPath)
    }
    
    func adjustedScrollToItem(at indexPath: IndexPath, at scrollPosition: UICollectionView.ScrollPosition, animated: Bool, completionHandler: (() -> Void)? = nil) {
        
        let animationDuration: TimeInterval = animated ? 0.1 : 0
        let animator = UIViewPropertyAnimator(duration: animationDuration, curve: .linear)
        animator.addAnimations { [weak self] in
            self?.scrollToItem(at: indexPath, at: scrollPosition, animated: false)
        }
        animator.addCompletion { [weak self] (position) in
            guard position == .end else { return }
            if self?.indexPathsForVisibleItems.contains(indexPath) == true {
                // We scroll one last time to make sure the cell is at the right location
                self?.scrollToItem(at: indexPath, at: scrollPosition, animated: animated)
                completionHandler?()
            } else {
                self?.adjustedScrollToItem(at: indexPath, at: scrollPosition, animated: animated, completionHandler: completionHandler)
            }
        }
        animator.startAnimation()

    }
        
}
