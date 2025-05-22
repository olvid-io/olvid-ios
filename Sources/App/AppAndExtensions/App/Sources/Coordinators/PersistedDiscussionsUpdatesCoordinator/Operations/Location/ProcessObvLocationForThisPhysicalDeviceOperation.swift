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
import OSLog
import CoreData
import OlvidUtils
import ObvUICoreData
import ObvAppTypes
import ObvTypes


final class ProcessObvLocationForThisPhysicalDeviceOperation: ContextualOperationWithSpecificReasonForCancel<ProcessObvLocationForThisPhysicalDeviceOperation.ReasonForCancel>, @unchecked Sendable {
    
    private let obvLocation: ObvLocation
    
    init(obvLocation: ObvLocation) {
        self.obvLocation = obvLocation
        super.init()
    }
    
    private(set) var unprocessedMessagesToSend = Set<MessageSentPermanentID>()
    private(set) var updateMessageJSONsToSend = Set<UpdateMessageJSONToSend>()

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            switch obvLocation {

            case .send(let locationData, let discussionIdentifier):
                
                guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: discussionIdentifier.ownedCryptoId, within: obvContext.context) else {
                    assertionFailure()
                    return cancel(withReason: .couldNotFindOwnedIdentityInDatabase)
                }

                guard ownedIdentity.isActive else {
                    assertionFailure()
                    return cancel(withReason: .ownedIdentityIsInactive)
                }

                let unprocessedMessageToSend = try ownedIdentity.createPersistedLocationOneShotSent(locationData: locationData, discussionIdentifier: discussionIdentifier)
                
                unprocessedMessagesToSend.insert(unprocessedMessageToSend)

            case .startSharing(let locationData, let discussionIdentifier, let expirationDate):
                
                guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: discussionIdentifier.ownedCryptoId, within: obvContext.context) else {
                    assertionFailure()
                    return cancel(withReason: .couldNotFindOwnedIdentityInDatabase)
                }

                guard ownedIdentity.isActive else {
                    assertionFailure()
                    return cancel(withReason: .ownedIdentityIsInactive)
                }

                let (unprocessedMessagesToSend, updatedSentMessages) = try ownedIdentity.createPersistedLocationContinuousSentForCurrentOwnedDevice(locationData: locationData, expirationDate: expirationDate, discussionIdentifier: discussionIdentifier)

                self.unprocessedMessagesToSend.formUnion(unprocessedMessagesToSend)
                self.updateMessageJSONsToSend.formUnion(try updatedSentMessages.map({ try $0.toUpdateMessageJSONToSend() }))

            case .updateSharing(let locationData):
                
                let ownedIdentities = try PersistedObvOwnedIdentity.getAllActive(within: obvContext.context)
                
                for ownedIdentity in ownedIdentities {
                    let (unprocessedMessagesToSend, updatedSentMessages) = try ownedIdentity.updatePersistedLocationContinuousSent(locationData: locationData)
                    self.unprocessedMessagesToSend.formUnion(unprocessedMessagesToSend)
                    self.updateMessageJSONsToSend.formUnion(try updatedSentMessages.map({ try $0.toUpdateMessageJSONToSend() }))
                }

            case .endSharing(let type):
                
                switch type {
                    
                case .discussion(discussionIdentifier: let discussionIdentifier):

                    guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: discussionIdentifier.ownedCryptoId, within: obvContext.context) else {
                        assertionFailure()
                        return cancel(withReason: .couldNotFindOwnedIdentityInDatabase)
                    }

                    guard ownedIdentity.isActive else {
                        assertionFailure()
                        return cancel(withReason: .ownedIdentityIsInactive)
                    }

                    let updatedSentMessages = try ownedIdentity.endPersistedLocationContinuousSentInDiscussion(discussionIdentifier: discussionIdentifier)
                    self.updateMessageJSONsToSend.formUnion(try updatedSentMessages.map({ try $0.toUpdateMessageJSONToSend() }))

                case .all:
                    
                    let ownedIdentities = try PersistedObvOwnedIdentity.getAllActive(within: obvContext.context)

                    for ownedIdentity in ownedIdentities {
                        let updatedSentMessages = try ownedIdentity.endPersistedLocationContinuousSentInAllDiscussions()
                        self.updateMessageJSONsToSend.formUnion(try updatedSentMessages.map({ try $0.toUpdateMessageJSONToSend() }))
                    }
                    
                }
                
            }
            
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        case coreDataError(error: Error)
        case couldNotFindOwnedIdentityInDatabase
        case ownedIdentityIsInactive
        
        var logType: OSLogType {
            switch self {
            case .coreDataError, .couldNotFindOwnedIdentityInDatabase, .ownedIdentityIsInactive:
                return .fault
            }
        }
        
        var errorDescription: String? {
            switch self {
            case .coreDataError(error: let error): return "Core Data error: \(error.localizedDescription)"
            case .couldNotFindOwnedIdentityInDatabase: return "Could not obtain persisted owned identity in database"
            case .ownedIdentityIsInactive: return "Owned identity is inactive"
            }
        }
        
    }

}

