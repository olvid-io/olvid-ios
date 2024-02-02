/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import os.log
import CoreData
import OlvidUtils
import ObvMetaManager
import ObvCrypto
import ObvTypes


final class SendTargetedPingMessageForKeycloakGroupV2ProtocolWhereContactIsPendingMemberOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    private let identityDelegate: ObvIdentityDelegate
    private let channelDelegate: ObvChannelDelegate
    private let protocolDelegate: ObvProtocolDelegate
    private let prng: PRNGService
    private let contactIdentifiers: Set<ObvContactIdentifier>
    private let log: OSLog

    init(identityDelegate: ObvIdentityDelegate, channelDelegate: ObvChannelDelegate, protocolDelegate: ObvProtocolDelegate, prng: PRNGService, contactIdentifiers: Set<ObvContactIdentifier>, logSubsystem: String) {
        self.identityDelegate = identityDelegate
        self.channelDelegate = channelDelegate
        self.protocolDelegate = protocolDelegate
        self.prng = prng
        self.contactIdentifiers = contactIdentifiers
        self.log = OSLog(subsystem: logSubsystem, category: "SendTargetedPingMessageForKeycloakGroupV2ProtocolWhereContactIsMemberOperation")
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        for contactIdentifier in contactIdentifiers {
            
            let ownedIdentity = contactIdentifier.ownedCryptoId.cryptoIdentity
            let contactIdentity = contactIdentifier.contactCryptoId.cryptoIdentity
            
            do {
                let groupIdentifiers = try identityDelegate.getIdentifiersOfAllKeycloakGroupsWhereContactIsPending(ownedCryptoId: ownedIdentity, contactCryptoId: contactIdentity, within: obvContext)

                groupIdentifiers.forEach { groupIdentifier in
                    do {
                        let msg = try protocolDelegate.getInitiateTargetedPingMessageForKeycloakGroupV2Protocol(ownedIdentity: ownedIdentity, groupIdentifier: groupIdentifier, pendingMemberIdentity: contactIdentity, flowId: obvContext.flowId)
                        _ = try channelDelegate.postChannelMessage(msg, randomizedWith: prng, within: obvContext)
                    } catch {
                        os_log("Could not ping contact in a keycloak groups where she is pending (1): %{public}@", log: self.log, type: .fault, error.localizedDescription)
                    }
                }
                
            } catch {
                assertionFailure(error.localizedDescription)
                os_log("Could not ping contact in a keycloak groups where she is pending (2): %{public}@", log: self.log, type: .fault, error.localizedDescription)
            }
            
        }

    }
        
}
