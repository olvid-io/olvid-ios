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

import Foundation
import CoreData
import OlvidUtils
import ObvMetaManager
import ObvTypes
import ObvCrypto


/// Starts a contact device discovery during bootstrap. Records when this bootstrap is performed, so that we don't execute it too often.
final class BootstrapContactDeviceDiscoveryProtocolOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private let contactIdentifier: ObvContactIdentifier
    private let prng: PRNGService
    private let identityDelegate: ObvIdentityDelegate
    private let protocolDelegate: ObvProtocolDelegate
    private let channelDelegate: ObvChannelDelegate

    init(contactIdentifier: ObvContactIdentifier, prng: PRNGService, identityDelegate: ObvIdentityDelegate, protocolDelegate: ObvProtocolDelegate, channelDelegate: ObvChannelDelegate) {
        self.contactIdentifier = contactIdentifier
        self.prng = prng
        self.identityDelegate = identityDelegate
        self.protocolDelegate = protocolDelegate
        self.channelDelegate = channelDelegate
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        do {
            try identityDelegate.setDateOfLastBootstrappedContactDeviceDiscovery(
                forContactCryptoId: contactIdentifier.contactCryptoId.cryptoIdentity,
                ofOwnedCryptoId: contactIdentifier.ownedCryptoId.cryptoIdentity,
                to: .now,
                within: obvContext)
            let message = try protocolDelegate.getInitialMessageForContactDeviceDiscoveryProtocol(
                ownedIdentity: contactIdentifier.ownedCryptoId.cryptoIdentity,
                contactIdentity: contactIdentifier.contactCryptoId.cryptoIdentity)
            _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }

    }
    
}
