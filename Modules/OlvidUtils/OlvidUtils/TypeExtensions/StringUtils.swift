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
import UIKit


public extension String {
    
    func extractURLs() -> [URL] {
        if let url = URL(string: self.trimmingWhitespacesAndNewlines()) {
            // On rare occasions (which we encountered while extraction invitations URLs), the data detector failed to extract a full
            // URL. For this reason, we try this simpler method first.
            return [url]
        } else {
            guard let urlDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
            let range = NSRange(location: 0, length: self.utf16.count)
            let matches = urlDetector.matches(in: self, options: [], range: range)
            let urls: [URL] = matches.compactMap { (match) -> URL? in
                guard let rangeOfMatch = Range(match.range, in: self) else { return nil }
                return URL(string: String(self[rangeOfMatch]))
            }
            return urls
        }
    }

    func trimmingWhitespacesAndNewlines() -> String {
        return trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    func trimmingWhitespacesAndNewlinesAndMapToNilIfZeroLength() -> String? {
        return trimmingWhitespacesAndNewlines().mapToNilIfZeroLength()
    }

    func mapToNilIfZeroLength() -> String? {
        return self.isEmpty ? nil : self
    }

    
    /// Returns a new string made by removing from both ends of the String white spaces and news lines. Given a set of ranges in the original string, also returns a new set of equivalent ranges in the new string.
    func trimmingWhitespacesAndNewlines(updating ranges: [Range<String.Index>]) -> (trimmedString: String, rangesInTrimmedString: [Range<String.Index>]) {
        let trimmedString = self.trimmingWhitespacesAndNewlines()
        let rangesInTrimmedString: [Range<String.Index>]
        if trimmedString == self {
            rangesInTrimmedString = ranges
        } else if !trimmedString.isEmpty {
            let trimmedStringRangeInSelf = self.range(of: trimmedString)!
            let trimmedStringOffset = self.distance(from: self.startIndex, to: trimmedStringRangeInSelf.lowerBound)
            assert(trimmedStringOffset >= 0)
            rangesInTrimmedString = ranges.map { range in
                let updatedLowerBound = range.lowerBound.utf16Offset(in: self) - trimmedStringOffset
                let updatedUpperBound = range.upperBound.utf16Offset(in: self) - trimmedStringOffset
                let updatedStartIndex = String.Index(utf16Offset: updatedLowerBound, in: trimmedString)
                let updatedEndIndex = String.Index(utf16Offset: updatedUpperBound, in: trimmedString)
                let updatedRange = Range<String.Index>(uncheckedBounds: (updatedStartIndex, updatedEndIndex))
                return updatedRange
            }
        } else {
            rangesInTrimmedString = []
        }
        return (trimmedString, rangesInTrimmedString)
    }
    
}
