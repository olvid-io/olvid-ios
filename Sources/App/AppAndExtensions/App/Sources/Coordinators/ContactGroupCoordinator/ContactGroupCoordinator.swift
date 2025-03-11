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
import os.log
import CoreData
import ObvEngine
import ObvCoreDataStack
import ObvTypes
import ObvUICoreData
import ObvCrypto
import OlvidUtils
import ObvAppCoreConstants



final class ContactGroupCoordinator: OlvidCoordinator, ObvErrorMaker {
    
    let obvEngine: ObvEngine
    static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: ContactGroupCoordinator.self))
    private var observationTokens = [NSObjectProtocol]()
    static let errorDomain = "ContactGroupCoordinator"
    let coordinatorsQueue: OperationQueue
    let queueForComposedOperations: OperationQueue
    let queueForSyncHintsComputationOperation: OperationQueue
    weak var syncAtomRequestDelegate: ObvSyncAtomRequestDelegate?

    init(obvEngine: ObvEngine, coordinatorsQueue: OperationQueue, queueForComposedOperations: OperationQueue, queueForSyncHintsComputationOperation: OperationQueue) {
        self.obvEngine = obvEngine
        self.coordinatorsQueue = coordinatorsQueue
        self.queueForComposedOperations = queueForComposedOperations
        self.queueForSyncHintsComputationOperation = queueForSyncHintsComputationOperation
        listenToNotifications()
    }
        
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func applicationAppearedOnScreen(forTheFirstTime: Bool) async {}

}


// MARK: - Listen to notifications

extension ContactGroupCoordinator {
    
    private func listenToNotifications() {
        
        // Internal notifications
        
        observationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeInviteContactsToGroupOwned { [weak self] groupUid, ownedCryptoId, newGroupMembers in
                self?.processInviteContactsToGroupOwnedNotification(groupUid: groupUid, ownedCryptoId: ownedCryptoId, newGroupMembers: newGroupMembers)
            },
            ObvMessengerInternalNotification.observeRemoveContactsFromGroupOwned { [weak self] groupUid, ownedCryptoId, removedContacts in
                self?.processRemoveContactsFromGroupOwnedNotification(groupUid: groupUid, ownedCryptoId: ownedCryptoId, removedContacts: removedContacts)
            },
            ObvMessengerInternalNotification.observeUserWantsToRefreshContactGroupJoined { [weak self] (obvContactGroup) in
                self?.processUserWantsToRefreshContactGroupJoined(obvContactGroup: obvContactGroup)
            },
            ObvMessengerInternalNotification.observeUserWantsToUpdateCustomNameAndGroupV2Photo() { [weak self] ownedCryptoId, groupIdentifier, customName, customPhoto in
                self?.processUserWantsToUpdateCustomNameAndGroupV2Photo(ownedCryptoId: ownedCryptoId, groupIdentifier: groupIdentifier, customName: customName, customPhoto: customPhoto)
            },
            ObvMessengerInternalNotification.observeUserHasSeenPublishedDetailsOfGroupV2() { [weak self] groupObjectID in
                self?.processUserHasSeenPublishedDetailsOfGroupV2(groupObjectID: groupObjectID)
            },
            ObvMessengerInternalNotification.observeUserWantsToSetCustomNameOfJoinedGroupV1() { [weak self] (ownedCryptoId, groupIdentifier, groupNameCustom) in
                self?.processUserWantsToSetCustomNameOfJoinedGroupV1(ownedCryptoId: ownedCryptoId, groupIdentifier: groupIdentifier, groupNameCustom: groupNameCustom)
            },
            ObvMessengerInternalNotification.observeUserWantsToUpdatePersonalNoteOnGroupV1 { [weak self] ownedCryptoId, groupIdentifier, newText in
                self?.processUserWantsToUpdatePersonalNoteOnGroupV1(ownedCryptoId: ownedCryptoId, groupIdentifier: groupIdentifier, newText: newText)
            },
            ObvMessengerInternalNotification.observeUserWantsToUpdatePersonalNoteOnGroupV2 { [weak self] ownedCryptoId, groupIdentifier, newText in
                self?.processUserWantsToUpdatePersonalNoteOnGroupV2(ownedCryptoId: ownedCryptoId, groupIdentifier: groupIdentifier, newText: newText)
            },
            ObvMessengerInternalNotification.observeUserHasSeenPublishedDetailsOfContactGroupJoined { [weak self] obvGroupIdentifier in
                self?.processUserHasSeenPublishedDetailsOfContactGroupJoined(obvGroupIdentifier: obvGroupIdentifier)
            },
        ])
        
        // ObvEngine Notifications
        
        observationTokens.append(contentsOf: [
            ObvEngineNotificationNew.observeContactGroupOwnedHasUpdatedLatestDetails(within: NotificationCenter.default) { [weak self] obvContactGroup in
                self?.processContactGroupOwnedHasUpdatedLatestDetailsNotification(obvContactGroup: obvContactGroup)
            },
            ObvEngineNotificationNew.observeContactGroupOwnedDiscardedLatestDetails(within: NotificationCenter.default) { [weak self] obvContactGroup in
                self?.processContactGroupOwnedDiscardedLatestDetailsNotification(obvContactGroup: obvContactGroup)
            },
            ObvEngineNotificationNew.observeContactGroupJoinedHasUpdatedTrustedDetails(within: NotificationCenter.default) { [weak self] obvContactGroup in
                self?.processContactGroupJoinedHasUpdatedTrustedDetailsNotification(obvContactGroup: obvContactGroup)
            },
            ObvEngineNotificationNew.observeContactGroupDeleted(within: NotificationCenter.default) { [weak self] obvOwnedIdentity, groupOwner, groupUid in
                self?.processContactGroupDeletedNotification(obvOwnedIdentity: obvOwnedIdentity, groupOwner: groupOwner, groupUid: groupUid)
            },
            ObvEngineNotificationNew.observeNewPendingGroupMemberDeclinedStatus(within: NotificationCenter.default) { [weak self] obvContactGroup in
                self?.processNewPendingGroupMemberDeclinedStatusNotification(obvContactGroup: obvContactGroup)
            },
            ObvEngineNotificationNew.observeNewContactGroup(within: NotificationCenter.default) { [weak self] obvContactGroup in
                self?.processNewContactGroupNotification(obvContactGroup: obvContactGroup)
            },
            ObvEngineNotificationNew.observeContactGroupHasUpdatedPendingMembersAndGroupMembers(within: NotificationCenter.default) { [weak self] obvContactGroup in
                self?.updatePersistedContactGroupWithObvContactGroupFromEngine(obvContactGroup: obvContactGroup)
            },
            ObvEngineNotificationNew.observeContactGroupHasUpdatedPublishedDetails(within: NotificationCenter.default) { [weak self] obvContactGroup in
                self?.updatePersistedContactGroupWithObvContactGroupFromEngine(obvContactGroup: obvContactGroup)
            },
            ObvEngineNotificationNew.observeTrustedPhotoOfContactGroupJoinedHasBeenUpdated(within: NotificationCenter.default) { [weak self] obvContactGroup in
                self?.updatePersistedContactGroupWithObvContactGroupFromEngine(obvContactGroup: obvContactGroup)
            },
            ObvEngineNotificationNew.observePublishedPhotoOfContactGroupOwnedHasBeenUpdated(within: NotificationCenter.default) { [weak self] obvContactGroup in
                self?.updatePersistedContactGroupWithObvContactGroupFromEngine(obvContactGroup: obvContactGroup)
            },
            ObvEngineNotificationNew.observePublishedPhotoOfContactGroupJoinedHasBeenUpdated(within: NotificationCenter.default) { [weak self] obvContactGroup in
                self?.updatePersistedContactGroupWithObvContactGroupFromEngine(obvContactGroup: obvContactGroup)
            },
            ObvEngineNotificationNew.observeGroupV2WasCreatedOrUpdated(within: NotificationCenter.default) { [weak self] obvGroupV2, initiator in
                Task { [weak self] in await self?.processGroupV2WasCreatedOrUpdated(obvGroupV2: obvGroupV2, initiator: initiator) }
            },
            ObvEngineNotificationNew.observeGroupV2WasDeleted(within: NotificationCenter.default) { [weak self] ownedIdentity, appGroupIdentifier in
                self?.processGroupV2WasDeleted(ownedIdentity: ownedIdentity, appGroupIdentifier: appGroupIdentifier)
            },
            ObvEngineNotificationNew.observeGroupV2UpdateDidFail(within: NotificationCenter.default) { [weak self] ownedIdentity, appGroupIdentifier in
                self?.processGroupV2UpdateDidFail(ownedIdentity: ownedIdentity, appGroupIdentifier: appGroupIdentifier)
            },
        ])
        
        // ObvMessengerGroupV2Notifications Notifications

        observationTokens.append(contentsOf: [
            ObvMessengerCoreDataNotification.observeGroupV2TrustedDetailsShouldBeReplacedByPublishedDetails { [weak self] ownCryptoId, groupIdentifier in
                self?.processGroupV2TrustedDetailsShouldBeReplacedByPublishedDetails(ownCryptoId: ownCryptoId, groupIdentifier: groupIdentifier)
            },
        ])
    }

    
    private func processUserWantsToRefreshContactGroupJoined(obvContactGroup: ObvContactGroup) {
        let ownedCryptoId = obvContactGroup.ownedIdentity.cryptoId
        let groupUid = obvContactGroup.groupUid
        let groupOwned = obvContactGroup.groupOwner.cryptoId
        do {
            try obvEngine.refreshContactGroupJoined(ownedCryptoId: ownedCryptoId, groupUid: groupUid, groupOwner: groupOwned)
        } catch {
            os_log("Could not refresh contact group joined", log: Self.log, type: .fault)
            return
        }
    }

    
    
    private func processInviteContactsToGroupOwnedNotification(groupUid: UID, ownedCryptoId: ObvCryptoId, newGroupMembers: Set<ObvCryptoId>) {
        do {
            try obvEngine.inviteContactsToGroupOwned(groupUid: groupUid,
                                                     ownedCryptoId: ownedCryptoId,
                                                     newGroupMembers: newGroupMembers)
        } catch {
            assertionFailure()
            os_log("Could not invite contact to group owned", log: Self.log, type: .error)
        }
    }
    
    
    private func processRemoveContactsFromGroupOwnedNotification(groupUid: UID, ownedCryptoId: ObvCryptoId, removedContacts: Set<ObvCryptoId>) {
        do {
            try obvEngine.removeContactsFromGroupOwned(groupUid: groupUid,
                                                       ownedCryptoId: ownedCryptoId,
                                                       removedGroupMembers: removedContacts)
        } catch {
            assertionFailure()
            os_log("Could not invite contact to group owned", log: Self.log, type: .error)
        }
    }
    
    

    private func processContactGroupOwnedHasUpdatedLatestDetailsNotification(obvContactGroup: ObvContactGroup) {
        let op1 = ProcessContactGroupOwnedHasUpdatedLatestDetailsOperation(obvContactGroup: obvContactGroup)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        coordinatorsQueue.addOperation(composedOp)
    }

    
    private func processContactGroupOwnedDiscardedLatestDetailsNotification(obvContactGroup: ObvContactGroup) {
        let op1 = ProcessContactGroupOwnedDiscardedLatestDetailsOperation(obvContactGroup: obvContactGroup)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        coordinatorsQueue.addOperation(composedOp)
    }

    
    private func processContactGroupJoinedHasUpdatedTrustedDetailsNotification(obvContactGroup: ObvContactGroup) {
        guard obvContactGroup.groupType == .joined else { assertionFailure(); return }
        let op1 = UpdatePersistedContactGroupWithObvContactGroupFromEngineOperation(obvContactGroup: obvContactGroup)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        coordinatorsQueue.addOperation(composedOp)
    }

    
    private func processNewPendingGroupMemberDeclinedStatusNotification(obvContactGroup: ObvContactGroup) {
        guard obvContactGroup.groupType == .owned else { assertionFailure(); return }
        let op1 = UpdatePersistedContactGroupWithObvContactGroupFromEngineOperation(obvContactGroup: obvContactGroup)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        coordinatorsQueue.addOperation(composedOp)
    }

    
    /// This method is called to process many distinct notifications concerning contact groups
    private func updatePersistedContactGroupWithObvContactGroupFromEngine(obvContactGroup: ObvContactGroup) {
        let op1 = UpdatePersistedContactGroupWithObvContactGroupFromEngineOperation(obvContactGroup: obvContactGroup)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        coordinatorsQueue.addOperation(composedOp)
    }


    private func processContactGroupDeletedNotification(obvOwnedIdentity: ObvOwnedIdentity, groupOwner: ObvCryptoId, groupUid: UID) {
        let op1 = ProcessContactGroupDeletedOperation(obvOwnedIdentity: obvOwnedIdentity, groupOwner: groupOwner, groupUid: groupUid)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        coordinatorsQueue.addOperation(composedOp)
    }

    
    private func processNewContactGroupNotification(obvContactGroup: ObvContactGroup) {
        let op1 = ProcessNewContactGroupOperation(obvContactGroup: obvContactGroup)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        coordinatorsQueue.addOperation(composedOp)
    }
    
    
    private func processGroupV2WasCreatedOrUpdated(obvGroupV2: ObvGroupV2, initiator: ObvGroupV2.CreationOrUpdateInitiator) async {
        let op1 = CreateOrUpdatePersistedGroupV2Operation(obvGroupV2: obvGroupV2, initiator: initiator, obvEngine: obvEngine)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
    }
    
    
    private func processGroupV2WasDeleted(ownedIdentity: ObvCryptoId, appGroupIdentifier: Data) {
        let op1 = DeletePersistedGroupV2Operation(ownedIdentity: ownedIdentity, appGroupIdentifier: appGroupIdentifier)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        coordinatorsQueue.addOperation(composedOp)
    }
    
    
    private func processGroupV2UpdateDidFail(ownedIdentity: ObvCryptoId, appGroupIdentifier: Data) {
        let op1 = RemoveUpdateInProgressForGroupV2Operation(ownedIdentity: ownedIdentity, appGroupIdentifier: appGroupIdentifier)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        coordinatorsQueue.addOperation(composedOp)
    }


    private func processUserWantsToUpdateCustomNameAndGroupV2Photo(ownedCryptoId: ObvCryptoId, groupIdentifier: Data, customName: String?, customPhoto: UIImage?) {
        let op1 = UpdateCustomNameAndGroupV2PhotoOperation(
            ownedCryptoId: ownedCryptoId,
            groupIdentifier: groupIdentifier,
            update: .customNameAndCustomPhoto(customName: customName, customPhoto: customPhoto),
            makeSyncAtomRequest: true,
            syncAtomRequestDelegate: syncAtomRequestDelegate)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        coordinatorsQueue.addOperation(composedOp)
    }

    
    private func processUserHasSeenPublishedDetailsOfGroupV2(groupObjectID: TypeSafeManagedObjectID<PersistedGroupV2>) {
        let op1 = MarkPublishedDetailsOfGroupV2AsSeenOperation(groupV2ObjectID: groupObjectID)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        coordinatorsQueue.addOperation(composedOp)
    }

    
    private func processUserWantsToSetCustomNameOfJoinedGroupV1(ownedCryptoId: ObvCryptoId, groupIdentifier: GroupV1Identifier, groupNameCustom: String?) {
        let op1 = SetCustomNameOfJoinedGroupV1Operation(ownedCryptoId: ownedCryptoId, groupIdentifier: groupIdentifier, groupNameCustom: groupNameCustom, makeSyncAtomRequest: true, syncAtomRequestDelegate: syncAtomRequestDelegate)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        coordinatorsQueue.addOperation(composedOp)
    }

    
    private func processUserWantsToUpdatePersonalNoteOnGroupV1(ownedCryptoId: ObvCryptoId, groupIdentifier: GroupV1Identifier, newText: String?) {
        let op1 = UpdatePersonalNoteOnGroupV1Operation(ownedCryptoId: ownedCryptoId, groupIdentifier: groupIdentifier, newText: newText, makeSyncAtomRequest: true, syncAtomRequestDelegate: syncAtomRequestDelegate)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        coordinatorsQueue.addOperation(composedOp)
    }

    
    private func processUserWantsToUpdatePersonalNoteOnGroupV2(ownedCryptoId: ObvCryptoId, groupIdentifier: Data, newText: String?) {
        let op1 = UpdatePersonalNoteOnGroupV2Operation(ownedCryptoId: ownedCryptoId, groupIdentifier: groupIdentifier, newText: newText, makeSyncAtomRequest: true, syncAtomRequestDelegate: syncAtomRequestDelegate)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        coordinatorsQueue.addOperation(composedOp)
    }

    
    private func processUserHasSeenPublishedDetailsOfContactGroupJoined(obvGroupIdentifier: ObvGroupV1Identifier) {
        let op1 = ProcessUserHasSeenPublishedDetailsOfContactGroupJoinedOperation(obvGroupIdentifier: obvGroupIdentifier)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        coordinatorsQueue.addOperation(composedOp)
    }

    
    private func processGroupV2TrustedDetailsShouldBeReplacedByPublishedDetails(ownCryptoId: ObvCryptoId, groupIdentifier: Data) {
        let obvEngine = self.obvEngine
        Task.detached {
            do {
                try await obvEngine.replaceTrustedDetailsByPublishedDetailsOfGroupV2(ownedCryptoId: ownCryptoId, groupIdentifier: groupIdentifier)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }
    
}
