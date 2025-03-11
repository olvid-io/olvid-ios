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


public struct PersistedGroupV2DiscussionStructure {

    let groupIdentifier: Data
    let ownerIdentity: PersistedObvOwnedIdentityStructure
    public let group: PersistedGroupV2Structure
    fileprivate let discussionStruct: PersistedDiscussionAbstractStructure
    public var title: String { discussionStruct.title }
    var localConfiguration: PersistedDiscussionLocalConfigurationStructure { discussionStruct.localConfiguration }
    var ownedCryptoId: ObvCryptoId { discussionStruct.ownedCryptoId }
    var ownedIdentity: PersistedObvOwnedIdentityStructure { discussionStruct.ownedIdentity }
    
    public init(groupIdentifier: Data, ownerIdentity: PersistedObvOwnedIdentityStructure, group: PersistedGroupV2Structure, discussionStruct: PersistedDiscussionAbstractStructure) {
        self.groupIdentifier = groupIdentifier
        self.ownerIdentity = ownerIdentity
        self.group = group
        self.discussionStruct = discussionStruct
    }
    
    
    var identifier: ObvDiscussionIdentifier {
        .groupV2(id: group.obvGroupIdentifier)
    }

    
    /// This is used by the `ObvCommunicationMapper` to specify the `conversationIdentifier` of certain intents.
    /// We leverage the (almost) `LosslessStringConvertible` conformance of `ObvDiscussionIdentifier`.
    public var conversationIdentifier: String {
        self.identifier.description
    }

}
