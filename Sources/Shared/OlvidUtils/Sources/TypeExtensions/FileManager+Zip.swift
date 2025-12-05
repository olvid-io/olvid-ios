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
import UniformTypeIdentifiers


extension FileManager {
    
    /// Creates a zip file of a directory. The zip file is created at the location specified by `urlOfDestinationZipFile`. This location must **not** exist before calling this method.
    public func obvZipDirectory(at directoryURL: URL, urlOfDestinationZipFile: URL) async throws {
        
        guard try directoryURL.isDirectory else {
            assertionFailure()
            throw ObvFileManagerExtensionError.urlIsNotDirectory
        }
        
        // Make sure the destination file does not already exist
        
        guard !self.fileExists(atPath: urlOfDestinationZipFile.path) else {
            assertionFailure()
            throw ObvFileManagerExtensionError.urlOfDestinationZipFileAlreadyExists
        }
        
        // Make sure the UTI of the destination file is zip
        
        guard UTType(filenameExtension: urlOfDestinationZipFile.pathExtension) == .zip else {
            assertionFailure()
            throw ObvFileManagerExtensionError.urlOfDestinationZipFileIsNotZipFile
        }
        
        let coordinator = NSFileCoordinator()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            var coordinatorError: NSError?
            coordinator.coordinate(readingItemAt: directoryURL, options: .forUploading, error: &coordinatorError) { urlOfZippedFile in
                do {
                    
                    // Make sure the destination file does not already exist (it may have been created since last check)

                    guard !self.fileExists(atPath: urlOfDestinationZipFile.path) else {
                        assertionFailure()
                        throw ObvFileManagerExtensionError.urlOfDestinationZipFileAlreadyExists
                    }

                    // Move the received file to the destination file
                    
                    try self.moveItem(at: urlOfZippedFile, to: urlOfDestinationZipFile)
                    
                    return continuation.resume()
                    
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
                
            }
            // If there is an error, the block is not executed, so we must call continuation.resume here.
            if let coordinatorError {
                return continuation.resume(throwing: coordinatorError)
            }
        }
        
    }
    
}


enum ObvFileManagerExtensionError: Error {
    case urlIsNotDirectory
    case urlOfDestinationZipFileAlreadyExists
    case urlOfDestinationZipFileIsNotZipFile
}
