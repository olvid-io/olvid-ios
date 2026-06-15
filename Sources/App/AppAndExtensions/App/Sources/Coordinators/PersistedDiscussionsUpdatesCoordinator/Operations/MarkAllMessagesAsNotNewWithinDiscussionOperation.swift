/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import OSLog
import OlvidUtils
import ObvUICoreData
import ObvTypes
import ObvAppTypes


final class MarkAllMessagesAsNotNewWithinDiscussionOperation: ContextualOperationWithSpecificReasonForCancel<MarkAllMessagesAsNotNewWithinDiscussionOperation.ReasonForCancel>, @unchecked Sendable, OperationProvidingDiscussionReadJSON {
    
    enum Input {
        case persistedDiscussionObjectID(persistedDiscussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>)
        case draftObjectID(_ drafObjectID: TypeSafeManagedObjectID<PersistedDraft>)
        case discussionReadJSON(ownedCryptoId: ObvCryptoId, discussionRead: DiscussionReadJSON)
    }
    
    private let input: Input
    
    init(input: Input) {
        self.input = input
        super.init()
    }

    private(set) var ownedCryptoId: ObvCryptoId?
    private(set) var discussionReadJSONToSend: DiscussionReadJSON?
    private(set) var ownedIdentityHasAnotherReachableDevice = false
    
    enum Result {
        case processed(receivedMessagesForReadReceipts: [TypeSafeManagedObjectID<PersistedMessageReceived>])
        case couldNotFindActiveDiscussionInDatabase(discussionIdentifier: ObvDiscussionIdentifier)
    }

    private(set) var result: Result?

    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            let discussionId: ObvDiscussionIdentifier
            let dateWhenMessageTurnedNotNew: Date
            let serverTimestampWhenDiscussionReadOnAnotherOwnedDevice: Date?
            let requestReceivedFromAnotherOwnedDevice: Bool
            switch input {
            case .persistedDiscussionObjectID(persistedDiscussionObjectID: let persistedDiscussionObjectID):
                guard let _discussionId = try PersistedDiscussion.getObvDiscussionIdentifier(discussionObjectID: persistedDiscussionObjectID, within: obvContext.context) else {
                    assertionFailure()
                    return cancel(withReason: .couldNotDetermineDiscussionIdentifier)
                }
                discussionId = _discussionId
                dateWhenMessageTurnedNotNew = .now
                serverTimestampWhenDiscussionReadOnAnotherOwnedDevice = nil
                requestReceivedFromAnotherOwnedDevice = false
            case .draftObjectID(let draftObjectID):
                guard let draft = try PersistedDraft.get(objectID: draftObjectID, within: obvContext.context) else {
                    assertionFailure()
                    return cancel(withReason: .couldNotFindDraft)
                }
                discussionId = try draft.discussion.discussionIdentifier
                dateWhenMessageTurnedNotNew = .now
                serverTimestampWhenDiscussionReadOnAnotherOwnedDevice = nil
                requestReceivedFromAnotherOwnedDevice = false
            case .discussionReadJSON(ownedCryptoId: let _ownedCryptoId, discussionRead: let discussionRead):
                dateWhenMessageTurnedNotNew = discussionRead.lastReadMessageServerTimestamp
                serverTimestampWhenDiscussionReadOnAnotherOwnedDevice = discussionRead.lastReadMessageServerTimestamp
                discussionId = try discussionRead.getObvDiscussionId(ownedCryptoId: _ownedCryptoId)
                requestReceivedFromAnotherOwnedDevice = true
            }
            
            guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: discussionId.ownedCryptoId, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindOwnedIdentity)
            }
            
            self.ownedCryptoId = discussionId.ownedCryptoId
            self.ownedIdentityHasAnotherReachableDevice = ownedIdentity.hasAnotherDeviceWhichIsReachable
            
            let markAllMessagesAsNotNewResult = try ownedIdentity.markAllMessagesAsNotNew(discussionId: discussionId.toDiscussionIdentifier(),
                                                                                          serverTimestampWhenDiscussionReadOnAnotherOwnedDevice: serverTimestampWhenDiscussionReadOnAnotherOwnedDevice,
                                                                                          dateWhenMessageTurnedNotNew: dateWhenMessageTurnedNotNew)
            
            let lastReadMessageServerTimestamp = markAllMessagesAsNotNewResult?.maxTimestampOfModifiedMessages
            
            do {
                let isDiscussionActive = try ownedIdentity.isDiscussionActive(discussionId: discussionId.toDiscussionIdentifier())
                let shouldSendDiscussionReadJSON = isDiscussionActive && !requestReceivedFromAnotherOwnedDevice
                if let lastReadMessageServerTimestamp, shouldSendDiscussionReadJSON {
                    discussionReadJSONToSend = try ownedIdentity.getDiscussionReadJSON(discussionId: discussionId.toDiscussionIdentifier(), lastReadMessageServerTimestamp: lastReadMessageServerTimestamp)
                }
            } catch {
                assertionFailure(error.localizedDescription) // Continue anyway
            }
            
            return result = .processed(receivedMessagesForReadReceipts: markAllMessagesAsNotNewResult?.receivedMessagesForReadReceipts ?? [])
            
        } catch {
            if let error = error as? ObvUICoreDataError {
                
                // The only case we return a result that allows to keep a message for later is when the
                // request comes from another owned device.
                let discussionIdentifier: ObvDiscussionIdentifier
                switch input {
                case .draftObjectID, .persistedDiscussionObjectID:
                    assertionFailure()
                    return cancel(withReason: .coreDataError(error: error))
                case .discussionReadJSON(ownedCryptoId: let ownedCryptoId, discussionRead: let discussionReadJSON):
                    do {
                        discussionIdentifier = try discussionReadJSON.getObvDiscussionId(ownedCryptoId: ownedCryptoId)
                    } catch {
                        assertionFailure()
                        return cancel(withReason: .coreDataError(error: error))
                    }
                }
                
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
                    assert(discussionIdentifier == ObvDiscussionIdentifier.groupV2(id: groupIdentifier))
                    return result = .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)

                case .couldNotFindOneToOneContactWithId(contactIdentifier: let contactIdentifier):
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
                    let discussionIdentifier = ObvDiscussionIdentifier.oneToOne(id: contactIdentifier)
                    return result = .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)

                default:
                    assertionFailure()
                    return cancel(withReason: .coreDataError(error: error))
                }
            } else {
                assertionFailure()
                return cancel(withReason: .coreDataError(error: error))
            }
        }
        
    }
    
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case coreDataError(error: Error)
        case couldNotFindDiscussion
        case contextIsNil
        case couldNotFindOwnedIdentity
        case couldNotDetermineDiscussionIdentifier
        case couldNotFindDraft

        var logType: OSLogType {
            switch self {
            case .coreDataError,
                    .contextIsNil,
                    .couldNotFindOwnedIdentity,
                    .couldNotDetermineDiscussionIdentifier,
                    .couldNotFindDraft:
                return .fault
            case .couldNotFindDiscussion:
                return .error
            }
        }
        
        var errorDescription: String? {
            switch self {
            case .contextIsNil:
                return "Context is nil"
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .couldNotFindDiscussion:
                return "Could not find discussion in database"
            case .couldNotFindOwnedIdentity:
                return "Could not find owned identity"
            case .couldNotFindDraft:
                return "Could not find draft"
            case .couldNotDetermineDiscussionIdentifier:
                return "Could not determine discussion identifier"
            }
        }

    }

}
