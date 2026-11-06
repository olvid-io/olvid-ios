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
import ObvPollFeature


/// The poll a message asks, in the bubble of that message.
///
/// **The poll itself is drawn by `ObvPollFeature.MessagePollContentView`, the very view the legacy screen hosts** — so this view has no layout of its own. What it does
/// is what that view cannot: follow the poll through a stream, put it in a bubble of the right colour, and turn what a reader taps into an action.
struct MessagePollBubbleView: View {

    let poll: PollInMessage
    let style: MessageBubbleStyle
    let dataSource: any SingleDiscussionCellViewDataSource
    let actions: any SingleDiscussionCellViewActions

    /// What the poll currently says, as its own stream reports it. Nil until it has said anything, and until then the bubble is drawn from ``placeholder``.
    @State private var state: MessagePollViewModel?

    /// Holds the two gestures of the drawn view, which speaks through a delegate rather than through closures. Made once and kept, so that a view redrawn does not
    /// leave the old one holding the tap.
    @State private var gestures = Gestures()

    /// How this poll says that a finger on one of its answers is on the *answer* and not on the message around it — see ``AFingerOnSomethingInsideAMessage``, and
    /// finding 18 of the 2026-08-30 review: holding an answer shrank the whole message as though a long press were beginning, and on an answer it never becomes one
    /// (measured on an iPhone 13: a two-second hold voted on release and opened no menu).
    ///
    /// Read here and handed to ``Gestures``, which is a class and cannot read an environment of its own.
    @Environment(\.aFingerOnSomethingInsideAMessage) private var aFingerOnSomethingInsideAMessage

    /// What the reader is looking for, so that a poll found by a search can show why. See ``EnvironmentValues/theWordsBeingLookedFor``.
    @Environment(\.theWordsBeingLookedFor) private var theWordsBeingLookedFor

    /// Whether a message sent shifts its blue with where it sits on the screen — see ``TheFieldTheBubblesTravelThrough``.
    @Environment(\.sentBubbleHueVariesWithScroll) private var sentBubbleHueVariesWithScroll

    /// Whether *this* bubble does: only a poll the reader sent, as in ``MessageBubbleView``.
    private var theColourTravels: Bool {
        sentBubbleHueVariesWithScroll && style == .sent
    }

    var body: some View {
        // A single-root container, so that this view stays *unary*. See `SingleDiscussionCellView`.
        VStack(spacing: 0) {
            // **Never nil, which is what keeps the row still.** Handed the model's own account of the poll until the stream speaks, this draws the question, the
            // answers and the expiry line at once — so the bubble is its final height on the frame it first appears on, and the votes arriving change only what is
            // written inside it. Passing nil here draws a spinner instead, and the row then grew by the height of a whole poll a moment later: on entering a
            // discussion ending in one, after the list had been placed at the end and revealed.
            MessagePollContentView(viewModel: state ?? placeholder,
                                   textColor: style.foregroundColor,
                                   progressColor: Self.progressColor(for: style),
                                   delegate: gestures,
                                   // **The question and the answers are both searchable**, so both may have to show a match: the text a poll leaves for clients too
                                   // old to understand one is its question followed by its numbered answers, and that text is what a search reads. Applied through a
                                   // closure so that `ObvPollFeature`, which knows nothing of persistence, need know nothing of searching either.
                                   asDrawn: { AttributedString($0).withTheWordsBeingLookedForHighlighted(theWordsBeingLookedFor) })
            // Greyed while it is the placeholder, as every other part of this screen shows something it does not know yet.
            // An empty set of reasons is no redaction at all, so this stays one unconditional modifier rather than a
            // branch, and the view keeps one shape.
            .redacted(reason: state == nil ? .placeholder : [])
            // **Nothing may be voted for before the votes are known.** The placeholder's answers are real answers with real identifiers, so a tap on one would
            // otherwise cast a genuine vote against a bubble that is still grey — and its `hasVoted` is a fiction, so the vote would be the wrong way round.
            .allowsHitTesting(state != nil)
        }
        .padding(.horizontal, MessageBubbleMetrics.horizontalInset)
        .padding(.vertical, MessageBubbleMetrics.verticalInset)
        .frame(maxWidth: MessagePollBubbleView.maxWidth, alignment: .leading)
        // **A poll's bubble travels through the field too**, from 2026-09-04 — it did not before, and among sent messages that were shifting their blue a poll
        // read as a flat patch. It draws its own background rather than going through ``MessageBubbleView``, so the fill is asked for here; the silhouette is a
        // plain rectangle because the `clipShape` below is what rounds this bubble.
        .background {
            TheColourTravelsIfAsked(asked: theColourTravels,
                                    shape: Rectangle(),
                                    colour: style.backgroundColor)
        }
        .clipShape(RoundedRectangle(cornerRadius: MessageBubbleMetrics.cornerRadius, style: .continuous))
        .task { gestures.actOn(poll, through: actions, sayingWhenAFingerIsOnAnAnswerTo: aFingerOnSomethingInsideAMessage) }
        .task(id: poll.pollIdentifier) { await followsThePoll() }
    }


    /// The poll as the *message's* model knows it: everything but the votes, which are what the stream is for.
    ///
    /// Drawn redacted, so the fictions in it are never read as facts — no answer is chosen, no share is anything but zero, and nobody has voted. What is not
    /// fiction is every measurement: see ``PollInMessage/Shape``.
    private var placeholder: MessagePollViewModel {
        .init(question: poll.shape.question,
              multipleChoice: poll.shape.multipleChoice,
              candidates: poll.shape.candidates.map({ .init(uuid: $0.uuid, text: $0.text, hasVoted: false, totalPercent: 0) }),
              expirationDate: poll.shape.expirationDate,
              totalNumberOfResponses: 0)
    }


    /// Follows the poll for as long as this view is on screen rather than taking its first answer: a vote may arrive at any moment, from any voter.
    private func followsThePoll() async {
        for await reported in dataSource.getAsyncStreamOfPollState(forPollWith: poll.pollIdentifier) {
            state = reported
        }
    }


    /// The tint of the bars, as the legacy cells pass it: white on a message sent, and half-transparent label on one received. It is only used for an answer that has
    /// no colour of its own, which in practice means a poll with more answers than there are poll colours.
    private static func progressColor(for style: MessageBubbleStyle) -> Color {
        switch style {
        case .sent: return Color(UIColor.white)
        case .received: return Color(UIColor.label).opacity(0.5)
        }
    }


    /// A poll is text, and text in a bubble is bounded as every other bubble on this screen is.
    private static let maxWidth = CGFloat(320)


    /// Turns what the drawn view reports into the actions of this screen.
    ///
    /// A class because `MessagePollContentViewDelegate` is one — it is held weakly by the view that speaks through it, that view being shared with a UIKit screen
    /// where a delegate is the natural shape.
    @MainActor
    private final class Gestures: MessagePollContentViewDelegate {

        private var poll: PollInMessage?
        private var actions: (any SingleDiscussionCellViewActions)?
        private var aFingerOnSomethingInsideAMessage: AFingerOnSomethingInsideAMessage?

        func actOn(_ poll: PollInMessage,
                   through actions: any SingleDiscussionCellViewActions,
                   sayingWhenAFingerIsOnAnAnswerTo aFingerOnSomethingInsideAMessage: AFingerOnSomethingInsideAMessage?) {
            self.poll = poll
            self.actions = actions
            self.aFingerOnSomethingInsideAMessage = aFingerOnSomethingInsideAMessage
        }


        /// Finding 18: a finger on an answer is a finger on the answer, so the message does not pretend a long press is beginning.
        func aFingerIsOnAnAnswerOfThePoll(_ isOnAnAnswer: Bool) {
            aFingerOnSomethingInsideAMessage?.thereIsAFingerOnAControl(isOnAnAnswer)
        }

        func userWantsToUpdatePollVote(_ view: MessagePollContentView, pollCandidateUUID: UUID, voted: Bool, voteSentStatus: VoteSentStatus) async throws {
            guard let poll, let actions else { return }
            let refusal: VoteSentStatus? = voteSentStatus == .canBeSent ? nil : voteSentStatus
            await actions.userWantsToActOnPoll(poll, action: .vote(candidate: pollCandidateUUID, chosen: voted, refusal: refusal))
        }

        func userWantsToDisplayPollView() async throws {
            guard let poll, let actions else { return }
            await actions.userWantsToActOnPoll(poll, action: .showThePoll)
        }

    }

}
