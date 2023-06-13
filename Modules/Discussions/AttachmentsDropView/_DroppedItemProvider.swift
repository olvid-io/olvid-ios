/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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

/// When a drop interaction is performed, we receive a `UIDropSession`. This session contains one or more `NSItemProvider` instances whose scope is limited
/// to the UIDropInteractionDelegate's implementation of ``-dropInteraction:performDrop:``. For this reason, we load each of these items in that delegate method,
/// and create a ``DroppedItemProvider`` for each: these new items have a scope valid until they are deallocated.
@available(iOSApplicationExtension 14, *)
final class DroppedItemProvider: NSItemProvider {
    
    /// Copies a given file, at `url`, into `directory`
    /// - Parameters:
    ///   - url: The source `URL` to copy
    ///   - directory: An `URL` to the temporary directory
    /// - Returns: The copied file's info
    ///
    /// - SeeAlso: ``CopiedItemInfo``
    private static func copyFile(at url: URL, intoRandomDirectoryIn directory: URL) throws -> CopiedItemInfo {
        let uuid = UUID()
        let directoryForCopyingFileURL = directory.appendingPathComponent(uuid.uuidString)
        try FileManager.default.createDirectory(at: directoryForCopyingFileURL, withIntermediateDirectories: true)
        let toURL = directoryForCopyingFileURL.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: toURL)

        return .init(
            parentDirectoryURL: directoryForCopyingFileURL,
            locallyReferencedFileURL: toURL
        )
    }

    /// This is the directory that contains ``locallyReferencedFileURL``
    /// The rational behind this directory is to prevent name collisions
    private let locallyReferencedFileParentDirectoryURL: URL

    /// This file has been locally copied, and is ours to keep when in use. Most importantly, must delete after we're done
    private let locallyReferencedFileURL: URL

    /// Designated initializer, will make a local copy of `url`
    /// - Parameters:
    ///   - url: The `URL` of the _locally_ available file, a copy will be available during the lifetime of the returned object
    ///   - directoryForTemporaryFiles: The source root directory of where we will store our temporary files
    ///   - typeIdentifiersToRegister: An array of `UTType`s  that are handled originally handled by the source item provider
    ///
    /// - Throws:
    ///   - ``ProviderError``
    ///   - Errors thrown by `FileManager`
    public init(url: URL, directoryForTemporaryFiles: URL, typeIdentifiersToRegister: [UTType]) throws {
        // Copy the file at `url` into the `directoryForTemporaryFiles` (where we create a new "random" directory to store the file)
        let copiedItemInfo = try Self.copyFile(at: url, intoRandomDirectoryIn: directoryForTemporaryFiles)

        locallyReferencedFileParentDirectoryURL = copiedItemInfo.parentDirectoryURL

        // Keep a reference to the created file in order to delete it when we are deallocated
        let locallyReferencedFileURL = copiedItemInfo.locallyReferencedFileURL

        self.locallyReferencedFileURL = locallyReferencedFileURL

        super.init()

        // Register all type identifiers for the file

        typeIdentifiersToRegister.forEach { typeIdentifier in
            @Sendable
            func loadHandler(completion: @escaping (URL?, Bool, Error?) -> Void) -> Progress? {
                guard FileManager.default.fileExists(atPath: locallyReferencedFileURL.path) else {
                    completion(nil, false, ProviderError.referencedFileDoesNotExist(at: locallyReferencedFileURL))

                    return nil
                }

                completion(locallyReferencedFileURL, false, nil)

                return nil
            }

            if #available(iOS 16, *) {
                registerFileRepresentation(
                    for: typeIdentifier,
                    visibility: .ownProcess,
                    loadHandler: loadHandler
                )
            } else {
                registerFileRepresentation(
                    forTypeIdentifier: typeIdentifier.identifier,
                    visibility: .ownProcess,
                    loadHandler: loadHandler)
            }
        }
    }

    deinit {
        if FileManager.default.fileExists(atPath: locallyReferencedFileURL.path) {
            do {
                try FileManager.default.removeItem(at: locallyReferencedFileURL)
            } catch {
                assertionFailure("failed to delete file at \(locallyReferencedFileURL) with error: \(error)")
            }

            do {
                try FileManager.default.removeItem(at: locallyReferencedFileParentDirectoryURL)
            } catch {
                assertionFailure("failed to delete parent directory at \(locallyReferencedFileParentDirectoryURL) with error: \(error)")
            }
        } else {
            assertionFailure("expected to have our file exist at \(locallyReferencedFileURL)")
        }
    }
}

@available(iOSApplicationExtension 14, *)
extension DroppedItemProvider {
    /// Denotes the possible errors thrown by an instance of ``DroppedItemProvider``
    ///
    /// - referencedFileDoesNotExist: Error thrown when the file at the given `URL` does not exist
    enum ProviderError: Error {
        /// Error thrown when the file at the given `URL` does not exist
        case referencedFileDoesNotExist(at: URL)
    }
}

@available(iOSApplicationExtension 14, *)
extension DroppedItemProvider {
    /// Structure containing info regarding the copied item
    struct CopiedItemInfo {
        /// This is the directory that contains ``locallyReferencedFileURL``
        let parentDirectoryURL: URL

        /// The `URL` of the copied item
        let locallyReferencedFileURL: URL
    }
}
