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

import SwiftUI
import ObvUICoreData
import ObvSystemIcon



extension PersistedMessageSent.MessageStatus {
    
    func getSymbolIcon(messageHasMoreThanOneRecipient: Bool) -> any SymbolIcon {
        
        switch self {

        case .sentFromAnotherOwnedDevice:
            return SystemIcon.iphoneGen3CircleFill

        case .hasNoRecipient:
            return SystemIcon.circle

        case .couldNotBeSentToOneOrMoreRecipients:
            return SystemIcon.exclamationmarkCircle

        case .fullyDeliveredAndFullyRead:
            return messageHasMoreThanOneRecipient ? CustomIcon.checkmarkDoubleCircleFill : CustomIcon.checkmarkCircleFill

        case .fullyDeliveredAndPartiallyRead:
            return messageHasMoreThanOneRecipient ? CustomIcon.checkmarkDoubleCircleHalfFill : CustomIcon.checkmarkCircleFill

        case .fullyDeliveredAndNotRead:
            return messageHasMoreThanOneRecipient ? CustomIcon.checkmarkDoubleCircle : CustomIcon.checkmarkCircle

        case .partiallyDeliveredAndPartiallyRead:
            return CustomIcon.checkmarkCircleFill
            
        case .partiallyDeliveredNotRead:
            return CustomIcon.checkmarkCircle

        case .sent:
            return CustomIcon.checkmark
            
        case .processing:
            return SystemIcon.hare
            
        case .unprocessed:
            return SystemIcon.hourglass
            
        }
        
    }
    
    
    func getLocalizedStringKey(messageHasMoreThanOneRecipient: Bool) -> LocalizedStringKey {
        
        switch self {
            
        case .sentFromAnotherOwnedDevice:
            return "SENT_MESSAGE_STATUS_KIND_SENT_FROM_ANOTHER_OWNED_DEVICE"
            
        case .hasNoRecipient:
            return "SENT_MESSAGE_STATUS_KIND_HAS_NO_RECIPIENT"
            
        case .couldNotBeSentToOneOrMoreRecipients:
            if messageHasMoreThanOneRecipient {
                return "SENT_MESSAGE_STATUS_KIND_COULD_NOT_BE_SENT_TO_ONE_OR_MORE_RECIPIENTS_MORE_THAN_ONE_RECIPIENT"
            } else {
                return "SENT_MESSAGE_STATUS_KIND_COULD_NOT_BE_SENT_TO_ONE_OR_MORE_RECIPIENTS_NOT_MORE_THAN_ONE_RECIPIENT"
            }
            
        case .fullyDeliveredAndFullyRead:
            if messageHasMoreThanOneRecipient {
                return "SENT_MESSAGE_STATUS_KIND_FULLY_DELIVERED_AND_FULLY_READ_MORE_THAN_ONE_RECIPIENT"
            } else {
                return "SENT_MESSAGE_STATUS_KIND_FULLY_DELIVERED_AND_FULLY_READ_NOT_MORE_THAN_ONE_RECIPIENT"
            }
            
        case .fullyDeliveredAndPartiallyRead:
            if messageHasMoreThanOneRecipient {
                return "SENT_MESSAGE_STATUS_KIND_FULLY_DELIVERED_AND_PARTIALLY_READ_MORE_THAN_ONE_RECIPIENT"
            } else {
                return "SENT_MESSAGE_STATUS_KIND_FULLY_DELIVERED_AND_PARTIALLY_READ_NOT_MORE_THAN_ONE_RECIPIENT"
            }
            
        case .fullyDeliveredAndNotRead:
            if messageHasMoreThanOneRecipient {
                return "SENT_MESSAGE_STATUS_KIND_FULLY_DELIVERED_AND_NOT_READ_MORE_THAN_ONE_RECIPIENT"
            } else {
                return "SENT_MESSAGE_STATUS_KIND_FULLY_DELIVERED_AND_NOT_READ_NOT_MORE_THAN_ONE_RECIPIENT"
            }
            
        case .partiallyDeliveredAndPartiallyRead:
            return "SENT_MESSAGE_STATUS_KIND_PARTIALLY_DELIVERED_AND_PARTIALLY_READ"
            
        case .partiallyDeliveredNotRead:
            return "SENT_MESSAGE_STATUS_KIND_PARTIALLY_DELIVERED_NOT_READ"
            
        case .sent:
            return "SENT_MESSAGE_STATUS_KIND_SENT"
            
        case .processing:
            return "SENT_MESSAGE_STATUS_KIND_PROCESSING"
            
        case .unprocessed:
            return "SENT_MESSAGE_STATUS_KIND_UNPROCESSED"
            
        }

        
    }
    
}
