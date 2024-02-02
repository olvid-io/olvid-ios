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
import os.log
import UniformTypeIdentifiers
import ObvSettings
import CoreTransferable


struct NewBackupInfo: Identifiable, Transferable, Equatable, Hashable {
    
    let fileUrl: URL
    let deviceName: String?
    let creationDate: Date?
    var id: URL { fileUrl }
    
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: Self.self))

    static func createBackupInfoByCopyingFile(at url: URL) -> Self? {
        
        let tempBackupFileUrl: URL
        do {
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }

            guard let pathExtension = (url as NSURL).pathExtension, pathExtension == UTType.olvidBackup.preferredFilenameExtension else {
                os_log("The chosen file does not conform to the appropriate type. The file name shoud in with .olvidbackup", log: Self.log, type: .error)
                assertionFailure()
                return nil
            }
            
            os_log("A file with an appropriate file extension was returned.", log: Self.log, type: .info)

            // We can copy the backup file at an appropriate location

            let tempDir = ObvUICoreDataConstants.ContainerURL.forTempFiles.appendingPathComponent("BackupFilesToRestore", isDirectory: true)
            do {
                if FileManager.default.fileExists(atPath: tempDir.path) {
                    try FileManager.default.removeItem(at: tempDir) // Clean the directory
                }
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            } catch let error {
                os_log("Could not create temporary directory: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                return nil
            }

            let fileName = url.lastPathComponent
            tempBackupFileUrl = tempDir.appendingPathComponent(fileName)

            do {
                try FileManager.default.copyItem(at: url, to: tempBackupFileUrl)
            } catch let error {
                os_log("Could not copy backup file to temp location: %{public}@", log: Self.log, type: .error, error.localizedDescription)
                return nil
            }

            // Check that the file can be read
            do {
                _ = try Data(contentsOf: tempBackupFileUrl)
            } catch {
                os_log("Could not read backup file: %{public}@", log: Self.log, type: .error, error.localizedDescription)
                return nil
            }
        }

        // If we reach this point, we can start processing the backup file located at tempBackupFileUrl
        let info = NewBackupInfo(fileUrl: tempBackupFileUrl, deviceName: nil, creationDate: nil)
        return info
        
    }
    
    @available(iOS 16.0, macCatalyst 16.0, *)
    static var transferRepresentation: some TransferRepresentation {

        // For some reason, specifying .olvidBackup does not work.
        // This can be seen in the console by filtering on the Olvid process and DragAndDrop.
        // At some point, the recognized type appears to be something like "dyn.ah62d4rv4ge8085d0rfwge2pdrr41a".
        FileRepresentation(importedContentType: .item) { received in

            guard let backupInfo = Self.createBackupInfoByCopyingFile(at: received.file) else {
                assertionFailure()
                return .init(fileUrl: received.file, deviceName: nil, creationDate: nil)
            }
            return backupInfo

        }
    }

}
