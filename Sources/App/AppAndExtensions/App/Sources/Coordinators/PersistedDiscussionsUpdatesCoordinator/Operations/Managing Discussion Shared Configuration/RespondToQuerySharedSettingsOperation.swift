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
import ObvUICoreData
import os.log
import ObvTypes
import CoreData


/// The operation processes received QuerySharedSettingsJSON requests by a contact or another device of the owned identity.
///
/// If we consider that our discussion details are more recent than those of the contact who made the request, we send an ``aDiscussionSharedConfigurationIsNeededByContact``
/// or an ``aDiscussionSharedConfigurationIsNeededByAnotherOwnedDevice`` notification. This notification will be catched by the coordinator who will
/// eventually send our shared details to the contact who made the request.
///
final class RespondToQuerySharedSettingsOperation: ContextualOperationWithSpecificReasonForCancel<RespondToQuerySharedSettingsOperation.ReasonForCancel>, @unchecked Sendable {
    
    enum Requester {
        case contact(contactIdentifier: ObvContactIdentifier)
        case ownedIdentity(ownedCryptoId: ObvCryptoId)
    }

    private let querySharedSettingsJSON: QuerySharedSettingsJSON
    private let requester: Requester
    
    init(querySharedSettingsJSON: QuerySharedSettingsJSON, requester: Requester) {
        self.querySharedSettingsJSON = querySharedSettingsJSON
        self.requester = requester
        super.init()
    }

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            let weShouldSendBackOurSharedSettings: Bool
            let discussionId: DiscussionIdentifier
            
            switch requester {
                
            case .contact(contactIdentifier: let contactIdentifier):
                
                guard let contact = try PersistedObvContactIdentity.get(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindContact)
                }
                
                (weShouldSendBackOurSharedSettings, discussionId) = try contact.processQuerySharedSettingsRequestFromThisContact(querySharedSettingsJSON: querySharedSettingsJSON)
                
            case .ownedIdentity(ownedCryptoId: let ownedCryptoId):
                
                guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindOwnedIdentity)
                }
                
                (weShouldSendBackOurSharedSettings, discussionId) = try ownedIdentity.processQuerySharedSettingsRequestFromThisOwnedIdentity(querySharedSettingsJSON: querySharedSettingsJSON)
                
            }
            
            if weShouldSendBackOurSharedSettings {
                switch requester {
                case .contact(contactIdentifier: let contactIdentifier):
                    requestSendingDiscussionSharedConfigurationToContact(contactIdentifier: contactIdentifier, discussionId: discussionId, within: obvContext)
                case .ownedIdentity(ownedCryptoId: let ownedCryptoId):
                    requestSendingDiscussionSharedConfigurationToAnotherOwnedDevice(ownedCryptoId: ownedCryptoId, discussionId: discussionId, within: obvContext)
                }
            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }

    
    private func requestSendingDiscussionSharedConfigurationToContact(contactIdentifier: ObvContactIdentifier, discussionId: DiscussionIdentifier, within obvContext: ObvContext) {
        do {
            try obvContext.addContextDidSaveCompletionHandler { error in
                guard error == nil else { return }
                ObvMessengerInternalNotification.aDiscussionSharedConfigurationIsNeededByContact(
                    contactIdentifier: contactIdentifier,
                    discussionId: discussionId)
                .postOnDispatchQueue()
            }
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }

    
    private func requestSendingDiscussionSharedConfigurationToAnotherOwnedDevice(ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, within obvContext: ObvContext) {
        do {
            try obvContext.addContextDidSaveCompletionHandler { error in
                guard error == nil else { return }
                ObvMessengerInternalNotification.aDiscussionSharedConfigurationIsNeededByAnotherOwnedDevice(
                    ownedCryptoId: ownedCryptoId,
                    discussionId: discussionId)
                .postOnDispatchQueue()
            }
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }

    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case coreDataError(error: Error)
        case couldNotFindOwnedIdentity
        case couldNotFindContact

        var logType: OSLogType {
            return .fault
        }

        var errorDescription: String? {
            switch self {
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .couldNotFindOwnedIdentity:
                return "Could not find owned identity"
            case .couldNotFindContact:
                return "Could not find the contact identity"
            }
        }

    }

    
    
}
