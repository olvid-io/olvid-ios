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
import ObvUICoreData

extension UIApplication {
    
    public func userSelectedURL(_ url: URL, within viewController: UIViewController) async {
        await userSelectedURL(url, within: viewController, confirmed: false)
    }
    
    
    @MainActor
    private func userSelectedURL(_ url: URL, within viewController: UIViewController, confirmed: Bool) async {

        if confirmed {

            guard url.scheme?.lowercased() == "https" else { assertionFailure(); return }
            open(url, options: [:], completionHandler: nil)

        } else {

            guard let safeURL = url.toHttpsURL else { assertionFailure(); return }
            
            let alert = UIAlertController(title: Strings.AlertOpenURL.title,
                                          message: Strings.AlertOpenURL.message(safeURL),
                                          preferredStyleForTraitCollection: viewController.traitCollection)

            alert.addAction(UIAlertAction(title: Strings.AlertOpenURL.openButton, style: .default, handler: { [weak self] (action) in
                Task { await self?.userSelectedURL(safeURL, within: viewController, confirmed: true) }
            }))

            alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))
            DispatchQueue.main.async {
                viewController.present(alert, animated: true, completion: nil)
            }

        }

    }
}

extension UIApplication {
    
    struct Strings {
        
        struct AlertOpenURL {
            static let title = NSLocalizedString("Open in Safari?", comment: "Alert title")
            static let message = { (url: URL) in
                String.localizedStringWithFormat(NSLocalizedString("Do you wish to open %@ in Safari?", comment: "Alert message"), url.absoluteString)
            }
            static let openButton = NSLocalizedString("Open", comment: "Alert button title")
        }
        
    }
        
}
