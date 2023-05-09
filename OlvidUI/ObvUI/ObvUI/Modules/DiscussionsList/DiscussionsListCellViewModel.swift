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


public class DiscussionsListCellViewModel: NSObject {
    let numberOfNewReceivedMessages: Int
    let circledInitialsConfig: CircledInitialsConfiguration?
    let shouldMuteNotifications: Bool
    let title: String
    let subtitle: String
    let isSubtitleInItalics: Bool
    let timestampOfLastMessage: String
    
    public init(numberOfNewReceivedMessages: Int, circledInitialsConfig: CircledInitialsConfiguration?, shouldMuteNotifications: Bool, title: String, subtitle: String, isSubtitleInItalics: Bool, timestampOfLastMessage: String) {
        self.numberOfNewReceivedMessages = numberOfNewReceivedMessages
        self.circledInitialsConfig = circledInitialsConfig
        self.shouldMuteNotifications = shouldMuteNotifications
        self.title = title
        self.subtitle = subtitle
        self.isSubtitleInItalics = isSubtitleInItalics
        self.timestampOfLastMessage = timestampOfLastMessage
    }
}
