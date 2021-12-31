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

@available(iOS 13.0, *)
extension UIContextMenuConfiguration {
    
    convenience init(indexPath: IndexPath, previewProvider: UIContextMenuContentPreviewProvider?, actionProvider: UIContextMenuActionProvider? = nil) {
        let indexPathDescription = "\(indexPath.section)-\(indexPath.item)"
        self.init(identifier: indexPathDescription as NSString,
                  previewProvider: nil,
                  actionProvider: actionProvider)
    }
    
    var indexPath: IndexPath? {
        guard let indexPathDescription = self.identifier as? String else { return nil }
        let indexPathElements = indexPathDescription.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
        guard indexPathElements.count == 2 else { return nil }
        guard let section = Int(indexPathElements[0]) else { return nil }
        guard let item = Int(indexPathElements[1]) else { return nil }
        return IndexPath(item: item, section: section)
    }

}
