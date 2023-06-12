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
import os.log
import ObvTypes
import UserNotifications

actor UserNotificationsBadgesManager {
    
    // Properties
    
    private var currentOwnedCryptoId: ObvCryptoId? = nil {
        didSet {
            recomputeAllBadges(completion: { _ in })
        }
    }
    
    private let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier)
    
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: UserNotificationsBadgesManager.self))
    private var notificationTokens = [NSObjectProtocol]()
    private let queueForBadgesOperations = OperationQueue.createSerialQueue(name: "Queue for badges operations", qualityOfService: .background)
    
    /// List of tabs that may display a badge. We use this enum to keep track of the badges to update on the next ContextDidSaveNotification
    enum TabBadge {
        case discussions
        case invitations
    }
    
    // Keeping track of the badges to update on the next ContextDidSaveNotification
    private var _badgesToUpdate = Set<TabBadge>()
    private func tabShouldUpdate(_ tabBadge: TabBadge) {
        _badgesToUpdate.insert(tabBadge)
    }
    private func getAndResetTabBadgesToUpdate() -> Set<TabBadge> {
        let badgesToUpdate = _badgesToUpdate
        _badgesToUpdate.removeAll()
        return badgesToUpdate
    }
        
    // MARK: - Initializer
    
    init() {
        Task {
            await observeNotifications()
        }
    }
    
    
    func applicationAppearedOnScreen(forTheFirstTime: Bool) async {
        recomputeAllBadges(completion: { _ in })
    }
    
        
    private func recomputeAllBadges(completion: @escaping (Bool) -> Void) {
        guard let userDefaults else { completion(false); return }
        if let currentOwnedCryptoId = self.currentOwnedCryptoId {
            let refreshBadgeForNewMessagesOperation = RefreshBadgeForNewMessagesOperation(ownedCryptoId: currentOwnedCryptoId, userDefaults: userDefaults, log: Self.log)
            let refreshBadgeForInvitationsOperation = RefreshBadgeForInvitationsOperation(ownedCryptoId: currentOwnedCryptoId, userDefaults: userDefaults, log: Self.log)
            queueForBadgesOperations.addOperation(refreshBadgeForNewMessagesOperation)
            queueForBadgesOperations.addOperation(refreshBadgeForInvitationsOperation)
        }
        let refreshAppBadgeOperation = RefreshAppBadgeOperation(userDefaults: userDefaults, log: Self.log)
        queueForBadgesOperations.addOperation(refreshAppBadgeOperation)
        refreshAppBadgeOperation.completionBlock = {
            completion(true)
        }
    }
    
}


// MARK: - Listening to notifications

extension UserNotificationsBadgesManager {
    
    
    private func observeNotifications() {
        
        notificationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeNeedToRecomputeAllBadges { completion in
                Task { [weak self] in await self?.recomputeAllBadges(completion: completion) }
            },
            ObvMessengerInternalNotification.observeUpdateBadgeBackgroundTaskWasLaunched() { completion in
                Task { [weak self] in
                    await self?.recomputeAllBadges(completion: completion)
                    os_log("🤿 Update badge task has been done in background", log: Self.log, type: .info)
                }
            },
            ObvMessengerInternalNotification.observeMetaFlowControllerDidSwitchToOwnedIdentity { ownedCryptoId in
                Task { [weak self] in await self?.switchCurrentOwnedCryptoId(to: ownedCryptoId) }
            },
            ObvMessengerCoreDataNotification.observeNumberOfNewMessagesChangedForOwnedIdentity { _, _ in
                Task { [weak self] in await self?.recomputeAllBadges(completion: { _ in }) }
            },
        ])
        
        // We observe the NSManagedObjectContextObjectsDidChange in order to:
        // - Watch for updated persisted message received marked as "read" so as to decrement the appropriate counter
        // - and more

        do {
            let NotificationName = Notification.Name.NSManagedObjectContextObjectsDidChange
            let token = NotificationCenter.default.addObserver(forName: NotificationName, object: nil, queue: nil) { notification in
                guard let userInfo = notification.userInfo else { return }
                Task { [weak self] in
                    await self?.processNSManagedObjectContextObjectsDidChangeNotification(notificationsUserInfo: userInfo)
                }
            }
            notificationTokens.append(token)
        }
        
        // We observe the NSManagedObjectContextDidSave in order to:
        // - Watch for new inserted persisted message received so as to increment the appropriate counter
        // - and more

        do {
            let NotificationName = Notification.Name.NSManagedObjectContextDidSave
            let token = NotificationCenter.default.addObserver(forName: NotificationName, object: nil, queue: nil) { notification in
                guard let userInfo = notification.userInfo else { return }
                Task { [weak self] in
                    await self?.processNSManagedObjectContextDidSaveNotification(notificationsUserInfo: userInfo)
                }
            }
            notificationTokens.append(token)
        }
    }
    
    
    private func processNSManagedObjectContextObjectsDidChangeNotification(notificationsUserInfo userInfo: [AnyHashable: Any]) {
                
        if let updatedObjects = userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject>, !updatedObjects.isEmpty {
            
            // Updated PersistedMessageReceived
            do {
                let updatedPersistedMessageReceived = updatedObjects.compactMap { $0 as? PersistedMessageReceived }
                if !updatedPersistedMessageReceived.isEmpty {
                    tabShouldUpdate(.discussions)
                }
            }
            
            // Updated PersistedMessageSystem
            do {
                let updatedPersistedMessageSystem = updatedObjects.compactMap { $0 as? PersistedMessageSystem }
                if !updatedPersistedMessageSystem.isEmpty {
                    tabShouldUpdate(.discussions)
                }
            }

            // Updated PersistedInvitation
            do {
                let updatedPersistedInvitations = updatedObjects.compactMap { $0 as? PersistedInvitation }
                if !updatedPersistedInvitations.isEmpty {
                    // For invitations, we simply refresh the counter, instead of incrementing/decrementing it
                    // We cannot refresh the badge count here since this would require to query the database, which has not been updated yet.
                    // We will do this in the observer of the NSManagedObjectContextDidSave notification
                    tabShouldUpdate(.invitations)
                }
            }
            
        }

    }
    
    
    private func processNSManagedObjectContextDidSaveNotification(notificationsUserInfo userInfo: [AnyHashable: Any]) {
        
        guard let userDefaults else { assertionFailure(); return }

        guard let currentOwnedCryptoId else { return }
        
        if let insertedObjects = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject>, !insertedObjects.isEmpty {
            
            // Watch for new inserted persisted message received so as to increment the appropriate counter
            
            do {
                let insertedPersistedMessageReceived = insertedObjects.compactMap { $0 as? PersistedMessageReceived }
                if !insertedPersistedMessageReceived.isEmpty {
                    tabShouldUpdate(.discussions)
                }
            }
            
            // Watch for new inserted persisted message system so as to increment the appropriate counter
            
            do {
                let insertedPersistedMessageSystem = insertedObjects.compactMap { $0 as? PersistedMessageSystem }
                if !insertedPersistedMessageSystem.isEmpty {
                    tabShouldUpdate(.discussions)
                }
            }

            // Look for new inserted invitation so as to refresh the appropriate counter
            
            let insertedPersistedInvitations = insertedObjects.compactMap { $0 as? PersistedInvitation }
            if !insertedPersistedInvitations.isEmpty {
                tabShouldUpdate(.invitations)
            }
            
        }
        
        if let deletedObjects = userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject>, !deletedObjects.isEmpty {
            
            // Look for deleted messages so as to refresh the appropriate counter (decrementing won't work since, at this point, the the managed object fails to fault the contact identity)
            
            let deletedPersistedMessageReceived = deletedObjects.compactMap { $0 as? PersistedMessageReceived }
            if !deletedPersistedMessageReceived.isEmpty {
                tabShouldUpdate(.discussions)
            }
            
            let deletedPersistedMessageSystem = deletedObjects.compactMap { $0 as? PersistedMessageSystem }
            if !deletedPersistedMessageSystem.isEmpty {
                tabShouldUpdate(.discussions)
            }
            
            // Look for new deleted invitations so as to refresh the appropriate counter
            
            let deletedPersistedInvitations = deletedObjects.compactMap { $0 as? PersistedInvitation }
            if !deletedPersistedInvitations.isEmpty {
                tabShouldUpdate(.invitations)
            }
            
        }
        
        // Update the badges if required
        
        let badgesToUpdate = getAndResetTabBadgesToUpdate()
        
        guard !badgesToUpdate.isEmpty else { return }
        
        if badgesToUpdate.contains(.discussions) {
            let refreshBadgeForNewMessagesOperation = RefreshBadgeForNewMessagesOperation(ownedCryptoId: currentOwnedCryptoId, userDefaults: userDefaults, log: Self.log)
            queueForBadgesOperations.addOperation(refreshBadgeForNewMessagesOperation)
        }
        
        if badgesToUpdate.contains(.invitations) {
            let refreshBadgeForInvitationsOperation = RefreshBadgeForInvitationsOperation(ownedCryptoId: currentOwnedCryptoId, userDefaults: userDefaults, log: Self.log)
            queueForBadgesOperations.addOperation(refreshBadgeForInvitationsOperation)
        }
        
        let refreshAppBadgeOperation = RefreshAppBadgeOperation(userDefaults: userDefaults, log: Self.log)
        queueForBadgesOperations.addOperation(refreshAppBadgeOperation)

    }
    
}


// MARK: - Updating the current owned identity

extension UserNotificationsBadgesManager {
    
    private func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) async {
        currentOwnedCryptoId = newOwnedCryptoId
    }
    
}
