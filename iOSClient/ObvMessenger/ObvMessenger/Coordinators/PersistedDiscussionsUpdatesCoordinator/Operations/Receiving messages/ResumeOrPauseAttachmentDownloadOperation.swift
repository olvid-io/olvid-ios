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
import CoreData
import OlvidUtils
import ObvEngine


/// This operation gets executed when the user decides to resume or to pause the download of a received attachment.
/// It does not modify the app database but, instead, requests a resume or a pause of the download to the engine.
final class ResumeOrPauseAttachmentDownloadOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: ResumeOrPauseAttachmentDownloadOperation.self))

    private let receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>
    private let resumeOrPause: ResumeOrPause
    private let obvEngine: ObvEngine

    enum ResumeOrPause {
        case resume
        case pause
    }
    
    init(receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>, resumeOrPause: ResumeOrPause, obvEngine: ObvEngine) {
        self.receivedJoinObjectID = receivedJoinObjectID
        self.resumeOrPause = resumeOrPause
        self.obvEngine = obvEngine
        super.init()
    }

    override func main() {

        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

        obvContext.performAndWait {
            do {
                
                guard let attachment = try? ReceivedFyleMessageJoinWithStatus.getReceivedFyleMessageJoinWithStatus(objectID: receivedJoinObjectID.objectID, within: obvContext.context) else { return }
                
                switch attachment.status {
                case .downloading:
                    guard resumeOrPause == .pause else { return }
                case .downloadable:
                    guard resumeOrPause == .resume else { return }
                case .complete, .cancelledByServer:
                    return
                }
                
                guard let ownedCryptoId = attachment.message?.discussion.ownedIdentity?.cryptoId else { return }
                let messageId = attachment.messageIdentifierFromEngine
                
                switch resumeOrPause {
                case .resume:
                    try obvEngine.resumeDownloadOfAttachment(attachment.index, ofMessageWithIdentifier: messageId, ownedCryptoId: ownedCryptoId)
                case .pause:
                    try obvEngine.pauseDownloadOfAttachment(attachment.index, ofMessageWithIdentifier: messageId, ownedCryptoId: ownedCryptoId)
                }
                
                
            } catch(let error) {
                assertionFailure()
                return cancel(withReason: .coreDataError(error: error))
            }
        }

    }
}