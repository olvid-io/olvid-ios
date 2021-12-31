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
import ObvMetaManager
import CoreData
import ObvTypes

final class ResumeOrSuspendAllTasksOfURLSessionOperation: Operation {
        
    enum ResumeOrSuspend {
        case resume
        case suspend
    }
    
    enum ReasonForCancel {
        case todo
    }

    private let uuid = UUID()
    private let urlSession: URLSession
    private let logSubsystem: String
    private let log: OSLog
    private let logCategory = String(describing: CleanExistingInboxAttachmentSessions.self)
    private let resumeOrSuspend: ResumeOrSuspend
    
    private(set) var reasonForCancel: ReasonForCancel?

    private var _isFinished = false {
        willSet { willChangeValue(for: \.isFinished) }
        didSet { didChangeValue(for: \.isFinished) }
    }
    override var isFinished: Bool { _isFinished }

    init(urlSession: URLSession, resumeOrSuspend: ResumeOrSuspend, logSubsystem: String) {
        self.urlSession = urlSession
        self.logSubsystem = logSubsystem
        self.log = OSLog(subsystem: logSubsystem, category: logCategory)
        self.resumeOrSuspend = resumeOrSuspend
        super.init()
    }
    
    private func cancel(withReason reason: ReasonForCancel) {
        assert(self.reasonForCancel == nil)
        self.reasonForCancel = reason
        self.cancel()
        _isFinished = true
    }
    
    override func main() {

        let resumeOrSuspend = self.resumeOrSuspend
        
        urlSession.getAllTasks { [weak self] (tasks) in
            for task in tasks {
                switch resumeOrSuspend {
                case .resume:
                    task.resume()
                case .suspend:
                    task.suspend()
                }
            }
            self?._isFinished = true
        }
        
    }
}
