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
import ObvEngine
import ObvUICoreData


// 2020-09-30 Not used for now
final class CircledInitialsBarButtonItem: UIBarButtonItem {
    
    static func createFor(ownedIdentity: PersistedObvOwnedIdentity, target: Any?, selector: Selector) -> CircledInitialsBarButtonItem {
        assert(Thread.isMainThread)
        assert(ownedIdentity.managedObjectContext == ObvStack.shared.viewContext)
        let ownCircleInitials = (Bundle.main.loadNibNamed(CircledInitials.nibName, owner: nil, options: nil)!.first as! CircledInitials)
        ownCircleInitials.showCircledText(from: ownedIdentity.identityCoreDetails.getDisplayNameWithStyle(.firstNameThenLastName))
        ownCircleInitials.identityColors = ownedIdentity.cryptoId.colors
        let constraints = [
            ownCircleInitials.widthAnchor.constraint(equalToConstant: 30.0),
            ownCircleInitials.heightAnchor.constraint(equalToConstant: 30.0),
        ]
        ownCircleInitials.isUserInteractionEnabled = false
        NSLayoutConstraint.activate(constraints)
        let button = UIButton(type: .custom)
        button.addSubview(ownCircleInitials)
        button.addTarget(target, action: selector, for: .touchUpInside)
        return CircledInitialsBarButtonItem(customView: button)
    }
    
}
