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

import UIKit

enum OlvidTextInputTypes {
    struct LookupResult {
        let prefix: String

        let word: String

        let range: Range<String.Index>
    }
}

protocol OlvidTextInput: UITextInput {
    var olvid_caretNSRange: NSRange { get }

    var olvid_caretRange: Range<String.Index> { get }

    func olvid_word(at nsRange: NSRange) -> (result: String, range: Range<String.Index>)?

    //func olvid_word(at range: Range<String.Index>) -> (result: String, range: Range<String.Index>)?

    func olvid_lookup(for prefixes: Set<String>, excludedRanges: Set<NSRange>) -> OlvidTextInputTypes.LookupResult?
}

extension UITextView: OlvidTextInput {
    var olvid_caretNSRange: NSRange {
        guard let selectedTextRange else {
            return .init(location: 0, length: 0)
        }

        let selectionStart = selectedTextRange.start

        let selectionEnd = selectedTextRange.end

        return NSRange(location: offset(from: beginningOfDocument, to: selectionStart), length: offset(from: selectionStart, to: selectionEnd))
    }

    var olvid_caretRange: Range<String.Index> {
        guard let swiftRange = Range(olvid_caretNSRange, in: text) else {
            return text.startIndex..<text.startIndex
        }

        return swiftRange
    }

    func olvid_word(at nsRange: NSRange) -> (result: String, range: Range<String.Index>)? {
        guard let text,
              let result = text.word(at: nsRange) else {
            return nil
        }

        return (result.word, result.range)
    }

//    func olvid_word(at range: Range<String.Index>) -> (result: String, range: Range<String.Index>)? {
//        guard let text,
//              text.isEmpty == false else {
//            return nil
//        }
//
//        let lhs = text[..<range.lowerBound]
//
//        let lhsComponents = lhs.components(separatedBy: .whitespacesAndNewlines)
//
//        let lhsWord = lhsComponents.last!
//
//        let rhs = text[range.lowerBound...]
//
//        let rhsComponents = rhs.components(separatedBy: .whitespacesAndNewlines)
//
//        let rhsWord = rhsComponents.first!
//
//        if range.lowerBound > text.startIndex {
//            let characterBeforeCursor = text[text.index(before: range.lowerBound)..<range.lowerBound]
//
//            if let whitespaceRange = characterBeforeCursor.rangeOfCharacter(from: .whitespaces),
//               text.distance(from: whitespaceRange.lowerBound, to: whitespaceRange.upperBound) == 1 {
//                let rhsRange = Range<String.Index>(uncheckedBounds: (lower: range.lowerBound, upper: text.index(range.lowerBound, offsetBy: rhsWord.count)))
//
//                return (rhsWord, rhsRange)
//            }
//        }
//
//        let word = lhsWord.appending(rhsWord)
//
//        if word.contains("\n") {
//            return (word.components(separatedBy: .newlines).last!, text.range(of: word)!)
//        }
//
//        let range = text.index(range.lowerBound, offsetBy: -lhsWord.count)..<text.index(range.lowerBound, offsetBy: rhsWord.count)
//
//        return (word, range)
//    }

    func olvid_lookup(for prefixes: Set<String>, excludedRanges: Set<NSRange>) -> OlvidTextInputTypes.LookupResult? {
        guard prefixes.isEmpty == false else {
            return nil
        }

        guard let (word, range) = olvid_word(at: olvid_caretNSRange) else {
            return nil
        }

        let rangeIsExcluded: Bool = {
            let nsRange = NSRange(range, in: text)

            if excludedRanges.contains(nsRange) {
                return true
            }

            for aRange in excludedRanges {
                if aRange.intersection(nsRange) != nil {
                    return true
                }
            }

            return false
        }()

        guard rangeIsExcluded == false else {
            return nil
        }

        for aPrefix in prefixes {
            if word.hasPrefix(aPrefix) {
                return .init(prefix: aPrefix,
                             word: word,
                             range: range)
            }
        }

        return nil
    }
}

extension String {
    func wordParts(_ range: Range<String.Index>) -> (left: String.SubSequence, right: String.SubSequence)? {
        let whitespace = NSCharacterSet.whitespacesAndNewlines
        let leftView = self[..<range.upperBound]
        let leftIndex = leftView.rangeOfCharacter(from: whitespace, options: .backwards)?.upperBound
            ?? leftView.startIndex

        let rightView = self[range.upperBound...]
        let rightIndex = rightView.rangeOfCharacter(from: whitespace)?.lowerBound
            ?? endIndex

        return (leftView[leftIndex...], rightView[..<rightIndex])
    }

    func word(at nsrange: NSRange) -> (word: String, range: Range<String.Index>)? {
        guard !isEmpty,
            let range = Range(nsrange, in: self),
            let parts = self.wordParts(range)
            else { return nil }

        // if the left-next character is whitespace, the "right word part" is the full word
        // short circuit with the right word part + its range
        if let characterBeforeRange = index(range.lowerBound, offsetBy: -1, limitedBy: startIndex),
            let character = self[characterBeforeRange].unicodeScalars.first,
            NSCharacterSet.whitespaces.contains(character) {
            let right = parts.right
            return (String(right), right.startIndex ..< right.endIndex)
        }

        let joinedWord = String(parts.left + parts.right)
        guard !joinedWord.isEmpty else { return nil }

        return (joinedWord, parts.left.startIndex ..< parts.right.endIndex)
    }

}
