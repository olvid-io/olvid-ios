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
import OlvidUtils
import os.log
import LinkPresentation


/// This operation is used by the share extension and leverages the operation that loads item providers. If one of them occurs to be an https URL, this operation fetches a "link preview" for it so that the share extension can cache it.
/// Eventually, when sending the message, we use the cache to add the "link preview" to the sent message if appropriate.
final class FetchAndCacheObvLinkMetadataForFirstURLInLoadedItemProvidersOperation: AsyncOperationWithSpecificReasonForCancel<FetchAndCacheObvLinkMetadataForFirstURLInLoadedItemProvidersOperation.ReasonForCancel> {
    
    private let loadedItemProviderProvider: LoadedItemProviderProvider
    private let currentURLsInCache: Set<URL>

    init(loadedItemProviderProvider: LoadedItemProviderProvider, currentURLsInCache: Set<URL>) {
        self.loadedItemProviderProvider = loadedItemProviderProvider
        self.currentURLsInCache = currentURLsInCache
        super.init()
    }
    
    private(set) var fetchedMetadata: (url: URL, linkMetadata: ObvLinkMetadata)?
    
    override func main() async {
        
        guard let loadedItemProviders = loadedItemProviderProvider.loadedItemProviders else {
            cancel(withReason: .noLoadedItemProviders)
            return finish()
        }

        let loadedHTTPSURL = loadedItemProviders
            .compactMap { loadItemProvider in
                switch loadItemProvider {
                case .url(content: let url):
                    return url
                case .text(content: let body):
                    guard let firstURLInBody = body.extractURLs().first else { return nil }
                    return firstURLInBody
                default:
                    return nil
                }
            }
            .filter {
                $0.scheme?.lowercased() == "https"
            }
            .first
        guard let loadedHTTPSURL else {
            return finish()
        }
        guard !currentURLsInCache.contains(loadedHTTPSURL) else {
            return finish()
        }
        let previewMetadataProvider = LPMetadataProvider()
        do {
            let linkMetadataFromProvider = try await previewMetadataProvider.startFetchingMetadata(for: loadedHTTPSURL)
            let linkMetadata = await ObvLinkMetadata.from(linkMetadata: linkMetadataFromProvider)
            fetchedMetadata = (loadedHTTPSURL, linkMetadata)
        } catch {
            return cancel(withReason: .failedToFetchMetadata(error: error))
        }

        return finish()
        
    }
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case noLoadedItemProviders
        case failedToFetchMetadata(error: Error)

        var logType: OSLogType {
            return .fault
        }
        
        var errorDescription: String? {
            switch self {
            case .noLoadedItemProviders: return "No loaded item provider in given operation"
            case .failedToFetchMetadata(error: let error): return "Failed to fetch metadata: \(error.localizedDescription)"
            }
        }
    }

}
