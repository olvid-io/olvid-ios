import ProjectDescription

public enum Constants {
    
    static let developmentRegion = "en"

    static let availableRegions = [
        "Base",
        developmentRegion,
        "fr"
    ]

    static let baseAppBundleIdentifier = "io.olvid.messenger"

    static let sampleAppBaseBundleIdentifier = baseAppBundleIdentifier + ".sample_app"

    public static let iOSDeploymentTargetVersion = "15.5"

    public static let iOSDeploymentDevices: DeploymentDevice = [.iphone, .ipad, .mac]

    public static let deploymentTarget: DeploymentTarget = .iOS(
        targetVersion: Constants.iOSDeploymentTargetVersion,
        devices: Constants.iOSDeploymentDevices,
        supportsMacDesignedForIOS: false)

    static let developmentTeam = ""

    static let marketingVersion = "2.1"

    static var buildNumber: String {
        get throws {
            return "757"
        }
    }
    
    public static let nsHumanReadableCopyrightValue = "Copyright © 2019-2024 Olvid SAS"


    static let fileHeader = """
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

"""
}
