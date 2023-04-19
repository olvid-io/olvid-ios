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
import OlvidUtils

final class FileSystemService {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: FileSystemService.self))
    private var notificationTokens = [NSObjectProtocol]()
    private let internalQueue = OperationQueue.createSerialQueue(name: "FileSystemService internal Queue", qualityOfService: .default)

    init() {
        listenToNotifications()
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
        let mirroredContainerURL = Mirror(reflecting: ObvMessengerConstants.containerURL)
        for (_, element) in mirroredContainerURL.children.enumerated() {
            if let url = element.value as? URL {
                
                // Creating the directory if required
                if FileManager.default.fileExists(atPath: url.path) {
                    os_log("Path %{public}@ exists for ContainerURL %{public}@", log: log, type: .debug, url.path, element.label ?? "None")
                } else {
                    os_log("Path %{public}@ does not exist for ContainerURL %{public}@", log: log, type: .debug, url.path, element.label ?? "None")
                    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    os_log("Path %{public}@ was created for ContainerURL %{public}@", log: log, type: .debug, url.path, element.label ?? "None")
                }
                
                // Preventing iCloud backup
                do {
                    var mutableURL = url
                    var resourceValues = URLResourceValues()
                    resourceValues.isExcludedFromBackup = true
                    try mutableURL.setResourceValues(resourceValues)
                } catch let error as NSError {
                    fatalError("Error excluding \(url.deletingLastPathComponent()) from backup \(error.localizedDescription)")
                }

            }
        }
    }
    
    
    private func emptyTrashNow() {
        
        os_log("Emptying Trash...", log: log, type: .info)
        
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(at: ObvMessengerConstants.containerURL.forTrash, includingPropertiesForKeys: nil)
        } catch {
            os_log("Could not get content of trash directory: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }
        
        for url in urls {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                os_log("Failed to delete a trashed file: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                // In production, continue anyway
            }
        }

        os_log("Trash was emptied", log: log, type: .info)

    }
    
}
