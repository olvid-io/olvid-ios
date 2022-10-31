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
import os.log

final class MuteDiscussionManager {

    fileprivate static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: MuteDiscussionManager.self))

    private let internalQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        queue.name = "MuteDiscussionManager internal queue"
        return queue
    }()

    private var nextTimer: Timer?

    private var observationTokens = [NSObjectProtocol]()


    init() {
        observeNewMuteExpirationNotifications()
    }

    private func observeNewMuteExpirationNotifications() {
        let log = MuteDiscussionManager.log
        observationTokens.append(ObvMessengerInternalNotification.observeNewMuteExpiration { [weak self] (_) in
            guard let _self = self else { return }
            let now = Date()
            let op = ScheduleNextTimerOperation(now: now, currentTimer: _self.nextTimer, log: log, delegate: _self)
            _self.internalQueue.addOperation(op)
        })
    }

}



extension MuteDiscussionManager: ScheduleNextTimerOperationDelegate {

    func replaceCurrentTimerWith(newTimer: Timer) {
        self.nextTimer?.invalidate()
        self.nextTimer = newTimer
        RunLoop.main.add(newTimer, forMode: .common)
    }

    func timerFired(timer: Timer) {
        let timerIsValid = timer.isValid
        Task {
            _ = await NewAppStateManager.shared.waitUntilAppIsInitialized()
            let log = MuteDiscussionManager.log
            guard timerIsValid else { return }
            let now = Date()
            ObvMessengerInternalNotification.cleanExpiredMuteNotficationsThatExpiredEarlierThanNow
                .postOnDispatchQueue()
            ObvMessengerInternalNotification.needToRecomputeAllBadges(completionHandler: { [weak self] _ in
                guard let _self = self else { return }
                let op = ScheduleNextTimerOperation(now: now, currentTimer: _self.nextTimer, log: log, delegate: _self)
                _self.internalQueue.addOperation(op)
            }).postOnDispatchQueue()
        }
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

        ObvStack.shared.performBackgroundTaskAndWait { (context) in

            let expirationDate: Date
            do {
                guard let _expirationDate = try PersistedDiscussionLocalConfiguration.getEarliestMuteExpirationDate(laterThan: now, within: context) else {
                    os_log("No planned mute expiration", log: log, type: .info)
                    return
                }
                expirationDate = _expirationDate
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

            // If we reach this point, we should schedule a timer.
            // We do not want the Timer block to keep a strong pointer on our delegate, so
            // We pass in a weak reference (we checked with the debugger, this works ;-).
            // Note that we cannot simply was [weak self] to the block (so as to access self?.delegate),
            // Since self is deallocated as soon as the operation finishes.
            weak var delegate = self.delegate
            let newTimer = Timer(fire: expirationDate, interval: 0, repeats: false, block: { timer in delegate?.timerFired(timer: timer) })
            delegate?.replaceCurrentTimerWith(newTimer: newTimer)

        }

    }

}
