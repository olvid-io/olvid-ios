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
import ObvTypes
import ObvCrypto
import OlvidUtils


public enum ObvBackupNotification {
    
    case newBackupSeedGenerated(backupSeedString: String, backupKeyInformation: BackupKeyInformation, flowId: FlowIdentifier)
    case backupSeedGenerationFailed(flowId: FlowIdentifier)
    case backupForExportWasFinished(backupKeyUid: UID, version: Int, encryptedContent: Data, flowId: FlowIdentifier)
    case backupForUploadWasFinished(backupKeyUid: UID, version: Int, encryptedContent: Data, flowId: FlowIdentifier)
    case backupFailed(flowId: FlowIdentifier)
    case backupableManagerDatabaseContentChanged(flowId: FlowIdentifier)
    case backupForUploadWasUploaded(backupKeyUid: UID, version: Int, flowId: FlowIdentifier)
    case backupForExportWasExported(backupKeyUid: UID, version: Int, flowId: FlowIdentifier)

    private enum Name {
        case newBackupSeedGenerated
        case backupSeedGenerationFailed
        case backupForExportWasFinished
        case backupForUploadWasFinished
        case backupFailed
        case backupableManagerDatabaseContentChanged
        case backupForUploadWasUploaded
        case backupForExportWasExported
        
        private var namePrefix: String { return "ObvBackupNotification" }
        
        private var nameSuffix: String {
            switch self {
            case .newBackupSeedGenerated: return "newBackupSeedGenerated"
            case .backupSeedGenerationFailed: return "backupSeedGenerationFailed"
            case .backupForExportWasFinished: return "backupForExportWasFinished"
            case .backupForUploadWasFinished: return "backupForUploadWasFinished"
            case .backupFailed: return "backupFailed"
            case .backupableManagerDatabaseContentChanged: return "backupableManagerDatabaseContentChanged"
            case .backupForUploadWasUploaded: return "backupForUploadWasUploaded"
            case .backupForExportWasExported: return "backupForExportWasExported"
            }
        }

        var name: NSNotification.Name {
            let name = [namePrefix, nameSuffix].joined(separator: ".")
            return NSNotification.Name(name)
        }
        
        static func forInternalNotification(_ notification: ObvBackupNotification) -> NSNotification.Name {
            switch notification {
            case .newBackupSeedGenerated: return Name.newBackupSeedGenerated.name
            case .backupSeedGenerationFailed: return Name.backupSeedGenerationFailed.name
            case .backupForExportWasFinished: return Name.backupForExportWasFinished.name
            case .backupForUploadWasFinished: return Name.backupForUploadWasFinished.name
            case .backupFailed: return Name.backupFailed.name
            case .backupableManagerDatabaseContentChanged: return Name.backupableManagerDatabaseContentChanged.name
            case .backupForUploadWasUploaded: return Name.backupForUploadWasUploaded.name
            case .backupForExportWasExported: return Name.backupForExportWasExported.name
            }
        }

    }
    
    private var userInfo: [AnyHashable: Any]? {
        let info: [AnyHashable: Any]?
        switch self {
        case .newBackupSeedGenerated(backupSeedString: let backupSeedString, backupKeyInformation: let backupKeyInformation, flowId: let flowId):
            info = [
                "backupSeedString": backupSeedString,
                "backupKeyInformation": backupKeyInformation,
                "flowId": flowId,
            ]
        case .backupSeedGenerationFailed(flowId: let flowId):
            info = [
                "flowId": flowId,
            ]
        case .backupForExportWasFinished(backupKeyUid: let backupKeyUid, version: let version, encryptedContent: let encryptedContent, flowId: let flowId):
            info = [
                "backupKeyUid": backupKeyUid,
                "version": version,
                "encryptedContent": encryptedContent,
                "flowId": flowId,
            ]
        case .backupForUploadWasFinished(backupKeyUid: let backupKeyUid, version: let version, encryptedContent: let encryptedContent, flowId: let flowId):
            info = [
                "backupKeyUid": backupKeyUid,
                "version": version,
                "encryptedContent": encryptedContent,
                "flowId": flowId,
            ]
        case .backupFailed(flowId: let flowId):
            info = [
                "flowId": flowId,
            ]
        case .backupableManagerDatabaseContentChanged(flowId: let flowId):
            info = [
                "flowId": flowId,
            ]
        case .backupForUploadWasUploaded(backupKeyUid: let backupKeyUid, version: let version, flowId: let flowId):
            info = [
                "backupKeyUid": backupKeyUid,
                "version": version,
                "flowId": flowId,
            ]
        case .backupForExportWasExported(backupKeyUid: let backupKeyUid, version: let version, flowId: let flowId):
            info = [
                "backupKeyUid": backupKeyUid,
                "version": version,
                "flowId": flowId,
            ]
        }
        return info
    }
    
    func post(within notificationDelegate: ObvNotificationDelegate) {
        let name = Name.forInternalNotification(self)
        notificationDelegate.post(name: name, userInfo: userInfo)
    }
        
    public func postOnDispatchQueue(withLabel label: String, within notificationDelegate: ObvNotificationDelegate) {
        let name = Name.forInternalNotification(self)
        let userInfo = self.userInfo
        DispatchQueue(label: label).async {
            notificationDelegate.post(name: name, userInfo: userInfo)
        }
    }
    
    public static func observeBackupForExportWasExported(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (UID, Int, FlowIdentifier) -> Void) -> NSObjectProtocol {
        let name = Name.backupForExportWasExported.name
        return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
            let backupKeyUid = notification.userInfo!["backupKeyUid"] as! UID
            let version = notification.userInfo!["version"] as! Int
            let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
            block(backupKeyUid, version, flowId)
        }
    }

    public static func observeBackupForUploadWasUploaded(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (UID, Int, FlowIdentifier) -> Void) -> NSObjectProtocol {
        let name = Name.backupForUploadWasUploaded.name
        return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
            let backupKeyUid = notification.userInfo!["backupKeyUid"] as! UID
            let version = notification.userInfo!["version"] as! Int
            let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
            block(backupKeyUid, version, flowId)
        }
    }

    public static func observeBackupableManagerDatabaseContentChanged(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (FlowIdentifier) -> Void) -> NSObjectProtocol {
        let name = Name.backupableManagerDatabaseContentChanged.name
        return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
            let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
            block(flowId)
        }
    }

    public static func observeBackupFailed(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (FlowIdentifier) -> Void) -> NSObjectProtocol {
        let name = Name.backupFailed.name
        return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
            let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
            block(flowId)
        }
    }

    public static func observeNewBackupSeedGenerated(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (String, BackupKeyInformation, FlowIdentifier) -> Void) -> NSObjectProtocol {
        let name = Name.newBackupSeedGenerated.name
        return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
            let backupSeedString = notification.userInfo!["backupSeedString"] as! String
            let backupKeyInformation = notification.userInfo!["backupKeyInformation"] as! BackupKeyInformation
            let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
            block(backupSeedString, backupKeyInformation, flowId)
        }
    }

    public static func observeBackupSeedGenerationFailed(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (FlowIdentifier) -> Void) -> NSObjectProtocol {
        let name = Name.backupSeedGenerationFailed.name
        return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
            let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
            block(flowId)
        }
    }
    
    public static func observeBackupForExportWasFinished(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (UID, Int, Data, FlowIdentifier) -> Void) -> NSObjectProtocol {
        let name = Name.backupForExportWasFinished.name
        return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
            let backupKeyUid = notification.userInfo!["backupKeyUid"] as! UID
            let version = notification.userInfo!["version"] as! Int
            let encryptedContent = notification.userInfo!["encryptedContent"] as! Data
            let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
            block(backupKeyUid, version, encryptedContent, flowId)
        }
    }

    public static func observeBackupForUploadWasFinished(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (UID, Int, Data, FlowIdentifier) -> Void) -> NSObjectProtocol {
        let name = Name.backupForUploadWasFinished.name
        return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
            let backupKeyUid = notification.userInfo!["backupKeyUid"] as! UID
            let version = notification.userInfo!["version"] as! Int
            let encryptedContent = notification.userInfo!["encryptedContent"] as! Data
            let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
            block(backupKeyUid, version, encryptedContent, flowId)
        }
    }

}
