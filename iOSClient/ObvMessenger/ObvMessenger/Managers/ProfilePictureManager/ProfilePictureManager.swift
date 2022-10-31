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
import CoreData
import UIKit
import os.log


final class ProfilePictureManager {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: ProfilePictureManager.self))

    /// Used, in particular, to store group pictures during the creation process
    private let profilePicturesCacheDirectory: URL
    private let customContactProfilePicturesDirectory: URL
    private var observationTokens = [NSObjectProtocol]()

    init() {
        self.profilePicturesCacheDirectory = ObvMessengerConstants.containerURL.forProfilePicturesCache
        self.customContactProfilePicturesDirectory = ObvMessengerConstants.containerURL.forCustomContactProfilePictures
        clearThenCreateCacheDirectory()
        deleteUnusedCustomPictureIdentityPhotos()
        observeNewProfilePictureCandidateToCacheNotifications()
        observeNewCustomContactPictureCandidateToSaveNotifications()
    }
    
    deinit {
        clearThenCreateCacheDirectory()
    }
    
    private func clearThenCreateCacheDirectory() {
        if FileManager.default.fileExists(atPath: profilePicturesCacheDirectory.path) {
            do {
                try FileManager.default.removeItem(at: profilePicturesCacheDirectory)
            } catch let error {
                os_log("Could not delete profile picture cache at %{public}@: %{public}@", log: log, type: .error, profilePicturesCacheDirectory.path, error.localizedDescription)
            }
        }
        try! FileManager.default.createDirectory(at: profilePicturesCacheDirectory, withIntermediateDirectories: true, attributes: nil)
    }

    private func saveImage(_ image: UIImage, into url: URL) -> URL? {
        guard let jpegData = image.jpegData(compressionQuality: 0.75) else {
            assertionFailure()
            return nil
        }
        let filename = [UUID().uuidString, "jpeg"].joined(separator: ".")
        let filepath = url.appendingPathComponent(filename)
        do {
            try jpegData.write(to: filepath)
        } catch {
            assertionFailure()
            return nil
        }
        return filepath
    }
    
    private func observeNewProfilePictureCandidateToCacheNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeNewProfilePictureCandidateToCache { [weak self] (requestUUID, profilePicture) in
            guard let _self = self else { return }
            guard let filepath = _self.saveImage(profilePicture, into: _self.profilePicturesCacheDirectory) else { return }
            ObvMessengerInternalNotification.newCachedProfilePictureCandidate(requestUUID: requestUUID, url: filepath)
                .postOnDispatchQueue()
        })
    }

    private func observeNewCustomContactPictureCandidateToSaveNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeNewCustomContactPictureCandidateToSave { [weak self] (requestUUID, profilePicture) in
            guard let _self = self else { return }
            guard let filepath = _self.saveImage(profilePicture, into: _self.customContactProfilePicturesDirectory) else { return }
            ObvMessengerInternalNotification.newSavedCustomContactPictureCandidate(requestUUID: requestUUID, url: filepath)
                .postOnDispatchQueue()
        })
    }

    private func deleteUnusedCustomPictureIdentityPhotos() {
        ObvStack.shared.performBackgroundTaskAndWait { [weak self] (context) in
            guard let _self = self else { return }

            let photoURLsInDatabase: Set<URL>
            do {
                photoURLsInDatabase = try _self.getAllUsedCustomPhotoURL(within: context)
            } catch let error {
                os_log("Unable to compute the Set of all used custom photoURL: %{public}@", log: _self.log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }

            let photoURLsOnDisk: Set<URL>
            do {
                photoURLsOnDisk = try _self.getAllCustomPhotoURLOnDisk()
            } catch let error {
                os_log("Unable to compute the photo on disk: %{public}@", log: _self.log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }

            let photoURLsToDeleteFromDisk = photoURLsOnDisk.subtracting(photoURLsInDatabase)
            let photoURLsMissingFromDisk = photoURLsInDatabase.subtracting(photoURLsOnDisk)

            for photoURL in photoURLsToDeleteFromDisk {
                do {
                    try FileManager.default.removeItem(at: photoURL)
                } catch {
                    os_log("Cannot delete unused photo: %{public}@", log: _self.log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    return
                }
            }

            if !photoURLsMissingFromDisk.isEmpty {
                os_log("There are %d photo URLs referenced in database that cannot be found on disk", log: _self.log, type: .fault, photoURLsMissingFromDisk.count)
                assertionFailure()
            }
        }
    }

    private func getAllUsedCustomPhotoURL(within context: NSManagedObjectContext) throws -> Set<URL> {
        try PersistedObvContactIdentity.getAllCustomPhotoURLs(within: context)
    }

    private func getAllCustomPhotoURLOnDisk() throws  -> Set<URL> {
        Set(try FileManager.default.contentsOfDirectory(at: self.customContactProfilePicturesDirectory, includingPropertiesForKeys: nil))
    }

}
