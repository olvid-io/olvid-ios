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
import OlvidUtils
import UIKit
import ObvUICoreData
import ObvEngine
import ObvTypes
import ObvCrypto


final class UpdateDiscussionLocalConfigurationOperation: ContextualOperationWithSpecificReasonForCancel<UpdateDiscussionLocalConfigurationOperation.ReasonForCancel> {

    private let value: PersistedDiscussionLocalConfigurationValue
    private let input: Input

    private let makeSyncAtomRequest: Bool
    private weak var syncAtomRequestDelegate: ObvSyncAtomRequestDelegate?

    fileprivate static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: UpdateDiscussionLocalConfigurationOperation.self))

    enum Input {
        case configurationObjectID(TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>)
        case discussionPermanentID(ObvManagedObjectPermanentID<PersistedDiscussion>)
        case discussionWithOneToOneContact(contactIdentifier: ObvContactIdentifier)
        case groupV1Discussion(ownedCryptoId: ObvCryptoId, groupIdentifier: GroupV1Identifier)
        case groupV2Discussion(ownedCryptoId: ObvCryptoId, groupIdentifier: GroupV2Identifier)
    }

    init(value: PersistedDiscussionLocalConfigurationValue, input: Input, makeSyncAtomRequest: Bool, syncAtomRequestDelegate: ObvSyncAtomRequestDelegate?) {
        self.value = value
        self.input = input
        self.makeSyncAtomRequest = makeSyncAtomRequest
        self.syncAtomRequestDelegate = syncAtomRequestDelegate
        super.init()
    }

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            let localConfiguration: PersistedDiscussionLocalConfiguration
            switch input {
            case .configurationObjectID(let objectID):
                guard let _localConfiguration = try PersistedDiscussionLocalConfiguration.get(with: objectID, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindDiscussionLocalConfiguration)
                }
                localConfiguration = _localConfiguration
            case .discussionPermanentID(let discussionPermanentID):
                guard let discussion = try? PersistedDiscussion.getManagedObject(withPermanentID: discussionPermanentID, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindDiscussionLocalConfiguration)
                }
                localConfiguration = discussion.localConfiguration
            case .discussionWithOneToOneContact(contactIdentifier: let contactIdentifier):
                guard let contact = try PersistedObvContactIdentity.get(persisted: contactIdentifier, whereOneToOneStatusIs: .oneToOne, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindContactInDatabase)
                }
                guard let oneToOneDiscussion = contact.oneToOneDiscussion else {
                    return cancel(withReason: .couldNotFindDiscussionInDatabase)
                }
                localConfiguration = oneToOneDiscussion.localConfiguration
            case .groupV1Discussion(ownedCryptoId: let ownedCryptoId, groupIdentifier: let groupIdentifier):
                guard let groupV1 = try PersistedContactGroup.getContactGroup(groupIdentifier: groupIdentifier, ownedCryptoId: ownedCryptoId, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindGroupInDatabase)
                }
                localConfiguration = groupV1.discussion.localConfiguration
            case .groupV2Discussion(ownedCryptoId: let ownedCryptoId, groupIdentifier: let groupIdentifier):
                guard let groupV2 = try PersistedGroupV2.get(ownIdentity: ownedCryptoId, appGroupIdentifier: groupIdentifier, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindGroupInDatabase)
                }
                guard let groupV2Discussion = groupV2.discussion else {
                    return cancel(withReason: .couldNotFindDiscussionInDatabase)
                }
                localConfiguration = groupV2Discussion.localConfiguration
            }
            
            let doSendReadReceiptBeforeUpdate = localConfiguration.doSendReadReceipt
            
            localConfiguration.update(with: value)

            let doSendReadReceiptAfterUpdate = localConfiguration.doSendReadReceipt
            let doSendReadReceiptWasUpdated = doSendReadReceiptBeforeUpdate != doSendReadReceiptAfterUpdate

            let value = self.value
            try obvContext.addContextDidSaveCompletionHandler { error in
                guard error == nil else { return }
                if case .muteNotificationsEndDate = value,
                   let expiration = localConfiguration.currentMuteNotificationsEndDate {
                    // This is catched by the MuteDiscussionManager in order to schedule a BG operation allowing to remove the mute
                    ObvMessengerInternalNotification.newMuteExpiration(expirationDate: expiration)
                        .postOnDispatchQueue()
                }
            }
            
            if makeSyncAtomRequest && doSendReadReceiptWasUpdated {
                assert(self.syncAtomRequestDelegate != nil)
                if let syncAtomRequestDelegate = self.syncAtomRequestDelegate {
                    guard let discussion = localConfiguration.discussion else { assertionFailure(); return }
                    guard let ownedCryptoId = discussion.ownedIdentity?.cryptoId else { assertionFailure(); return }
                    let syncAtom: ObvSyncAtom
                    switch try? discussion.kind {
                    case .oneToOne(withContactIdentity: let contact):
                        guard let contact else { assertionFailure(); return }
                        syncAtom = .contactSendReadReceipt(contactCryptoId: contact.cryptoId, doSendReadReceipt: doSendReadReceiptAfterUpdate)
                    case .groupV1(withContactGroup: let groupV1):
                        guard let groupV1 else { assertionFailure(); return }
                        guard let groupId = try? groupV1.getGroupId() else { assertionFailure(); return }
                        syncAtom = .groupV1ReadReceipt(groupOwner: groupId.groupOwner, groupUid: groupId.groupUid, doSendReadReceipt: doSendReadReceiptAfterUpdate)
                    case .groupV2(withGroup: let groupV2):
                        guard let groupV2 else { assertionFailure(); return }
                        syncAtom = .groupV2ReadReceipt(groupIdentifier: groupV2.groupIdentifier, doSendReadReceipt: doSendReadReceiptAfterUpdate)
                    case .none:
                        assertionFailure()
                        return
                    }
                    try? obvContext.addContextDidSaveCompletionHandler { error in
                        guard error == nil else { return }
                        Task.detached {
                            await syncAtomRequestDelegate.requestPropagationToOtherOwnedDevices(of: syncAtom, for: ownedCryptoId)
                        }
                    }
                }
            }
            
        } catch(let error) {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }

    
    enum ReasonForCancel: LocalizedErrorWithLogType {

        case contextIsNil
        case coreDataError(error: Error)
        case couldNotFindDiscussionLocalConfiguration
        case couldNotFindContactInDatabase
        case couldNotFindDiscussionInDatabase
        case couldNotFindGroupInDatabase

        var logType: OSLogType {
            switch self {
            case .coreDataError, .contextIsNil, .couldNotFindContactInDatabase, .couldNotFindDiscussionInDatabase, .couldNotFindGroupInDatabase:
                return .fault
            case .couldNotFindDiscussionLocalConfiguration:
                return .error
            }
        }

        var errorDescription: String? {
            switch self {
            case .contextIsNil: return "Context is nil"
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .couldNotFindDiscussionLocalConfiguration:
                return "Could not find local configuration in database"
            case .couldNotFindContactInDatabase:
                return "Could not find contact in database"
            case .couldNotFindDiscussionInDatabase:
                return "Could not find discussion in database"
            case .couldNotFindGroupInDatabase:
                return "Could not find group in database"
            }
        }


    }

}
