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
import LinkPresentation


/// This shall replace most of what is done in the extension of LPMetadataProviderUtils
@available(iOS 13.0, *)
final class CachedLPMetadataProvider {
    
    static let shared = CachedLPMetadataProvider()

    private init() {}
    
    private static func makeError(message: String) -> Error { NSError(domain: "CachedLPMetadataProvider", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { CachedLPMetadataProvider.makeError(message: message) }
    
    private static var log: OSLog {
        return OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))
    }

    private var completionsForURL = [URL: [(LPLinkMetadata?, Error?) -> Void]]()
    
    func getCachedOrStartFetchingMetadata(for URL: URL, cacheHit: (LPLinkMetadata) -> Void, completionHandler: @escaping (LPLinkMetadata?, Error?) -> Void) {
        
        assert(Thread.isMainThread)
        
        do {
            if let cachedLinkMetada = try LPMetadataProvider.getCachedLinkMetada(for: URL) {
                cacheHit(cachedLinkMetada)
                return
            }
        } catch let error {
            os_log("Could not get cached link metadata: %{public}@", log: CachedLPMetadataProvider.log, type: .error, error.localizedDescription)
        }
        
        // Make sure that the scheme is https
        guard URL.scheme?.lowercased() == "https" else {
            let error = makeError(message: "Unexpected scheme: \(String(describing: URL.scheme)). Expecting https.")
            completionHandler(nil, error)
            return
        }
        
        if var completions = completionsForURL[URL] {
            // The URL was already requested, so we only store the completion handler
            completions.append(completionHandler)
            completionsForURL[URL] = completions
            return
        }
        
        // If we reach this point, the URL has not been request yet. So we request it now.
        
        completionsForURL[URL] = [completionHandler]
        
        let provider = LPMetadataProvider()
        provider.startFetchingMetadata(for: URL) { (metadata, error) in
            assert(!Thread.isMainThread)
            if error == nil && metadata != nil {
                do {
                    try LPMetadataProvider.storeLinkMetada(metadata!, for: URL)
                } catch let error {
                    os_log("Could not store link metadata: %{public}@", log: CachedLPMetadataProvider.log, type: .error, error.localizedDescription)
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let _self = self else { return }
                guard let completions = _self.completionsForURL.removeValue(forKey: URL) else { assertionFailure(); return }
                for completion in completions {
                    completion(metadata, error)
                }
            }
        }
        
    }
    
}
