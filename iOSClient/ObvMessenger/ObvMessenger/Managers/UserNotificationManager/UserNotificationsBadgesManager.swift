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
import ObvTypes
import UserNotifications
import ObvUICoreData

actor UserNotificationsBadgesManager {
    
    // Properties
    
    private var currentOwnedCryptoId: ObvCryptoId?
    
    private let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier)
    private var notificationTokens = [NSObjectProtocol]()
    private let queueForBadgesOperations = OperationQueue.createSerialQueue(name: "Queue for badges operations")

    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: UserNotificationsBadgesManager.self))

    // MARK: - Initializer
    
    init() {
        Task {
            await observeNotifications()
        }
    }
    
    deinit {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    
    func applicationAppearedOnScreen(forTheFirstTime: Bool) async {
        await recomputeAllBadges()
    }
    

    private func recomputeAllBadges(completion: ((Bool) -> Void)? = nil) async {
        
        guard let userDefaults else {
            assertionFailure()
            completion?(false)
            return
        }
        
        var operationsToQueue = [Operation]()
        
        if let currentOwnedCryptoId = self.currentOwnedCryptoId {
            let refreshBadgeForNewMessagesOperation = RefreshBadgeForNewMessagesOperation(ownedCryptoId: currentOwnedCryptoId, userDefaults: userDefaults, log: Self.log)
            let refreshBadgeForInvitationsOperation = RefreshBadgeForInvitationsOperation(ownedCryptoId: currentOwnedCryptoId, userDefaults: userDefaults, log: Self.log)
            operationsToQueue.append(refreshBadgeForNewMessagesOperation)
            operationsToQueue.append(refreshBadgeForInvitationsOperation)
        }
        
        if await canRefreshAppBadge() {
            let refreshAppBadgeOperation = RefreshAppBadgeOperation(userDefaults: userDefaults, log: Self.log)
            operationsToQueue.append(refreshAppBadgeOperation)
        }
        
        if let completion {
            let currentOperationsToQueue = operationsToQueue
            let blockOperation = BlockOperation()
            blockOperation.completionBlock = {
                if currentOperationsToQueue.first(where: { $0.isCancelled }) != nil {
                    assertionFailure()
                    completion(false)
                } else {
                    completion(true)
                }
            }
            operationsToQueue.append(blockOperation)
        }
        
        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        
        operationsToQueue.forEach { queueForBadgesOperations.addOperation($0) }
        
    }
    
    
    private func canRefreshAppBadge() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let notificationSettings = await center.notificationSettings()
        let badgeSetting = notificationSettings.badgeSetting
        switch badgeSetting {
        case .notSupported, .disabled:
            return false
        case .enabled:
            return true
        @unknown default:
            return false
        }
    }
    
}


// MARK: - Listening to notifications

extension UserNotificationsBadgesManager {
    
    
    private func observeNotifications() {
        
        notificationTokens.append(contentsOf: [
            ObvMessengerCoreDataNotification.observeNewPersistedObvOwnedIdentity { _, _ in
                Task { [weak self] in await self?.recomputeAllBadges() }
            },
            ObvMessengerCoreDataNotification.observeOwnedIdentityWasReactivated { _ in
                Task { [weak self] in await self?.recomputeAllBadges() }
            },
            ObvMessengerCoreDataNotification.observeOwnedIdentityWasDeactivated { _ in
                Task { [weak self] in await self?.recomputeAllBadges() }
            },
            ObvMessengerCoreDataNotification.observeBadgeCountForDiscussionsOrInvitationsTabChangedForOwnedIdentity { [weak self] _ in
                Task { [weak self] in await self?.recomputeAllBadges() }
            },
            ObvMessengerInternalNotification.observeUpdateBadgeBackgroundTaskWasLaunched() { [weak self] completion in
                Task { [weak self] in await self?.recomputeAllBadges(completion: completion) }
            },
            ObvMessengerInternalNotification.observeMetaFlowControllerDidSwitchToOwnedIdentity { [weak self] ownedCryptoId in
                Task { [weak self] in await self?.switchCurrentOwnedCryptoId(to: ownedCryptoId) }
            },
        ])
        
    }
    
        
}


// MARK: - Updating the current owned identity

extension UserNotificationsBadgesManager {
    
    private func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) async {
        currentOwnedCryptoId = newOwnedCryptoId
        await recomputeAllBadges()
    }
    
}
