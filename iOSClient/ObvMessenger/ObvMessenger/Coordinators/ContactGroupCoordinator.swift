/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import CoreDataStack
import ObvTypes

final class ContactGroupCoordinator {
    
    private let obvEngine: ObvEngine
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: ContactGroupCoordinator.self))
    private var observationTokens = [NSObjectProtocol]()
    private let internalQueue: OperationQueue
    
    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { Self.makeError(message: message) }

    init(obvEngine: ObvEngine, operationQueue: OperationQueue) {
        self.obvEngine = obvEngine
        self.internalQueue = operationQueue
        listenToNotifications()
    }
    
}


// MARK: - Listen to notifications

extension ContactGroupCoordinator {
    
    private func listenToNotifications() {
        
        // Internal notifications
        
        do {
            let NotificationType = MessengerInternalNotification.InviteContactsToGroupOwned.self
            let token = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: internalQueue) { [weak self] (notification) in
                guard let (groupUid, ownedCryptoId, newGroupMembers) = NotificationType.parse(notification) else { return }
                self?.processInviteContactsToGroupOwnedNotification(groupUid: groupUid, ownedCryptoId: ownedCryptoId, newGroupMembers: newGroupMembers)
            }
            observationTokens.append(token)
        }
        
        do {
            let NotificationType = MessengerInternalNotification.RemoveContactsFromGroupOwned.self
            let token = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: internalQueue) { [weak self] (notification) in
                guard let (groupUid, ownedCryptoId, removedContacts) = NotificationType.parse(notification) else { return }
                self?.processRemoveContactsFromGroupOwnedNotification(groupUid: groupUid, ownedCryptoId: ownedCryptoId, removedContacts: removedContacts)
            }
            observationTokens.append(token)
        }

        // ObvEngine Notifications
        
        do {
            let NotificationType = ObvEngineNotification.ContactGroupOwnedHasUpdatedLatestDetails.self
            let token = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: internalQueue) { [weak self] (notification) in
                guard let obvContactGroup = NotificationType.parse(notification) else { return }
                self?.processContactGroupOwnedHasUpdatedLatestDetailsNotification(obvContactGroup: obvContactGroup)
            }
            observationTokens.append(token)
        }

        do {
            let NotificationType = ObvEngineNotification.ContactGroupOwnedDiscardedLatestDetails.self
            let token = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: internalQueue) { [weak self] (notification) in
                guard let obvContactGroup = NotificationType.parse(notification) else { return }
                self?.processContactGroupOwnedDiscardedLatestDetailsNotification(obvContactGroup: obvContactGroup)
            }
            observationTokens.append(token)
        }

        do {
            let NotificationType = ObvEngineNotification.ContactGroupJoinedHasUpdatedTrustedDetails.self
            let token = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: internalQueue) { [weak self] (notification) in
                guard let obvContactGroup = NotificationType.parse(notification) else { return }
                self?.processContactGroupJoinedHasUpdatedTrustedDetailsNotification(obvContactGroup: obvContactGroup)
            }
            observationTokens.append(token)
        }

        do {
            let NotificationType = ObvEngineNotification.ContactGroupHasUpdatedPublishedDetails.self
            let token = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: internalQueue) { [weak self] (notification) in
                guard let obvContactGroup = NotificationType.parse(notification) else { return }
                self?.processContactGroupHasUpdatedPublishedDetailsNotification(obvContactGroup: obvContactGroup)
            }
            observationTokens.append(token)
        }

        do {
            let NotificationType = ObvEngineNotification.ContactGroupDeleted.self
            let token = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: internalQueue) { [weak self] (notification) in
                guard let (obvOwnedIdentity, groupOwner, groupUid) = NotificationType.parse(notification) else { return }
                self?.processContactGroupDeletedNotification(obvOwnedIdentity: obvOwnedIdentity, groupOwner: groupOwner, groupUid: groupUid)
            }
            observationTokens.append(token)
        }

        do {
            let NotificationType = ObvEngineNotification.NewPendingGroupMemberDeclinedStatus.self
            let token = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: internalQueue) { [weak self] (notification) in
                guard let obvContactGroup = NotificationType.parse(notification) else { return }
                self?.processNewPendingGroupMemberDeclinedStatusNotification(obvContactGroup: obvContactGroup)
            }
            observationTokens.append(token)
        }
        
        do {
            let NotificationType = ObvEngineNotification.NewContactGroup.self
            let token = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: internalQueue) { [weak self] (notification) in
                guard let obvContactGroup = NotificationType.parse(notification) else { return }
                self?.processNewContactGroupNotification(obvContactGroup: obvContactGroup)
            }
            observationTokens.append(token)
        }

        do {
            let NotificationType = ObvEngineNotification.ContactGroupHasUpdatedPendingMembersAndGroupMembers.self
            let token = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: internalQueue) { [weak self] (notification) in
                guard let obvContactGroup = NotificationType.parse(notification) else { return }
                self?.processContactGroupHasUpdatedPendingMembersAndGroupMembersNotification(obvContactGroup: obvContactGroup)
            }
            observationTokens.append(token)
        }
        
        do {
            // No need to sync this call on the internalQueue, there no concurrency issue here.
            let token = ObvMessengerInternalNotification.observeUserWantsToRefreshContactGroupJoined { [weak self] (obvContactGroup) in
                self?.processUserWantsToRefreshContactGroupJoined(obvContactGroup: obvContactGroup)
            }
            observationTokens.append(token)
        }

        observationTokens.append(contentsOf: [
            ObvEngineNotificationNew.observeTrustedPhotoOfContactGroupJoinedHasBeenUpdated(within: NotificationCenter.default, queue: internalQueue) { [weak self] (obvContactGroup) in
                self?.processTrustedPhotoOfContactGroupJoinedHasBeenUpdated(obvContactGroup: obvContactGroup)
            },
            ObvEngineNotificationNew.observePublishedPhotoOfContactGroupOwnedHasBeenUpdated(within: NotificationCenter.default, queue: internalQueue) { [weak self] (obvContactGroup) in
                self?.processPublishedPhotoOfContactGroupOwnedHasBeenUpdated(obvContactGroup: obvContactGroup)
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
            os_log("Could not refresh contact group joined", log: log, type: .fault)
            return
        }
    }

    
    
    private func processInviteContactsToGroupOwnedNotification(groupUid: UID, ownedCryptoId: ObvCryptoId, newGroupMembers: Set<ObvCryptoId>) {
        
        do {
            try obvEngine.inviteContactsToGroupOwned(groupUid: groupUid,
                                                     ownedCryptoId: ownedCryptoId,
                                                     newGroupMembers: newGroupMembers)
        } catch {
            os_log("Could not invite contact to group owned", log: log, type: .error)
        }
        
    }
    
    
    private func processRemoveContactsFromGroupOwnedNotification(groupUid: UID, ownedCryptoId: ObvCryptoId, removedContacts: Set<ObvCryptoId>) {
        
        do {
            try obvEngine.removeContactsFromGroupOwned(groupUid: groupUid,
                                                       ownedCryptoId: ownedCryptoId,
                                                       removedGroupMembers: removedContacts)
        } catch {
            os_log("Could not invite contact to group owned", log: log, type: .error)
        }

    }
    
    

    private func processContactGroupOwnedHasUpdatedLatestDetailsNotification(obvContactGroup: ObvContactGroup) {
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            context.name = "Context created in processContactGroupOwnedHasUpdatedLatestDetailsNotification"
            
            guard let persistedObvOwnedIdentity = try? PersistedObvOwnedIdentity.get(persisted: obvContactGroup.ownedIdentity, within: context) else {
                os_log("Could not find owned identity", log: log, type: .error)
                return
            }
            
            let groupId = (obvContactGroup.groupUid, obvContactGroup.groupOwner.cryptoId)
            
            guard let groupOwned = try? PersistedContactGroupOwned.getContactGroup(groupId: groupId, ownedIdentity: persistedObvOwnedIdentity) as? PersistedContactGroupOwned else {
                os_log("Could not find group owned", log: log, type: .error)
                return
            }
            
            groupOwned.setStatus(to: .withLatestDetails)

            do {
                try context.save(logOnFailure: log)
            } catch {
                os_log("Could not save context", log: log, type: .error)
                return
            }

        }
        
    }

    
    private func processContactGroupOwnedDiscardedLatestDetailsNotification(obvContactGroup: ObvContactGroup) {
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            context.name = "Context created in processContactGroupOwnedHasUpdatedLatestDetailsNotification"
            
            guard let persistedObvOwnedIdentity = try? PersistedObvOwnedIdentity.get(persisted: obvContactGroup.ownedIdentity, within: context) else {
                os_log("Could not find owned identity", log: log, type: .error)
                return
            }
            
            let groupId = (obvContactGroup.groupUid, obvContactGroup.groupOwner.cryptoId)
            
            guard let groupOwned = try? PersistedContactGroupOwned.getContactGroup(groupId: groupId, ownedIdentity: persistedObvOwnedIdentity) as? PersistedContactGroupOwned else {
                os_log("Could not find group owned", log: log, type: .error)
                return
            }
            
            groupOwned.setStatus(to: .noLatestDetails)
            
            do {
                try context.save(logOnFailure: log)
            } catch {
                os_log("Could not save context", log: log, type: .error)
                return
            }
            
        }
        
    }

    
    private func processContactGroupJoinedHasUpdatedTrustedDetailsNotification(obvContactGroup: ObvContactGroup) {
        
        guard obvContactGroup.groupType == .joined else { return }
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            context.name = "Context created in processContactGroupJoinedHasUpdatedTrustedDetailsNotification"
            
            guard let persistedObvOwnedIdentity = try? PersistedObvOwnedIdentity.get(persisted: obvContactGroup.ownedIdentity, within: context) else {
                os_log("Could not find owned identity", log: log, type: .error)
                return
            }
            
            let groupId = (obvContactGroup.groupUid, obvContactGroup.groupOwner.cryptoId)
            
            guard let groupJoined = try? PersistedContactGroupJoined.getContactGroup(groupId: groupId, ownedIdentity: persistedObvOwnedIdentity) as? PersistedContactGroupJoined else {
                os_log("Could not find group joined", log: log, type: .error)
                return
            }
            
            do {
                try groupJoined.resetGroupName(to: obvContactGroup.trustedOrLatestCoreDetails.name)
            } catch {
                os_log("Could not reset joined group name", log: log, type: .error)
                return
            }
            
            groupJoined.setStatus(to: .noNewPublishedDetails)

            groupJoined.updatePhoto(with: obvContactGroup.trustedOrLatestPhotoURL)

            do {
                try context.save(logOnFailure: log)
            } catch {
                os_log("Could not save context", log: log, type: .error)
                return
            }
            
        }

    }

    
    private func processContactGroupHasUpdatedPublishedDetailsNotification(obvContactGroup: ObvContactGroup) {
        
        switch obvContactGroup.groupType {
        case .owned:
            
            ObvStack.shared.performBackgroundTaskAndWait { (context) in
                
                guard let persistedObvOwnedIdentity = try? PersistedObvOwnedIdentity.get(persisted: obvContactGroup.ownedIdentity, within: context) else {
                    os_log("Could not find owned identity", log: log, type: .error)
                    return
                }
                
                let groupId = (obvContactGroup.groupUid, obvContactGroup.groupOwner.cryptoId)
                
                guard let groupOwned = try? PersistedContactGroupOwned.getContactGroup(groupId: groupId, ownedIdentity: persistedObvOwnedIdentity) as? PersistedContactGroupOwned else {
                    os_log("Could not find group joined", log: log, type: .error)
                    return
                }
                
                do {
                    try groupOwned.resetGroupName(to: obvContactGroup.publishedCoreDetails.name)
                } catch {
                    os_log("Could not reset owned group name", log: log, type: .error)
                    return
                }
                
                groupOwned.setStatus(to: .noLatestDetails)

                do {
                    try context.save(logOnFailure: log)
                } catch {
                    os_log("Could not save context", log: log, type: .error)
                    return
                }
                
            }
            
        case .joined:
            
            ObvStack.shared.performBackgroundTaskAndWait { (context) in
                context.name = "Context created in processContactGroupHasUpdatedPublishedDetailsNotification (joined)"
                
                guard let persistedObvOwnedIdentity = try? PersistedObvOwnedIdentity.get(persisted: obvContactGroup.ownedIdentity, within: context) else {
                    os_log("Could not find owned identity", log: log, type: .error)
                    return
                }
                
                let groupId = (obvContactGroup.groupUid, obvContactGroup.groupOwner.cryptoId)
                
                guard let groupJoined = try? PersistedContactGroupJoined.getContactGroup(groupId: groupId, ownedIdentity: persistedObvOwnedIdentity) as? PersistedContactGroupJoined else {
                    os_log("Could not find group joined", log: log, type: .error)
                    return
                }
                
                groupJoined.setStatus(to: .unseenPublishedDetails)

                do {
                    try context.save(logOnFailure: log)
                } catch {
                    os_log("Could not save context", log: log, type: .error)
                    return
                }
                
            }

            
        }
        
    }

    
    private func processTrustedPhotoOfContactGroupJoinedHasBeenUpdated(obvContactGroup: ObvContactGroup) {
        
        ObvStack.shared.performBackgroundTaskAndWait { context in

            guard let persistedObvOwnedIdentity = try? PersistedObvOwnedIdentity.get(persisted: obvContactGroup.ownedIdentity, within: context) else {
                os_log("Could not find owned identity", log: log, type: .error)
                return
            }

            let groupId = (obvContactGroup.groupUid, obvContactGroup.groupOwner.cryptoId)

            guard let groupJoined = try? PersistedContactGroupJoined.getContactGroup(groupId: groupId, ownedIdentity: persistedObvOwnedIdentity) as? PersistedContactGroupJoined else {
                os_log("Could not find group joined", log: log, type: .error)
                return
            }

            groupJoined.updatePhoto(with: obvContactGroup.trustedOrLatestPhotoURL)

            do {
                try context.save(logOnFailure: log)
            } catch {
                os_log("Could not save context", log: log, type: .error)
                return
            }

        }
        
    }

    
    private func processPublishedPhotoOfContactGroupOwnedHasBeenUpdated(obvContactGroup: ObvContactGroup) {
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            
            guard let persistedObvOwnedIdentity = try? PersistedObvOwnedIdentity.get(persisted: obvContactGroup.ownedIdentity, within: context) else {
                os_log("Could not find owned identity", log: log, type: .error)
                return
            }
            
            let groupId = (obvContactGroup.groupUid, obvContactGroup.groupOwner.cryptoId)
            
            guard let groupOwned = try? PersistedContactGroupOwned.getContactGroup(groupId: groupId, ownedIdentity: persistedObvOwnedIdentity) as? PersistedContactGroupOwned else {
                os_log("Could not find group joined", log: log, type: .error)
                return
            }
            
            groupOwned.updatePhoto(with: obvContactGroup.publishedPhotoURL)
            
            do {
                try context.save(logOnFailure: log)
            } catch {
                os_log("Could not save context", log: log, type: .error)
                return
            }
            
        }
    }

    
    private func processContactGroupDeletedNotification(obvOwnedIdentity: ObvOwnedIdentity, groupOwner: ObvCryptoId, groupUid: UID) {
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            context.name = "Context created in processContactGroupDeletedNotification"
            
            guard let persistedObvOwnedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: obvOwnedIdentity.cryptoId, within: context) else {
                os_log("Could not find owned identity", log: log, type: .error)
                return
            }
            
            let groupId = (groupUid, groupOwner)
            
            guard let group = try? PersistedContactGroup.getContactGroup(groupId: groupId, ownedIdentity: persistedObvOwnedIdentity) else {
                os_log("Could not find group", log: log, type: .error)
                return
            }
            
            let persistedGroupDiscussion = group.discussion
            
            guard PersistedDiscussionGroupLocked(persistedGroupDiscussionToLock: persistedGroupDiscussion) != nil else {
                os_log("Could not lock the persisted group discussion", log: log, type: .error)
                return
            }
            
            context.delete(group)
            
            do {
                try context.save(logOnFailure: log)
            } catch {
                os_log("Could not save context", log: log, type: .error)
                return
            }
            
        }

    }

    
    private func processNewPendingGroupMemberDeclinedStatusNotification(obvContactGroup: ObvContactGroup) {
        
        guard obvContactGroup.groupType == .owned else { return }
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            context.name = "Context created in processPendingGroupMemberDeclinedInvitationNotification"
            
            guard let persistedObvOwnedIdentity = try? PersistedObvOwnedIdentity.get(persisted: obvContactGroup.ownedIdentity, within: context) else {
                os_log("Could not find owned identity", log: log, type: .error)
                return
            }
            
            let groupId = (obvContactGroup.groupUid, obvContactGroup.groupOwner.cryptoId)
            
            guard let groupOwned = try? PersistedContactGroupOwned.getContactGroup(groupId: groupId, ownedIdentity: persistedObvOwnedIdentity) as? PersistedContactGroupOwned else {
                os_log("Could not find group owned", log: log, type: .error)
                return
            }

            let declinedMemberIdentites = Set(obvContactGroup.declinedPendingGroupMembers.map { $0.cryptoId })
            for pendingMember in groupOwned.pendingMembers {
                debugPrint(declinedMemberIdentites.contains(pendingMember.cryptoId))
                pendingMember.declined = declinedMemberIdentites.contains(pendingMember.cryptoId)
            }
            
            do {
                try context.save(logOnFailure: log)
            } catch {
                os_log("Could not save context", log: log, type: .error)
                return
            }
            
        }

    }
    
    
    private func processNewContactGroupNotification(obvContactGroup: ObvContactGroup) {
        
        assert(OperationQueue.current == internalQueue)

        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            
            context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump // External changes trump changes made here
            
            // We create a new persisted contact group associated to this engine's contact group
            
            switch obvContactGroup.groupType {
            case .owned:
                guard PersistedContactGroupOwned(contactGroup: obvContactGroup, within: context) != nil else {
                    os_log("Could not create a new contact group owned", log: log, type: .fault)
                    return
                }
            case .joined:
                guard PersistedContactGroupJoined(contactGroup: obvContactGroup, within: context) != nil else {
                    os_log("Could not create a new contact group joined", log: log, type: .fault)
                    return
                }
            }
            
            do {
                try context.save(logOnFailure: log)
            } catch {
                os_log("We could not create the group discussion: %@", log: log, type: .fault, error.localizedDescription)
                return
            }
            
        }
        
    }
    
    
    private func processContactGroupHasUpdatedPendingMembersAndGroupMembersNotification(obvContactGroup: ObvContactGroup) {
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            guard let persistedObvOwnedIdentity = try? PersistedObvOwnedIdentity.get(persisted: obvContactGroup.ownedIdentity, within: context) else {
                os_log("Could not find owned identity", log: log, type: .fault)
                return
            }
            
            let persistedObvContactIdentities: Set<PersistedObvContactIdentity> = Set(obvContactGroup.groupMembers.compactMap {
                guard let persistedContact = try? PersistedObvContactIdentity.get(persisted: $0, within: context) else {
                    os_log("One of the group members is not among our persisted contacts. The group members will be updated when this contact will be added to the persisted contact.", log: log, type: .info)
                    return nil
                }
                return persistedContact
            })
            
            let contactGroup: PersistedContactGroup
            do {
                let groupUid = obvContactGroup.groupUid
                let groupOwner = obvContactGroup.groupOwner.cryptoId
                let groupId = (groupUid, groupOwner)
                guard let _contactGroup = try PersistedContactGroup.getContactGroup(groupId: groupId, ownedIdentity: persistedObvOwnedIdentity) else { throw NSError() }
                contactGroup = _contactGroup
            } catch {
                os_log("Could not find the contact group", log: log, type: .fault)
                return
            }
            
            contactGroup.set(persistedObvContactIdentities)
            contactGroup.setPendingMembers(to: obvContactGroup.pendingGroupMembers)
            
            if let groupOwned = contactGroup as? PersistedContactGroupOwned {
                if obvContactGroup.groupType == .owned {
                    let declinedMemberIdentites = Set(obvContactGroup.declinedPendingGroupMembers.map { $0.cryptoId })
                    for pendingMember in groupOwned.pendingMembers {
                        debugPrint(declinedMemberIdentites.contains(pendingMember.cryptoId))
                        pendingMember.declined = declinedMemberIdentites.contains(pendingMember.cryptoId)
                    }
                }
            }
            
            do {
                try context.save(logOnFailure: log)
            } catch {
                os_log("We could not update the group discussion contacts", log: log, type: .fault)
                return
            }
            
        }
        
    }

}
