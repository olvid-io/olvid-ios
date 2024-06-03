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
import CoreData
import os.log
import ObvTypes
import OlvidUtils
import ObvEngine
import ObvUICoreData


/// Called prior the processing a discussion deletion requested by an owned identity from the current device. This operation does nothing if the deletion type is `.fromThisDeviceOnly`.
final class SendGlobalDeleteDiscussionJSONOperation: OperationWithSpecificReasonForCancel<SendGlobalDeleteDiscussionJSONOperationReasonForCancel> {

    private let persistedDiscussionObjectID: NSManagedObjectID
    private let deletionType: DeletionType
    private let obvEngine: ObvEngine
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: SendGlobalDeleteDiscussionJSONOperation.self))

    init(persistedDiscussionObjectID: NSManagedObjectID, deletionType: DeletionType, obvEngine: ObvEngine) {
        self.persistedDiscussionObjectID = persistedDiscussionObjectID
        self.obvEngine = obvEngine
        self.deletionType = deletionType
        super.init()
    }

    override func main() {

        guard deletionType != .fromThisDeviceOnly else { return }

        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            
            do {
                
                // We create the PersistedItemJSON instance to send
                
                guard let discussion = try PersistedDiscussion.get(objectID: persistedDiscussionObjectID, within: context) else {
                    return cancel(withReason: .couldNotFindDiscussion)
                }
                
                let deleteDiscussionJSON: DeleteDiscussionJSON
                do {
                    deleteDiscussionJSON = try DeleteDiscussionJSON(persistedDiscussionToDelete: discussion)
                } catch {
                    return cancel(withReason: .couldNotConstructDeleteDiscussionJSON(error: error))
                }
                let itemJSON = PersistedItemJSON(deleteDiscussionJSON: deleteDiscussionJSON)
                
                // Find all the contacts to which this item should be sent.
                
                let contactCryptoIds: Set<ObvCryptoId>
                let ownCryptoId: ObvCryptoId
                switch deletionType {
                case .fromThisDeviceOnly:
                    assertionFailure()
                    return
                case .fromAllOwnedDevices:
                    do {
                        (ownCryptoId, _) = try discussion.getAllActiveParticipants()
                        contactCryptoIds = Set() // Send the request to our other remote devices only
                    } catch {
                        return cancel(withReason: .couldNotGetCryptoIdOfDiscussionParticipants(error: error))
                    }
                case .fromAllOwnedDevicesAndAllContactDevices:
                    do {
                        (ownCryptoId, contactCryptoIds) = try discussion.getAllActiveParticipants()
                    } catch {
                        return cancel(withReason: .couldNotGetCryptoIdOfDiscussionParticipants(error: error))
                    }
                }

                guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownCryptoId, within: context) else {
                    return cancel(withReason: .couldNotFindOwnedIdentity)
                }
                        
                // Create a payload of the PersistedItemJSON we just created and send it.
                // We do not keep track of the message identifiers from engine.
                
                let payload: Data
                do {
                    payload = try itemJSON.jsonEncode()
                } catch {
                    return cancel(withReason: .failedToEncodePersistedItemJSON)
                }
                
                guard !contactCryptoIds.isEmpty || ownedIdentity.devices.count > 1 else { return }
                
                do {
                    _ = try obvEngine.post(messagePayload: payload,
                                           extendedPayload: nil,
                                           withUserContent: false,
                                           isVoipMessageForStartingCall: false,
                                           attachmentsToSend: [],
                                           toContactIdentitiesWithCryptoId: contactCryptoIds,
                                           ofOwnedIdentityWithCryptoId: ownCryptoId,
                                           alsoPostToOtherOwnedDevices: true)
                } catch {
                    return cancel(withReason: .couldNotPostMessageWithinEngine)
                }
                
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
        }
        
    }
    
}


enum SendGlobalDeleteDiscussionJSONOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case couldNotFindDiscussion
    case couldNotConstructDeleteDiscussionJSON(error: Error)
    case couldNotGetCryptoIdOfDiscussionParticipants(error: Error)
    case failedToEncodePersistedItemJSON
    case couldNotPostMessageWithinEngine
    case couldNotFindOwnedIdentity
    
    var logType: OSLogType {
        switch self {
        case .coreDataError,
             .couldNotFindDiscussion,
             .couldNotGetCryptoIdOfDiscussionParticipants,
             .failedToEncodePersistedItemJSON,
             .couldNotPostMessageWithinEngine,
             .couldNotFindOwnedIdentity,
             .couldNotConstructDeleteDiscussionJSON:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotFindDiscussion:
            return "Could not find discussion"
        case .couldNotConstructDeleteDiscussionJSON(error: let error):
            return "Could not construct the DeleteDiscussionJSON instance: \(error.localizedDescription)"
        case .couldNotGetCryptoIdOfDiscussionParticipants(error: let error):
            return "Could not get the cryptoId of the discussion participants: \(error.localizedDescription)"
        case .failedToEncodePersistedItemJSON:
            return "We failed to encode the persisted item JSON"
        case .couldNotPostMessageWithinEngine:
            return "We failed to post the serialized DeleteMessagesJSON within the engine"
        case .couldNotFindOwnedIdentity:
            return "Could not find owned identity"
        }
    }

}
