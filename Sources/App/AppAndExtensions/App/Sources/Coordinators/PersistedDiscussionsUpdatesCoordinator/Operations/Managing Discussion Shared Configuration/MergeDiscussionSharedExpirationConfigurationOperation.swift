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
import os.log
import ObvEngine
import OlvidUtils
import ObvUICoreData
import ObvTypes
import ObvAppTypes

/// When receiving a shared configuration for a discussion, we merge it with our own current configuration.
final class MergeDiscussionSharedExpirationConfigurationOperation: ContextualOperationWithSpecificReasonForCancel<MergeDiscussionSharedExpirationConfigurationOperation.ReasonForCancel>, @unchecked Sendable {
    
    
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
        case couldNotFindActiveDiscussionInDatabase(discussionIdentifier: ObvDiscussionIdentifier)
        case contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: ObvGroupIdentifier, contactCryptoId: ObvCryptoId)
        case merged
    }

    
    private var ownedCryptoId: ObvCryptoId {
        switch origin {
        case .fromContact(let contactIdentifier):
            return contactIdentifier.ownedCryptoId
        case .fromOtherDeviceOfOwnedIdentity(let ownedCryptoId):
            return ownedCryptoId
        }
    }
    
    
    private(set) var result: Result?


    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        let discussionIdentifier: ObvDiscussionIdentifier
        
        do {
            
            let ownedCryptoId: ObvCryptoId
            
            switch origin {
                
            case .fromContact(contactIdentifier: let contactIdentifier):
                
                ownedCryptoId = contactIdentifier.ownedCryptoId
                
                guard let _discussionIdentifier = discussionSharedConfiguration.getDiscussionIdentifier(ownedCryptoId: ownedCryptoId) else {
                    assertionFailure()
                    return cancel(withReason: .couldNotDetermineDiscussionIdentifier)
                }
                discussionIdentifier = _discussionIdentifier
                
                guard let persistedOwnedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindPersistedOwnedIdentity)
                }

                let (discussionId, weShouldSendBackOurSharedSettings) = try persistedOwnedIdentity.mergeReceivedDiscussionSharedConfigurationSentByContact(
                    discussionSharedConfiguration: discussionSharedConfiguration,
                    messageUploadTimestampFromServer: messageUploadTimestampFromServer, 
                    messageLocalDownloadTimestamp: messageLocalDownloadTimestamp,
                    contactCryptoId: contactIdentifier.contactCryptoId)
                                                      
                if weShouldSendBackOurSharedSettings {
                    requestSendingDiscussionSharedConfiguration(contactIdentifier: contactIdentifier, discussionId: discussionId, within: obvContext)
                }

                return result = .merged

            case .fromOtherDeviceOfOwnedIdentity(ownedCryptoId: let _ownedCryptoId):
                
                ownedCryptoId = _ownedCryptoId
                
                guard let _discussionIdentifier = discussionSharedConfiguration.getDiscussionIdentifier(ownedCryptoId: ownedCryptoId) else {
                    assertionFailure()
                    return cancel(withReason: .couldNotDetermineDiscussionIdentifier)
                }
                discussionIdentifier = _discussionIdentifier

                guard let persistedOwnedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindPersistedOwnedIdentity)
                }
                
                let (discussionId, weShouldSendBackOurSharedSettings) = try persistedOwnedIdentity.mergeReceivedDiscussionSharedConfigurationSentByThisOwnedIdentity(
                    discussionSharedConfiguration: discussionSharedConfiguration, 
                    messageUploadTimestampFromServer: messageUploadTimestampFromServer)
                                
                if weShouldSendBackOurSharedSettings {
                    ObvMessengerInternalNotification.aDiscussionSharedConfigurationIsNeededByAnotherOwnedDevice(
                        ownedCryptoId: ownedCryptoId,
                        discussionId: discussionId)
                    .postOnDispatchQueue()
                }
            
                return result = .merged

            }
            
        } catch {
            
            if let error = error as? ObvUICoreDataError {
                switch error {
                    
                case .couldNotFindDiscussion,
                        .cannotChangeShareConfigurationOfLockedDiscussion,
                        .cannotChangeShareConfigurationOfPreDiscussion:
                    return result = .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)

                case .couldNotFindGroupV1InDatabase:
                    // If a group does not exist, any associated discussion also cannot exist.
                    // Therefore, return a `couldNotFindActiveDiscussionInDatabase` result.
                    // The message will remain on hold until the discussion is created,
                    // which occurs automatically upon group creation.
                    return result = .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)

                case .couldNotFindGroupV2InDatabase(groupIdentifier: let groupIdentifier):
                    // If a group does not exist, any associated discussion also cannot exist.
                    // Therefore, return a `couldNotFindActiveDiscussionInDatabase` result.
                    // The message will remain on hold until the discussion is created,
                    // which occurs automatically upon group creation.
                    let discussionIdentifier = ObvDiscussionIdentifier.groupV2(id: groupIdentifier)
                    result = .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)
                    return

                case .couldNotFindContactWithId(contactIdentifier: let contactIdentifier):
                    // This can happen if the owned identity performed a mutual scan with the contact from another owned device.
                    // In the case the received information concerns:
                    // - a one2one discussion:
                    // If a contact does not exist, any associated discussion also cannot exist.
                    // Therefore, return a `couldNotFindActiveDiscussionInDatabase` result.
                    // The message will remain on hold until the discussion is created,
                    // which occurs automatically upon contact creation.
                    // - a group discussion:
                    // To the contrary of the previous case, the discussion with the contact might never be
                    // created (e.g., when the contact is added to the group by another administrator). So we
                    // return a `contactIsNotPartOfGroupOrRequiresPermissions` result.
                    if let obvGroupIdentifier = discussionIdentifier.obvGroupIdentifier {
                        // Group discussion
                        return result = .contactIsNotPartOfGroupOrRequiresPermissions(
                            groupIdentifier: obvGroupIdentifier,
                            contactCryptoId: contactIdentifier.contactCryptoId)
                    } else {
                        // One2one discussion
                        return result = .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)
                    }
                    
                case .couldNotFindOneToOneContactWithId:
                    // This can happen when receiving a shared config from a contact who just accepted
                    // our invitation to be a oneToOne contact. We should not fail as this case is handled:
                    // we will soon turn her into a oneToOne contact, and thus,
                    // send her back our own shared config for the discussion.
                    // Upon receiving our discussion shared settings, she will
                    // again send us back her shared settings if required.
                    //
                    // If a contact is not one-to-one, any associated discussion is locked, or cannot exist.
                    // Therefore, return a `couldNotFindDiscussionInDatabase` result.
                    // The message will remain on hold until the discussion is created, or if the existing discussion
                    // status is set to active again.
                    return result = .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)
                    
                case .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
                    assert(groupIdentifier == discussionIdentifier.obvGroupIdentifier)
                    return result = .contactIsNotPartOfGroupOrRequiresPermissions(
                        groupIdentifier: groupIdentifier,
                        contactCryptoId: contactCryptoId)
                                        
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
        case couldNotDetermineDiscussionIdentifier

        var logType: OSLogType {
            switch self {
            case .coreDataError,
                 .couldNotFindPersistedOwnedIdentity,
                 .couldNotDetermineDiscussionIdentifier,
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
            case .couldNotDetermineDiscussionIdentifier:
                return "Could not determine discussion identifier"
            }
        }

    }

}
