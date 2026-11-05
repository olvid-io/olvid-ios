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
import ObvEmojiUtils


/// The body of a message: a bubble, or — for a body that is nothing but a few emoji — the emoji alone, shown large.
///
/// Both kinds of cell show their body through this, so that the rule deciding between the two exists once.
struct MessageBodyView: View {

    let textBody: AttributedString?
    let style: MessageBubbleStyle

    /// What a tap on a link in the body leads to. Not `openURL`: the app decides what to do with a URL, an Olvid link being something it opens itself rather than
    /// handing to a browser.
    let actions: any SingleDiscussionCellViewActions

    /// What the reader is looking for, if they are looking for anything. Read here rather than carried in the model, for the reason
    /// ``EnvironmentValues/theWordsBeingLookedFor`` gives.
    @Environment(\.theWordsBeingLookedFor) private var theWordsBeingLookedFor

    /// The body as plain characters, which is what the emoji rule is asked of — that rule is about what was written, not about how it is marked up.
    private var plainBody: String? {
        textBody.map({ String($0.characters) })
    }

    /// What is actually drawn: the body with its lists and headings made visible, `Text` drawing only the inline half of markdown by itself. See
    /// ``AttributedString/withBlockIntentsMadeVisible()``.
    /// `map` rather than `textBody?.…`: `AttributedString` looks its attributes up by dynamic member, so an optional-chained method name is taken for the name of
    /// an attribute and fails to resolve.
    ///
    /// **The highlight comes last**, over the styling rather than under it: it is what the reader is hunting for, so it wins over a link's colour where the two land
    /// on the same characters. Costs nothing at all while nobody searches — ``TheWordsBeingLookedFor/ranges(foundIn:)`` looks for no words and returns the body
    /// untouched.
    private var bodyAsDrawn: AttributedString? {
        textBody.map({ $0.withBlockIntentsMadeVisible()
                         .withLinksAndMentionsEmphasised(inTheColour: style.foregroundColorOfALink)
                         .withTheWordsBeingLookedForHighlighted(theWordsBeingLookedFor) })
    }

    var body: some View {
        // A `Group`, so that a message with no body at all contributes **nothing** to the stack of the cell — neither a bubble around nothing, nor the empty
        // container that would still be given a gap of its own. See `MessageAudioPlayerView`, where that reasoning is written out.
        Group {
            if let plainBody, plainBody.isShownAsEmojiAlone {
                Text(verbatim: plainBody)
                    .font(.system(size: Self.emojiFontSize))
                    .lineLimit(1)
            } else if let bodyAsDrawn {
                AtMostAFractionOfTheOfferedWidth(fraction: MessageBubbleMetrics.maxWidthRatio) {
                    MessageBubbleView(style: style) {
                        // **On a Mac the body is a `UITextView`, so that it can be selected**, and the branch is the whole of the platform
                        // difference: the cap above, the bubble around it, its corners and its padding are the same views on every platform, and iOS and
                        // iPadOS compile to exactly what they compiled to before. See ``TheBodyOfAMessageThatCanBeSelected``, which explains why the
                        // one-line modifier this step was scoped around does not work here.
                        #if targetEnvironment(macCatalyst)
                        TheBodyOfAMessageThatCanBeSelected(body: bodyAsDrawn, style: style, actions: actions)
                        #else
                        Text(bodyAsDrawn)
                            // **The body states its own font, and until 2026-08-26 it did not.** Inheriting looks free and is not: the text then takes whatever
                            // the *context* resolves, and this view is drawn in two of them — in a `List` row, and again in the context menu's overlay as the
                            // copy that is lifted. Those resolve differently, so the copy's text came out **3.4% larger** than the message underneath it, and a
                            // reader dismissing the menu watched the message land and then shrink. Measured: the same view, offered the same 878.4pt, answering
                            // 619.5 in the overlay against 599.0 in the cell — and 436.0 against 451.0 at a width neither uses, which is what proved the two
                            // were never the same content.
                            //
                            // **`\.font` reads `nil` in both**, which is why the first probe here was misleading rather than wrong: it says neither rendering
                            // *sets* a font, not that the two arrive at the same one. The general lesson is the one this screen keeps relearning — a view drawn
                            // in two places must state what it depends on, or the two drift wherever the environments differ.
                            //
                            // A text **style** and not `.system(size:)`: a message body must follow Dynamic Type, a fixed point size being permitted
                            // only where the text repeats something shown another way, which a body is the opposite of.
                            .font(.body)
                            // **The body keeps every line it needs, whatever height it is offered.** A `Text` is the one thing in a cell that is flexible
                            // vertically: asked to fit into less than it wants, it drops a line and truncates rather than overflow. That is what was seen for a
                            // quarter of a second each time a message was sent — the bubble showing one truncated line and then two again.
                            //
                            // What squeezes it is a *stale* proposal. The status indicator beside the date grows the date row by a fraction of a point when it
                            // changes, and the pass that discovers this still carries the row's previous height: the stack must then fit slightly more into
                            // exactly as much, so it takes the space from the only child that will yield. Measured at the cell: proposed 78.67pt, answered
                            // 57.33pt — a drop of one whole line — and settling at 79.33pt one pass later.
                            //
                            // Fixing it here rather than at the date row is deliberate: any part of a cell may come to change size under a stale proposal, and
                            // the body should never be what pays for it.
                            .fixedSize(horizontal: false, vertical: true)
                        #endif
                    }
                }
            }
        }
        // **The app decides what a URL means**, so a link is caught here rather than left to the system: the legacy screen sends every tapped link to
        // `UIApplication.userSelectedURL(_:within:)`, which knows an Olvid invitation from an ordinary page. Returning `.handled` stops SwiftUI opening it too.
        .environment(\.openURL, OpenURLAction { url in
            Task { await actions.userWantsToOpenURLFromAMessage(url) }
            return .handled
        })
        // The colour of a link is set on the link itself rather than tinted from here — see `withLinksAndMentionsEmphasised(inTheColour:)`. The tint remains for
        // anything else SwiftUI decides to draw as interactive.
        .tint(style.foregroundColorOfALink)
        // A message the sender has edited changes under the reader, and that is worth showing rather than swapping instantly.
        //
        // Scoped to the body by `value:` rather than decided where the model is applied: everything else a message carries — its status, its reactions,
        // whatever it grows next — changes without animating, and cannot start one here by accident. A condition on the *value* also needs no revisiting when
        // the model gains a field, whereas "the models differ only by their body" would have to be re-decided every time.
        //
        // What this animates is the text, and **not the height of the cell**, which snaps. A `List` row is a self-sizing collection view cell and its new size
        // is applied outside any transaction that can be opened from within the row: measured three ways — this modifier here, the same one at the root of the
        // cell, and a `withAnimation` around the model being applied — the height snapped every time, and at the root nothing animated at all. So an edit that
        // changes how many lines a message takes still moves everything below it in one step.
        .animation(.default, value: textBody)
    }

    /// `EmojiOnlyBodyView` on the legacy screen, whose label is a plain `UIFont.systemFont(ofSize: 50)`.
    private static let emojiFontSize: CGFloat = 50

}


extension String {

    /// Whether this message body is shown as the emoji alone, large and without a bubble, rather than as text in a bubble.
    ///
    /// The rule is the legacy screen's, in `SentMessageCell` and `ReceivedMessageCell`: only emoji, and fewer than four of them. Four or more go back into a
    /// bubble, at which point they read as a message rather than as a gesture.
    ///
    /// `containsOnlyEmoji` comes from `ObvEmojiUtils` rather than being written again here: what counts as an emoji is a question with a long tail —
    /// modifiers, zero-width joiners, flags — and the answer already exists.
    var isShownAsEmojiAlone: Bool {
        containsOnlyEmoji && count < 4
    }

}
