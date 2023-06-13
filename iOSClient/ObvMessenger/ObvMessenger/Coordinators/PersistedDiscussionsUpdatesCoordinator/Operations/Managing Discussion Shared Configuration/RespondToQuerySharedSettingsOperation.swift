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
import ObvUICoreData


/// The operation processes received QuerySharedSettingsJSON requests for group v2 discussions.
///
/// If we consider that our discussion details are more recent than those of the contact who made the request, we send an ``anOldDiscussionSharedConfigurationWasReceived`` notification.
/// This notification will be catched by the coordinator who will eventually send our shared details to the contact who made the request (provided that we have the right to change the group discussion details).
final class RespondToQuerySharedSettingsOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    let fromContactIdentity: ObvContactIdentity
    let querySharedSettingsJSON: QuerySharedSettingsJSON
    
    init(fromContactIdentity: ObvContactIdentity, querySharedSettingsJSON: QuerySharedSettingsJSON) {
        self.fromContactIdentity = fromContactIdentity
        self.querySharedSettingsJSON = querySharedSettingsJSON
        super.init()
    }

    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        obvContext.performAndWait {

            do {
                
                let ownIdentity = fromContactIdentity.ownedIdentity.cryptoId
                let groupV2Identifier = querySharedSettingsJSON.groupV2Identifier
                let sharedSettingsVersionKnownByContact = querySharedSettingsJSON.knownSharedSettingsVersion ?? Int.min
                let sharedExpirationKnownByContact = querySharedSettingsJSON.knownSharedExpiration

                // Try to get the group
                
                guard let group = try PersistedGroupV2.get(ownIdentity: ownIdentity, appGroupIdentifier: groupV2Identifier, within: obvContext.context) else {
                    // We could not get the group, there is not much we can do
                    return
                }
                
                guard let discussion = group.discussion else {
                    // We could not get the discussion, there is not much we can do
                    return
                }
                
                let sharedConfiguration = discussion.sharedConfiguration
                
                // Get the values known locally
                
                let sharedSettingsVersionKnownLocally = sharedConfiguration.version
                let sharedExpirationKnownLocally: ExpirationJSON?
                if sharedSettingsVersionKnownLocally >= 0 {
                    sharedExpirationKnownLocally = sharedConfiguration.toExpirationJSON()
                } else {
                    sharedExpirationKnownLocally = nil
                }
                
                // If the locally known values are identical to the values known to the contact, we are done, we do not need to answer the query
                
                guard sharedSettingsVersionKnownByContact <= sharedSettingsVersionKnownLocally || sharedExpirationKnownByContact != sharedExpirationKnownLocally else {
                    return
                }
                
                // If we reach this point, something differed between the shared settings of our contact and ours

                var weShouldSentBackTheSharedSettings = false
                if sharedSettingsVersionKnownLocally > sharedSettingsVersionKnownByContact {
                    weShouldSentBackTheSharedSettings = true
                } else if sharedSettingsVersionKnownLocally == sharedSettingsVersionKnownByContact && sharedExpirationKnownByContact != sharedExpirationKnownLocally {
                    weShouldSentBackTheSharedSettings = true
                }
                
                guard weShouldSentBackTheSharedSettings else {
                    return
                }
                
                // If we reach this point, we must send our shared settings back
                
                discussion.sendNotificationIndicatingThatAnOldDiscussionSharedConfigurationWasReceived()
                
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }

        }

    }

}
