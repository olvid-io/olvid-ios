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
import UIKit
import ObvTypes

struct ObvMessengerConstants {
    
    static let logSubsystem = "io.olvid.messenger"
        
    static let developmentMode = Bool(Bundle.main.infoDictionary!["OBV_DEVELOPMENT_MODE"]! as! String)!
    static let isTestFlight = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    
    static let appGroupIdentifier = Bundle.main.infoDictionary!["OBV_APP_GROUP_IDENTIFIER"]! as! String
    
    struct Host {
        static let forInvitations = Bundle.main.infoDictionary!["OBV_HOST_FOR_INVITATIONS"]! as! String
        static let forConfigurations = Bundle.main.infoDictionary!["OBV_HOST_FOR_CONFIGURATIONS"]! as! String
        static let forOpenIdRedirect = Bundle.main.infoDictionary!["OBV_HOST_FOR_OPENID_REDIRECT"]! as! String
    }
    
    static let serverURL = URL(string: Bundle.main.infoDictionary!["OBV_SERVER_URL"]! as! String)!
    
    static let hardcodedAPIKey: UUID? = {
        guard Bundle.main.infoDictionary!.keys.contains("HARDCODED_API_KEY") else { return nil }
        return UUID(uuidString: Bundle.main.infoDictionary!["HARDCODED_API_KEY"]! as! String)
    }()
    
    static let defaultServerAndAPIKey: ServerAndAPIKey? = {
        guard let hardcodedAPIKey = ObvMessengerConstants.hardcodedAPIKey else { return nil }
        return ServerAndAPIKey(server: serverURL, apiKey: hardcodedAPIKey)
    }()
    
    static let toEmailForSendingInitializationFailureErrorMessage = "feedback@olvid.io"
    
    static let iCloudContainerIdentifierForEngineBackup = "iCloud.io.olvid.messenger.backup"

    static let userDataHasBeenDownloadedAfterMigration = "userDataHasBeenDownloadedAfterMigration"

    static let urlForManagingSubscriptionWithTheAppStore = URL(string: "https://apps.apple.com/account/subscriptions")!
    static let urlForManagingPaymentsOnTheAppStore = URL(string: "https://apps.apple.com/account/billing")!
    static let urlToOlvidTermsOfUse = URL(string: "https://olvid.io/terms")!
    static let urlToOlvidPrivacyPolicy = URL(string: "https://olvid.io/privacy")!

    static var showExperimentalFeature: Bool {
        ObvMessengerConstants.developmentMode || ObvMessengerConstants.isTestFlight || ObvMessengerSettings.BetaConfiguration.showBetaSettings
    }

    static let muteIcon: ObvSystemIcon = .moonZzzFill
    static let defaultEmoji = "👍"

    static let iTunesOlvidIdentifier = NSNumber(value: 1414865219) // Found via https://tools.applemediaservices.com
    static let shortLinkToOlvidAppIniTunes = URL(string: "https://apple.co/3lrdOUV")!
    
    static var isRunningOnRealDevice: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    enum AppType {
        case mainApp
        case shareExtension
        case notificationExtension

        var pathComponent: String {
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
    
    struct TTL {
        static let cachedURLMetadata: Int64 = 60*60*24*2 // 2 days
    }
    
    // Any URL added to this struct will be automatically created at app launched using the `FileSystemService`
    struct ContainerURL {
        let mainAppContainer: URL
        let mainEngineContainer: URL
        let forDatabase: URL
        let forFyles: URL
        let forDocuments: URL
        let forTempFiles: URL
        let forMessagesDecryptedWithinNotificationExtension: URL
        let forCache: URL
        let forTrash: URL
        let forDisplayableLogs: URL
        let forCustomContactProfilePictures: URL
        let forCustomGroupProfilePictures: URL
        init() {
            let securityApplicationGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)!
            let mainAppContainer = securityApplicationGroupURL.appendingPathComponent("Application", isDirectory: true)
            self.mainAppContainer = mainAppContainer
            self.mainEngineContainer = securityApplicationGroupURL.appendingPathComponent("Engine", isDirectory: true)
            self.forDatabase = mainAppContainer.appendingPathComponent("Database", isDirectory: true)
            self.forFyles = mainAppContainer.appendingPathComponent("Fyles", isDirectory: true)
            self.forDocuments = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            self.forTempFiles = FileManager.default.temporaryDirectory
            self.forMessagesDecryptedWithinNotificationExtension = securityApplicationGroupURL.appendingPathComponent("MessagesDecryptedWithinNotificationExtension", isDirectory: true)
            self.forCache = mainAppContainer.appendingPathComponent("Cache", isDirectory: true)
            self.forTrash = mainAppContainer.appendingPathComponent("Trash", isDirectory: true)
            self.forDisplayableLogs = mainAppContainer.appendingPathComponent("DisplayableLogs", isDirectory: true)
            self.forCustomContactProfilePictures = mainAppContainer.appendingPathComponent("CustomContactProfilePictures", isDirectory: true)
            self.forCustomGroupProfilePictures = mainAppContainer.appendingPathComponent("CustomGroupProfilePictures", isDirectory: true)
        }
        
        func forFylesHardlinks(within appType: AppType) -> URL {
            return mainAppContainer.appendingPathComponent("FylesHardLinks", isDirectory: true).appendingPathComponent(appType.pathComponent, isDirectory: true)
        }
        
        func forThumbnails(within appType: AppType) -> URL {
            return mainAppContainer.appendingPathComponent("Thumbnails", isDirectory: true).appendingPathComponent(appType.pathComponent, isDirectory: true)
        }
        
        func forLastPersistentHistoryToken(within appType: AppType) -> URL {
            return mainAppContainer.appendingPathComponent("LastPersistentHistoryToken", isDirectory: true).appendingPathComponent(appType.pathComponent, isDirectory: true)
        }

        var forProfilePicturesCache: URL {
            ObvMessengerConstants.containerURL.forCache.appendingPathComponent("ProfilePicture", isDirectory: true)
        }
        
    }
    static let containerURL = ContainerURL()
    
    // WebRTC
    
    struct TurnServerURLs {
        static let loadBalanced = [
            "turns:turn-scaled.olvid.io:5349?transport=udp",
            "turns:turn-scaled.olvid.io:443?transport=tcp",
        ]
    }
    
    // Version
    
    static let shortVersion = Bundle.main.infoDictionary!["CFBundleShortVersionString"]! as! String // Such as 0.3
    static let bundleVersion = Bundle.main.infoDictionary!["CFBundleVersion"]! as! String // Aka build number
    static let bundleVersionAsInt = Int(bundleVersion)!
    static let fullVersion = "\(shortVersion) (\(bundleVersion))"
    
    static let localIOSVersion = Double(UIDevice.current.systemVersion) ?? floor(NSFoundationVersionNumber)
    static let supportedIOSVersion = 13.0
    static let recommendedMinimumIOSVersion = 15.0
    
    static func writeToPreferences() {
        UserDefaults.standard.setValue(fullVersion, forKey: "preference_version")
    }

    // Notifications
    
    static let requestIdentifiersOfSilentNotificationsAddedByExtension = "requestIdentifiersOfSilentNotificationsAddedByExtension"
    static let requestIdentifiersOfFullNotificationsAddedByExtension = "requestIdentifiersOfFullNotificationsAddedByExtension"
    
    // Capabilities
    
    static let supportedObvCapabilities: Set<ObvCapability> = {
        [.webrtcContinuousICE]
    }()
}
