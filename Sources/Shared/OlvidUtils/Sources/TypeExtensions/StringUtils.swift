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
import UIKit


public extension String {
    
    func extractURLs() -> [URL] {
        let trimmed = self.trimmingWhitespacesAndNewlines()
        if !trimmed.isEmpty, trimmed.allSatisfy({ !$0.isWhitespace }), let url = URL(string: self.trimmingWhitespacesAndNewlines()) {
            // On rare occasions (which we encountered while extracting invitations URLs), the data detector failed to extract a full
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
    
}


public extension AttributedString {
    
    func trimmingWhitespacesAndNewlines() -> Self {
        var mutableSelf = self
        while mutableSelf.fistCharacterIsWhiteSpaceOrNewLine {
            let nextIndex = mutableSelf.index(afterCharacter: mutableSelf.startIndex)
            mutableSelf = AttributedString(mutableSelf[nextIndex...])
        }
        while mutableSelf.lastCharacterIsWhiteSpaceOrNewLine {
            let previousIndex = mutableSelf.index(beforeCharacter: mutableSelf.endIndex)
            mutableSelf = AttributedString(mutableSelf[..<previousIndex])
        }
        return mutableSelf
    }

    private var fistCharacterIsWhiteSpaceOrNewLine: Bool {
        self.characters.first?.isWhitespace == true
    }
    
    private var lastCharacterIsWhiteSpaceOrNewLine: Bool {
        self.characters.last?.isWhitespace == true
    }

}


public extension AttributedString {
    
    func trimWhitespacesAndNewlinesAndDropTrailingURL(_ urlToRemove: URL?) -> Self? {
        
        let trimmed = self.trimmingWhitespacesAndNewlines()
        guard !trimmed.characters.isEmpty else { return nil }
        guard let urlToRemove else { return trimmed }
        
        let urlString = urlToRemove.absoluteString
        guard self.characters.count >= urlString.count else { return trimmed }
        
        let candidateStartIndex = self.index(self.endIndex, offsetByCharacters: -urlString.count)
        guard candidateStartIndex >= self.startIndex else { assertionFailure(); return trimmed }
        
        if String(self.characters[candidateStartIndex..<self.endIndex]) == urlString {
            let stringToReturn = AttributedString(self[self.startIndex..<candidateStartIndex]).trimmingWhitespacesAndNewlines()
            guard !stringToReturn.characters.isEmpty else {
                return nil
            }
            return stringToReturn
        } else {
            return trimmed
        }

    }
    
}
