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
import os.log
import CoreData
import OlvidUtils
import ObvEngine
import ObvUICoreData
import ObvAppCoreConstants


/// This operation gets executed when the user decides to resume or to pause the download of an attachment sent from another owned device.
/// It does not modify the app database but, instead, requests a resume or a pause of the download to the engine.
final class ResumeOrPauseOwnedAttachmentDownloadOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {

    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: ResumeOrPauseAttachmentDownloadOperation.self))

    private let sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>
    private let resumeOrPause: ResumeOrPause
    private let obvEngine: ObvEngine

    enum ResumeOrPause {
        case resume
        case pause
    }
    
    init(sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>, resumeOrPause: ResumeOrPause, obvEngine: ObvEngine) {
        self.sentJoinObjectID = sentJoinObjectID
        self.resumeOrPause = resumeOrPause
        self.obvEngine = obvEngine
        super.init()
    }

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        guard let attachment = try? SentFyleMessageJoinWithStatus.getSentFyleMessageJoinWithStatus(objectID: sentJoinObjectID.objectID, within: obvContext.context) else { return }
        guard let messageId = attachment.messageIdentifierFromEngine else {
            assertionFailure("The messageIdentifierFromEngine for messages sent from another owned device should always be non-nil. It is always nil for messages sent from the current device (for which no resume/pause download makes sense")
            return
        }
        
        switch attachment.status {
        case .downloading:
            guard resumeOrPause == .pause else { return }
        case .downloadable:
            guard resumeOrPause == .resume else { return }
        case .complete, .cancelledByServer:
            return
        case .uploadable:
            assertionFailure("This should never happen for an attachment sent from another owned device")
            return
        case .uploading:
            assertionFailure("This should never happen for an attachment sent from another owned device")
            return
        }
        
        guard let ownedCryptoId = attachment.message?.discussion?.ownedIdentity?.cryptoId else { return }
        
        let attachmentIndex = attachment.index        
        Task {
            do {
                switch resumeOrPause {
                case .resume:
                    try await obvEngine.resumeDownloadOfAttachment(attachmentIndex, ofMessageWithIdentifier: messageId, ownedCryptoId: ownedCryptoId)
                case .pause:
                    try await obvEngine.pauseDownloadOfAttachment(attachmentIndex, ofMessageWithIdentifier: messageId, ownedCryptoId: ownedCryptoId)
                }
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
        
    }
}
