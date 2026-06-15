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

import ObvUI
import UIKit
import ObvUICoreData
import ObvSystemIcon
import ObvAppCoreConstants


enum OlvidSnackBarCategory: CaseIterable {
    
    case grantPermissionToRecord
    case grantPermissionToRecordInSettings
    case newerAppVersionAvailable

    static func removeAllLastDisplayDate() {
        for category in OlvidSnackBarCategory.allCases {
            userDefaults.removeObject(forKey: category.lastDisplayDateKey)
        }
    }
    
    static func setLastDisplayDate(for category: OlvidSnackBarCategory) {
        let now = Date()
        userDefaults.setValue(now, forKey: category.lastDisplayDateKey)
    }
    
    var lastDisplayDate: Date? {
        OlvidSnackBarCategory.userDefaults.value(forKey: lastDisplayDateKey) as? Date
    }

    
    
    private static var userDefaults: UserDefaults { UserDefaults(suiteName: ObvAppCoreConstants.appGroupIdentifier)! }

    var body: String {
        switch self {
        case .grantPermissionToRecord:
            return NSLocalizedString("SNACK_BAR_BODY_GRANT_PERMISSION_TO_RECORD", comment: "")
        case .grantPermissionToRecordInSettings:
            return NSLocalizedString("SNACK_BAR_BODY_GRANT_PERMISSION_TO_RECORD_IN_SETTINGS", comment: "")
        case .newerAppVersionAvailable:
            return NSLocalizedString("SNACK_BAR_BODY_NEW_APP_VERSION_AVAILABLE", comment: "")
        }
    }
    
    var buttonTitle: String {
        switch self {
        case .grantPermissionToRecord:
            return NSLocalizedString("SNACK_BAR_BUTTON_TITLE_GRANT_PERMISSION_TO_RECORD", comment: "")
        case .grantPermissionToRecordInSettings:
            return NSLocalizedString("SNACK_BAR_BUTTON_TITLE_GRANT_PERMISSION_TO_RECORD_IN_SETTINGS", comment: "")
        case .newerAppVersionAvailable:
            return NSLocalizedString("SNACK_BAR_BUTTON_TITLE_NEW_APP_VERSION_AVAILABLE", comment: "")
        }
    }

    private var lastDisplayDateKey: String {
        switch self {
        case .grantPermissionToRecord:
            return "io.olvid.snackBarCoordinator.lastDisplayDate.grantPermissionToRecord"
        case .grantPermissionToRecordInSettings:
            return "io.olvid.snackBarCoordinator.lastDisplayDate.grantPermissionToRecordInSettings"
        case .newerAppVersionAvailable:
            return "io.olvid.snackBarCoordinator.lastDisplayDate.newerAppVersionAvailable"
        }
    }

    var icon: SystemIcon {
        switch self {
        case .grantPermissionToRecord, .grantPermissionToRecordInSettings:
            return .phoneCircleFill
        case .newerAppVersionAvailable:
            return .forwardFill
        }
    }
    
    var detailsTitle: String {
        switch self {
        case .grantPermissionToRecord:
            return NSLocalizedString("SNACK_BAR_DETAILS_TITLE_GRANT_PERMISSION_TO_RECORD", comment: "")
        case .grantPermissionToRecordInSettings:
            return NSLocalizedString("SNACK_BAR_DETAILS_TITLE_GRANT_PERMISSION_TO_RECORD_IN_SETTINGS", comment: "")
        case .newerAppVersionAvailable:
            return NSLocalizedString("SNACK_BAR_DETAILS_TITLE_NEW_APP_VERSION_AVAILABLE", comment: "")
        }
    }
    
    var detailsBody: String {
        switch self {
        case .grantPermissionToRecord:
            return NSLocalizedString("SNACK_BAR_DETAILS_BODY_GRANT_PERMISSION_TO_RECORD", comment: "")
        case .grantPermissionToRecordInSettings:
            return NSLocalizedString("SNACK_BAR_DETAILS_BODY_GRANT_PERMISSION_TO_RECORD_IN_SETTINGS", comment: "")
        case .newerAppVersionAvailable:
            return NSLocalizedString("SNACK_BAR_DETAILS_BODY_NEW_APP_VERSION_AVAILABLE", comment: "")
        }
    }
    
    var primaryActionTitle: String {
        switch self {
        case .grantPermissionToRecord:
            return NSLocalizedString("GRANT_PERMISSION_TO_RECORD_BUTTON_TITLE", comment: "")
        case .grantPermissionToRecordInSettings:
            return NSLocalizedString("GRANT_PERMISSION_TO_RECORD_IN_SETTINGS_BUTTON_TITLE", comment: "")
        case .newerAppVersionAvailable:
            return NSLocalizedString("GO_TO_APP_STORE_BUTTON_TITLE", comment: "")
        }
    }

    var secondaryActionTitle: String {
        switch self {
        case .grantPermissionToRecord:
            return NSLocalizedString("REMIND_ME_LATER", comment: "")
        case .grantPermissionToRecordInSettings:
            return NSLocalizedString("REMIND_ME_LATER", comment: "")
        case .newerAppVersionAvailable:
            return NSLocalizedString("REMIND_ME_LATER", comment: "")
        }
    }

}
