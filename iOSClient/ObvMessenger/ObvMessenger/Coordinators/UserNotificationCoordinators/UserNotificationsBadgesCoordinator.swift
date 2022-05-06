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
import ObvEngine
import UserNotifications

final class UserNotificationsBadgesCoordinator: NSObject {
    
    // Properties
    
    private var currentOwnedCryptoId: ObvCryptoId? = nil {
        didSet {
            recomputeAllBadges()
        }
    }
    
    private let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier)
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: UserNotificationsBadgesCoordinator.self))
    private var notificationTokens = [NSObjectProtocol]()
    private let queueForBadgesOperations: OperationQueue = {
        let opQueue = OperationQueue()
        opQueue.maxConcurrentOperationCount = 1
        return opQueue
    }()
    
    /// List of tabs that may display a badge. We use this enum to keep track of the badges to update on the next ContextDidSaveNotification
    enum TabBadge {
        case discussions
        case invitations
    }
    
    // Keeping track of the badges to update on the next ContextDidSaveNotification
    private var _badgesToUpdate = Set<TabBadge>()
    private var badgesToUpdateQueue = DispatchQueue(label: "badgesToUpdateQueue")
    private func tabShouldUpdate(_ tabBadge: TabBadge) {
        _ = badgesToUpdateQueue.sync {
            _badgesToUpdate.insert(tabBadge)
        }
    }
    private func getAndResetTabBadgesToUpdate() -> Set<TabBadge> {
        var badgesToUpdate = Set<TabBadge>()
        badgesToUpdateQueue.sync {
            badgesToUpdate = _badgesToUpdate
            _badgesToUpdate.removeAll()
        }
        return badgesToUpdate
    }
    
    
    // MARK: - Initializer
    
    override init() {
        super.init()
        observeCurrentOwnedIdentityChangedNotifications()
        observeUIApplicationDidStartRunningNotifications()
        observeNSManagedObjectContextDidSaveNotifications()
        observeNSManagedObjectContextObjectsDidChangeNotifications()
        observeNeedToRecomputeAllBadges()
        observeUpdateBadgeBackgroundTaskWasLaunchedNotifications()
    }
    
    
    private func recomputeAllBadges() {
        guard let userDefaults = self.userDefaults else { return }
        if let currentOwnedCryptoId = self.currentOwnedCryptoId {
            let refreshBadgeForNewMessagesOperation = RefreshBadgeForNewMessagesOperation(ownedCryptoId: currentOwnedCryptoId, userDefaults: userDefaults, log: log)
            let refreshBadgeForInvitationsOperation = RefreshBadgeForInvitationsOperation(ownedCryptoId: currentOwnedCryptoId, userDefaults: userDefaults, log: log)
            queueForBadgesOperations.addOperation(refreshBadgeForNewMessagesOperation)
            queueForBadgesOperations.addOperation(refreshBadgeForInvitationsOperation)
        }
        let refreshAppBadgeOperation = RefreshAppBadgeOperation(userDefaults: userDefaults, log: log)
        queueForBadgesOperations.addOperation(refreshAppBadgeOperation)
    }
    
}


// MARK: - Listening to notifications

extension UserNotificationsBadgesCoordinator {
    
    private func observeCurrentOwnedIdentityChangedNotifications() {
        let token = ObvMessengerInternalNotification.observeCurrentOwnedCryptoIdChanged(queue: OperationQueue.main) { [weak self] (newOwnedCryptoId, apiKey) in
            self?.currentOwnedCryptoId = newOwnedCryptoId
        }
        notificationTokens.append(token)
    }
    
    
    private func observeUIApplicationDidStartRunningNotifications() {
        notificationTokens.append(ObvMessengerInternalNotification.observeAppStateChanged() { [weak self] _, currentState in
            guard currentState.isInitializedAndActive else { return }
            self?.recomputeAllBadges()
        })
    }

    private func observeNeedToRecomputeAllBadges() {
        notificationTokens.append(ObvMessengerInternalNotification.observeNeedToRecomputeAllBadges { [weak self] in
            self?.recomputeAllBadges()
        })

    }

    private func observeUpdateBadgeBackgroundTaskWasLaunchedNotifications() {
        notificationTokens.append(ObvMessengerInternalNotification.observeUpdateBadgeBackgroundTaskWasLaunched() { (completion) in
            self.recomputeAllBadges()
            os_log("🤿 Update badge task has been done in background", log: self.log, type: .info)
            completion(true)
        })
    }

    // We observe the NSManagedObjectContextObjectsDidChange in order to:
    // - Watch for updated persisted message received marked as "read" so as to decrement the appropriate counter
    // - and more

    private func observeNSManagedObjectContextObjectsDidChangeNotifications() {
        let NotificationName = Notification.Name.NSManagedObjectContextObjectsDidChange
        let token = NotificationCenter.default.addObserver(forName: NotificationName, object: nil, queue: nil) { [weak self] (notification) in
            guard let _self = self else { return }
            
            guard let userInfo = notification.userInfo else { return }
            
            guard let currentOwnedCryptoId = _self.currentOwnedCryptoId else { return }

            if let updatedObjects = userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject>, !updatedObjects.isEmpty {
                
                // Updated PersistedMessageReceived
                do {
                    let updatedPersistedMessageReceived = updatedObjects.compactMap { $0 as? PersistedMessageReceived }
                    let updatedPersistedMessageReceivedToCount = updatedPersistedMessageReceived.filter { $0.changedValues().contains(where: { (key, value) -> Bool in
                        key == PersistedMessageReceived.rawStatusKey && (value as? Int) != PersistedMessageReceived.MessageStatus.new.rawValue
                    }) }
                    if !updatedPersistedMessageReceivedToCount.isEmpty {
                        _self.tabShouldUpdate(.discussions)
                    }
                }
                
                // Updated PersistedMessageSystem
                do {
                    let updatedPersistedMessageSystem = updatedObjects.compactMap { $0 as? PersistedMessageSystem }
                    let updatedPersistedMessageSystemToConsider = updatedPersistedMessageSystem.filter { $0.changedValues().contains(where: { (key, value) -> Bool in
                        key == PersistedMessageSystem.rawStatusKey && (value as? Int) != PersistedMessageSystem.MessageStatus.new.rawValue
                    }) }
                    if !updatedPersistedMessageSystemToConsider.isEmpty {
                        _self.tabShouldUpdate(.discussions)
                    }
                }

                // Updated PersistedInvitation
                do {
                    let updatedPersistedInvitations = updatedObjects.compactMap { $0 as? PersistedInvitation }
                    let updatedPersistedInvitationsToConsider = updatedPersistedInvitations.filter { $0.ownedIdentity?.cryptoId == currentOwnedCryptoId }
                    if !updatedPersistedInvitationsToConsider.isEmpty {
                        // For invitations, we simply refresh the counter, instead of incrementing/decrementing it
                        // We cannot refresh the badge count here since this would require to query the database, which has not been updated yet.
                        // We will do this in the observer of the NSManagedObjectContextDidSave notification
                        _self.tabShouldUpdate(.invitations)
                    }
                }
                
            }
            
        }
        notificationTokens.append(token)
    }
    
    
    // We observe the NSManagedObjectContextDidSave in order to:
    // - Watch for new inserted persisted message received so as to increment the appropriate counter
    // - and more
    
    private func observeNSManagedObjectContextDidSaveNotifications() {
        let NotificationName = Notification.Name.NSManagedObjectContextDidSave
        let token = NotificationCenter.default.addObserver(forName: NotificationName, object: nil, queue: nil) { [weak self] (notification) in
            guard let _self = self else { return }
            
            guard let userInfo = notification.userInfo else { return }

            guard let userDefaults = _self.userDefaults else { return }

            guard let currentOwnedCryptoId = _self.currentOwnedCryptoId else { return }
            
            if let insertedObjects = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject>, !insertedObjects.isEmpty {
                
                // Watch for new inserted persisted message received so as to increment the appropriate counter
                
                do {
                    let insertedPersistedMessageReceived = insertedObjects.compactMap { $0 as? PersistedMessageReceived }
                    let insertedPersistedMessageReceivedToCount = insertedPersistedMessageReceived.filter { $0.contactIdentity?.ownedIdentity?.cryptoId == currentOwnedCryptoId }
                    if !insertedPersistedMessageReceivedToCount.isEmpty {
                        _self.tabShouldUpdate(.discussions)
                    }
                }
                
                // Watch for new inserted persisted message system so as to increment the appropriate counter
                
                do {
                    let insertedPersistedMessageSystem = insertedObjects.compactMap { $0 as? PersistedMessageSystem }
                    let insertedPersistedMessageSystemToCount = insertedPersistedMessageSystem.filter { $0.discussion.ownedIdentity?.cryptoId == currentOwnedCryptoId }
                    if !insertedPersistedMessageSystemToCount.isEmpty {
                        _self.tabShouldUpdate(.discussions)
                    }
                }

                // Look for new inserted invitation so as to refresh the appropriate counter
                
                let insertedPersistedInvitations = insertedObjects.compactMap { $0 as? PersistedInvitation }
                if !insertedPersistedInvitations.isEmpty {
                    _self.tabShouldUpdate(.invitations)
                }
                
            }
            
            if let deletedObjects = userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject>, !deletedObjects.isEmpty {
                
                // Look for deleted messages so as to refresh the appropriate counter (decrementing won't work since, at this point, the the managed object fails to fault the contact identity)
                
                let deletedPersistedMessageReceived = deletedObjects.compactMap { $0 as? PersistedMessageReceived }
                if !deletedPersistedMessageReceived.isEmpty {
                    _self.tabShouldUpdate(.discussions)
                }
                
                let deletedPersistedMessageSystem = deletedObjects.compactMap { $0 as? PersistedMessageSystem }
                if !deletedPersistedMessageSystem.isEmpty {
                    _self.tabShouldUpdate(.discussions)
                }
                
                // Look for new deleted invitations so as to refresh the appropriate counter
                
                let deletedPersistedInvitations = deletedObjects.compactMap { $0 as? PersistedInvitation }
                if !deletedPersistedInvitations.isEmpty {
                    _self.tabShouldUpdate(.invitations)
                }
                
            }
            
            // Update the badges if required
            
            let badgesToUpdate = _self.getAndResetTabBadgesToUpdate()
            
            guard !badgesToUpdate.isEmpty else { return }
            
            if badgesToUpdate.contains(.discussions) {
                let refreshBadgeForNewMessagesOperation = RefreshBadgeForNewMessagesOperation(ownedCryptoId: currentOwnedCryptoId, userDefaults: userDefaults, log: _self.log)
                _self.queueForBadgesOperations.addOperation(refreshBadgeForNewMessagesOperation)
            }
            
            if badgesToUpdate.contains(.invitations) {
                let refreshBadgeForInvitationsOperation = RefreshBadgeForInvitationsOperation(ownedCryptoId: currentOwnedCryptoId, userDefaults: userDefaults, log: _self.log)
                _self.queueForBadgesOperations.addOperation(refreshBadgeForInvitationsOperation)
            }
            
            let refreshAppBadgeOperation = RefreshAppBadgeOperation(userDefaults: userDefaults, log: _self.log)
            _self.queueForBadgesOperations.addOperation(refreshAppBadgeOperation)
            
        }
        notificationTokens.append(token)
    }
}


// MARK: - UserNotificationsBadgesDelegate {

extension UserNotificationsBadgesCoordinator: UserNotificationsBadgesDelegate {
    
    func getCurrentCountForNewMessagesBadgeForOwnedIdentity(with ownedCryptoId: ObvCryptoId) -> Int {
        return self.userDefaults?.integer(forKey: UserDefaultsKeyForBadge.keyForNewMessagesCountForOwnedIdentiy(with: ownedCryptoId)) ?? 0
    }
    
    func getCurrentCountForInvitationsBadgeForOwnedIdentity(with ownedCryptoId: ObvCryptoId) -> Int {
        return self.userDefaults?.integer(forKey: UserDefaultsKeyForBadge.keyForInvitationsCountForOwnedIdentiy(with: ownedCryptoId)) ?? 0
    }
}
