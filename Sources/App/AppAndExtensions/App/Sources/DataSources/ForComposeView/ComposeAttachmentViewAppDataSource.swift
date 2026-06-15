/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvEncoder

@MainActor
final class ComposeAttachmentViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    private var composeViewDataSourceFyleModelStreamManagerForStreamUUID = [UUID: ComposeViewDataSourceFyleModelStreamManager]()
    
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "ComposeAttachmentViewAppDataSource")
    
    private let cacheDelegate: DiscussionCacheDelegate
    
    init(viewContext: NSManagedObjectContext,
         backgroundContext: NSManagedObjectContext,
         cacheDelegate: DiscussionCacheDelegate) {
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
        self.cacheDelegate = cacheDelegate
    }
}

extension ComposeAttachmentViewAppDataSource: ComposeAttachmentViewDataSource {
    
    @MainActor
    func getInitialComposeViewDataSourceFyleModel(attachmentIdentifier: ObvComposition.ComposeAttachmentView.AttachmentIdentifier) -> ObvComposition.ComposeViewDataSourceFyleModel? {
        let persistedDraftFyleJoinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>
        switch attachmentIdentifier {
        case .persistedDraftFyleJoinObjectID(let objectID):
            persistedDraftFyleJoinObjectID = TypeSafeManagedObjectID<PersistedDraftFyleJoin>(objectID: objectID)
        }
        if let persistedDraftFyleJoin = try? PersistedDraftFyleJoin.get(withObjectID: persistedDraftFyleJoinObjectID, within: viewContext) {
            
            let contentTypeAndImage: ComposeViewDataSourceFyleModel.ContentTypeAndImage
            let linkMetadata: ObvLinkMetadata?
            let audioURL: URL?
            
            if persistedDraftFyleJoin.isPreviewType {
                linkMetadata = LinkMetadataManager.getLinkMetadata(for: persistedDraftFyleJoin)
                contentTypeAndImage = .init(contentType: .olvidLinkPreview, image: nil)
                audioURL = nil
            } else if persistedDraftFyleJoin.isAudioType {
                audioURL = AudioManager.getCachedAudioURL(for: persistedDraftFyleJoin)
                contentTypeAndImage = .init(contentType: .audio, image: AttachmentThumbnailManager.getCachedThumbnail(for: persistedDraftFyleJoin, cacheDelegate: cacheDelegate))
                linkMetadata = nil
            } else {
                contentTypeAndImage = .init(contentType: persistedDraftFyleJoin.contentType, image: AttachmentThumbnailManager.getCachedThumbnail(for: persistedDraftFyleJoin, cacheDelegate: cacheDelegate))
                linkMetadata = nil
                audioURL = nil
            }
            
            return ComposeViewDataSourceFyleModel(attachmentType: .init(type: persistedDraftFyleJoin.attachmentType),
                                                  contentTypeAndImage: contentTypeAndImage,
                                                  linkMetadata: linkMetadata,
                                                  audioURL: audioURL)
        }
        
        return nil
    }
    
    
    func getAsyncStreamOfComposeViewDataSourceFyleModel(attachmentIdentifier: ObvComposition.ComposeAttachmentView.AttachmentIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvComposition.ComposeViewDataSourceFyleModel>) {
        let persistedDraftFyleJoinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>
        switch attachmentIdentifier {
        case .persistedDraftFyleJoinObjectID(let objectID):
            persistedDraftFyleJoinObjectID = TypeSafeManagedObjectID<PersistedDraftFyleJoin>(objectID: objectID)
        }
        let manager = ComposeViewDataSourceFyleModelStreamManager(persistedDraftFyleJoinObjectID: persistedDraftFyleJoinObjectID,
                                                                  cacheDelegate: cacheDelegate,
                                                                  context: backgroundContext)
        composeViewDataSourceFyleModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    
    func finishAsyncStreamOfComposeViewDataSourceFyleModel(streamUUID: UUID) {
        guard let manager = composeViewDataSourceFyleModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }

}


extension ComposeAttachmentViewAppDataSource {
    
    enum ObvError: Error {
        case unexpectedIdentifier
    }
    
}


extension ComposeAttachmentViewAppDataSource {
    
    private final class ComposeViewDataSourceFyleModelStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<ComposeViewDataSourceFyleModel, PersistedDraftFyleJoin>, @unchecked Sendable {
        
        weak var cacheDelegate: DiscussionCacheDelegate?
        
        init(persistedDraftFyleJoinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>,
             cacheDelegate: DiscussionCacheDelegate?,
             context: NSManagedObjectContext) {
            self.cacheDelegate = cacheDelegate
            let frc = PersistedDraftFyleJoin.getFetchedResultsController(withObjectID: persistedDraftFyleJoinObjectID, within: context)
            
            super.init(frc: frc)
        }
        
        
        private var persistedDraftFyleJoin: PersistedDraftFyleJoin? {
            get throws {
                let frc = self.frc
                
                guard let fetchedObjects = frc.fetchedObjects else {
                    assertionFailure()
                    throw ObvError.couldNotFetchObjects
                }
                
                assert(fetchedObjects.count <= 1)
                
                guard let persistedDraftFyleJoin = fetchedObjects.first else {
                    return nil
                }
                
                return persistedDraftFyleJoin
            }
        }
        
        override func createModel(fetchedObjects: [PersistedDraftFyleJoin]) throws -> ComposeViewDataSourceFyleModel {
            
            if let persistedDraftFyleJoin = fetchedObjects.first {
                
                let draftFyleJoinObjectID = persistedDraftFyleJoin.typedObjectID
                let attachmentType = persistedDraftFyleJoin.attachmentType
                let contentType = persistedDraftFyleJoin.contentType

                if persistedDraftFyleJoin.isPreviewType { /// We fetched a preview, we want to generate link preview metadata

                    let linkMetadata = LinkMetadataManager.getLinkMetadata(for: persistedDraftFyleJoin)
                    let contentTypeAndImage = ComposeViewDataSourceFyleModel.ContentTypeAndImage(contentType: contentType, image: nil)
                    let model = ComposeViewDataSourceFyleModel(attachmentType: .init(type: attachmentType), contentTypeAndImage: contentTypeAndImage, linkMetadata: linkMetadata, audioURL: nil)
                    return model
                    
                } else { /// We fetched a default attachment, we want a thumbnail to be generated
                    
                    let image = AttachmentThumbnailManager.getCachedThumbnail(for: persistedDraftFyleJoin, cacheDelegate: cacheDelegate)
                    
                    if image == nil {
                        Task { [weak self] in
                            guard let self else { return }
                            if let imageGenerated = await AttachmentThumbnailManager.getThumbnail(draftFyleJoinObjectID: draftFyleJoinObjectID, cacheDelegate: cacheDelegate, within: frc.managedObjectContext) {
                                let contentTypeAndImage = ComposeViewDataSourceFyleModel.ContentTypeAndImage(contentType: contentType, image: imageGenerated)
                                let model = ComposeViewDataSourceFyleModel(attachmentType: .init(type: attachmentType), contentTypeAndImage: contentTypeAndImage, linkMetadata: nil, audioURL: AudioManager.getCachedAudioURL(for: persistedDraftFyleJoin))
                                self.yieldModelIfNeeded(model: model, within: frc.managedObjectContext)
                            }
                        }
                    }
                    
                    let audioURL: URL?
                    
                    if persistedDraftFyleJoin.isAudioType {
                        audioURL = AudioManager.getCachedAudioURL(for: persistedDraftFyleJoin)
                        if audioURL == nil {
                            Task { [weak self] in
                                guard let self else { return }
                                if let audioURLFetched = await AudioManager.getAudioURL(draftFyleJoinObjectID: draftFyleJoinObjectID, within: frc.managedObjectContext) {
                                    let contentTypeAndImage = ComposeViewDataSourceFyleModel.ContentTypeAndImage(contentType: contentType, image: image)
                                    let model = ComposeViewDataSourceFyleModel(attachmentType: .init(type: attachmentType), contentTypeAndImage: contentTypeAndImage, linkMetadata: nil, audioURL: audioURLFetched)
                                    self.yieldModelIfNeeded(model: model, within: frc.managedObjectContext)
                                }
                            }
                        }
                    } else {
                        audioURL = nil
                    }
                    
                    let contentTypeAndImage = ComposeViewDataSourceFyleModel.ContentTypeAndImage(contentType: contentType, image: image)
                    let model = ComposeViewDataSourceFyleModel(attachmentType: .init(type: attachmentType), contentTypeAndImage: contentTypeAndImage, linkMetadata: nil, audioURL: audioURL)
                    return model
                }
                
            } else {
                throw ObvError.couldNotCreateModel
            }
        }
        
        enum ObvError: Error {
            case couldNotFetchObjects
            case couldNotCreateModel
        }
        
    }
}

class AudioManager {
    
    /// Maps a draft fyle join onto a hard link URL, making it possible for the cell to compute a thumnail
    private static var hardlinkForDraftFyleObjectID = [TypeSafeManagedObjectID<PersistedDraftFyleJoin>: HardLinkToFyle]()

    public static func getCachedAudioURL(for persistedDraftFyleJoin: PersistedDraftFyleJoin) -> URL? {
        let draftFyleJoinObjectID = persistedDraftFyleJoin.typedObjectID
        
        if let hardlink = AudioManager.hardlinkForDraftFyleObjectID[draftFyleJoinObjectID], let hardlinkURL = hardlink.hardlinkURL, FileManager.default.fileExists(atPath: hardlinkURL.path) {
            return hardlinkURL
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
        
    public static func getAudioURL(draftFyleJoinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>, within context: NSManagedObjectContext, hardlinkToFyleRequested: Bool = false) async -> URL? {
        
        //  Hardlink has been requested, it is here and we can fetch the cached thumbnail
        if let hardlink = AudioManager.hardlinkForDraftFyleObjectID[draftFyleJoinObjectID], let hardlinkURL = hardlink.hardlinkURL, FileManager.default.fileExists(atPath: hardlinkURL.path) {
            return hardlinkURL
        } else if !hardlinkToFyleRequested { //  Hardlink missing, it is not already requested, so we make a request to get it
            AudioManager.hardlinkForDraftFyleObjectID.removeValue(forKey: draftFyleJoinObjectID)
            
            let fyleElement: FyleElement? = await context.perform {
                let draft = PersistedDraftFyleJoin.get(objectID: draftFyleJoinObjectID, within: context)
                return draft?.fyleElement ?? draft?.genericFyleElement
            }
            
            if let fyleElement,
                let hardlinkToFyle = try? await requestHardLinkToFyleForFyleElement(fyleElement) {
                AudioManager.hardlinkForDraftFyleObjectID[draftFyleJoinObjectID] = hardlinkToFyle
                return await getAudioURL(draftFyleJoinObjectID: draftFyleJoinObjectID, within: context, hardlinkToFyleRequested: true)
            }
        }
        
        // Hardlink missing, and we already ask to generate it, it may occurs because of an error
        return nil
    }
    
}

class LinkMetadataManager {
    
    public static func getLinkMetadata(for persistedDraftFyleJoin: PersistedDraftFyleJoin) -> ObvLinkMetadata? {
        guard let fallbackURL = URL(string: persistedDraftFyleJoin.fileName), let fyleURL = persistedDraftFyleJoin.fyle?.url else {
            return nil
        }
        
        if FileManager.default.fileExists(atPath: fyleURL.path),
           let data = try? Data(contentsOf: fyleURL),
           let obvEncoded = ObvEncoded(withRawData: data) {
            return ObvLinkMetadata.decode(obvEncoded, fallbackURL: fallbackURL)
        }
        
        return nil
    }
    
}

class AttachmentThumbnailManager {
    
    /// Maps a draft fyle join onto a hard link URL, making it possible for the cell to compute a thumnail
    private static var hardlinkForDraftFyleObjectID = [TypeSafeManagedObjectID<PersistedDraftFyleJoin>: HardLinkToFyle]()
    
    private static let thumbnailSize = CGSize(width: 80.0, height: 125.0)
    
    public static func getCachedThumbnail(for persistedDraftFyleJoin: PersistedDraftFyleJoin, cacheDelegate: DiscussionCacheDelegate?) -> UIImage? {
        let draftFyleJoinObjectID = persistedDraftFyleJoin.typedObjectID
        
        if let hardlink = AttachmentThumbnailManager.hardlinkForDraftFyleObjectID[draftFyleJoinObjectID], let hardlinkURL = hardlink.hardlinkURL, FileManager.default.fileExists(atPath: hardlinkURL.path) {
            if let thumbnail = cacheDelegate?.getCachedImageForHardlink(hardlink: hardlink, size: .full(minSize: AttachmentThumbnailManager.thumbnailSize)) {
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
        
    public static func getThumbnail(draftFyleJoinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>, cacheDelegate: DiscussionCacheDelegate?, within context: NSManagedObjectContext, hardlinkToFyleRequested: Bool = false) async -> UIImage? {
        
        //  Hardlink has been requested, it is here and we can fetch the cached thumbnail
        if let hardlink = AttachmentThumbnailManager.hardlinkForDraftFyleObjectID[draftFyleJoinObjectID], let hardlinkURL = hardlink.hardlinkURL, FileManager.default.fileExists(atPath: hardlinkURL.path) {
            if let thumbnail = cacheDelegate?.getCachedImageForHardlink(hardlink: hardlink, size: .full(minSize: AttachmentThumbnailManager.thumbnailSize)) {
                return thumbnail
            } else {
                return try? await cacheDelegate?.requestImageForHardlink(hardlink: hardlink, size: .full(minSize: AttachmentThumbnailManager.thumbnailSize))
            }
        } else if !hardlinkToFyleRequested { //  Hardlink missing, it is not already requested, so we make a request to get it
            AttachmentThumbnailManager.hardlinkForDraftFyleObjectID.removeValue(forKey: draftFyleJoinObjectID)
            
            let fyleElement: FyleElement? = await context.perform {
                let draft = PersistedDraftFyleJoin.get(objectID: draftFyleJoinObjectID, within: context)
                return draft?.fyleElement ?? draft?.genericFyleElement
            }
            
            if let fyleElement,
                let hardlinkToFyle = try? await requestHardLinkToFyleForFyleElement(fyleElement) {
                AttachmentThumbnailManager.hardlinkForDraftFyleObjectID[draftFyleJoinObjectID] = hardlinkToFyle
                return await getThumbnail(draftFyleJoinObjectID: draftFyleJoinObjectID, cacheDelegate: cacheDelegate, within: context, hardlinkToFyleRequested: true)
            }
        }
        
        // Hardlink missing, and we already ask to generate it, it may occurs because of an error
        return nil
    }
}


fileprivate extension ComposeViewDataSourceFyleModel.FyleMessageJoinType {
    
    init(type: PersistedDraftFyleJoin.FyleMessageJoinType) {
        switch type {
        case .photo: self = .photo
        case .video: self = .video
        case .audio: self = .audio
        case .other: self = .other
        }
    }
    
}
