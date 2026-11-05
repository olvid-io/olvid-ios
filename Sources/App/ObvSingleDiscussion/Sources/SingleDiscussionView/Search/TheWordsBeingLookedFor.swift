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

import SwiftUI
import UIKit


/// What the reader is looking for, as words rather than as the string they typed — and the single answer to *what counts as a match*.
///
/// **Why this exists.** The screen it replaces asks that question twice and gets two different answers. Its fetch splits what was typed into words and
/// requires **every** one of them, anywhere; its highlight then looks for the **whole typed string** as one contiguous range. So searching for two words
/// finds a message that mentions both, scrolls the reader to it, says "1 of 1" — and shows no yellow anywhere. Neither half is broken; they were never made
/// to agree.
///
/// So the splitting and the matching live here, in one type, and both consumers are handed the same instance: the fetch that selects the messages, and the
/// highlight inside one. They cannot drift apart, because there is nothing to keep in step.
///
/// **What counts as a match: case and diacritics are ignored, and nothing else is.** That is `contains[cd]`, which is what the fetch's predicate does, so
/// ``ranges(foundIn:)`` uses exactly `[.caseInsensitive, .diacriticInsensitive]` and no more. Searching for "eleve" highlights "élève".
///
/// The legacy highlight also passes `.widthInsensitive`, which its own fetch does not. **A third rule that only one half obeys is exactly what this type
/// exists to prevent**, so it is deliberately not carried over.
///
/// **Every occurrence of every word is found**, where legacy highlights only the first, `range(of:)` returning one range. Ranges belonging to different
/// words may overlap, and that is left alone: the highlight is a background colour, and applying it twice is the same as applying it once.
public struct TheWordsBeingLookedFor: Equatable, Hashable, Sendable {

    /// Never holds an empty string: what the reader typed is split on whitespace, and the gaps are dropped.
    public let words: [String]

    /// Splits what the reader typed. Spaces, tabs and newlines all separate, and any number of them together separate once.
    public init(inWhatTheReaderTyped term: String) {
        self.words = term.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Nothing to look for, which is what the screen carries whenever no search is running.
    public static let nothing = TheWordsBeingLookedFor(inWhatTheReaderTyped: "")

    /// **No words is no search, rather than a search that matches everything.** Both the fetch and the highlight must read it that way: a fetch given nothing to
    /// look for would otherwise select the whole discussion.
    public var isEmpty: Bool {
        words.isEmpty
    }

    /// Where each word is found in the given text, in no particular order, and possibly overlapping.
    ///
    /// The text to pass is the body **as it will be drawn**, not as the message stores it. Making a list visible writes its bullets and numbers into the string, so
    /// the characters the reader sees are not quite the characters the message holds, and a range measured against the stored body would land a little further left
    /// with every marker above it.
    public func ranges(foundIn text: AttributedString) -> [Range<AttributedString.Index>] {

        guard !words.isEmpty, !text.characters.isEmpty else { return [] }

        var ranges: [Range<AttributedString.Index>] = []

        for word in words {
            var lookFrom = text.startIndex
            while lookFrom < text.endIndex,
                  let found = text[lookFrom...].range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) {
                ranges.append(found)
                // A found range cannot be empty, `words` holding no empty string — but were it ever to be, stepping one character on is what keeps this from
                // looking at the same place for ever.
                lookFrom = found.upperBound > found.lowerBound ? found.upperBound : text.characters.index(after: found.lowerBound)
            }
        }

        return ranges

    }

}


// MARK: - Carrying the words down to the cells

extension EnvironmentValues {

    /// What the reader is looking for, as every message body on the screen sees it.
    ///
    /// **The environment, and deliberately not the cell model.** A model is rebuilt for every cell that changes, and the models are held in an `NSCache` keyed on
    /// the message — so a term put into one would be a value that is not a property of the message at all, poisoning that cache and costing a pass over every
    /// visible cell per keystroke. Through the environment, a body reads the term where it is drawn, finds its own ranges, and a message that holds none of the words
    /// draws itself exactly as it always did. The screen it replaces needs a whole extra piece of bookkeeping for this —
    /// `messagesContainingSearchedText`, kept only so that it knows which cells to reconfigure by hand.
    ///
    /// **Nothing changes it while nobody is searching**, which is what keeps the scroll out of this: a value that never changes rebuilds nothing.
    var theWordsBeingLookedFor: TheWordsBeingLookedFor {
        get { self[TheWordsBeingLookedForKey.self] }
        set { self[TheWordsBeingLookedForKey.self] = newValue }
    }

}


private struct TheWordsBeingLookedForKey: EnvironmentKey {
    static let defaultValue: TheWordsBeingLookedFor = .nothing
}


// MARK: - The highlight itself

extension AttributedString {

    /// The same body, with every occurrence of every word given the yellow behind it that says *this is what you were looking for*.
    ///
    /// **Applied to the body as drawn**, after its lists have been made visible and its links coloured, for the reason
    /// ``TheWordsBeingLookedFor/ranges(foundIn:)`` gives: the characters the reader sees are not quite the characters the message holds.
    ///
    /// The colours are the legacy screen's, in `withHighlightedSearchedText(_:)`: the system yellow, and **black text on it** rather than the body's own colour.
    /// Black is not a light-mode choice that dark mode was forgotten in — the background here is a fixed yellow in both appearances, so the text on it has to be
    /// dark in both.
    func withTheWordsBeingLookedForHighlighted(_ words: TheWordsBeingLookedFor) -> AttributedString {

        let rangesToHighlight = words.ranges(foundIn: self)
        guard !rangesToHighlight.isEmpty else { return self }

        var highlight = AttributeContainer()
        highlight.backgroundColor = Color(uiColor: .systemYellow)
        highlight.foregroundColor = .black

        var highlighted = self
        // Merged range by range, and overlaps left alone: two words may be found over the same characters, and a background applied twice looks like a background
        // applied once.
        for range in rangesToHighlight {
            highlighted[range].mergeAttributes(highlight)
        }

        return highlighted

    }

}
