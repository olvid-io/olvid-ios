/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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

public struct ObvAppCoreConstants {
    
    public static let logSubsystem = "io.olvid.messenger"
    
    public static let appGroupIdentifier = Bundle.main.infoDictionary!["OBV_APP_GROUP_IDENTIFIER"]! as! String
    
    public struct Host {
        public static let forInvitations = Bundle.main.infoDictionary!["OBV_HOST_FOR_INVITATIONS"]! as! String
        public static let forConfigurations = Bundle.main.infoDictionary!["OBV_HOST_FOR_CONFIGURATIONS"]! as! String
        public static let forOpenIdRedirect = Bundle.main.infoDictionary!["OBV_HOST_FOR_OPENID_REDIRECT"]! as! String
    }

    public static let requestIdentifiersOfFullNotificationsAddedByExtension = "requestIdentifiersOfFullNotificationsAddedByExtension"

    public static var targetEnvironmentIsMacCatalyst: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }

    #if targetEnvironment(macCatalyst)
    public static let remoteNotificationByteIdentifierForServer = {
        let byteAsString = Bundle.main.infoDictionary!["OBV_REMOTE_NOTIFICATION_BYTE_IDENTIFIER_FOR_SERVER_MAC"]! as! String
        return Data(repeating: UInt8(byteAsString.suffix(2), radix: 16)!, count: 1)
    }()
    #else
    public static let remoteNotificationByteIdentifierForServer = {
        let byteAsString = Bundle.main.infoDictionary!["OBV_REMOTE_NOTIFICATION_BYTE_IDENTIFIER_FOR_SERVER_IPHONE"]! as! String
        return Data(repeating: UInt8(byteAsString.suffix(2), radix: 16)!, count: 1)
    }()
    #endif
    
    public static let securityApplicationGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier)!.resolvingSymlinksInPath()

    // Version

    public static let shortVersion = Bundle.main.infoDictionary!["CFBundleShortVersionString"]! as! String // Such as 0.3
    public static let bundleVersion = Bundle.main.infoDictionary!["CFBundleVersion"]! as! String // Aka build number
    public static let bundleVersionAsInt = Int(bundleVersion)!
    public static let fullVersion = "\(shortVersion) (\(bundleVersion))"

    public static func writeToPreferences() {
        UserDefaults.standard.setValue(fullVersion, forKey: "preference_version")
    }

    public static let toEmailForSendingInitializationFailureErrorMessage = "feedback@olvid.io"

    public enum OlvidAppType: Sendable {
        case development
        case production
    }

    public static let appType: OlvidAppType = {
        let stringValue = Bundle.main.infoDictionary!["OBV_APP_TYPE"]! as! String
        switch stringValue {
        case "development":
            return .development
        case "production":
            return .production
        default:
            assertionFailure()
            return .production
        }
    }()

    public static var developmentMode: Bool {
        Self.appType == .development
    }

    public static let isTestFlight = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"

    public static let urlForManagingSubscriptionWithTheAppStore = URL(string: "https://apps.apple.com/account/subscriptions")!
    public static let urlForManagingPaymentsOnTheAppStore = URL(string: "https://apps.apple.com/account/billing")!

    public static let serverURL = URL(string: Bundle.main.infoDictionary!["OBV_SERVER_URL"]! as! String)!
    public static var serverURLForStoringDeviceBackup: URL { serverURL }

    public static let iCloudContainerIdentifierForEngineBackup = "iCloud.io.olvid.messenger.backup"

    public struct BackupConstants {
        
        public static let recordType = "EngineBackupRecord"
        public static let creationDate = "creationDate" // Not a custom key since it belongs to CKRecord
        
        public enum Key: String {
            case deviceIdentifierForVendor = "deviceIdentifierForVendor"
            case deviceName = "deviceName"
            case encryptedBackupFile = "encryptedBackupFile"
        }

    }
    
}
