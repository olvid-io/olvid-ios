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
import UIKit
import ObvTypes
import ObvUI
import ObvUICoreData
import ObvSystemIcon
import ObvSettings
import ObvAppCoreConstants


enum ObvMessengerConstants {
    
    // Now found in ObvAppCoreConstants
    // static let logSubsystem = "io.olvid.messenger"
        
    static var developmentMode: Bool {
        ObvAppCoreConstants.appType == .development
    }

    // Now found in ObvAppCoreConstants
    //static let isTestFlight = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    
    // Now found in ObvAppCoreConstants
    // static let appGroupIdentifier = Bundle.main.infoDictionary!["OBV_APP_GROUP_IDENTIFIER"]! as! String
    
    // Now found in ObvAppCoreConstants
//    struct Host {
//        static let forInvitations = Bundle.main.infoDictionary!["OBV_HOST_FOR_INVITATIONS"]! as! String
//        static let forConfigurations = Bundle.main.infoDictionary!["OBV_HOST_FOR_CONFIGURATIONS"]! as! String
//        static let forOpenIdRedirect = Bundle.main.infoDictionary!["OBV_HOST_FOR_OPENID_REDIRECT"]! as! String
//    }
    
    // Now found in ObvAppCoreConstants
    //static let serverURL = URL(string: Bundle.main.infoDictionary!["OBV_SERVER_URL"]! as! String)!
  
    // Now found in ObvAppCoreConstants
    //static let toEmailForSendingInitializationFailureErrorMessage = "feedback@olvid.io"
    
    // Now found in ObvAppCoreConstants
    //static let iCloudContainerIdentifierForEngineBackup = "iCloud.io.olvid.messenger.backup"

    static let userDataHasBeenDownloadedAfterMigration = "userDataHasBeenDownloadedAfterMigration"

    // Now found in ObvAppCoreConstants
    //static let urlForManagingSubscriptionWithTheAppStore = URL(string: "https://apps.apple.com/account/subscriptions")!
    //static let urlForManagingPaymentsOnTheAppStore = URL(string: "https://apps.apple.com/account/billing")!
    static let urlToOlvidTermsOfUse = URL(string: "https://olvid.io/terms")!
    static let urlToOlvidPrivacyPolicy = URL(string: "https://olvid.io/privacy")!

    // Now found in ObvAppCoreConstants
    static var showExperimentalFeature: Bool {
        ObvAppCoreConstants.developmentMode || ObvAppCoreConstants.isTestFlight || ObvMessengerSettings.BetaConfiguration.showBetaSettings
    }

    static let defaultEmoji = "👍"
    static let forwardIcon: SystemIcon = .arrowshapeTurnUpForward

    static let downsizedImageSize = CGSize(width: 40, height: 40) // In pixels
    
    static let contentInsetBottomWithFloatingButton: CGFloat = 100.0

    static let allowedNumberOfWrongPasscodesBeforeLockOut = 3
    static let lockOutDuration: TimeInterval = TimeInterval(seconds: 60)

    static let iTunesOlvidIdentifier = NSNumber(value: 1414865219) // Found via https://tools.applemediaservices.com
    static let shortLinkToOlvidAppIniTunes = URL(string: "https://apple.co/3lrdOUV")!
    

    static var isRunningOnRealDevice: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }
    
    static var targetEnvironmentIsMacCatalyst: Bool {
        ObvAppCoreConstants.targetEnvironmentIsMacCatalyst
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
        static let cachedURLMetadata: TimeInterval = .init(days: 2)
    }
        
    static let localIOSVersion = Double(UIDevice.current.systemVersion) ?? floor(NSFoundationVersionNumber)
    static let supportedIOSVersion = 15.5
    static let recommendedMinimumIOSVersion = 18.0
    
    // Notifications
    
    // Now found in ObvAppCoreConstants
    // static let requestIdentifiersOfFullNotificationsAddedByExtension = "requestIdentifiersOfFullNotificationsAddedByExtension"

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
            "bsky.app",
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

    // UserDefaults keys shared accross managers and coordinators
    
    enum UserDefaultsKeys: String {
        case dateOfLastDatabaseSync = "io.olvid.background.processing.database.sync.date"
        case dateOfLastAppInboxSyncMessageIdsKeptForLater = "io.olvid.background.processing.app.inbox.message.ids.sync.date"
        case dateOfCreationOfFirstProfile = "io.olvid.date.of.creation.of.first.profile"
        case dateOfLastOlvidPlusTipDisplay = "io.olvid.date.of.last.olvid.plus.tip.display"
        case olvidPlusSubscriptionConfirmationTipToDisplay = "io.olvid.plus.subscription.confirmation.tip.to.display" // Stores the raw value of a ObvOwnershipType
        case dateOfLastOSUpgradeTipDisplay = "io.olvid.snackBarCoordinator.lastDisplayDate.upgradeIOS"
        case dateOfLastOwnedDeviceExpiringTipDisplay = "io.olvid.date.of.last.owned.device.expiring.tip.display"
    }

}
