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

import Foundation
import CoreData
import os.log
import ObvEngine
import OlvidUtils

final class SendPersistedDiscussionSharedConfigurationOperation: OperationWithSpecificReasonForCancel<SendPersistedDiscussionSharedConfigurationOperationReasonForCancel> {
    
    private let persistedDiscussionObjectID: NSManagedObjectID
    private let obvEngine: ObvEngine
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: SendPersistedDiscussionSharedConfigurationOperation.self))

    init(persistedDiscussionObjectID: NSManagedObjectID, obvEngine: ObvEngine) {
        self.persistedDiscussionObjectID = persistedDiscussionObjectID
        self.obvEngine = obvEngine
        super.init()
    }

    override func main() {
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            
            // We create the PersistedItemJSON instance to send

            let sharedConfig: PersistedDiscussionSharedConfiguration
            do {
                guard let discussion = try PersistedDiscussion.get(objectID: persistedDiscussionObjectID, within: context) else {
                    return cancel(withReason: .configCannotBeFound)
                }
                sharedConfig = discussion.sharedConfiguration
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }

            let sharedConfigJSON: DiscussionSharedConfigurationJSON
            do {
                sharedConfigJSON = try sharedConfig.toJSON()
            } catch {
                return cancel(withReason: .couldNotComputeJSON)
            }
            let itemJSON = PersistedItemJSON(discussionSharedConfiguration: sharedConfigJSON)
            
            guard let discussion = sharedConfig.discussion else {
                return cancel(withReason: .couldNotFindDiscussion)
            }
            
            // Find all the contacts to which this item should be sent.
            // If the discussion is a group discussion, we make sure we are the owner of the group.
            
            let contactCryptoIds: Set<ObvCryptoId>
            let ownCryptoId: ObvCryptoId
            do {
                switch try discussion.kind {
                case .oneToOne(withContactIdentity: let contactIdentity):
                    guard let contactIdentity = contactIdentity else {
                        os_log("Could not find contact identity", log: log, type: .fault)
                        return cancel(withReason: .couldNotFindContactIdentity)
                    }
                    contactCryptoIds = Set([contactIdentity.cryptoId])
                    guard let _ownCryptoId = discussion.ownedIdentity?.cryptoId else {
                        return cancel(withReason: .couldNotDetermineOwnedCryptoId)
                    }
                    ownCryptoId = _ownCryptoId
                case .groupV1(withContactGroup: let contactGroup):
                    guard let contactGroup = contactGroup else {
                        return cancel(withReason: .couldNotFindContactGroup)
                    }
                    guard contactGroup.category == .owned else {
                        // When the group is not owned, we do not send the configuration.
                        // Only the group owner can do that.
                        return
                    }
                    contactCryptoIds = Set(contactGroup.contactIdentities.map({ $0.cryptoId }))
                    guard let _ownCryptoId = discussion.ownedIdentity?.cryptoId else {
                        return cancel(withReason: .couldNotDetermineOwnedCryptoId)
                    }
                    ownCryptoId = _ownCryptoId
                }
            } catch {
                return cancel(withReason: .unexpectedDiscussionType)
            }

            // Create a payload of the PersistedItemJSON we just created and send it.
            // We do not keep track of the message identifiers from engine.
            
            let payload: Data
            do {
                payload = try itemJSON.jsonEncode()
            } catch {
                os_log("Could not encode the shared discussion settings: %{public}@", log: log, type: .fault, error.localizedDescription)
                return cancel(withReason: .failedToEncodeSettings)
            }
            
            if !contactCryptoIds.isEmpty {
                do {
                    _ = try obvEngine.post(messagePayload: payload,
                                           extendedPayload: nil,
                                           withUserContent: false,
                                           isVoipMessageForStartingCall: false,
                                           attachmentsToSend: [],
                                           toContactIdentitiesWithCryptoId: contactCryptoIds,
                                           ofOwnedIdentityWithCryptoId: ownCryptoId)
                } catch {
                    return cancel(withReason: .couldNotPostMessageWithinEngine)
                }
            }
            
        }
        
    }
    
}


enum SendPersistedDiscussionSharedConfigurationOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case configCannotBeFound
    case failedToEncodeSettings
    case couldNotFindContactIdentity
    case couldNotFindContactGroup
    case unexpectedDiscussionType
    case couldNotDetermineOwnedCryptoId
    case couldNotPostMessageWithinEngine
    case couldNotComputeJSON
    case couldNotFindDiscussion
    
    var logType: OSLogType {
        switch self {
        case .coreDataError,
             .failedToEncodeSettings,
             .couldNotFindContactIdentity,
             .couldNotFindContactGroup,
             .couldNotDetermineOwnedCryptoId,
             .couldNotPostMessageWithinEngine,
             .couldNotComputeJSON,
             .couldNotFindDiscussion:
            return .fault
        case .configCannotBeFound,
             .unexpectedDiscussionType:
            return .error
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .couldNotFindDiscussion:
            return "Could not find discussion"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .configCannotBeFound:
            return "Could not find shared configuration in database"
        case .failedToEncodeSettings:
            return "We failed to encode the discussion shared settings"
        case .couldNotFindContactIdentity:
            return "Could not find the contact identity of the One2One discussion associated to the shared settings to send"
        case .couldNotFindContactGroup:
            return "Could not find the contact group of the group discussion associated with the shared settings to send"
        case .unexpectedDiscussionType:
            return "We are trying to share the settings of a discussion that is not a One2One nor a group discussion"
        case .couldNotDetermineOwnedCryptoId:
            return "We could not determine the owned crypto identity associated with the discussion"
        case .couldNotPostMessageWithinEngine:
            return "We failed to post the serialized discussion shared settings within the engine"
        case .couldNotComputeJSON:
            return "Could not compute JSON"
        }
    }

}
