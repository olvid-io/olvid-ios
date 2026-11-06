/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvTypes
import ObvUICoreData
import ObvAppTypes


protocol SomeSingleDiscussionViewController: UIViewController {
    var discussionId: ObvDiscussionIdentifier? { get } // Non-nil, unless the identifier cannot be determined, which may hapen with locked discussions
    var discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion> { get }
    var discussionPermanentID: DiscussionPermanentID { get }
    var currentOwnedCryptoId: ObvCryptoId { get }
    func addAttachmentFromAirDropFile(at url: URL)
    func scrollTo(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>)

    // The keyboard's find shortcuts — ⌘F, ⌘G and ⇧⌘G. They are declared here so that `MainFlowViewController`, which is where the responder chain answers them, can
    // hand them to whichever discussion is showing without knowing which of the two screens it is. They are also `UIResponderStandardEditActions` methods, whose
    // optionality in Objective-C makes a call through a protocol that does not name them awkward; naming them settles it.
    func find(_ sender: Any?)
    func findNext(_ sender: Any?)
    func findPrevious(_ sender: Any?)
}
