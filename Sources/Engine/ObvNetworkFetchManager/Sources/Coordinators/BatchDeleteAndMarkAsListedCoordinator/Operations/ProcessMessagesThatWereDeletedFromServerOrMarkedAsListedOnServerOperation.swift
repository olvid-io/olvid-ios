/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import CoreData
import OSLog
import ObvTypes
import OlvidUtils
import ObvServerInterface
import ObvCrypto


final class ProcessMessagesThatWereDeletedFromServerOrMarkedAsListedOnServerOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private static let logger = Logger(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: "ProcessMessagesThatWereDeletedFromServerOrMarkedAsListedOnServerOperation")

    private let ownedCryptoIdentity: ObvCryptoIdentity
    private let messageUIDsAndCategories: [ObvServerDeleteMessageAndAttachmentsMethod.MessageUIDAndCategory]
    private let inbox: URL

    init(ownedCryptoIdentity: ObvCryptoIdentity, messageUIDsAndCategories: [ObvServerDeleteMessageAndAttachmentsMethod.MessageUIDAndCategory], inbox: URL) {
        self.ownedCryptoIdentity = ownedCryptoIdentity
        self.messageUIDsAndCategories = messageUIDsAndCategories
        self.inbox = inbox
        super.init()
    }
    
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        for messageUIDAndCategory in messageUIDsAndCategories {
            let messageId = ObvMessageIdentifier(ownedCryptoIdentity: ownedCryptoIdentity, uid: messageUIDAndCategory.messageUID)
            let category = messageUIDAndCategory.category
            switch category {
            case .requestDeletion:
                do {
                    // The row decides whether it goes or merely records the confirmation — never this request, which may have been built while the message was
                    // in the other state. All three outcomes are reported, and unconditionally: the row being kept is the ordinary result of an early deletion
                    // and the row being absent is not, and until this returned an outcome rather than an optional URL the two were indistinguishable — from
                    // each other, and from a case that never arose.
                    let outcome = try InboxMessage.processServerConfirmationOfDeletion(messageId: messageId, inbox: inbox, within: obvContext.context)

                    switch outcome {

                    case .rowKeptAndMarkedAsDeletedFromServer:

                        Self.logger.info("🎉 [\(messageId.debugDescription, privacy: .public)] The server confirmed the deletion. The app is not done with this message, so its row survives and now records that the server no longer holds it")

                    case .noRowFound:

                        Self.logger.info("🎉 [\(messageId.debugDescription, privacy: .public)] The server confirmed the deletion, but no row carries this identifier any more. Nothing left to do")

                    case .rowDeleted(let attachmentsDirectory):

                        Self.logger.info("🎉 [\(messageId.debugDescription, privacy: .public)] The server confirmed the deletion and the app is done with this message, so its row is gone")

                        if let attachmentsDirectory {
                            Self.logger.info("📁 [\(messageId.debugDescription, privacy: .public)] The message was deleted from the server, so its whole attachments directory \(attachmentsDirectory.path, privacy: .public) will be removed when this context saves")
                            try obvContext.addContextDidSaveCompletionHandler { error in
                                // Reported in every branch. A removal that never happened and one that happened and took a download's bytes with it are
                                // indistinguishable from silence, and this is one of the few places that can remove a whole message directory.
                                guard error == nil else {
                                    Self.logger.info("📁 [\(messageId.debugDescription, privacy: .public)] Not removing \(attachmentsDirectory.path, privacy: .public): the context failed to save")
                                    return
                                }
                                guard FileManager.default.fileExists(atPath: attachmentsDirectory.path) else {
                                    Self.logger.info("📁 [\(messageId.debugDescription, privacy: .public)] Not removing \(attachmentsDirectory.path, privacy: .public): there is nothing there any more")
                                    return
                                }
                                do {
                                    try FileManager.default.removeItem(at: attachmentsDirectory)
                                    Self.logger.info("📁 [\(messageId.debugDescription, privacy: .public)] Removed the attachments directory \(attachmentsDirectory.path, privacy: .public), and every attachment file in it")
                                } catch {
                                    Self.logger.error("📁 [\(messageId.debugDescription, privacy: .public)] Could not remove the attachments directory \(attachmentsDirectory.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                                }
                            }
                        }

                    }

                } catch {
                    assertionFailure()
                    // In production, continue anyway
                }
            case .markAsListed:
                do {
                    try InboxMessage.markAsListedOnServer(messageId: messageId, within: obvContext.context)
                } catch {
                    assertionFailure()
                    // In production, continue anyway
                }
            }
        }
    }
    
}
