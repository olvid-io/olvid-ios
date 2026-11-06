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
import UserNotifications

public struct ObvAppCoreConstants {
    
    public static let logSubsystem = "io.olvid.messenger"
    
    public static let appGroupIdentifier: String = {
        if let value = Bundle.main.infoDictionary?["OBV_APP_GROUP_IDENTIFIER"] as? String {
            return value
        }
        // `Bundle.main` does not carry the build-injected Info.plist keys when running in a bare `xctest` host (no host
        // application). In that case only, we fall back to the production app group identifier. This never triggers in
        // the app or its extensions, where the Info.plist key is always present, so production behavior is unchanged.
        return "group.io.olvid.messenger"
    }()
    
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

    public static var isRunningOnRealDevice: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
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
    
    public static let minimumLengthOfPasswordForHiddenProfiles = 4

    // WebRTC
    
    public struct ICEServerURLs {
        private static let global = [
            "turn:turn-scaled.olvid.io:5349?transport=udp",
            "turn:turn-scaled.olvid.io:443?transport=tcp",
            "turns:turn-scaled.olvid.io:443?transport=tcp",
        ]
        private struct regional {
            static let eu = [
                "turn:eu.turn-scaled.olvid.io:5349?transport=udp",
                "turn:eu.turn-scaled.olvid.io:443?transport=tcp",
                "turns:eu.turn-scaled.olvid.io:443?transport=tcp",
            ]
            static let us = [
                "turn:us.turn-scaled.olvid.io:5349?transport=udp",
                "turn:us.turn-scaled.olvid.io:443?transport=tcp",
                "turns:us.turn-scaled.olvid.io:443?transport=tcp",
            ]
            static let ap = [
                "turn:ap.turn-scaled.olvid.io:5349?transport=udp",
                "turn:ap.turn-scaled.olvid.io:443?transport=tcp",
                "turns:ap.turn-scaled.olvid.io:443?transport=tcp",
            ]
        }
        public static var preferred: [String] {
            // At some point, a setting should allow to choose between global or regional settings
            return global
        }
    }

}


// MARK: - Notification authorization

extension UNAuthorizationOptions {

    /// The options of every notification authorization request made by the app.
    ///
    /// Every request must use this list. If notifications are authorized without one of these options, the user does not
    /// get the matching setting, and our authorization screens are not shown again to fix it.
    public static let requestedByOlvid: UNAuthorizationOptions = [.alert, .sound, .badge, .carPlay]

}
