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
import ObvUICoreData
import ObvSettings


extension MetaFlowController {
    
    struct Strings {
        
        struct AlertChannelEstablishementRestarted {
            static let title = NSLocalizedString("The channel establishment was restarted", comment: "Alert title")
        }
        
        struct AlertChannelEstablishementRestartedFailed {
            static let title = NSLocalizedString("At least one of the channel establishment failed to restart", comment: "Alert title")
        }

        static let authorizationRequired = NSLocalizedString("Authorization Required", comment: "Alert title")
        static let cameraAccessDeniedExplanation = NSLocalizedString("Olvid is not authorized to access the camera. You can change this setting within the Settings app.", comment: "Body of an alert")
        static let goToSettingsButtonTitle = NSLocalizedString("Open Settings", comment: "Button title")

        static let deleteGroupExplanation = NSLocalizedString("Your are about to permanently delete a group.", comment: "Explanation")
        
        static let leaveGroupExplanation = NSLocalizedString("Your are about to leave a group.", comment: "Explanation")

        struct AlertDeleteOwnedGroupFailed {
            static let title = NSLocalizedString("Could not delete group", comment: "Alert title")
            static let message = NSLocalizedString("Please remove any pending/group member and try again.", comment: "Alert body")
        }
        
        struct AlertMutualIntroduction {
            static let title = NSLocalizedString("Mutual Introduction", comment: "UIAlertController title")
            static let message = { (displayNameIntroduced: String, displayNameTo: String, numberOfOther: Int) in
                String.localizedStringWithFormat(NSLocalizedString("You are about to introduce X to Y and count other contacts.", comment: "UIAlertController message"), numberOfOther, displayNameIntroduced, displayNameTo)
            }
            static let actionPerformIntroduction = NSLocalizedString("Perform the introduction", comment: "UIAlertController action")
        }
        
        struct AlertMutualIntroductionPerformedSuccessfully {
            static let title = NSLocalizedString("Contact Introduction Performed", comment: "UIAlert title")
            static let message = { (displayNameIntroduced: String, displayNameTo: String, numberOfOther: Int) in
                String.localizedStringWithFormat(NSLocalizedString("You successfully introduced X to Y and count other contacts.", comment: "UIAlertController message"), numberOfOther, displayNameIntroduced, displayNameTo)
            }
        }
        
        struct AlertSuccessfulExportToFilesApp {
            static let title = NSLocalizedString("File exported to Files App", comment: "Alert title")
        }
        
        struct AlertOutgoingCallFailedBecauseUserDeniedRecordPermission {
            static let message = NSLocalizedString("ALERT_MSG_OUTGOING_CALL_FAILED_USER_DENIED_RECORDING", comment: "Alert message")
        }

        struct AlertVoiceMessageFailedBecauseUserDeniedRecordPermission {
            static let message = NSLocalizedString("ALERT_VOICE_MESSAGE_FAILED_USER_DENIED_RECORDING", comment: "Alert message")
        }

        struct AlertRejectedIncomingCallBecauseUserDeniedRecordPermission {
            static let message = NSLocalizedString("REJECTED_INCOMING_CALL_BECAUSE_RECORD_PERMISSION_IS_DENIED", comment: "Alert message")
        }

        static let pastedStringIsNotValidOlvidURL = NSLocalizedString("PASTED_STRING_IS_NOT_VALID_OLVID_CONFIG", comment: "")  
        
        struct AppDialogOutdatedAppVersion {
            static let title = NSLocalizedString("DIALOG_TITLE_OUTDATED_VERSION", comment: "")
            static let message = NSLocalizedString("DIALOG_MESSAGE_OUTDATED_VERSION", comment: "")
            static let positiveButtonTitle = NSLocalizedString("BUTTON_LABEL_UPDATE", comment: "")
            static let negativeButtonTitle = NSLocalizedString("BUTTON_LABEL_REMIND_ME_LATER", comment: "")
        }

        struct AlertChooseHiddenProfileClosePolicy {
            static let title = NSLocalizedString("ALERT_CHOOSE_HIDDEN_PROFILE_CLOSE_POLICY_TITLE", comment: "")
            static let message = NSLocalizedString("ALERT_CHOOSE_HIDDEN_PROFILE_CLOSE_POLICY_MESSAGE", comment: "")
            static let actionScreenLock = NSLocalizedString("ALERT_CHOOSE_HIDDEN_PROFILE_CLOSE_POLICY_ACTION_SCREEN_LOCK", comment: "")
            static let actionManualSwitching = NSLocalizedString("ALERT_CHOOSE_HIDDEN_PROFILE_CLOSE_POLICY_ACTION_MANUAL_SWITCHING", comment: "")
            static let actionBackground = NSLocalizedString("ALERT_CHOOSE_HIDDEN_PROFILE_CLOSE_POLICY_ACTION_BACKGROUND", comment: "")
        }
        
        struct AlertTimeIntervalForBackgroundHiddenProfileClosePolicy {
            static let title = NSLocalizedString("TIME_INTERVAL_FOR_BG_HIDDEN_PROFILE_CLOSE_POLICY", comment: "")
            static func actionTitle(for timeInterval: ObvMessengerSettings.Privacy.TimeIntervalForBackgroundHiddenProfileClosePolicy) -> String {
                switch timeInterval {
                case .immediately:
                    return CommonString.Word.Immediately
                case .tenSeconds:
                    return NSLocalizedString("AFTER_TEN_SECONDS", comment: "")
                case .thirtySeconds:
                    return NSLocalizedString("AFTER_THIRTY_SECONDS", comment: "")
                case .oneMinute:
                    return NSLocalizedString("AFTER_ONE_MINUTE", comment: "")
                case .twoMinutes:
                    return NSLocalizedString("AFTER_TWO_MINUTE", comment: "")
                case .fiveMinutes:
                    return NSLocalizedString("AFTER_FIVE_MINUTE", comment: "")
                }
            }
        }
        
        struct AlertShouldActivateScreenLockAfterCreatingHiddenProfile {
            static let title = NSLocalizedString("ALERT_SHOULD_ACTIVATE_SCREEN_LOCK_AFTER_CREATING_HIDDEN_PROFILE_TITLE", comment: "")
            static let message = NSLocalizedString("ALERT_SHOULD_ACTIVATE_SCREEN_LOCK_AFTER_CREATING_HIDDEN_PROFILE_MESSAGE", comment: "")
            static let actionGotToPrivacySettings = NSLocalizedString("ALERT_SHOULD_ACTIVATE_SCREEN_LOCK_AFTER_CREATING_HIDDEN_PROFILE_ACTION_GOTO_PRIVACY_SETTINGS", comment: "")
        }
        
    }
    
}
