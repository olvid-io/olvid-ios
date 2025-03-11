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
import OlvidUtils
import ObvUICoreData
import ObvAppCoreConstants


protocol ExpirationMessagesManagerDelegate: AnyObject {
    func wipeAllMessagesThatExpiredEarlierThanNow(launchedByBackgroundTask: Bool) async throws
}


final class ExpirationMessagesManager {

    fileprivate static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: ExpirationMessagesManager.self))
    fileprivate static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: ExpirationMessagesManager.self))

    private let internalQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        queue.name = "ExpirationMessagesManager internal queue"
        return queue
    }()

    private var nextTimer: Timer?

    private var observationTokens = [NSObjectProtocol]()
    
    weak var delegate: ExpirationMessagesManagerDelegate?
    
    init() {
        observeNewMessageExpirationNotifications()
        observeCleanExpiredMessagesBackgroundTaskWasLaunched()
    }
    
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    
    func applicationAppearedOnScreen(forTheFirstTime: Bool) async {

        guard forTheFirstTime else { return }

        let now = Date()
        
        if let delegate {
            do {
                try await delegate.wipeAllMessagesThatExpiredEarlierThanNow(launchedByBackgroundTask: false)
                Self.logger.info("Expired message were wiped at startup with success")
            } catch {
                Self.logger.fault("Could not wipe all messages that expired earlier than now: \(error.localizedDescription)")
                assertionFailure()
                // Continue anyway
            }
        } else {
            assertionFailure()
            Self.logger.fault("The delegate is not set")
        }
            
        let op = ScheduleNextTimerOperation(now: now, currentTimer: self.nextTimer, log: Self.log, delegate: self)
        internalQueue.addOperation(op)
        
    }

    
    private func observeNewMessageExpirationNotifications() {
        let log = ExpirationMessagesManager.log
        observationTokens.append(ObvMessengerCoreDataNotification.observeNewMessageExpiration { [weak self] (_) in
            guard let self else { return }
            internalQueue.addOperation { [weak self] in
                guard let self else { return }
                let op = ScheduleNextTimerOperation(now: Date.now, currentTimer: self.nextTimer, log: log, delegate: self)
                internalQueue.addOperation(op)
            }
        })
    }
    
    
    private func observeCleanExpiredMessagesBackgroundTaskWasLaunched() {
        observationTokens.append(ObvMessengerInternalNotification.observeCleanExpiredMessagesBackgroundTaskWasLaunched { (completion) in
            Task { [weak self] in
                guard let self else { return completion(false) }
                guard let delegate else { return completion(false) }
                do {
                    try await delegate.wipeAllMessagesThatExpiredEarlierThanNow(launchedByBackgroundTask: true)
                    return completion(true)
                } catch {
                    return completion(false)
                }
            }
        })
    }
    
}


extension ExpirationMessagesManager: ScheduleNextTimerOperationDelegate {
    
    func replaceCurrentTimerWith(newTimer: Timer) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.nextTimer?.invalidate()
            self.nextTimer = newTimer
            RunLoop.main.add(newTimer, forMode: .common)
        }
    }
    
    
    func timerFired(timer: Timer) {
        guard timer.isValid else { return }
        let now = Date()
        Task { [weak self] in
            guard let self else { return }

            _ = await NewAppStateManager.shared.waitUntilAppIsInitialized()
            
            if let delegate {
                do {
                    try await delegate.wipeAllMessagesThatExpiredEarlierThanNow(launchedByBackgroundTask: false)
                    Self.logger.info("Expired message were wiped thanks to a timer that fired.")
                } catch {
                    Self.logger.fault("Expired message could not be wiped thanks to a timer that fired: \(error.localizedDescription)")
                    assertionFailure()
                    // Continue anyway
                }
            } else {
                assertionFailure()
                Self.logger.fault("The delegate is not set")
            }

            let op = ScheduleNextTimerOperation(now: now, currentTimer: nextTimer, log: Self.log, delegate: self)
            internalQueue.addOperation(op)
            
        }
    }
    
}


fileprivate final class ScheduleNextTimerOperation: Operation, @unchecked Sendable {
    
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
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            
            let expirationDate: Date
            do {
                
//                // An expiration can be inserted after its expiration date. This can occur when:
//                // - The message is decrypted by the notification extension while the app is in the inactive. The app is later launched and processes the message after the expiration.
//                // - The device is in flight mode and receives the message later.
//                // Thus, we try to wipe expired messages here.
//
//                let completion: (Bool) -> Void = { success in
//                    os_log("Expired message (found before scheduling next timer) with success: %{public}@", log: self.log, type: .info, success.description)
//                }
//                ObvMessengerInternalNotification.wipeAllMessagesThatExpiredEarlierThanNow(launchedByBackgroundTask: false,
//                                                                                          completionHandler: completion).postOnDispatchQueue()

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
            let newTimer = Timer(fire: expirationDate, interval: 0, repeats: false) { timer in
                delegate?.timerFired(timer: timer)
            }
            delegate?.replaceCurrentTimerWith(newTimer: newTimer)
            
        }
        
    }
    
}

protocol ScheduleNextTimerOperationDelegate: AnyObject {
    func replaceCurrentTimerWith(newTimer: Timer)
    func timerFired(timer: Timer)
}
