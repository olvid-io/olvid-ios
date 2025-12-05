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
import CoreData
import UIKit
import OSLog
import ObvUICoreData
import ObvSettings
import ObvAppCoreConstants


final class ProfilePictureManager {
    
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: ProfilePictureManager.self))

    /// Used, in particular, to store group pictures during the creation process
    private let profilePicturesCacheDirectory: URL
    private let customContactProfilePicturesDirectory: URL

    init() {
        self.profilePicturesCacheDirectory = ObvUICoreDataConstants.ContainerURL.forProfilePicturesCache.url
        self.customContactProfilePicturesDirectory = ObvUICoreDataConstants.ContainerURL.forCustomContactProfilePictures.url
        clearThenCreateCacheDirectory()
        deleteUnusedCustomPictureIdentityPhotos()
    }
    
    deinit {
        clearThenCreateCacheDirectory()
    }
    
    private func clearThenCreateCacheDirectory() {
        if FileManager.default.fileExists(atPath: profilePicturesCacheDirectory.path) {
            do {
                try FileManager.default.removeItem(at: profilePicturesCacheDirectory)
            } catch let error {
                let profilePicturesCacheDirectoryPath = profilePicturesCacheDirectory.path
                Self.logger.error("Could not delete profile picture cache at \(profilePicturesCacheDirectoryPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        try! FileManager.default.createDirectory(at: profilePicturesCacheDirectory, withIntermediateDirectories: true, attributes: nil)
    }


    private func deleteUnusedCustomPictureIdentityPhotos() {
        ObvStack.shared.performBackgroundTask { [weak self] context in
            guard let _self = self else { return }

            let photoURLsInDatabase: Set<URL>
            do {
                photoURLsInDatabase = try _self.getAllUsedCustomPhotoURL(within: context)
            } catch let error {
                Self.logger.fault("Unable to compute the Set of all used custom photoURL: \(error.localizedDescription, privacy: .public)")
                assertionFailure()
                return
            }

            let photoURLsOnDisk: Set<URL>
            do {
                photoURLsOnDisk = try _self.getAllCustomPhotoURLOnDisk()
            } catch let error {
                Self.logger.fault("Unable to compute the photo on disk: \(error.localizedDescription, privacy: .public)")
                assertionFailure()
                return
            }

            let photoURLsToDeleteFromDisk = photoURLsOnDisk.subtracting(photoURLsInDatabase)
            let photoURLsMissingFromDisk = photoURLsInDatabase.subtracting(photoURLsOnDisk)

            for photoURL in photoURLsToDeleteFromDisk {
                do {
                    try FileManager.default.removeItem(at: photoURL)
                } catch {
                    Self.logger.fault("Cannot delete unused photo: \(error.localizedDescription, privacy: .public)")
                    assertionFailure()
                    return
                }
            }

            if !photoURLsMissingFromDisk.isEmpty {
                Self.logger.fault("There are \(photoURLsMissingFromDisk.count) photo URLs referenced in database that cannot be found on disk")
                assertionFailure()
            }
        }
    }

    private func getAllUsedCustomPhotoURL(within context: NSManagedObjectContext) throws -> Set<URL> {
        try PersistedObvContactIdentity.getAllCustomPhotoURLs(within: context)
    }

    private func getAllCustomPhotoURLOnDisk() throws -> Set<URL> {
        return Set(try FileManager.default.contentsOfDirectory(at: self.customContactProfilePicturesDirectory, includingPropertiesForKeys: nil).map({ $0.resolvingSymlinksInPath() }))
    }

}
