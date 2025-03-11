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
import OlvidUtils
import ObvEngine
import ObvTypes
import ObvUICoreData
import CoreData


/// When the `ScreenCaptureDetector` detects that messages with limited visibility were screenshoted or captured (e.g. with a video capture of the screen), this operation gets called.
/// It first sends a message to all contacts of the discussion to warn them about this capture and inserts a local system message in this discussion to warn the user of what just happened.
final class ProcessDetectionThatSensitiveMessagesWereCapturedByOwnedIdentityOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
     
    let discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>
    let obvEngine: ObvEngine
    
    init(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, obvEngine: ObvEngine) {
        self.discussionPermanentID = discussionPermanentID
        self.obvEngine = obvEngine
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            // Find the discussion and owned identity
            
            guard let discussion = try PersistedDiscussion.getManagedObject(withPermanentID: discussionPermanentID, within: obvContext.context) else {
                // The discussion could not be found, nothing left to do
                assertionFailure()
                return
            }
            
            guard let ownedIdentity = discussion.ownedIdentity else {
                assertionFailure()
                return
            }
            
            // Process the event locally, which returns the JSON to send to contacts and other owned devices
            
            let (screenCaptureDetectionJSON, recipients) = try ownedIdentity.processLocalDetectionThatSensitiveMessagesWereCapturedByThisOwnedIdentity(discussionPermanentID: discussionPermanentID)
            
            // Ask the engine to send the JSON to notify contacts and other owned devices
            
            let payload: Data
            do {
                let itemJSON = PersistedItemJSON(screenCaptureDetectionJSON: screenCaptureDetectionJSON)
                payload = try itemJSON.jsonEncode()
            }
            
            _ = try obvEngine.post(messagePayload: payload,
                                   extendedPayload: nil,
                                   withUserContent: false,
                                   isVoipMessageForStartingCall: false,
                                   attachmentsToSend: [],
                                   toContactIdentitiesWithCryptoId: recipients,
                                   ofOwnedIdentityWithCryptoId: ownedIdentity.cryptoId,
                                   alsoPostToOtherOwnedDevices: true)
            
        } catch {
            assertionFailure(error.localizedDescription)
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
