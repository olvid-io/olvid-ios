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
import ObvUICoreData
import ObvTypes

/// When receiving a shared configuration for a discussion, we merge it with our own current configuration.
final class MergeDiscussionSharedExpirationConfigurationOperation: ContextualOperationWithSpecificReasonForCancel<MergeDiscussionSharedExpirationConfigurationOperation.ReasonForCancel> {
    
    
    private let discussionSharedConfiguration: DiscussionSharedConfigurationJSON
    private let origin: Origin
    private let messageUploadTimestampFromServer: Date
    private let messageLocalDownloadTimestamp: Date
    
    
    enum Origin {
        case fromContact(contactIdentifier: ObvContactIdentifier)
        case fromOtherDeviceOfOwnedIdentity(ownedCryptoId: ObvCryptoId)
    }


    init(discussionSharedConfiguration: DiscussionSharedConfigurationJSON, origin: Origin, messageUploadTimestampFromServer: Date, messageLocalDownloadTimestamp: Date) {
        self.discussionSharedConfiguration = discussionSharedConfiguration
        self.origin = origin
        self.messageUploadTimestampFromServer = messageUploadTimestampFromServer
        self.messageLocalDownloadTimestamp = messageLocalDownloadTimestamp
        super.init()
    }
    
    
    enum Result {
        case couldNotFindGroupV2InDatabase(groupIdentifier: GroupV2Identifier)
        case couldNotFindContactInDatabase(contactCryptoId: ObvCryptoId)
        case contactIsNotOneToOne
        case merged
    }

    
    private(set) var result: Result?


    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            switch origin {
                
            case .fromContact(contactIdentifier: let contactIdentifier):
                
                guard let persistedOwnedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: contactIdentifier.ownedCryptoId, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindPersistedOwnedIdentity)
                }

                let (discussionId, weShouldSendBackOurSharedSettings) = try persistedOwnedIdentity.mergeReceivedDiscussionSharedConfigurationSentByContact(
                    discussionSharedConfiguration: discussionSharedConfiguration,
                    messageUploadTimestampFromServer: messageUploadTimestampFromServer, 
                    messageLocalDownloadTimestamp: messageLocalDownloadTimestamp,
                    contactCryptoId: contactIdentifier.contactCryptoId)
                
                result = .merged
                                      
                if weShouldSendBackOurSharedSettings {
                    requestSendingDiscussionSharedConfiguration(contactIdentifier: contactIdentifier, discussionId: discussionId, within: obvContext)
                }

                
            case .fromOtherDeviceOfOwnedIdentity(ownedCryptoId: let ownedCryptoId):
                
                guard let persistedOwnedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindPersistedOwnedIdentity)
                }
                
                let (discussionId, weShouldSendBackOurSharedSettings) = try persistedOwnedIdentity.mergeReceivedDiscussionSharedConfigurationSentByThisOwnedIdentity(
                    discussionSharedConfiguration: discussionSharedConfiguration, 
                    messageUploadTimestampFromServer: messageUploadTimestampFromServer)
                                
                result = .merged

                if weShouldSendBackOurSharedSettings {
                    ObvMessengerInternalNotification.aDiscussionSharedConfigurationIsNeededByAnotherOwnedDevice(
                        ownedCryptoId: ownedCryptoId,
                        discussionId: discussionId)
                    .postOnDispatchQueue()
                }
                
            }
            
        } catch {
            
            if let error = error as? ObvUICoreDataError {
                switch error {
                case .couldNotFindGroupV2InDatabase(groupIdentifier: let groupIdentifier):
                    result = .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
                    return
                case .couldNotFindContactWithId(contactIdentifier: let contactIdentifier):
                    // This can happen if the owned identity performed a mutual scan with the contact from another owned device
                    result = .couldNotFindContactInDatabase(contactCryptoId: contactIdentifier.contactCryptoId)
                    return
                case .contactIsNotOneToOne:
                    // This can happen when receiving a shared config from a contact who just accepted our invitation to be a oneToOne contact. We should not fail as this case is handled:
                    // we will soon turn her into a oneToOne contact, and thus, send her back our own shared config for the discussion. Upon receiving our discussion shared settings, she will
                    // again send us back her shared settings if required.
                    result = .contactIsNotOneToOne
                    return
                default:
                    return cancel(withReason: .coreDataError(error: error))
                }
            } else {
                return cancel(withReason: .coreDataError(error: error))
            }
        }
        
    }
    

    // We had to create a contact, meaning we had to create/unlock a one2one discussion. In that case, we want to (re)send the discussion shared settings to our contact.
    // This allows to make sure those settings are in sync.
    private func requestSendingDiscussionSharedConfiguration(contactIdentifier: ObvContactIdentifier, discussionId: DiscussionIdentifier, within obvContext: ObvContext) {
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

    
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case coreDataError(error: Error)
        case couldNotFindPersistedOwnedIdentity
        case contextIsNil

        var logType: OSLogType {
            switch self {
            case .coreDataError,
                 .couldNotFindPersistedOwnedIdentity,
                 .contextIsNil:
                return .fault
            }
        }
        
        var errorDescription: String? {
            switch self {
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .couldNotFindPersistedOwnedIdentity:
                return "Could not find persisted owned identity"
            case .contextIsNil:
                return "Context is nil"
            }
        }

    }

}
