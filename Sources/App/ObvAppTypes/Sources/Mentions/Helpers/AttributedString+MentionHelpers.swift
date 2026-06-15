/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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

extension AttributedString {
    
    /// Returns a selection adjusted to fully include any mentions intersecting it. This is typically used to ensure that mentions are always fully selected,
    /// whether the user moves the cursor or selects a range of text.
    ///
    /// - Parameter selection: The current selection to adjust.
    /// - Returns: A new `AttributedTextSelection` that snaps insertion points inside mentions to the full mention,
    ///            or expands range selections to include intersecting mention ranges.
    ///
    /// - **If the selection is an insertion point**:
    ///   If the cursor is placed inside a mention, the selection is expanded to cover the entire mention.
    ///
    /// - **If the selection is a RangeSet**:
    ///   If the selection range intersects with a mention, the selection is expanded to include the full range of the mention.
    ///   Supports complex selections (e.g., `RangeSet` for bidirectional text) by expanding all ranges in the set.
    @available(iOS 26.0, *)
    public func adjustSelectionForMentions(_ selection: AttributedTextSelection) -> AttributedTextSelection {
        switch selection.indices(in: self) {
        case .insertionPoint(let index):
            if let rangeOfMentionsAroundIndex = self.rangeOfMentionsAroundIndex(index) {
                return AttributedTextSelection(range: rangeOfMentionsAroundIndex)
            } else {
                return selection
            }
        case .ranges(let rangeSet):
            let newRangeSet = self.expandRangeSetToIncludeMentionRanges(rangeSet)
            return AttributedTextSelection(ranges: newRangeSet)
        }
    }

    
    /// Returns the range of the mention in this attributed string if the cursor is "in" the mention.
    ///
    /// If the cursor is in between two *distinct* mentions, this method returns `nil`.
    public func rangeOfMentionsAroundIndex(_ index: AttributedString.Index) -> Range<AttributedString.Index>? {
        guard let rangeBefore = self.rangeOfMentionBeforeIndex(index) else { return nil }
        guard let rangeAfter = self.rangeOfMentionAtIndex(index) else { return nil }
        return rangeBefore == rangeAfter ? rangeBefore : nil
    }

    
    /// Returns the range of the mention in the attributed string that is immediately before the cursor’s current position, if such a mention exists.
    private func rangeOfMentionBeforeIndex(_ index: AttributedString.Index) -> Range<AttributedString.Index>? {
        guard index > self.startIndex else { return nil }
        let previousIndex = self.index(index, offsetByCharacters: -1)
        return self.runs[\.mention]
            .compactMap { (mention, range) in
                guard mention != nil else { return nil }
                guard range.contains(previousIndex) else { return nil }
                return range
            }
            .first
    }

    
    /// Returns the range of the mention in the attributed string that is immediately after the cursor’s current position, if such a mention exists.
    private func rangeOfMentionAtIndex(_ index: AttributedString.Index) -> Range<AttributedString.Index>? {
        guard index < self.endIndex else { return nil }
        return self.runs[\.mention]
            .compactMap { (mention, range) in
                guard mention != nil else { return nil }
                guard range.contains(index) else { return nil }
                return range
            }
            .first
    }

    
    /// Given a range in the attributed string, return a new range, that includes the original range, but possibly expanded to include all mentions intersecting the original range.
    private func expandRangeToIncludeMentionRange(_ range: Range<AttributedString.Index>) -> Range<AttributedString.Index> {
        var lowerBound = range.lowerBound
        var upperBound = range.upperBound
        if let rangeOfMentionsAroundIndex = self.rangeOfMentionsAroundIndex(lowerBound) {
            lowerBound = min(rangeOfMentionsAroundIndex.lowerBound, lowerBound)
        }
        if let rangeOfMentionsAroundIndex = self.rangeOfMentionsAroundIndex(upperBound) {
            upperBound = max(rangeOfMentionsAroundIndex.upperBound, upperBound)
        }
        return lowerBound..<upperBound
    }

    
    @available(iOS 18.0, *)
    private func expandRangeSetToIncludeMentionRanges(_ rangeSet: RangeSet<AttributedString.Index>) -> RangeSet<AttributedString.Index> {
        let newRanges: [Range<AttributedString.Index>] = rangeSet.ranges.map { self.expandRangeToIncludeMentionRange($0) }
        return RangeSet<AttributedString.Index>(newRanges)
    }

}


extension AttributedString {
    
    /// Detect a single-character deletion that partially removes a mention and atomically remove the whole mention.
    /// - Parameters:
    ///   - oldValue: The previous attributed text value.
    ///   - newValue: The new attributed text value after the user's edit.
    /// - Returns: A tuple containing the corrected text and the insertion point index, if a partial mention deletion was handled; otherwise `nil`.
    public func fixingPartialMentionDeletionCompared(to oldValue: AttributedString) -> (text: AttributedString, insertionIndex: AttributedString.Index)? {
        // Compute the difference between the characters of the old and the new strings
        let oldCharacters = oldValue.characters
        let newCharacters = self.characters
        // We only handle single character deletion (other cases typically never happen, as they were filtered out
        // by letting the View ensure that mentions are always fully selected).
        guard oldCharacters.count == newCharacters.count + 1 else { return nil }
        let differences = newCharacters.difference(from: oldCharacters)
        guard differences.removals.count == 1, let removal = differences.removals.first else { return nil }
        switch removal {
        case .insert:
            return nil
        case .remove(offset: let offset, element: _, associatedWith: _):
            var mutableOldValue = oldValue
            guard let rangeOfMention = mutableOldValue.rangeOfMentionsAroundIndex(mutableOldValue.index(mutableOldValue.startIndex, offsetByCharacters: offset)) else { return nil }
            let numberOfCharactersBeforeMention = mutableOldValue.characters.distance(from: mutableOldValue.startIndex, to: rangeOfMention.lowerBound)
            mutableOldValue.replaceSubrange(rangeOfMention, with: AttributedString())
            let insertionIndex = mutableOldValue.index(mutableOldValue.startIndex, offsetByCharacters: numberOfCharactersBeforeMention)
            return (mutableOldValue, insertionIndex)
        }
    }
    
}
