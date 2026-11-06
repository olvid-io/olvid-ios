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

            // **Reported unconditionally, and before anything is deleted.** The twin of this sweep in `ObvIdentityManagerImplementation` carries the
            // reasoning; the short of it is that this is the same shape as the inbox's orphan sweep, which subtracted a `Set<URL>` built by
            // `appendingPathComponent` from one built by `contentsOfDirectory(at:)` — `/var/mobile/…` against `/private/var/mobile/…`, the same file and
            // never an exact match — and deleted every live message directory on every launch for as long as nobody looked. Here the database side is
            // `PersistedObvContactIdentity.customPhotoURL`, which appends to `ContainerURL.forCustomContactProfilePictures`, and the disk side is
            // `contentsOfDirectory(at:)` through `resolvingSymlinksInPath()`.
            //
            // **This one can be broken without anybody noticing**, which is why it is worth a line of its own: it covers only the photos a reader sets by
            // hand, so a developer with no custom contact photo never reaches the `assertionFailure` below whatever the comparison does.
            // `bothNonEmptyAndDisjoint` is the derived value that **is** the bug — two sets naming the same photos cannot be disjoint.
            let bothNonEmptyAndDisjoint = !photoURLsInDatabase.isEmpty && !photoURLsOnDisk.isEmpty && photoURLsInDatabase.isDisjoint(with: photoURLsOnDisk)
            Self.logger.info("📁 Custom contact photos sweep: \(photoURLsInDatabase.count) in database, \(photoURLsOnDisk.count) on disk, \(photoURLsToDeleteFromDisk.count) to delete from disk, \(photoURLsMissingFromDisk.count) missing from disk, bothNonEmptyAndDisjoint=\(bothNonEmptyAndDisjoint ? "TRUE" : "false", privacy: .public)")
            if !photoURLsToDeleteFromDisk.isEmpty || !photoURLsMissingFromDisk.isEmpty {
                // One URL of each shape whenever the two sides disagree, which is the whole diagnosis in a single line.
                Self.logger.info("📁 Custom contact photos sweep: a database URL reads \(photoURLsInDatabase.first?.path ?? "none", privacy: .public) and a disk URL reads \(photoURLsOnDisk.first?.path ?? "none", privacy: .public)")
            }

            for photoURL in photoURLsToDeleteFromDisk {
                do {
                    try FileManager.default.removeItem(at: photoURL)
                    Self.logger.info("📁 Custom contact photos sweep: deleted \(photoURL.path, privacy: .public)")
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
