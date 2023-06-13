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
import ObvTypes


public struct ObvUICoreDataConstants {
    
    static let logSubsystem = "io.olvid.obvuicoredata"
    
    public static let minimumLengthOfPasswordForHiddenProfiles = 4
    
    static let seedLengthForHiddenProfiles = 8
    
    static let appGroupIdentifier = Bundle.main.infoDictionary!["OBV_APP_GROUP_IDENTIFIER"]! as! String

    static var isRunningOnRealDevice: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    
    public static let developmentMode: Bool = {
        let stringValue = Bundle.main.infoDictionary!["OBV_DEVELOPMENT_MODE"]! as! String

        if let value = Bool(stringValue) {
            return value
        }

        if stringValue == "YES" {
            return true
        }

        return false
    }()

    
    // Keys of userDefault properties shared between app and extensions

    public enum SharedUserDefaultsKey: String {
        case objectsModifiedByShareExtension = "objectsModifiedByShareExtension"
        case extensionFailedToWipeAllEphemeralMessagesBeforeDate = "extensionFailedToWipeAllEphemeralMessagesBeforeDate"
        case latestCurrentOwnedIdentity = "latestCurrentOwnedIdentity"
    }

    public enum AppType {
        case mainApp
        case shareExtension
        case notificationExtension

        public var pathComponent: String {
            switch self {
            case .mainApp: return "MainApp"
            case .shareExtension: return "ShareExtension"
            case .notificationExtension: return "NotificationExtension"
            }
        }
        
        public var transactionAuthor: String {
            switch self {
            case .mainApp: return "mainApp"
            case .shareExtension: return "shareExtension"
            case .notificationExtension: return "notificationExtension"
            }
        }
    }

    // Any URL added to this enum will be automatically created at app launched using the `FileSystemService`
    public enum ContainerURL: CaseIterable {
        case mainAppContainer
        case mainEngineContainer
        case forDatabase
        case forFyles
        case forDocuments
        case forTempFiles
        case forMessagesDecryptedWithinNotificationExtension
        case forCache
        case forTrash
        case forDisplayableLogs
        case forCustomContactProfilePictures
        case forCustomGroupProfilePictures
        case forNotificationAttachments
        case forProfilePicturesCache
        case forFylesHardlinksWithinMainApp
        case forFylesHardlinksWithinShareExtension
        case forThumbnailsWithinMainApp
        /// This is for a place to store and process dropped attachments
        case forTemporaryDroppedItems

        private var securityApplicationGroupURL: URL {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ObvUICoreDataConstants.appGroupIdentifier)!
        }

        public func appendingPathComponent(_ pathComponent: String) -> URL {
            return self.url.appendingPathComponent(pathComponent)
        }

        public func appendingPathComponent(_ pathComponent: String, isDirectory: Bool) -> URL {
            return self.url.appendingPathComponent(pathComponent, isDirectory: isDirectory)
        }

        public var path: String {
            self.url.path
        }

        public var url: URL {
            switch self {
            case .mainAppContainer:
                return securityApplicationGroupURL.appendingPathComponent("Application", isDirectory: true)
            case .mainEngineContainer:
                return securityApplicationGroupURL.appendingPathComponent("Engine", isDirectory: true)
            case .forDatabase:
                return Self.mainAppContainer.url.appendingPathComponent("Database", isDirectory: true)
            case .forFyles:
                return Self.mainAppContainer.url.appendingPathComponent("Fyles", isDirectory: true)
            case .forDocuments:
                return try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            case .forTempFiles:
                return FileManager.default.temporaryDirectory
            case .forMessagesDecryptedWithinNotificationExtension:
                return securityApplicationGroupURL.appendingPathComponent("MessagesDecryptedWithinNotificationExtension", isDirectory: true)
            case .forCache:
                return Self.mainAppContainer.url.appendingPathComponent("Cache", isDirectory: true)
            case .forTrash:
                return Self.mainAppContainer.url.appendingPathComponent("Trash", isDirectory: true)
            case .forDisplayableLogs:
                return Self.mainAppContainer.url.appendingPathComponent("DisplayableLogs", isDirectory: true)
            case .forCustomContactProfilePictures:
                return Self.mainAppContainer.url.appendingPathComponent("CustomContactProfilePictures", isDirectory: true)
            case .forCustomGroupProfilePictures:
                return Self.mainAppContainer.url.appendingPathComponent("CustomGroupProfilePictures", isDirectory: true)
            case .forProfilePicturesCache:
                return Self.forCache.url.appendingPathComponent("ProfilePicture", isDirectory: true)
            case .forNotificationAttachments:
                return securityApplicationGroupURL.appendingPathComponent("NotificationAttachments", isDirectory: true)
            case .forFylesHardlinksWithinMainApp:
                return Self.mainAppContainer.url.appendingPathComponent("FylesHardLinks", isDirectory: true).appendingPathComponent(ObvUICoreDataConstants.AppType.mainApp.pathComponent, isDirectory: true)
            case .forFylesHardlinksWithinShareExtension:
                return Self.mainAppContainer.url.appendingPathComponent("FylesHardLinks", isDirectory: true).appendingPathComponent(ObvUICoreDataConstants.AppType.shareExtension.pathComponent, isDirectory: true)
            case .forThumbnailsWithinMainApp:
                return Self.mainAppContainer.url.appendingPathComponent("Thumbnails", isDirectory: true).appendingPathComponent(ObvUICoreDataConstants.AppType.mainApp.pathComponent, isDirectory: true)
            case .forTemporaryDroppedItems:
                return Self.forTempFiles.url.appendingPathComponent("dropped_items", isDirectory: true)
            }
        }

        public var printInitialDebugLogs: Bool {
            switch self {
            case .forDocuments, .forTempFiles, .forFylesHardlinksWithinMainApp, .forThumbnailsWithinMainApp, .forTrash, .forTemporaryDroppedItems:
                return true
            default:
                return false
            }
        }

        private var penultimateIsTitle: Bool {
            switch self {
            case .forFylesHardlinksWithinMainApp, .forFylesHardlinksWithinShareExtension, .forThumbnailsWithinMainApp:
                return true
            default: return false
            }
        }

        public var title: String {
            if penultimateIsTitle {
                return url.pathComponents.suffix(2).first ?? url.lastPathComponent
            } else {
                return url.lastPathComponent
            }
        }

        public var subtitle: String? {
            guard penultimateIsTitle else { return nil }
            return url.pathComponents.suffix(2).last
        }
    }

    // Groups V2
    
    public static let defaultObvGroupV2PermissionsForNewGroupMembers: Set<ObvGroupV2.Permission> = {
        Set([
            ObvGroupV2.Permission.sendMessage,
            ObvGroupV2.Permission.remoteDeleteAnything,
            ObvGroupV2.Permission.editOrRemoteDeleteOwnMessages,
        ])
    }()

    public static let defaultObvGroupV2PermissionsForAdmin: Set<ObvGroupV2.Permission> = {
        Set(ObvGroupV2.Permission.allCases)
    }()

}


// This extension makes it possible to use kvo on the user defaults dictionary used by the share extension

public extension UserDefaults {
    
    @objc dynamic var objectsModifiedByShareExtension: String {
        return ObvUICoreDataConstants.SharedUserDefaultsKey.objectsModifiedByShareExtension.rawValue
    }

    @objc dynamic var extensionFailedToWipeAllEphemeralMessagesBeforeDate: String {
        return ObvUICoreDataConstants.SharedUserDefaultsKey.extensionFailedToWipeAllEphemeralMessagesBeforeDate.rawValue
    }
    
}
