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
import CoreData

protocol CellWithMessage: UICollectionViewCell {

    var persistedMessageObjectID: TypeSafeManagedObjectID<PersistedMessage>? { get }
    var persistedDraftObjectID: TypeSafeManagedObjectID<PersistedDraft>? { get }
    var viewForTargetedPreview: UIView { get }

    var textToCopy: String? { get }

    var fyleMessagesJoinWithStatus: [FyleMessageJoinWithStatus]? { get } // Legacy, used within the old discussion screen, replaced by itemProvidersForAllAttachments
    var imageAttachments: [FyleMessageJoinWithStatus]? { get } // Legacy, used within the old discussion screen, replaced by itemProvidersForImages
    var itemProvidersForImages: [UIActivityItemProvider]? { get }
    var itemProvidersForAllAttachments: [UIActivityItemProvider]? { get }

    var infoViewController: UIViewController? { get }

}
