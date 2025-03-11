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

import Foundation
import ObvTypes
import ObvAppTypes


public struct PersistedGroupDiscussionStructure {
    
    let groupUID: Data
    let ownerIdentity: PersistedObvOwnedIdentityStructure
    public let contactGroup: PersistedContactGroupStructure
    fileprivate let discussionStruct: PersistedDiscussionAbstractStructure
    public var title: String { discussionStruct.title }
    var localConfiguration: PersistedDiscussionLocalConfigurationStructure { discussionStruct.localConfiguration }
    var ownedCryptoId: ObvCryptoId { discussionStruct.ownedCryptoId }
    var ownedIdentity: PersistedObvOwnedIdentityStructure { discussionStruct.ownedIdentity }
    
    public init(groupUID: Data, ownerIdentity: PersistedObvOwnedIdentityStructure, contactGroup: PersistedContactGroupStructure, discussionStruct: PersistedDiscussionAbstractStructure) {
        self.groupUID = groupUID
        self.ownerIdentity = ownerIdentity
        self.contactGroup = contactGroup
        self.discussionStruct = discussionStruct
    }
    
    
    var identifier: ObvDiscussionIdentifier {
        .groupV1(id: contactGroup.obvGroupIdentifier)
    }

    
    /// This is used by the `ObvCommunicationMapper` to specify the `conversationIdentifier` of certain intents.
    /// We leverage the (almost) `LosslessStringConvertible` conformance of `ObvDiscussionIdentifier`.
    public var conversationIdentifier: String {
        self.identifier.description
    }

}
