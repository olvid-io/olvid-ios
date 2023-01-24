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
import OlvidUtils
import ObvEngine
import ObvTypes


/// When the `ScreenCaptureDetector` detects that messages with limited visibility were screenshoted or captured (e.g. with a video capture of the screen), this operation gets called.
/// It first sends a message to all contacts of the discussion to warn them about this capture and inserts a local system message in this discussion to warn the user of what just happened.
final class ProcessDetectionThatSensitiveMessagesWereCapturedByOwnedIdentityOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
     
    let discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>
    let obvEngine: ObvEngine
    
    init(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, obvEngine: ObvEngine) {
        self.discussionObjectID = discussionObjectID
        self.obvEngine = obvEngine
        super.init()
    }
    
    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        obvContext.performAndWait {
            
            do {
                
                // Find the discussion and owned identity
                
                guard let discussion = try PersistedDiscussion.get(objectID: discussionObjectID.objectID, within: obvContext.context) else {
                    // The discussion could not be found, nothing left to do
                    assertionFailure()
                    return
                }
                                
                guard let ownCryptoId = discussion.ownedIdentity?.cryptoId else {
                    assertionFailure()
                    return
                }
                
                // Make sure the discussion is active
                
                switch discussion.status {
                case .active:
                    break
                case .locked, .preDiscussion:
                    return
                }
                
                // Determine if the ScreenCaptureDetectionJSON concerns a one2one or a group discussion. Determine the recipients of this JSON message.
                
                let recipients: Set<ObvCryptoId>
                let screenCaptureDetectionJSON: ScreenCaptureDetectionJSON
                
                switch try discussion.kind {
                case .oneToOne(withContactIdentity: let contact):
                    guard let contact else { assertionFailure(); return }
                    screenCaptureDetectionJSON = ScreenCaptureDetectionJSON()
                    recipients = Set([contact.cryptoId])
                case .groupV1(withContactGroup: let group):
                    guard let group else { assertionFailure(); return }
                    let groupV1Identifier = try group.getGroupId()
                    screenCaptureDetectionJSON = ScreenCaptureDetectionJSON(groupV1Identifier: groupV1Identifier)
                    recipients = Set(group.contactIdentities.compactMap({ $0.cryptoId }))
                case .groupV2(withGroup: let group):
                    guard let group else { assertionFailure(); return }
                    let groupV2Identifier = group.groupIdentifier
                    screenCaptureDetectionJSON = ScreenCaptureDetectionJSON(groupV2Identifier: groupV2Identifier)
                    recipients = Set(group.contactsAmongOtherPendingAndNonPendingMembers.map({ $0.cryptoId }))
                }
                
                // Compute the payload to send
                
                let payload: Data
                do {
                    let itemJSON = PersistedItemJSON(screenCaptureDetectionJSON: screenCaptureDetectionJSON)
                    payload = try itemJSON.jsonEncode()
                }
                
                // Send the JSON message
                
                _ = try obvEngine.post(messagePayload: payload,
                                       extendedPayload: nil,
                                       withUserContent: false,
                                       isVoipMessageForStartingCall: false,
                                       attachmentsToSend: [],
                                       toContactIdentitiesWithCryptoId: recipients,
                                       ofOwnedIdentityWithCryptoId: ownCryptoId)
                
                // Insert an appropriate system message within the discussion
                
                _ = try PersistedMessageSystem.insertOwnedIdentityDidCaptureSensitiveMessages(within: discussion)
                
            } catch {
                assertionFailure(error.localizedDescription)
                return cancel(withReason: .coreDataError(error: error))
            }
            
        }
        
    }
    
}
