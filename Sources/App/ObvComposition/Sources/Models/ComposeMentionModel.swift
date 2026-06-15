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

import Foundation
import ObvDesignSystem
import ObvTypes


public struct ComposeSuggestionsModel: Sendable, Equatable {

    let mentions: [ComposeMentionSuggestionModel]
    let range: Range<AttributedString.Index>?
    
    public init(mentions: [ComposeMentionSuggestionModel], range: Range<AttributedString.Index>?) {
        self.mentions = mentions
        self.range = range
    }
}


/// View model for mentions
public struct ComposeMentionSuggestionModel: Sendable, Equatable, Hashable {
    
    public let title: String
    
    let mentionedCryptoId: ObvCryptoId
    
    let avatarModel: ObvAvatarViewModel
    
    public init(title: String, mentionedCryptoId: ObvCryptoId, avatarModel: ObvAvatarViewModel) {
        self.title = title
        self.mentionedCryptoId = mentionedCryptoId
        self.avatarModel = avatarModel
    }
}
