/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import OlvidUtils


public extension String {
    
    func trimmingWhitespacesAndNewlines(updating mentions: [MessageJSON.UserMention]) -> (trimmedString: String, mentionsInTrimmedString: [MessageJSON.UserMention]) {
        
        let ranges = mentions.map { $0.range }
        let (trimmedString, newRanges) = self.trimmingWhitespacesAndNewlines(updating: ranges)

        let mentionsInTrimmedString: [MessageJSON.UserMention]
        if newRanges.count == mentions.count {
            mentionsInTrimmedString = zip(mentions.map(\.mentionedCryptoId), newRanges)
                .map {
                    MessageJSON.UserMention(mentionedCryptoId: $0, range: $1)
                }
        } else {
            assertionFailure()
            mentionsInTrimmedString = []
        }
        
        return (trimmedString, mentionsInTrimmedString)
        
    }
    
}
