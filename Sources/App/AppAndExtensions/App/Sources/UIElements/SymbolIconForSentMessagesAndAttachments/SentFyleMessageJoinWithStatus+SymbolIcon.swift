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
import ObvUICoreData
import ObvSystemIcon


extension SentFyleMessageJoinWithStatus {
    
    func getSymbolIcon() -> any SymbolIcon {
        let messageHasMoreThanOneRecipient = self.sentMessage.unsortedRecipientsInfos.count > 1
        if let iconForReceptionStatus = self.receptionStatus.getSymbolIcon(messageHasMoreThanOneRecipient: messageHasMoreThanOneRecipient) {
            return iconForReceptionStatus
        } else {
            let iconForFyleStatus = self.status.getSymbolIcon(messageHasMoreThanOneRecipient: messageHasMoreThanOneRecipient)
            return iconForFyleStatus
        }
    }
    
}



private extension SentFyleMessageJoinWithStatus.FyleStatus {
    
    func getSymbolIcon(messageHasMoreThanOneRecipient: Bool) -> any SymbolIcon {
        switch self {
        case .uploadable: return SystemIcon.circleDashed
        case .uploading: return SystemIcon.arrowUpCircle
        case .complete: return CustomIcon.checkmark
        case .downloadable: return SystemIcon.arrowDownCircle
        case .downloading: return SystemIcon.arrowDownCircle
        case .cancelledByServer: return SystemIcon.exclamationmarkCircle
        }
    }
    
}


private extension SentFyleMessageJoinWithStatus.FyleReceptionStatus {
    
    func getSymbolIcon(messageHasMoreThanOneRecipient: Bool) -> (any SymbolIcon)? {
        
        switch self {

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
            
        case .none:
            return nil
            
        }
        
    }
    
}
