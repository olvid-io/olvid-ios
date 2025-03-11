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


final class ManuallyAcknowledgeChunksThenInvalidateAndCancelAndDeleteOutboxAttachmentSessionOperation: Operation, @unchecked Sendable {
        
    enum ReasonForCancel: Hashable {
        case contextCreatorIsNotSet
        case cannotFindAttachmentInDatabase
        case noOutboxAttachmentSessionSet
        case couldNotSaveContext
    }

    private let uuid = UUID()
    private let attachmentId: ObvAttachmentIdentifier
    private let logSubsystem: String
    private let log: OSLog
    private let logCategory = String(describing: ManuallyAcknowledgeChunksThenInvalidateAndCancelAndDeleteOutboxAttachmentSessionOperation.self)
    private let flowId: FlowIdentifier
    private let sharedContainerIdentifier: String
    private weak var contextCreator: ObvCreateContextDelegate?
    
    private(set) var reasonForCancel: ReasonForCancel?

    private var _isFinished = false {
        willSet { willChangeValue(for: \.isFinished) }
        didSet { didChangeValue(for: \.isFinished) }
    }
    override var isFinished: Bool { _isFinished }

    init(attachmentId: ObvAttachmentIdentifier, logSubsystem: String, contextCreator: ObvCreateContextDelegate, flowId: FlowIdentifier, sharedContainerIdentifier: String) {
        self.attachmentId = attachmentId
        self.logSubsystem = logSubsystem
        self.log = OSLog(subsystem: logSubsystem, category: logCategory)
        self.contextCreator = contextCreator
        self.flowId = flowId
        self.sharedContainerIdentifier = sharedContainerIdentifier
        super.init()
    }
    
    private func cancel(withReason reason: ReasonForCancel) {
        assert(self.reasonForCancel == nil)
        self.reasonForCancel = reason
        self.cancel()
        _isFinished = true
    }

    override func main() {
        
        guard let contextCreator = self.contextCreator else {
            return cancel(withReason: .contextCreatorIsNotSet)
        }
        
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
            guard let outboxAttachment = try? OutboxAttachment.get(attachmentId: attachmentId, within: obvContext) else {
                return cancel(withReason: .cannotFindAttachmentInDatabase)
            }
            
            guard let outboxAttachmentSession = outboxAttachment.session else {
                return cancel(withReason: .noOutboxAttachmentSessionSet)
            }
            
            let originalAppType = outboxAttachmentSession.appType ?? .mainApp
            
            let sessionConfiguration = URLSessionConfiguration.background(withIdentifier: outboxAttachmentSession.sessionIdentifier)
            sessionConfiguration.useOlvidSettings(sharedContainerIdentifier: sharedContainerIdentifier)
            
            let log = self.log
            
            let urlSession = URLSession(configuration: sessionConfiguration, delegate: nil, delegateQueue: nil)
            urlSession.getAllTasks(completionHandler: { [weak self] (tasks) in
                obvContext.performAndWait {

                    for task in tasks {
                        guard let chunkNumber = task.getAssociatedChunkNumber() else { continue }
                        guard chunkNumber < outboxAttachment.chunks.count else { continue }
                        let ciphertextChunkLength = outboxAttachment.chunks[chunkNumber].ciphertextChunkLength
                        guard task.didSendFullChunk(ofLength: ciphertextChunkLength) else { continue }
                        outboxAttachment.chunkWasAchknowledged(chunkNumber: chunkNumber, by: originalAppType)
                        os_log("⛑ Chunk %{public}@/%{public}d was manually acknowledged", log: log, type: .info, outboxAttachment.attachmentId.debugDescription, chunkNumber)
                    }
                    
                    urlSession.invalidateAndCancel()
                    obvContext.delete(outboxAttachmentSession)
                    
                    do {
                        try obvContext.save(logOnFailure: log)
                    } catch {
                        self?.cancel(withReason: .couldNotSaveContext)
                    }

                    self?._isFinished = true
                }
            })
            
            
        }
    
    }
    
}


private extension URLSessionTask {
    
    func didSendFullChunk(ofLength length: Int) -> Bool {
        guard let httpURLResponse = self.response as? HTTPURLResponse else { return false }
        guard httpURLResponse.statusCode == 200 else { return false }
        guard self.countOfBytesSent == length else { return false }
        return true
    }
    
}
