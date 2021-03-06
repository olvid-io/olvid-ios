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

import UIKit


enum OlvidSnackBarCategory: CaseIterable {
    
    case createBackupKey
    case shouldPerformBackup
    case shouldVerifyBackupKey
    case grantPermissionToRecord
    case grantPermissionToRecordInSettings
    case upgradeIOS
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

    
    
    private static var userDefaults: UserDefaults { UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier)! }

    var body: String {
        switch self {
        case .createBackupKey:
            return NSLocalizedString("SNACK_BAR_BODY_CREATE_BACKUP_KEY", comment: "")
        case .shouldPerformBackup:
            return NSLocalizedString("SNACK_BAR_BODY_SHOULD_PERFORM_BACKUP", comment: "")
        case .shouldVerifyBackupKey:
            return NSLocalizedString("SNACK_BAR_BODY_SHOULD_VERIFY_BACKUP_KEY", comment: "")
        case .grantPermissionToRecord:
            return NSLocalizedString("SNACK_BAR_BODY_GRANT_PERMISSION_TO_RECORD", comment: "")
        case .grantPermissionToRecordInSettings:
            return NSLocalizedString("SNACK_BAR_BODY_GRANT_PERMISSION_TO_RECORD_IN_SETTINGS", comment: "")
        case .upgradeIOS:
            if ObvMessengerConstants.localIOSVersion < ObvMessengerConstants.supportedIOSVersion {
                return NSLocalizedString("SNACK_BAR_BODY_IOS_VERSION_WILL_BE_UNSUPPORTED", comment: "")
            } else if ObvMessengerConstants.localIOSVersion < ObvMessengerConstants.recommendedMinimumIOSVersion {
                return NSLocalizedString("SNACK_BAR_BODY_IOS_VERSION_SHOULD_UPGRADE", comment: "")
            } else {
                return NSLocalizedString("SNACK_BAR_BODY_IOS_VERSION_ACCEPTABLE", comment: "")
            }
        case .newerAppVersionAvailable:
            return NSLocalizedString("SNACK_BAR_BODY_NEW_APP_VERSION_AVAILABLE", comment: "")
        }
    }
    
    var buttonTitle: String {
        switch self {
        case .createBackupKey:
            return NSLocalizedString("SNACK_BAR_BUTTON_TITLE_CREATE_BACKUP_KEY", comment: "")
        case .shouldPerformBackup:
            return NSLocalizedString("SNACK_BAR_BUTTON_TITLE_SHOULD_PERFORM_BACKUP", comment: "")
        case .shouldVerifyBackupKey:
            return NSLocalizedString("SNACK_BAR_BUTTON_TITLE_SHOULD_VERIFY_BACKUP_KEY", comment: "")
        case .grantPermissionToRecord:
            return NSLocalizedString("SNACK_BAR_BUTTON_TITLE_GRANT_PERMISSION_TO_RECORD", comment: "")
        case .grantPermissionToRecordInSettings:
            return NSLocalizedString("SNACK_BAR_BUTTON_TITLE_GRANT_PERMISSION_TO_RECORD_IN_SETTINGS", comment: "")
        case .upgradeIOS:
            if ObvMessengerConstants.localIOSVersion < ObvMessengerConstants.supportedIOSVersion {
                return NSLocalizedString("SNACK_BAR_TITLE_IOS_VERSION_WILL_BE_UNSUPPORTED", comment: "")
            } else if ObvMessengerConstants.localIOSVersion < ObvMessengerConstants.recommendedMinimumIOSVersion {
                return NSLocalizedString("SNACK_BAR_TITLE_IOS_VERSION_SHOULD_UPGRADE", comment: "")
            } else {
                return NSLocalizedString("SNACK_BAR_TITLE_IOS_VERSION_ACCEPTABLE", comment: "")
            }
        case .newerAppVersionAvailable:
            return NSLocalizedString("SNACK_BAR_BUTTON_TITLE_NEW_APP_VERSION_AVAILABLE", comment: "")
        }
    }

    private var lastDisplayDateKey: String {
        switch self {
        case .createBackupKey:
            return "io.olvid.snackBarCoordinator.lastDisplayDate.createBackupKey"
        case .shouldPerformBackup:
            return "io.olvid.snackBarCoordinator.lastDisplayDate.shouldPerformBackup"
        case .shouldVerifyBackupKey:
            return "io.olvid.snackBarCoordinator.lastDisplayDate.shouldVerifyBackupKey"
        case .grantPermissionToRecord:
            return "io.olvid.snackBarCoordinator.lastDisplayDate.grantPermissionToRecord"
        case .grantPermissionToRecordInSettings:
            return "io.olvid.snackBarCoordinator.lastDisplayDate.grantPermissionToRecordInSettings"
        case .upgradeIOS:
            return "io.olvid.snackBarCoordinator.lastDisplayDate.upgradeIOS"
        case .newerAppVersionAvailable:
            return "io.olvid.snackBarCoordinator.lastDisplayDate.newerAppVersionAvailable"
        }
    }
    
    var image: UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: 30, weight: .regular)
        switch self {
        case .createBackupKey, .shouldPerformBackup, .shouldVerifyBackupKey:
            return UIImage(systemIcon: .arrowCounterclockwiseCircleFill, withConfiguration: config)
        case .grantPermissionToRecord, .grantPermissionToRecordInSettings:
            return UIImage(systemIcon: .phoneCircleFill, withConfiguration: config)
        case .upgradeIOS:
            return UIImage(systemIcon: .gear, withConfiguration: config)
        case .newerAppVersionAvailable:
            return UIImage(systemIcon: .forwardFill, withConfiguration: config)
        }
    }
    
    var detailsTitle: String {
        switch self {
        case .createBackupKey:
            return NSLocalizedString("SNACK_BAR_DETAILS_TITLE_CREATE_BACKUP_KEY", comment: "")
        case .shouldPerformBackup:
            return NSLocalizedString("SNACK_BAR_DETAILS_TITLE_SHOULD_PERFORM_BACKUP", comment: "")
        case .shouldVerifyBackupKey:
            return NSLocalizedString("SNACK_BAR_DETAILS_TITLE_SHOULD_VERIFY_BACKUP_KEY", comment: "")
        case .grantPermissionToRecord:
            return NSLocalizedString("SNACK_BAR_DETAILS_TITLE_GRANT_PERMISSION_TO_RECORD", comment: "")
        case .grantPermissionToRecordInSettings:
            return NSLocalizedString("SNACK_BAR_DETAILS_TITLE_GRANT_PERMISSION_TO_RECORD_IN_SETTINGS", comment: "")
        case .upgradeIOS:
            if ObvMessengerConstants.localIOSVersion < ObvMessengerConstants.supportedIOSVersion {
                return NSLocalizedString("SNACK_BAR_DETAILS_TITLE_IOS_VERSION_WILL_BE_UNSUPPORTED", comment: "")
            } else if ObvMessengerConstants.localIOSVersion < ObvMessengerConstants.recommendedMinimumIOSVersion {
                return NSLocalizedString("SNACK_BAR_DETAILS_TITLE_IOS_VERSION_SHOULD_UPGRADE", comment: "")
            } else {
                return NSLocalizedString("SNACK_BAR_DETAILS_TITLE_IOS_VERSION_ACCEPTABLE", comment: "")
            }
        case .newerAppVersionAvailable:
            return NSLocalizedString("SNACK_BAR_DETAILS_TITLE_NEW_APP_VERSION_AVAILABLE", comment: "")
        }
    }
    
    var detailsBody: String {
        switch self {
        case .createBackupKey:
            return String.localizedStringWithFormat(NSLocalizedString("SNACK_BAR_DETAILS_BODY_CREATE_BACKUP_KEY_%@", comment: ""), UIDevice.current.name)
        case .shouldPerformBackup:
            return String.localizedStringWithFormat(NSLocalizedString("SNACK_BAR_DETAILS_BODY_SHOULD_PERFORM_BACKUP_%@", comment: ""), UIDevice.current.name)
        case .shouldVerifyBackupKey:
            return String.localizedStringWithFormat(NSLocalizedString("SNACK_BAR_DETAILS_BODY_SHOULD_VERIFY_BACKUP_KEY_%@", comment: ""), UIDevice.current.name)
        case .grantPermissionToRecord:
            return NSLocalizedString("SNACK_BAR_DETAILS_BODY_GRANT_PERMISSION_TO_RECORD", comment: "")
        case .grantPermissionToRecordInSettings:
            return NSLocalizedString("SNACK_BAR_DETAILS_BODY_GRANT_PERMISSION_TO_RECORD_IN_SETTINGS", comment: "")
        case .upgradeIOS:
            if ObvMessengerConstants.localIOSVersion < ObvMessengerConstants.supportedIOSVersion {
                return NSLocalizedString("SNACK_BAR_DETAILS_BODY_IOS_VERSION_WILL_BE_UNSUPPORTED", comment: "")
            } else if ObvMessengerConstants.localIOSVersion < ObvMessengerConstants.recommendedMinimumIOSVersion {
                return NSLocalizedString("SNACK_BAR_DETAILS_BODY_IOS_VERSION_SHOULD_UPGRADE", comment: "")
            } else {
                return NSLocalizedString("SNACK_BAR_DETAILS_BODY_IOS_VERSION_ACCEPTABLE", comment: "")
            }
        case .newerAppVersionAvailable:
            return NSLocalizedString("SNACK_BAR_DETAILS_BODY_NEW_APP_VERSION_AVAILABLE", comment: "")
        }
    }
    
    var primaryActionTitle: String {
        switch self {
        case .createBackupKey:
            return NSLocalizedString("CONFIGURE_BACKUPS_BUTTON_TITLE", comment: "")
        case .shouldPerformBackup:
            return NSLocalizedString("CONFIGURE_BACKUPS_BUTTON_TITLE", comment: "")
        case .shouldVerifyBackupKey:
            return NSLocalizedString("CONFIGURE_BACKUPS_BUTTON_TITLE", comment: "")
        case .grantPermissionToRecord:
            return NSLocalizedString("GRANT_PERMISSION_TO_RECORD_BUTTON_TITLE", comment: "")
        case .grantPermissionToRecordInSettings:
            return NSLocalizedString("GRANT_PERMISSION_TO_RECORD_IN_SETTINGS_BUTTON_TITLE", comment: "")
        case .upgradeIOS:
            return CommonString.Word.Ok
        case .newerAppVersionAvailable:
            return NSLocalizedString("GO_TO_APP_STORE_BUTTON_TITLE", comment: "")
        }
    }
    
    var secondaryActionTitle: String {
        switch self {
        case .createBackupKey:
            return NSLocalizedString("REMIND_ME_LATER", comment: "")
        case .shouldPerformBackup:
            return NSLocalizedString("REMIND_ME_LATER", comment: "")
        case .shouldVerifyBackupKey:
            return NSLocalizedString("REMIND_ME_LATER", comment: "")
        case .grantPermissionToRecord:
            return NSLocalizedString("REMIND_ME_LATER", comment: "")
        case .grantPermissionToRecordInSettings:
            return NSLocalizedString("REMIND_ME_LATER", comment: "")
        case .upgradeIOS:
            return NSLocalizedString("REMIND_ME_LATER", comment: "")
        case .newerAppVersionAvailable:
            return NSLocalizedString("REMIND_ME_LATER", comment: "")
        }
    }

}
