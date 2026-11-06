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


extension AttributedString {

    /// The blocks of a markdown body made *visible*: a bullet before each item of a list, a number before each item of an ordered one, and a heading drawn as a
    /// heading.
    ///
    /// **`Text` renders inline intents and ignores block ones.** Bold, italic and strikethrough come out of `AttributedString` already styled; a list, an ordered
    /// list and a heading arrive as `presentationIntent` and are drawn as ordinary paragraphs — which is why a message written as a list showed as lines with no
    /// bullets and no numbers, and a heading as plain text.
    ///
    /// The legacy screen has the same intents and a different way out of it: it builds `NSTextList`s, hangs them off `NSParagraphStyle.textLists`, and lets
    /// **TextKit 2** draw the markers and the indentation. That is a `UITextView` capability and there is nothing equivalent here — `Text` has no paragraph style —
    /// so the markers are written into the string instead, and the headings are given fonts.
    ///
    /// What that costs, and it is worth knowing rather than discovering: a marker is *text*, so the second line of a long list item wraps under the bullet rather
    /// than under the words. TextKit hangs the marker outside the paragraph and this cannot. Nesting is shown by indenting with spaces, for the same reason.
    func withBlockIntentsMadeVisible() -> AttributedString {

        var result = AttributedString()

        for (intent, range) in self.runs[\.presentationIntent] {

            var block = AttributedString(self[range])

            guard let intent else {
                result += block
                continue
            }

            // A heading is a font, as it is on the legacy screen: bold `title2`, `title3`, then `headline` — and the air above it, which there is
            // `paragraphSpacingBefore` and here has to be a line of its own. See ``spacerAbove(aHeaderAtLevel:)``.
            if let level = intent.levelOfTheHeader {
                if !result.characters.isEmpty {
                    result += Self.spacerAbove(aHeaderAtLevel: level)
                }
                block.font = Self.fontOfAHeader(atLevel: level)
            }

            // A list item is a marker written in front of it. The *innermost* list decides whether that marker is a bullet or a number — the components run from
            // outermost to innermost — and how many lists it sits inside decides how far it is indented.
            if let list = intent.innermostList {
                let marker: String
                switch list {
                case .unordered:
                    marker = "•  "
                case .ordered:
                    marker = "\(intent.ordinalOfTheListItem ?? 1).  "
                }
                let indentation = String(repeating: "    ", count: max(0, intent.numberOfListsItSitsIn - 1))
                block = AttributedString(indentation + marker) + block
            }

            result += block

        }

        return result

    }


    /// `fontDescriptorForTitle(level:)` on the legacy screen, in SwiftUI's terms.
    private static func fontOfAHeader(atLevel level: Int) -> Font {
        switch level {
        case 1: return .title2.bold()
        case 2: return .title3.bold()
        default: return .headline
        }
    }


    /// The air above a heading, as a line of its own.
    ///
    /// The legacy screen asks for `paragraphSpacingBefore` — the heading's own point size times **1**, **¾** or **½** by level — which `Text` has no way of
    /// expressing: there is no paragraph style, and `lineSpacing` would space every line of the message equally. So the space is an empty line, given the font
    /// whose *line height* comes to the wanted number. The point sizes are read from the text styles rather than written down, so this follows the reader's text
    /// size exactly as the legacy screen does.
    ///
    /// Nothing is added above a heading that opens a message: there is nothing to be spaced from, and the bubble has its own inset.
    private static func spacerAbove(aHeaderAtLevel level: Int) -> AttributedString {
        let textStyle: UIFont.TextStyle
        let proportion: CGFloat
        switch level {
        case 1: textStyle = .title2; proportion = 1
        case 2: textStyle = .title3; proportion = 0.75
        default: textStyle = .headline; proportion = 0.5
        }
        let wantedHeight = UIFont.preferredFont(forTextStyle: textStyle).pointSize * proportion
        var spacer = AttributedString("\n")
        spacer.font = .system(size: Self.sizeOfAFontWhoseLineIs(high: wantedHeight))
        return spacer
    }


    /// The point size a system font needs for one of its lines to be `high` points tall. A line is what an empty line costs, and a line is what there is to work
    /// with — so the spacing asked for is turned into the size that produces it, rather than guessed at with a constant.
    private static func sizeOfAFontWhoseLineIs(high wantedHeight: CGFloat) -> CGFloat {
        let reference = UIFont.systemFont(ofSize: 100)
        guard reference.lineHeight > 0 else { return wantedHeight }
        return max(1, wantedHeight * 100 / reference.lineHeight)
    }

}


private extension PresentationIntent {

    enum ListKind {
        case unordered
        case ordered
    }

    /// The list this block sits directly inside, and nil for a block that is not a list item at all. The components run from outermost to innermost, so the last
    /// list among them is the one whose marker is drawn.
    var innermostList: ListKind? {
        var innermost: ListKind?
        for component in components {
            switch component.kind {
            case .unorderedList: innermost = .unordered
            case .orderedList: innermost = .ordered
            default: break
            }
        }
        return innermost
    }

    /// How many lists this block sits inside, which is what its indentation is made of.
    var numberOfListsItSitsIn: Int {
        components.reduce(0) { count, component in
            switch component.kind {
            case .unorderedList, .orderedList: return count + 1
            default: return count
            }
        }
    }

    /// Which number this item is, as the parser counted it — so that a reader who wrote every item as `1.` still sees 1, 2, 3.
    var ordinalOfTheListItem: Int? {
        for component in components {
            if case .listItem(let ordinal) = component.kind { return ordinal }
        }
        return nil
    }

    /// The level of the heading this block is, and nil for a block that is not one.
    var levelOfTheHeader: Int? {
        for component in components {
            if case .header(let level) = component.kind { return level }
        }
        return nil
    }

}
