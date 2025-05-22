/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvEngine
import ObvUICoreData
import ObvAppTypes


/// This class handles the process of stopping the continuous location sharing of a physical device in a discussion when the discussion is deleted.
/// When a discussion gets deleted, we execute this operation to send `END_SHARING` LocationJSON messages to other participants for all messages used
/// to share the continuous location of the current physical device. This ensures that other participants are aware that the sharing has stopped, as deleting
/// the discussion would delete sent messages where the location was shared and thus associated `PersistedLocationContinuousSent` instances.
final class SendEndSharingLocationJSONWhenDeletingDiscussionOperation: OperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    enum DiscussionIdentifier {
        case objectID(NSManagedObjectID)
        case obvDiscussionIdentifier(ObvDiscussionIdentifier)
    }
    
    private let discussionIdentifier: DiscussionIdentifier
    private let obvEngine: ObvEngine

    init(discussionIdentifier: DiscussionIdentifier, obvEngine: ObvEngine) {
        self.discussionIdentifier = discussionIdentifier
        self.obvEngine = obvEngine
        super.init()
    }

    
    override func main() {
        
        ObvStack.shared.performBackgroundTaskAndWait { context in
         
            do {
                
                let discussion: PersistedDiscussion
                switch self.discussionIdentifier {
                case .objectID(let persistedDiscussionObjectID):
                    guard let _discussion = try PersistedDiscussion.get(objectID: persistedDiscussionObjectID, within: context) else {
                        assertionFailure("The discussion seems to have been deleted before we could send the END_SHARING messages")
                        return
                    }
                    discussion = _discussion
                case .obvDiscussionIdentifier(let discussionIdentifier):
                    guard let _discussion = try PersistedDiscussion.getPersistedDiscussion(discussionIdentifier: discussionIdentifier, within: context) else {
                        assertionFailure("The discussion seems to have been deleted before we could send the END_SHARING messages")
                        return
                    }
                    discussion = _discussion
                }
                
                guard let locationSent = try PersistedLocationContinuousSent.getPersistedLocationContinuousSentFromCurrentPhysicalDevice(within: context) else {
                    // No need to send a END_SHARING messages since we are not sharing the current physical device location.
                    return
                }
                
                let sentMessagesInDiscussion = locationSent.sentMessages.filter { $0.discussion?.objectID == discussion.objectID }
                
                guard !sentMessagesInDiscussion.isEmpty else {
                    // No need to send a PersistedItemJSON this we are not sharing the current device physical location in the discussion
                    // we are about to delete.
                    return
                }
                
                let endSharingLocationJSON = LocationJSON(type: .END_SHARING, timestamp: Date.now, count: nil, quality: nil, sharingExpiration: nil, latitude: 0, longitude: 0, altitude: nil, precision: nil, address: nil)
                let updateMessageJSON = try sentMessagesInDiscussion.map { try UpdateMessageJSON(persistedMessageSentToEdit: $0, newTextBody: nil, userMentions: [], locationJSON: endSharingLocationJSON) }
                let itemJSONs = updateMessageJSON.map { PersistedItemJSON(updateMessageJSON: $0) }
                
                // We have itemJSONs to send

                let (ownCryptoId, contactCryptoIds) = try discussion.getAllActiveParticipants()

                guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownCryptoId, within: context) else {
                    return
                }

                guard !contactCryptoIds.isEmpty || ownedIdentity.devices.count > 1 else { return }

                // Send the messages
                
                for itemJSON in itemJSONs {
                    
                    let payload: Data
                    do {
                        payload = try itemJSON.jsonEncode()
                    } catch {
                        continue
                    }

                    do {
                        _ = try obvEngine.post(messagePayload: payload,
                                               extendedPayload: nil,
                                               withUserContent: true,
                                               isVoipMessageForStartingCall: false,
                                               attachmentsToSend: [],
                                               toContactIdentitiesWithCryptoId: contactCryptoIds,
                                               ofOwnedIdentityWithCryptoId: ownCryptoId,
                                               alsoPostToOtherOwnedDevices: true)
                    } catch {
                        continue
                    }

                }

            } catch {
                assertionFailure(error.localizedDescription)
                return cancel(withReason: .coreDataError(error: error))
            }

            
        }
        
    }
    
}
