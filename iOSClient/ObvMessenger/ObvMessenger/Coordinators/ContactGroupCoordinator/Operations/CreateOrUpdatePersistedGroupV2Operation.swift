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
import OlvidUtils
import ObvTypes
import ObvEngine
import ObvUICoreData
import CoreData


final class CreateOrUpdatePersistedGroupV2Operation: ContextualOperationWithSpecificReasonForCancel<CreateOrUpdatePersistedGroupV2Operation.ReasonForCancel> {
    
    private let obvGroupV2: ObvGroupV2
    private let initiator: ObvGroupV2.CreationOrUpdateInitiator
    private let obvEngine: ObvEngine
    
    init(obvGroupV2: ObvGroupV2, initiator: ObvGroupV2.CreationOrUpdateInitiator, obvEngine: ObvEngine) {
        self.obvGroupV2 = obvGroupV2
        self.initiator = initiator
        self.obvEngine = obvEngine
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: obvGroupV2.ownIdentity, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindPersistedOwnedIdentity)
            }
            
            let group = try ownedIdentity.createOrUpdateGroupV2(obvGroupV2: obvGroupV2, createdByMe: initiator == .createdByMe)
            
            /* If we the group was updated by someone else and if the list of users that can change the discussion shared setttings was changed (compared to the one we knew about),
             * we might be in a situation where one of the new members allowed to change these shared settings did change the settings while we were not aware of her rights to do so.
             * In that case, we have thrown away her change request.
             * To make sure we have the latest shared settings, we thus query for these settings in case the list of users that can change the discussion shared setttings was changed.
             */
            
            if initiator == .createdOrUpdatedBySomeoneElse && group.otherMembers.contains(where: { $0.permissionChangeSettingsIsUpdated }) {
                
                do {
                    
                    // Create the payload of the QuerySharedSettingsJSON
                    
                    let payload: Data
                    do {
                        let knownSharedSettingsVersion: Int?
                        if let version = group.discussion?.sharedConfiguration.version {
                            knownSharedSettingsVersion = (version == 0) ? nil : version
                        } else {
                            knownSharedSettingsVersion = nil
                        }
                        let knownSharedExpiration: ExpirationJSON?
                        if knownSharedSettingsVersion != nil {
                            knownSharedExpiration = group.discussion?.sharedConfiguration.toExpirationJSON()
                        } else {
                            knownSharedExpiration = nil
                        }
                        let querySharedSettingsJSON = QuerySharedSettingsJSON(groupV2Identifier: group.groupIdentifier,
                                                                              knownSharedSettingsVersion: knownSharedSettingsVersion,
                                                                              knownSharedExpiration: knownSharedExpiration)
                        let itemJSON = PersistedItemJSON(querySharedSettingsJSON: querySharedSettingsJSON)
                        payload = try itemJSON.jsonEncode()
                    }
                    
                    // We want to send the QuerySharedSettingsJSON to all the group members that are allowed to change settings
                    
                    let cryptoIdsOfContactsAmongNonPendingOtherMembers = Set(group.contactsAmongNonPendingOtherMembers.map({ $0.cryptoId }))
                    let cryptoIdsOfMembersAllowedToChangeSettings = Set(group.otherMembers.filter({ $0.isAllowedToChangeSettings })).compactMap({ $0.cryptoId })
                    let toContactIdentitiesWithCryptoId = cryptoIdsOfContactsAmongNonPendingOtherMembers.intersection(cryptoIdsOfMembersAllowedToChangeSettings)
                    
                    if !toContactIdentitiesWithCryptoId.isEmpty {
                        _ = try obvEngine.post(messagePayload: payload,
                                               extendedPayload: nil,
                                               withUserContent: false,
                                               isVoipMessageForStartingCall: false,
                                               attachmentsToSend: [],
                                               toContactIdentitiesWithCryptoId: toContactIdentitiesWithCryptoId,
                                               ofOwnedIdentityWithCryptoId: obvGroupV2.ownIdentity,
                                               alsoPostToOtherOwnedDevices: true)
                    }
                    
                } catch {
                    assertionFailure(error.localizedDescription)
                    // In production, continue anyway since we should not fail because we could not create or send the QuerySharedSettingsJSON
                }
                
                
            } // End of if initiator == .createdOrUpdatedBySomeoneElse...
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
    
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case coreDataError(error: Error)
        case couldNotFindPersistedOwnedIdentity

        var logType: OSLogType {
            switch self {
            case .coreDataError,
                    .couldNotFindPersistedOwnedIdentity:
                return .fault
            }
        }
        
        var errorDescription: String? {
            switch self {
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .couldNotFindPersistedOwnedIdentity:
                return "Could not find persisted owned identity"
            }
        }

    }

    
}
