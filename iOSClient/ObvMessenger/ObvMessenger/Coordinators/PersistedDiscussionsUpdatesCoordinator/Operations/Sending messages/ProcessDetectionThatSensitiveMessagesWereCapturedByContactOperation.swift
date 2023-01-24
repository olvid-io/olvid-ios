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


/// This operation allows to process a received message indicating that one of our contacts did take a screen capture of some sensitive (read-once of with limited visibility) messages within a discussion. If this happen, we want to show this to the owned identity by displaying an appropriate system message within the corresponding discussion.
final class ProcessDetectionThatSensitiveMessagesWereCapturedByContactOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    let contactIdentity: ObvContactIdentity
    let screenCaptureDetectionJSON: ScreenCaptureDetectionJSON
    
    init(contactIdentity: ObvContactIdentity, screenCaptureDetectionJSON: ScreenCaptureDetectionJSON) {
        self.contactIdentity = contactIdentity
        self.screenCaptureDetectionJSON = screenCaptureDetectionJSON
        super.init()
    }
    
    override func main() {
        
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        obvContext.performAndWait {
            
            do {
                
                // Get the contact and the owned identities
                
                guard let persistedContactIdentity = try PersistedObvContactIdentity.get(persisted: contactIdentity, whereOneToOneStatusIs: .any, within: obvContext.context) else {
                    // We could not find the contact, we cannot do much
                    return
                }
                
                guard let ownedIdentity = persistedContactIdentity.ownedIdentity else {
                    assertionFailure()
                    return
                }
                
                // Recover the appropriate discussion
                
                let groupIdentifier = screenCaptureDetectionJSON.groupIdentifier
                
                let discussion: PersistedDiscussion
                switch groupIdentifier {
                case .none:
                    guard let oneToOneDiscussion = persistedContactIdentity.oneToOneDiscussion else {
                        assertionFailure()
                        return
                    }
                    discussion = oneToOneDiscussion
                case .groupV1(groupV1Identifier: let groupV1Identifier):
                    guard let group = try PersistedContactGroup.getContactGroup(groupId: groupV1Identifier, ownedIdentity: ownedIdentity) else {
                        assertionFailure()
                        return
                    }
                    discussion = group.discussion
                case .groupV2(groupV2Identifier: let groupV2Identifier):
                    guard let group = try PersistedGroupV2.get(ownIdentity: ownedIdentity, appGroupIdentifier: groupV2Identifier) else {
                        assertionFailure()
                        return
                    }
                    guard let groupDiscussion = group.discussion else {
                        assertionFailure()
                        return
                    }
                    discussion = groupDiscussion
                }
                
                // Make sure the discussion is active
                
                switch discussion.status {
                case .active:
                    break
                case .locked, .preDiscussion:
                    return
                }

                // Insert the appropriate system message in the discussion
                
                _ = try PersistedMessageSystem.insertContactIdentityDidCaptureSensitiveMessages(within: discussion, contact: persistedContactIdentity)
                
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
        }
        
        
    }
    
}
