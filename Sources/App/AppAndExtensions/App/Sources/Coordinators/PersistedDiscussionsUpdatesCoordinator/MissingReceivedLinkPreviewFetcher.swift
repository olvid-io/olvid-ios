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
import ObvUICoreData
import ObvSettings
import ObvCrypto
import LinkPresentation
import UniformTypeIdentifiers
import CoreData
import ObvAppCoreConstants

protocol MissingReceivedLinkPreviewFetcherDelegate {
    func fetchMissingPreviewIfNeeded(with objectID: TypeSafeManagedObjectID<PersistedMessageReceived>, cacheDelegate: DiscussionCacheDelegate?) async throws
}


/// This actor is in charge of fetching and caching link previews metada for received messages.
///
/// When an (https) link is detected in a received message and no link preview metada is provided, ``fetchMissingPreviewIfNeeded(with:cacheDelegate:)`` is called. If no error occurs, an instance of ``ReceivedFyleMessageJoinWithStatus`` is created in the view context (and thus, automatically shown in the discussion's cell displaying the received message)
actor MissingReceivedLinkPreviewFetcher: MissingReceivedLinkPreviewFetcherDelegate {
    
    private static let logCategory = "MissingPreviewFetcherCoordinator"
    private static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: logCategory)
    
    private var cache = [TypeSafeManagedObjectID<PersistedMessageReceived>: MissingPreviewFetcherTask]()
    
    private let Sha256 = ObvCryptoSuite.sharedInstance.hashFunctionSha256()
    
    private enum MissingPreviewFetcherTask {
        case inProgress(Task<Void, Error>)
        case finished
    }
    
    
    func fetchMissingPreviewIfNeeded(with objectID: TypeSafeManagedObjectID<PersistedMessageReceived>, cacheDelegate: DiscussionCacheDelegate?) async throws {
        
        // We check that the user's settings specify that she allows preview to be created.
        guard ObvMessengerSettings.Discussions.fetchMissingLinkPreviewFromMessageReceived else { return }

        // If a request has already been made, we wait for the end of it
        if let cached = cache[objectID] {
            os_log("[MissingPreviewFetcherCoordinator] fetching preview has already been requested for %{public}@", log: Self.log, type: .info, objectID.objectID)
            switch cached {
            case .finished:
                break
            case .inProgress(let task):
                try await task.value
            }
            return
        }
        
        // If we reach this point, it means no request for missing preview has been made for this particular message.
        let task = createTaskForFetchingPreview(with: objectID, cacheDelegate: cacheDelegate)
        
        cache[objectID] = .inProgress(task)
        
        do {
            try await task.value
            cache[objectID] = .finished
            return
        } catch {
            cache.removeValue(forKey: objectID)
            throw error
        }
    }
    
    
    private func createTaskForFetchingPreview(with objectID: TypeSafeManagedObjectID<PersistedMessageReceived>, cacheDelegate: DiscussionCacheDelegate?) -> Task<Void, Error> {
        
        return Task {
            
            guard let link = await getLinkFromMessage(with: objectID, cacheDelegate: cacheDelegate) else { return }
            
            guard let fileNameForArchiving = link.toFileNameForArchiving() else { return }
            
            let fyleURL = ObvUICoreDataConstants.ContainerURL.forPreviews.appendingPathComponent(fileNameForArchiving)
            
            var previewAttached: Bool = false
            
            if !FileManager.default.fileExists(atPath: fyleURL.path) {
                os_log("[MissingPreviewFetcherCoordinator] Fyle does not exist for %{public}@", log: MissingReceivedLinkPreviewFetcher.log, type: .info, objectID.objectID)
                
                let previewMetadataProvider = LPMetadataProvider()
                let linkMetadataFromProvider = try await previewMetadataProvider.startFetchingMetadata(for: link)
                let linkMetadata = await ObvLinkMetadata.from(linkMetadata: linkMetadataFromProvider)
                
                os_log("[MissingPreviewFetcherCoordinator] Metadatas have been fetched for: %{public}@ from %{public}@", log: MissingReceivedLinkPreviewFetcher.log, type: .info, link.absoluteString, objectID.debugDescription)
                
                // Save metadata to file and get pieces of information to use afterwise
                try await saveMetadataToFile(from: linkMetadata, saveTo: fyleURL)
            }
            
            previewAttached = await createReceivedFyleJoinWithStatus(fromURL: fyleURL, filename: link.absoluteString, linkTo: objectID) != nil
            
            if previewAttached {
                os_log("[MissingPreviewFetcherCoordinator] Preview has been attached for: %{public}@ to %{public}@", log: MissingReceivedLinkPreviewFetcher.log, type: .info, link.absoluteString, objectID.debugDescription)
            } else {
                os_log("[MissingPreviewFetcherCoordinator] Preview has not been attached for: %{public}@ to %{public}@", log: MissingReceivedLinkPreviewFetcher.log, type: .info, link.absoluteString, objectID.debugDescription)
            }
            
        }
    }
    
    
    @MainActor
    private func getLinkFromMessage(with objectID: TypeSafeManagedObjectID<PersistedMessageReceived>, cacheDelegate: DiscussionCacheDelegate?) async -> URL? {
        
        guard let message = try? PersistedMessageReceived.get(with: objectID, within: ObvStack.shared.viewContext),
              message.fyleMessageJoinWithStatus?.filter({ $0.isPreviewType }).first == nil, // we only try to generate a preview if none exists.
              let text = message.textBody,
              let link = cacheDelegate?.getFirstHttpsURL(text: text) else {
            return nil
        }
        
        return link
    }
    
    
    private func saveMetadataToFile(from metadata: ObvLinkMetadata, saveTo fyleURL: URL) async throws {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let data: Data = try metadata.obvEncode().rawData
                try data.write(to: fyleURL)
                continuation.resume(returning: ())
            } catch {
                continuation.resume(throwing: error)
                return
            }
        }
        
    }
    
    @MainActor
    private func createReceivedFyleJoinWithStatus(fromURL fyleURL: URL, filename: String, linkTo objectID: TypeSafeManagedObjectID<PersistedMessageReceived>) -> ReceivedFyleMessageJoinWithStatus? {
        
        // Compute the sha256 of the file
        let sha256: Data
        do {
            sha256 = try Sha256.hash(fileAtUrl: fyleURL)
        } catch {
            os_log("[MissingPreviewFetcherCoordinator] Failed to generate sha256 of the file for %{public}@: %{public}@", log: MissingReceivedLinkPreviewFetcher.log, type: .info,  objectID.debugDescription, error.localizedDescription)
            return nil
        }

        do {
            // create ReceivedFyleMessageJoinWithStatus and add it automatically to the received message.
            let messageFyleJoinWithStatus = try ReceivedFyleMessageJoinWithStatus(forPreviewWithSha256: sha256,
                                                                                  fromURL: fyleURL,
                                                                                  filename: filename,
                                                                                  uti: UTType.olvidPreviewUti,
                                                                                  messageObjectID: objectID,
                                                                                  within: ObvStack.shared.viewContext)
            os_log("[MissingPreviewFetcherCoordinator] messageFyleJoinWithStatus created for %{public}@", log: MissingReceivedLinkPreviewFetcher.log, type: .info, objectID.debugDescription)
            return messageFyleJoinWithStatus
        } catch {
            os_log("[MissingPreviewFetcherCoordinator] Failed to generate messageFyleJoinWithStatus for %{public}@: %{public}@", log: MissingReceivedLinkPreviewFetcher.log, type: .info, objectID.debugDescription, error.localizedDescription)
            assertionFailure()
            return nil
        }
    }
}


extension MissingReceivedLinkPreviewFetcher {
    
    static func removeCachedPreviewFilesGenerated(olderThan dateLimit: Date) {
        let previewDir = ObvUICoreDataConstants.ContainerURL.forPreviews.url
        
        guard FileManager.default.fileExists(atPath: previewDir.path) else { return }
        let includingPropertiesForKeys = [
            URLResourceKey.creationDateKey,
            URLResourceKey.isWritableKey,
            URLResourceKey.isRegularFileKey,
        ]
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(at: previewDir, includingPropertiesForKeys: includingPropertiesForKeys, options: .skipsHiddenFiles) else { return }
        for fileURL in fileURLs {
            guard fileURL.isArchive else { return }
            guard let attributes = try? fileURL.resourceValues(forKeys: Set(includingPropertiesForKeys)) else { continue }
            guard attributes.isWritable == true else { return }
            guard attributes.isRegularFile == true else { return }
            guard let creationDate = attributes.creationDate, creationDate < dateLimit else { return }
            // If we reach this point, we should delete the archive
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
    
}
