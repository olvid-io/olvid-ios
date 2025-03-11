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
import ObvEncoder


/// Used in discussions cells for decoding and caching sent or received "link previews".
final class CachedObvLinkMetadataManager {
    
    static let shared = CachedObvLinkMetadataManager()

    private init() {}
    
    private var storedLinkMetadata = [URL: ObvLinkMetadata]()

    private var urlsForWhichDecodingOrCachingMetadataFailed = Set<URL>()
    
    private let helper = CachedLPMetadataProviderHelper()
    
    enum CachedMetadata {
        case metadataCached(preview: ObvLinkMetadata)
        case metadaNotCachedYet
        case failureOccuredWhenDecodingOrCachingMetadata
    }

    
    /// Must be called on the main thread
    func getCachedMetadata(for URL: URL) -> CachedMetadata {
        
        assert(Thread.isMainThread)
        
        if let storedPreview = storedLinkMetadata[URL] {
            return .metadataCached(preview: storedPreview)
        }

        if urlsForWhichDecodingOrCachingMetadataFailed.contains(URL) {
            return .failureOccuredWhenDecodingOrCachingMetadata
        }
        
        return .metadaNotCachedYet
        
    }
    
    
    @MainActor
    func decodeAndCacheMetadata(for URL: URL, fallbackURL: URL?) async throws {
        do {
            let linkMetadata = try await helper.decodeEncodedMetadata(for: URL, fallbackURL: fallbackURL)
            await MainActor.run {
                storedLinkMetadata[URL] = linkMetadata
            }
        } catch {
            await MainActor.run {
                _ = urlsForWhichDecodingOrCachingMetadataFailed.insert(URL)
            }
            throw error
        }
    }
    
    
    @MainActor
    func clearCache() async {
        urlsForWhichDecodingOrCachingMetadataFailed.removeAll()
    }
    
}


// MARK: - CachedLPMetadataProviderHelper

private actor CachedLPMetadataProviderHelper {
    
    private var cachedPreviewForFyleURL = [URL: ObvLinkMetadata]()
    private var fyleURLsForWhichDecodingFailed = Set<URL>()

    
    func decodeEncodedMetadata(for fyleURL: URL, fallbackURL: URL?) throws -> ObvLinkMetadata {
        if let preview = cachedPreviewForFyleURL[fyleURL] {
            return preview
        }
        guard !fyleURLsForWhichDecodingFailed.contains(fyleURL) else {
            throw ObvError.decodingFailed(fyleURL: fyleURL)
        }
        guard FileManager.default.fileExists(atPath: fyleURL.path),
              let data = try? Data(contentsOf: fyleURL),
              let obvEncoded = ObvEncoded(withRawData: data),
              let preview = ObvLinkMetadata.decode(obvEncoded, fallbackURL: fallbackURL) else {
            throw ObvError.decodingFailed(fyleURL: fyleURL)
        }
        cachedPreviewForFyleURL[fyleURL] = preview
        return preview
    }
    
    
    func clearCache() {
        cachedPreviewForFyleURL.removeAll()
        fyleURLsForWhichDecodingFailed.removeAll()
    }

    enum ObvError: Error {
        case decodingFailed(fyleURL: URL)
    }
    
}
