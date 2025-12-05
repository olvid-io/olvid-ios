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
import OSLog
import CoreData
import ObvEngine
import ObvCoreDataStack
import ObvTypes
import ObvUICoreData
import ObvCrypto
import OlvidUtils
import ObvAppCoreConstants
import ObvAppTypes



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

}


// MARK: - Listen to notifications

extension ContactGroupCoordinator {
    
    private func listenToNotifications() {
        
        // Internal notifications
        
        observationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeUserWantsToUpdateCustomNameAndGroupV2Photo() { [weak self] ownedCryptoId, groupIdentifier, customName, customPhoto in
                self?.processUserWantsToUpdateCustomNameAndGroupV2Photo(ownedCryptoId: ownedCryptoId, groupIdentifier: groupIdentifier, customName: customName, customPhoto: customPhoto)
            },
            ObvMessengerInternalNotification.observeUserWantsToUpdateCustomNameAndGroupV1Photo { [weak self] groupV1Identifier, customName, customPhoto in
                self?.processUserWantsToSetCustomNameOfJoinedGroupV1(groupV1Identifier: groupV1Identifier, groupNameCustom: customName, customPhoto: customPhoto)
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

    
    /// Called from the
    func processUserHasSeenPublishedDetailsOfGroup(groupIdentifier: ObvGroupIdentifier) async throws {
        let op1 = MarkPublishedDetailsOfGroupAsSeenOperation(groupIdentifier: groupIdentifier)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            return
        }
    }
    
    
    private func processUserWantsToSetCustomNameOfJoinedGroupV1(groupV1Identifier: ObvGroupV1Identifier, groupNameCustom: String?, customPhoto: UIImage?) {
        let op1 = SetCustomNameOfJoinedGroupV1Operation(groupV1Identifier: groupV1Identifier, groupNameCustom: groupNameCustom, customPhoto: customPhoto, makeSyncAtomRequest: true, syncAtomRequestDelegate: syncAtomRequestDelegate)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        coordinatorsQueue.addOperation(composedOp)
    }

    
    /// Called from the `RootViewController`.
    func processUserWantsToUpdatePersonalNoteOnGroupV1(groupV1Identifier: ObvGroupV1Identifier, newText: String?) async throws {
        let op1 = UpdatePersonalNoteOnGroupV1Operation(ownedCryptoId: groupV1Identifier.ownedCryptoId, groupIdentifier: groupV1Identifier.groupV1Identifier, newText: newText, makeSyncAtomRequest: true, syncAtomRequestDelegate: syncAtomRequestDelegate)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            throw ObvError.couldNotUpdatePersonalNote
        }
    }

    
    /// Called from the `RootViewController`.
    func processUserWantsToUpdatePersonalNoteOnGroupV2(groupV2Identifier: ObvGroupV2Identifier, newText: String?) async throws {
        let op1 = UpdatePersonalNoteOnGroupV2Operation(ownedCryptoId: groupV2Identifier.ownedCryptoId, groupIdentifier: groupV2Identifier.identifier.appGroupIdentifier, newText: newText, makeSyncAtomRequest: true, syncAtomRequestDelegate: syncAtomRequestDelegate)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            throw ObvError.couldNotUpdatePersonalNote
        }
    }

    
    private func processGroupV2TrustedDetailsShouldBeReplacedByPublishedDetails(ownCryptoId: ObvCryptoId, groupIdentifier: Data) {
        guard let identifier = ObvGroupV2.Identifier(appGroupIdentifier: groupIdentifier) else { assertionFailure(); return }
        let groupIdentifier = ObvGroupV2Identifier(ownedCryptoId: ownCryptoId, identifier: identifier)
        Task {
            do {
                try await userWantsToReplaceTrustedDetailsByPublishedDetails(groupIdentifier: groupIdentifier)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }
    
    
    func userWantsToReplaceTrustedDetailsByPublishedDetails(groupIdentifier: ObvGroupV2Identifier) async throws {
        try await obvEngine.replaceTrustedDetailsByPublishedDetailsOfGroupV2(ownedCryptoId: groupIdentifier.ownedCryptoId, groupIdentifier: groupIdentifier.identifier.appGroupIdentifier)
    }
    
}


extension ContactGroupCoordinator {
    
    enum ObvError: Error {
        case couldNotUpdatePersonalNote
    }
    
}
