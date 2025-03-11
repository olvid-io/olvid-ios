import ProjectDescription


public struct Constant {
    
    public static let devTeam = "VMDQ4PU27W"
    
    public static let destinations: ProjectDescription.Destinations = [.iPhone, .iPad, .macCatalyst]
    
    public static let deploymentTargets: ProjectDescription.DeploymentTargets = .iOS("15.5")
    
    static let organizationName = "Olvid"
    
    public static let developmentRegion = "en"

    public static let availableRegions = [
        "Base",
        developmentRegion,
        "fr"
    ]
            
    public static let appCategory = "public.app-category.social-networking"

    public static let nsHumanReadableCopyrightValue = "Copyright © 2019-2025 Olvid SAS"
    
    public static func olvidBundleDisplayName(for appType: OlvidAppType) -> String {
        switch appType {
        case .development:
            return "Olvid_dev"
        case .production:
            return "Olvid"
        }
    }
    
    public static func cfBundleURLSchemes(for appType: OlvidAppType) -> String {
        switch appType {
        case .development:
            return "olvid.dev"
        case .production:
            return "olvid"
        }
    }
    
    public static func appGroupIdentifier(for appType: OlvidAppType) -> String {
        switch appType {
        case .development:
            return "group.io.olvid.messenger-debug"
        case .production:
            return "group.io.olvid.messenger"
        }
    }
    
    
    public static func olvidBundleIdentifiers(for appType: OlvidAppType) -> OlvidBundleIdentifiers {
        switch appType {
        case .development:
            return .init(app: "io.olvid.messenger-debug",
                         shareExtension: "io.olvid.messenger-debug.extension-share",
                         notificationExtension: "io.olvid.messenger-debug.extension-notification-service",
                         intentsExtension: "io.olvid.messenger-debug.ObvMessengerIntentsExtension")
        case .production:
            return .init(app: "io.olvid.messenger",
                         shareExtension: "io.olvid.messenger.extension-share",
                         notificationExtension: "io.olvid.messenger.extension-notification-service",
                         intentsExtension: "io.olvid.messenger.ObvMessengerIntentsExtension")
        }
    }
    
    
    public static func olvidTargetNames(for appType: OlvidAppType) -> OlvidTargetNames {
        switch appType {
        case .development:
            return .init(app: "Olvid-Development",
                         shareExtension: "ObvMessengerShareExtension-Development",
                         notificationExtension: "ObvMessengerNotificationServiceExtension-Development",
                         intentsExtension: "ObvMessengerIntentsExtension-Development")
        case .production:
            return .init(app: "Olvid",
                         shareExtension: "ObvMessengerShareExtension",
                         notificationExtension: "ObvMessengerNotificationServiceExtension",
                         intentsExtension: "ObvMessengerIntentsExtension")
        }
    }
    
    
    /// Name of the Olvid app icon found in the Assets catalog of the main app.
    public static func olvidAppIconName(for appType: OlvidAppType) -> String {
        switch appType {
        case .development:
            return "AppIcon-debug"
        case .production:
            return "AppIcon"
        }
    }
    
    
    public static func olvidDistributionServerInfos(appType: OlvidAppType) -> OlvidDistributionServerInfos {
        switch appType {
        case .development:
            return .init(url: "https://server.dev.olvid.io",
                         remoteNotificationByteIdentifierForServer: .init(
                            mac: "0x06",
                            iPhone: "0x04"))
        case .production:
            return .init(url: "https://server.olvid.io",
                         remoteNotificationByteIdentifierForServer: .init(
                            mac: "0x06",
                            iPhone: "0x05"))
        }
    }

    
    public static let iCloudContainerIdentifierForOlvidBackups = "iCloud.io.olvid.messenger.backup"
    
    static let fileHeaderTemplate = """
/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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

"""

}


public enum OlvidAppType: CustomStringConvertible {
    
    case development
    case production
    
    public var description: String {
        switch self {
        case .development: return "development"
        case .production: return "production"
        }
    }
    
}


public enum OlvidHost: CustomStringConvertible {
    
    case openIdRedirect(appType: OlvidAppType)
    case olvidConfiguration
    case invitation
    
    /// This allows to interpolate an `OlvidHost`. Don't change this.
    public var description: String {
        switch self {
        case .openIdRedirect(appType: let appType):
            switch appType {
            case .production:
                return "openid-redirect.olvid.io"
            case .development:
                return "openid-redirect.dev.olvid.io"
            }
        case .olvidConfiguration:
            return "configuration.olvid.io"
        case .invitation:
            return "invitation.olvid.io"
        }
    }
    
}


public struct OlvidBundleIdentifiers {
    public let app: String
    public let shareExtension: String
    public let notificationExtension: String
    public let intentsExtension: String
}


public struct OlvidTargetNames {
    public let app: String
    public let shareExtension: String
    public let notificationExtension: String
    public let intentsExtension: String
}


public struct OlvidDistributionServerInfos {
    
    public let url: String
    public let remoteNotificationByteIdentifierForServer: RemoteNotificationByteIdentifierForServer
    
    /// Possible values for remote notification byte identifier:
    ///   - 0x00 means iOS silent notification, production mode (legacy)
    ///   - 0x03 means iOS silent notification, sandbox mode (legacy)
    ///   - 0x04 means iOS notification with content, sandbox mode
    ///   - 0x05 means iOS notification with content, production mode
    ///   - 0x06 means macOS notification
    public struct RemoteNotificationByteIdentifierForServer {
        public let mac: String
        public let iPhone: String
    }
    
}
