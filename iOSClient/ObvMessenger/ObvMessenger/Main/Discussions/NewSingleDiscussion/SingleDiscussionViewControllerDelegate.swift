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
import ObvEngine
import ObvUICoreData

protocol SingleDiscussionViewControllerDelegate: AnyObject {
    
    func userTappedTitleOfDiscussion(_ discussion: PersistedDiscussion)
    func userDidTapOnContactImage(contactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>)


    /// Delegation method called whenever a user taps on a user mention within the text
    /// - Parameters:
    ///   - viewController: An instance of ``SomeSingleDiscussionViewController``.
    ///   - mentionableIdentity: An instance of ``ObvMentionableIdentityAttribute.Value`` that the user tapped.
    func singleDiscussionViewController(_ viewController: SomeSingleDiscussionViewController, userDidTapOn mentionableIdentity: ObvMentionableIdentityAttribute.Value) async
}
