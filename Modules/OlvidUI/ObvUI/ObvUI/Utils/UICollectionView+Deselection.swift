/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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

public extension UICollectionView {
    /// Deselects the currently selected items with our transition coordinator, if present
    /// - Parameters:
    ///   - transitionCoordinator: The transition coordinator to coordinate the deselection
    ///   - animated: Should we animated this change
    func deselectItems(with transitionCoordinator: UIViewControllerTransitionCoordinator?, animated: Bool) {
        guard let selectedIndexPaths = self.indexPathsForSelectedItems,
              selectedIndexPaths.isEmpty == false else {
            return
        }

        guard let coordinator = transitionCoordinator else {
            selectedIndexPaths.forEach {
                deselectItem(at: $0, animated: animated)
            }

            return
        }

        coordinator.animate(alongsideTransition: { _ in
            selectedIndexPaths.forEach {
                self.deselectItem(at: $0, animated: animated)
            }
        },
                            completion: { context in
                                if context.isCancelled {
                                    selectedIndexPaths.forEach {
                                        self.selectItem(at: $0, animated: animated, scrollPosition: [])
                                    }
                                }
        })
    }
}
