/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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


final class CleanExistingInboxAttachmentSessionsOperation: ContextualOperationWithSpecificReasonForCancel<CleanExistingInboxAttachmentSessionsOperation.ReasonForCancel>, @unchecked Sendable {
    
    
    private let uuid = UUID()
    private let logSubsystem: String
    private let log: OSLog
    private let logCategory = String(describing: CleanExistingInboxAttachmentSessionsOperation.self)
    
    
    init(logSubsystem: String) {
        self.logSubsystem = logSubsystem
        self.log = OSLog(subsystem: logSubsystem, category: logCategory)
        super.init()
    }

    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            let attachmentSessions = try InboxAttachmentSession.getAll(within: obvContext)

            for attachmentSession in attachmentSessions {
                
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
                
                try attachmentSession.deleteInboxAttachmentSession()
                
            }
                        
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case coreDataError(error: Error)
        case cannotFindAttachmentInDatabase
        case noOutboxAttachmentSessionSet
        
        public var logType: OSLogType {
            switch self {
            case .coreDataError,
                    .noOutboxAttachmentSessionSet,
                    .cannotFindAttachmentInDatabase:
                return .fault
            }
        }
        
        public var errorDescription: String? {
            switch self {
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .cannotFindAttachmentInDatabase:
                return "Cannot find attachment in database"
            case .noOutboxAttachmentSessionSet:
                return "No outbox attachment session set"
            }
        }
        
    }

}
