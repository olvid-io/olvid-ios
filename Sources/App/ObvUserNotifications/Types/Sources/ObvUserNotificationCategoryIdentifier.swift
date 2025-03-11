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

import Foundation
import UserNotifications


/// A notification *category* determines the set of *actions* that will be available on the notification.
///
/// The actions are actually defined in the `ObvUserNotificationsCreator` target.
public enum ObvUserNotificationCategoryIdentifier: String, CaseIterable {
    
    case minimal = "ObvUserNotificationCategory.minimal"
    case acceptInvite = "ObvUserNotificationCategory.acceptInvite"
    case invitationWithNoAction = "ObvUserNotificationCategory.invitationWithNoAction"
    case newMessage = "ObvUserNotificationCategory.newMessage"
    case newMessageWithLimitedVisibility = "ObvUserNotificationCategory.newMessageWithLimitedVisibility"
    case newMessageWithHiddenContent = "ObvUserNotificationCategory.newMessageWithHiddenContent"
    case missedCall = "ObvUserNotificationCategory.missedCall"
    case newReaction = "ObvUserNotificationCategory.newReaction"
    case postUserNotificationAsAnotherCallParticipantStartedCamera = "ObvUserNotificationCategory.postUserNotificationAsAnotherCallParticipantStartedCamera"
    case rejectedIncomingCallBecauseOfDeniedRecordPermission = "ObvUserNotificationCategory.rejectedIncomingCallBecauseOfDeniedRecordPermission"
    case protocolMessage = "ObvUserNotificationCategory.protocolMessage"

    
    public var categoryIdentifier: String {
        self.rawValue
    }

}

// MARK: - Making it easy to set/access an ObvUserNotificationCategory

public extension UNNotificationContent {

    var obvCategoryIdentifier: ObvUserNotificationCategoryIdentifier? {
        guard !self.categoryIdentifier.isEmpty else { return nil }
        guard let obvCategoryIdentifier = ObvUserNotificationCategoryIdentifier(rawValue: self.categoryIdentifier) else {
            assertionFailure()
            return nil
        }
        return obvCategoryIdentifier
    }
    
}

public extension UNMutableNotificationContent {

    func setObvCategoryIdentifier(to newValue: ObvUserNotificationCategoryIdentifier?) {
        self.categoryIdentifier = newValue?.categoryIdentifier ?? ""
    }
    
}
