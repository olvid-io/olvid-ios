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
import ObvFlowManager
import ObvSettings


final class DiscussionCollectionView: UICollectionView {
    
    func adjustedScrollToItem(at indexPath: IndexPath, at scrollPosition: UICollectionView.ScrollPosition, completion: @escaping () -> Void) {
        adjustedScrollToItem(at: indexPath, at: scrollPosition, limit: 10_000, completion: completion)
    }
    
    
    private func adjustedScrollToItem(at indexPath: IndexPath, at scrollPosition: UICollectionView.ScrollPosition, limit: Int, completion: @escaping () -> Void) {

        switch ObvMessengerSettings.Interface.discussionLayoutType {
        case .productionLayout:

            guard let layout = collectionViewLayout as? DiscussionLayout else { completion(); return }
            guard let itemLayoutInfos = layout.getCurrentLayoutInfosOfItem(at: indexPath) else { assertionFailure(); completion(); return }
            guard limit > 0 else { completion(); return }
            
            guard indexPath.section < numberOfSections && indexPath.item < numberOfItems(inSection: indexPath.section) else { completion(); return  }
            // 2024-02-28 Commenting out the following test. It prevents the animation of the scroll during search
            //UIView.performWithoutAnimation {
                scrollToItem(at: indexPath, at: scrollPosition, animated: false)
            //}
            DispatchQueue.main.async { [weak self] in
                if itemLayoutInfos.usesPreferredAttributes && self?.indexPathsForVisibleItems.contains(indexPath) == true {
                    completion()
                } else {
                    let newLimit = limit - 1
                    self?.adjustedScrollToItem(at: indexPath, at: scrollPosition, limit: newLimit, completion: completion)
                }
            }

        case .listLayout:
            
            self.scrollToItem(at: indexPath, at: scrollPosition, animated: false)
            completion()
            
        }
        
    }
    
    
    func adjustedScrollToBottom(completion: @escaping () -> Void) {
        guard let lastIndexPath = self.lastIndexPath else { completion(); return }
        adjustedScrollToItem(at: lastIndexPath, at: .bottom, completion: completion)
    }
        

    var lastIndexPath: IndexPath? {
        for section in (0..<numberOfSections).reversed() {
            for item in (0..<numberOfItems(inSection: section)).reversed() {
                return IndexPath(item: item, section: section)
            }
        }
        return nil
    }
}
