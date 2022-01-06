/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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


protocol ViewControllerWithEllipsisCircleRightBarButtonItem: UIViewController {}


extension ViewControllerWithEllipsisCircleRightBarButtonItem {
    
    @available(iOS, introduced: 14.0)
    func getConfiguredEllipsisCircleRightBarButtonItem() -> UIBarButtonItem {
        let menu = getFirstMenuAvailable()
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
        let ellipsisImage = UIImage(systemIcon: .ellipsisCircle, withConfiguration: symbolConfiguration)
        let ellipsisButton = UIBarButtonItem(
            title: "Menu",
            image: ellipsisImage,
            primaryAction: nil,
            menu: menu)
        return ellipsisButton
    }

    
    @available(iOS, introduced: 13.0, deprecated: 14.0, message: "Used because iOS 13 does not support UIMenu on UIBarButtonItem")
    func getConfiguredEllipsisCircleRightBarButtonItem(selector: Selector) -> UIBarButtonItem {
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
        let ellipsisImage = UIImage(systemIcon: .ellipsisCircle, withConfiguration: symbolConfiguration)
        let ellipsisButton = UIBarButtonItem.init(image: ellipsisImage, style: UIBarButtonItem.Style.plain, target: self, action: selector)
        return ellipsisButton
    }

    
    @available(iOS, introduced: 13.0, deprecated: 14.0, message: "Used because iOS 13 does not support UIMenu on UIBarButtonItem")
    func ellipsisButtonTapped(sourceBarButtonItem: UIBarButtonItem?) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.popoverPresentationController?.barButtonItem = sourceBarButtonItem
        let alertActions = getFirstAlertActionsAvailable()
        assert(!alertActions.isEmpty)
        alertActions.forEach { alert.addAction($0) }
        alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))
        if let presentedViewController = presentedViewController {
            presentedViewController.dismiss(animated: true) { [weak self] in
                self?.present(alert, animated: true)
            }
        } else {
            present(alert, animated: true)
        }
    }

}
