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

    /// What a double tap on a message received reacts with, when the reader has set nothing.
    ///
    /// The same glyph as ``defaultEmoji``, and a separate constant: the double tap and the quick-emoji button have
    /// their own settings at both levels, global and per discussion, so changing one does not change the other.
    static let defaultDoubleTapEmoji = "👍"
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
        
    /// An iOS version reduced to its major and minor components, compared component by component: 18.10 is later
    /// than 18.9, which a `major.minor` written as a `Double` gets wrong.
    struct IOSVersion: Comparable, Sendable {
        let major: Int
        let minor: Int
        static func < (lhs: IOSVersion, rhs: IOSVersion) -> Bool {
            (lhs.major, lhs.minor) < (rhs.major, rhs.minor)
        }
    }

    /// The running iOS version, compared against the two thresholds below.
    ///
    /// Read from `UIDevice`, never from `ProcessInfo`: under Mac Catalyst, `ProcessInfo` reports the macOS version
    /// (15.6) where `UIDevice.systemVersion` reports the iOS it corresponds to (18.6), and the thresholds are iOS
    /// versions. `UIDevice.current` is main-actor isolated, hence the `@MainActor`. A version that cannot be parsed
    /// counts as recent, an upgrade tip shown by mistake being worse than one missed.
    @MainActor
    static let localIOSVersion: IOSVersion = {
        let components = UIDevice.current.systemVersion.split(separator: ".").map { Int($0) }
        guard components.count >= 1, let major = components[0] else { return recommendedMinimumIOSVersion }
        let minor = components.count >= 2 ? (components[1] ?? 0) : 0
        return IOSVersion(major: major, minor: minor)
    }()
    static let supportedIOSVersion = IOSVersion(major: 15, minor: 5)
    static let recommendedMinimumIOSVersion = IOSVersion(major: 18, minor: 0)
    
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
        /// A JSON-encoded `ObvInboxDrainReport`. A background run happens while nobody is watching, so what it writes here is the only evidence it ran.
        ///
        /// **The drain's *date* is not a key of its own**, unlike the two sync tasks above: it is `startedAt` inside this report, which is what the schedule
        /// reads. There was such a key, written on every run and read by nothing.
        case lastEngineInboxDrainReport = "io.olvid.background.processing.drain.inbox.report"
        case dateOfCreationOfFirstProfile = "io.olvid.date.of.creation.of.first.profile"
        case dateOfLastOlvidPlusTipDisplay = "io.olvid.date.of.last.olvid.plus.tip.display"
        case olvidPlusSubscriptionConfirmationTipToDisplay = "io.olvid.plus.subscription.confirmation.tip.to.display" // Stores the raw value of a ObvOwnershipType
        case dateOfLastOSUpgradeTipDisplay = "io.olvid.snackBarCoordinator.lastDisplayDate.upgradeIOS"
        case dateOfLastOwnedDeviceExpiringTipDisplay = "io.olvid.date.of.last.owned.device.expiring.tip.display"
        case dateOfLastNewerAppVersionAvailableTipDisplay = "io.olvid.snackBarCoordinator.lastDisplayDate.newerAppVersionAvailable"
        case dateOfLastGrantRecordPermissionTipDisplay = "io.olvid.snackBarCoordinator.lastDisplayDate.grantPermissionToRecord"
    }

}
