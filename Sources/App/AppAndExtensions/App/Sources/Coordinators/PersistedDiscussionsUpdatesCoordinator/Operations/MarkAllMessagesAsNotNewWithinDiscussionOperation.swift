/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import OlvidUtils
import ObvUICoreData
import ObvTypes


final class MarkAllMessagesAsNotNewWithinDiscussionOperation: ContextualOperationWithSpecificReasonForCancel<MarkAllMessagesAsNotNewWithinDiscussionOperation.ReasonForCancel>, @unchecked Sendable, OperationProvidingDiscussionReadJSON {
    
    enum Input {
        case persistedDiscussionObjectID(persistedDiscussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>)
        case draftPermanentID(draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>)
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
        case couldNotFindGroupV2InDatabase(groupIdentifier: GroupV2Identifier)
        case couldNotFindOneToOneContactInDatabase(contactCryptoId: ObvCryptoId)
        case processed(receivedMessagesForReadReceipts: [TypeSafeManagedObjectID<PersistedMessageReceived>])
    }

    private(set) var result: Result?

    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            let ownedCryptoId: ObvCryptoId
            let discussionId: DiscussionIdentifier
            let dateWhenMessageTurnedNotNew: Date
            let serverTimestampWhenDiscussionReadOnAnotherOwnedDevice: Date?
            let requestReceivedFromAnotherOwnedDevice: Bool
            switch input {
            case .persistedDiscussionObjectID(persistedDiscussionObjectID: let persistedDiscussionObjectID):
                (ownedCryptoId, discussionId) = try PersistedObvOwnedIdentity.getDiscussionIdentifiers(from: persistedDiscussionObjectID, within: obvContext.context)
                dateWhenMessageTurnedNotNew = .now
                serverTimestampWhenDiscussionReadOnAnotherOwnedDevice = nil
                requestReceivedFromAnotherOwnedDevice = false
            case .draftPermanentID(draftPermanentID: let draftPermanentID):
                (ownedCryptoId, discussionId) = try PersistedObvOwnedIdentity.getDiscussionIdentifiers(from: draftPermanentID, within: obvContext.context)
                dateWhenMessageTurnedNotNew = .now
                serverTimestampWhenDiscussionReadOnAnotherOwnedDevice = nil
                requestReceivedFromAnotherOwnedDevice = false
            case .discussionReadJSON(ownedCryptoId: let _ownedCryptoId, discussionRead: let discussionRead):
                ownedCryptoId = _ownedCryptoId
                dateWhenMessageTurnedNotNew = discussionRead.lastReadMessageServerTimestamp
                serverTimestampWhenDiscussionReadOnAnotherOwnedDevice = discussionRead.lastReadMessageServerTimestamp
                discussionId = try discussionRead.getDiscussionId(ownedCryptoId: ownedCryptoId)
                requestReceivedFromAnotherOwnedDevice = true
            }
            
            guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindOwnedIdentity)
            }
            
            self.ownedCryptoId = ownedIdentity.cryptoId
            self.ownedIdentityHasAnotherReachableDevice = ownedIdentity.hasAnotherDeviceWhichIsReachable
            
            let markAllMessagesAsNotNewResult = try ownedIdentity.markAllMessagesAsNotNew(discussionId: discussionId,
                                                                                          serverTimestampWhenDiscussionReadOnAnotherOwnedDevice: serverTimestampWhenDiscussionReadOnAnotherOwnedDevice,
                                                                                          dateWhenMessageTurnedNotNew: dateWhenMessageTurnedNotNew)
            
            let lastReadMessageServerTimestamp = markAllMessagesAsNotNewResult?.maxTimestampOfModifiedMessages
            
            do {
                let isDiscussionActive = try ownedIdentity.isDiscussionActive(discussionId: discussionId)
                let shouldSendDiscussionReadJSON = isDiscussionActive && !requestReceivedFromAnotherOwnedDevice
                if let lastReadMessageServerTimestamp, shouldSendDiscussionReadJSON {
                    discussionReadJSONToSend = try ownedIdentity.getDiscussionReadJSON(discussionId: discussionId, lastReadMessageServerTimestamp: lastReadMessageServerTimestamp)
                }
            } catch {
                assertionFailure(error.localizedDescription) // Continue anyway
            }
            
            result = .processed(receivedMessagesForReadReceipts: markAllMessagesAsNotNewResult?.receivedMessagesForReadReceipts ?? [])
            
        } catch {
            if let error = error as? ObvUICoreDataError {
                switch error {
                case .couldNotFindGroupV2InDatabase(groupIdentifier: let groupIdentifier):
                    result = .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
                    return
                case .couldNotFindDiscussionWithId(discussionId: let discussionId):
                    switch discussionId {
                    case .groupV2(let id):
                        switch id {
                        case .groupV2Identifier(let groupIdentifier):
                            result = .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
                            return
                        case .objectID:
                            assertionFailure()
                            return cancel(withReason: .coreDataError(error: error))
                        }
                    case .oneToOne(id: let discussionId):
                        switch discussionId {
                        case .objectID:
                            assertionFailure()
                            return cancel(withReason: .coreDataError(error: error))
                        case .contactCryptoId(let contactCryptoId):
                            result = .couldNotFindOneToOneContactInDatabase(contactCryptoId: contactCryptoId)
                            return
                        }
                    case .groupV1:
                        assertionFailure()
                        return cancel(withReason: .coreDataError(error: error))
                    }
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

        var logType: OSLogType {
            switch self {
            case .coreDataError,
                    .contextIsNil,
                    .couldNotFindOwnedIdentity:
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
            }
        }

    }

}
