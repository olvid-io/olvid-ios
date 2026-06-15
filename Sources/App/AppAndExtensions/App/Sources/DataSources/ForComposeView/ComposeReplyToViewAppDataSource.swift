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
import ObvComposition
import CoreData
import OSLog
import ObvUICoreData
import ObvAppTypes
import ObvAppCoreConstants
import OlvidUtils

@MainActor
final class ComposeReplyToViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    private let cacheDelegate: DiscussionCacheDelegate
    
    private var composeViewDataSourceReplyModelStreamManagerForStreamUUID = [UUID: ComposeViewDataSourceReplyToModelStreamManager]()
    
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "ComposeReplyToViewAppDataSource")
    
    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext, cacheDelegate: DiscussionCacheDelegate) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
        self.cacheDelegate = cacheDelegate
    }
}

extension ComposeReplyToViewAppDataSource: ComposeReplyToViewDataSource {
    
    @MainActor
    func getInitialComposeViewDataSourceReplyToModel(messageIdentifier: ObvAppTypes.ObvMessageAppIdentifier) -> ComposeViewDataSourceReplyToModel? {
        
        if let persistedMessage = try? PersistedMessage.getMessage(messageAppIdentifier: messageIdentifier, within: viewContext) {
            
            let readingRequiresUserAction = (persistedMessage as? PersistedMessageReceived)?.readingRequiresUserAction ?? false
            
            var image: UIImage? = nil
            
            if let fyleMessageJoinWithStatus = persistedMessage.fyleMessageJoinWithStatus, !readingRequiresUserAction {
                for join in fyleMessageJoinWithStatus {
                    if let cacheImage = ReplyToThumbnailManager.getCachedThumbnail(for: join, cacheDelegate: cacheDelegate) {
                        image = cacheImage
                        break
                    }
                }
            }
            
            return ComposeViewDataSourceReplyToModel(persistedMessage: persistedMessage, image: image)
        }
        
        return nil
        
    }
    
    
    func getAsyncStreamOfComposeViewDataSourceReplyToModel(_ view: ComposeReplyToView, messageIdentifier: ObvAppTypes.ObvMessageAppIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ComposeViewDataSourceReplyToModel>) {

        let viewContext = self.viewContext
        let persistedMessageObjectID: TypeSafeManagedObjectID<PersistedMessage> = try await viewContext.perform {
            guard let message = try PersistedMessage.getMessage(messageAppIdentifier: messageIdentifier, within: viewContext) else {
                assertionFailure()
                throw ObvError.couldNotFindMessage
            }
            return message.typedObjectID
        }
        let manager = ComposeViewDataSourceReplyToModelStreamManager(persistedMessageObjectID: persistedMessageObjectID,
                                                                     cacheDelegate: cacheDelegate,
                                                                     context: backgroundContext)
        composeViewDataSourceReplyModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    
    func finishAsyncStreamOfComposeViewDataSourceReplyToModel(_ view: ComposeReplyToView, streamUUID: UUID) {
        guard let manager = composeViewDataSourceReplyModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
    enum ObvError: Error {
        case couldNotFindMessage
    }
    
}

extension ComposeReplyToViewAppDataSource {
    
    private final class ComposeViewDataSourceReplyToModelStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<ComposeViewDataSourceReplyToModel, PersistedMessage>, @unchecked Sendable {
        
        weak var cacheDelegate: DiscussionCacheDelegate?
        
        init(persistedMessageObjectID: TypeSafeManagedObjectID<PersistedMessage>,
             cacheDelegate: DiscussionCacheDelegate?,
             context: NSManagedObjectContext) {
            
            self.cacheDelegate = cacheDelegate
            
            let frc = PersistedMessage.getFetchedResultsController(objectID: persistedMessageObjectID, within: context)
            
            super.init(frc: frc)
        }
        
        
        override func createModel(fetchedObjects: [PersistedMessage]) throws -> ComposeViewDataSourceReplyToModel {
            guard let persistedMessage = fetchedObjects.first else {
                throw ObvError.couldNotCreateModel
            }
            
            var image: UIImage? = nil
            
            let readingRequiresUserAction = (persistedMessage as? PersistedMessageReceived)?.readingRequiresUserAction ?? false
            
            if let fyleMessageJoinWithStatus = persistedMessage.fyleMessageJoinWithStatus, !readingRequiresUserAction {
                
                for join in fyleMessageJoinWithStatus {
                    if let cacheImage = ReplyToThumbnailManager.getCachedThumbnail(for: join, cacheDelegate: cacheDelegate) {
                        image = cacheImage
                        break
                    }
                }
                
                if image == nil, let join = fyleMessageJoinWithStatus.first(where: { $0.fullFileIsAvailable }) ?? fyleMessageJoinWithStatus.first { /// No thumbnail cached found, we generate one

                    let messageObjectID = persistedMessage.objectID
                    let joinObjectID = join.objectID
                    
                    Task { [weak self, joinObjectID, messageObjectID] in
                        guard let self else { return }
                        
                        // Recreate join model on the background context
                        guard let join = await self.frc.managedObjectContext.perform({
                            let context = self.frc.managedObjectContext
                            
                            return try? FyleMessageJoinWithStatus.get(objectID: joinObjectID, within: context)
                            
                        }) else { return }
                        
                        let imageGenerated = await ReplyToThumbnailManager.getThumbnail(for: join, cacheDelegate: self.cacheDelegate)
                        guard let imageGenerated else { return }
                        
                        // Recreate the model on the background context using a fresh fetch to avoid capturing non-Sendable objects
                        await self.frc.managedObjectContext.perform {

                            let context = self.frc.managedObjectContext
                            
                            if let message = try? PersistedMessage.get(with: messageObjectID, within: context) {
                                let model = ComposeViewDataSourceReplyToModel(persistedMessage: message, image: imageGenerated)
                                self.yieldModelIfNeeded(model: model, within: self.frc.managedObjectContext)
                            }
                            
                        }
                    }
                }
            }
            
            return ComposeViewDataSourceReplyToModel(persistedMessage: persistedMessage, image: image)
        }
        
        enum ObvError: Error {
            case couldNotFetchObjects
            case couldNotCreateModel
        }
        
    }
}

extension ComposeViewDataSourceReplyToModel {
    
    init(persistedMessage: PersistedMessage, image: UIImage?) {
        var title: String = ""
        var body: String?
        var textColor: UIColor
        
        if let messageReceived = persistedMessage as? PersistedMessageReceived {
            if let contact = messageReceived.contactIdentity {
                textColor = contact.cryptoId.colors.text
                title = MessageCellStrings.replyingTo(contact.customOrFullDisplayName)
            } else {
                textColor = .label
                title = NewSingleDiscussionViewController.Strings.replying
            }
        } else if persistedMessage is PersistedMessageSent {
            textColor = .label
            title = NewSingleDiscussionViewController.Strings.replyingToYourself
        } else {
            textColor = .label
            title = NewSingleDiscussionViewController.Strings.replying
        }
        
        body = persistedMessage.textBody
        
        var attachmentLeft = 0
        if let joins = persistedMessage.fyleMessageJoinWithStatus, image != nil, joins.count > 1 {
            attachmentLeft = joins.count - 1
        }
        self.init(title: title,
                  body: body,
                  image: image,
                  attachmentLeft: attachmentLeft,
                  textColor: textColor)
    }
}

class ReplyToThumbnailManager {
    
    /// Maps a draft fyle join onto a hard link URL, making it possible for the cell to compute a thumbnail
    private static var hardlinkForFyleMessageJoinWithStatus = [TypeSafeManagedObjectID<FyleMessageJoinWithStatus>: HardLinkToFyle]()
    
    private static let thumbnailSize = CGSize(width: 50.0, height: 50.0)
    
    public static func getCachedThumbnail(for fyleMessageJoinWithStatus: FyleMessageJoinWithStatus, cacheDelegate: DiscussionCacheDelegate?) -> UIImage? {
        let fyleJoinObjectID = fyleMessageJoinWithStatus.typedObjectID
        
        if let hardlink = ReplyToThumbnailManager.hardlinkForFyleMessageJoinWithStatus[fyleJoinObjectID], let hardlinkURL = hardlink.hardlinkURL, FileManager.default.fileExists(atPath: hardlinkURL.path) {
            if let thumbnail = cacheDelegate?.getCachedImageForHardlink(hardlink: hardlink, size: .full(minSize: ReplyToThumbnailManager.thumbnailSize)) {
                return thumbnail
            }
        }
        
        return nil
    }

    public static func requestHardLinkToFyleForFyleElement(_ fyleElement: FyleElement) async throws -> HardLinkToFyle {
        return try await withCheckedThrowingContinuation { continuation in
            HardLinksToFylesNotifications.requestHardLinkToFyle(fyleElement: fyleElement) { result in
                switch result {
                case .success(let hardlink):
                    continuation.resume(returning: hardlink)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }.postOnDispatchQueue()
        }
    }
        
    public static func getThumbnail(for fyleMessageJoinWithStatus: FyleMessageJoinWithStatus, cacheDelegate: DiscussionCacheDelegate?, hardlinkToFyleRequested: Bool = false) async -> UIImage? {
        
        let fyleJoinObjectID = fyleMessageJoinWithStatus.typedObjectID
        
        //  Hardlink has been requested, it is here and we can fetch the cached thumbnail
        if let hardlink = ReplyToThumbnailManager.hardlinkForFyleMessageJoinWithStatus[fyleJoinObjectID], let hardlinkURL = hardlink.hardlinkURL, FileManager.default.fileExists(atPath: hardlinkURL.path) {
            if let thumbnail = cacheDelegate?.getCachedImageForHardlink(hardlink: hardlink, size: .full(minSize: ReplyToThumbnailManager.thumbnailSize)) {
                return thumbnail
            } else {
                return try? await cacheDelegate?.requestImageForHardlink(hardlink: hardlink, size: .full(minSize: ReplyToThumbnailManager.thumbnailSize))
            }
        } else if !hardlinkToFyleRequested { //  Hardlink missing, it is not already requested, so we make a request to get it
            ReplyToThumbnailManager.hardlinkForFyleMessageJoinWithStatus.removeValue(forKey: fyleJoinObjectID)
            
            // Retrieve the fyleElement in the proper Core Data context
            guard let context = fyleMessageJoinWithStatus.managedObjectContext else {
                return nil
            }
            
            // Capture only the Sendable objectID, not the entire non-Sendable managed object
            let joinObjectID = fyleMessageJoinWithStatus.objectID
            
            let fyleElement: FyleElement? = await context.perform {
                guard let join = try? FyleMessageJoinWithStatus.get(objectID: joinObjectID, within: context) else {
                    return nil
                }
                return join.fyleElement ?? join.genericFyleElement
            }
            
            if let fyleElement,
                let hardlinkToFyle = try? await requestHardLinkToFyleForFyleElement(fyleElement) {
                ReplyToThumbnailManager.hardlinkForFyleMessageJoinWithStatus[fyleJoinObjectID] = hardlinkToFyle
                return await getThumbnail(for: fyleMessageJoinWithStatus, cacheDelegate: cacheDelegate, hardlinkToFyleRequested: true)
            }
        }
        
        // Hardlink missing, and we already asked to generate it, it may occur because of an error
        return nil
    }
}

