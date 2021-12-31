/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

import LinkPresentation
import CryptoKit
import os.log

@available(iOS 13.0, *)
extension LPMetadataProvider {
    
    private static let errorDomain = "LPMetadataProvider"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    private static var tempDir: URL {
        return ObvMessengerConstants.containerURL.forCache.appendingPathComponent("ArchivedLPMetadata")
    }
    
    private static var log: OSLog {
        return OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))
    }
    
    func getCachedOrStartFetchingMetadata(for URL: URL, cacheHit: (LPLinkMetadata?) -> Void, completionHandler: @escaping (LPLinkMetadata?, Error?) -> Void) {
        
        do {
            if let cachedLinkMetada = try LPMetadataProvider.getCachedLinkMetada(for: URL) {
                cacheHit(cachedLinkMetada)
                return
            }
        } catch let error {
            os_log("Could not get cached link metadata: %{public}@", log: LPMetadataProvider.log, type: .error, error.localizedDescription)
        }
        
        // Make sure that the scheme is https
        guard URL.scheme?.lowercased() == "https" else {
            let error = LPMetadataProvider.makeError(message: "Unexpected scheme: \(String(describing: URL.scheme)). Expecting https.")
            completionHandler(nil, error)
            return
        }
        
        startFetchingMetadata(for: URL) { (metadata, error) in
            if error == nil && metadata != nil {
                do {
                    try LPMetadataProvider.storeLinkMetada(metadata!, for: URL)
                } catch let error {
                    os_log("Could not store link metadata: %{public}@", log: LPMetadataProvider.log, type: .error, error.localizedDescription)
                }
            }
            completionHandler(metadata, error)
        }
        
        
    }

    
    static func getCachedLinkMetada(for url: URL) throws -> LPLinkMetadata? {
        guard let fileNameForArchiving = url.toFileNameForArchiving() else { return nil }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        let filePath = tempDir.appendingPathComponent(fileNameForArchiving)
        guard FileManager.default.fileExists(atPath: filePath.path) else { return nil }
        do {
            let archivedData = try Data(contentsOf: filePath)
            let archiver = try NSKeyedUnarchiver(forReadingFrom: archivedData)
            archiver.requiresSecureCoding = true
            let metadata = LPLinkMetadata(coder: archiver)
            if metadata == nil {
                try FileManager.default.removeItem(at: filePath)
            }
            return metadata
        } catch let error {
            try? FileManager.default.removeItem(at: filePath)
            throw error
        }
    }
    
    
    static func storeLinkMetada(_ metadata: LPLinkMetadata, for url: URL) throws {
        guard let fileNameForArchiving = url.toFileNameForArchiving() else {
            return
        }
        let archivedData = NSMutableData()
        let archiver = NSKeyedArchiver(forWritingWith: archivedData)
        archiver.requiresSecureCoding = true
        metadata.encode(with: archiver)
        archiver.finishEncoding()
        let filePath = tempDir.appendingPathComponent(fileNameForArchiving)
        try archivedData.write(to: filePath)
    }
    
    
    static func removeCachedURLMetadata(olderThan dateLimit: Date) {
        guard FileManager.default.fileExists(atPath: tempDir.path) else { return }
        let includingPropertiesForKeys = [
            URLResourceKey.creationDateKey,
            URLResourceKey.isWritableKey,
            URLResourceKey.isRegularFileKey,
        ]
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: includingPropertiesForKeys, options: .skipsHiddenFiles) else { return }
        for fileURL in fileURLs {
            guard fileURL.isArchive else { return }
            guard let attributes = try? fileURL.resourceValues(forKeys: Set(includingPropertiesForKeys)) else { continue }
            guard attributes.isWritable == true else { return }
            guard attributes.isRegularFile == true else { return }
            guard let creationDate = attributes.creationDate, creationDate < dateLimit else { debugPrint("Keep"); return }
            // If we reach this point, we should delete the archive
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
    
}


@available(iOS 13.0, *)
private extension URL {
    
    func toFileNameForArchiving() -> String? {
        let digest = SHA256.hash(data: self.dataRepresentation)
        let digestString = digest.map { String(format: "%02hhx", $0) }.joined()
        return [digestString, "archive"].joined(separator: ".")
    }
    
    
    var isArchive: Bool {
        return self.pathExtension == "archive"
    }
}
