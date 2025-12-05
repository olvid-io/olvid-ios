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
import OSLog
import OlvidUtils
import ObvUICoreData
import ObvSettings
import ObvAppCoreConstants


final class FileSystemService {
    
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: FileSystemService.self))
    private var notificationTokens = [NSObjectProtocol]()
    private let internalQueue = OperationQueue.createSerialQueue(name: "FileSystemService internal Queue")

    init() {
        listenToNotifications()
    }
    
    deinit {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func listenToNotifications() {
        notificationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeTrashShouldBeEmptied(queue: internalQueue) { [weak self] in
                self?.emptyTrashNow()
            },
        ])
    }
    
}


extension FileSystemService {
    
    func createAllDirectoriesIfRequired() {
        
        for containerURL in ObvUICoreDataConstants.ContainerURL.allCases {
            let url = containerURL.url
            var title = containerURL.title
            if let subtitle = containerURL.subtitle {
                title += " (" + subtitle + ")"
            }
            // Creating the directory if required
            if FileManager.default.fileExists(atPath: url.path) {
                Self.logger.debug("Path \(url.path, privacy: .public) exists for ContainerURL: \(title, privacy: .public)")
            } else {
                Self.logger.debug("Path \(url.path, privacy: .public) does not exist for ContainerURL: \(title, privacy: .public)")
                try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                Self.logger.debug("Path \(url.path, privacy: .public) was created for ContainerURL: \(title, privacy: .public)")
            }
        }
        
        // Preventing iCloud backup by excluding all directories (but not regular files) found in the securityApplicationGroupURL
        
        Self.logger.info("Excluding the directories of the securityApplicationGroupURL from backup...")
        
        do {
            let urlsInSecurityApplicationGroupURL: [URL] = try FileManager.default.contentsOfDirectory(at: ObvUICoreDataConstants.ContainerURL.securityApplicationGroupURL, includingPropertiesForKeys: [.isDirectoryKey])
            for urlToExclude in urlsInSecurityApplicationGroupURL {
                do {
                    let isDirectory = try urlToExclude.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? true
                    if isDirectory {
                        try urlToExclude.excludeFromBackup()
                    }
                } catch {
                    Self.logger.fault("Could not exclude from backup this specific URL of the securityApplicationGroupURL \(urlToExclude.path, privacy: .public): \(error, privacy: .public)")
                    assertionFailure()
                }
            }
            Self.logger.info("Did exclude the directories of the securityApplicationGroupURL from backup")
        } catch {
            Self.logger.fault("Could not exclude from backup content of the securityApplicationGroupURL: \(error, privacy: .public)")
            assertionFailure()
        }
            
    }
    
    
    private func emptyTrashNow() {
        
        Self.logger.info("Emptying Trash...")
        
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(at: ObvUICoreDataConstants.ContainerURL.forTrash.url, includingPropertiesForKeys: nil)
        } catch {
            Self.logger.fault("Could not get content of trash directory: \(error.localizedDescription, privacy: .public)")
            assertionFailure()
            return
        }
        
        for url in urls {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                Self.logger.fault("Failed to delete a trashed file: \(error.localizedDescription, privacy: .public)")
                assertionFailure()
                // In production, continue anyway
            }
        }

        Self.logger.info("Trash was emptied")

    }
    
}
