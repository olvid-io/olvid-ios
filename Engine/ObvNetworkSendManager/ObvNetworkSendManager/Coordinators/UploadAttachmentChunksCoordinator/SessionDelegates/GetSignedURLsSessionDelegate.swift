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
import ObvMetaManager
import ObvTypes
import ObvServerInterface
import OlvidUtils


final class GetSignedURLsSessionDelegate: NSObject {
    
    private let uuid = UUID()
    private let attachmentId: AttachmentIdentifier
    private let obvContext: ObvContext
    private let appType: AppType
    private let log: OSLog
    private var dataReceived = Data()
    private let logCategory = String(describing: GetSignedURLsSessionDelegate.self)

    private weak var tracker: AttachmentChunksSignedURLsTracker?
    
    private var flowId: FlowIdentifier {
        return obvContext.flowId
    }

    enum ErrorForTracker: Error {
        case aTaskDidBecomeInvalidWithError(error: Error)
        case couldNotParseServerResponse
        case cannotFindAttachmentInDatabase
        case couldNotSaveContext
        case attachmentWasDeletedFromServerSoWeDidSetItAsAcknowledged
        case generalErrorFromServer
        case sessionInvalidationError(error: Error)
    }

    // First error "wins"
    private var _error: ErrorForTracker?
    private var errorForTracker: ErrorForTracker? {
        get { _error }
        set {
            guard _error == nil && newValue != nil else { return }
            _error = newValue
        }
    }

    init(attachmentId: AttachmentIdentifier, obvContext: ObvContext, appType: AppType, logSubsystem: String, attachmentChunksSignedURLsTracker: AttachmentChunksSignedURLsTracker) {
        self.attachmentId = attachmentId
        self.obvContext = obvContext
        self.appType = appType
        self.log = OSLog(subsystem: logSubsystem, category: logCategory)
        self.tracker = attachmentChunksSignedURLsTracker
        super.init()
    }
    
}


// MARK: - Tracker

protocol AttachmentChunksSignedURLsTracker: AnyObject {
    func getSignedURLsSessionDidBecomeInvalid(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier, error: GetSignedURLsSessionDelegate.ErrorForTracker?)
}


// MARK: - URLSessionDataDelegate

extension GetSignedURLsSessionDelegate: URLSessionDataDelegate {


    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        dataReceived.append(data)
    }

    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
                
        guard error == nil else {
            os_log("The GetSignedURLsSessionDelegate task failed for attachment %{public}@: %@", log: log, type: .error, attachmentId.debugDescription, error!.localizedDescription)
            self.errorForTracker = .aTaskDidBecomeInvalidWithError(error: error!)
            return
        }
        
        // If we reach this point, the data task did complete without error
        
        guard let (status, returnedValues) = ObvServerUploadPrivateURLsForAttachmentChunksMethod.parseObvServerResponse(responseData: dataReceived, using: log) else {
            os_log("Could not parse the server response for the ObvServerDownloadPrivateURLsForAttachmentChunksMethod for attachment %{public}@", log: log, type: .fault, attachmentId.debugDescription)
            self.errorForTracker = .couldNotParseServerResponse
            return
        }
        
        switch status {
        case .ok:
            
            let chunkDownloadPrivateUrls = returnedValues!
            
            obvContext.performAndWait {
                
                guard let attachment = OutboxAttachment.get(attachmentId: attachmentId, within: obvContext) else {
                    os_log("Could not find attachment %{public}@", log: log, type: .fault, attachmentId.debugDescription)
                    self.errorForTracker = .cannotFindAttachmentInDatabase
                    return
                }
                
                do {
                    try attachment.setChunkUploadSignedUrls(chunkDownloadPrivateUrls)
                    try obvContext.save(logOnFailure: log)
                } catch {
                    os_log("Could not set the attachment chunk private URLs", log: log, type: .fault)
                    self.errorForTracker = .couldNotSaveContext
                    return
                }
                
                os_log("We successfully set new private URLs for the chunks of attachment %{public}@ (2)", log: log, type: .info, attachmentId.debugDescription)
                return
            }
            
        case .deletedFromServer:
            // We assume that this means that the attachment was uploaded in the past, that the recipient did fetch everything, which would be the reason why there is no attachment left on the server
            os_log("Server reported that the attachment was deleted from server for attachment %{public}@", log: log, type: .fault, attachmentId.debugDescription)

            obvContext.performAndWait {
                
                guard let attachment = OutboxAttachment.get(attachmentId: attachmentId, within: obvContext) else {
                    os_log("Could not find attachment %{public}@", log: log, type: .fault, attachmentId.debugDescription)
                    self.errorForTracker = .cannotFindAttachmentInDatabase
                    return
                }
                
                os_log("Setting all chunks of attachment %{public}@ as aknowledged", log: log, type: .error, attachmentId.debugDescription)
                attachment.setAllChunksAsAcknowledged(by: appType)
                
                do {
                    try obvContext.save(logOnFailure: log)
                } catch {
                    self.errorForTracker = .couldNotSaveContext
                    return
                }
                
                self.errorForTracker = .attachmentWasDeletedFromServerSoWeDidSetItAsAcknowledged
                return
            }
            
        case .generalError:
            os_log("Server reported general error during the DownloadPrivateURLsForAttachmentChunksUploadCoordinator data task for attachment %{public}@", log: log, type: .fault, attachmentId.debugDescription)
            self.errorForTracker = .generalErrorFromServer
            return
        }
        
    }
    
    
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        
        let tracker = self.tracker
        let attachmentId = self.attachmentId
        let flowId = self.flowId

        if let error = error {
            errorForTracker = .sessionInvalidationError(error: error)
        }
        
        let errorForTracker = self.errorForTracker
        DispatchQueue(label: "Queue for calling uploadAttachmentChunksSessionDidBecomeInvalid").async {
            tracker?.getSignedURLsSessionDidBecomeInvalid(attachmentId: attachmentId, flowId: flowId, error: errorForTracker)
        }

    }
}
