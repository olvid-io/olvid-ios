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


struct MessageCellConstants {
    
    static let bubbleMaxWidth = CGFloat(241) // 2*120 + 1
    static let attachmentIconSize = CGFloat(50)
    static let singleAttachmentViewWidth = CGFloat(260) // 2*120 + 1
    
    /// Size of the contact picture for received messages within group discussions.
    static let contactPictureSize = CGFloat(30)
    
    static let bubbleVerticalInset = CGFloat(10)
    static let bubbleHorizontalInsets = CGFloat(12)
    static let replyToLineWidth = CGFloat(6)
    static let replyToImageSize = CGFloat(40)
    static let replyToBubbleMinWidth = CGFloat(100)

    static let fontForContactName = UIFont.rounded(ofSize: 17.0, weight: .bold)
    
    static let panLimitForReplyingToMessage = CGFloat(80)
    static let mainStackGap = CGFloat(2.0)
    
    static let gapBetweenContactPictureAndMessage = CGFloat(4)

    static let gapBetweenExpirationViewAndBubble = CGFloat(4)
    static let expirationIndicatorViewHeight = CGFloat(30)
    
    struct TimeIntervalForMessageDestruction {
        static let limitForRed: TimeInterval = 60
        static let limitForYellow: TimeInterval = 60*60
        static let limitForDarkGray: TimeInterval = 60*60*24
    }
    
    static let fyleProgressSize = CGFloat(44)
    
    static let cornerRadiusForInformationsViews = CGFloat(14)
    
    static let defaultGifViewSize = CGSize(width: 200, height: 150)
    
    struct BubbleView {
        static let largeCornerRadius = CGFloat(16)
        static let smallCornerRadius = CGFloat(4)
    }
}
