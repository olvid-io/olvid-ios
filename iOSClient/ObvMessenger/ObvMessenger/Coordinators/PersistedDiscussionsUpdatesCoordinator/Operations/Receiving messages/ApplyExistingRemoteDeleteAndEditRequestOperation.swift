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
import CoreData
import OlvidUtils
import ObvEngine
import os.log
import ObvUICoreData
import ObvTypes


/// Given its inputs, this operation looks for an existing `RemoteDeleteAndEditRequest`. If one is found, this operation either executes a `WipeMessagesOperation` or an `EditTextBodyOfReceivedMessageOperation`
/// operation, depending on the nature of the request found.
final class ApplyExistingRemoteDeleteAndEditRequestOperation: ContextualOperationWithSpecificReasonForCancel<ApplyingRemoteDeleteAndEditRequestOperationReasonForCancel> {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: ApplyExistingRemoteDeleteAndEditRequestOperation.self))

    private let obvMessage: ObvMessage
    private let messageJSON: MessageJSON
    
    init(obvMessage: ObvMessage, messageJSON: MessageJSON) {
        self.obvMessage = obvMessage
        self.messageJSON = messageJSON
        super.init()
    }
    
    override func main() {
        
        os_log("Executing an ApplyExistingRemoteDeleteAndEditRequestOperation for obvMessage %{public}@", log: log, type: .debug, obvMessage.messageIdentifierFromEngine.debugDescription)
        ObvDisplayableLogs.shared.log("🧨 Starting ApplyExistingRemoteDeleteAndEditRequestOperation")
        defer { ObvDisplayableLogs.shared.log("🧨 Ending ApplyExistingRemoteDeleteAndEditRequestOperation") }

        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

        obvContext.performAndWait {
            
            do {
                
                // Grab the persisted contact and the appropriate discussion
                
                guard let persistedContactIdentity = try PersistedObvContactIdentity.get(persisted: obvMessage.fromContactIdentity, whereOneToOneStatusIs: .any, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindPersistedObvContactIdentityInDatabase)
                }
                
                guard let ownedIdentity = persistedContactIdentity.ownedIdentity else {
                    return cancel(withReason: .couldNotDetermineOwnedIdentity)
                }
                
                let discussion: PersistedDiscussion
                switch messageJSON.groupIdentifier {
                case .none:
                    guard let oneToOneDiscussion = persistedContactIdentity.oneToOneDiscussion else {
                        return cancel(withReason: .couldNotFindDiscussion)
                    }
                    discussion = oneToOneDiscussion
                case .groupV1(groupV1Identifier: let groupV1Identifier):
                    guard let contactGroup = try PersistedContactGroup.getContactGroup(groupId: groupV1Identifier, ownedIdentity: ownedIdentity) else {
                        return cancel(withReason: .couldNotFindPersistedContactGroupInDatabase)
                    }
                    discussion = contactGroup.discussion
                case .groupV2(groupV2Identifier: let groupV2Identifier):
                    guard let group = try PersistedGroupV2.get(ownIdentity: ownedIdentity, appGroupIdentifier: groupV2Identifier) else {
                        return cancel(withReason: .couldNotFindPersistedContactGroupInDatabase)
                    }
                    guard let groupDiscussion = group.discussion else {
                        return cancel(withReason: .couldNotFindDiscussion)
                    }
                    discussion = groupDiscussion
                }
                
                // Look for an existing RemoteDeleteAndEditRequest for the received message in that discussion
                
                let remoteRequest = try RemoteDeleteAndEditRequest.getRemoteDeleteAndEditRequest(
                    discussion: discussion,
                    senderIdentifier: obvMessage.fromContactIdentity.cryptoId.getIdentity(),
                    senderThreadIdentifier: messageJSON.senderThreadIdentifier,
                    senderSequenceNumber: messageJSON.senderSequenceNumber)
                
                switch remoteRequest {
                    
                case .none:
                    // We found no existing remote request, there is nothing left to do
                    return
                    
                case .some(let request):
                    
                    // A remote request was found. Depending on its type, we execute a WipeMessagesOperation or an EditTextBodyOfReceivedMessageOperation.
                    // We do not queue them in order to prevent a deadlock on the obvContext thread, we take advantage of the reentrant feature of performAndWait.
                    
                    switch request.requestType {
                    case .delete:
                        let op = WipeMessagesOperation(messagesToDelete: [request.messageReferenceJSON],
                                                       groupIdentifier: messageJSON.groupIdentifier,
                                                       requester: obvMessage.fromContactIdentity,
                                                       messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer,
                                                       saveRequestIfMessageCannotBeFound: false)
                        op.obvContext = obvContext
                        op.main()
                        guard !op.isCancelled else {
                            guard let reason = op.reasonForCancel else { return cancel(withReason: .unknownReason) }
                            return cancel(withReason: .wipeMessagesOperationCancelled(reason: reason))
                        }
                    case .edit:
                        let op = EditTextBodyOfReceivedMessageOperation(newTextBody: request.body,
                                                                        requester: obvMessage.fromContactIdentity,
                                                                        groupIdentifier: messageJSON.groupIdentifier,
                                                                        receivedMessageToEdit: request.messageReferenceJSON,
                                                                        messageUploadTimestampFromServer: request.serverTimestamp,
                                                                        saveRequestIfMessageCannotBeFound: false,
                                                                        newMentions: messageJSON.userMentions)
                        op.obvContext = obvContext
                        op.main()
                        guard !op.isCancelled else {
                            guard let reason = op.reasonForCancel else { return cancel(withReason: .unknownReason) }
                            return cancel(withReason: .editTextBodyOfReceivedMessageOperation(reason: reason))
                        }
                    }
                    
                    // If we reach this point, the remote request has been processed, we can delete it
                    
                    try request.delete()
                    
                }
                
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
        }
        
    }
    
}


enum ApplyingRemoteDeleteAndEditRequestOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case unknownReason
    case contextIsNil
    case couldNotFindPersistedObvContactIdentityInDatabase
    case couldNotDetermineOwnedIdentity
    case couldNotFindPersistedContactGroupInDatabase
    case coreDataError(error: Error)
    case couldNotFindPersistedMessageReceived
    case wipeMessagesOperationCancelled(reason: WipeMessagesOperationReasonForCancel)
    case editTextBodyOfReceivedMessageOperation(reason: EditTextBodyOfReceivedMessageOperationReasonForCancel)
    case couldNotFindDiscussion

    var logType: OSLogType {
        switch self {
        case .couldNotFindPersistedObvContactIdentityInDatabase,
                .couldNotFindPersistedContactGroupInDatabase,
                .couldNotFindDiscussion:
            return .error
        case .unknownReason,
             .contextIsNil,
             .coreDataError,
             .couldNotDetermineOwnedIdentity,
            .couldNotFindPersistedMessageReceived:
            return .fault
        case .wipeMessagesOperationCancelled(reason: let reason):
            return reason.logType
        case .editTextBodyOfReceivedMessageOperation(reason: let reason):
            return reason.logType
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .unknownReason:
            return "One of the operations cancelled without speciying a reason. This is a bug."
        case .contextIsNil:
            return "The context is not set"
        case .couldNotFindPersistedObvContactIdentityInDatabase:
            return "Could not find contact identity of received message in database"
        case .couldNotFindPersistedContactGroupInDatabase:
            return "Could not find group of received message in database"
        case .couldNotDetermineOwnedIdentity:
            return "Could not determine owned identity"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotFindPersistedMessageReceived:
            return "Could not find message received although it is expected to be created within this context at this point"
        case .wipeMessagesOperationCancelled(reason: let reason):
            return reason.errorDescription
        case .editTextBodyOfReceivedMessageOperation(reason: let reason):
            return reason.errorDescription
        case .couldNotFindDiscussion:
            return "Could not find discussion"
        }
    }
    
}
