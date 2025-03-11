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


public struct PersistedOneToOneDiscussionStructure {

    public let contactIdentity: PersistedObvContactIdentityStructure
    fileprivate let discussionStruct: PersistedDiscussionAbstractStructure
    var title: String { discussionStruct.title }
    var localConfiguration: PersistedDiscussionLocalConfigurationStructure { discussionStruct.localConfiguration }
    var ownedCryptoId: ObvCryptoId { discussionStruct.ownedCryptoId }
    var ownedIdentity: PersistedObvOwnedIdentityStructure { discussionStruct.ownedIdentity }
    
    public init(contactIdentity: PersistedObvContactIdentityStructure, discussionStruct: PersistedDiscussionAbstractStructure) {
        self.contactIdentity = contactIdentity
        self.discussionStruct = discussionStruct
    }
    
    
    public var identifier: ObvDiscussionIdentifier {
        .oneToOne(id: contactIdentity.contactIdentifier)
    }
    
    
    /// This is used by the `ObvCommunicationMapper` to specify the `conversationIdentifier` of certain intents.
    /// We leverage the (almost) `LosslessStringConvertible` conformance of `ObvDiscussionIdentifier`.
    public var conversationIdentifier: String {
        self.identifier.description
    }
    
}
