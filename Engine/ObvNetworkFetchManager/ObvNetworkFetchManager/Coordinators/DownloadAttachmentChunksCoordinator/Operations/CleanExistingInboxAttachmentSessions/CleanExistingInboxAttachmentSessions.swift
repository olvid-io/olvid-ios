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
import ObvMetaManager
import CoreData
import ObvTypes
import OlvidUtils


final class CleanExistingInboxAttachmentSessions: Operation {
        
    enum ReasonForCancel: Hashable {
        case contextCreatorIsNotSet
        case cannotFindAttachmentInDatabase
        case noOutboxAttachmentSessionSet
        case couldNotSaveContext
        case coreDataFailure
    }

    private let uuid = UUID()
    private let attachmentId: ObvAttachmentIdentifier
    private let logSubsystem: String
    private let log: OSLog
    private let logCategory = String(describing: CleanExistingInboxAttachmentSessions.self)
    private let flowId: FlowIdentifier
    private weak var contextCreator: ObvCreateContextDelegate?
    private weak var delegate: FinalizeCleanExistingInboxAttachmentSessionsDelegate?
    
    private(set) var reasonForCancel: ReasonForCancel?

    init(attachmentId: ObvAttachmentIdentifier, logSubsystem: String, contextCreator: ObvCreateContextDelegate, delegate: FinalizeCleanExistingInboxAttachmentSessionsDelegate, flowId: FlowIdentifier) {
        self.attachmentId = attachmentId
        self.logSubsystem = logSubsystem
        self.log = OSLog(subsystem: logSubsystem, category: logCategory)
        self.contextCreator = contextCreator
        self.delegate = delegate
        self.flowId = flowId
        super.init()
    }
    
    private func cancel(withReason reason: ReasonForCancel) {
        assert(self.reasonForCancel == nil)
        self.reasonForCancel = reason
        self.cancel()
    }
    
    override func main() {
        
        defer {
            let attachmentId = self.attachmentId
            let flowId = self.flowId
            let error = self.reasonForCancel
            let delegate = self.delegate
            DispatchQueue(label: "Queue for calling cleanExistingInboxAttachmentSessionsIsFinished").async {
                assert(delegate != nil)
                delegate?.cleanExistingInboxAttachmentSessionsIsFinished(attachmentId: attachmentId, flowId: flowId, error: error)
            }
            
        }
        
        guard let contextCreator = self.contextCreator else {
            return cancel(withReason: .contextCreatorIsNotSet)
        }
        
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
            let attachment: InboxAttachment
            do {
                guard let _attachment = try InboxAttachment.get(attachmentId: attachmentId, within: obvContext) else {
                    return cancel(withReason: .cannotFindAttachmentInDatabase)
                }
                attachment = _attachment
            } catch {
                os_log("Failed to get inbox attachment: %{public}@", log: log, type: .fault, error.localizedDescription)
                return cancel(withReason: .coreDataFailure)
            }

            guard let attachmentSession = attachment.session else {
                return cancel(withReason: .noOutboxAttachmentSessionSet)
            }
            
            let sessionConfiguration = URLSessionConfiguration.background(withIdentifier: attachmentSession.sessionIdentifier)
            sessionConfiguration.waitsForConnectivity = false
            sessionConfiguration.isDiscretionary = false
            sessionConfiguration.allowsCellularAccess = true
            sessionConfiguration.sessionSendsLaunchEvents = true
            sessionConfiguration.shouldUseExtendedBackgroundIdleMode = true
            sessionConfiguration.allowsConstrainedNetworkAccess = true
            sessionConfiguration.allowsExpensiveNetworkAccess = true
            
            let urlSession = URLSession(configuration: sessionConfiguration, delegate: nil, delegateQueue: nil)
            urlSession.invalidateAndCancel()
            
            obvContext.delete(attachmentSession)
            
            do {
                try obvContext.save(logOnFailure: log)
            } catch {
                cancel(withReason: .couldNotSaveContext)
            }
            
        }
    
    }
    
}


protocol FinalizeCleanExistingInboxAttachmentSessionsDelegate: AnyObject {
    
    func cleanExistingInboxAttachmentSessionsIsFinished(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier, error: CleanExistingInboxAttachmentSessions.ReasonForCancel?)
    
}
