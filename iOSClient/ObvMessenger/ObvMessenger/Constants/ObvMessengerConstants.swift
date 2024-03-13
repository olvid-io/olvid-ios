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
import ObvUI
import ObvUICoreData
import UI_SystemIcon
import ObvSettings


enum ObvMessengerConstants {
    
    static let logSubsystem = "io.olvid.messenger"
        
    static var developmentMode: Bool {
        ObvUICoreDataConstants.developmentMode
    }

    static let isTestFlight = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    
    static let appGroupIdentifier = Bundle.main.infoDictionary!["OBV_APP_GROUP_IDENTIFIER"]! as! String
    
    struct Host {
        static let forInvitations = Bundle.main.infoDictionary!["OBV_HOST_FOR_INVITATIONS"]! as! String
        static let forConfigurations = Bundle.main.infoDictionary!["OBV_HOST_FOR_CONFIGURATIONS"]! as! String
        static let forOpenIdRedirect = Bundle.main.infoDictionary!["OBV_HOST_FOR_OPENID_REDIRECT"]! as! String
    }
    
    static let serverURL = URL(string: Bundle.main.infoDictionary!["OBV_SERVER_URL"]! as! String)!
  
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

    static let muteIcon: SystemIcon = .moonZzzFill
    static let defaultEmoji = "👍"
    static let forwardIcon: SystemIcon = .arrowshapeTurnUpForward

    static let downsizedImageSize = CGSize(width: 40, height: 40) // In pixels

    static let allowedNumberOfWrongPasscodesBeforeLockOut = 3
    static let lockOutDuration: TimeInterval = TimeInterval(seconds: 60)

    static let iTunesOlvidIdentifier = NSNumber(value: 1414865219) // Found via https://tools.applemediaservices.com
    static let shortLinkToOlvidAppIniTunes = URL(string: "https://apple.co/3lrdOUV")!
    
    static let minimumLengthOfPasswordForHiddenProfiles = ObvUICoreDataConstants.minimumLengthOfPasswordForHiddenProfiles
    

    static var isRunningOnRealDevice: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }
    
    static var targetEnvironmentIsMacCatalyst: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }

    /// Helper indicating if remote notifications are available or not
    ///
    /// Enabled for:
    ///   - physical devices
    ///   - Mx (i.e. Apple Silicon) Simulators
    ///
    /// - Remark: Intel Macs with T2 chips can receive push notifications, however there is no way to distinguish them at build time
    static let areRemoteNotificationsAvailable: Bool = {
        #if targetEnvironment(simulator) && arch(x86_64)
            return false
        #else
            return true
        #endif
    }()
    
    struct TTL {
        static let cachedURLMetadata: Int64 = 60*60*24*2 // 2 days
    }
        
    // WebRTC
    
    struct ICEServerURLs {
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
        static var preferred: [String] {
            // At some point, a setting should allow to choose between global or regional settings
            return global
        }
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
    
    static let requestIdentifiersOfFullNotificationsAddedByExtension = "requestIdentifiersOfFullNotificationsAddedByExtension"

    // Capabilities
    
    static let supportedObvCapabilities: Set<ObvCapability> = {
        [.webrtcContinuousICE, .oneToOneContacts, .groupsV2]
    }()
    
    // Other
    
    public static let maximumTimeIntervalForKeptForLaterMessages = TimeInterval(days: 2)
    
    public static let maxCountForFilename = Int(NAME_MAX)

    // Link previews
    
    struct LinkPreview {
        
        static let numberOfLinesForDescriptions = 5
        
        static let domainsWithLongDescription: Set<String> = Set([
            "x.com",
            "twitter.com",
            "fxtwitter.com",
            "vxtwitter.com",
            "mastodon.social",
        ])

        
    }
    
    // VoIP
    
    public static let maxOtherParticipantCountForVideoCalls = 2
    public struct StreamId {
        static let olvid = "OlvidStreamId"
        static let video = "video"
        static let screencast = "screencast"
    }
    public struct TrackId {
        static let video = "video0"
        static let screencast = "screencast0"
        static let audio = "audio0"
    }

}
