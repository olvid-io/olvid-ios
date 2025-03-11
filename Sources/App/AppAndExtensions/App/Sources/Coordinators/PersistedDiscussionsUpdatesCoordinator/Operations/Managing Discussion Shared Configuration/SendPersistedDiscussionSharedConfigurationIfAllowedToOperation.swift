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
import CoreData
import os.log
import ObvEngine
import OlvidUtils
import ObvTypes
import ObvUICoreData
import ObvAppCoreConstants


final class SendPersistedDiscussionSharedConfigurationIfAllowedToOperation: OperationWithSpecificReasonForCancel<SendPersistedDiscussionSharedConfigurationIfAllowedToOperation.ReasonForCancel>, @unchecked Sendable {
    
    private let ownedCryptoId: ObvCryptoId
    private let discussionId: DiscussionIdentifier
    private let obvEngine: ObvEngine
    private let sendTo: SendToOption
    
    enum SendToOption {
        case otherOwnedDevices
        case specificContact(contactCryptoId: ObvCryptoId)
        case allContactsAndOtherOwnedDevices
    }
    
    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: SendPersistedDiscussionSharedConfigurationIfAllowedToOperation.self))

    init(ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, sendTo: SendToOption, obvEngine: ObvEngine) {
        self.ownedCryptoId = ownedCryptoId
        self.discussionId = discussionId
        self.obvEngine = obvEngine
        self.sendTo = sendTo
        super.init()
    }

    override func main() {
        
        // If this operation is dependent on an operation that cancelled, return now
        for dependency in dependencies {
            assert(dependency.isFinished)
            guard !dependency.isCancelled else { return }
        }
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in

            // Get the persisted discussion
            
            let discussion: PersistedDiscussion
            let ownedIdentityHasAnotherReachableDevice: Bool
            do {
                guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: context) else {
                    return cancel(withReason: .couldNotFindOwnedIdentity)
                }
                ownedIdentityHasAnotherReachableDevice = ownedIdentity.hasAnotherDeviceWhichIsReachable
                discussion = try ownedIdentity.getPersistedDiscussion(withDiscussionId: discussionId)
            } catch {
                if let error = error as? ObvUICoreDataError {
                    switch error {
                    case .couldNotFindDiscussion:
                        // This happens when entering in contact as the discussion is not yet available.
                        // The shared configuration will eventually be re-sent, no need to cancel.
                        return
                    default:
                        return cancel(withReason: .coreDataError(error: error))
                    }
                } else {
                    return cancel(withReason: .coreDataError(error: error))
                }
            }
            
            // We create the PersistedItemJSON instance to send

            let sharedConfig = discussion.sharedConfiguration

            // Find all the contacts to which this item should be sent.
            // If the discussion is a group v1 discussion, we make sure we are the owner of the group.
            // If the discussion is a group v2 discussion, we make sure we are allowed to change the settings
            
            let contactCryptoIds: Set<ObvCryptoId>
            do {
                switch try discussion.kind {
                case .oneToOne(withContactIdentity: let contactIdentity):
                    guard let contactIdentity = contactIdentity else {
                        os_log("Could not find contact identity", log: log, type: .fault)
                        return cancel(withReason: .couldNotFindContactIdentity)
                    }
                    contactCryptoIds = Set([contactIdentity.cryptoId])
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
                case .groupV2(withGroup: let group):
                    guard let group = group else {
                        return cancel(withReason: .couldNotFindContactGroup)
                    }
                    guard group.ownedIdentityIsAllowedToChangeSettings else {
                        // If we are not allowed to change settings, we do not send the configuration
                        return
                    }
                    contactCryptoIds = Set(group.otherMembers.filter({ !$0.isPending }).compactMap({ $0.cryptoId }))
                }
            } catch {
                return cancel(withReason: .unexpectedDiscussionType)
            }

            let sharedConfigJSON: DiscussionSharedConfigurationJSON
            do {
                sharedConfigJSON = try sharedConfig.toDiscussionSharedConfigurationJSON()
            } catch {
                return cancel(withReason: .couldNotComputeJSON)
            }
            let itemJSON = PersistedItemJSON(discussionSharedConfiguration: sharedConfigJSON)

            // Create a payload of the PersistedItemJSON we just created and send it.
            // We do not keep track of the message identifiers from engine.
            
            let payload: Data
            do {
                payload = try itemJSON.jsonEncode()
            } catch {
                os_log("Could not encode the shared discussion settings: %{public}@", log: log, type: .fault, error.localizedDescription)
                return cancel(withReason: .failedToEncodeSettings)
            }
            
            // Filter out the contacts/owned devices depending on the sendTo option
            
            let toContactIdentitiesWithCryptoId: Set<ObvCryptoId>
            let alsoPostToOtherOwnedDevices: Bool
            switch sendTo {
            case .allContactsAndOtherOwnedDevices:
                toContactIdentitiesWithCryptoId = contactCryptoIds
                alsoPostToOtherOwnedDevices = ownedIdentityHasAnotherReachableDevice
            case .otherOwnedDevices:
                toContactIdentitiesWithCryptoId = Set()
                alsoPostToOtherOwnedDevices = ownedIdentityHasAnotherReachableDevice
            case .specificContact(contactCryptoId: let contactCryptoId):
                guard contactCryptoIds.contains(contactCryptoId) else { return }
                toContactIdentitiesWithCryptoId = Set([contactCryptoId])
                alsoPostToOtherOwnedDevices = false
            }
            
            if !toContactIdentitiesWithCryptoId.isEmpty || alsoPostToOtherOwnedDevices {
                do {
                    _ = try obvEngine.post(messagePayload: payload,
                                           extendedPayload: nil,
                                           withUserContent: false,
                                           isVoipMessageForStartingCall: false,
                                           attachmentsToSend: [],
                                           toContactIdentitiesWithCryptoId: toContactIdentitiesWithCryptoId,
                                           ofOwnedIdentityWithCryptoId: ownedCryptoId,
                                           alsoPostToOtherOwnedDevices: alsoPostToOtherOwnedDevices)
                } catch {
                    return cancel(withReason: .couldNotPostMessageWithinEngine)
                }
            }
            
        }
        
    }
 
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case coreDataError(error: Error)
        case failedToEncodeSettings
        case couldNotFindContactIdentity
        case couldNotFindContactGroup
        case unexpectedDiscussionType
        case couldNotFindOwnedIdentity
        case couldNotPostMessageWithinEngine
        case couldNotComputeJSON
        
        var logType: OSLogType {
            switch self {
            case .coreDataError,
                 .failedToEncodeSettings,
                 .couldNotFindContactIdentity,
                 .couldNotFindContactGroup,
                 .couldNotFindOwnedIdentity,
                 .couldNotPostMessageWithinEngine,
                 .couldNotComputeJSON:
                return .fault
            case .unexpectedDiscussionType:
                return .error
            }
        }
        
        var errorDescription: String? {
            switch self {
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .failedToEncodeSettings:
                return "We failed to encode the discussion shared settings"
            case .couldNotFindContactIdentity:
                return "Could not find the contact identity of the One2One discussion associated to the shared settings to send"
            case .couldNotFindContactGroup:
                return "Could not find the contact group of the group discussion associated with the shared settings to send"
            case .unexpectedDiscussionType:
                return "We are trying to share the settings of a discussion that is not a One2One nor a group discussion"
            case .couldNotFindOwnedIdentity:
                return "We could not find the owned identity in database"
            case .couldNotPostMessageWithinEngine:
                return "We failed to post the serialized discussion shared settings within the engine"
            case .couldNotComputeJSON:
                return "Could not compute JSON"
            }
        }

    }

}
