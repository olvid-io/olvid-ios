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
import CoreData
import ObvAppTypes
import ObvDesignSystem
import ObvTypes
import ObvPollFeature


// MARK: - SingleDiscussionView's data source

@MainActor
public protocol SingleDiscussionViewDataSource: Sendable {

    /// Everything known synchronously when the screen is created, so that it neither appears empty nor as a screenful of skeletons before the streams
    /// produce their first models. Called by the owner of the view (the hosting view controller), never from within `SingleDiscussionView.init`.
    ///
    /// Both are returned by a single call so that they are necessarily consistent, as of one and the same instant.
    func getInitialSingleDiscussionViewModelAndValues(discussionIdentifier: ObvDiscussionIdentifier) throws -> (model: SingleDiscussionView.Model, initialValues: SingleDiscussionView.InitialValues)

    func getAsyncStreamOfSingleDiscussionViewModel(discussionIdentifier: ObvDiscussionIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<SingleDiscussionView.Model>)

    func finishAsyncStreamOfSingleDiscussionViewModel(discussionIdentifier: ObvDiscussionIdentifier, streamUUID: UUID)

    /// Follows who the reader is talking to: the name above the discussion, the line under it, and the picture beside them.
    ///
    /// **A stream of its own, and not part of the model above**, because it is made of different objects entirely — the contact, the group, the discussion — and
    /// because it changes on its own cadence: a contact renamed changes the header and not one message. Folding it into the model of the list would rebuild the
    /// list's identifiers every time somebody edited a group's name.
    ///
    /// It is what keeps the header from going stale, which the screen it replaces cannot claim: that one reads `discussion.title` once, in `init`.
    func getAsyncStreamOfDiscussionHeader(discussionIdentifier: ObvDiscussionIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<DiscussionHeader>)

    func finishAsyncStreamOfDiscussionHeader(discussionIdentifier: ObvDiscussionIdentifier, streamUUID: UUID)

    /// The messages of this discussion holding **every** one of these words, oldest first. Empty when there is nothing to look for.
    ///
    /// **Identifiers and nothing heavier**, as everywhere else on this screen: what comes back is what the list is keyed on, so a result can be scrolled to with no
    /// further lookup, and a search over a long discussion costs a fetch of object IDs rather than a screenful of models.
    ///
    /// **The words arrive already split**, by ``TheWordsBeingLookedFor``, which also decides what counts as a match. That is not a detail of convenience: the screen
    /// this replaces splits the words for its fetch and looks for the whole typed string in its highlight, so a two-word search highlights nothing. One type answers
    /// the question for both halves here.
    ///
    /// **Called on every change of the term**, so the caller is the one that waits: the debounce belongs to the view, and this does the work it is asked for.
    func getCellIdentifiersOfMessages(matching words: TheWordsBeingLookedFor, discussionIdentifier: ObvDiscussionIdentifier) async throws -> [SingleDiscussionView.CellIdentifier]

    /// What may be done to these messages, the reader having asked to delete them. See ``WhatCanBeDeleted``.
    ///
    /// **All of them or none.** A kind is on offer only if *every* message in the selection can be deleted that way, which is what the reader is promised by
    /// being shown one button for the lot. An implementation is expected to arrive at that by simulating the deletion of the whole set once per kind, and not
    /// once per message: the per-message question creates a child context for each kind it tries, so a selection of two hundred asked message by message is six
    /// hundred child contexts on the main thread, where the plural question is three.
    ///
    /// **Asked when the trash is tapped, and never as the selection changes.** It is not cheap and it is not meant to be — the answer is wanted once, at the
    /// moment the reader asks for it.
    ///
    /// An empty set of kinds is a legitimate answer and means what it says: nothing here can be deleted. The screen says so rather than showing a button that
    /// does nothing.
    func whatCanBeDeleted(cellIdentifiers: Set<SingleDiscussionView.CellIdentifier>, discussionIdentifier: ObvDiscussionIdentifier) async -> WhatCanBeDeleted

    /// Whether these messages may be forwarded, the reader having asked to. See ``WhatCanBeForwarded``.
    ///
    /// **All of them or none**, as with the deletion above, and for a plainer reason: one Forward over a whole selection promises that the whole selection goes.
    /// Sending the eligible ones and quietly dropping the rest would leave the reader believing they had sent something they had not, and the chooser covers the
    /// transcript they would otherwise check against.
    ///
    /// **Cheap, unlike ``whatCanBeDeleted(cellIdentifiers:discussionIdentifier:)``.** The rule behind this is plain property reads — nothing is simulated and no
    /// child context is made — so an implementation is expected to loop over the selection and answer. It is asked when Forward is tapped all the same, rather
    /// than as the ticks change: the answer is wanted once, at the moment the reader asks for it, and it wants the view context on the main thread.
    ///
    /// A refusal carries **one** reason, and it is the reason for the *selection* rather than for a particular message — see ``WhatCanBeForwarded/Reason``.
    func whatCanBeForwarded(cellIdentifiers: Set<SingleDiscussionView.CellIdentifier>, discussionIdentifier: ObvDiscussionIdentifier) async -> WhatCanBeForwarded

}


// MARK: - SingleDiscussionView's actions

/// What the **screen** asks of its owner, as opposed to what its cells do.
///
/// It exists so that the hosting controller need not: a `UIHostingController` is kept to what UIKit insists on, and the lifecycle of this screen is announced by the
/// screen itself. That is what survives this migration — these views exist to *become* the whole screen, and behaviour left in a controller is behaviour to move
/// again when the controller goes away.
@MainActor
public protocol SingleDiscussionViewActions: AnyObject {

    /// The reader is looking at this discussion.
    ///
    /// **Must be safe to say twice.** It is said again whenever the reader comes back from something shown on top of this screen — a gallery, a contact's details,
    /// the full-screen map — exactly as the legacy screen's `viewWillAppear` is.
    func discussionAppeared(discussionIdentifier: ObvDiscussionIdentifier)

    /// **The reader pressed Esc and this screen had nothing of its own to dismiss**.
    ///
    /// The screen answers Esc for the three things it owns — the context menu overlay, a search, and select mode — and says this when none of them was up. What
    /// is left belongs to the app: the **reply draft**, which arrives from the app's own data source and is removed through `userWantstoRemoveReplyToMessage`,
    /// this screen seeing the composition bar only as an opaque view. Anything **presented over** the screen answers Esc for itself.
    ///
    /// **A report and not an instruction.** The screen says what happened and what it did not do; what remains to be dismissed is a thing only the app can
    /// enumerate, and deciding it here would mean this module knowing about a bar it deliberately does not.
    func userPressedEscapeWithNothingOnThisScreenToDismiss(discussionIdentifier: ObvDiscussionIdentifier)

    /// **The reader clicked on the messages**, which on a Mac says they have finished typing, and the app takes the caret out of the composition bar.
    ///
    /// Said on Catalyst only — see ``AClickOnTheMessagesTakesTheCaretAway`` for why a phone says nothing — and a report for the same reason as the one above:
    /// the bar is the app's, and this screen sees it as an opaque view.
    func userClickedOnTheMessages(discussionIdentifier: ObvDiscussionIdentifier)

    /// Whether a message is being shown beside the composition bar while the reader writes a reply to it.
    ///
    /// **A report, and the bar answers it however it likes.** What it is for is the composition bar's quote panel: while the message itself is on show above the
    /// bar, legacy folds the quote down to the name alone — `ComposeReplyToView` hides the body and the thumbnail on `hasReplyViewDisplayedAbove`, each on a
    /// quarter-second ease-in-out. That property is the app's to set, this module seeing the bar only as an opaque view, which is the same layering that puts the
    /// reply quote itself on the far side of ``userPressedEscapeWithNothingOnThisScreenToDismiss(discussionIdentifier:)``.
    ///
    /// **A note this corrects.** `SwiftUISingleDiscussionMessagePresenter` said *"Nothing has to be told to the compose bar"* about exactly this property, on the
    /// reading that it was legacy's bookkeeping for asking a cell for a view. It is not: it is a display mode of the panel, and the difference is plain in the two
    /// screenshots this step was measured from.
    func aMessageIsShownBesideTheCompositionBar(discussionIdentifier: ObvDiscussionIdentifier, isShown: Bool)

    /// The reader has left this discussion, which is what wipes its read-once messages and gives up its claim on being the current one.
    ///
    /// **Nothing may depend on this for correctness**: it is not said when the app is merely backgrounded. What must happen then is already the app's business —
    /// wiping at launch, and on lock-out.
    func discussionDisappeared(discussionIdentifier: ObvDiscussionIdentifier)

    /// What the reader is looking at: what is on the screen now, and everything they have seen since this was last said.
    ///
    /// **Two sets because there are two questions, and they differ exactly where it matters.**
    ///
    /// - `onScreenNow` is what a screenshot would capture. It reaches the screen-capture detector, which is how a sender is told that their ephemeral message was
    ///   screenshotted or screen-recorded. Said as soon as it changes, **scrolling or not** — a capture during a scroll catches what is passing — and said even when
    ///   empty, that being what says a capture would now catch nothing.
    /// - `seenSinceTheLastReport` is what marks messages read, and it **accumulates**: everything that crossed the screen since the last time, including what went by
    ///   under a finger and is already gone. Said only once the list has stopped. Reporting merely what remained on screen would leave holes — read one to ten, fling
    ///   past to twenty, and eleven to nineteen stay unread for ever, so a discussion whose *last* message the reader has read still claims nine unread. Flinging
    ///   through a discussion to clear its badge is a thing people do, and it works on the legacy screen because it accumulates in the same way.
    ///
    /// **What was on screen is all this screen may claim to know.** Which of these are still unread, which are ephemeral, whether the window is even frontmost — all
    /// of that is the app's, and none of it is a question a view can answer.
    func messagesAreOnScreen(discussionIdentifier: ObvDiscussionIdentifier, onScreenNow: Set<SingleDiscussionView.CellIdentifier>, seenSinceTheLastReport: Set<SingleDiscussionView.CellIdentifier>)

    /// The reader tapped the header, which asks to be shown whoever this discussion is with — the contact, or the group.
    ///
    /// The route already exists on the app's side: `userTappedTitleOfDiscussion(_:discussionObjectID:)`, which is what the legacy title view's tap gesture calls.
    func userTappedTheHeader(discussionIdentifier: ObvDiscussionIdentifier)

    /// Carries out what the reader asked of the bar: a setting shown, the gallery opened, a call placed, a mute cleared.
    ///
    /// **On this protocol and not on a data source**, because three of the four *present* something, and only something holding a view controller can present. See
    /// ``DiscussionBarAction``.
    func userWantsToActOnTheDiscussion(discussionIdentifier: ObvDiscussionIdentifier, action: DiscussionBarAction)

    /// Whatever the reader let go over the **messages** — a file out of Finder, a photograph, a link — on its way to the draft.
    ///
    /// **The same destination as a drop on the composition bar**, which the bar answers for itself: both end in the one operation that decides what a dropped thing
    /// becomes, and that closes the bar to editing while a large file is copied. Nothing about that is decided here, and nothing about it differs by where the reader
    /// let go. This exists only because the transcript is a `List`, whose drop cannot be answered inside the bar's own view — see
    /// ``TakesWhateverIsDroppedOnTheMessages``.
    ///
    /// Never called with an empty set of providers: an empty drop is not a drop.
    func userDroppedItemsOnTheMessages(discussionIdentifier: ObvDiscussionIdentifier, itemProviders: [NSItemProvider])

    /// Deletes the messages the reader has chosen, in the way they chose.
    ///
    /// **One request for the whole selection, and not one per message.** Everything below this is already plural — the operations that delete, the one that
    /// cancels an upload, and `DeleteMessagesJSON`, which carries a reference per message so that a deletion for everyone is **one** protocol message rather than
    /// one each. Asking message by message would send as many.
    ///
    /// **`async throws`, which is what a notification could not be.** This screen has a bar to dismiss, a mode to leave and a failure to report, and it must do
    /// none of them until the messages are actually gone. An implementation is expected to return once the deletion has been carried out, and to throw if it
    /// could not be.
    ///
    /// The kind is one the reader was offered — see ``SingleDiscussionViewDataSource/whatCanBeDeleted(cellIdentifiers:discussionIdentifier:)``. It is asked for
    /// again on the way through rather than trusted: a sheet may stand open for as long as the reader likes, and what was true when it was drawn need not be
    /// true when a button is pressed.
    func userWantsToDeleteMessages(discussionIdentifier: ObvDiscussionIdentifier, cellIdentifiers: Set<SingleDiscussionView.CellIdentifier>, kind: WhatCanBeDeleted.Kind) async throws

    /// Forwards the messages the reader has chosen, once they have said where to.
    ///
    /// **The implementation owns the asking as well as the sending**, which is what makes this one call rather than two. Where the messages go is answered by a
    /// chooser that is a `UIViewController`, and this module has no way to present one; handing back a set of discussions for the screen to act on would mean
    /// this module holding a vocabulary of discussions it has no other use for. So the app puts the question, waits for the answer, and sends.
    ///
    /// **`async throws`, and it returns whether anything went.** The screen must not leave the mode or clear the ticks until the messages have actually been
    /// forwarded, exactly as with the deletion — and cancelling the chooser is an ordinary outcome rather than a failure, so it is a returned `false` and not a
    /// thrown error. A reader who backs out of choosing keeps their selection and can try again.
    ///
    /// The order the messages are sent in is not this screen's to decide: a selection is a set of ticks, and what a recipient must see is the discussion's own
    /// order, which only the app can read.
    ///
    /// - Returns: whether the messages were forwarded. `false` when the reader chose no discussion.
    func userWantsToForwardMessages(discussionIdentifier: ObvDiscussionIdentifier, cellIdentifiers: Set<SingleDiscussionView.CellIdentifier>) async throws -> Bool

}


// MARK: - SingleDiscussionView

/// Entry point of the full SwiftUI implementation of the single discussion screen.
///
/// This screen is reached when the beta-only "Discussion layout" setting is set to `SwiftUI`. It streams the identifiers of the cells to show, and
/// lets each ``SingleDiscussionCellView`` resolve its own model. Only sent and received messages are shown for now.
///
/// The composition bar is **injected** rather than built here, which keeps this module independent of `ObvComposition`, and lets the owner of this view
/// build the bar exactly once — the side effects of `ComposeView.init` then run once, instead of on every evaluation of this body.
public struct SingleDiscussionView: View {

    /// All the data sources required by this screen and its cells.
    public struct DataSources {

        /// Public, as the owner of the view needs it to compute the initial model.
        public let dataSource: any SingleDiscussionViewDataSource

        /// Public for the same kind of reason as ``dataSource``: it is also an ``ObvAvatarViewDataSource``, which is what the
        /// sheet listing who reacted needs to draw the people in it, and that sheet is presented by the owner of the view.
        public let cellViewDataSource: any SingleDiscussionCellViewDataSource

        /// Who reacted to a message, and with what — read by the sheet a reactions chip opens.
        ///
        /// **Not this screen's own data source, and carried here rather than asked of it.** The chip on a cell needs only a
        /// count per emoji, which ``SingleDiscussionCellViewDataSource`` answers through `ReactionsCountViewDataSource`; the
        /// sheet needs every reaction with the person who left it, which is a different question with a data source of its
        /// own, already written and already used by the legacy screen. This screen never reads it — it hands it to the sheet
        /// it presents.
        public let messageReactionsViewDataSource: any ObvMessageReactionsViewDataSource

        public init(dataSource: any SingleDiscussionViewDataSource, cellViewDataSource: any SingleDiscussionCellViewDataSource, messageReactionsViewDataSource: any ObvMessageReactionsViewDataSource) {
            self.dataSource = dataSource
            self.cellViewDataSource = cellViewDataSource
            self.messageReactionsViewDataSource = messageReactionsViewDataSource
        }

    }

    /// Identifies one cell of the discussion.
    ///
    /// This is not an `ObvAppTypes.ObvMessageAppIdentifier`: that type only models sent and received messages, whereas a discussion also contains
    /// system messages, and will contain cells that are not messages at all (date separators, unread marker). On top of that, a list of object IDs is
    /// far cheaper to build and to diff — reading `objectID` requires no fault fulfillment, so the whole list can be built without materializing a
    /// single message. Object IDs must not escape into anything persisted or crossing a process boundary; use `ObvMessageAppIdentifier` there.
    public enum CellIdentifier: Hashable, Sendable {
        case objectID(_ objectID: NSManagedObjectID) // NSManagedObjectID of a PersistedMessage (enforced by the datasource)
        case forPreview(_ uuid: UUID)
        /// Identifies the marker that says how many messages arrived since the reader last looked, shown above the first of them.
        ///
        /// Never produced by a data source: the list inserts it itself, from ``Model/newMessages``. It exists as an identifier, rather than being
        /// drawn inside the row of the message it precedes, so that the screen can *scroll to it* when the discussion opens.
        case newMessagesMarker
    }

    public struct Model: Equatable, Sendable {

        /// All the cells of the discussion, in the order they are displayed (oldest first).
        let cellIdentifiers: [CellIdentifier]

        /// Whether this model's rows are the **beginning** of that one's — which is to say whether the change from this to that is a pure *append*, with nothing
        /// removed and nothing inserted in the middle.
        ///
        /// **It answers *is a row leaving*, and it answers it conservatively** — see ``SingleDiscussionView/theWayARowLeaves``. A pure append is a message arriving
        /// at the end, which needs no animation because it arrives below the visible area. Anything else — a deletion, the unread marker going, a date separator
        /// inserted before a message, a message arriving *and* the marker leaving in the same yield — is treated as a row leaving and gets the fade. Erring that way
        /// is free: a fade on a row that only arrived is invisible for exactly the reason the arrival needs none.
        ///
        /// **A prefix walk rather than two `Set`s.** A discussion runs to hundreds of rows and this is asked on every change of the list, where building two sets
        /// would hash every identifier twice to answer a question the common case settles by walking until the shorter one runs out. It exits on the first
        /// difference, so a deletion near the end costs the whole walk and a deletion near the top costs almost nothing.
        func cellIdentifiersAreAPrefixOf(_ other: Model) -> Bool {
            guard cellIdentifiers.count <= other.cellIdentifiers.count else { return false }
            for (mine, theirs) in zip(cellIdentifiers, other.cellIdentifiers) where mine != theirs { return false }
            return true
        }

        /// The model of the **last** cell, streamed with the identifiers rather than looked up afterwards.
        ///
        /// It earns its place twice over. A cell resolves its own model from its own stream, which takes a few milliseconds — long enough that a message
        /// arriving showed as a redacted skeleton first and then turned into its content, which reads as a glitch. And it is what tells the screen whether
        /// the last cell is a message that was *sent*, which no identifier can say: a message one has just sent is always scrolled to, wherever the reader
        /// happens to be, so that they see it leave, whereas a message received only pulls the list down when the reader is already at the end.
        let lastCellModel: SingleDiscussionCellView.Model?

        /// Which messages count as new since the reader entered or last replied, and nil when none do. What the unread marker is drawn from; see
        /// ``NewMessages``.
        ///
        /// **Streamed with the identifiers rather than on its own**, and by construction rather than for tidiness: every event that changes this set — a message
        /// arriving, the reader sending one, a message deleted — **is** a change of ``cellIdentifiers``. So the marker and the message it belongs to are always
        /// part of the same value and appear on the same frame, where two streams could deliver one a frame before the other.
        let newMessages: NewMessages?

        /// The sections of the list, in display order: the first holds the first `numberOfCells` of ``cellIdentifiers``, and so on. What a section is, the data
        /// source decides; the app's makes it a month.
        ///
        /// **Sections are what keep a long discussion fast.** A `List` finds a row by walking from the first row of its section, and it does so for every cell it
        /// sizes. In a single section, a row near the end of a discussion of thousands costs thousands of steps.
        ///
        /// Empty, or not adding up to the number of cells, means a single section.
        let theSections: [TheSection]

        public struct TheSection: Equatable, Sendable {
            /// Says which section it is to the data source only. Unique in a model, as each section is a single run of cells.
            public let identifier: String
            public let numberOfCells: Int
            public init(identifier: String, numberOfCells: Int) {
                self.identifier = identifier
                self.numberOfCells = numberOfCells
            }
        }

        public init(cellIdentifiers: [CellIdentifier], lastCellModel: SingleDiscussionCellView.Model?, newMessages: NewMessages?, theSections: [TheSection] = []) {
            self.cellIdentifiers = cellIdentifiers
            self.lastCellModel = lastCellModel
            self.newMessages = newMessages
            self.theSections = theSections
        }

        /// The messages the unread marker speaks for.
        ///
        /// **A set, and only a set.** It answers two questions and both are membership: the marker sits above the first of these still in the discussion, and it
        /// says how many of them are still there. A message deleted therefore needs no special case, and neither does one deleted from the middle of the block.
        ///
        /// **It does not mean "unread", and that is legacy's meaning rather than a shortcut.** Nothing takes a message out of this set because the reader has read
        /// it — only its deletion, a message the reader sends, or leaving the discussion. So it means *new since you entered or last replied*: the marker persists
        /// over messages that have demonstrably been read, its count grows as more arrive, and it stays anchored above the first. Legacy's
        /// `objectIDsOfMessagesToConsiderInNewMessagesCell`, whose five triggers this reproduces.
        ///
        /// **The count is the size of the set**, which is exactly legacy's `appropriateNumberOfNewMessages`. This once carried a separate count of new messages the
        /// screen did not list, because system messages count towards the unread total; since Step 18b the screen draws all three kinds, and the only categories its
        /// fetch excludes are `.numberOfNewMessages` and `.discussionIsEndToEndEncrypted` — neither of which counts towards unread. So there is nothing left to
        /// count separately.
        public struct NewMessages: Equatable, Sendable {

            let theOnesThatCount: Set<CellIdentifier>

            public init(theOnesThatCount: Set<CellIdentifier>) {
                self.theOnesThatCount = theOnesThatCount
            }

        }

    }

    /// The values this screen needs at creation time, and which are never updated afterwards. They are deliberately kept out of ``Model``, which
    /// describes the state streamed to this screen: a value that only ever makes sense at init has no business being part of every update.
    public struct InitialValues {

        /// Models known synchronously for the most recent cells, so that they are shown on the very first frame.
        ///
        /// Without them, every cell appears as a redacted skeleton until its own stream produces a first model, which takes long enough to be seen
        /// while the screen is being pushed, and makes the whole list reflow as the bubbles reach their real height. The data source prefetches enough
        /// of them to fill a screen; the cells left out show a skeleton, which is expected when scrolling far into the past.
        let cellModels: [CellIdentifier: SingleDiscussionCellView.Model]

        /// What the discussion says about itself before anything else: that what is written in it is end-to-end encrypted.
        ///
        /// **A fixed first row rather than a message in the list**, which is what makes its position an invariant instead of a hope: the legacy screen keeps it as an
        /// ordinary `PersistedMessageSystem` and therefore relies on nothing ever sorting below it, where a history transfer inserts messages carrying their original
        /// timestamps. Here it cannot be anywhere but first, and the data source excludes that category from the identifiers so that it is not also drawn twice.
        ///
        /// The sentence comes from the app because it is the app's: there are a long and a short form, chosen by a setting the reader controls. Read once, with the
        /// rest of these values — a reader who changes that setting while looking at a discussion sees it on the next one they open, as they do for the setting that
        /// hides group changes.
        let sentenceSayingTheDiscussionIsEndToEndEncrypted: String?

        /// Who the reader is talking to, as it is at the moment the screen is created.
        ///
        /// Here rather than streamed-and-awaited for the reason every seed on this screen is here: the bar is on screen from the first frame, and a header that
        /// arrived a few milliseconds later would be seen filling in. It is a seed and not the truth — ``SingleDiscussionView`` follows the stream from there.
        let header: DiscussionHeader

        public struct NewMessages {

            /// The messages the reader had not seen **that this screen lists**, as a set, because what is asked of it is membership.
            ///
            /// **A set rather than the first one and a count**, which is what this carried until a message was deleted out of the middle of it. The marker then
            /// vanished — its position being the index of one particular identifier, which was no longer in the discussion — where what the reader expects is the
            /// marker staying put and counting one fewer. Both questions are answered by intersecting this with the identifiers the screen currently holds: the
            /// marker sits above the first member still there, and says how many members are still there. Nothing needs remembering, and a deletion anywhere in
            /// the block is handled by the same line as a deletion at its top.
            let theListedOnes: Set<CellIdentifier>

            /// How many *more* the reader missed than this screen lists.
            ///
            /// New system messages count towards what the marker says, as they do on the legacy screen, and this screen does not show them yet — so the number it
            /// announces is deliberately larger than the number of rows below it. Held as a difference so that the count starts at exactly what it always was, and
            /// only what can be seen to disappear takes anything off it.
            let alsoCountingUnlisted: Int

            public init(theListedOnes: Set<CellIdentifier>, alsoCountingUnlisted: Int) {
                self.theListedOnes = theListedOnes
                self.alsoCountingUnlisted = alsoCountingUnlisted
            }

        }

        /// Whether a message the reader sent shifts its blue with where it sits on the screen — **on by default from iOS 26**, and a switch of the reader's
        /// rather than a beta option. See ``TheFieldTheBubblesTravelThrough``.
        ///
        /// **Here rather than asked for by the view**, because it is a setting of the app's and this module reads no settings: what the screen needs to know, the app
        /// tells it. Read once, as the screen is created, so turning it on shows on the next discussion opened rather than on the one behind the settings — which is
        /// what a look being compared with another wants anyway.
        let sentBubbleHueVariesWithScroll: Bool
        let elasticScrolling: Bool

        /// Whether opening this discussion waits for the transcript to be in place before showing it, and then sees the scroll through to the end — a setting of
        /// the app's, read once as the screen is created, **on** unless somebody has turned it off among the beta options.
        ///
        /// One value over two behaviours on purpose; the reasoning is with the setting, in `ObvMessengerSettings.Interface`. It is here rather than in the
        /// environment for the two the environment carries, because nothing below the entry reads it: the entry is the only thing it governs.

        public init(cellModels: [CellIdentifier: SingleDiscussionCellView.Model], sentenceSayingTheDiscussionIsEndToEndEncrypted: String?, header: DiscussionHeader, sentBubbleHueVariesWithScroll: Bool, elasticScrolling: Bool) {
            self.cellModels = cellModels
            self.sentenceSayingTheDiscussionIsEndToEndEncrypted = sentenceSayingTheDiscussionIsEndToEndEncrypted
            self.header = header
            self.sentBubbleHueVariesWithScroll = sentBubbleHueVariesWithScroll
            self.elasticScrolling = elasticScrolling
        }

    }

    private let discussionIdentifier: ObvDiscussionIdentifier
    private let dataSources: DataSources

    /// What the cells of this screen ask of their owner, as opposed to what they ask about.
    private let actions: any SingleDiscussionCellViewActions

    /// What the screen itself asks of its owner: that it has appeared, and that it has gone. See ``SingleDiscussionViewActions``.
    private let screenActions: any SingleDiscussionViewActions

    private let initialModel: Model
    private let initialValues: InitialValues

    /// The composition bar, built once by the owner of this view. Stored as a value, and not as a `@ViewBuilder` closure, precisely so that it is *not*
    /// rebuilt on each evaluation of this body.
    ///
    /// Type erased rather than generic: a generic parameter here would force every reference to the nested ``CellIdentifier``, ``Model`` and
    /// ``InitialValues`` to spell it out. An `AnyView` is acceptable in this one spot as it wraps a single view, created once, and not the row of a lazy
    /// container — which is the case where erasing the type of a view actually costs.
    private let composeBar: AnyView

    @State private var streamedModel: Model?

    /// Who the reader is talking to, as its own stream reports it. Nil until it has said anything, and until then the seed stands. See ``DiscussionHeader``.
    @State private var streamedHeader: DiscussionHeader?

    /// The search the reader is performing, or is not. See ``TheSearchOfThisDiscussion``.
    @State private var search = TheSearchOfThisDiscussion.notSearching

    /// The messages the reader is choosing, or is not. See ``TheSelectionOfSeveralMessages``.
    ///
    /// **A sibling of `search` and not a variant of it.** The two are the same kind of thing — a mode of this screen, entered from the ellipsis, taking the
    /// composition bar's place — and they are kept apart because what they hold has nothing in common. What they *do* share is the one place they are drawn, and
    /// therefore the rule that they cannot both be running: see ``startSelectingMessages()``.
    @State private var selection = TheSelectionOfSeveralMessages.notSelecting

    /// Where the reader is in the act of forwarding what they have chosen. See ``TheForwardingOfSeveralMessages``.
    ///
    /// **Beside ``deletion`` and not folded into it**, though the two can never both be running: they are asked different questions, refused for different
    /// reasons and drawn by different modifiers, and one enum spanning both would be a state that says *which action* as well as *how far along*. The menu
    /// declines while either is busy, which is where the exclusivity actually lives.
    @State private var forwarding: TheForwardingOfSeveralMessages = .notAsked

    /// Where the reader is in the act of deleting what they have chosen. See ``TheDeletionOfSeveralMessages``.
    @State private var deletion: TheDeletionOfSeveralMessages = .notAsked

    /// How anything asks the list to take the reader somewhere: the message a reply answers, the result of a search, and the message the app was told to show.
    ///
    /// **Held by the owner of this view rather than by the list**, which is where it used to live. The list cannot own it because the search bar is not inside the
    /// list and so cannot see what the list puts into the environment; this view cannot own it either, because the app asks for a jump while building the screen,
    /// before any of this exists. See ``WhereTheReaderWantsToGo``.
    private let whereTheReaderWantsToGo: WhereTheReaderWantsToGo

    /// What decides the space kept below the composition bar — see ``TheSpaceBelowTheCompositionBar``.
    ///
    /// **Written by this view and observed only by the bar**, which keeps that space itself. See ``TheBarKeepsItsMargin``. Both values change as the keyboard
    /// comes and goes. As `@State` of this view, each change redrew the whole screen and the list of messages with it, which then compared every row of the
    /// discussion: about 133 ms on an iPhone Xs for 4,760 messages. Here the `@State` holds an object this view does not observe, so only the bar is redrawn.
    @State private var theSpaceBelowTheCompositionBar = TheSpaceBelowTheCompositionBar()

    /// Where the reader is in the act of pressing a message — see ``TheContextMenuOfAMessage``.
    ///
    /// **Held by the screen and not by the list**, because the overlay it drives has to cover the composition bar as well as the transcript: it is applied outside
    /// the safe-area inset the bar is inserted into. What the *messages* need of it reaches them as an environment value, and the list reads the same value to
    /// know that it must hold still.
    @State private var contextMenu: TheContextMenuOfAMessage = .idle

    /// The one flag every visible movement of the lift hangs on: the message rising, the card growing out of its corner, the backdrop coming up.
    ///
    /// Separate from ``contextMenu`` on purpose. The state changes first, without animation, placing a copy of the message exactly where the real one already was
    /// — so that frame is identical to what the reader is looking at and nothing can be seen to happen. Only then is this set, inside one spring, and that spring
    /// is the whole of what the eye sees.
    @State private var theMessageIsUp = false

    /// Whether a message is being held beside the composition bar while the reader writes a reply to it. See ``TheMessageBesideTheCompositionBar``.
    @State private var besideTheBar: TheMessageBesideTheCompositionBar = .none

    /// Separate from ``besideTheBar`` for the reason ``theMessageIsUp`` is separate from ``contextMenu``: the state changes first, without animation, placing a
    /// copy exactly where the real message already was, and only then is this set inside the one animation the eye sees.
    @State private var theMessageIsDown = false

    /// Whether the copy is still on its way down: true from the moment the journey begins until the animation itself says it has stopped moving.
    ///
    /// **What it decides is whether the destination is held or read.** A band that moves while the copy is in the air is a retarget; one that moves after it has
    /// landed — the keyboard coming up, a line added to the draft — must simply carry the copy inside whatever animation is moving the bar. See
    /// ``TheMessageHeldBesideTheCompositionBar/whereTheJourneyEnds``.
    @State private var theCopyIsStillOnItsWayDown = false

    /// How a message says it is being pressed — created here because this is where the answer is decided. See ``PressesOnMessages``.
    @State private var pressesOnMessages = PressesOnMessages()

    /// The knock a message gives as the menu lifts it.
    ///
    /// **Held, rather than made where it is used, so that it can be *prepared*.** A generator created and fired in the same breath asks a sleeping Taptic Engine to
    /// answer at once, and it arrives late or not at all; `prepare()` wakes it, and the moment to do that is when the finger goes down, a quarter of a second before
    /// the lift. That is why this is state and not a local — a generator that does not outlive the call cannot be warmed.
    ///
    /// **Said on every platform, felt on some.** A `UIFeedbackGenerator` does nothing where there is no hardware for it — an iPad, and a Mac under Catalyst — so
    /// there is nothing to switch off and no platform test to keep in step. `.medium` is what UIKit's own context menu gives.
    @State private var theKnockWhenAMessageIsLifted = UIImpactFeedbackGenerator(style: .medium)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// The legacy screen keeps the composition bar 16pt above the keyboard. It expresses this as a constraint of -16 applied whenever the bottom safe area
    /// inset is zero — which reads as being about the iPhone SE, but is also exactly what happens as soon as the keyboard appears, the inset of the home
    /// indicator collapsing then. Measured on both screens, the bar of this one sat 16pt lower than the legacy one, to the point.
    private static let marginAboveKeyboard: CGFloat = 16

    /// What is kept below the bar when the system leaves nothing there — an iPhone SE, which has no home indicator. The legacy screen's own `-16.0`, from the
    /// branch of `constantForComposeMessageContainerViewbottomAnchorConstraintToKeyboardConstant` that tests `view.safeAreaInsets.bottom.isZero`.
    ///
    /// The same 16 as above the keyboard, and deliberately a constant of its own: they answer different questions and one of them may be tuned without the other.
    private static let marginWhenTheSystemLeavesNone: CGFloat = 16

    /// How the screen moves as the reader begins and ends choosing messages.
    ///
    /// **The system's own default, deliberately unnamed beyond this.** It is what `EditButton` uses for the same change, and the reader has seen it in every
    /// other application that indents a list to show its ticks; a curve of our own here would be an opinion about something nobody asked us to have one about.
    ///
    /// **It carries three things and not one**, which is why it is a constant rather than a bare `withAnimation`: the rows indenting, the bar at the bottom
    /// changing, and the navigation item swapping. They are one movement to the eye and must be one transaction, or they arrive in the order they happen to be
    /// written in.
    ///
    /// The bar changing means the **bottom inset** now changes over the length of this rather than in one step, which is a thing this screen has been careful
    /// about. It is safe here for a reason worth
    /// stating: the rule that answered such a change by leaping to the end was the fault fixed on 2026-08-17, and what remains either moves *by* the change or
    /// declines unless the reader is within a point of the end.
    private static let theSwitchIntoAndOutOfChoosing: Animation = .default

    private var model: Model { streamedModel ?? initialModel }

    private var header: DiscussionHeader { streamedHeader ?? initialValues.header }

    /// What may be done to the messages the reader has chosen — forwarding them, and deleting them.
    ///
    /// **A menu labelled with a word**, and that change was written down before it was made: while deleting was the only thing on offer this was
    /// a bare trash, with a comment saying *"a button and not a menu… it offers six things and this offers one, and a menu of a single entry is a worse control
    /// than the entry itself. When share and forward arrive this becomes that menu — and then it is labelled with a word, a menu having no single symbol to
    /// stand for it."* Both halves of that are now true. It is also what the **discussions list** does with the actions of its own select mode, which is the
    /// screen that decides such things here, having shipped first.
    ///
    /// **Apple's preference for symbols does not reach this.** Their toolbar guidance illustrates *Filter, Delete, New* as text marked wrong and the same three
    /// as symbols marked right — *prefer simple, recognizable symbols for items instead of text, except for actions like edit that aren't well-represented by
    /// symbols* — and a menu is exactly such an exception: there is no glyph that means *the things you may do to these*. The pairing the guidance really cares
    /// about is preserved by ``theWayOut``, which is a symbol and sits trailing.
    ///
    /// **Photos labels this same menu with an ellipsis** — the glyph the sentence above says does not exist — and the word is kept here all the same, decided
    /// 2026-09-07 on the screenshots that settled ``theWayOut``. The reader arrived in this mode *from* an ellipsis, and a second one in its place says nothing
    /// about what has changed, where *Actions* names what the menu is now for.
    ///
    /// **Delete is destructive here rather than red out there**, which settles an argument that was lost on sight when the trash was built. It was styled red as a bar button, over
    /// the objection that destructive styling belongs to a context-menu *entry*, where a reader reads a word rather than aims at a glyph. The objection was
    /// right and only its case was wrong: it lost because the trash was then the **only** thing the bar did. It no longer is, and the styling goes where it was
    /// always argued to belong.
    ///
    /// **Forward first, Delete last**, so the destructive entry stays at the bottom as it does on a message's own menu and on the legacy one.
    ///
    /// **Disabled rather than hidden** while nothing is chosen, which is the gallery's rule and the discussions list's: a bar that rearranges itself as the
    /// reader works is worse than one that greys. It declines while either action is busy, too — that is where the exclusivity of the two lives, there being no
    /// state that says *one of these is running*.
    ///
    /// Nothing is done about the hit area — a navigation bar item is UIKit's to lay out and to make tappable, which is why that had to be said by hand while
    /// this lived on a bar of our own.
    @ViewBuilder
    private var theActionsOnTheSelection: some View {
        Menu {
            Button(action: forwardsWhatIsSelected) {
                Label {
                    Text("FORWARD")
                } icon: {
                    Image(systemIcon: .arrowshapeTurnUpForward)
                }
            }
            Button(role: .destructive, action: deletesWhatIsSelected) {
                Label {
                    Text("DELETE")
                } icon: {
                    Image(systemIcon: .trash)
                }
            }
        } label: {
            Text("ACTIONS")
        }
        .disabled(selection.isEmpty || deletion != .notAsked || forwarding != .notAsked)
    }


    /// The way out of choosing: **an `xmark`, unstyled**, which is what Apple's own select mode uses — changed 2026-09-07.
    ///
    /// **Settled by looking rather than by reasoning.** This was a prominent `DONE` for three weeks, on an argument from Apple's toolbar guidance — *use the
    /// prominent style for key actions such as Done or Submit… only specify one primary action, and put it on the trailing side* — and from `editButtonItem`,
    /// whose system-supplied title really is *Edit ⇄ Done*. A second argument was written down beside it and was wrong: that an `xmark` in a navigation bar
    /// means *dismiss this presentation*, the gallery's own `.close` item being exactly that, so it could not be spent on leaving a mode of a screen the
    /// reader stays on. **Photos on iOS 26 does precisely that**, screenshots on 2026-09-07: `Select` opens a mode whose trailing side is a plain circular
    /// `xmark`, in a capsule of its own, beside a grouped ellipsis that is disabled until something is ticked. Apple's own select mode, on the current OS,
    /// for semantics identical to these. A reading of the guidance does not outrank the shipped app it is guidance for.
    ///
    /// **Unstyled, and that is half the change.** Photos' `xmark` is an ordinary glass button, not a tinted one, so the `.glassProminent` goes with the word
    /// and the iOS 26 branch goes with it — a plain bar button is already a circular glass one on 26 and an ordinary one before it. Nothing is *primary*
    /// here: the reader came for the menu, and the exit is an exit.
    ///
    /// **The word survives as the accessibility label**, so `DONE` keeps its thirteen translations and VoiceOver keeps a verb rather than a glyph name. The
    /// semantics never changed — nothing is applied on leaving, the ticks are discarded — only what is drawn, which is why this is still not *Cancel*.
    ///
    /// **A capsule of its own, as in Photos**, which took two changes and not one: the actions and the way out are two `ToolbarItem`s rather than one
    /// `ToolbarItemGroup`, **and** a `ToolbarSpacer` stands between them. Two items alone drew the same single capsule the group had, a placement's items
    /// sharing a background on iOS 26 whatever they are declared as — proven by a screenshot in which nothing had visibly changed. The group had been kept
    /// for a day on the grounds that it is the one arrangement in which the bar animates; that was the wrong thing to spend the separation on, and the
    /// reasoning is at the call site. **The roles are now told apart by the bar rather than by a tint**, which is the same change as dropping
    /// `.glassProminent` said a second way.
    ///
    /// **One difference from Photos remains**: its library is a root screen where this one is pushed, so the `xmark` sits opposite a back chevron the mode
    /// does not hide. It is trailing, where a close never is, and the reader who ticked a message put it there.
    private var theWayOut: some View {
        Button(action: stopSelectingMessages) {
            Image(systemIcon: .xmark)
        }
        .accessibilityLabel(Text("DONE"))
    }


    /// What the items of the bar say the reader asked for, passed on with the identifier of the discussion they concern.
    private func act(_ action: DiscussionBarAction) {
        screenActions.userWantsToActOnTheDiscussion(discussionIdentifier: discussionIdentifier, action: action)
    }

    /// The reader asked to search this discussion. **Answered here rather than by the app**: nothing is presented, the field taking the composition bar's place.
    ///
    /// **A selection ends when a search begins**, which is what ``startSelectingMessages()`` says from the other side and which this had never said back. The two
    /// modes stand in the one place and only one bar is drawn, so a state where both are running is not a mode the screen has — it is a screen with a mode nobody
    /// can see. That state was reachable: the ellipsis is not in the toolbar while the reader is choosing, but **⌘F is answered by the responder chain whatever the
    /// screen is doing**, and `answersTheFindShortcuts()` asks for a search without qualification. What it produced was `search.isRunning` with no field drawn — the
    /// branch below the transcript tests the selection first — and then a first Esc that appeared to do nothing, cancelling the invisible search instead of the mode
    /// the reader could actually see.
    ///
    /// Only when there is a selection to end, unlike its mirror: ``stopSearching()`` is a plain assignment where ``stopSelectingMessages()`` carries an animation of
    /// its own, and there is no reason for every ⌘F to run one for nothing.
    private func startASearch() {
        guard !search.isRunning else { return }
        if selection.isRunning {
            stopSelectingMessages()
        }
        search.isRunning = true
    }

    /// The reader is done searching. Everything goes at once — the field, the term, the results, and with them every highlight on the screen, ``TheSearchOfThisDiscussion/words``
    /// answering nothing as soon as the search stops running.
    private func stopSearching() {
        search = .notSearching
    }

    /// The reader asked to choose several messages. **Answered here rather than by the app**, as a search is, and for the same reason: nothing is
    /// presented, the bar of ``TheBarForSelectingSeveralMessages`` taking the composition bar's place.
    ///
    /// **A search ends when a selection begins.** Both stand in the one place, so only one can be shown, and saying so here means the branch that draws them
    /// never has to answer for a state that cannot happen. Ending the search also takes every highlight off the screen, which is right: a reader choosing
    /// messages to delete is not one still hunting for a word.
    ///
    /// **The keyboard goes.** Nothing in this mode takes typing, and a keyboard left up would cover half the messages the reader is trying to choose. The
    /// draft is untouched — the composition bar keeps its state and is merely not drawn, so a half-written message is still there afterwards.
    ///
    /// **Animated, as `EditButton` animates the mode it owns**: one transaction for the whole change, so the indent, the bar and the navigation item move
    /// together rather than arriving in whatever order they are computed. See ``theSwitchIntoAndOutOfChoosing``.
    ///
    /// **The navigation bar does not animate on the way in, and nothing here is the cause.** Four explanations were tried and each was killed by a run: the
    /// transaction (both directions share it), the shape of the toolbar, the menu, and a one-turn delay. One asymmetry survives, and it is in the toolbar's
    /// shape rather than in this method — entering *removes two items and inserts a group* where leaving *removes one group and inserts two items*, and UIKit
    /// animates a change of the item set. It is written up where the toolbar is built. What has never been tested is whether the movement happens and is
    /// **dropped**: entering makes the `List` inset every visible row to make room for a circle, which is the heavier pass, and a bar animation over dropped
    /// frames looks exactly like no animation. That is testable without changing a line, in a discussion of two messages rather than two thousand.
    ///
    /// - Parameter startingWith: The message to begin with, already ticked — what the entry of a message's own menu passes. **Nil from the ellipsis**, which
    ///   names the mode rather than a message, so the reader starts with nothing chosen.
    private func startSelectingMessages(startingWith cellIdentifier: CellIdentifier? = nil) {
        guard !selection.isRunning else { return }
        withAnimation(Self.theSwitchIntoAndOutOfChoosing) {
            stopSearching()
            selection.isRunning = true
        }
        // Outside the animation, having a curve of its own that is the system's rather than ours.
        theKeyboardGoesAway()
        ticksTheMessageTheReaderStartedFrom(cellIdentifier)
    }


    /// Ticks the message the mode was entered from, **one turn after the mode is on**.
    ///
    /// **Written in the same update as `isRunning`, it did not stick** — reported on 2026-08-17 from a Mac and an iPhone alike: the mode opened with nothing
    /// chosen. The selection is the `List`'s own, bound to this state, and what the `List` does with that binding as it enters edit mode is not ours to
    /// arrange — whether the write is lost in the same update or the list initialises its selection over it, both are answered by writing after the mode is
    /// established rather than with it.
    ///
    /// **A turn, and not a wait.** The same idiom the screen already uses twice — `SingleDiscussionCellsListView` delays the scroll that follows a message
    /// arriving by exactly one turn, and for the same class of reason: a change asked for inside the update that caused it is not a change of its own.
    ///
    /// Nothing happens when the mode was entered from the ellipsis, which names the mode rather than a message.
    private func ticksTheMessageTheReaderStartedFrom(_ cellIdentifier: CellIdentifier?) {
        guard let cellIdentifier else { return }
        Task { @MainActor in
            // The reader may have left again before this ran, in which case there is no mode for a tick to belong to.
            guard selection.isRunning else { return }
            // **Ticked, and where a range extends from** — Step 42e: *a selection seeded by the `Select` entry sets the anchor to the message it started
            // from*. Without the anchor, a reader who chose *Select* on a message and then ⇧-clicked another would get a plain click, which is the one case
            // where it is obvious to everyone but the code. One call, so this stays a single change to a single piece of state on every platform.
            selection.startsFrom(cellIdentifier)
        }
    }


    /// The reader is done choosing. Everything goes at once — the mode, and whatever was ticked.
    ///
    /// The ticks are cleared *inside* the animation on purpose: the circles then fade with the indent they sat in, where clearing them first would empty them a
    /// frame before they left.
    private func stopSelectingMessages() {
        withAnimation(Self.theSwitchIntoAndOutOfChoosing) {
            selection = .notSelecting
        }
        // **A deletion is a question about a selection, so it cannot outlive one.** The guard in ``deletesWhatIsSelected()`` puts the state back when its own
        // answer arrives late, which covers the case that was found; this covers the one that reading alone would not settle, an answer that never arrives at
        // all. It is also what the state's lifetime says: there is nothing to ask about a selection that has ended.
        //
        // Safe against the answer landing afterwards, and deliberately so rather than by luck: that guard requires `deletion == .findingOutWhatCanBeDone`, so a
        // task in flight when this runs finds `.notAsked` and writes nothing — including in the awkward case of the reader starting a *new* selection before the
        // old answer arrives, where testing the selection alone would have let a stale answer through.
        deletion = .notAsked
        // The same reasoning, and the same safety: ``forwardsWhatIsSelected()`` requires `.findingOutWhetherTheyCanBeForwarded` before it writes, so an answer
        // arriving after the mode has ended finds `.notAsked` and leaves it alone. Note what this does *not* do — it does not stand down a forward that is
        // already ``TheForwardingOfSeveralMessages/underWay``, because nothing here can: the chooser belongs to the app and the messages may already be gone.
        // That case cannot arise from the reader's side, the menu being disabled throughout, and it is left rather than defended against.
        forwarding = .notAsked
    }


    /// The reader has chosen Forward. Asks whether what they chose may go, and hands the question of *where* to the app.
    ///
    /// **The cap is asked first, and locally.** How many messages may go at once is a product rule about wording rather than a fact about the messages, so it
    /// costs no round trip and it is answered before anything is asked of the app. See ``TheForwardingOfSeveralMessages/theMostThatMayBeForwardedAtOnce``.
    ///
    /// The two guards after it are ``deletesWhatIsSelected()``'s, for the reasons recorded there — an answer that has been overtaken must not write, and one that
    /// arrives after the reader has left the mode must put the state back rather than wedge it.
    private func forwardsWhatIsSelected() {
        guard !selection.isEmpty else { return }
        // **Neither action may begin while the other is anywhere but at rest**, and *at rest* is the whole of the test rather than *acting*. Working out what may
        // be deleted is three simulated deletions of the whole selection on the main thread, and the menu used to stay live throughout — so a reader could ask
        // for a forward while that ran, and the chooser would go up in time for the deletion's own sheet to be asked for from underneath it.
        guard forwarding == .notAsked, deletion == .notAsked else { return }
        guard selection.count <= TheForwardingOfSeveralMessages.theMostThatMayBeForwardedAtOnce else {
            forwarding = .tooManyWereChosen(theMost: TheForwardingOfSeveralMessages.theMostThatMayBeForwardedAtOnce)
            return
        }
        forwarding = .findingOutWhetherTheyCanBeForwarded
        // **Read once, and it is the set that is both asked about and sent.** Reading the ticks again on the far side of the question would mean sending a
        // selection that was never checked — a message can leave the selection while this runs, `keepsOnlyWhatIsStillThere(in:)` dropping it when it is deleted
        // from another device — and the two sets differing is precisely the case nobody would think to test.
        let theMessagesChosen = selection.cellIdentifiers
        Task {
            let whatCanBeDone = await dataSources.dataSource.whatCanBeForwarded(cellIdentifiers: theMessagesChosen,
                                                                               discussionIdentifier: discussionIdentifier)
            guard forwarding == .findingOutWhetherTheyCanBeForwarded else { return }
            guard selection.isRunning else { forwarding = .notAsked; return }
            switch whatCanBeDone {
            case .atLeastOneCannotBeForwarded(let reason):
                forwarding = .nothingCanBeForwarded(reason)
            case .allOfThem:
                await sendsWhereverTheReaderSays(theMessagesChosen)
            }
        }
    }


    /// Asks the app where they should go, sends them, and leaves the mode once they have gone.
    ///
    /// **The mode is left after the forward and not before it**, which is ``deletesWhatIsSelected(_:)``'s decision and holds here for a further reason of its
    /// own: the reader may cancel the chooser, and a mode ended on the way *in* would have thrown away a selection they never finished using. So a cancellation
    /// — a `false` rather than a thrown error — puts the state back and changes nothing else.
    ///
    /// **The ticks are read once, before the chooser goes up.** A chooser can stand there for as long as the reader likes, and what is forwarded must be what
    /// they chose rather than what is still ticked when they come back — the same reasoning that puts the offer inside the deletion's `confirmationDialog`
    /// rather than reading it back from state.
    private func sendsWhereverTheReaderSays(_ cellIdentifiers: Set<CellIdentifier>) async {
        guard !cellIdentifiers.isEmpty else { forwarding = .notAsked; return }
        forwarding = .underWay
        do {
            let theyWereForwarded = try await screenActions.userWantsToForwardMessages(discussionIdentifier: discussionIdentifier,
                                                                                      cellIdentifiers: cellIdentifiers)
            forwarding = .notAsked
            // Only when something actually went. A reader who backed out of the chooser keeps their selection and the mode, and may try again.
            if theyWereForwarded {
                stopSelectingMessages()
            }
        } catch {
            // The mode stays, so that the reader still has their selection and may try again or take some of it back.
            forwarding = .itFailed
        }
    }


    /// The reader has tapped the trash. Asks what may be done to what they have chosen, and offers it.
    ///
    /// **The question is asked here and not as the selection changes**, which is the whole reason it is a method and not a computed property: arriving at the
    /// answer means simulating the deletion of the selection once per kind, on the main thread against the view context, and doing that on every tick would put
    /// that work between a finger and a circle. See ``SingleDiscussionViewDataSource/whatCanBeDeleted(cellIdentifiers:discussionIdentifier:)``.
    private func deletesWhatIsSelected() {
        guard !selection.isEmpty else { return }
        // The mirror of the guard in ``forwardsWhatIsSelected()``, and it says why both are written this way round.
        guard deletion == .notAsked, forwarding == .notAsked else { return }
        deletion = .findingOutWhatCanBeDone
        Task {
            let whatCanBeDone = await dataSources.dataSource.whatCanBeDeleted(cellIdentifiers: selection.cellIdentifiers,
                                                                             discussionIdentifier: discussionIdentifier)
            // **Two refusals, and they must not share a line, because only one of them may write.** Anything other than
            // ``TheDeletionOfSeveralMessages/findingOutWhatCanBeDone`` means this answer has been overtaken and somebody else owns the state now: leave it
            // exactly as it is.
            guard deletion == .findingOutWhatCanBeDone else { return }
            // Where the reader has *left the mode* while this was being worked out, the answer is about a selection that no longer exists — but the state is
            // still ours, and returning without putting it back is what wedged the screen: `.findingOutWhatCanBeDone` draws no sheet and nothing else resets it,
            // so `guard deletion == .notAsked` above refused every later tap on the trash, silently, for the life of the screen. Tapping the trash and then DONE
            // quickly enough was all it took.
            guard selection.isRunning else { deletion = .notAsked; return }
            deletion = whatCanBeDone.kinds.isEmpty ? .nothingCanBeDeleted : .choosing(whatCanBeDone)
        }
    }


    /// Deletes them, in the way the reader chose, and leaves the mode once they are gone.
    ///
    /// **The mode is left after the deletion and not before it.** Leaving first would be quicker to write and would lie: the messages are still there while the
    /// operations run, and a reader returned to an ordinary transcript that still holds what they deleted has been told it worked before it did.
    private func deletesWhatIsSelected(_ kind: WhatCanBeDeleted.Kind) {
        let cellIdentifiers = selection.cellIdentifiers
        guard !cellIdentifiers.isEmpty else { deletion = .notAsked; return }
        deletion = .deleting
        Task {
            do {
                try await screenActions.userWantsToDeleteMessages(discussionIdentifier: discussionIdentifier,
                                                                  cellIdentifiers: cellIdentifiers,
                                                                  kind: kind)
                deletion = .notAsked
                stopSelectingMessages()
            } catch {
                // The mode stays, so that the reader still has their selection and may try again or take some of it back.
                deletion = .itFailed
            }
        }
    }


    /// Puts the keyboard away, whoever has it.
    ///
    /// Asked of the responder chain rather than of the composition bar, which this module knows nothing about — it arrives as a view the app has already built, and
    /// there is nothing here to ask. The same line as `PollCreationFlowView`, which has the same problem.
    private func theKeyboardGoesAway() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// Looks for what has been typed, once the typing pauses.
    ///
    /// **The wait is the debounce, and it is `.task(id:)` that makes it one.** SwiftUI cancels this task and starts a new one on every change of the words, so each
    /// keystroke throws away the wait that was in progress: only a pause of ``pauseBeforeSearching`` long enough to survive reaches the fetch. The legacy screen does
    /// the same thing with a Combine `debounce` of the same duration.
    ///
    /// `results` is set to nil first, on purpose: it is what makes the bar say nothing rather than *no result* while the answer is on its way.
    ///
    /// **Unless the answer for these very words is already held**, in which case this does nothing at all — see ``TheSearchOfThisDiscussion/hasAlreadyAnswered(_:)``.
    /// A `.task(id:)` is started again every time its view returns to the hierarchy, with the words unchanged, and the reader is somewhere in the results by then.
    private func looksForWhatIsBeingTyped(_ words: TheWordsBeingLookedFor) async {

        guard search.isRunning, !words.isEmpty else {
            search.hasNotLookedYet()
            return
        }

        guard !search.hasAlreadyAnswered(words) else { return }

        search.hasNotLookedYet()

        do {
            try await Task.sleep(seconds: Self.pauseBeforeSearching)
            let found = try await dataSources.dataSource.getCellIdentifiersOfMessages(matching: words, discussionIdentifier: discussionIdentifier)
            // The words may have moved on while the fetch was running, in which case a newer task has already been started and this answer is stale.
            guard words == search.words else { return }
            search.hasFound(found, for: words)
        } catch {
            // Cancelled by the next keystroke, which is the ordinary case and not a failure, or the fetch itself failed. Either way there is nothing to show, and
            // `results` is already nil.
        }

    }

    /// How long the typing must pause before the discussion is searched. The legacy screen's Combine pipeline uses the same 0.3s.
    private static let pauseBeforeSearching: Double = 0.3


    /// **Esc backs out of whatever is up**, and the priorities are the whole of the step.
    ///
    /// Legacy has one `keyCommand` with three: the reaction view, else the reply draft, else the top presented controller. Ours has more things Esc could mean,
    /// and the plan expected ordering them to *be* the work. **It largely is not, and the reason is worth writing down**: a search and a selection are siblings
    /// that never run together, and *both replace the composition bar*, so a reply draft is not on screen while either is. The states are nearly all mutually
    /// exclusive, and the only ordering that decides anything is that **the overlay comes first** — it is the one thing that can sit on top of any of the others.
    ///
    /// **Esc means Cancel for a mode**, decided 2026-08-26, and nobody had decided it before because legacy has neither mode. It is what Esc means everywhere
    /// else on a Mac, and both modes already have a Cancel this simply calls, so there is one way out of each rather than two implementations of leaving.
    ///
    /// **What is not here is the reply draft**, and that is a layering decision rather than an omission: it arrives as a value from the *app's* data source and
    /// is removed through `userWantstoRemoveReplyToMessage`, this screen seeing the composition bar only as an opaque view. So the app answers Esc for it, and
    /// this reports upward when it had nothing of its own to dismiss. Anything *presented* over the screen, legacy's third priority, answers Esc for itself.
    /// What the messages of the discussion are told about being taken, which **two** treatments can now be the cause of — the context menu's lift, and Step 60's
    /// copy beside the composition bar.
    ///
    /// Computed here rather than by either modifier because only one of them may publish it: an `.environment` set further out silently overrides one set
    /// further in, so two modifiers each publishing their own view of this would mean whichever is applied last wins and the other's message is drawn twice.
    /// **The two are mutually exclusive** — each of them refuses to start while the other is up — so this is a choice between them and never a merge.
    private var theMessageBeingLifted: TheMessageBeingLifted {
        contextMenu.isUp ? contextMenu.asTheMessagesSeeIt : besideTheBar.asTheMessagesSeeIt
    }


    /// Whether the overlay took the press — and the four states are not two, which is why this is not `contextMenu.isUp`.
    ///
    /// `isUp` is *anything but idle*, and that includes `pressing`: a finger down on a message which has not yet been there long enough to mean anything. Esc
    /// does not dismiss a finger, and answering `true` there would swallow the press and leave a search running. A menu already **dismissing** does take it,
    /// there being nothing to add and Esc reaching past a menu that is visibly leaving being the more surprising of the two.
    private func theMenuAnswersTheEscape() -> Bool {
        switch contextMenu {
        case .lifted:
            // The same dismissal the backdrop's own tap performs, so the message travels back exactly as it does when the reader taps away from it.
            putTheMessageBack()
            return true
        case .dismissing:
            return true
        case .idle, .pressing:
            return false
        }
    }


    /// Puts the message back when the reply it was brought down for is dropped from the composition bar, and it is a **parity regression found on an
    /// iPhone 13 on 2026-08-27**: the reader swiped to reply, the message came down, and tapping the quote panel's close button took the quote away and left the
    /// message hanging over a blurred discussion with nothing to answer.
    ///
    /// Legacy has this and we did not. `NewSingleDiscussionViewController.userWantstoRemoveReplyToMessage(_:discussionIdentifier:)` removes the quote from the
    /// draft and then calls `hideReplyViewIfNeeded(animated: true)` — two things from one tap. Our app-side handler did only the first, and the comment there said
    /// why: *"the bar is built from the draft, so it stops showing the quotation on its own"*. That was **true until Step 60**, which gave the screen something of
    /// its own to put away, and it is the same shape as every other regression this migration has found — one behaviour that a screen assembled by hand does in
    /// passing and a screen assembled from a framework has to be told to do.
    ///
    /// **Animated, exactly as a tap on the blur is**, so there is one way for the message to go back and not two.
    private func putsTheMessageBackWhenTheReplyGoes() async {
        for await whatBecameOfIt in compositionBar.timesTheReplyWentAway() {
            switch whatBecameOfIt {
            case .theReaderDroppedIt:
                putsTheMessageBackFromTheBar()
            case .aMessageWasSentWithIt:
                fadesTheMessageAwayBesideTheBar()
            }
        }
    }


    private func answersTheEscapeKey() {
        if theMenuAnswersTheEscape() { return }
        // **Before the search, and that is legacy's own order** — its `inputEscape` dismisses the reaction context view, then the reply, then whatever is
        // presented. A reply holds a copy of the message beside the composition bar, over a blur of the discussion; Esc takes those away exactly as a tap on the blur
        // does, so there is one way out and not two. What it does *not* do is drop the reply itself: the quote stays in the bar, which is what legacy
        // leaves too — every one of its `hideReplyViewIfNeeded` call sites takes the default `shouldRemoveReplyTo: false`. A second Esc then reaches the
        // app, which is what removes the quote.
        if theMessageBesideTheBarAnswersTheEscape() { return }
        if search.isRunning { stopSearching(); return }
        if selection.isRunning { stopSelectingMessages(); return }
        screenActions.userPressedEscapeWithNothingOnThisScreenToDismiss(discussionIdentifier: discussionIdentifier)
    }

    /// Answers the keyboard's find shortcuts, for as long as this screen is on show.
    ///
    /// **They mean exactly what the search bar's own controls mean**, and are answered by the same three calls, so there is one implementation of stepping through the
    /// results rather than one per way of asking. ⌘F on a search already running is left alone, which is what legacy does — its `userWantsToStartNewSearch()` is
    /// called twice on iOS and says so.
    private func answersTheFindShortcuts() async {
        for await shortcut in findShortcuts.shortcutsAskedFor() {
            switch shortcut {
            case .find:
                startASearch()
            case .findNext:
                guard search.isRunning else { continue }
                search.goesToTheNextResult()
            case .findPrevious:
                guard search.isRunning else { continue }
                search.goesToThePreviousResult()
            }
        }
    }

    /// How ⌘F and its two companions reach this screen, the responder chain that carries them being answered far above it. See ``WhatTheFindShortcutsAsk``.
    private let findShortcuts: WhatTheFindShortcutsAsk

    /// How the composition bar says the reply being answered has gone. See ``WhatTheCompositionBarAsks`` for why the screen has to be told at all.
    private let compositionBar: WhatTheCompositionBarAsks

    /// How the screen learns that the push that brought it in has finished — see ``WhenTheScreenHasFinishedArriving``, and the entry, which waits for it before
    /// uncovering the transcript.
    private let whenTheScreenHasFinishedArriving: WhenTheScreenHasFinishedArriving

    public init(discussionIdentifier: ObvDiscussionIdentifier, dataSources: DataSources, actions: any SingleDiscussionCellViewActions, screenActions: any SingleDiscussionViewActions, initialModel: Model, initialValues: InitialValues, composeBar: AnyView, findShortcuts: WhatTheFindShortcutsAsk, compositionBar: WhatTheCompositionBarAsks, whereTheReaderWantsToGo: WhereTheReaderWantsToGo, whenTheScreenHasFinishedArriving: WhenTheScreenHasFinishedArriving) {
        self.whereTheReaderWantsToGo = whereTheReaderWantsToGo
        self.whenTheScreenHasFinishedArriving = whenTheScreenHasFinishedArriving
        self.discussionIdentifier = discussionIdentifier
        self.dataSources = dataSources
        self.actions = actions
        self.screenActions = screenActions
        self.initialModel = initialModel
        self.initialValues = initialValues
        self.composeBar = composeBar
        self.findShortcuts = findShortcuts
        self.compositionBar = compositionBar
        self.attachmentFrames = actions.attachmentFrames
        self.reportsWhatTheReaderIsLookingAt = { onScreenNow, seenSinceTheLastReport in
            screenActions.messagesAreOnScreen(discussionIdentifier: discussionIdentifier,
                                              onScreenNow: onScreenNow,
                                              seenSinceTheLastReport: seenSinceTheLastReport)
        }
        self.itemsWereDroppedOnTheMessages = { itemProviders in
            screenActions.userDroppedItemsOnTheMessages(discussionIdentifier: discussionIdentifier, itemProviders: itemProviders)
        }
        self.theReaderClickedOnTheMessages = {
            screenActions.userClickedOnTheMessages(discussionIdentifier: discussionIdentifier)
        }
    }

    /// What the list says, and the app answers: what the reader is looking at, that something was dropped on the messages, and, on a Mac, that the messages were
    /// clicked. See `SingleDiscussionViewActions`.
    ///
    /// **Built once, in the initialiser, and never in the body.** A new closure never compares equal to the previous one. Handed new ones at each redraw of
    /// this screen, the list ran its own body each time and compared every row of the discussion: about 133 ms on an iPhone Xs for 4,760 messages, once per
    /// character typed in the search.
    private let reportsWhatTheReaderIsLookingAt: (_ onScreenNow: Set<CellIdentifier>, _ seenSinceTheLastReport: Set<CellIdentifier>) -> Void
    private let itemsWereDroppedOnTheMessages: ([NSItemProvider]) -> Void
    private let theReaderClickedOnTheMessages: () -> Void

    /// Observed **here and nowhere else**, so that the one thing a tile cares about reaches it as an environment value rather than as an object every tile watches.
    /// See ``AttachmentFrames``.
    @ObservedObject private var attachmentFrames: AttachmentFrames

    /// How many arrivals have finished fading in, counted rather than flagged so that each one is a change the list can act on.
    ///
    /// A message arriving is two movements in sequence: it appears where it is, and then the transcript scrolls to it. This is the join between them. The list
    /// decides *whether and what* to follow at the moment the identifiers change — which has to be before the insertion, so that the gate reads where the reader
    /// was rather than where the new row has put them — and acts when this says the appearance is over. See
    /// `SingleDiscussionCellsListView.theMessageToScrollToOnceItHasAppeared`.
    ///
    /// `&+=` because it only has to *change*; what it counts to is of no interest, and it must not trap after a very long conversation.
    @State private var arrivalsThatHaveFinishedAppearing = 0


    /// How a row leaves — a message deleted, the *"N new messages"* marker going away — and **nothing at all for a row that arrives**.
    ///
    /// **Why an arrival needs no animation.** A message sent from the end is inserted *below* the visible area, behind the composition bar, and only then
    /// is the transcript scrolled to it. There is nothing on screen to fade in. Measured: **eleven of fifteen** sends produced no animation at all, while
    /// the four that did cost 135–178ms for a fade nobody could see. It was being paid for where it was invisible and skipped where it would have shown.
    ///
    /// **Why a departure needs one.** A row that leaves is on screen by definition, and its space closes up. Unanimated, it disappears and the rows below
    /// jump.
    ///
    /// **It is two questions, not one.** The marker is not among ``Model/cellIdentifiers`` — the list inserts it as a row of its own. A message arriving
    /// while a marker is up appends to the identifiers *and* removes the marker in the same yield, so the identifiers alone say *nothing left* while a
    /// visible row is leaving. ``Model/newMessages`` changing is the second question, asked as a plain inequality rather than by working out whether the
    /// marker is really going: that arithmetic belongs to the list, which owns the marker.
    ///
    /// **Not `.default`**, which is a spring from iOS 17 and is erratic rather than slow: two sends seconds apart gave 62ms and 386ms of stillness,
    /// `.removed` firing when SwiftUI judges a spring settled, which depends on the size of what moved. A curve is predictable and has no tail to wait
    /// through, so the completion keeps the guarantee that it fires when the movement has stopped.
    ///
    /// **0.2s is a first choice, not a measurement.** Two attempts to predict it from a transfer function were wrong, and the second is worth remembering:
    /// it was derived from two samples that both happened to be the animating case, and **two samples of a bimodal quantity look like a measurement and
    /// are worse than none.**
    private static let theWayARowLeaves: Animation = .easeOut(duration: 0.2)




    private func onTask() async {
        do {
            let (streamUUID, stream) = try await dataSources.dataSource.getAsyncStreamOfSingleDiscussionViewModel(discussionIdentifier: discussionIdentifier)
            defer { dataSources.dataSource.finishAsyncStreamOfSingleDiscussionViewModel(discussionIdentifier: discussionIdentifier, streamUUID: streamUUID) }
            for await receivedModel in stream {
                // The *first* model is the discussion appearing, and not a change to it: there was nothing on screen to animate from. Animating it puts the
                // list's initial move to the end of the discussion inside an animated transaction, which is seen, on entering, as a fast scroll down.
                guard let previousModel = streamedModel else {
                    streamedModel = receivedModel
                    continue
                }
                // **Whether the marker's *row* came or went — its presence, and never its contents** — corrected 2026-08-28, and the difference was worth a
                // screenful. ``Model/newMessages`` is the *set* of messages that count as new, so a message arriving while the marker is up **joins that set**:
                // 6 → 7, the value changes, and the test that read the value called that a row leaving. It is not. The marker row stays exactly where it was and
                // relabels, which needs no animation of any kind — and the cost of pretending otherwise was that **every arrival while the marker was up animated
                // the whole list change over 0.2s**, re-measuring the collection view inside an animation while the follow scroll was also running. What the
                // reader saw was one frame with the transcript several hundred points out of place, and it went away the moment they repeated the walk with the
                // marker scrolled off the screen. Three things were writing the geometry for one event; this removes the one that was never meant to be there.
                //
                // The marker can also *move*, which would be a row change — but only if the **earliest** new message changes, and an arrival adds a later one.
                // Were the earliest deleted, the identifiers change and the prefix test below catches it. So its presence is the whole question, and it is asked
                // here, once, because both branches ask it.
                //
                // **And only its going, not its coming** — the second half of the same correction, made when the reader found the bad frame surviving in exactly
                // one case: a message that makes the marker *appear* while also taking the date line off the message above it. Step 59 settled this for rows and
                // the marker was never brought into line with it — *"for the message appearing at the bottom, it's perfect, no need to fade. But we certainly do
                // need to fade when a cell leaves."* The reason an arrival needs no animation is that it is inserted **below the visible area**, and the marker
                // goes immediately before the first *new* message, which is at the end of the transcript for the same reason. Its departure keeps the fade,
                // which is what this branch was written for: the reader goes away, the set is re-derived, and the marker has to leave.
                let theMarkerWent = previousModel.newMessages != nil && receivedModel.newMessages == nil
                // What is worth animating is a message arriving or disappearing — a change to the *list*. Everything else this model carries describes a message
                // already on screen, its status above all, and animating that from here animates the whole cell: it is seen growing and settling back as the
                // send indicator resolves. A change confined to one message is for the view that draws it to animate, scoped to the part that changed.
                guard receivedModel.cellIdentifiers != previousModel.cellIdentifiers else {
                    // **The one exception, and it is a row appearing or going after all**. The unread marker is not a message, so it comes and goes
                    // without the identifiers changing: the reader goes away, the set is re-derived, and the marker has to leave. Unanimated it simply vanishes,
                    // which is what it did until this branch existed.
                    //
                    // **Animated, but deliberately not as an arrival.** The branch below also says *the appearance has finished*, which is what makes the list
                    // scroll to whatever just arrived — and nothing has arrived here, so borrowing it would send the transcript to the last message because a
                    // marker went away.
                    //
                    // A status change reaching the screen in the same value as a marker reset would be animated with it, and would be seen settling; it needs two
                    // things to land in one yield of the stream, and the alternative is to leave the marker vanishing abruptly on every reset.
                    if theMarkerWent {
                        withAnimation(Self.theWayARowLeaves) { streamedModel = receivedModel }
                    } else {
                        streamedModel = receivedModel
                    }
                    continue
                }
                // **And say when that animation has finished**, which is what the list waits for before following the message that arrived. The
                // arrival is deliberately two movements in sequence rather than one: the message fades in where it is, and only then does the transcript scroll
                // to it. Overlapping them makes the row's height and the scroll offset two animations of the same event, which either cancel or compound, and
                // which of those happens is not something to reason about.
                //
                // **`completionCriteria: .removed`, and not a `Task.sleep` matched to the duration.** A sleep is a hand-copied duplicate that drifts the moment
                // anybody retunes the animation, and it ignores the animation altogether — under Debug ▸ Slow Animations the fade would still be running when
                // the clock ran out. `.removed` rather than `.logicallyComplete` because what is being waited for is *it has stopped moving*.
                //
                // **And the animation is named rather than left to the default**, and it is the one part of that step that survived it: see
                // ``theWayARowLeaves``.
                if #available(iOS 17.0, *) {
                    // **Two questions, because the marker is not one of ``Model/cellIdentifiers``** — the list inserts it as a row of its own from
                    // ``Model/newMessages``. So a message arriving while a marker is up is a *pure append* of the identifiers, which the prefix test rightly calls
                    // *nothing left* — while the marker vanishes at the same instant. Asked of the identifiers alone, this cannot see the marker at all, and the
                    // reader found exactly that: a deletion faded and the *"N new messages"* row popped.
                    //
                    // **Its going and not its contents, nor its coming**, for which see ``theMarkerWent`` above: a message arriving while the marker is up joins
                    // the set of new messages without the marker's row going anywhere, and one that makes the marker appear puts it below the visible area — and
                    // animating either was what put a frame of this screen several hundred points out.
                    let aRowIsLeaving = !previousModel.cellIdentifiersAreAPrefixOf(receivedModel) || theMarkerWent
                    withAnimation(aRowIsLeaving ? Self.theWayARowLeaves : nil, completionCriteria: .removed) {
                        streamedModel = receivedModel
                    } completion: {
                        arrivalsThatHaveFinishedAppearing &+= 1
                    }
                } else {
                    // iOS 16 never reaches the list this serves — it shows the placeholder instead — so there is nothing here to tell.
                    //
                    // **This is the one seam that decides whether iOS 16 is affordable, and today it degrades in silence.** Nothing here increments
                    // ``arrivalsThatHaveFinishedAppearing``, so on iOS 16 a message that arrives would simply never be followed, and no line anywhere would say
                    // so. That is harmless while the screen shows a placeholder there and is the worst kind of fallback the moment it does not. Whenever iOS 16
                    // is decided, this must become a *stated* trade rather than an absence — most likely scrolling at once and letting the fade and the scroll
                    // overlap, which is worse than sequencing them but is a choice somebody made.
                    withAnimation { streamedModel = receivedModel }
                }
            }
        } catch {
            assertionFailure()
        }
    }


    /// Follows who the reader is talking to, for as long as this screen is up: a contact renamed, a group gaining a member, a discussion becoming locked.
    ///
    /// Animated, unlike the model of the list: a header changing is one small thing in a bar changing, and there is nothing below it to be moved by it.
    private func followsTheHeader() async {
        do {
            let (streamUUID, stream) = try await dataSources.dataSource.getAsyncStreamOfDiscussionHeader(discussionIdentifier: discussionIdentifier)
            defer { dataSources.dataSource.finishAsyncStreamOfDiscussionHeader(discussionIdentifier: discussionIdentifier, streamUUID: streamUUID) }
            for await receivedHeader in stream {
                guard receivedHeader != header else { continue }
                withAnimation { streamedHeader = receivedHeader }
            }
        } catch {
            assertionFailure()
        }
    }


    // MARK: The context menu of a message


    /// Follows what the reader's finger is doing to the messages, for as long as this screen is up. See ``PressesOnMessages``.
    private func followsThePressesOnMessages() async {
        for await press in pressesOnMessages.pressesToFollow() {
            switch press {
            case .began(let cellIdentifier):
                aFingerWentDown(on: cellIdentifier)
            case .ended(let cellIdentifier):
                theFingerLeft(cellIdentifier)
            case .heldLongEnough(let cellIdentifier, showing: let model):
                lift(cellIdentifier, showing: model)
            case .askedToReplyTo(let cellIdentifier, showing: let model, pulledAcrossBy: let pulledAcrossBy):
                // The swipe's half of Step 60. The reply itself was asked for by the gesture; this is the message coming down beside the bar.
                holdsTheMessageBesideTheBar(cellIdentifier, showing: model, pulledAcrossBy: pulledAcrossBy)
            case .draggedAway:
                thePressBecameADrag()
            }
        }
    }


    /// The press turned into a drag: the reader held a message and then moved, and its files are on their way out.
    ///
    /// **Whatever the press was becoming stops.** A message travelling out of the discussion is not one the reader is choosing an action for, so a menu that had
    /// opened is put back and a press that had not yet become one is abandoned. This is what UIKit's own pair does for itself — one press, and the movement decides
    /// which of the two it meant. Ours has to be told, because the drag is UIKit's and the menu is not.
    private func thePressBecameADrag() {
        switch contextMenu {
        case .pressing:
            contextMenu = .idle
        case .lifted:
            putTheMessageBack()
        case .idle, .dismissing:
            break
        }
    }


    private func aFingerWentDown(on cellIdentifier: CellIdentifier) {
        // A press arriving while something is already up is ignored rather than queued: the backdrop is what takes touches then, and this can only be a stray one.
        guard contextMenu == .idle else { return }
        contextMenu = .pressing(cellIdentifier)
        // **Warmed here, a quarter of a second before it is needed.** See ``theKnockWhenAMessageIsLifted``.
        theKnockWhenAMessageIsLifted.prepare()
    }


    /// The finger left, which cancels a press that had not yet been held long enough.
    ///
    /// **This is also said after a press that *was* recognised**, when the finger finally lifts — which is why it is guarded on the state rather than trusted to
    /// mean a cancellation. Without the guard, letting go of a message would put it straight back down again.
    private func theFingerLeft(_ cellIdentifier: CellIdentifier) {
        guard contextMenu == .pressing(cellIdentifier) else { return }
        contextMenu = .idle
    }


    /// Lifts a message out of the discussion: the invisible swap, and then the one animation.
    ///
    /// **The order is the reason the change cannot be seen.** The real message is hidden and its copy placed at exactly the frame it already occupied, inside a
    /// transaction with animations disabled; only then is ``theMessageIsUp`` set inside a spring.
    ///
    /// What the message *is* arrives with the press, from the cell that is drawing it — see ``PressOnAMessage/heldLongEnough(_:showing:)``. What it *offers* is
    /// asked for here and nowhere else, at press time and for the one message pressed, on the main thread and against the view context. See
    /// ``WhatAMessageOffers``, which sets out why the second cannot be part of a cell model.
    private func lift(_ cellIdentifier: CellIdentifier, showing model: SingleDiscussionCellView.Model) {

        // **Never while a message is already down beside the composition bar**. The two are the screen's two full-screen treatments and they may
        // never both be up: a blur over a blur, and two copies of two different messages with no way to tell which a tap belongs to. The refusal is here as
        // well as in ``holdsTheMessageBesideTheBar(_:showing:pulledAcrossBy:)`` because either may be asked for first.
        guard !besideTheBar.isUp else { return }

        // From a press on this message, or straight from idle — which is how VoiceOver asks, having no press to precede it.
        switch contextMenu {
        case .idle:
            break
        case .pressing(let cellIdentifierPressed) where cellIdentifierPressed == cellIdentifier:
            break
        case .pressing, .lifted, .dismissing:
            return
        }

        // A message that offers nothing has no menu to draw. Not worth a lift, and not worth an assertion: a message deleted between the finger going down and the
        // press being recognised is a race the reader can win.
        let offers = dataSources.cellViewDataSource.whatTheMessageOffers(cellIdentifier: cellIdentifier)
        guard !offers.isEmpty else {
            contextMenu = .idle
            return
        }

        // Asked in the same breath, and only when there is a bar to draw — see ``TheEmojisOnOffer``.
        let emojis = offers.offersToReact ? dataSources.cellViewDataSource.whatTheReaderMayReactWith(cellIdentifier: cellIdentifier) : .none

        // The knock as the message comes up, which is what UIKit's own context menu gives and what the reader's finger is waiting for. Prepared when the finger went
        // down — see ``theKnockWhenAMessageIsLifted``.
        theKnockWhenAMessageIsLifted.impactOccurred()

        var theSwap = Transaction()
        theSwap.disablesAnimations = true
        withTransaction(theSwap) {
            contextMenu = .lifted(.init(cellIdentifier: cellIdentifier, model: model, offers: offers, emojis: emojis))
            theMessageIsUp = false
        }

        withAnimation(reduceMotion ? TheContextMenuOfAMessage.theLiftWithReducedMotion : TheContextMenuOfAMessage.theLift) {
            theMessageIsUp = true
        }

    }


    /// Puts the message back where it came from.
    ///
    /// **The real message is given back on a later frame than the copy's arrival**, never at the same moment: the two overlapping is what produces a double image,
    /// which is the one artefact this whole arrangement exists to avoid. So the state stays `dismissing` — and the real message stays hidden — for as long as the
    /// return takes.
    private func putTheMessageBack(andThen whatToDoNext: (() -> Void)? = nil) {

        guard case .lifted(let lifted) = contextMenu else { whatToDoNext?(); return }
        contextMenu = .dismissing(lifted)

        let theReturn = reduceMotion ? TheContextMenuOfAMessage.theReturnWithReducedMotion : TheContextMenuOfAMessage.theReturn

        // **The animation says when it is done; a clock does not get to guess.** This used to sleep for a hand-copied
        // duplicate of the animation's duration, which is wrong in two ways. It drifts the moment anybody tunes the spring
        // — and it ignores the animation entirely, so under Debug ▸ Slow Animations the copy began its slow journey back
        // and then vanished mid-flight, the timer having run out on a clock the animation was no longer keeping. That is
        // how it was noticed; it was already fragile without it.
        //
        // `.removed` rather than `.logicallyComplete`: the real message may only come back once the copy has stopped
        // moving altogether. Hiding it a fraction too long is invisible, and un-hiding it too early is the double image
        // this whole arrangement exists to avoid.
        if #available(iOS 17.0, *) {
            withAnimation(theReturn, completionCriteria: .removed) {
                theMessageIsUp = false
            } completion: {
                giveTheMessageBack(andThen: whatToDoNext)
            }
        } else {
            // iOS 16 has no completion, so the clock is all there is. Unreachable in practice — the list this overlay
            // draws over is iOS 18 — and kept so the module still compiles for its deployment target.
            withAnimation(theReturn) {
                theMessageIsUp = false
            }
            Task { @MainActor in
                try? await Task.sleep(seconds: reduceMotion ? TheContextMenuOfAMessage.howLongTheReturnTakesWithReducedMotion : TheContextMenuOfAMessage.howLongTheReturnTakes)
                giveTheMessageBack(andThen: whatToDoNext)
            }
        }

    }


    /// Gives the real message back, the copy having finished travelling to it.
    ///
    /// **Guarded on still being in the middle of a dismissal**, which the timer above never was: the overlay can be taken
    /// away while one is running — a rotation, or the message being deleted — and the reader can then lift something else
    /// before this arrives. Ungarded, a completion belonging to a dismissal nobody is watching any more would put that new
    /// lift straight back down.
    private func giveTheMessageBack(andThen whatToDoNext: (() -> Void)? = nil) {
        guard case .dismissing = contextMenu else { return }
        var theSwap = Transaction()
        theSwap.disablesAnimations = true
        withTransaction(theSwap) { contextMenu = .idle }
        // **Step 60's reply waits for this and not for a clock.** Choosing *Reply* has to put the menu away and then take the same message down beside the
        // composition bar, and the two must not be on screen together — two copies of one message travelling in opposite directions. Legacy separates them with
        // `DispatchQueue.main.asyncAfter(deadline: .now() + 0.5)`; here the menu's own return animation says when it is finished, which is the same intent
        // without a hand-copied duration. Under Debug ▸ Slow Animations this waits longer, correctly, where a timer would not.
        whatToDoNext?()
    }


    /// Takes the overlay away without animating anything, for the two occasions on which there is nothing left to animate back to: the geometry changing under it
    /// — a rotation, a window resized on iPad — and the message itself being deleted while it is up.
    private func takeTheOverlayAwayAtOnce() {
        guard contextMenu.isUp else { return }
        var theSwap = Transaction()
        theSwap.disablesAnimations = true
        withTransaction(theSwap) {
            contextMenu = .idle
            theMessageIsUp = false
        }
    }




    // MARK: - The message beside the composition bar — Step 60


    /// Brings a message down beside the composition bar, a blur coming up over the discussion behind it.
    ///
    /// **The order is the reason nothing is seen to jump**, and it is the same order the context menu's lift uses: the real message is hidden and its copy placed
    /// at exactly the frame it already occupied, inside a transaction with animations disabled; only then is ``theMessageIsDown`` set inside one animation.
    ///
    /// **The frame it already occupied is where the swipe left it**, which is eighty-odd points from its row — hence `pulledAcrossBy`. Placing the copy at the
    /// row instead put it that far from where the reader was looking, and hid the real message before its spring home could be seen at all.
    ///
    /// **And it is asked for *before* the reply reaches the draft**, which is where this departs from legacy and what lets the timer go. Legacy writes the reply,
    /// waits half a second for the composition bar to have grown its quote panel, and only then reads the bar's top edge to work out where to put the message —
    /// a number, so it has to be read late. Here the resting place is not a number at all: the copy is laid out against the space below the messages, which the
    /// layout reports, so the bar may grow after the journey has begun and the message still lands where it belongs. See
    /// ``TheMessageHeldBesideTheCompositionBar/spaceBelowTheMessages``.
    private func holdsTheMessageBesideTheBar(_ cellIdentifier: CellIdentifier, showing model: SingleDiscussionCellView.Model, pulledAcrossBy: CGFloat) {

        // **Never while the context menu is up**, the two being the screen's two full-screen treatments — see ``lift(_:showing:)``, which refuses the other way
        // round. In practice the menu's Reply waits for its own dismissal before calling this, so what this catches is the swipe arriving while a menu is open.
        guard !contextMenu.isUp else { return }
        // And never twice: a second swipe while a message is already down is ignored rather than queued, the blur being what takes touches by then. This is
        // true because the swipe asks for the reply and the copy in one breath, so there is no window in which the bar quotes one message and holds another.
        guard case .none = besideTheBar else { return }

        var theSwap = Transaction()
        theSwap.disablesAnimations = true
        withTransaction(theSwap) {
            besideTheBar = .beside(.init(cellIdentifier: cellIdentifier, model: model, handedOver: nil, pulledAcrossBy: pulledAcrossBy))
            theMessageIsDown = false
        }

        theJourneyDownMayBegin()

        // **After the guards, so a refusal never says it.** Legacy says this earlier — before the reply has even reached the draft — so its quote panel is built
        // folded. Ours says it as the journey begins, which on the menu's path is a third of a second later, and what the reader sees is the quote's body
        // sliding away as the message itself arrives to replace it. That reads as one movement rather than as a correction, and it was preferred to saying it
        // from both of this method's callers and having to unsay it when a guard refuses.
        screenActions.aMessageIsShownBesideTheCompositionBar(discussionIdentifier: discussionIdentifier, isShown: true)

    }


    /// Takes the message away again: the blur goes, the copy fades where it sits, and the real message comes back up in the transcript.
    ///
    /// **All three in one animation, and the copy does not travel back.** That is what legacy does — `HidableView.hide()` fades the blur, puts the original back
    /// to `alpha 1` and the snapshot to `alpha 0` inside a single 0.2s animator — and it is a deliberate exception to the rule Step 21b wrote against a
    /// crossfade. That rule exists because a copy fading out *over* its original reads as a double image; here the two are at opposite ends of the screen.
    ///
    /// **The reply itself is kept.** Every one of legacy's `hideReplyViewIfNeeded` call sites takes the default `shouldRemoveReplyTo: false`, and the quote stays
    /// in the composition bar — which is exactly what the reader sees in the recording this was measured from. Removing the quote is the app's, through
    /// `userWantstoRemoveReplyToMessage`, and is what a *second* Esc reaches.
    private func putsTheMessageBackFromTheBar() {
        takesTheMessageAwayFromTheBar(.travellingHomeToItsRow)
    }


    /// Takes the copy away without flying it anywhere, which is what a **send** asks for — added 2026-08-28.
    ///
    /// The reply has become a message, so there is nothing to give back and nothing for a journey home to say. Flying it home anyway put a copy across the screen
    /// at the same moment the sent message arrived at the end of the discussion and the transcript scrolled to meet it, which the reader saw as *"too much on
    /// screen"*. See ``TheMessageBesideTheCompositionBar/TheWayItLeaves`` for why this is a second departure rather than a setting on the first.
    private func fadesTheMessageAwayBesideTheBar() {
        takesTheMessageAwayFromTheBar(.fadingWhereItSits)
    }


    /// The one way out, taken two ways — see ``TheMessageBesideTheCompositionBar/TheWayItLeaves``.
    ///
    /// **The animation is the same and only what it carries differs**, which is what keeps this one function rather than two: both departures fade the blur over
    /// ``TheMessageBesideTheCompositionBar/theWayOut``, both end on the animation saying so, and both give the message back in the same place.
    private func takesTheMessageAwayFromTheBar(_ theWayItLeaves: TheMessageBesideTheCompositionBar.TheWayItLeaves) {

        guard case .beside(let beside) = besideTheBar else { return }

        let theWayOut = reduceMotion ? TheMessageBesideTheCompositionBar.theWayOutWithReducedMotion : TheMessageBesideTheCompositionBar.theWayOut

        // **`theMessageIsDown` is left alone when the copy is fading**, and that is the whole of the difference: false is what sends the copy travelling to
        // ``whereTheJourneyRestsWhenItIsNotDown``, so a copy that must not move has to stay down. It is put back to false once there is nothing being drawn, in
        // ``theMessageHasGoneFromBesideTheBar()``.
        let theCopyTravels = theWayItLeaves == .travellingHomeToItsRow

        // The animation says when it is done; a clock does not get to guess. `.removed` rather than `.logicallyComplete`, the thing being waited for being *it
        // has stopped moving*. See ``putTheMessageBack()`` beside this, where the same lesson was learnt under Slow Animations.
        if #available(iOS 17.0, *) {
            withAnimation(theWayOut, completionCriteria: .removed) {
                // **Inside the animation, and that is Step 64's doing.** `leaving` is what turns the copy's resting place from *where its journey began* into
                // *the message's own row*, and it also stands the handover's residual scale down. Set outside the animation, a reader who dismisses **mid-journey**
                // would see that residual scale — up to 4% — snap rather than settle. Inside it, both changes are carried by the same 0.2s the copy travels on.
                besideTheBar = .leaving(beside, theWayItLeaves)
                if theCopyTravels { theMessageIsDown = false }
            } completion: {
                theMessageHasGoneFromBesideTheBar()
            }
        } else {
            // iOS 16 has no completion, so the clock is all there is. Unreachable in practice — the list this is drawn over is iOS 18 — and kept so the module
            // still compiles for its deployment target.
            withAnimation(theWayOut) {
                besideTheBar = .leaving(beside, theWayItLeaves)
                if theCopyTravels { theMessageIsDown = false }
            }
            Task { @MainActor in
                try? await Task.sleep(seconds: TheMessageBesideTheCompositionBar.howLongTheWayOutTakes)
                theMessageHasGoneFromBesideTheBar()
            }
        }

    }


    /// The copy has finished fading; there is nothing left to draw.
    ///
    /// **Guarded on still being in the middle of one**, for the reason ``giveTheMessageBack(andThen:)`` is: this can be taken away while the animation runs — the
    /// message deleted, the geometry changing — and the reader can then ask for another reply before this arrives. Unguarded, a completion belonging to a
    /// dismissal nobody is watching would take the new one straight back down.
    private func theMessageHasGoneFromBesideTheBar() {
        guard case .leaving = besideTheBar else { return }
        var theSwap = Transaction()
        theSwap.disablesAnimations = true
        withTransaction(theSwap) {
            besideTheBar = .none
            // **A no-op for the departure that travels and necessary for the one that fades**, which leaves the copy down so that it does not move. Said here
            // rather than left to the next reply to correct, so that *nothing is down* and *the message is not down* never disagree.
            theMessageIsDown = false
            theCopyIsStillOnItsWayDown = false
        }
        screenActions.aMessageIsShownBesideTheCompositionBar(discussionIdentifier: discussionIdentifier, isShown: false)
    }


    /// Hands the context menu's lifted copy straight to the composition bar, with no journey home in between.
    ///
    /// **The fault this removes is a redundant movement, not a slow animation.** The menu lifts the message out of its row; choosing *Reply* used to send it
    /// **back** to that row and wait for the spring to be `.removed` before Step 60 took it **down** to the bar. Three movements, the middle one returning a
    /// message to a place it immediately left.
    ///
    /// **One transaction with animations disabled**, which is why nothing is seen to change hands: both treatments hold the same message from the same anchor,
    /// so in one frame the menu stops drawing its copy and Step 60 starts drawing it at the same displacement. The blur is **swapped rather than crossfaded**
    /// — two `.regularMaterial`s over one another are visibly darker than either.
    ///
    /// **The exclusion of the two treatments is stronger after this, not weaker**, which was the risk the plan named. It used to rest on the menu being gone
    /// before Step 60 began; now there is no instant at which both are up — `contextMenu` goes to `.idle` and `besideTheBar` to `.beside` in the one
    /// transaction, so ``theMessageBeingLifted`` resolves to Step 60 without ever falling back to nothing, and the real message is never given back.
    ///
    /// **What is not animated away is the card.** The menu's card, its emoji bar and its backdrop all go in that one frame. That is what this trades for the
    /// wait, and it is deliberate: fading the card would mean its backdrop living alongside Step 60's for the length of the fade, which is the crossfade this
    /// avoids. If it reads abruptly, the answer is a menu that fades its card while giving up its backdrop — a change in ``TheContextMenuOfAMessage``.
    private func handsTheMessageOverToTheBar(_ cellIdentifier: CellIdentifier, showing model: SingleDiscussionCellView.Model, from theCopy: TheCopyTheMenuHandsOver) {

        // Only from a menu that is actually up, and only onto a bar holding nothing. Neither can fail as things stand — the entry cannot be chosen otherwise —
        // and both are here because the two treatments' exclusion is asserted at every door rather than reasoned about at any of them.
        guard case .lifted = contextMenu, case .none = besideTheBar else { return }

        var theSwap = Transaction()
        theSwap.disablesAnimations = true
        withTransaction(theSwap) {
            contextMenu = .idle
            theMessageIsUp = false
            // Nothing pulled it aside: the menu's copy is already where it is, and `handedOver` is what says so on this path.
            besideTheBar = .beside(.init(cellIdentifier: cellIdentifier, model: model, handedOver: theCopy, pulledAcrossBy: 0))
            theMessageIsDown = false
        }

        // Said as the journey begins, exactly as the swipe's door says it — see ``holdsTheMessageBesideTheBar(_:showing:pulledAcrossBy:)``, which explains why
        // the bar is told at this moment rather than earlier.
        screenActions.aMessageIsShownBesideTheCompositionBar(discussionIdentifier: discussionIdentifier, isShown: true)

        theJourneyDownMayBegin()

    }


    /// Sends the copy on its way — the single animation the eye sees, and the one place either door starts it.
    ///
    /// Said in the same turn as the placement, as it always has been. What the band does *after* that is the copy's own business; see
    /// ``TheMessageHeldBesideTheCompositionBar/theJourneyTakesItsNewDestination()``, which is where a destination that moves mid-flight is answered.
    private func theJourneyDownMayBegin() {
        guard case .beside(let beside) = besideTheBar, !theMessageIsDown else { return }
        let theJourney = reduceMotion ? TheMessageBesideTheCompositionBar.theJourneyDownWithReducedMotion : TheMessageBesideTheCompositionBar.theJourneyDown
        if #available(iOS 17.0, *) {
            theCopyIsStillOnItsWayDown = true
            // The animation says when the copy has landed; a clock does not get to guess. `.removed` rather than `.logicallyComplete`, the thing being waited for
            // being *it has stopped moving*.
            withAnimation(theJourney, completionCriteria: .removed) {
                theMessageIsDown = true
            } completion: {
                theCopyHasLandedBesideTheBar(beside.cellIdentifier)
            }
        } else {
            // iOS 16 has no completion, and rather than time the spring by hand the copy is simply never held: it reads the band live throughout, as it did
            // before the journey took a destination of its own. Unreachable in practice — the list this is drawn over is iOS 18.
            withAnimation(theJourney) {
                theMessageIsDown = true
            }
        }
    }


    /// The copy has stopped moving, so the band is read live from here on.
    ///
    /// **Guarded on the reply it belongs to**, for the reason ``theMessageHasGoneFromBesideTheBar()`` is guarded: a reader who dismisses mid-journey and replies
    /// to something else leaves this completion in the air, and unguarded it would stand the *new* journey's retargeting down mid-flight.
    private func theCopyHasLandedBesideTheBar(_ cellIdentifier: CellIdentifier) {
        guard case .beside(let beside) = besideTheBar, beside.cellIdentifier == cellIdentifier else { return }
        theCopyIsStillOnItsWayDown = false
    }


    /// Takes it away with nothing animated, for the two occasions on which there is nothing left to animate: the geometry changing under it, and the message
    /// itself being deleted while it is down.
    private func takesTheMessageBesideTheBarAwayAtOnce() {
        guard besideTheBar.isUp else { return }
        var theSwap = Transaction()
        theSwap.disablesAnimations = true
        withTransaction(theSwap) {
            besideTheBar = .none
            theMessageIsDown = false
            theCopyIsStillOnItsWayDown = false
        }
        screenActions.aMessageIsShownBesideTheCompositionBar(discussionIdentifier: discussionIdentifier, isShown: false)
    }


    /// Whether Step 60's copy takes the Esc — and, as with the menu, a treatment already *leaving* takes it too, there being nothing to add and Esc reaching past
    /// something visibly going being the more surprising of the two.
    private func theMessageBesideTheBarAnswersTheEscape() -> Bool {
        switch besideTheBar {
        case .beside:
            // The same dismissal the blur's own tap performs, so there is one way out of this and not two.
            putsTheMessageBackFromTheBar()
            return true
        case .leaving:
            return true
        case .none:
            return false
        }
    }


    /// Carries out what the reader chose, and puts the message back first.
    ///
    /// **The order was always intended and, until 2026-08-30, was not enforced.** This said *puts the message back first* and then fired the action in the same
    /// turn — but ``putTheMessageBack(andThen:)`` only **starts** a spring, so a sheet went up while the copy of the message was still travelling under it, and
    /// the flight was what looked wrong. An entry that presents something now waits for that return to have *finished*, on the animation's own completion rather
    /// than on a clock, which is exactly what Step 60's `Reply` already did.
    ///
    /// **Only the entries that cover the screen wait.** The rest change the message rather than hiding it, and their result is better written while it is on its
    /// way home than a third of a second after it lands — the bar of favourites being the quickest thing in this menu. Which is which is answered by
    /// ``MessageAction/putsSomethingOverTheScreen``, on the action rather than here, so that adding an entry cannot quietly miss it.
    private func choose(_ action: MessageAction, on cellIdentifier: CellIdentifier, showing model: SingleDiscussionCellView.Model, theCopyAsItStands: TheCopyTheMenuHandsOver) {
        // **Reply hands the copy over rather than sending it home first**, and it waits on that handover exactly as the branch below waits on the
        // return. See ``handsTheMessageOverToTheBar(_:showing:from:)``.
        if action == .reply {
            handsTheMessageOverToTheBar(cellIdentifier, showing: model, from: theCopyAsItStands)
        } else if action.putsSomethingOverTheScreen {
            // Nothing below this concerns these entries: `select` never reports `true`, being answered by the screen.
            putTheMessageBack(andThen: { Task { await actions.userWantsToActOnMessage(cellIdentifier: cellIdentifier, action: action) } })
            return
        } else {
            putTheMessageBack()
        }
        // **Answered here and never passed on**, which makes it the one entry of the menu the app does not see. The reason is the ellipsis's: nothing is
        // presented, the screen simply changes what it is doing — see `DiscussionEllipsisMenu`, where search is a closure for the same reason. The message
        // pressed is what the mode starts with, so a reader who wanted to delete *this one and two others* has already chosen the first.
        if action == .select {
            startSelectingMessages(startingWith: cellIdentifier)
            return
        }
        Task { await actions.userWantsToActOnMessage(cellIdentifier: cellIdentifier, action: action) }
    }


    public var body: some View {
        Group {
            // **iOS 18**, decided 2026-08-24 — see `minimum-os-version.md`. Supporting 17 costs no iPhone whatsoever and had already made the composition
            // bar worse on every device, so the screen keeps the APIs it was written for. 16 and 17 show the placeholder and get the legacy screen.
            //
            // **An empty discussion is not a reason to show the placeholder**, though this condition said so until 2026-08-26. That test dates from when the
            // placeholder *was* this screen. What it means today is that opening a **brand-new** discussion shows a line of developer text: a new discussion
            // is empty by this screen's reckoning, its one `PersistedMessageSystem` being the `.discussionIsEndToEndEncrypted` sentence, which the data source
            // excludes from the identifiers because the list draws it itself as a fixed first row.
            //
            // Nothing below needs a message to exist: `rowAndAnchor(toOpenOn:)` answers nil, so the entry asks for no scroll, the cover is lifted at once
            // rather than waiting for a settle that will never be reported, the marker is nil, and the sentence is drawn outside the `ForEach`.
            //
            // **And empty is never a loading state**, which is what makes removing the test safe rather than merely tidy: the model is computed synchronously
            // from Core Data in `SwiftUISingleDiscussionViewController.init` before this view exists, so an empty one is a fact about the discussion rather
            // than a moment before the messages arrive. Were it otherwise, this would open every discussion on a list of no rows and then *prepend* the whole
            // of it — the thing Step 44a measured a `List` failing to survive.
            if #available(iOS 18.0, *) {
                SingleDiscussionCellsListView(
                    cellIdentifiers: model.cellIdentifiers,
                    theSections: model.theSections,
                    lastCellModel: model.lastCellModel,
                    initialCellModels: initialValues.cellModels,
                    // The entry alone reads this; see the setting in `ObvMessengerSettings.Interface`.
                    newMessages: model.newMessages,
                    sentenceSayingTheDiscussionIsEndToEndEncrypted: initialValues.sentenceSayingTheDiscussionIsEndToEndEncrypted,
                    dataSource: dataSources.cellViewDataSource,
                    actions: actions,
                    // Said by the list, which is the only thing that knows what is on screen, and answered by the app. See `SingleDiscussionViewActions`.
                    reportsWhatTheReaderIsLookingAt: reportsWhatTheReaderIsLookingAt,
                    // When a message that has just arrived has finished fading in, which is when the list scrolls to it — see
                    // ``arrivalsThatHaveFinishedAppearing``.
                    arrivalsThatHaveFinishedAppearing: arrivalsThatHaveFinishedAppearing,
                    // Said by the list, which owns the collection view a drop can be answered on, and answered by the app — which puts it in the draft, exactly as a
                    // drop on the composition bar is put there. See `SingleDiscussionViewActions`.
                    itemsWereDroppedOnTheMessages: itemsWereDroppedOnTheMessages,
                    // Said by the list, on a Mac only, and answered by the app, which holds the composition bar the caret is to leave.
                    theReaderClickedOnTheMessages: theReaderClickedOnTheMessages,
                    // The ticks themselves, written by the `List`. A binding rather than a report, because a `List` owns its selection and this
                    // screen owns the mode: neither can hold both halves.
                    selectedCellIdentifiers: $selection.cellIdentifiers,
                    // Where a ⇧-click extends from, Catalyst's alone, and beside the ticks for the same reason they are here.
                    theAnchorOfTheSelection: $selection.theAnchor,
                    // What the last ⇧-click added, so that the next one can take it back, corrected on 2026-08-31. Beside the anchor because the two
                    // are one mechanism: the anchor says where a range starts and this says what the range last put there.
                    whatTheLastExtensionAdded: $selection.whatTheLastExtensionAdded,
                    theReaderIsChoosingMessages: selection.isRunning,
                    whereTheReaderWantsToGo: whereTheReaderWantsToGo)
            } else {
                Text(verbatim: "SwiftUI implementation of a single discussion")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Which attachment is flying to or from the viewer, so that its own tile draws nothing while a stand-in stands in for it.
        .environment(\.attachmentBeingPresented, attachmentFrames.attachmentBeingPresented)
        // What takes every gesture away from the messages while the reader is choosing them. See ``EnvironmentValues/theReaderIsChoosingMessages``,
        // which says why this is one value at the top of the tree rather than a decision at each gesture.
        .environment(\.theReaderIsChoosingMessages, selection.isRunning)
        // What every message body looks for in itself. **Written unconditionally and equal to nothing whenever no search is running**, so that the value on the
        // scrolling path is one that never changes — see ``EnvironmentValues/theWordsBeingLookedFor``.
        .environment(\.theWordsBeingLookedFor, search.words)
        // Whether a message sent shifts its blue as it travels up the screen. A constant for the life of the screen, so no cell is ever rebuilt on its account.
        .environment(\.sentBubbleHueVariesWithScroll, initialValues.sentBubbleHueVariesWithScroll)
        .environment(\.elasticScrolling, initialValues.elasticScrolling)
        .environment(\.whenTheScreenHasFinishedArriving, whenTheScreenHasFinishedArriving)
        // The search itself: a fetch, once the typing pauses. See ``looksForWhatIsBeingTyped(_:)``.
        .task(id: search.words) { await looksForWhatIsBeingTyped(search.words) }
        // Takes the reader to the result they are on — when the results first arrive, and then each time they step to another.
        //
        // **Driven by which result it is rather than by the stepping**, so that there is one place where a result is scrolled to instead of one per way of asking: the
        // chevrons, the keyboard shortcuts, and a fresh set of results all just change this. The list centres what it is asked for and gives up quietly if it does not
        // hold it, which is what a message deleted mid-search amounts to. See ``WhereTheReaderWantsToGo``.
        // The one-parameter form, which is deprecated from iOS 17 and is what this body can use: it compiles for iOS 16, where the form taking the previous value does
        // not exist. The list may use the newer one, being iOS 18 only.
        // A tick on a message that has since gone is forgotten — a message deleted from another device, or one wiped as it expired. See
        // ``TheSelectionOfSeveralMessages/keepsOnlyWhatIsStillThere(in:)``, which says why the selection cannot simply be trusted to age well.
        //
        // **On the identifiers and not on the mode**, so it holds while the reader is choosing rather than only as they enter.
        .onChange(of: model.cellIdentifiers) { newCellIdentifiers in
            selection.keepsOnlyWhatIsStillThere(in: newCellIdentifiers)
        }
        .onChange(of: search.theCurrentResult) { theResult in
            guard let theResult else { return }
            whereTheReaderWantsToGo.goTo(theResult)
        }
        // **Step 60, and it is applied here — before the bar is inserted — deliberately.** Everything of the context menu goes on *after* the safe-area inset
        // below, so its backdrop covers the composition bar as well as the transcript; this one must not, the reader being about to write into that bar while
        // the message sits above it. One line's difference in where a modifier is applied is the whole of the z-ordering, and it is what legacy achieves with
        // `insertSubview(replyToContainerView, belowSubview: composeMessageContainerView)`.
        .modifier(TheMessageBesideTheCompositionBarOnThisScreen(
            besideTheBar: $besideTheBar,
            theMessageIsDown: theMessageIsDown,
            theCopyIsStillOnItsWayDown: theCopyIsStillOnItsWayDown,
            cellIdentifiers: model.cellIdentifiers,
            whereTheReaderWantsToGo: whereTheReaderWantsToGo,
            dataSource: dataSources.cellViewDataSource,
            actions: actions,
            dismiss: putsTheMessageBackFromTheBar,
            dismissAtOnce: takesTheMessageBesideTheBarAwayAtOnce))
        // Inserting the bar into the safe area pins it to the bottom *and* insets the scrolled content above it, which the legacy screen has to do by
        // hand. It is also what makes the bar follow the keyboard.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // **A search takes the composition bar's place**, which is what the legacy screen does too — `configureAcessoryViewVisibility(animate:)` swaps its
            // accessory view for the results bar. In a `Group`, which ``TheBarKeepsItsMargin`` puts them in, so that whichever bar is shown is the only subview here
            // and neither is wrapped in a container of its own.
            //
            // Deliberately given no background: the messages are meant to be seen through the bar, which is what its glass effect is for. Inserting it in
            // the safe area insets the content without clipping the list, whose frame still reaches the bottom of the screen, so the messages do scroll
            // behind it — by design.
            TheBarKeepsItsMargin(theSpace: theSpaceBelowTheCompositionBar) {
                // **Choosing messages takes the same place, and is tested first.** The two modes are exclusive in both directions — starting a selection ends a
                // search and starting a search ends a selection — so the order here decides nothing that can happen; it says which of them owns the place, which is
                // worth reading off the branch rather than inferring from a method elsewhere. See ``startSelectingMessages()`` and ``startASearch()``.
                //
                // **Both halves of that are needed and only one of them was written.** Until 2026-08-31 a search begun with ⌘F while the reader was choosing
                // messages left both running, and this branch is where the consequence landed: the mode was drawn, the field was not, and the search was invisible.
                if selection.isRunning {
                    // **It counts and says nothing else** since the trash moved to the navigation bar — see ``TheBarForSelectingSeveralMessages``, which says why
                    // there is still a bar at all when the only thing it held has gone.
                    TheBarForSelectingSeveralMessages(numberOfSelectedMessages: selection.count)
                } else if search.isRunning {
                    TheSearchBarOfThisDiscussion(
                        term: $search.term,
                        numberOfResults: search.results?.count,
                        numberOfTheCurrentResult: search.numberOfTheCurrentResult,
                        goToTheNextResult: { search.goesToTheNextResult() },
                        goToThePreviousResult: { search.goesToThePreviousResult() },
                        cancel: stopSearching)
                } else if header.theReaderCanWriteHere {
                    composeBar
                }
                // **And otherwise nothing at all**, and the same order legacy uses: `accessoryViewKindToShow` answers a search *before* it asks whether
                // the discussion can be written to, so a locked discussion still gets its results bar. A reader may be here and unable to write: the discussion
                // is locked, the contact is no longer active, a group v1 has nobody left in it, a group v2 has withdrawn the permission. Legacy shows no bar in
                // any of those, and a bar offering to send what cannot be sent is worse than an empty space.
                //
                // **A `Group` with no branch taken contributes no subview**, which is exactly what is wanted here and is the opposite of the rule for a row of a
                // lazy container, which must be unary. So the inset collapses to nothing and the scrolling rules follow the change like any other, the space below the
                // messages being a quantity they read rather than one they are told. Nothing needed telling.
            }
        }
        // The two sheets of a deletion. In a modifier of its own for the reason the context menu below is: this body has been too large for the type
        // checker once already.
        .deletesTheMessagesTheReaderHasChosen($deletion, numberOfSelectedMessages: selection.count, delete: deletesWhatIsSelected(_:))
        .forwardsTheMessagesTheReaderHasChosen($forwarding)
        // Everything of the context menu, in one modifier of its own. **Extracted, and not merely for tidiness**: inlined here it made the body of this screen too
        // large for the type checker, which gave up on the whole expression rather than on the part that had grown.
        .modifier(TheContextMenuOfAMessageOnThisScreen(
            contextMenu: $contextMenu,
            theMessageIsUp: theMessageIsUp,
            cellIdentifiers: model.cellIdentifiers,
            pressesOnMessages: pressesOnMessages,
            whereTheReaderWantsToGo: whereTheReaderWantsToGo,
            dataSource: dataSources.cellViewDataSource,
            actions: actions,
            theMessageBeingLifted: theMessageBeingLifted,
            followsThePresses: followsThePressesOnMessages,
            chose: choose(_:on:showing:theCopyAsItStands:),
            dismiss: { putTheMessageBack() },
            dismissAtOnce: takeTheOverlayAwayAtOnce))
        // Set before the safe area changes, so the margin is already part of the movement the system animates with the keyboard, rather than a step of its
        // own afterwards.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            theSpaceBelowTheCompositionBar.theKeyboardIsUp = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            theSpaceBelowTheCompositionBar.theKeyboardIsUp = false
        }
        // What the system leaves below this screen, read here rather than inside the safe-area inset: the bar is placed *in* that inset, so its own proxy reports
        // what is left after it, which is not the question. Read once per change of the geometry, and nothing about the layout depends on it — see
        // ``TheSpaceBelowTheCompositionBar/spaceTheSystemLeavesBelowTheScreen``.
        .onGeometryChange(for: CGFloat.self, of: { $0.safeAreaInsets.bottom }) { newSpace in
            theSpaceBelowTheCompositionBar.spaceTheSystemLeavesBelowTheScreen = newSpace
        }
        // **The title stays, even though nothing shows it.** A principal item takes over the display, but the string is what the *next* screen's back button is
        // built from, and what a long press on that button lists. Confirmed on a device: pushing a screen over this one gives it a back button reading the title.
        // The legacy screen sets `navigationItem.title` for exactly this reason, and says so.
        .navigationTitle(Text(verbatim: header.title))
        .navigationBarTitleDisplayMode(.inline)
        // Who the reader is talking to. **Installed as the bar's title view**, which is what a principal item is, so it inherits the bar's own sizing rules — see
        // `SingleDiscussionHeaderView`, where what those rules grant is written down after being measured.
        .toolbar {
            ToolbarItem(placement: .principal) {
                SingleDiscussionHeaderView(
                    header: header,
                    avatarDataSource: dataSources.cellViewDataSource,
                    tapped: { screenActions.userTappedTheHeader(discussionIdentifier: discussionIdentifier) })
            }
            // **While messages are being chosen, nothing else is offered**. Muting a discussion, opening its gallery or calling somebody are not
            // things to do in the middle of choosing what to delete, and leaving them would give the reader two ways out of the mode.
            //
            // **What acts on the selection lives here, beside the way out** — moved from the bar at the bottom on 2026-08-17, because that is where the
            // **discussions list** puts the actions of its own select mode, and the screen that already shipped decides which place that is.
            //
            // **The way out is an item of its own, not grouped with the actions** — 2026-09-07, and it is what Photos does: its select mode puts the `xmark`
            // in a capsule by itself, beside a capsule holding the things that act. It takes **both** of the things below to say that, and the first alone
            // looks exactly like having said nothing — see the spacer. The two roles are then separated by the *bar* rather than by a style, which is what
            // replaced the prominent tint this button used to carry — see ``theWayOut``.
            //
            // **What that costs is an animation, and it was measured rather than assumed.** Three arrangements had been run when the group was chosen:
            //
            // | selecting | not selecting | what animates |
            // |---|---|---|
            // | one `ToolbarItemGroup` | **two `ToolbarItem`s** | leaving, not entering |
            // | one `ToolbarItemGroup` holding an `if`/`else` | the same one | **neither** |
            // | one `ToolbarItemGroup` | one `ToolbarItemGroup` | **neither** |
            //
            // What animates a navigation bar is items being **inserted and removed**, which is UIKit's own doing: a group that merely swaps its content is
            // never inserted or removed, and one group replacing one group is one item replacing one item, updated in place. By that reading this branch now
            // animates **only for a muted discussion** — an unmuted one offers a single item, the ellipsis, so two replacing one is still a change of the set,
            // where a muted one offers two and two replacing two is the third row of the table again.
            //
            // **That is a prediction from the table and not a measurement**, which the table itself is: the three rows were run, this fourth has not been.
            // It is written down rather than checked because nothing turns on it — the separation is what is wanted, and a select mode that appears without
            // sliding is not a defect. Check it before believing it, and note where it would be seen if it is wrong: a discussion the reader has muted.
            //
            // **Declaration order is left to right**, the reverse of UIKit's `rightBarButtonItems`, and measured rather than assumed — see Step 32b. So the
            // way out is declared last and lands on the trailing side, furthest from the back button and where Photos keeps its own.
            if selection.isRunning {
                // **A menu labelled with a word**, which is what this comment used to say would happen: while deleting was the only thing on offer
                // it was a bare trash, *"a button and not a menu… a menu of a single entry is a worse control than the entry itself"*, and forward arriving is
                // exactly the condition it named. See ``theActionsOnTheSelection``, where the rest of that reasoning now lives.
                ToolbarItem(placement: .topBarTrailing) {
                    theActionsOnTheSelection
                }
                // **Two items are not two capsules, and only a `ToolbarSpacer` says so** — 2026-09-07, from a screenshot. Splitting the group into two items
                // was necessary and is not sufficient: on iOS 26 everything at one placement shares a background by default, so `Actions` and the `xmark` came
                // out in the same capsule looking exactly as they had inside the group. A spacer is the break — `.fixed`, which is the small deliberate gap
                // Photos has between its own two, rather than `.flexible`, which would push them to opposite ends of the space the bar has left.
                //
                // **Nothing is needed before 26**, where a bar draws no capsules to share and the items are already apart.
                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    theWayOut
                }
            } else {
                if let mute = header.mute {
                    ToolbarItem(placement: .topBarTrailing) {
                        DiscussionUnmuteButton(mute: mute, act: act)
                    }
                }
                // The whole item is left out, and not merely its content: a locked discussion has no ellipsis at all on the legacy screen, which builds its menu
                // elements first and makes no button when there are none.
                if DiscussionEllipsisMenu.hasAnythingToOffer(header) {
                    ToolbarItem(placement: .topBarTrailing) {
                        DiscussionEllipsisMenu(header: header,
                                               act: act,
                                               startASearch: startASearch,
                                               // Wrapped rather than passed by name: the method now takes the message to begin with, and the ellipsis names
                                               // the mode rather than a message — so the reader starts with nothing chosen.
                                               startSelectingMessages: { startSelectingMessages() })
                    }
                }
            }
        }
        .task(onTask)
        .task(followsTheHeader)
        .task(answersTheFindShortcuts)
        // Hidden, because what Esc closes depends on what is up; ``answersTheEscapeKey()`` decides. Being a shortcut, it reaches this screen only while the
        // screen is frontmost.
        .escapeKeyPresses(answersTheEscapeKey)
        .task(putsTheMessageBackWhenTheReplyGoes)
        // **Said by the screen, and not by the controller hosting it.** What hangs off being the discussion the reader is looking at — read-once messages wiped on
        // leaving, notifications suppressed while here, the user activity, the discussions list's own idea of where the reader is — all of it follows from these two.
        // See `SingleDiscussionViewActions`.
        //
        // **Synchronous, and deliberately not a `Task`.** Hopping to another turn of the main actor before saying it was enough for the screen being left to be gone
        // by the time anyone was told: the actions object holds its controller weakly, and a popped controller is released within the transition. Nothing here awaits
        // anything, so there was never a reason to hop.
        .onAppear {
            screenActions.discussionAppeared(discussionIdentifier: discussionIdentifier)
        }
        .onDisappear {
            screenActions.discussionDisappeared(discussionIdentifier: discussionIdentifier)
        }
    }

}


// MARK: - The space kept below the composition bar

extension SingleDiscussionView {

    /// The space kept between the composition bar and whatever is below it, which has two quite separate reasons and one number.
    ///
    /// **Above the keyboard**, 16pt, as the legacy screen keeps whenever its keyboard is shown. And **above the bottom edge on a phone with no
    /// home indicator** (an iPhone SE), where nothing else provides a margin and a bar flush with the edge looks wrong. Legacy says the same
    /// thing as `-16.0` when `view.safeAreaInsets.bottom.isZero`. On every other phone the home indicator is the margin, so this is nothing.
    ///
    /// **Not the Mac's margin**, which the bar keeps itself: see `ComposeView.spaceKeptBelowTheBar`. That one is inside the bar so that the gap
    /// under it accepts a dropped file, as the bar does. This one is outside, which is fine on a phone, where nothing is dragged between
    /// applications. Hence the guard below: on Catalyst the bar has already kept its space and this must not add a second.
    @MainActor
    fileprivate final class TheSpaceBelowTheCompositionBar: ObservableObject {

        /// Whether the keyboard is up, which is one of the two reasons this screen keeps space below the composition bar.
        @Published var theKeyboardIsUp = false

        /// The space the system already leaves at the bottom of this screen — 34pt of home indicator, 21 in landscape, and **nothing at all** on a
        /// phone that has none, which is the case this is read for.
        @Published var spaceTheSystemLeavesBelowTheScreen: CGFloat = 0

        /// **Computed rather than stored**, since it answers two questions and a stored value would have to be written from both.
        var marginBelowComposeBar: CGFloat {
            if theKeyboardIsUp { return SingleDiscussionView.marginAboveKeyboard }
            #if targetEnvironment(macCatalyst)
            return 0
            #else
            return spaceTheSystemLeavesBelowTheScreen.isZero ? SingleDiscussionView.marginWhenTheSystemLeavesNone : 0
            #endif
        }

    }


    /// Whichever bar is at the bottom, with the space kept below it. It observes ``TheSpaceBelowTheCompositionBar`` so that the screen does not have to — see
    /// ``SingleDiscussionView/theSpaceBelowTheCompositionBar``.
    fileprivate struct TheBarKeepsItsMargin<Bar: View>: View {

        @ObservedObject var theSpace: TheSpaceBelowTheCompositionBar
        @ViewBuilder let bar: Bar

        var body: some View {
            Group { bar }
                .padding(.bottom, theSpace.marginBelowComposeBar)
        }

    }

}


#if DEBUG

// MARK: - Previews

@MainActor
private final class DataSourceForPreviews: SingleDiscussionViewDataSource, SingleDiscussionCellViewDataSource, SingleDiscussionCellViewActions, SingleDiscussionViewActions {

    // SingleDiscussionViewDataSource

    func getInitialSingleDiscussionViewModelAndValues(discussionIdentifier: ObvDiscussionIdentifier) throws -> (model: SingleDiscussionView.Model, initialValues: SingleDiscussionView.InitialValues) {
        return (SingleDiscussionView.Model.sampleData, SingleDiscussionView.InitialValues.sampleData)
    }

    func getAsyncStreamOfSingleDiscussionViewModel(discussionIdentifier: ObvDiscussionIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleDiscussionView.Model>) {
        let stream = AsyncStream<SingleDiscussionView.Model> { (continuation: AsyncStream<SingleDiscussionView.Model>.Continuation) in
            continuation.yield(SingleDiscussionView.Model.sampleData)
        }
        return (UUID(), stream)
    }

    func finishAsyncStreamOfSingleDiscussionViewModel(discussionIdentifier: ObvDiscussionIdentifier, streamUUID: UUID) {
        // Nothing to finish in previews
    }

    /// Says the discussion is with somebody else a moment later, so that a preview shows a header that follows a rename rather than one read once.
    func getAsyncStreamOfDiscussionHeader(discussionIdentifier: ObvDiscussionIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<DiscussionHeader>) {
        let stream = AsyncStream<DiscussionHeader> { (continuation: AsyncStream<DiscussionHeader>.Continuation) in
            Task {
                continuation.yield(.sampleData)
                try? await Task.sleep(seconds: 3)
                continuation.yield(.sampleDataAfterARename)
            }
        }
        return (UUID(), stream)
    }

    func finishAsyncStreamOfDiscussionHeader(discussionIdentifier: ObvDiscussionIdentifier, streamUUID: UUID) {
        // Nothing to finish in previews
    }

    /// Finds nothing, a preview holding no database to search. The highlight is previewed by giving the words straight to a cell, which is the way it reaches one on
    /// the real screen too — see ``TheWordsBeingLookedFor``.
    func getCellIdentifiersOfMessages(matching words: TheWordsBeingLookedFor, discussionIdentifier: ObvDiscussionIdentifier) async throws -> [SingleDiscussionView.CellIdentifier] {
        return []
    }

    /// Offers all three kinds, a preview having no database to simulate a deletion against — so the sheet can be looked at with everything on it, which is the
    /// arrangement most likely to be wrong.
    func whatCanBeDeleted(cellIdentifiers: Set<SingleDiscussionView.CellIdentifier>, discussionIdentifier: ObvDiscussionIdentifier) async -> WhatCanBeDeleted {
        .init(kinds: WhatCanBeDeleted.Kind.allCases, readerHasAnotherDevice: true, discussionHasSeveralContacts: true, numberOfAttachments: 3)
    }

    /// Lets everything be forwarded, a preview having no messages to refuse — so the chooser is what a preview of the mode reaches, which is the part worth
    /// looking at. The alerts that say why a forward was declined cannot be provoked from here at all.
    func whatCanBeForwarded(cellIdentifiers: Set<SingleDiscussionView.CellIdentifier>, discussionIdentifier: ObvDiscussionIdentifier) async -> WhatCanBeForwarded {
        .allOfThem
    }

    // SingleDiscussionCellViewDataSource

    func getAsyncStreamOfSingleDiscussionCellViewModel(cellIdentifier: SingleDiscussionView.CellIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleDiscussionCellView.Model>) {
        let stream = AsyncStream<SingleDiscussionCellView.Model> { (continuation: AsyncStream<SingleDiscussionCellView.Model>.Continuation) in
            Task {
                // Sleeping allows to see the redacted skeletons in previews
                try? await Task.sleep(seconds: 1)
                guard let model = SingleDiscussionCellView.Model.sampleDataForCellIdentifier[cellIdentifier] else { return }
                continuation.yield(model)
            }
        }
        return (UUID(), stream)
    }

    func finishAsyncStreamOfSingleDiscussionCellViewModel(cellIdentifier: SingleDiscussionView.CellIdentifier, streamUUID: UUID) {
        // Nothing to finish in previews
    }

    /// Nothing cached, on purpose: previews rely on the seeds and on the streams, so that both paths are visible.
    func cachedModelOfSingleDiscussionCellView(cellIdentifier: SingleDiscussionView.CellIdentifier) -> SingleDiscussionCellView.Model? {
        return nil
    }

    // Attachments, handed to the data source the previews of the cells already share, so that they behave the same here as there.

    func getAsyncStreamOfStateForAttachment(_ attachment: MessageAttachment, pixelSize: CGSize) -> AsyncStream<AttachmentState> {
        singleDiscussionCellViewDataSourceForPreviews.getAsyncStreamOfStateForAttachment(attachment, pixelSize: pixelSize)
    }

    func cachedImageForAttachment(_ attachment: MessageAttachment, pixelSize: CGSize) -> CGImage? {
        singleDiscussionCellViewDataSourceForPreviews.cachedImageForAttachment(attachment, pixelSize: pixelSize)
    }

    func recordingForAudioAttachment(_ attachment: MessageAttachment, numberOfSamples: Int) async -> AudioRecording? {
        await singleDiscussionCellViewDataSourceForPreviews.recordingForAudioAttachment(attachment, numberOfSamples: numberOfSamples)
    }

    func getTheFileOfAnAttachment(_ attachment: MessageAttachment) async throws -> URL {
        try await singleDiscussionCellViewDataSourceForPreviews.getTheFileOfAnAttachment(attachment)
    }

    func cachedImageOfAnySizeForAttachment(_ attachment: MessageAttachment) -> CGImage? {
        singleDiscussionCellViewDataSourceForPreviews.cachedImageOfAnySizeForAttachment(attachment)
    }

    func getAsyncStreamOfFramesForAnimatedImage(_ attachment: MessageAttachment, maxPixelSize: Int) -> AsyncStream<CGImage> {
        singleDiscussionCellViewDataSourceForPreviews.getAsyncStreamOfFramesForAnimatedImage(attachment, maxPixelSize: maxPixelSize)
    }

    func linkPreviewMetadata(for source: LinkPreviewInMessage, maxPixelSize: Int) async -> LinkPreviewMetadata? {
        await singleDiscussionCellViewDataSourceForPreviews.linkPreviewMetadata(for: source, maxPixelSize: maxPixelSize)
    }

    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await singleDiscussionCellViewDataSourceForPreviews.fetchAvatar(view, photoURL: photoURL, avatarSize: avatarSize)
    }

    func fetchAvatarFromCache(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        singleDiscussionCellViewDataSourceForPreviews.fetchAvatarFromCache(view, photoURL: photoURL, avatarSize: avatarSize)
    }

    func getAsyncStreamOfLocationState(forLocationWith identifier: LocationInMessage.Identifier) -> AsyncStream<LocationState> {
        singleDiscussionCellViewDataSourceForPreviews.getAsyncStreamOfLocationState(forLocationWith: identifier)
    }

    func getAsyncStreamOfPollState(forPollWith identifier: PollInMessage.Identifier) -> AsyncStream<MessagePollViewModel> {
        singleDiscussionCellViewDataSourceForPreviews.getAsyncStreamOfPollState(forPollWith: identifier)
    }

    func getAsyncStreamOfReactionsCountViewModel(messageIdentifier: ObvMessageReactionsViewModel.MessageIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvReactionsCountViewModel>) {
        try singleDiscussionCellViewDataSourceForPreviews.getAsyncStreamOfReactionsCountViewModel(messageIdentifier: messageIdentifier)
    }

    func finishAsyncStreamOfReactionsCountViewModel(streamUUID: UUID) {
        singleDiscussionCellViewDataSourceForPreviews.finishAsyncStreamOfReactionsCountViewModel(streamUUID: streamUUID)
    }

    func userWantsToActOnPoll(_ poll: PollInMessage, action: PollAction) async {
        await singleDiscussionCellViewDataSourceForPreviews.userWantsToActOnPoll(poll, action: action)
    }

    func userWantsToRevealMessage(_ message: TapToRead) async {
        await singleDiscussionCellViewDataSourceForPreviews.userWantsToRevealMessage(message)
    }

    func userWantsToKnowWhyMessagesAreMissing() async {
        await singleDiscussionCellViewDataSourceForPreviews.userWantsToKnowWhyMessagesAreMissing()
    }

    func userWantsToActOnSystemMessage(_ systemMessage: TappableSystemMessage) async {
        await singleDiscussionCellViewDataSourceForPreviews.userWantsToActOnSystemMessage(systemMessage)
    }

    func userWantsToActOnMessage(cellIdentifier: SingleDiscussionView.CellIdentifier, action: MessageAction) async {
        await singleDiscussionCellViewDataSourceForPreviews.userWantsToActOnMessage(cellIdentifier: cellIdentifier, action: action)
    }

    func whatTheMessageOffers(cellIdentifier: SingleDiscussionView.CellIdentifier) -> WhatAMessageOffers {
        singleDiscussionCellViewDataSourceForPreviews.whatTheMessageOffers(cellIdentifier: cellIdentifier)
    }

    func whatTheReaderMayReactWith(cellIdentifier: SingleDiscussionView.CellIdentifier) -> TheEmojisOnOffer {
        singleDiscussionCellViewDataSourceForPreviews.whatTheReaderMayReactWith(cellIdentifier: cellIdentifier)
    }

    func userWantsToSeeAContact(contactIdentifier: ObvContactIdentifier) async {
        await singleDiscussionCellViewDataSourceForPreviews.userWantsToSeeAContact(contactIdentifier: contactIdentifier)
    }

    func userWantsToSeeWhoReactedToAMessage(messageIdentifier: ObvMessageReactionsViewModel.MessageIdentifier) async {
        await singleDiscussionCellViewDataSourceForPreviews.userWantsToSeeWhoReactedToAMessage(messageIdentifier: messageIdentifier)
    }

    // SingleDiscussionViewActions

    /// Nothing to do: what a discussion appearing sets off — wiping what is read once, claiming the user activity — is all database and app, and a preview has neither.
    func discussionAppeared(discussionIdentifier: ObvDiscussionIdentifier) {}

    func discussionDisappeared(discussionIdentifier: ObvDiscussionIdentifier) {}

    func userPressedEscapeWithNothingOnThisScreenToDismiss(discussionIdentifier: ObvDiscussionIdentifier) {}

    /// Nothing to do: the composition bar of a preview is a stand-in with no caret to take away.
    func userClickedOnTheMessages(discussionIdentifier: ObvDiscussionIdentifier) {}

    /// Nothing to do: the composition bar of a preview is a stand-in with no quote panel to fold.
    func aMessageIsShownBesideTheCompositionBar(discussionIdentifier: ObvDiscussionIdentifier, isShown: Bool) {}

    /// Nothing to do: marking a message read and keeping a visibility running are both database work, and a preview has no database.
    func messagesAreOnScreen(discussionIdentifier: ObvDiscussionIdentifier, onScreenNow: Set<SingleDiscussionView.CellIdentifier>, seenSinceTheLastReport: Set<SingleDiscussionView.CellIdentifier>) {}

    /// Nothing to do: showing a contact or a group is a presentation, and a preview has no controller to present from.
    func userTappedTheHeader(discussionIdentifier: ObvDiscussionIdentifier) {}

    /// Nothing to do either, and for the same reason: three of the four present something, and the fourth writes to a database a preview does not have.
    func userWantsToActOnTheDiscussion(discussionIdentifier: ObvDiscussionIdentifier, action: DiscussionBarAction) {}

    /// Nothing to do: a drop ends in a draft, and a preview has neither draft nor database to put one in.
    func userDroppedItemsOnTheMessages(discussionIdentifier: ObvDiscussionIdentifier, itemProviders: [NSItemProvider]) {}

    /// Waits a moment and says it worked, so that a preview shows the bar disabled while a deletion runs and the mode ending afterwards. Nothing is deleted:
    /// there is nothing to delete.
    func userWantsToDeleteMessages(discussionIdentifier: ObvDiscussionIdentifier, cellIdentifiers: Set<SingleDiscussionView.CellIdentifier>, kind: WhatCanBeDeleted.Kind) async throws {
        try? await Task.sleep(seconds: 1)
    }

    /// Waits a moment and says the messages went, so that a preview shows the menu disabled while a forward runs and the mode ending afterwards. There is no
    /// chooser: a preview has no view controller to present one from.
    func userWantsToForwardMessages(discussionIdentifier: ObvDiscussionIdentifier, cellIdentifiers: Set<SingleDiscussionView.CellIdentifier>) async throws -> Bool {
        try? await Task.sleep(seconds: 1)
        return true
    }

    func mapSnapshot(centeredOn coordinate: LocationCoordinate, pointSize: CGSize, displayScale: CGFloat, appearance: MapAppearance) async -> CGImage? {
        await singleDiscussionCellViewDataSourceForPreviews.mapSnapshot(centeredOn: coordinate, pointSize: pointSize, displayScale: displayScale, appearance: appearance)
    }

    func getAsyncStreamOfAudioPlaybackState(forAttachment attachment: MessageAttachment) async throws -> (streamUUID: UUID, stream: AsyncStream<AudioPlaybackState>) {
        try await singleDiscussionCellViewDataSourceForPreviews.getAsyncStreamOfAudioPlaybackState(forAttachment: attachment)
    }

    func finishAsyncStreamOfAudioPlaybackState(streamUUID: UUID) async {
        await singleDiscussionCellViewDataSourceForPreviews.finishAsyncStreamOfAudioPlaybackState(streamUUID: streamUUID)
    }

    func userWantsToActOnAudioAttachment(_ attachment: MessageAttachment, action: AudioAction) async {
        await singleDiscussionCellViewDataSourceForPreviews.userWantsToActOnAudioAttachment(attachment, action: action)
    }

    func userWantsToActOnLocation(_ location: LocationInMessage, at coordinate: LocationCoordinate, address: String?, action: LocationAction) async {
        await singleDiscussionCellViewDataSourceForPreviews.userWantsToActOnLocation(location, at: coordinate, address: address, action: action)
    }

    func getAsyncStreamOfProgressForAttachment(_ attachment: MessageAttachment) async throws -> (streamUUID: UUID, stream: AsyncStream<AttachmentProgress>) {
        try await singleDiscussionCellViewDataSourceForPreviews.getAsyncStreamOfProgressForAttachment(attachment)
    }

    func finishAsyncStreamOfProgressForAttachment(streamUUID: UUID) async {
        await singleDiscussionCellViewDataSourceForPreviews.finishAsyncStreamOfProgressForAttachment(streamUUID: streamUUID)
    }

    // SingleDiscussionCellViewActions

    func userWantsToActOnAttachment(_ attachment: MessageAttachment, action: AttachmentAction) async {
        await singleDiscussionCellViewDataSourceForPreviews.userWantsToActOnAttachment(attachment, action: action)
    }

    func userWantsToOpenAttachment(_ attachment: MessageAttachment) async {
        await singleDiscussionCellViewDataSourceForPreviews.userWantsToOpenAttachment(attachment)
    }

    func userWantsToOpenURLFromAMessage(_ url: URL) async {
        await singleDiscussionCellViewDataSourceForPreviews.userWantsToOpenURLFromAMessage(url)
    }

    /// The same one the cells' own preview data source holds, so that a frame reported here is a frame found there.
    var attachmentFrames: AttachmentFrames {
        singleDiscussionCellViewDataSourceForPreviews.attachmentFrames
    }

}


private let dataSourceForPreviews = DataSourceForPreviews()


/// Stands in for the composition bar, which this module knows nothing about. Only its footprint matters here: it is what the list is inset by.
private struct ComposeBarForPreviews: View {

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color(UIColor.secondarySystemFill))
            .frame(height: 44)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
    }

}


/// A discussion with nothing in it — which is what a **brand-new** one is, and what this screen showed a developer placeholder for until 2026-08-26.
///
/// What it must draw is the sentence saying the discussion is end-to-end encrypted, at the top, and nothing else: that row is a fixed first row of the list
/// rather than one of the messages, so it is there whether or not any message is. See the availability test in ``SingleDiscussionView/body``.
#Preview("Empty discussion") {
    NavigationView {
        SingleDiscussionView(
            discussionIdentifier: ObvDiscussionIdentifier.sampleData,
            dataSources: .init(dataSource: dataSourceForPreviews, cellViewDataSource: dataSourceForPreviews, messageReactionsViewDataSource: messageReactionsDataSourceForPreviews),
            actions: dataSourceForPreviews,
            screenActions: dataSourceForPreviews,
            initialModel: .init(cellIdentifiers: [], lastCellModel: nil, newMessages: nil),
            initialValues: SingleDiscussionView.InitialValues.sampleData,
            composeBar: AnyView(ComposeBarForPreviews()),
            findShortcuts: WhatTheFindShortcutsAsk(),
            compositionBar: WhatTheCompositionBarAsks(),
            whereTheReaderWantsToGo: WhereTheReaderWantsToGo(),
            // A preview is never pushed, so nothing ever says it has arrived: the entry waits out its bound and uncovers, which is the behaviour that branch is for.
            whenTheScreenHasFinishedArriving: WhenTheScreenHasFinishedArriving())
    }
}


#Preview {
    NavigationView {
        SingleDiscussionView(
            discussionIdentifier: ObvDiscussionIdentifier.sampleData,
            dataSources: .init(dataSource: dataSourceForPreviews, cellViewDataSource: dataSourceForPreviews, messageReactionsViewDataSource: messageReactionsDataSourceForPreviews),
            actions: dataSourceForPreviews,
            screenActions: dataSourceForPreviews,
            initialModel: SingleDiscussionView.Model.sampleData,
            initialValues: SingleDiscussionView.InitialValues.sampleData,
            composeBar: AnyView(ComposeBarForPreviews()),
            // Two channels nothing speaks into: a preview has no responder chain above it to deliver ⌘F, and nobody to ask it to jump anywhere.
            findShortcuts: WhatTheFindShortcutsAsk(),
            compositionBar: WhatTheCompositionBarAsks(),
            whereTheReaderWantsToGo: WhereTheReaderWantsToGo(),
            // A preview is never pushed, so nothing ever says it has arrived: the entry waits out its bound and uncovers, which is the behaviour that branch is for.
            whenTheScreenHasFinishedArriving: WhenTheScreenHasFinishedArriving())
    }
}

#endif
