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
import CoreData
import ObvPollFeature


/// The poll a message asks: two identifiers, and the **shape** of what is going to be drawn.
///
/// The votes are not here, and never will be: they arrive through ``PollDataSource/getAsyncStreamOfPollState(forPollWith:)``, because casting one writes
/// `PersistedPollVote` objects and leaves the message and even the poll untouched — so nothing else would say so, and a vote reaching a bubble through its message
/// would cost a pass over the whole discussion each time anyone voted.
///
/// **The shape is here for one reason: a row must be its final height on the frame it first appears on.** It was not, and that was visible. Everything a poll
/// draws used to arrive through that stream, so the bubble was a spinner until the database answered and then became a question and its answers — growing by a
/// hundred points or more. On entering a discussion whose last message is a poll, that growth landed *after* the list had been placed at the end and revealed, so
/// the reader watched the discussion settle. A late resize is
/// the thing to avoid. See
/// ``GifInMessage/canvasSize``, which is the same lesson learnt on an animated image: **the model carries what decides the height, and a stream carries what
/// changes inside it.**
public struct PollInMessage: Hashable, Sendable {

    /// Identifies the **message**, which is what an action names — showing the whole poll is asked for by message, as the legacy screen asks for it.
    public let identifier: Identifier

    /// Identifies the **poll**, which is what the stream follows.
    public let pollIdentifier: Identifier

    /// What the poll is, as opposed to how it has been answered — and therefore exactly what its height depends on. See ``Shape``.
    public let shape: Shape

    public enum Identifier: Hashable, Sendable {
        /// The object ID of a `PersistedMessage` or of a `PersistedPoll`, enforced by the data source — this module knows nothing of the persistence layer. Object IDs
        /// must not escape into anything persisted or crossing a process boundary.
        case objectID(_ objectID: NSManagedObjectID)
        case forPreview(_ uuid: UUID)
    }

    /// Everything about a poll that decides how tall its bubble is, and nothing that changes as it is answered.
    ///
    /// The split is not a guess: it was read off `MessagePollContentView`, which stacks the question, one line saying whether several answers may be chosen, a row
    /// per answer, a line for the expiry *if there is one*, and a line counting the voters. So the question and the answers must be here, because text wraps and
    /// wrapping is height; the expiry must be here, because its presence adds a line and its non-expired form prints a full date that may well take two; and the
    /// votes must **not** be, because they change nothing that has a height — a chosen answer swaps a stroked circle for a filled one in the same 20pt frame, a
    /// share is a footnote on a line that exists either way, and the bar is a fixed 8pt.
    ///
    /// It is what the bubble draws *redacted* until the stream speaks, which is why it is the real facts and not a plausible-looking stand-in: a skeleton of the
    /// wrong height would be the very defect this exists to remove.
    ///
    /// **This can go stale, where the two identifiers could not**, a poll being editable: a question rewritten without the message being touched leaves the model
    /// as it was until something else rebuilds it. The consequence is bounded to nothing much — the stream is the source of truth and replaces all of this within
    /// milliseconds, so what a reader could see at worst is one greyed-out frame of a previous question. Do not build anything on it that outlives that frame.
    public struct Shape: Hashable, Sendable {

        public let question: String

        /// Whether several answers may be chosen, which decides *which* of two one-line sentences is drawn under the question — carried so that the redacted
        /// bubble draws the same one as the bubble that replaces it.
        public let multipleChoice: Bool

        /// The answers, in the order they are shown.
        public let candidates: [Candidate]

        /// When the poll closes, and nil for one that does not. Its **presence** is what matters here: it adds a line.
        public let expirationDate: Date?

        public init(question: String, multipleChoice: Bool, candidates: [Candidate], expirationDate: Date?) {
            self.question = question
            self.multipleChoice = multipleChoice
            self.candidates = candidates
            self.expirationDate = expirationDate
        }

        /// One answer, with the identity the drawn view keeps its rows by — so that the redacted rows and the rows that replace them are the *same* rows, rather
        /// than an insertion of one set and a removal of another.
        public struct Candidate: Hashable, Sendable {

            public let uuid: UUID
            public let text: String

            public init(uuid: UUID, text: String) {
                self.uuid = uuid
                self.text = text
            }

        }

    }

    public init(identifier: Identifier, pollIdentifier: Identifier, shape: Shape) {
        self.identifier = identifier
        self.pollIdentifier = pollIdentifier
        self.shape = shape
    }

}


/// What the reader can ask of a poll.
public enum PollAction: Sendable {

    /// Show the whole poll: the chart, the votes, and who has yet to vote — `ObvPollFeature.PollView`, which the legacy screen opens too.
    case showThePoll

    /// Cast or withdraw a vote for one answer.
    ///
    /// `refusal` is non-nil when the vote must **not** be sent, and says why: the view holds the poll's expiry and knows whether "None" is chosen, so it can refuse
    /// without a round trip — as the legacy screen does. An implementation is expected to tell the reader, which needs a toast and therefore belongs to the app.
    case vote(candidate: UUID, chosen: Bool, refusal: VoteSentStatus?)

}


/// What a poll is doing, and what it says.
///
/// A protocol of its own, alongside ``AttachmentProgressDataSource``, ``AudioPlaybackDataSource``, ``LinkPreviewDataSource`` and ``LocationDataSource``, so that what
/// this screen asks of its app stays legible one question at a time.
@MainActor
public protocol PollDataSource: AnyObject {

    /// Follows one poll: its question, its answers, their share of the votes, and when it ends — again each time any of that changes.
    ///
    /// **It watches the poll and its answers, and not the message showing them**, which is the whole reason it exists: a vote writes vote objects and touches neither
    /// the message nor the poll, so a screen watching only its messages would never see one arrive. The legacy screen gets away without such a stream by having the
    /// app *fault the message in the view context* after every vote — a nudge this screen cannot receive, its models being built on a background context.
    ///
    /// It yields the model `ObvPollFeature.MessagePollContentView` draws, rather than something of this module's own: the bubble is that view, shared with the legacy
    /// screen, so there is one shape for a poll and not two.
    ///
    /// **The answers arrive resolved**: in `sortIndex` order, with percentages over *voters*, and with a reader who chose "None" already shown as having chosen
    /// nothing else. None of those are decisions a view should be making.
    ///
    /// Unlike the streams of models, this one takes no `streamUUID` and has no counterpart to finish it: a caller that loses interest cancels the task it is iterating
    /// in, and the implementation is expected to tear down whatever it was watching then.
    func getAsyncStreamOfPollState(forPollWith identifier: PollInMessage.Identifier) -> AsyncStream<MessagePollViewModel>

}
