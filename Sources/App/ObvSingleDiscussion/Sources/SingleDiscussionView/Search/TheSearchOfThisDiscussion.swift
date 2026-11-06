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
import ObvDesignSystem
import ObvSystemIcon


/// Everything the screen knows about the search the reader is performing, or is not.
///
/// Small and `Equatable` on purpose: it is held as one piece of state, so a keystroke is one change rather than three, and the screen's own body is what decides
/// what the cells are told.
struct TheSearchOfThisDiscussion: Equatable {

    /// Whether the reader has asked for a search at all. It is what swaps the composition bar for the field, and what the highlight is gated on.
    var isRunning: Bool = false

    /// What has been typed, exactly as typed. Split into words only where the words are needed, by ``TheWordsBeingLookedFor``.
    var term: String = ""

    /// What was found, or **nil while it is not yet known** — which is the whole of the difference between "no result" and "not looked yet".
    ///
    /// Without that distinction the bar says *no result* between every keystroke and its answer, so typing a word that matches a hundred messages flickers through
    /// "no result" for each letter of it. Nil is set the moment the words change, and a list is set when the fetch comes back.
    ///
    /// **Written only through ``hasFound(_:for:)`` and ``hasNotLookedYet()``**, so that it can never disagree with ``theWordsTheResultsAnswer``.
    private(set) var results: [SingleDiscussionView.CellIdentifier]?

    /// Which words ``results`` are the answer to.
    ///
    /// **It is what tells *already answered* from *not looked yet***, and the two are indistinguishable without it: `results` alone says only that something was
    /// found, never what for. See ``hasAlreadyAnswered(_:)``, which is the whole reason this is here.
    private(set) var theWordsTheResultsAnswer: TheWordsBeingLookedFor?

    /// Which result the reader is on, as a position in ``results``. Nil when there is nothing to be on.
    ///
    /// **It starts at the last, which is the newest**, because that is the result nearest where the reader already is — the screen having opened at the end of the
    /// discussion. The legacy screen starts at `results?.last` for the same reason.
    private(set) var positionInTheResults: Int?

    /// Nothing being searched for, which is how the screen starts and what cancelling returns it to.
    static let notSearching = TheSearchOfThisDiscussion()

    /// The result the reader is being shown, if any.
    var theCurrentResult: SingleDiscussionView.CellIdentifier? {
        guard let results, let positionInTheResults, results.indices.contains(positionInTheResults) else { return nil }
        return results[positionInTheResults]
    }

    /// Which result this is, as the bar says it: **counted from the newest**, so the newest match is "1 of n".
    ///
    /// That is the legacy screen's numbering — `numberOfIndexes - currentIndex` — and it follows from where a search starts rather than being a separate decision. The
    /// results themselves are oldest first, as the fetch returns them and as the discussion reads.
    var numberOfTheCurrentResult: Int? {
        guard let results, let positionInTheResults, results.indices.contains(positionInTheResults) else { return nil }
        return results.count - positionInTheResults
    }

    /// Everything that was found for these words, replacing whatever was found before, with the reader put on the newest of them.
    mutating func hasFound(_ found: [SingleDiscussionView.CellIdentifier], for words: TheWordsBeingLookedFor) {
        results = found
        positionInTheResults = found.isEmpty ? nil : found.count - 1
        theWordsTheResultsAnswer = words
    }

    /// Nothing is known about what is being looked for: no results, no position, and no words they answer.
    ///
    /// This is what makes the bar say nothing rather than *no result* while a fetch is on its way — see ``results``.
    mutating func hasNotLookedYet() {
        results = nil
        positionInTheResults = nil
        theWordsTheResultsAnswer = nil
    }

    /// Whether what is held is already the answer for these words, in which case there is nothing to look for and — the important half — **nothing to clear**.
    ///
    /// The search runs from a `.task(id:)` keyed on the words, and a `.task` is cancelled and started again whenever its view leaves the hierarchy and returns.
    /// That happens far more often than a reader would guess: pushing contact details does it, and so does opening a photograph — the same lifecycle fact that makes
    /// an `AsyncStream` behind a `.task` a trap, met from another side. A re-run that cleared the results and fetched them again would put
    /// the reader back on the *newest* match — ``hasFound(_:for:)`` starting there — so stepping five matches back and glancing at a contact card threw the
    /// transcript away from what was being read. Asking whether the answer is already held makes the re-run cost nothing and change nothing.
    func hasAlreadyAnswered(_ words: TheWordsBeingLookedFor) -> Bool {
        results != nil && theWordsTheResultsAnswer == words
    }

    /// Towards **older** messages, which is up the transcript, wrapping at the oldest.
    ///
    /// This is what the legacy screen calls *find next*, and what its **up** chevron does. Worth stating plainly, because the words pull the other way: the "next"
    /// result is the one further *back* in the discussion.
    mutating func goesToTheNextResult() {
        movesBy(-1)
    }

    /// Towards **newer** messages, which is down the transcript, wrapping at the newest. Legacy's *find previous*, and its **down** chevron.
    mutating func goesToThePreviousResult() {
        movesBy(+1)
    }

    /// Moves by one result and wraps at both ends.
    ///
    /// The remainder is taken **after** adding the count, rather than corrected afterwards: `(0 - 1) % n` is `-1` in Swift, not `n - 1`, so the obvious arithmetic
    /// indexes out of bounds at exactly the moment it should wrap. The legacy screen writes the same thing as a correction after the fact.
    private mutating func movesBy(_ step: Int) {
        guard let results, !results.isEmpty, let positionInTheResults else { return }
        self.positionInTheResults = (positionInTheResults + step + results.count) % results.count
    }

    /// What the cells are told to look for.
    ///
    /// **Nothing at all unless a search is running**, whatever `term` happens to hold. So cancelling takes every highlight off the screen on the same frame, with no
    /// need to clear the text first — and the environment carries an empty value at every other moment of this screen's life.
    var words: TheWordsBeingLookedFor {
        isRunning ? TheWordsBeingLookedFor(inWhatTheReaderTyped: term) : .nothing
    }

}


/// The field the reader types a search into, which takes the composition bar's place for as long as the search lasts.
///
/// ## Why it is here and not in the navigation bar
///
/// The screen it replaces puts a `UISearchController` in the navigation bar. A spike of `.searchable` established that the same place is not available to us — a
/// SwiftUI screen hosted in a UIKit navigation controller gets the bar's *drawer*, which is revealed by pulling the discussion down past its top, and this screen
/// opens at the **end** of a discussion that may hold tens of thousands of messages. Its top is not somewhere a reader can reach.
///
/// The bottom of the screen is where iOS 26 puts a search field on iPhone anyway, and the usual reason to prefer the top — that the bottom is occupied — does not
/// apply here, because a search *replaces* the composition bar. So this is not a workaround: it is the recommended place, available to us precisely when it is
/// needed.
///
/// It also means **no part of a search moves the list**, which is what keeps the scrolling of this screen out of this feature entirely.
struct TheSearchBarOfThisDiscussion: View {

    @Binding var term: String

    /// What was found, or nil while the answer is still being waited for. See ``TheSearchOfThisDiscussion/results``.
    let numberOfResults: Int?

    /// Which result the reader is on, counted from the newest. See ``TheSearchOfThisDiscussion/numberOfTheCurrentResult``.
    let numberOfTheCurrentResult: Int?

    /// Towards older messages, up the transcript. See ``TheSearchOfThisDiscussion/goesToTheNextResult()``.
    let goToTheNextResult: () -> Void

    /// Towards newer messages, down the transcript.
    let goToThePreviousResult: () -> Void

    let cancel: () -> Void

    /// Whether there is anywhere to go, which is what greys the chevrons out.
    private var thereAreResults: Bool {
        (numberOfResults ?? 0) > 0
    }

    /// Focused as soon as the bar appears: the reader asked for a search, so the keyboard is what they want next. The legacy screen does the same, by making its
    /// search bar the first responder in `didPresentSearchController`.
    @FocusState private var theFieldHasFocus: Bool

    var body: some View {
        HStack(spacing: 12) {

            HStack(spacing: 6) {

                // `Text(Image(...))` rather than `Image(...)`: an image is laid out as an image and its box is taller than a line of the font beside it, which makes
                // the row taller than the field needs. As a glyph on the line it costs exactly nothing. See `MessageEditedBadgeView`.
                Text(Image(systemIcon: .magnifyingglass))
                    .foregroundStyle(.secondary)

                // **One word, which is what the screen this replaces says too.** Legacy sets no placeholder at all, so its field shows `UISearchBar`'s own default —
                // the system's localised *Search*. "Search this discussion" was an invention of ours, and it does not fit: three capsules share this bar, so the field
                // is a little over half its width and the sentence was truncated even on the widest iPhone. There is nothing else in the app a search field could mean
                // here, the discussion being what fills the screen behind it.
                TextField(text: $term) {
                    Text("Search")
                }
                .focused($theFieldHasFocus)
                .submitLabel(.search)
                // A search is not a sentence: the first letter of a name is as likely as not, and correcting what somebody is hunting for is worse than useless.
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

                // A `Group`, not a container: with nothing to say it must take no space, and a container that holds nothing is still a subview the stack puts its
                // spacing around.
                Group {
                    whatWasFound
                }

            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .modifier(OnAPieceOfGlass())

            // **Up goes to older messages and down to newer**, which is the legacy screen's arrangement and the only one that matches what the reader sees moving.
            // The shortcuts are the system's own for find-next and find-previous, and they are put on the buttons that do the same thing so there is one
            // implementation rather than two.
            //
            // The two of them share **one** piece of glass, being one control with two directions, where Cancel has its own: it does something else entirely, and
            // grouping it with them would say it belonged to stepping through the results.
            // **The padding is inside each button and the shape is declared**, which is not tidiness: SwiftUI hit-tests what is *drawn*, and the capsule behind
            // these is a `.background`, which takes no part in hit testing. Applied outside the buttons — as this was until 2026-08-17 — the only thing answering a
            // click was the chevron itself, and everything around it was decoration that let the click through to the transcript behind the bar. Found on the
            // trash of the selection bar, where the same construction deselected a message; these had it too, and less visibly, a word being a larger target than
            // a glyph. See `TheButtonBackToTheEnd`, where the rule is written down.
            HStack(spacing: 4) {
                Button(action: goToTheNextResult) {
                    Text(Image(systemIcon: .chevronUp))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(.rect)
                }
                .keyboardShortcut("g", modifiers: .command)
                Button(action: goToThePreviousResult) {
                    Text(Image(systemIcon: .chevronDown))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(.rect)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            }
            .buttonStyle(.plain)
            .foregroundStyle(thereAreResults ? Color.accentColor : Color.secondary)
            .disabled(!thereAreResults)
            .modifier(OnAPieceOfGlass())

            Button(action: cancel) {
                Text("Cancel")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .modifier(OnAPieceOfGlass())

        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onAppear {
            theFieldHasFocus = true
        }
    }


    /// Which result of how many, `No result`, or nothing at all while there is nothing to say.
    ///
    /// **Counted from the newest**, so the match nearest where the reader was standing is "1 of n" — see ``TheSearchOfThisDiscussion/numberOfTheCurrentResult``. The
    /// numbering is the legacy screen's string. The other is not: legacy says *No message found 🥲* in a bar the width of the screen, where a sentence fits, and this
    /// sits in a capsule beside the field, where it reads as a status rather than as a message.
    ///
    /// **It keeps its one line whatever it is given**, which is a layout rule and not a matter of wording. In this capsule the flexible thing is the field, and a
    /// `Text` is what an `HStack` takes space from when there is not enough — so the message wrapped onto a second line while the field kept its width, which is the
    /// wrong way round: the field can afford to be narrower for as long as there is something to say. Shortening the English alone would have hidden that until a
    /// longer translation brought it back, German being half again as long.
    @ViewBuilder
    private var whatWasFound: some View {
        if term.isEmpty {
            // Nothing asked for, so nothing answered.
            EmptyView()
        } else if let numberOfResults {
            if numberOfResults == 0 {
                theStatus(Text("SEARCH_NO_RESULT"))
            } else if let numberOfTheCurrentResult {
                theStatus(Text("RESULT_NUMBER_\(numberOfTheCurrentResult)_OF_\(numberOfResults)").monospacedDigit())
            } else {
                EmptyView()
            }
        } else {
            // Typed, and not yet answered. Deliberately not a spinner: a search takes a fraction of a second, and something appearing and vanishing at that rate
            // reads as a fault rather than as progress.
            EmptyView()
        }
    }


    /// How anything said beside the field is drawn: quietly, on one line, and never squeezed. See ``whatWasFound``.
    private func theStatus(_ text: Text) -> some View {
        text
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

}


/// A capsule of glass under a piece of a bar that stands where the composition bar does, so that it can be read whatever the messages behind it happen to be.
///
/// **Three pieces, three capsules** in the search bar: the field, the two chevrons together, and Cancel. The bar is deliberately given no background of its own — the
/// messages are meant to be seen through it, as they are through the composition bar it replaces — and the cost of that is a control drawn straight onto whatever is
/// underneath. A dark photograph behind a chevron leaves nothing to see.
///
/// **Not wrapped in a `GlassEffectContainer`.** That exists to let nearby pieces of glass blend into one another, and these must not: two capsules 12pt apart would
/// merge into a single shape, which is the opposite of saying that stepping through the results and abandoning the search are different things.
///
/// Glass from iOS 26, and `thinMaterial` before it, following ``SingleDiscussionHeaderView`` — the same choice, made in the same way, for the same bar.
///
/// **Not `private`, since Step 42a**: ``TheBarForSelectingSeveralMessages`` stands in the same place, under the same messages, with the same problem, and two bars
/// that swap with one another had better not disagree about what they are made of.
struct OnAPieceOfGlass: ViewModifier {

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
                .background(Capsule().fill(.thinMaterial))
        }
    }

}
