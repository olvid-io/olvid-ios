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
import UIKit
import os.log

final class ExpirationMessagesCoordinator {

    fileprivate static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: ExpirationMessagesCoordinator.self))

    private let internalQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        queue.name = "ExpirationMessagesCoordinator internal queue"
        return queue
    }()

    private var nextTimer: Timer?

    private var observationTokens = [NSObjectProtocol]()
    
    init() {
        observeAppStateChangedNotifications()
        observeNewMessageExpirationNotifications()
        observeCleanExpiredMessagesBackgroundTaskWasLaunched()
    }
    
    
    private func observeAppStateChangedNotifications() {
        let log = ExpirationMessagesCoordinator.log
        observationTokens.append(ObvMessengerInternalNotification.observeAppStateChanged() { [weak self] (previousState, currentState) in
            guard let _self = self else { return }
            if currentState.isInitializedAndActive {
                let now = Date()
                let completion: (Bool) -> Void = { success in
                    os_log("Expired message were wiped at startup with success: %{public}@", log: log, type: .info, success.description)
                }
                ObvMessengerInternalNotification.wipeAllMessagesThatExpiredEarlierThanNow(launchedByBackgroundTask: false, completionHandler: completion)
                    .postOnDispatchQueue()
                let op = ScheduleNextTimerOperation(now: now, currentTimer: _self.nextTimer, log: log, delegate: _self)
                _self.internalQueue.addOperation(op)
            }
        })
    }

    
    private func observeNewMessageExpirationNotifications() {
        let log = ExpirationMessagesCoordinator.log
        observationTokens.append(ObvMessengerInternalNotification.observeNewMessageExpiration(queue: internalQueue) { [weak self] (_) in
            guard let _self = self else { return }
            let now = Date()
            let op = ScheduleNextTimerOperation(now: now, currentTimer: _self.nextTimer, log: log, delegate: _self)
            _self.internalQueue.addOperation(op)
        })
    }
    
    
    private func observeCleanExpiredMessagesBackgroundTaskWasLaunched() {
        observationTokens.append(ObvMessengerInternalNotification.observeCleanExpiredMessagesBackgroundTaskWasLaunched { (completion) in
            let completionHandler: (Bool) -> Void = { (success) in
                DispatchQueue.main.async {
                    (UIApplication.shared.delegate as? AppDelegate)?.scheduleBackgroundTaskForCleaningExpiredMessages()
                    completion(success)
                }
            }
            ObvMessengerInternalNotification.wipeAllMessagesThatExpiredEarlierThanNow(launchedByBackgroundTask: true, completionHandler: completionHandler)
                .postOnDispatchQueue()
        })
    }
    
}


extension ExpirationMessagesCoordinator: ScheduleNextTimerOperationDelegate {
    
    func replaceCurrentTimerWith(newTimer: Timer) {
        self.nextTimer?.invalidate()
        self.nextTimer = newTimer
        RunLoop.main.add(newTimer, forMode: .common)
    }
    
    func timerFired(timer: Timer) {
        let log = ExpirationMessagesCoordinator.log
        guard timer.isValid else { return }
        let now = Date()
        let completion: (Bool) -> Void = { success in
            os_log("Expired message were wiped thanks to a timer that fired. Wipe success is: %{public}@", log: log, type: .info, success.description)
        }
        guard AppStateManager.shared.currentState.isInitialized else { return }
        ObvMessengerInternalNotification.wipeAllMessagesThatExpiredEarlierThanNow(launchedByBackgroundTask: false, completionHandler: completion)
            .postOnDispatchQueue()
        let op = ScheduleNextTimerOperation(now: now, currentTimer: self.nextTimer, log: log, delegate: self)
        internalQueue.addOperation(op)
    }
    
}


fileprivate final class ScheduleNextTimerOperation: Operation {
    
    let now: Date
    let currentTimer: Timer?
    let log: OSLog
    weak var delegate: ScheduleNextTimerOperationDelegate?
    
    init(now: Date, currentTimer: Timer?, log: OSLog, delegate: ScheduleNextTimerOperationDelegate) {
        self.now = now
        self.currentTimer = currentTimer
        self.log = log
        self.delegate = delegate
        super.init()
    }
    
    override func main() {
        
        guard AppStateManager.shared.currentState.isInitialized else {
            os_log("A ScheduleNextTimerOperation is executing before the app is initialized. Returning now.", log: log, type: .error)
            return
        }
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            
            let expirationDate: Date
            do {
                guard let expiration = try PersistedMessageExpiration.getEarliestExpiration(laterThan: now, within: context) else {
                    os_log("No planned message expiration", log: log, type: .info)
                    return
                }
                expirationDate = expiration.expirationDate
                if let currentTimer = self.currentTimer {
                    if currentTimer.fireDate > Date() {
                        guard expirationDate < currentTimer.fireDate else {
                            os_log("The previous scheduled timer will fire ealier than the eariliest expiration in DB", log: log, type: .info)
                            return
                        }
                    } else {
                        delegate?.timerFired(timer: currentTimer)
                    }
                }
            } catch {
                os_log("Could not get earliest message expiration: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
            
            /*
             * If we reach this point, we should schedule a timer.
             * We do not want the Timer block to keep a strong pointer on our delegate, so
             * we pass in a weak reference (we checked with the debugger, this works ;-).
             * Note that we cannot simply was [weak self] to the block (so as to access self?.delegate),
             * since self is deallocated as soon as the operation finishes.
             */
            weak var delegate = self.delegate
            let newTimer = Timer(fire: expirationDate, interval: 0, repeats: false, block: { timer in delegate?.timerFired(timer: timer) })
            delegate?.replaceCurrentTimerWith(newTimer: newTimer)
            
        }
        
    }
    
}

protocol ScheduleNextTimerOperationDelegate: AnyObject {
    func replaceCurrentTimerWith(newTimer: Timer)
    func timerFired(timer: Timer)
}



// MARK: - Extending AppDelegate for managing the background task allowing to wipe expired messages

extension AppDelegate {

    /// If there exists at least one message expiration in database, this method schedules a background task allowing to perform a wipe of the associated message in the background.
    /// This method is called when the app goes in the background.
    func scheduleBackgroundTaskForCleaningExpiredMessages() {
        // We make sure the app was initialized. Otherwise, the shared stack is not garanteed to exist. Accessing it would crash the app.
        guard AppStateManager.shared.currentState.isInitialized else { return }
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            let log = ExpirationMessagesCoordinator.log
            let nextExpirationDate: Date
            do {
                guard let expiration = try PersistedMessageExpiration.getEarliestExpiration(laterThan: Date(), within: context) else {
                    os_log("🤿 We do not schedule any background task for message expiration since there is no expiration left", log: log, type: .info)
                    return
                }
                nextExpirationDate = expiration.expirationDate
            } catch {
                os_log("🤿 We could not get earliest expiration: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
            // If we reach this point, we should schedule a background task for message expiration
            do {
                try BackgroundTasksManager.shared.submit(task: .cleanExpiredMessages, earliestBeginDate: nextExpirationDate)
            } catch {
                guard ObvMessengerConstants.isRunningOnRealDevice else { assertionFailure("We should not be scheduling BG tasks on a simulator as they are unsuported"); return }
                os_log("🤿 Could not schedule next expiration: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
        }
    }

    
}
