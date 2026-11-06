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
import Combine
import CoreData
import OSLog
// For `OSAllocatedUnfairLock`, which holds the cells still following their model.
import os
import SwiftUI
import AVFoundation
import ImageIO
import MapKit
import QuickLookThumbnailing
import UniformTypeIdentifiers
import ObvAppCoreConstants
import ObvAppTypes
import ObvDesignSystem
import ObvEncoder
import ObvPollFeature
import ObvSettings
import ObvSingleDiscussion
import ObvSystemIcon
import ObvTypes
import ObvUICoreData
import OlvidUtils


/// What this data source cannot do by itself, and asks of whoever created it: the reader's requests on an attachment, which end at the engine.
///
/// Two methods, because the app has always had two: an attachment of a received message is fetched from its sender, and one of a sent message is fetched from
/// another of the reader's own devices. The data source is what tells the two apart, having the join in hand.
@MainActor
protocol SingleDiscussionViewAppDataSourceDelegate: AnyObject {
    func userWantsToActOnReceivedAttachment(_ dataSource: SingleDiscussionViewAppDataSource, receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>, action: AttachmentAction) async
    func userWantsToActOnSentAttachment(_ dataSource: SingleDiscussionViewAppDataSource, sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>, action: AttachmentAction) async
    func getAsyncStreamOfDownloadProgress(_ dataSource: SingleDiscussionViewAppDataSource, attachmentId: ObvAttachmentIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvAttachmentDownloadProgress>)
    func finishAsyncStreamOfDownloadProgress(_ dataSource: SingleDiscussionViewAppDataSource, streamUUID: UUID) async

    /// The same for an attachment on its way **out**. A stream of its own, from the send manager rather than the fetch manager — the two
    /// directions are reported by different managers and were, until Step 36, reported in different ways.
    func getAsyncStreamOfUploadProgress(_ dataSource: SingleDiscussionViewAppDataSource, attachmentId: ObvAttachmentIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvAttachmentUploadProgress>)

    func finishAsyncStreamOfUploadProgress(_ dataSource: SingleDiscussionViewAppDataSource, streamUUID: UUID) async

    /// A `Fyle` presented under the name it was sent with. Needed because a `Fyle` is stored under the hexadecimal of its own hash, with no extension, and
    /// anything that decides what a file *is* from its name — QuickLook, above all — cannot make sense of that. `HardLinksToFylesManager` does the work.
    func requestHardLinkToFyle(_ dataSource: SingleDiscussionViewAppDataSource, fyleElement: FyleElement) async throws -> HardLinkToFyle

    /// Where the metadata of a link the sender attached no preview for is held, fetched if this is the first time it is asked for.
    ///
    /// Asked of `MissingReceivedLinkPreviewFetcher`, which the legacy screen already uses — so a link fetched for one screen is not fetched again for the other,
    /// both reading the same file. A *file* rather than the metadata itself because this data source decodes both routes a preview arrives by with one function.
    func requestFileHoldingLinkPreviewMetadata(_ dataSource: SingleDiscussionViewAppDataSource, ofLink link: URL) async throws -> URL
}


/// Feeds the SwiftUI implementation of the single discussion screen: the identifiers of the cells to show, and one model per cell.
///
/// This is a first cut: the whole list of cell identifiers is streamed at once, with no paging window and no incremental diffing beyond what the
/// fetched results controller and the debouncing of `ObvDataSourceStreamManager` already provide.
///
/// Only sent and received messages are supported for now, so system messages are filtered out of the list of cell identifiers. Keeping them would
/// leave cells that can never resolve a model, showing a redacted skeleton forever.
///
/// It answers the reader's requests on an attachment as well as it feeds the views, because the two cannot be separated: what the reader has asked for and
/// the engine has not yet done exists nowhere else, so the same object has to hold it and to fold it into what it streams.
@MainActor
final class SingleDiscussionViewAppDataSource: SingleDiscussionViewDataSource, SingleDiscussionCellViewDataSource, SingleDiscussionAttachmentActions {

    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    weak var delegate: SingleDiscussionViewAppDataSourceDelegate?

    /// The app's own avatar photo cache, which this data source only forwards to — a cell drawing a person must not decode a picture the rest of the app already
    /// has. Weak, being owned by `ObvDataSources` and shared with every other screen.
    private weak var avatarViewDataSource: (any ObvAvatarViewDataSource)?

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext, avatarViewDataSource: any ObvAvatarViewDataSource) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
        self.avatarViewDataSource = avatarViewDataSource
        self.theCellsFollowingTheirModel = TheCellsFollowingTheirModel(context: backgroundContext)
        watchesForTheReaderGoingAwayFromADiscussion()
    }


    /// What is watching for the reader going away, which is what makes the unread marker start again.
    private var theWatchOnTheReaderGoingAway = [NSObjectProtocol]()
    private var theWatchOnTheMacWindow = Set<AnyCancellable>()


    /// Tells the marker of a discussion to start again when the reader goes away from it, and **legacy's two triggers plus the one a Mac needs.**
    ///
    /// Legacy calls `theUserLeftTheDiscussion()` from `currentDiscussionDidChange` and from `UIScene.didEnterBackgroundNotification`, and that method empties its set
    /// and re-derives it from what is still unread — so the marker goes, the messages having been read by then.
    ///
    /// **The third trigger is not legacy's.** It is the window losing focus: `traitCollectionActiveAppearance` leaving `.active`. ``SwiftUISingleDiscussionActions``
    /// uses the same signal in the opposite direction, to retry marking messages read when the reader comes back. Deliberately **not** `willDeactivate`, which
    /// would also fire for a call banner or a peek at the app switcher: those are not the reader leaving.
    ///
    /// **On a Mac, the window stays on screen when the reader goes to another application.** If the marker started again then, its row would leave or move,
    /// and the rows around it would move in front of the reader. So on a Mac neither the focus trigger nor the background one starts it again at once. Both
    /// wait for the next message that arrives, and the wait is cancelled if the reader comes back first. Switching application on a Mac does background the
    /// scene: measured, every switch posts `UIScene.didEnterBackgroundNotification` just before the window stops being active. On iOS and iPadOS the scene is
    /// then off the screen, so the background trigger starts the marker again at once.
    ///
    /// **The reader is back when the window becomes active, or when the scene becomes active while the window is**, as for marking messages read. If the scene
    /// went to the background while the window kept its focus, the trait would never change back, and watching it alone would leave the wait armed.
    ///
    /// Here rather than in the screen or its actions, because the set belongs to the stream managers and this owns them. The discussion that was left is named for
    /// the first trigger and not for the other two: backgrounding takes every open discussion away at once, and only the ones on screen have a manager.
    private func watchesForTheReaderGoingAwayFromADiscussion() {

        theWatchOnTheReaderGoingAway.append(ObvMessengerInternalNotification.observeCurrentDiscussionDidChange { [weak self] previousDiscussion, currentDiscussion in
            Task { @MainActor [weak self] in
                Self.saysWhatHappensToTheMarker("the current discussion changed, from \(previousDiscussion == nil ? "none" : "a discussion") to \(currentDiscussion == nil ? "none" : (previousDiscussion == currentDiscussion ? "the same one" : "another"))")
                // The same guard legacy makes: this fires for the discussion being *entered* as well, and only the one being left is going away.
                guard let previousDiscussion, previousDiscussion != currentDiscussion else { return }
                guard let self else { return }
                guard let discussion = try? PersistedDiscussion.getManagedObject(withPermanentID: previousDiscussion, within: self.viewContext) else { return }
                guard let identifier = try? discussion.discussionIdentifier else { return }
                self.theMarkersStartAgain(where: { $0 == identifier }, because: "the reader left the discussion")
            }
        })

        theWatchOnTheReaderGoingAway.append(NotificationCenter.default.addObserver(forName: UIScene.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in
                // Switching application on a Mac backgrounds the scene, but the window stays on screen. So the marker waits for an arrival, as on a loss of focus.
                if ObvAppCoreConstants.targetEnvironmentIsMacCatalyst {
                    Self.saysWhatHappensToTheMarker("the scene entered the background, on a Mac: the window is still on screen")
                    self?.theMarkersStartAgainWithTheNextArrival()
                } else {
                    self?.theMarkersStartAgain(where: { _ in true }, because: "the scene entered the background")
                }
            }
        })

        // The scene coming back cancels a waiting start, as the window coming back does. On a Mac only if the window is active too: a window behind another
        // is still an active scene, and the reader is not looking at it.
        theWatchOnTheReaderGoingAway.append(NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in
                if ObvAppCoreConstants.targetEnvironmentIsMacCatalyst, OlvidUserActivitySingleton.shared.traitCollectionActiveAppearance != .active {
                    Self.saysWhatHappensToTheMarker("the scene became active, on a Mac with the window not active: the marker still waits")
                    return
                }
                Self.saysWhatHappensToTheMarker("the scene became active")
                self?.theMarkersNoLongerWaitForAnArrival()
            }
        })

        // Losing focus makes the marker wait for the next arrival. Becoming active again cancels the wait.
        OlvidUserActivitySingleton.shared.$traitCollectionActiveAppearance
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] traitCollectionActiveAppearance in
                Self.saysWhatHappensToTheMarker("the window is now \(traitCollectionActiveAppearance == .active ? "ACTIVE" : "not active (\(traitCollectionActiveAppearance.map { String($0.rawValue) } ?? "nil"))")")
                if traitCollectionActiveAppearance == .active {
                    self?.theMarkersNoLongerWaitForAnArrival()
                } else {
                    self?.theMarkersStartAgainWithTheNextArrival()
                }
            }
            .store(in: &theWatchOnTheMacWindow)

    }


    /// The reader looked away without leaving: another window took the focus, or, on a Mac, the scene went to the background with its window still on screen.
    /// Every marker starts again with the next message that arrives.
    private func theMarkersStartAgainWithTheNextArrival() {
        for manager in viewModelStreamManagerForStreamUUID.values {
            manager.theReaderHasLookedAway()
        }
    }


    /// The reader is back before anything arrived, so every marker stays as it was.
    private func theMarkersNoLongerWaitForAnArrival() {
        for manager in viewModelStreamManagerForStreamUUID.values {
            manager.theReaderIsBack()
        }
    }


    /// Has the marker of every matching discussion start again, and forgets the seed with it.
    ///
    /// **Both halves are needed.** The manager holds the set the marker is drawn from *now*; ``theNewMessagesTheStreamShouldStartFrom`` holds what a *new* manager
    /// would start from, and this screen builds new managers while it stays up — the model is followed from a `.task`, which opening a photograph cancels. Left
    /// alone, that seed would bring a marker the reader has already dismissed straight back on the way out of a photograph. Emptied, a new manager starts from
    /// nothing and then unions with what is still unread, which is exactly the right answer.
    private func theMarkersStartAgain(where itIsTheDiscussion: (ObvDiscussionIdentifier) -> Bool, because why: String) {
        let managers = viewModelStreamManagerForStreamUUID.values.filter({ itIsTheDiscussion($0.discussionIdentifier) })
        Self.saysWhatHappensToTheMarker("\(why), so \(managers.count) marker(s) start again AT ONCE")
        for manager in managers {
            theNewMessagesTheStreamShouldStartFrom[manager.discussionIdentifier] = []
            manager.theReaderHasGoneAway()
        }
    }


    /// DEBUG INSTRUMENT. Says what happens to the unread marker, in the `TranscriptRule` category with the transcript's other probes. Every path that changes
    /// the marker's set says so. The set is changed by several triggers and on two queues, and a marker that is simply gone does not say which one removed it.
    nonisolated static func saysWhatHappensToTheMarker(_ what: @autoclosure () -> String) {
        #if DEBUG
        let line = what()
        theMarkersProbe.info("🎞 the marker: \(line, privacy: .public)")
        #endif
    }

    nonisolated private static let theMarkersProbe = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "TranscriptRule")

    private var viewModelStreamManagerForStreamUUID = [UUID: SingleDiscussionViewModelStreamManager]()
    private let theCellsFollowingTheirModel: TheCellsFollowingTheirModel
    private var reactionsCountViewModelStreamManagerForStreamUUID = [UUID: ObvReactionsCountViewModelStreamManager]()
    /// Which progress streams are following an upload rather than a download, so that each is ended by the manager it came from.
    private var uploadStreamUUIDs = Set<UUID>()
    private var headerStreamManagerForStreamUUID = [UUID: any ObvDataSourceStreamManagerForDiscussionHeader]()

    // MARK: SingleDiscussionViewDataSource

    func getInitialSingleDiscussionViewModelAndValues(discussionIdentifier: ObvDiscussionIdentifier) throws -> (model: SingleDiscussionView.Model, initialValues: SingleDiscussionView.InitialValues) {
        let discussionObjectID = try Self.getDiscussionObjectID(discussionIdentifier: discussionIdentifier, within: viewContext)
        let objectIDsAndSectionIdentifiers = try PersistedMessage.getObjectIDsOfAllMessagesWithinDiscussion(
            discussionObjectID: discussionObjectID,
            showing: Self.messagesShownByTheScreen,
            within: viewContext)
        // Filtering on the entity of the object IDs materializes no message at all
        let supportedMessages = objectIDsAndSectionIdentifiers
            .filter({ Self.entityNamesOfSupportedMessages.contains($0.objectID.entity.name ?? "") })
        let objectIDsOfSupportedMessages = supportedMessages.map(\.objectID)
        let cellIdentifiers = objectIDsOfSupportedMessages
            .map({ SingleDiscussionView.CellIdentifier.objectID($0) })
        // **Read before the models are built, which is why it moved up here.** Where the screen opens decides which models are worth having on the first
        // frame — see ``objectIDsWorthAModelOnTheFirstFrame(among:openingOn:)``.
        let theNewMessages = try Self.getNewMessages(discussionObjectID: discussionObjectID,
                                                     among: Set(objectIDsOfSupportedMessages),
                                                     within: viewContext)
        let cellModels = try getInitialCellModels(objectIDs: Self.objectIDsWorthAModelOnTheFirstFrame(among: objectIDsOfSupportedMessages,
                                                                                                     openingOn: theNewMessages?.objectIDOfTheFirstNewMessage))
        let lastCellModel = cellIdentifiers.last.flatMap({ cellModels[$0] })
        guard let discussion = try PersistedDiscussion.get(objectID: discussionObjectID, within: viewContext) else {
            throw ObvError.couldNotFindDiscussion
        }
        // **Kept for the stream to start from, and this is the one place it can be computed.** The set is *history-dependent*: it is what was new at the
        // moment the reader arrived, and it must not be re-derived later, because by then the messages in it may have been marked read and a fresh query would
        // answer *nothing is new*. Legacy has the same constraint and answers it the same way, computing the set once in `init` and never asking again.
        theNewMessagesTheStreamShouldStartFrom[discussionIdentifier] = theNewMessages?.theOnesThatCount ?? []
        return (model: .init(cellIdentifiers: cellIdentifiers,
                             lastCellModel: lastCellModel,
                             newMessages: Self.newMessages(from: theNewMessages?.theOnesThatCount ?? []),
                             theSections: Self.theSections(ofCellsWithSectionIdentifiers: supportedMessages.map(\.sectionIdentifier))),
                initialValues: .init(cellModels: cellModels,
                                     sentenceSayingTheDiscussionIsEndToEndEncrypted: PersistedMessageSystem.sentenceSayingTheDiscussionIsEndToEndEncrypted,
                                     header: Self.header(of: discussion),
                                     // On by default since 2026-08-29, and switched in Settings ▸ Interface ▸ Scrolling effects. Read here because the view module
                                     // reads no settings — see `TheFieldTheBubblesTravelThrough`.
                                     sentBubbleHueVariesWithScroll: ObvMessengerSettings.Interface.sentBubbleHueVariesWithScroll,
                                     elasticScrolling: ObvMessengerSettings.Interface.elasticScrolling))
    }


    /// What the reader missed since they last looked: which messages they had not seen, and how many more there are than this screen lists.
    ///
    /// Read once, as the screen is created — which is *before* anything is marked as read, and is why the answer holds for as long as the screen lives. The
    /// legacy screen computes the same set at the same moment, in `computeInitialValueOfObjectIDsOfMessagesToConsiderInNewMessagesCell`, and then writes a
    /// system message into the discussion to mark the spot. Nothing is written here.
    ///
    /// System messages count alongside received ones, as on the legacy screen. This screen does not show them yet, so the count can for now exceed what the
    /// reader will find below the marker.
    ///
    /// Where the marker *sits*, on the other hand, has to be a message this screen actually lists, and system messages are filtered out of the identifiers it
    /// is given — hence the intersection: the screen is told which new messages it holds, and separately how many more the count includes that it does not.
    /// Were the oldest unseen thing a system message, the marker would simply sit above the oldest unseen *listed* one, which is what it has always done.
    /// Returns the object ID of the first new message alongside what the screen is told, because the caller needs it too: which models are worth building on the
    /// first frame depends on where the screen is about to open. `NewMessages.firstOne` is internal to the view module, so it is passed here rather than read
    /// back out of the value.
    /// `nonisolated` because the stream manager asks it too, on the queue of its own context — see `SingleDiscussionViewModelStreamManager`. It touches nothing but
    /// the context it is handed.
    nonisolated fileprivate static func getNewMessages(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, among objectIDsTheScreenLists: Set<NSManagedObjectID>, within context: NSManagedObjectContext) throws -> (theOnesThatCount: Set<NSManagedObjectID>, objectIDOfTheFirstNewMessage: NSManagedObjectID)? {
        guard let discussion = try PersistedDiscussion.get(objectID: discussionObjectID, within: context) else { assertionFailure(); return nil }
        guard let firstNewReceivedMessage = try PersistedMessageReceived.getFirstNew(in: discussion) else { return nil }
        // **The two kinds legacy counts**, from `computeInitialValueOfObjectIDsOfMessagesToConsiderInNewMessagesCell`: every received message still `new`, and every
        // system message that is `new`, counts towards the unread total and names a contact. The received ones by object ID alone, materializing nothing.
        let theNewReceivedOnes = try PersistedMessageReceived.getObjectIDsOfAllNew(in: discussion)
        let theNewSystemOnes = try PersistedMessageSystem.getAllNewRelevantSystemMessages(in: discussion).map({ $0.objectID })
        // Intersected with what the screen lists, which is a safety net rather than a filter: since Step 18b it lists all three kinds and excludes only
        // `.numberOfNewMessages` and `.discussionIsEndToEndEncrypted`, neither of which counts towards unread. A message that counts and is *not* listed could never
        // be found among the identifiers, so counting it would inflate the marker's number with something the reader cannot reach.
        return (theNewReceivedOnes.union(theNewSystemOnes).intersection(objectIDsTheScreenLists),
                firstNewReceivedMessage.objectID)
    }


    /// Builds the models of the most recent messages, so that the screen shows its content on its very first frame instead of a screenful of redacted
    /// skeletons reflowing as the models arrive.
    ///
    /// This is the one place where messages are materialized synchronously, on the main thread, while the screen is being pushed. It is bounded to a
    /// screenful, and fetched in one go.
    /// Which messages are worth a model on the very first frame: **the ones the reader will be looking at**, which is not always the most recent.
    ///
    /// A cell created without a model draws a skeleton of a fixed, one-line height and becomes as tall as its content when its own stream answers — see
    /// `SingleDiscussionCellView.initialModel`. That is harmless at the end of a discussion, where the rows that do it are below what is shown. It is not
    /// harmless when the screen opens on the **unread marker**, because then the un-modelled rows are *above* the marker, and growing to their real height
    /// pushes it down the screen after the scroll has already placed it.
    ///
    /// Measured on 2026-08-19, opening on a marker with three photographs above it: the marker was centred at `y=428.8` and was at `y=844.8` **227ms later**,
    /// having slid 416pt to the bottom of the screen — with the scroll offset unchanged across the frames either side, so nothing scrolled. The rows above it
    /// simply became what they are. An `ImageAttachmentView` is framed from its model rather than from the decoded image, so a row that *has* a model is laid
    /// out at its final height straight away and none of this happens.
    ///
    /// So the window follows the entry: around the marker when there is one, and around the last message otherwise. ``TheRowsGivenAModelOnTheFirstFrame``
    /// keeps it whole near either end of the discussion. The last message is always included, whatever the window, because
    /// `SingleDiscussionView.Model.lastCellModel` is taken from these models and tells the screen whether a message that arrives was sent or received.
    private static func objectIDsWorthAModelOnTheFirstFrame(among objectIDs: [NSManagedObjectID], openingOn objectIDOfTheFirstNewMessage: NSManagedObjectID?) -> [NSManagedObjectID] {
        // The marker is centred in the viewport, so what comes before it matters as much as what comes after. Without one, the discussion opens on its end.
        let indexOfTheRowItOpensOn = objectIDOfTheFirstNewMessage.flatMap({ objectIDs.firstIndex(of: $0) }) ?? (objectIDs.count - 1)
        let window = TheRowsGivenAModelOnTheFirstFrame.range(around: indexOfTheRowItOpensOn,
                                                             amongRows: objectIDs.count,
                                                             size: Self.numberOfCellModelsToPrefetch)
        let theLastOneUnlessTheWindowHoldsIt = window.contains(objectIDs.count - 1) ? [] : objectIDs.suffix(1)
        return Array(objectIDs[window] + theLastOneUnlessTheWindowHoldsIt)
    }


    private func getInitialCellModels(objectIDs objectIDsToPrefetch: [NSManagedObjectID]) throws -> [SingleDiscussionView.CellIdentifier: SingleDiscussionCellView.Model] {
        let messages = try PersistedMessage.getMessages(objectIDs: objectIDsToPrefetch, within: viewContext)
        var initialCellModels = [SingleDiscussionView.CellIdentifier: SingleDiscussionCellView.Model]()
        for message in messages {
            guard let model = try? Self.createModel(of: message) else { continue }
            initialCellModels[.objectID(message.objectID)] = model
        }
        return initialCellModels
    }

    /// What the marker should start from, per discussion, put here by ``getInitialSingleDiscussionViewModelAndValues(discussionIdentifier:)`` for the stream that
    /// follows it to pick up. See the note where it is written for why it cannot be computed a second time.
    private var theNewMessagesTheStreamShouldStartFrom = [ObvDiscussionIdentifier: Set<NSManagedObjectID>]()


    /// The value the screen is given for its marker, or nil when there is nothing to mark.
    nonisolated fileprivate static func newMessages(from objectIDs: Set<NSManagedObjectID>) -> SingleDiscussionView.Model.NewMessages? {
        guard !objectIDs.isEmpty else { return nil }
        return .init(theOnesThatCount: Set(objectIDs.map({ SingleDiscussionView.CellIdentifier.objectID($0) })))
    }


    func getAsyncStreamOfSingleDiscussionViewModel(discussionIdentifier: ObvDiscussionIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<SingleDiscussionView.Model>) {
        let discussionObjectID = try Self.getDiscussionObjectID(discussionIdentifier: discussionIdentifier, within: viewContext)
        Self.saysWhatHappensToTheMarker("a NEW manager starts, from a seed of \(theNewMessagesTheStreamShouldStartFrom[discussionIdentifier]?.count ?? 0) message(s)")
        let manager = SingleDiscussionViewModelStreamManager(
            discussionObjectID: discussionObjectID,
            discussionIdentifier: discussionIdentifier,
            showing: Self.messagesShownByTheScreen,
            // Nil only if the initial model was never asked for, which cannot happen — the screen cannot be built without it — and the manager then starts from
            // nothing rather than querying, for the reason given where this is written.
            startingFrom: theNewMessagesTheStreamShouldStartFrom[discussionIdentifier] ?? [],
            context: backgroundContext,
            // When the marker starts again with an arrival, the seed is forgotten. Otherwise a new manager, built after a photograph is closed for instance,
            // would bring the old marker back.
            whenTheMarkerStartsAgainWithAnArrival: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.theNewMessagesTheStreamShouldStartFrom[discussionIdentifier] = []
                }
            })
        viewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }

    func finishAsyncStreamOfSingleDiscussionViewModel(discussionIdentifier: ObvDiscussionIdentifier, streamUUID: UUID) {
        guard let manager = viewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        Self.saysWhatHappensToTheMarker("a manager FINISHES, its stream no longer followed")
        manager.finishStream()
    }


    /// Follows who this discussion is with, so that the bar above it never says something that has stopped being true.
    ///
    /// **The kind decides the manager**, and the identifier already carries the kind — so each of the three watches exactly what its own subtitle is made of,
    /// rather than four controllers of which two always fetch nothing. See `DiscussionHeaderStreamManagers.swift`.
    func getAsyncStreamOfDiscussionHeader(discussionIdentifier: ObvDiscussionIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvSingleDiscussion.DiscussionHeader>) {
        let discussionObjectID = try Self.getDiscussionObjectID(discussionIdentifier: discussionIdentifier, within: viewContext)
        let manager: any ObvDataSourceStreamManagerForDiscussionHeader
        switch discussionIdentifier {
        case .oneToOne(let contactIdentifier):
            manager = OneToOneDiscussionHeaderStreamManager(discussionObjectID: discussionObjectID, contactIdentifier: contactIdentifier, context: backgroundContext)
        case .groupV1(let groupIdentifier):
            manager = GroupV1DiscussionHeaderStreamManager(discussionObjectID: discussionObjectID, groupIdentifier: groupIdentifier, context: backgroundContext)
        case .groupV2(let groupIdentifier):
            manager = GroupV2DiscussionHeaderStreamManager(discussionObjectID: discussionObjectID, groupIdentifier: groupIdentifier, context: backgroundContext)
        }
        headerStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }


    func finishAsyncStreamOfDiscussionHeader(discussionIdentifier: ObvDiscussionIdentifier, streamUUID: UUID) {
        guard let manager = headerStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }


    /// Searches this discussion, off the main queue, and returns the identifiers of the cells that matched — oldest first.
    ///
    /// **On the context this data source was given, rather than one made for the search.** The legacy screen makes a fresh background context per search, and the
    /// reason not to copy that is the discipline this data source is built on: it is handed its two contexts and reaches for no singleton. The cost is that a search
    /// queues behind whatever the streams are doing on that queue, which is what the caller's debounce is for — a search runs when typing pauses, not per keystroke.
    ///
    /// The rules about what may be found — a location never, a message awaiting its tap never, a poll deliberately yes — belong to the fetch, and are written down
    /// where the predicate is: see `PersistedMessage.searchForMessagesTheReaderMayRead(discussionObjectID:words:within:)`.
    func getCellIdentifiersOfMessages(matching words: TheWordsBeingLookedFor, discussionIdentifier: ObvDiscussionIdentifier) async throws -> [SingleDiscussionView.CellIdentifier] {

        guard !words.isEmpty else { return [] }

        let discussionObjectID = try Self.getDiscussionObjectID(discussionIdentifier: discussionIdentifier, within: viewContext)

        let context = backgroundContext
        let wordsToLookFor = words.words

        let messageObjectIDs: [TypeSafeManagedObjectID<PersistedMessage>] = try await context.perform {
            try PersistedMessage.searchForMessagesTheReaderMayRead(discussionObjectID: discussionObjectID, words: wordsToLookFor, within: context)
        }

        return messageObjectIDs.map { .objectID($0.objectID) }

    }


    /// Who a discussion is with, as the bar above it says so — transcribed case for case from `configureNavigationTitle()`.
    ///
    /// **Two departures from the legacy screen, both deliberate.**
    ///
    /// - The **group-v2 subtitle** is the sorted, formatted list of members. The legacy screen builds it that way on its iOS 26 path and as an unsorted `", "`
    ///   join on the older one; the formatted list is plainly the intent, so it is taken for both.
    /// - **A locked discussion gets a header.** On the legacy iOS 26 path it gets none at all: the `.locked` branch of `configureNavigationTitle()` builds a
    ///   configuration and then never assigns `navigationItem.titleView`, which was set to nil a few lines above — so the bar of a locked discussion is empty
    ///   there. The pre-26 path does draw the padlock, and that is what is reproduced here.
    ///
    /// The avatar is **not** built here from the discussion's kind: `PersistedDiscussion.avatarViewModel` is the mapping the rest of the app already uses, padlock
    /// included, and a second one would be a second answer to the same question.
    nonisolated static func header(of discussion: PersistedDiscussion) -> ObvSingleDiscussion.DiscussionHeader {

        let avatar: ObvAvatarViewModel
        do {
            avatar = try discussion.avatarViewModel
        } catch {
            // The discussion has no contact or no group to draw — which is what a locked one looks like from below — so the padlock stands in, as it does in the
            // discussions list.
            assertionFailure(error.localizedDescription)
            avatar = .init(characterOrIcon: .icon(.lock(.fill, .none)),
                           colors: .init(foreground: .secondaryLabel, background: .secondarySystemBackground),
                           photoURL: nil)
        }

        return .init(title: Self.headerTitle(of: discussion),
                     subtitle: Self.headerSubtitle(of: discussion),
                     avatar: avatar,
                     isActive: discussion.status == .active,
                     isCallAvailable: discussion.isCallAvailable,
                     // Step 51. The conditions are on the entity rather than here, `isCallAvailable` beside them being the precedent — and they are the legacy
                     // screen's, gathered out of `accessoryViewKindToShow`.
                     theReaderCanWriteHere: discussion.ownedIdentityIsAllowedToSendMessages,
                     mute: Self.mute(of: discussion))

    }


    /// The mute this discussion is under, and nil when it is under none — or under one that has already run out, `currentMuteNotificationsEndDate` answering nil
    /// then.
    ///
    /// The sentence is built here because it is the app's: two forms, one naming a date through the app's own formatter and one saying the mute is indefinite,
    /// which is what the legacy screen says of anything more than ten years out.
    nonisolated private static func mute(of discussion: PersistedDiscussion) -> ObvSingleDiscussion.DiscussionHeader.Mute? {
        guard let endDate = discussion.localConfiguration.currentMuteNotificationsEndDate else { return nil }
        let sentence: String
        if endDate.timeIntervalSinceNow > TimeInterval(years: 10) {
            sentence = String(localized: "MUTED_NOTIFICATIONS_FOOTER_INDEFINITELY")
        } else {
            // The same two keys the legacy screen uses, written out rather than reached through `NewSingleDiscussionViewController.Strings`: the shared thing is the
            // key in the app's catalogue, and that controller is what this migration removes.
            sentence = String.localizedStringWithFormat(NSLocalizedString("MUTED_NOTIFICATIONS_CONFIRMATION_%@", comment: ""), endDate.formatted())
        }
        return .init(endDate: endDate, sentence: sentence)
    }


    /// What the discussion is called: the contact's name, the group's name, or — for a discussion that is locked, or whose kind cannot be resolved — the title the
    /// discussion carries itself.
    nonisolated private static func headerTitle(of discussion: PersistedDiscussion) -> String {
        switch discussion.status {
        case .locked:
            return discussion.title
        case .preDiscussion, .active:
            switch try? discussion.kind {
            case .oneToOne(withContactIdentity: let contact):
                return contact?.customOrNormalDisplayName ?? discussion.title
            case .groupV1(withContactGroup: let group):
                return group?.discussion.title ?? discussion.title
            case .groupV2(withGroup: let group):
                return group?.displayName ?? discussion.title
            case .none:
                return discussion.title
            }
        }
    }


    /// The line under the title: a contact's position at company, or the members of a group — sorted, and formatted as a list in the reader's language.
    ///
    /// Empty rather than nil when there is nothing to say, which is what the legacy configurations produce; the header then draws one line.
    nonisolated private static func headerSubtitle(of discussion: PersistedDiscussion) -> String {
        switch discussion.status {
        case .locked:
            return discussion.subtitle
        case .preDiscussion, .active:
            switch try? discussion.kind {
            case .oneToOne(withContactIdentity: let contact):
                return contact?.identityCoreDetails?.positionAtCompany() ?? ""
            case .groupV1(withContactGroup: let group):
                guard let group else { return discussion.subtitle }
                let names = group.contactIdentities
                    .sorted { $0.customOrShortDisplayName < $1.customOrShortDisplayName }
                    .compactMap({ $0.customOrShortDisplayName })
                return names.formatted(.list(type: .and, width: .short))
            case .groupV2(withGroup: let group):
                guard let group else { return discussion.subtitle }
                let names = group.otherMembersSorted
                    .sorted { ($0.displayedCustomDisplayNameOrFirstNameOrLastName ?? "") < ($1.displayedCustomDisplayNameOrFirstNameOrLastName ?? "") }
                    .compactMap({ $0.displayedCustomDisplayNameOrFirstNameOrLastName })
                return names.formatted(.list(type: .and, width: .short))
            case .none:
                return discussion.subtitle
            }
        }
    }

    // MARK: SingleDiscussionCellViewDataSource

    func getAsyncStreamOfSingleDiscussionCellViewModel(cellIdentifier: SingleDiscussionView.CellIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<SingleDiscussionCellView.Model>) {
        let messageObjectID = try Self.getMessageObjectID(cellIdentifier: cellIdentifier)
        return theCellsFollowingTheirModel.follow(messageObjectID.objectID)
    }

    func finishAsyncStreamOfSingleDiscussionCellViewModel(cellIdentifier: SingleDiscussionView.CellIdentifier, streamUUID: UUID) {
        theCellsFollowingTheirModel.stopsFollowing(streamUUID)
    }


    /// Follows the reactions of one message, so that the chip under it says what it says now.
    ///
    /// The very stream the reactions *sheet* uses, through the same manager — see ``ObvReactionsCountViewModelStreamManager``, which explains why that manager is not
    /// nested in either data source. A reaction is written by inserting a `PersistedMessageReaction` and touches neither the message nor the discussion, so the
    /// stream of a cell's own model would never report one: this is the only route by which a reaction reaches the screen.
    ///
    /// **One stream per message on screen**, opened when a row is created and finished when its task is cancelled. That is a pair of fetched results controllers per
    /// visible message, fetched on the background context — the same shape and the same cost as the stream each cell already opens for its own model.
    func getAsyncStreamOfReactionsCountViewModel(messageIdentifier: ObvSingleDiscussion.ObvMessageReactionsViewModel.MessageIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvSingleDiscussion.ObvReactionsCountViewModel>) {
        let manager = try ObvReactionsCountViewModelStreamManager(messageIdentifier: messageIdentifier, context: backgroundContext)
        reactionsCountViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }


    func finishAsyncStreamOfReactionsCountViewModel(streamUUID: UUID) {
        guard let manager = reactionsCountViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }


    /// What a message offers when it is pressed — transcribed entry by entry from `createMenu(for:)`, in its order.
    ///
    /// **On the main thread, against the view context, and only for the message pressed.** Three of the rules insist on it:
    /// `deletionTypesThatCanBeMadeAvailableForThisMessage` asserts the main thread and returns an *empty set* unless its context is main-queue, and it — like
    /// `editBodyActionCanBeMadeAvailableForSentMessage` — simulates the operation on a child context. Asking this while building cell models, on the
    /// background context, would have silently disabled Delete on every message.
    ///
    /// Three deliberate departures from legacy. The first two are because it reads the *cell* where this reads the message; the third is a legacy affordance
    /// that does nothing at all.
    ///
    /// - **What can be copied.** Legacy checks that the text bubble is showing something after markdown parsing; here it is the message having a body. A
    ///   message whose body renders to nothing would offer Copy where legacy does not — an edge case worth knowing rather than a difference worth
    ///   reproducing through a view.
    /// - **What can be shared and saved.** Legacy counts the attachments whose hardlink is already *cached*, that being what its cell can reach; here it
    ///   counts the ones whose file is on disk, which is the condition a hardlink can be made from. The providers and the hardlinks themselves are built when
    ///   an entry is chosen, never to draw a menu.
    /// - **Info is not offered on a system message**, where legacy offers it and then does nothing. `infoActionCanBeMadeAvailableForSystemMessage` requires a
    ///   development build, and `SystemMessageCell.infoViewController` — the only thing that entry leads to — `print`s to the console and returns **nil**. It
    ///   is a debug hook wearing a menu entry's clothes. Call and Delete remain reachable on a system message, and those two work.
    /// **Kept until Step 42c's open question is answered** — how long deleting many messages takes — with the line in
    /// ``whatCanBeDeleted(cellIdentifiers:discussionIdentifier:)``.
    private static let theCostOfADeletion = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "TheCostOfADeletion")



    /// What may be done to the messages the reader has chosen, they having asked to delete them.
    ///
    /// **On the main thread against the view context**, as `whatTheMessageOffers(cellIdentifier:)` is, and for the same
    /// reason: the answer comes from simulating each deletion on a child of that context.
    ///
    /// **All of them or none.** `PersistedMessage.deletionTypesThatCanBeMadeAvailable(forAllOf:within:)` simulates the
    /// whole selection once per kind rather than each message three times, and throws on the first refusal — which is
    /// what one button for the lot promises. See its own note for the arithmetic.
    ///
    /// The two booleans are the ones legacy's `deletionActionTitle(for:ownedIdentityHasHasAnotherReachableDevice:multipleContacts:)`
    /// switches on, and they are facts about the reader and the discussion rather than about the messages, which is why
    /// the module cannot work them out. `Self.discussionHasMultipleContacts(_:)` is not reachable from here — it lives
    /// on the presenter — so the same question is answered from the discussion's kind, which is what that method does.
    ///
    /// Attachments are counted the way the deletion alert counts them: the joins that are not already wiped.
    func whatCanBeDeleted(cellIdentifiers: Set<SingleDiscussionView.CellIdentifier>, discussionIdentifier: ObvDiscussionIdentifier) async -> WhatCanBeDeleted {

        let objectIDs = Set(cellIdentifiers.compactMap { cellIdentifier -> NSManagedObjectID? in
            guard case .objectID(let objectID) = cellIdentifier else { return nil }
            return objectID
        })

        guard !objectIDs.isEmpty else { return .nothing }

        // **TEMPORARY until how long deleting many messages takes is known**, this having been named as a thing to measure rather than assume. Three simulated
        // deletions of the whole selection happen on the main thread, and nobody knows what that costs at a hundred messages or at five hundred. One frame is
        // 16ms; past about a hundred this wants something on screen while it runs. It reports once per tap of the trash, so it is quiet.
        //
        //     xcrun simctl spawn booted log stream --predicate 'category == "TheCostOfADeletion"' --level debug
        let startedAt = Date()

        let kinds = PersistedMessage.deletionTypesThatCanBeMadeAvailable(forAllOf: objectIDs, within: viewContext)

        let tookMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1000)
        Self.theCostOfADeletion.info("what can be deleted: \(objectIDs.count, privacy: .public) messages took \(tookMilliseconds, privacy: .public)ms, offering \(kinds.count, privacy: .public) kinds")

        guard !kinds.isEmpty else { return .nothing }

        let messages = objectIDs.compactMap { try? viewContext.existingObject(with: $0) as? PersistedMessage }
        let numberOfAttachments = messages.reduce(0) { soFar, message in
            soFar + (message.fyleMessageJoinWithStatus?.filter({ !$0.isWiped }).count ?? 0)
        }

        let discussion = messages.first?.discussion
        let readerHasAnotherDevice = discussion?.ownedIdentity?.hasAnotherDeviceWhichIsReachable ?? false

        return .init(kinds: kinds.map(WhatCanBeDeleted.Kind.init),
                     readerHasAnotherDevice: readerHasAnotherDevice,
                     discussionHasSeveralContacts: Self.discussionHasSeveralContacts(discussion),
                     numberOfAttachments: numberOfAttachments)

    }


    /// Whether the messages the reader has chosen may be forwarded.
    ///
    /// **All of them or none**, as with the deletion above, and for a plainer reason: one Forward over a whole selection
    /// promises that the whole selection goes. See ``WhatCanBeForwarded``.
    ///
    /// **Cheap, and deliberately not measured.** Where the deletion simulates itself on child contexts and carries a
    /// timing line to this day, `whyThisMessageCannotBeForwarded` is plain property reads — so this is a loop over the
    /// selection and there is nothing to instrument. It is still `async` and still asked at the tap rather than at every
    /// tick, so that it matches its sibling and can grow a spinner if it ever needs one.
    ///
    /// **Read on the queue that owns the objects**, which is what a managed object requires and the only isolation this
    /// needs: the messages belong to ``viewContext``, a main-queue context, and this type is `@MainActor` — so being on
    /// its queue holds by isolation rather than by a check. `whyOneOfTheseMessagesCannotBeForwarded` refuses outright if it
    /// is ever handed a context of another kind.
    ///
    /// The reason reported is the app's own case order rather than the first message found — see
    /// `PersistedMessage.whyOneOfTheseMessagesCannotBeForwarded(objectIDs:within:)`, which says why that matters.
    func whatCanBeForwarded(cellIdentifiers: Set<SingleDiscussionView.CellIdentifier>, discussionIdentifier: ObvDiscussionIdentifier) async -> WhatCanBeForwarded {

        let objectIDs = Set(cellIdentifiers.compactMap { cellIdentifier -> NSManagedObjectID? in
            guard case .objectID(let objectID) = cellIdentifier else { return nil }
            return objectID
        })

        // **Nothing to forward, and it refuses rather than agreeing.** It cannot happen: the only row that is not a message is the unread marker, which no
        // platform allows to be ticked, and the screen refuses an empty selection before it asks. What matters is which way it fails if it ever does — and
        // ``WhatCanBeForwarded/Reason/theyCouldNotBeChecked`` is the one refusal that is true of a selection with nothing in it to examine, where every other
        // reason names something about a message there is no message here to name.
        guard !objectIDs.isEmpty else { assertionFailure(); return .atLeastOneCannotBeForwarded(because: .theyCouldNotBeChecked) }

        if let reason = PersistedMessage.whyOneOfTheseMessagesCannotBeForwarded(objectIDs: objectIDs, within: viewContext) {
            return .atLeastOneCannotBeForwarded(because: .init(reason))
        } else {
            return .allOfThem
        }

    }


    /// Whether a discussion is with more than one person, which changes what *delete for everyone* is called.
    ///
    /// The same rule as `SwiftUISingleDiscussionMessagePresenter.discussionHasMultipleContacts(_:)`, which answers it for
    /// the deletion of a single message, down to the cautious answer when the kind cannot be read: a title speaking of
    /// several contacts is harmless where there is one, and the reverse is not.
    private static func discussionHasSeveralContacts(_ discussion: PersistedDiscussion?) -> Bool {
        guard let discussion else { assertionFailure(); return false }
        do {
            switch try discussion.kind {
            case .oneToOne:
                return false
            case .groupV1(withContactGroup: let group):
                guard let group else { assertionFailure(); return false }
                return group.contactIdentities.count > 1
            case .groupV2(withGroup: let group):
                guard let group else { assertionFailure(); return false }
                return group.otherMembers.count > 1
            }
        } catch {
            assertionFailure()
            return true
        }
    }


    func whatTheMessageOffers(cellIdentifier: SingleDiscussionView.CellIdentifier) -> WhatAMessageOffers {

        guard case .objectID(let objectID) = cellIdentifier else { return .init(entries: []) }
        guard let message = try? viewContext.existingObject(with: objectID) as? PersistedMessage else {
            return .init(entries: [])
        }

        var entries = [WhatAMessageOffers.Entry]()

        // Not offered on a system message, and that is a departure taken knowingly — see the note above the method.
        if message.infoActionCanBeMadeAvailable, !(message is PersistedMessageSystem) {
            entries.append(.showInfo)
        }

        if (try? message.ownedIdentityIsAllowedToSetReaction) == true {
            // The same fact chooses the wording and the icon on the legacy screen: "Change" when there is one to change.
            entries.append(.react(alreadyReacted: message.deleteOwnReactionActionCanBeMadeAvailable))
        }

        if message.deleteOwnReactionActionCanBeMadeAvailable {
            entries.append(.deleteOwnReaction)
        }

        if message.copyTextActionCanBeMadeAvailable, message.textBody?.isEmpty == false {
            entries.append(.copyText)
        }

        if message.shareActionCanBeMadeAvailable {
            let photos = Self.numberOfSharableAttachments(of: message, imagesOnly: true)
            let all = Self.numberOfSharableAttachments(of: message, imagesOnly: false)
            if photos > 0 {
                entries.append(.sharePhotos(count: photos))
            }
            // Legacy omits this entry when the two sets are the same size — sharing "all" would repeat the photos entry.
            if all > 0, all != photos {
                entries.append(.shareAttachments(count: all))
            }
            if all > 0 {
                entries.append(.saveAttachments(count: all))
            }
        }

        // **No draft condition, unlike legacy, and that is now safe.** The legacy menu reads `cell.persistedDraftObjectID` beside this rule, and `SystemMessageCell`
        // returns nil for it — which is how that screen, and only that screen, keeps Reply off a system message. Transcribing the rule without the cell offered
        // Reply on every system message here until 2026-08-09, when the rule itself was made to say what it means. See `replyToActionCanBeMadeAvailable`.
        if message.replyToActionCanBeMadeAvailable {
            entries.append(.reply)
        }

        // The legacy condition is the flag *and* the message being one of the reader's own; the flag already answers
        // false for anything else, and both are kept so that neither has to be trusted alone.
        if message.editBodyActionCanBeMadeAvailable, message is PersistedMessageSent {
            entries.append(.edit)
        }

        if message.forwardActionCanBeMadeAvailable {
            entries.append(.forward)
        }

        // Only ever a system message carrying a call log — and system messages do have a menu, `SystemMessageCell`
        // conforming to `CellWithMessage` like the other two.
        if message.callActionCanBeMadeAvailable {
            entries.append(.call)
        }

        // **Offered on every message, and that is not an oversight**. Every other entry asks whether this message allows the thing; choosing several
        // asks nothing of the message at all, since what may then be *done* with the selection is decided when the trash is tapped, over the whole of it. A
        // message that can be deleted no way at all is still one a reader may tick — see `WhatCanBeDeleted`, where that decision and its reason live.
        //
        // Above Delete rather than below it, so the destructive entry stays last as it is on the legacy menu.
        entries.append(.select)

        if !message.deletionTypesThatCanBeMadeAvailableForThisMessage.isEmpty {
            entries.append(.delete)
        }

        return .init(entries: entries)

    }


    /// What the reader may react with, and what they have already put on this message — see ``TheEmojisOnOffer``.
    ///
    /// **On the main thread against the view context, as the offers beside it are**, and for the same reason: it is asked
    /// once per press and its second half is a fact about *this* message, read where a screen may read.
    ///
    /// The favourites and the rule for how many of them to show both belong to the app, so the cutting is done here — five
    /// on iOS and eight under Catalyst, which is `ReactionContextView.MAX_EMOJIS_COUNT`. The module is handed a list it can
    /// draw as it stands.
    func whatTheReaderMayReactWith(cellIdentifier: SingleDiscussionView.CellIdentifier) -> TheEmojisOnOffer {

        let favourites = Array(ObvMessengerSettings.Emoji.preferredEmojisList.prefix(Self.howManyFavouritesTheBarShows))

        // What a double tap sends, whatever this particular discussion says.
        let theEmojiADoubleTapSendsByDefault = ObvMessengerSettings.Emoji.defaultDoubleTapEmoji ?? ObvMessengerConstants.defaultDoubleTapEmoji

        guard case .objectID(let objectID) = cellIdentifier,
              let message = try? viewContext.existingObject(with: objectID) as? PersistedMessage else {
            return .init(favourites: favourites, theReadersOwn: nil, theEmojiADoubleTapSends: theEmojiADoubleTapSendsByDefault)
        }

        // Three levels: the emoji chosen for this discussion wins, then the global setting, then the constant.
        //
        // The quick-emoji button beside the composition bar has its own three and is not consulted here. The two gestures
        // are set independently at every level, and start from the same glyph.
        //
        // **`localConfigurationIfAny` and not `localConfiguration`.** The latter is declared non-optional and is not always set, so
        // reading through it produced a garbage string that crashed the app three frames later, inside `swift_retain`, as soon as any
        // message was long pressed. See that accessor for the whole story.
        let theEmojiADoubleTapSends = message.discussion?.localConfigurationIfAny?.doubleTapEmoji ?? theEmojiADoubleTapSendsByDefault

        // The same place the legacy emoji picker seeds its own selection from.
        return .init(favourites: favourites,
                     theReadersOwn: message.reactionFromOwnedIdentity()?.emoji,
                     theEmojiADoubleTapSends: theEmojiADoubleTapSends)

    }


    /// `ReactionContextView.MAX_EMOJIS_COUNT`, copied: a pointer has room for more of them.
    private static var howManyFavouritesTheBarShows: Int {
        ObvMessengerConstants.targetEnvironmentIsMacCatalyst ? 8 : 5
    }


    /// How many of a message's attachments could be shared or saved: everything but a link preview, and only what is
    /// actually on the device.
    ///
    /// The file check is what stands in for legacy's "has a cached hardlink" — see ``whatTheMessageOffers(cellIdentifier:)``.
    nonisolated private static func numberOfSharableAttachments(of message: PersistedMessage, imagesOnly: Bool) -> Int {
        guard let joins = message.fyleMessageJoinWithStatus else { return 0 }
        return joins.filter { join in
            guard !join.isPreviewType else { return false }
            guard join.fyle?.fileExistsOnDisk == true else { return false }
            return imagesOnly ? join.isImageType : true
        }.count
    }


    /// A lookup and nothing more, as the protocol requires: no fetch, and no message materialized. See ``cachedCellModels``.
    func cachedModelOfSingleDiscussionCellView(cellIdentifier: SingleDiscussionView.CellIdentifier) -> SingleDiscussionCellView.Model? {
        switch cellIdentifier {
        case .objectID(let objectID):
            return Self.cachedCellModels.object(forKey: objectID)?.model
        case .forPreview, .newMessagesMarker:
            return nil
        }
    }


    /// Fills ``cachedCellModels`` for the cells that are about to be displayed, so that they are created with their content rather than sizing themselves twice.
    ///
    /// Called from the main actor while the list is being scrolled, so the only work done here is discarding the identifiers whose models are already known —
    /// a lookup per identifier, and the reason the caller may ask as often as it likes with overlapping windows. Everything else happens on the queue of the
    /// background context.
    func prefetchModelsOfSingleDiscussionCellViews(cellIdentifiers: [SingleDiscussionView.CellIdentifier]) {
        let objectIDsToPrefetch = cellIdentifiers.compactMap { cellIdentifier -> NSManagedObjectID? in
            switch cellIdentifier {
            case .objectID(let objectID):
                guard Self.cachedCellModels.object(forKey: objectID) == nil else { return nil }
                return objectID
            case .forPreview, .newMessagesMarker:
                return nil
            }
        }
        guard !objectIDsToPrefetch.isEmpty else { return }
        // The newest window replaces whatever was still awaiting: while a finger is moving, an older window describes a part of the discussion that is no longer
        // about to be seen. Only one window is ever pending, so a fast scroll cannot pile up work.
        objectIDsAwaitingPrefetch = objectIDsToPrefetch
        prefetchesTheObjectIDsAwaitingPrefetchIfNotAlreadyDoingSo()
    }


    /// The models still to be built, in the order they are displayed. Only ever the *latest* window asked for.
    private var objectIDsAwaitingPrefetch: [NSManagedObjectID] = []

    private var isPrefetching = false


    /// Drains ``objectIDsAwaitingPrefetch`` in batches until nothing is left, one batch at a time.
    ///
    /// A running drain picks up whatever arrives while it works, which is what makes this idempotent: a second call during a fast scroll returns immediately
    /// and the window it left behind is honoured by the loop already in flight.
    ///
    /// A batch is never abandoned half way — the messages are already fetched by then, so finishing costs almost nothing — but the *remainder* of a window is
    /// dropped as soon as a newer one arrives, since it no longer describes what is about to be seen.
    private func prefetchesTheObjectIDsAwaitingPrefetchIfNotAlreadyDoingSo() {
        guard !isPrefetching else { return }
        isPrefetching = true
        Task {
            defer { isPrefetching = false }
            while !objectIDsAwaitingPrefetch.isEmpty {
                let window = objectIDsAwaitingPrefetch
                objectIDsAwaitingPrefetch = []
                var startIndex = window.startIndex
                while startIndex < window.endIndex {
                    let endIndex = min(startIndex + Self.numberOfCellModelsPerPrefetchBatch, window.endIndex)
                    await Self.prefetchesModels(objectIDs: Array(window[startIndex..<endIndex]), within: backgroundContext)
                    startIndex = endIndex
                    guard objectIDsAwaitingPrefetch.isEmpty else { break }
                }
            }
        }
    }


    /// Builds and caches the models of a batch of messages, off the main thread.
    ///
    /// `createModel(of:)` caches as a side effect, which is the whole mechanism: nothing is returned, and the caller reads the result through
    /// ``cachedModelOfSingleDiscussionCellView(cellIdentifier:)`` when it creates the cell. A message that cannot be turned into a model is skipped and left
    /// uncached, which is indistinguishable from never having been prefetched.
    ///
    /// The messages are turned back into faults afterwards. Prefetching hundreds of them would otherwise leave hundreds of fulfilled objects registered in a
    /// context shared with the streams of this screen, for no benefit: the models are values, and are all that is kept.
    nonisolated private static func prefetchesModels(objectIDs: [NSManagedObjectID], within context: NSManagedObjectContext) async {
        await context.perform {
            guard let messages = try? PersistedMessage.getMessages(objectIDs: objectIDs, within: context) else { return }
            for message in messages {
                _ = try? createModel(of: message)
            }
            for message in messages where !message.hasChanges {
                context.refresh(message, mergeChanges: false)
            }
        }
    }

    // MARK: AttachmentProgressDataSource

    /// Follows the download of an attachment, by asking the engine — which is where the number is, and which reports it as it changes rather than being polled.
    ///
    /// The translation is the whole of the work here: the view speaks of a ``MessageAttachment``, this speaks of a join, and the engine speaks of a message
    /// identifier and an attachment number. The bytes come back and the fraction goes out, the engine having no business deciding how a download is drawn.
    ///
    /// **Both directions, and they arrive by different routes** — which is the one place the two are genuinely not symmetrical.
    ///
    /// A *download* is asked of the engine, which reports the bytes as they land. An *upload* is not: the app already polls
    /// `requestUploadAttachmentProgressesUpdatedSince(date:)` in `PersistedDiscussionsUpdatesCoordinator` and writes the fraction onto
    /// the sent join as a **transient** attribute, on the main queue. So the fraction is already ticking before this screen asks for it,
    /// and what this does for a sent attachment is watch that object rather than open anything. Step 36.
    ///
    /// **The direction is not the kind of join, and reading it off the join was a bug.** A message sent from another of the owner's devices is downloaded by
    /// this one, and its attachments sit on `SentFyleMessageJoinWithStatus` all the same — so this asks the *status*, which is the only thing that knows which
    /// way the bytes are going, and a received join is the one case where the join alone settles it.
    func getAsyncStreamOfProgressForAttachment(_ attachment: MessageAttachment) async throws -> (streamUUID: UUID, stream: AsyncStream<AttachmentProgress>) {
        guard case .objectID(let joinObjectID) = attachment.identifier else { throw ObvError.attachmentIsNotPersisted }

        // A *sent* join, which is not the same thing as an upload — see below.
        if let sentJoin = (try? viewContext.existingObject(with: joinObjectID)) as? SentFyleMessageJoinWithStatus {

            switch sentJoin.status {

            // **A sent join holding a download**, which is what a message sent from another of the owner's devices leaves on this one: its attachments come
            // through the engine's inbox and are fetched chunk by chunk exactly as a contact's are, and only the message being the owner's puts them on a
            // *sent* join. These two statuses occur in no other circumstance.
            //
            // Until this branch existed, every sent join was sent to the upload stream, which threw — `obvAttachmentIdentifierOfTheFirstUpload` is nil for a
            // message from another device, its recipient infos carrying a one-byte sentinel rather than an identifier. The `try?` in
            // `FollowedAttachment.asksForTheProgress()` swallowed it, so no stream was opened at all and the control turned its stub for the whole download,
            // there being no telling a nil fraction from nought. Every attachment from another owned device, not merely a failing one.
            case .downloadable, .downloading:
                guard let attachmentId = sentJoin.obvAttachmentIdentifierOfTheDownloadFromAnotherOwnedDevice else { throw ObvError.couldNotDetermineAttachmentIdentifier }
                guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
                let (streamUUID, streamOfBytes) = try await delegate.getAsyncStreamOfDownloadProgress(self, attachmentId: attachmentId)
                let stream = AsyncStream(AttachmentProgress.self, bufferingPolicy: .bufferingNewest(1)) { continuation in
                    let task = Task {
                        for await bytes in streamOfBytes {
                            continuation.yield(.init(fractionCompleted: bytes.fractionCompleted))
                        }
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
                // Deliberately **not** recorded in `uploadStreamUUIDs`: this one is ended by the fetch manager, like any other download.
                return (streamUUID, stream)

            // An attachment on its way **out**, asked of the send manager exactly as a download is asked of the fetch manager.
            //
            // **No waiting**, and it used to need some: a view asks for this when it is told the phase is `uploading`, and that is now only said
            // once the message has been posted — so an identifier always exists by the time this runs. See the image-source manager.
            case .uploadable, .uploading:
                guard let attachmentId = sentJoin.obvAttachmentIdentifierOfTheFirstUpload else { throw ObvError.couldNotDetermineAttachmentIdentifier }
                guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
                let (streamUUID, streamOfBytes) = try await delegate.getAsyncStreamOfUploadProgress(self, attachmentId: attachmentId)
                let stream = AsyncStream(AttachmentProgress.self, bufferingPolicy: .bufferingNewest(1)) { continuation in
                    let task = Task {
                        for await bytes in streamOfBytes {
                            continuation.yield(.init(fractionCompleted: bytes.fractionCompleted))
                        }
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
                uploadStreamUUIDs.insert(streamUUID)
                return (streamUUID, stream)

            // Nothing is transferring, so there is no number to follow. A view does not ask in these states — `followsTheProgress` is false for the phases they
            // produce — so reaching here is a caller's mistake rather than a state to accommodate.
            case .complete, .cancelledByServer, .untransferred:
                throw ObvError.progressIsOnlyAvailableForAnAttachmentBeingTransferred

            }

        }

        guard let receivedJoin = try? viewContext.existingObject(with: joinObjectID) as? ReceivedFyleMessageJoinWithStatus else {
            throw ObvError.progressIsOnlyAvailableForAReceivedAttachment
        }
        guard let attachmentId = receivedJoin.obvAttachmentIdentifier else { throw ObvError.couldNotDetermineAttachmentIdentifier }
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        let (streamUUID, streamOfBytes) = try await delegate.getAsyncStreamOfDownloadProgress(self, attachmentId: attachmentId)
        let stream = AsyncStream(AttachmentProgress.self, bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                for await bytes in streamOfBytes {
                    continuation.yield(.init(fractionCompleted: bytes.fractionCompleted))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return (streamUUID, stream)
    }



    func finishAsyncStreamOfProgressForAttachment(streamUUID: UUID) async {
        guard let delegate else { assertionFailure(); return }
        // The two directions are ended by different managers, so which one this stream came from has to be remembered.
        if uploadStreamUUIDs.remove(streamUUID) != nil {
            await delegate.finishAsyncStreamOfUploadProgress(self, streamUUID: streamUUID)
            return
        }
        await delegate.finishAsyncStreamOfDownloadProgress(self, streamUUID: streamUUID)
    }


    // MARK: SingleDiscussionCellViewActions

    /// Carries out what the reader asked of an attachment, and — before anything reaches the engine — shows that it was heard.
    ///
    /// The acknowledgement is the point. The engine takes a round trip to start a download, and until it does the join reads exactly as it did before the tap,
    /// so a control that waited for Core Data would sit there inert. That is what the legacy screen makes the reader put up with. So the request is remembered
    /// here and pushed straight into every stream showing that attachment; the engine then confirms it in its own time, or contradicts it, and either way what
    /// it says wins.
    func userWantsToActOnAttachment(_ attachment: MessageAttachment, action: AttachmentAction) async {
        guard case .objectID(let joinObjectID) = attachment.identifier else { assertionFailure(); return }
        switch action {
        case .resumeDownload:
            attachmentsAskedFor.insert(joinObjectID)
        case .pauseDownload:
            attachmentsAskedFor.remove(joinObjectID)
        }
        await yieldStateForAttachment(joinObjectID: joinObjectID)
        await passToTheDelegate(action, onJoin: joinObjectID)
    }


    /// Sends the request on its way to the engine, by the route that fits the attachment: a received one is fetched from its sender, a sent one from another of
    /// the reader's own devices.
    private func passToTheDelegate(_ action: AttachmentAction, onJoin joinObjectID: NSManagedObjectID) async {
        guard let delegate else { assertionFailure(); return }
        switch try? viewContext.existingObject(with: joinObjectID) {
        case let receivedJoin as ReceivedFyleMessageJoinWithStatus:
            await delegate.userWantsToActOnReceivedAttachment(self, receivedJoinObjectID: receivedJoin.typedObjectID, action: action)
        case let sentJoin as SentFyleMessageJoinWithStatus:
            await delegate.userWantsToActOnSentAttachment(self, sentJoinObjectID: sentJoin.typedObjectID, action: action)
        default:
            assertionFailure()
        }
    }


    /// Pushes a freshly computed state into every stream showing this attachment.
    ///
    /// Needed because a tap changes nothing Core Data can see: the file, the stand-in and the join are as they were, and only ``attachmentsAskedFor`` has moved.
    /// So the last state is taken up again with a new phase — the image is carried over untouched, a stand-in decoded once not being worth decoding again on
    /// every tap.
    private func yieldStateForAttachment(joinObjectID: NSManagedObjectID) async {
        guard let continuations = stateContinuationsForJoin[joinObjectID], !continuations.isEmpty else { return }
        guard let lastState = latestStateForJoin[joinObjectID] else { return }
        // Nothing a tap can do to an attachment that has arrived, is never going to, is on its way out, or takes no tap at all. An
        // upload belongs in the first group: it takes no tap, by decision — deleting the message is how it is stopped.
        switch lastState.phase {
        case .available, .uploading, .cancelledByServer, .leftBehindByAHistoryTransfer, .knownOnlyFromANotification: return
        case .downloadable, .askedToDownload, .downloading: break
        }
        let phase = phaseOfAnAttachmentThatIsNotHereYet(joinObjectID: joinObjectID, isDownloading: lastState.phase == .downloading)
        let state = AttachmentState(phase: phase, image: lastState.image)
        guard state != lastState else { return }
        latestStateForJoin[joinObjectID] = state
        for continuation in continuations.values {
            continuation.yield(state)
        }
    }


    // MARK: Helpers

    /// The discussion is resolved on the view context, but only its object ID is used further down: an `NSManagedObjectID` is context agnostic, so it
    /// can safely be handed to the fetched results controller running on the background context.
    private static func getDiscussionObjectID(discussionIdentifier: ObvDiscussionIdentifier, within context: NSManagedObjectContext) throws -> TypeSafeManagedObjectID<PersistedDiscussion> {
        guard let discussion = try PersistedDiscussion.getPersistedDiscussion(discussionIdentifier: discussionIdentifier, within: context) else {
            throw ObvError.couldNotFindDiscussion
        }
        return discussion.typedObjectID
    }

    private static func getMessageObjectID(cellIdentifier: SingleDiscussionView.CellIdentifier) throws -> TypeSafeManagedObjectID<PersistedMessage> {
        switch cellIdentifier {
        case .objectID(let objectID):
            return TypeSafeManagedObjectID<PersistedMessage>(objectID: objectID)
        case .forPreview, .newMessagesMarker:
            // A preview identifier does not identify a message, and is never handed to a data source.
            assertionFailure()
            throw ObvError.unexpectedCellIdentifierType
        }
    }

    /// What this screen puts in its list, read by the fetch behind the list **and** by the look each model takes at the message above it — see
    /// ``PersistedMessage/MessagesShownByTheScreen``, which exists so that the two cannot disagree.
    ///
    /// Two kinds of system message are left out because this screen draws them itself: the count of new messages, which it holds for the life of the screen instead of
    /// writing a row into the database, and the sentence saying the discussion is end-to-end encrypted, which is a fixed first row — the one way to make sure it can
    /// never appear below a message.
    ///
    /// `nonisolated`, being read while a model is built on a background context as well as on the main actor. The setting behind it is a `UserDefaults` read.
    nonisolated private static var messagesShownByTheScreen: PersistedMessage.MessagesShownByTheScreen {
        .init(includeMembersOfGroupV2WereUpdated: !ObvMessengerSettings.ContactsAndGroups.hideGroupMemberChangeMessages,
              categoriesOfSystemMessagesTheScreenDrawsItself: [.numberOfNewMessages, .discussionIsEndToEndEncrypted])
    }

    /// The sections of the list, in display order, given each cell's `sectionIdentifier`: **one per month**. See `SingleDiscussionView.Model.theSections`.
    ///
    /// **The one place that decides what a section is.** A month balances two costs of a SwiftUI `List`. Finding a row walks its section from the first row, so
    /// a single section costs most at the end of a long discussion, where people read. Each update of the list asks about every section, and each answer walks
    /// the sections from the first, so an update costs the square of the number of sections. With one section per day, hundreds over a long history, a scroll
    /// on an iPhone Xs was slower than with a single section. A month keeps the sections to tens and their rows to hundreds.
    ///
    /// A `sectionIdentifier` is `year × 10000 + month × 100 + day` in the reader's calendar, so a section starts where a date separator does. Each month is a
    /// single run: a message's `sectionIdentifier` is kept between those of its neighbours when it is written.
    ///
    /// **The month is the identifier without its last two digits**, which are the day. The year does not always have four digits: it is `8` in the Japanese
    /// calendar, where taking the first six characters gave a section per day.
    nonisolated fileprivate static func theSections(ofCellsWithSectionIdentifiers sectionIdentifiers: [String]) -> [SingleDiscussionView.Model.TheSection] {
        var theSections = [SingleDiscussionView.Model.TheSection]()
        for sectionIdentifier in sectionIdentifiers {
            let theMonth = String(sectionIdentifier.dropLast(2))
            if let theLastSection = theSections.last, theLastSection.identifier == theMonth {
                theSections[theSections.count - 1] = .init(identifier: theMonth, numberOfCells: theLastSection.numberOfCells + 1)
            } else {
                theSections.append(.init(identifier: theMonth, numberOfCells: 1))
            }
        }
        return theSections
    }

    /// Enough to fill a screen of short messages, which is the worst case: a bubble of a single line, its date and the spacing around it take about
    /// 65pt, so a tall iPad shows fewer than 20. Prefetching fewer would leave the last cells of the first screen showing a skeleton.
    private static let numberOfCellModelsToPrefetch = 25

    /// How many messages are fetched and turned into models in one hop onto the background context.
    ///
    /// Small enough that the models of the cells nearest the viewport become available quickly rather than after the whole window, and that a window superseded
    /// by a scroll is abandoned promptly; large enough that a window of a few hundred does not cost a few hundred round trips.
    private static let numberOfCellModelsPerPrefetchBatch = 25

    /// Holds a cell model, since `NSCache` stores objects and a model is a value.
    private final class CachedCellModel {
        let model: SingleDiscussionCellView.Model
        init(_ model: SingleDiscussionCellView.Model) { self.model = model }
    }


    /// Every cell model ever built, so that a cell released and re-created by the `LazyVStack` — which happens whenever the content moves — is shown with its
    /// content instead of flashing back to a redacted skeleton. The most visible case was the message *before* the one just received, which flashed every
    /// time a message arrived.
    ///
    /// An `NSCache` rather than a dictionary for two reasons. This data source lives in `ObvDataSources`, shared by every discussion for the life of the
    /// process, so an unbounded store would end up holding the model of every message ever displayed; `NSCache` bounds itself and gives its contents up under
    /// memory pressure. And it is thread-safe, which a dictionary is not — the fill site below is `nonisolated` and runs on the queue of a background context
    /// as well as on the main actor.
    ///
    /// `nonisolated(unsafe)` is that second claim, made where the compiler cannot check it: Apple documents `NSCache` as safe to access from several threads
    /// without locking it yourself. Nothing else is shared here.
    ///
    /// What it cannot promise is that a model will still be there: eviction is at the discretion of `NSCache`. That is acceptable because a miss is not a
    /// failure — the cell shows a skeleton until its own stream produces a model, exactly as before this cache existed. So it makes the flash rare, not
    /// impossible.
    nonisolated(unsafe) private static let cachedCellModels: NSCache<NSManagedObjectID, CachedCellModel> = {
        let cache = NSCache<NSManagedObjectID, CachedCellModel>()
        cache.countLimit = 500
        return cache
    }()


    /// The single place where a message becomes a cell model, so that the model seeded before the first frame and the models later produced by the
    /// stream of a cell are necessarily identical. Were they to differ, a prefetched cell would visibly change as soon as its stream started.
    /// `nonisolated`, as it is called both from the main actor when seeding, and from the queue of the background context when streaming. It only ever
    /// touches the message it is given, which the caller has already brought onto the right queue.
    ///
    /// Being the one place, it is also where the cache above is filled: every model this screen has ever shown is remembered here as a side effect.
    nonisolated fileprivate static func createModel(of message: PersistedMessage) throws -> SingleDiscussionCellView.Model {
        let model = try createModelWithoutCaching(of: message)
        cachedCellModels.setObject(CachedCellModel(model), forKey: message.objectID)
        return model
    }



    /// What a message the reader **sent** says about its own ephemerality, transcribed from `SentMessageCell`'s configuration.
    ///
    /// `readingRequiresUserAction` is false and not merely absent: a sender is never asked to tap their own message, and the legacy
    /// cell passes `false` there literally.
    ///
    /// **`readOnce` is dropped once the message is wiped**, which the received side does not do — legacy writes
    /// `message.readOnce && !message.isWiped` here and plain `message.readOnce` there. Kept as it is rather than unified: a wiped
    /// message has already burned, so a flame beside it would be promising something that has happened.
    nonisolated private static func ephemerality(of message: PersistedMessageSent) -> TheEphemeralityOfAMessage {
        .init(readOnce: message.readOnce && !message.isWiped,
              readingRequiresUserAction: false,
              // Stated because it is true of the message, and drawn by nothing: `WhatWillHappenWhenThisMessageIsRead` is
              // received-only, as it is in legacy, and its gate — `readingRequiresUserAction` — is false here anyway.
              visibilityDuration: message.visibilityDuration,
              scheduledVisibilityDestructionDate: message.expirationForSentLimitedVisibility?.expirationDate,
              scheduledExistenceDestructionDate: message.expirationForSentLimitedExistence?.expirationDate)
    }


    /// The same for a message **received**, transcribed from `ReceivedMessageCell`.
    ///
    /// Here `readingRequiresUserAction` is real, and it decides what each of the two views says. The countdown shows a message whose
    /// body has still to be tapped counting down its *existence* only, its visibility not having started — see
    /// ``TheCountdownOfAnEphemeralMessage``; and the same flag is the whole of what makes the chip of terms appear, `readOnce` and
    /// `visibilityDuration` being what it then has to say — see ``WhatWillHappenWhenThisMessageIsRead``.
    ///
    /// **`visibilityDuration` is the duration the sender granted and not a date**, which is the one fact this model was missing: a
    /// message not yet read has no visibility expiration to take a date from, `expirationForReceivedLimitedVisibility` being written
    /// when it is read. So it cannot be derived from the date below, and the chip could not have been drawn without it.
    nonisolated private static func ephemerality(of message: PersistedMessageReceived) -> TheEphemeralityOfAMessage {
        .init(readOnce: message.readOnce,
              readingRequiresUserAction: message.readingRequiresUserAction,
              visibilityDuration: message.visibilityDuration,
              scheduledVisibilityDestructionDate: message.expirationForReceivedLimitedVisibility?.expirationDate,
              scheduledExistenceDestructionDate: message.expirationForReceivedLimitedExistence?.expirationDate)
    }


    nonisolated private static func createModelWithoutCaching(of message: PersistedMessage) throws -> SingleDiscussionCellView.Model {

        // One look at the message above, which answers two questions at once: whether this message opens a day, and whether it opens a run of messages from its
        // sender. Every fact it needs is a stored attribute, so this is an indexed query or two and no message materialized — see
        // `getWhatTheMessageAboveSays(among:)`, which says why the sender takes a query of its own.
        //
        // The *same* description the list is fetched with, so that the row above is the row the reader sees: were a message this screen does not show taken for it, a
        // message opening a day would be compared against something invisible and its separator would silently not be drawn.
        let whatTheMessageAboveSays = try? message.getWhatTheMessageAboveSays(among: messagesShownByTheScreen)

        if let sentMessage = message as? PersistedMessageSent {
            return .sentMessage(.init(
                content: content(of: sentMessage),
                statusIcon: statusIcon(of: sentMessage),
                timestamp: sentMessage.timestamp,
                dateSeparator: whatTheMessageAboveSays?.dayThisMessageOpens,
                isForwarded: sentMessage.forwarded,
                isShownAsEdited: isShownAsEdited(sentMessage),
                repliedTo: repliedTo(of: sentMessage),
                reactions: reactions(of: sentMessage),
                ephemerality: ephemerality(of: sentMessage)))
        } else if let receivedMessage = message as? PersistedMessageReceived {
            return .receivedMessage(.init(
                content: content(of: receivedMessage),
                timestamp: receivedMessage.timestamp,
                dateSeparator: whatTheMessageAboveSays?.dayThisMessageOpens,
                sender: sender(of: receivedMessage, whatTheMessageAboveSays: whatTheMessageAboveSays),
                isForwarded: receivedMessage.forwarded,
                isShownAsEdited: isShownAsEdited(receivedMessage),
                missedMessageCount: receivedMessage.missedMessageCount,
                repliedTo: repliedTo(of: receivedMessage),
                reactions: reactions(of: receivedMessage),
                ephemerality: ephemerality(of: receivedMessage)))
        } else if let systemMessage = message as? PersistedMessageSystem {
            return .systemMessage(.init(
                text: systemMessage.textBodyWithoutTimestamp ?? "",
                tint: tint(of: systemMessage),
                timestamp: timestampShown(of: systemMessage),
                dateSeparator: whatTheMessageAboveSays?.dayThisMessageOpens,
                expirations: expirations(setBy: systemMessage),
                tappable: tappable(systemMessage)))
        } else {
            assertionFailure()
            throw ObvError.unexpectedMessageKind
        }
    }


    /// The colour of the pill a system message is drawn in, transcribed category for category from `SystemMessageCell.updateConfiguration(using:)`.
    ///
    /// The two categories this screen draws itself never reach here, being excluded from its list — they are answered anyway rather than asserted, an unreachable
    /// branch that draws something being better than one that draws nothing.
    nonisolated private static func tint(of systemMessage: PersistedMessageSystem) -> SystemMessageCellView.Model.Tint {
        switch systemMessage.category {
        case .contactJoinedGroup,
                .contactLeftGroup,
                .contactWasDeleted,
                .contactIsOneToOneAgain,
                .contactWasIntroducedToAnotherContact,
                .discussionIsEndToEndEncrypted,
                .membersOfGroupV2WereUpdated,
                .notPartOfTheGroupAnymore,
                .ownedIdentityIsNoLongerPartOfGroupV2Admins,
                .ownedIdentityIsPartOfGroupV2Admins,
                .rejoinedGroup:
            return .green
        case .contactIdentityDidCaptureSensitiveMessages,
                .discussionWasRemotelyWiped,
                .ownedIdentityDidCaptureSensitiveMessages,
                .updatedDiscussionSharedSettings:
            return .orange
        case .contactRevokedByIdentityProvider,
                .numberOfNewMessages:
            return .red
        case .callLogItem:
            return .purple
        }
    }


    /// What tapping a system message asks for, and nil for the many that answer nothing — transcribed from `SystemMessageCell.tappedStuff(...)`.
    ///
    /// A call log answers only two of its kinds: a call refused because Olvid had no microphone, and one refused because this device is set not to take calls. Every
    /// other call report is inert there, and is here.
    nonisolated private static func tappable(_ systemMessage: PersistedMessageSystem) -> TappableSystemMessage? {

        let request: TappableSystemMessage.Request

        switch systemMessage.category {

        case .updatedDiscussionSharedSettings:
            request = .showTheSharedSettings

        case .membersOfGroupV2WereUpdated, .ownedIdentityIsPartOfGroupV2Admins, .ownedIdentityIsNoLongerPartOfGroupV2Admins:
            request = .showWhoTheDiscussionIsWith

        case .callLogItem:
            switch systemMessage.optionalCallLogItem?.callReportKind {
            case .rejectedIncomingCallBecauseOfDeniedRecordPermission:
                request = .askForPermissionToUseTheMicrophone
            case .rejectedIncomingCallAsTheReceiveCallsOnThisDeviceSettingIsFalse:
                request = .showTheSettingsForCalls
            default:
                return nil
            }

        case .contactJoinedGroup,
                .contactLeftGroup,
                .numberOfNewMessages,
                .discussionIsEndToEndEncrypted,
                .contactWasDeleted,
                .discussionWasRemotelyWiped,
                .contactRevokedByIdentityProvider,
                .notPartOfTheGroupAnymore,
                .rejoinedGroup,
                .contactIsOneToOneAgain,
                .ownedIdentityDidCaptureSensitiveMessages,
                .contactWasIntroducedToAnotherContact,
                .contactIdentityDidCaptureSensitiveMessages:
            return nil

        }

        return .init(identifier: .objectID(systemMessage.objectID), request: request)

    }


    /// What a change of the shared settings set, in the order the legacy cell lists them: read-once, then a visibility, then an existence.
    ///
    /// The durations are formatted **here**, where `DurationFormatter` is, and reach the view as words. A formatter per message rather than one kept around: only a
    /// change of the shared settings ever builds one, which is a handful of messages in a discussion.
    nonisolated private static func expirations(setBy systemMessage: PersistedMessageSystem) -> [SystemMessageCellView.Model.Expiration] {

        guard let expirationJSON = systemMessage.expirationJSON else { return [] }

        let durationFormatter = DurationFormatter()
        var expirations = [SystemMessageCellView.Model.Expiration]()

        if expirationJSON.readOnce {
            expirations.append(.readOnce)
        }
        if let visibilityDuration = expirationJSON.visibilityDuration {
            expirations.append(.visibility(duration: durationFormatter.string(from: visibilityDuration) ?? ""))
        }
        if let existenceDuration = expirationJSON.existenceDuration {
            expirations.append(.existence(duration: durationFormatter.string(from: existenceDuration) ?? ""))
        }

        return expirations

    }


    /// When a system message says it happened, and nil for the two the legacy screen gives no date to — the count of new messages, which marks a place in the reading
    /// rather than a moment, and the sentence about encryption, which is true of the whole discussion.
    nonisolated private static func timestampShown(of systemMessage: PersistedMessageSystem) -> Date? {
        switch systemMessage.category {
        case .numberOfNewMessages, .discussionIsEndToEndEncrypted:
            return nil
        default:
            return systemMessage.timestamp
        }
    }


    /// Whether a message shows the reactions it has, and nil for the one kind that shows none.
    ///
    /// **One branch, and it is the legacy one:** `ReceivedMessageCell` hides its reactions view when `readingRequiresUserAction`, and nowhere else — not on a wiped
    /// message, not on a location, not on a poll — while `SentMessageCell` has no such branch at all, a message of one's own never being one to ask to see. So the
    /// guard is the received one and everything else keeps its chip.
    ///
    /// It carries no emoji and no count: those are followed by the chip through a stream of its own, since reacting touches nothing this model is built from. See
    /// ``ReactionsOfAMessage``.
    nonisolated private static func reactions(of message: PersistedMessage) -> ReactionsOfAMessage? {
        guard (message as? PersistedMessageReceived)?.readingRequiresUserAction != true else { return nil }
        return .init(identifier: .objectID(message.objectID), theOnesItAlreadyHad: theReactionsAlreadyOn(message))
    }


    /// What a message has been reacted with **now**, so that its chip can be drawn on the cell's first frame — see ``ReactionsOfAMessage/theOnesItAlreadyHad``.
    ///
    /// **Counted the way ``ObvReactionsCountViewModelStreamManager`` counts them**, deliberately and not by a shorter route: the chip is drawn from that stream a
    /// moment later, and a seed that grouped or ordered differently would make every chip on the first screen change once for nothing. At most one reaction of the
    /// reader's own and any number received, grouped by emoji.
    ///
    /// **The one thing this adds to the hot path**, and it is worth naming: building a cell's model now faults the message's reactions. It is a to-many that is
    /// empty for the great majority of messages, and what it buys is measured — the entry's cover lifted at **432ms before and 368 after**, the chips no longer
    /// arriving after the first layout and dragging the content with them.
    nonisolated private static func theReactionsAlreadyOn(_ message: PersistedMessage) -> [ObvReactionsCountViewModel.ReactionAndCount] {
        var countForReaction = [Character: Int]()
        for reaction in message.reactions {
            guard let emoji = reaction.emoji?.first else { continue }
            countForReaction[emoji, default: 0] += 1
        }
        // **Sorted, and that is not tidiness** — `ObvReactionsCountViewModel.init(reactionsAndCount:)` sorts what the stream carries, so a seed left in the order a
        // `Dictionary` happens to enumerate is a chip that **reorders its emojis** the moment the stream answers, and Swift randomises that order per run. It was
        // written to explain a glitch in the cover's fade and did not: the fade broke identically with it sorted, which is recorded rather than deleted because
        // the reasoning is still right and the conclusion was still wrong. It stays because an unsorted seed *would* reshuffle, whether or not anyone has seen it.
        return countForReaction.map { ObvReactionsCountViewModel.ReactionAndCount(emoji: $0.key, count: $0.value) }.sorted()
    }


    /// The message a message answers, and nil when it answers none — or when this message is in no state to quote anything.
    ///
    /// **The suppression is unified on the received rule**, as the edited mark is: the legacy received cell clears the reply-to for a message that is wiped or has
    /// still to be asked for, and for a location or a poll, while the sent cell keeps it on a wiped message. A message that says nothing of itself should not go on
    /// quoting another, whichever side of the discussion it is on.
    ///
    /// Everything is resolved here, on the context the model is built on, where the legacy screen resolves it asynchronously through `DiscussionCacheManager` and
    /// reconfigures the cell when the answer lands — see ``MessageRepliedTo``. The thumbnail is the exception, and it needs no second cadence either: it is handed over
    /// as an attachment like any other, and the picture arrives through the machinery every attachment of this screen already goes through.
    nonisolated private static func repliedTo(of message: PersistedMessage) -> MessageRepliedTo? {

        guard !message.isWiped else { return nil }
        guard (message as? PersistedMessageReceived)?.readingRequiresUserAction != true else { return nil }
        guard !message.isLocationMessage else { return nil }
        guard message.poll == nil else { return nil }

        switch message.genericRepliesTo {

        case .none:
            return nil

        case .notAvailableYet:
            // A reply can arrive before the message it answers, and says so rather than pretending it is gone.
            return .init(identifier: nil, sender: .nobody, whatItSays: .itIsNotHereYet, thumbnail: nil)

        case .deleted:
            return .init(identifier: nil, sender: .nobody, whatItSays: .itWasDeleted, thumbnail: nil)

        case .available(message: let messageRepliedTo):

            // Wiped by the expiry of its own visibility is worded as deleted, as the legacy screen words it, and keeps neither name nor picture.
            if messageRepliedTo.isLocallyWiped {
                return .init(identifier: nil, sender: .nobody, whatItSays: .itWasDeleted, thumbnail: nil)
            }

            return .init(identifier: .objectID(messageRepliedTo.objectID),
                         sender: senderOfTheMessageRepliedTo(messageRepliedTo),
                         whatItSays: whatTheMessageRepliedToSays(messageRepliedTo),
                         thumbnail: thumbnailOfTheMessageRepliedTo(messageRepliedTo))

        }

    }


    /// Whoever wrote the message being answered, which is what colours the header.
    nonisolated private static func senderOfTheMessageRepliedTo(_ messageRepliedTo: PersistedMessage) -> MessageRepliedTo.Sender {
        if let received = messageRepliedTo as? PersistedMessageReceived {
            guard let contact = received.contactIdentity, let contactCryptoId = try? contact.cryptoId else {
                // The same sentence the sender of a message from a contact since deleted is given, so that one screen says it one way.
                return .aContactNoLongerKnown(name: CommonString.deletedContact)
            }
            // The full display name, as legacy interpolates into "Replying to %@" — the design keeps the name and drops the sentence.
            let color = AppTheme.shared.identityColors(for: contactCryptoId).text
            return .aContact(name: contact.customOrFullDisplayName, color: Color(color))
        } else if messageRepliedTo is PersistedMessageSent {
            return .theReader(name: CommonString.Word.You)
        } else {
            // A system message cannot be replied to, so this is unreachable rather than merely unlikely.
            assertionFailure()
            return .nobody
        }
    }


    /// What the second line of the header shows: the words of the message answered, the name of its first file when it has no words, or what became of it.
    ///
    /// The rule for the first two is settled with the design — the words when there are any, the file name as the fallback, never both.
    nonisolated private static func whatTheMessageRepliedToSays(_ messageRepliedTo: PersistedMessage) -> MessageRepliedTo.WhatItSays {

        if messageRepliedTo.isRemoteWiped {
            return .itWasWipedBy(contactNamed: nameOfWhoeverWiped(messageRepliedTo))
        }

        if let textBody = messageRepliedTo.textBody, !textBody.isEmpty {
            return .theseWords(textBody)
        }

        if let fileName = firstAttachment(of: messageRepliedTo)?.fileName {
            return .theseWords(fileName)
        }

        return .theseWords("")

    }


    /// Whoever wiped the message being answered, when they can be named — the same lookup ``wiped(of:)`` makes, on the message's own context.
    nonisolated private static func nameOfWhoeverWiped(_ message: PersistedMessage) -> String? {
        guard let context = message.managedObjectContext,
              let ownedCryptoId = message.discussion?.ownedIdentity?.cryptoId,
              let deleterCryptoId = message.deleterCryptoId,
              let deleter = try? PersistedObvContactIdentity.get(contactCryptoId: deleterCryptoId,
                                                                 ownedIdentityCryptoId: ownedCryptoId,
                                                                 whereOneToOneStatusIs: .any,
                                                                 within: context) else {
            return nil
        }
        return deleter.customOrShortDisplayName
    }


    /// The attachment whose picture the header shows, and nil when there is none to show.
    ///
    /// Legacy's rule, transcribed: a message with no attachment shows none, and **a message the reader has yet to ask to see shows none either** — its files are in
    /// the database from the moment it arrives, so a thumbnail would show what its sender covered.
    nonisolated private static func thumbnailOfTheMessageRepliedTo(_ messageRepliedTo: PersistedMessage) -> MessageAttachment? {
        guard (messageRepliedTo as? PersistedMessageReceived)?.readingRequiresUserAction != true else { return nil }
        return firstAttachment(of: messageRepliedTo)
    }


    /// The first attachment of a message, in the order the message shows them.
    ///
    /// The legacy screen chooses among the joins with `getAppropriateHardlinkForJoinsOfReplyTo(_:)`; the first is what a reader takes a quotation to be showing, and it
    /// is what the design draws.
    nonisolated private static func firstAttachment(of message: PersistedMessage) -> MessageAttachment? {
        guard let joins = message.fyleMessageJoinWithStatus else { return nil }
        guard let join = joins.sorted(by: { $0.index < $1.index }).first else { return nil }
        return attachment(of: join)
    }


    /// Whether a message says it was edited, which is **not** simply `isEdited`.
    ///
    /// The two legacy cells disagree, and this is where the disagreement is settled. `ReceivedMessageCell` suppresses the mark when the message is wiped, when it has
    /// still to be asked for, **or** when it is a location; `SentMessageCell` suppresses it for a location alone. Nothing in the product argues for the difference —
    /// it is the same fact about the same kind of thing — so the two are **unified on the received rule**, which is the stricter and the more sensible of them: a
    /// message that says nothing of itself must not claim to have been edited either.
    ///
    /// What that changes against the legacy screen: a *wiped* message the reader had edited no longer shows the pencil on the sent side. Nothing else moves — the
    /// tap-to-read clause reads a property only a received message has, so it was already vacuous for a sent one.
    nonisolated private static func isShownAsEdited(_ message: PersistedMessage) -> Bool {
        guard message.isEdited else { return false }
        guard !message.isWiped else { return false }
        guard !message.isLocationMessage else { return false }
        guard (message as? PersistedMessageReceived)?.readingRequiresUserAction != true else { return false }
        return true
    }


    /// What a received cell does about its sender: nothing at all in a one-to-one discussion, the name and the picture above the first message of a run, and the
    /// column of that picture kept empty within a run.
    ///
    /// Both rules come from outside the message, and the legacy cell reads them the same way. Which of the three it is depends on the *discussion* — a one-to-one
    /// one never names a sender, there being only one — and on the message above, which is what `whatTheMessageAboveSays` was fetched for. A discussion whose kind
    /// cannot be read is treated as a group, as it is there.
    nonisolated private static func sender(of receivedMessage: PersistedMessageReceived, whatTheMessageAboveSays: PersistedMessage.WhatTheMessageAboveSays?) -> SenderOfAMessage {

        switch try? receivedMessage.discussion?.kind {
        case .oneToOne:
            return .neverShown
        case .groupV1, .groupV2, .none:
            break
        }

        guard whatTheMessageAboveSays?.followsAMessageFromTheSameContact != true else {
            return .withinARunOfTheirMessages
        }

        guard let contact = receivedMessage.contactIdentity, let contactCryptoId = try? contact.cryptoId else {
            // A contact since deleted still says who they were, as far as it can be said: the sentence and the icon of the legacy cell, in the secondary label
            // colour that `CircledInitialsConfiguration.icon` gives its own picture.
            return .shown(.init(name: CommonString.deletedContact,
                                nameColor: Color(AppTheme.shared.colorScheme.secondaryLabel),
                                avatar: .init(characterOrIcon: .icon(.personFillXmark),
                                              colors: .init(foreground: AppTheme.shared.colorScheme.secondaryLabel,
                                                            background: AppTheme.shared.colorScheme.systemFill),
                                              photoURL: nil),
                                // **The one sender with nobody to open.** There is no contact left, so tapping this name does nothing — see
                                // `MessageSender.contactIdentifier`.
                                contactIdentifier: nil))
        }

        // The name in the colour derived from the sender's cryptographic identity, exactly as the legacy cell colours it — and the same colour their picture is
        // drawn in, `ObvAvatarViewModel(contact:)` reaching this very function through `CircledInitialsConfiguration.foregroundColor(appTheme:)`.
        let colorOfTheSender = AppTheme.shared.identityColors(for: contactCryptoId).text
        return .shown(.init(name: contact.nameForContactNameInGroupDiscussion,
                            nameColor: Color(colorOfTheSender),
                            avatar: .init(contact: contact),
                            // What tapping this sender opens. A group member is a contact whether or not the reader has a one-to-one discussion with them, and the
                            // screen this names knows the difference — see `SingleDiscussionCellViewActions.userWantsToSeeAContact(contactIdentifier:)`.
                            contactIdentifier: try? contact.obvContactIdentifier))

    }


    /// What a message shows: the one thing that replaces its content, or its text and its attachments.
    ///
    /// **Resolved here, once, and never in a view.** The legacy cells configure every part of themselves and then blank most of it again, across four
    /// branches. Returning a value instead means a view draws one thing and has nothing to undo.
    ///
    /// The branches are resolved in the order in which they *outrank* one another, which is what the legacy cells express by clearing what they have just built:
    /// wiped first, since a message that is gone says nothing whatever else it was; then the tap-to-read guard, before anything is read from the message; then a place
    /// and a poll; and the ordinary case last.
    nonisolated private static func content(of message: PersistedMessage) -> MessageContent {
        if let wiped = wiped(of: message) {
            return .wiped(wiped)
        }
        // **Before anything is read from the message.** One the reader has to ask to see must not have its body, its preview or its pictures put into a model at all —
        // see `tapToRead(of:)`.
        if let tapToRead = tapToRead(of: message) {
            return .tapToRead(tapToRead)
        }
        if let location = locationInMessage(of: message) {
            return .location(location)
        }
        if let poll = pollInMessage(of: message) {
            return .poll(poll)
        }
        let linkPreview = linkPreview(of: message)
        return .ordinary(.init(
            textBody: textBody(of: message, renderedBy: linkPreview),
            linkPreview: linkPreview,
            gif: gifInMessage(of: message),
            images: imageAttachments(of: message),
            video: videoAttachment(of: message),
            document: documentAttachment(of: message),
            audio: audioAttachment(of: message),
            cards: cardAttachments(of: message)))
    }


    /// What is left of a message that has been wiped, and nil for every message that has not.
    ///
    /// Which of the two sentences it is comes straight from which metadata the message carries, and each of those has exactly one writer — see ``WipedMessage``, where
    /// the reasoning is written down, including why "deleted by You" is never produced.
    ///
    /// The deleter's name is resolved **on the message's own context**, and not on the view context the legacy cell reaches for: this runs wherever the model is built,
    /// which is a background context. A deleter who cannot be found — a contact since deleted, a member who left the group — leaves no name, and the sentence becomes
    /// "Remotely wiped".
    nonisolated private static func wiped(of message: PersistedMessage) -> WipedMessage? {

        if message.isLocallyWiped {
            return .byTheExpiryOfItsOwnVisibility
        }

        guard message.isRemoteWiped else { return nil }

        guard let context = message.managedObjectContext,
              let ownedCryptoId = message.discussion?.ownedIdentity?.cryptoId,
              let deleterCryptoId = message.deleterCryptoId,
              let deleter = try? PersistedObvContactIdentity.get(contactCryptoId: deleterCryptoId,
                                                                 ownedIdentityCryptoId: ownedCryptoId,
                                                                 whereOneToOneStatusIs: .any,
                                                                 within: context) else {
            return .byAContact(named: nil)
        }

        return .byAContact(named: deleter.customOrShortDisplayName)

    }


    /// A message the reader has to ask to see, and nil for every message they may simply read.
    ///
    /// **This is the guard that keeps an ephemeral message from being shown before it is asked for**, and it has to come before every other branch: the body and the
    /// files of such a message are in the database from the moment it arrives — being marked read puts nothing there, it only sets the status and starts the
    /// expiration — so a model built without asking this question shows what the sender promised would be shown once, and shows it without telling them.
    ///
    /// `readingRequiresUserAction` is a *received* message's business only: `readOnce || visibilityDuration != nil`, while the status is `.new` or `.unread`. Revealing
    /// makes it `.read`, and this then answers nil.
    ///
    /// What is carried over is the attachments, for their **shapes** — a covered message must occupy exactly what it will occupy once read, or revealing it moves the
    /// discussion under the reader's finger — and whether there is a body, which is what decides the bubble. Never the body itself, and never the link preview.
    nonisolated private static func tapToRead(of message: PersistedMessage) -> TapToRead? {

        guard !message.isWiped else { return nil }
        guard let receivedMessage = message as? PersistedMessageReceived else { return nil }
        guard receivedMessage.readingRequiresUserAction else { return nil }

        return .init(identifier: .objectID(receivedMessage.objectID),
                     showsTheBubble: receivedMessage.textBodyToSend?.isEmpty == false,
                     covered: .init(textBody: nil,
                                    linkPreview: nil,
                                    gif: gifInMessage(of: receivedMessage),
                                    images: imageAttachments(of: receivedMessage),
                                    video: videoAttachment(of: receivedMessage),
                                    document: documentAttachment(of: receivedMessage),
                                    audio: audioAttachment(of: receivedMessage),
                                    cards: cardAttachments(of: receivedMessage)))

    }


    /// The poll a message asks, and nil for every message that does not.
    ///
    /// Two identifiers and nothing else: what a poll *says* comes through its own stream, since a vote changes neither the message nor the poll. A wiped message never
    /// reaches here — `wipeThisMessage` deletes the poll with it, and the guard above resolves wiping first in any case.
    ///
    /// Answering non-nil is what keeps `legacyPollMessageBody` out of the bubble: the question and the answers as plain markdown text, written for clients too old to
    /// know what a poll is, which this screen would otherwise show asterisks and all.
    nonisolated private static func pollInMessage(of message: PersistedMessage) -> PollInMessage? {
        guard !message.isWiped else { return nil }
        guard let poll = message.poll else { return nil }
        return .init(identifier: .objectID(message.objectID),
                     pollIdentifier: .objectID(poll.objectID),
                     shape: shape(of: poll))
    }


    /// What a poll is, as opposed to how it has been answered — read here so that the bubble is its final height on the frame it first appears on. See
    /// ``PollInMessage/Shape``.
    ///
    /// **Two relationships are walked that were not walked before**, `message.poll` and `poll.candidates`, and that is the whole cost of this. It is paid where
    /// every other relationship this model needs is already paid: on a background context, in a batch, ahead of the cells that will want it — the attachments of a
    /// message are walked join by join right here, and a wiped message even runs a fetch to name whoever wiped it. Nothing of it is on the scrolling path, which
    /// reads a cached model synchronously and nothing else. If it ever does show up in a measurement, the lever is
    /// `relationshipKeyPathsForPrefetching` on the fetch request behind the list, which nothing sets today: it would turn a fault per poll into one join.
    ///
    /// The candidates are sorted by `sortIndex`, as `PollStateStreamManager` sorts them, so the redacted rows and the rows that replace them are in the same order.
    /// A candidate with no UUID cannot be one of the drawn view's rows and is dropped, exactly as it is there.
    nonisolated private static func shape(of poll: PersistedPoll) -> PollInMessage.Shape {
        let candidates: [PollInMessage.Shape.Candidate] = poll.candidates
            .sorted(by: \.sortIndex)
            .compactMap { candidate in
                guard let candidateUUID = candidate.uuid else { return nil }
                return .init(uuid: candidateUUID, text: candidate.text)
            }
        return .init(question: poll.question,
                     multipleChoice: poll.multipleChoice,
                     candidates: candidates,
                     expirationDate: poll.expiration)
    }


    /// The place a location message shows, and nil for every message that is not one.
    ///
    /// **The message says whether it is a location, and its location says where.** `isLocation` stays true for the whole life of such a message, whereas the
    /// `PersistedLocation` it points at is severed and deleted when sharing ends — which is exactly what tells the two states apart here: a location message with
    /// no location is one whose sharing is over.
    ///
    /// Answering non-nil is what keeps the Google Maps URL of `legacyLocationMessageBody` out of the bubble, and with it the link preview this screen would
    /// otherwise fetch from Google for it.
    nonisolated private static func locationInMessage(of message: PersistedMessage) -> LocationInMessage? {

        guard message.isLocationMessage else { return nil }

        // A wiped message says nothing, whatever it once was, and that outranks being a location: were it not for this, wiping a location message would leave its
        // map on screen. Step 11 replaces the emptiness this falls back to with the wiped bubble the legacy screen draws.
        guard !message.isWiped else { return nil }

        let location: PersistedLocation? = switch message {
        case let sentMessage as PersistedMessageSent: sentMessage.locationContinuousSent ?? sentMessage.locationOneShotSent
        case let receivedMessage as PersistedMessageReceived: receivedMessage.locationContinuousReceived ?? receivedMessage.locationOneShotReceived
        default: nil
        }

        let identifier = LocationInMessage.Identifier.objectID(message.objectID)

        // The sharer, from the *message* as the legacy screen takes it: its contact for a message received, the owned identity for one sent.
        let sharer: ObvAvatarViewModel? = switch message {
        case let sentMessage as PersistedMessageSent: sentMessage.discussion?.ownedIdentity.map({ ObvAvatarViewModel(ownedIdentity: $0) })
        case let receivedMessage as PersistedMessageReceived: receivedMessage.contactIdentity.map({ ObvAvatarViewModel(contact: $0) })
        default: nil
        }

        guard let location else {
            return .init(identifier: identifier, locationIdentifier: nil, kind: .ended, coordinate: nil, isOwnSharingFromThisDevice: false, sharer: sharer)
        }

        var kind: LocationInMessage.Kind = switch try? location.continuousOrOneShot {
        case .continuous: .continuous
        case .oneShot: .oneShot
        // A raw value that decodes to neither can only mean a location this app cannot make sense of, which is what the legacy screen draws as sharing that ended.
        case nil: .ended
        }

        // **Sharing whose expiry has passed is over, and is drawn as over** — a deliberate departure. Such a location is severed from its message in bulk by a
        // bootstrap sweep, so a reader can meet one that is expired and still attached; the legacy screen goes on calling it continuous and merely makes its map
        // transparent, which leaves a blank square carrying an avatar and a live button. Nothing about that says the sharing has finished.
        if kind == .continuous, let continuousLocation = location as? PersistedLocationContinuous, continuousLocation.isSharingLocationExpired {
            kind = .ended
        }

        guard kind != .ended else {
            return .init(identifier: identifier, locationIdentifier: nil, kind: .ended, coordinate: nil, isOwnSharingFromThisDevice: false, sharer: sharer)
        }

        // Only the reader's own continuous sharing, from this very device, can be stopped from here or shows a countdown — `LocationView`'s
        // `userCanStopSharingLocation`, which is hardcoded false for every received message and reads the device for a sent one.
        let isOwnSharingFromThisDevice: Bool
        if let sentMessage = message as? PersistedMessageSent, let continuousSent = sentMessage.locationContinuousSent {
            isOwnSharingFromThisDevice = (continuousSent.ownedDevice?.isCurrentDevice ?? false) && sentMessage.status != .sentFromAnotherOwnedDevice
        } else {
            isOwnSharingFromThisDevice = false
        }

        return .init(identifier: identifier,
                     locationIdentifier: .objectID(location.objectID),
                     kind: kind,
                     // A seed for the first frame only: what follows a sender who moves is the stream above, keyed on the location.
                     coordinate: .init(latitude: location.latitude, longitude: location.longitude),
                     isOwnSharingFromThisDevice: isOwnSharingFromThisDevice,
                     sharer: sharer)

    }

    /// Where an attachment stands, and the best picture of it there is, again whenever either changes.
    ///
    /// **The join decides, always.** The cache is asked for pixels and never for whether a file exists, which is not something it can know: it is keyed on the
    /// file, so its entries outlive the messages that brought them. A reader who deletes a message and receives the same photograph again would otherwise be
    /// shown it as if it had been downloaded, and find it gone at the next launch — the cache being right about what the file looks like and wrong about there
    /// being one.
    ///
    /// The stream stays open, watching the join, because nothing else would say that the file has arrived: the model of a message is fetched from the message,
    /// and Core Data does not report a message as changed when one of its attachments does. One controller per attachment being shown, which is the same order
    /// as the one this screen already runs per visible cell.
    func getAsyncStreamOfStateForAttachment(_ attachment: MessageAttachment, pixelSize: CGSize) -> AsyncStream<AttachmentState> {
        AsyncStream { continuation in
            guard case .objectID(let joinObjectID) = attachment.identifier else {
                continuation.finish()
                return
            }
            // Registered so that a tap on the control can push a new phase at once, Core Data having nothing to say about a request the engine has not acted on.
            let registration = UUID()
            stateContinuationsForJoin[joinObjectID, default: [:]][registration] = continuation

            // The message as well as the join: the manager watches the recipients of one and the status of the other. Read from the **view**
            // context, on this queue, and handed to a manager working on the background one — an object ID identifies a row and not a context,
            // so which context answered is of no consequence. Reading it inside the task below would be too late: the manager has to be
            // visible to `onTermination`.
            guard let messageObjectID = (try? viewContext.existingObject(with: joinObjectID) as? FyleMessageJoinWithStatus)?.message?.objectID else {
                continuation.finish()
                return
            }
            let manager = AttachmentImageSourceStreamManager(joinObjectID: joinObjectID, messageObjectID: messageObjectID, context: backgroundContext)
            let task = Task { [weak self] in
                do {
                    let (_, sources) = try await manager.startStream()
                    for await source in sources {
                        guard let self else { break }
                        let state = await self.state(of: source, for: joinObjectID, pixelSize: pixelSize, sha256: attachment.sha256)
                        await MainActor.run {
                            // The request stands only until the engine has visibly acted on it: any phase but this one means it has.
                            if state.phase != .askedToDownload {
                                self.attachmentsAskedFor.remove(joinObjectID)
                            }
                            // Remembered so that a tap can be answered from it, Core Data having nothing to say about a request the engine has not acted on.
                            self.latestStateForJoin[joinObjectID] = state
                        }
                        continuation.yield(state)
                    }
                } catch {
                    assertionFailure()
                }
                continuation.finish()
            }
            continuation.onTermination = { [weak self] _ in
                task.cancel()
                manager.finishStream()
                Task { @MainActor in self?.forgetStateContinuation(registration, forJoin: joinObjectID) }
            }
        }
    }


    /// Drops one view's stream, and everything remembered for the attachment once no view is left showing it.
    ///
    /// The request itself is *not* forgotten: a reader who taps and scrolls away must find the control where they left it. That one lives in
    /// ``attachmentsAskedFor`` until the engine answers.
    private func forgetStateContinuation(_ registration: UUID, forJoin joinObjectID: NSManagedObjectID) {
        stateContinuationsForJoin[joinObjectID]?.removeValue(forKey: registration)
        guard stateContinuationsForJoin[joinObjectID]?.isEmpty ?? false else { return }
        stateContinuationsForJoin.removeValue(forKey: joinObjectID)
        latestStateForJoin.removeValue(forKey: joinObjectID)
    }


    /// Turns what an attachment currently offers into where it stands, which is what a view needs in order to know whether to draw a picture, a control, or a
    /// control that is spinning.
    ///
    /// The one thing the join cannot say is that the reader has *just asked* for the file: the engine has not answered yet, so the join still reads
    /// `downloadable`. That is what ``attachmentsAskedFor`` remembers.
    private func state(of source: AttachmentImageSource, for joinObjectID: NSManagedObjectID, pixelSize: CGSize, sha256: Data) async -> AttachmentState {
        switch source {
        case .cancelledByServer:
            return .init(phase: .cancelledByServer, image: nil)
        case .leftBehindByAHistoryTransfer:
            return .init(phase: .leftBehindByAHistoryTransfer, image: nil)
        case .knownOnlyFromANotification:
            return .init(phase: .knownOnlyFromANotification, image: nil)
        case .notDownloaded(let downsizedThumbnail, let isDownloading):
            // The blurred stand-in says nothing about how far along the attachment is — it is what the control is drawn on, not a sign that the file is here.
            let image: CGImage? = if let downsizedThumbnail { await Self.decodedImage(from: downsizedThumbnail) } else { nil }
            return .init(phase: phaseOfAnAttachmentThatIsNotHereYet(joinObjectID: joinObjectID, isDownloading: isDownloading), image: image)
        case .file(let url, let isUploading):
            // **A presentation that asks for nothing is given nothing, at once.** A link preview and an audio player ask for `.zero`: what they want from this
            // stream is the *phase*, the moment the file is there, after which they go and read the file themselves. Without this guard both went on to
            // `pictureOfTheFile`, which for a kind that is not an image asks QuickLook first — a hardlink and an out-of-process render, of a picture nothing draws,
            // *before* the phase they were waiting for is yielded. That is seconds on a simulator, and it is what made a link preview appear long after its row.
            let maxPixelSize = Int(max(pixelSize.width, pixelSize.height))
            guard maxPixelSize > 0 else { return .init(phase: isUploading ? .uploading : .available, image: nil) }
            // Now, and only now, is the cache worth asking: the join has just said there is a file, so a picture of that file is the right thing to show. Asked
            // directly, the guard of `cachedImageForAttachment(_:pixelSize:)` being exactly the question this case has already answered.
            if let alreadyDecoded = Self.cachedImages.object(forKey: Self.cacheKey(sha256: sha256, pixelSize: pixelSize)) {
                // **The second key is refreshed here too, and not only where the decode happens.** It was written only below, on the decoding
                // path, so a picture served from this cache hit — a cell rebuilt, a row scrolled back, a second cell showing the same file —
                // left it as it was. Evicted once, it was then never written again, and a drag out of a message whose picture is on screen at
                // that very moment previewed itself with a file icon. `NSCache` gives entries up under memory pressure, and this one is
                // inserted at no cost, so nothing else keeps it. Writing it on both paths is what makes "whatever has been decoded for this
                // file" true rather than "whatever was decoded the first time".
                Self.cachedImages.setObject(alreadyDecoded, forKey: Self.cacheKeyForAnySize(sha256: sha256), cost: 0)
                return .init(phase: isUploading ? .uploading : .available, image: alreadyDecoded)
            }
            let image = await pictureOfTheFile(at: url, forJoinWith: joinObjectID, maxPixelSize: maxPixelSize)
            if let image {
                Self.cachedImages.setObject(image, forKey: Self.cacheKey(sha256: sha256, pixelSize: pixelSize), cost: image.bytesPerRow * image.height)
                // The same picture under a second key, meaning **whatever has most recently been decoded for this file, at any size**. It is what
                // a drag out of the discussion previews itself with: a drag has to answer at once, at a size nothing on this screen displays, so
                // an exact-size lookup can only miss. The image is not copied — both keys hold the one `CGImage`.
                //
                // **`cost: 0` is a decision, not an oversight**, taken on 2026-08-15. It does not cost a pointer: this entry retains a whole
                // decoded image, and at no cost it never counts against `totalCostLimit`, so these are bounded by memory pressure rather than by
                // the budget. Charging the real cost would make the accounting honest and make this entry likelier to be evicted — which is
                // exactly what puts a file icon under the reader's finger for a photograph they can see. The preview wins.
                Self.cachedImages.setObject(image, forKey: Self.cacheKeyForAnySize(sha256: sha256), cost: 0)
            }
            // The picture is the same whichever way the bytes are going; only the phase differs, and with it whether an arc is drawn over it.
            return .init(phase: isUploading ? .uploading : .available, image: image)
        }
    }


    // MARK: AudioPlaybackDataSource

    /// Follows the playing of one recording.
    ///
    /// The stream is opened for *any* recording being shown, whether or not it is the one playing, because what a view needs to know includes that it is **not**
    /// playing: there is a single `ObvAudioPlayer` for the whole app, so starting one recording silences another, and the view showing that other one has no way to
    /// learn it except by being told.
    func getAsyncStreamOfAudioPlaybackState(forAttachment attachment: MessageAttachment) async throws -> (streamUUID: UUID, stream: AsyncStream<AudioPlaybackState>) {
        guard case .objectID = attachment.identifier else { throw ObvError.attachmentIsNotPersisted }
        let streamUUID = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: AudioPlaybackState.self, bufferingPolicy: .bufferingNewest(1))
        playbackContinuationsForAttachment[attachment.identifier, default: [:]][streamUUID] = continuation
        streamUUIDsOfPlaybackByAttachment[streamUUID] = attachment.identifier
        continuation.yield(playbackState(of: attachment.identifier))
        return (streamUUID, stream)
    }


    func finishAsyncStreamOfAudioPlaybackState(streamUUID: UUID) async {
        guard let identifier = streamUUIDsOfPlaybackByAttachment.removeValue(forKey: streamUUID) else { return }
        playbackContinuationsForAttachment[identifier]?.removeValue(forKey: streamUUID)?.finish()
        if playbackContinuationsForAttachment[identifier]?.isEmpty ?? false {
            playbackContinuationsForAttachment.removeValue(forKey: identifier)
        }
    }


    /// The views following a recording, and which recording each of them follows.
    private var playbackContinuationsForAttachment = [MessageAttachment.Identifier: [UUID: AsyncStream<AudioPlaybackState>.Continuation]]()
    private var streamUUIDsOfPlaybackByAttachment = [UUID: MessageAttachment.Identifier]()

    /// The recording this screen last handed to the player, with the hardlink it handed over.
    ///
    /// **Replaced only when another recording is handed over, and never cleared by anything the player reports.** That is the whole discipline of this section, and
    /// twice now the want of it has made a recording play in silence: the player's callbacks say *that* something happened and never *to which recording*, and they
    /// arrive a hop late, so one about the recording just displaced lands after the new one has been recorded. Used to mutate remembered state, they wipe it. Used
    /// only to go and re-read the player, they cannot.
    private var recordingHandedToThePlayer: (identifier: MessageAttachment.Identifier, hardlink: HardLinkToFyle)?

    /// Where every recording stands, whether the player is holding it or not.
    ///
    /// **One place for a position.** The player is asked for everything else about the recording it holds — whether it is sounding, how fast, how long — but never
    /// for where it has got to, because that is wanted precisely when the player cannot answer: after a pause, after another recording has taken it, and after the
    /// player has been let go of altogether, which is what leaving the discussion does. A recording the reader has merely dragged has never been near the player
    /// and is remembered here for the same reason. Written by the player's own reports, by an ask to play, and by a drag.
    private var whereEachRecordingStands = [MessageAttachment.Identifier: WhereARecordingStands]()

    private struct WhereARecordingStands {
        let time: TimeInterval
        /// Nil while the length is unknown, an `AVPlayer` fallback having none to give until its item is ready.
        let duration: TimeInterval?
    }

    /// The order recordings were first heard of, oldest first, which is the order they are forgotten in.
    ///
    /// Only an arrival is written here: a recording being played says where it stands thirty times a second, and none of those may touch this.
    private var theOrderRecordingsWereFirstHeardOf: [MessageAttachment.Identifier] = []

    /// How many positions are kept. This data source lives in `ObvDataSources` for the life of the process, so an unbounded store would end up holding a position
    /// for every recording ever shown. Forgetting one costs nothing: the recording is drawn at its beginning, which is what it was drawn at before any of this was
    /// remembered.
    private static let howManyRecordingsAreRemembered = 100

    private func remember(_ stands: WhereARecordingStands, of identifier: MessageAttachment.Identifier) {
        guard whereEachRecordingStands.updateValue(stands, forKey: identifier) == nil else { return }
        theOrderRecordingsWereFirstHeardOf.append(identifier)
        guard theOrderRecordingsWereFirstHeardOf.count > Self.howManyRecordingsAreRemembered else { return }
        whereEachRecordingStands.removeValue(forKey: theOrderRecordingsWereFirstHeardOf.removeFirst())
    }

    /// The recording whose sender has been told it was listened to, so that the telling happens once per recording rather than thirty times a second.
    private var theRecordingWhoseListeningWasReported: MessageAttachment.Identifier?

    /// Whether this is the recording the player is holding, which is the only one that can be making a sound.
    private func playerIsHolding(_ identifier: MessageAttachment.Identifier) -> Bool {
        recordingHandedToThePlayer?.identifier == identifier && thePlayerIsStillOnOurRecording
    }

    /// Whether the player is still on the recording this screen gave it. The player itself is the authority, always.
    private var thePlayerIsStillOnOurRecording: Bool {
        guard let recordingHandedToThePlayer else { return false }
        return ObvAudioPlayer.shared.current == recordingHandedToThePlayer.hardlink
    }


    /// What to tell a view about a recording: its position remembered, everything else read from the player.
    ///
    /// The rate is told to every recording, playing or not, because it belongs to the player and not to any one of them — a reader who changes the speed expects to
    /// see it change on the recording they are looking at, whichever that is.
    private func playbackState(of identifier: MessageAttachment.Identifier) -> AudioPlaybackState {
        let rate = AudioPlaybackRate(rawValue: ObvAudioPlayer.shared.currentPlayRate.rawValue.doubleValue) ?? .ordinary
        // A recording nothing is remembered of has never been played nor dragged, so it stands at its beginning and its length is nobody's to give.
        guard let stands = whereEachRecordingStands[identifier] else { return .atRest(rate: rate) }
        let isHeld = playerIsHolding(identifier)
        return .init(isPlaying: isHeld && ObvAudioPlayer.shared.isPlaying,
                     currentTime: stands.time,
                     duration: (isHeld ? ObvAudioPlayer.shared.totalDuration : nil) ?? stands.duration,
                     rate: rate)
    }


    private func yieldPlaybackState(of identifier: MessageAttachment.Identifier) {
        guard let continuations = playbackContinuationsForAttachment[identifier] else { return }
        let state = playbackState(of: identifier)
        for continuation in continuations.values {
            continuation.yield(state)
        }
    }


    // MARK: SingleDiscussionCellViewActions, for a recording

    /// Starts or stops a recording, and tells whoever was listening to the one it displaces.
    ///
    /// Becoming the player's delegate *is* taking the player, that being how `ObvAudioPlayer` is built: a single slot, whose previous occupant is told it has lost
    /// the recording it had. So this screen claims it at the moment the reader asks to play, exactly as the legacy screen does, rather than holding it while it is
    /// merely on display.
    func userWantsToActOnAudioAttachment(_ attachment: MessageAttachment, action: AudioAction) async {
        switch action {
        case .pause:
            ObvAudioPlayer.shared.pause()
        case .standsAt(let fraction, let lengthAccordingToTheView):
            // The player's own length while it is holding the recording, a position being drawn as a fraction of the length reported beside it.
            let duration = (playerIsHolding(attachment.identifier) ? ObvAudioPlayer.shared.totalDuration : nil) ?? lengthAccordingToTheView
            remember(.init(time: min(duration, max(0, fraction * duration)), duration: duration), of: attachment.identifier)
            yieldPlaybackState(of: attachment.identifier)
        case .setRate(let rate):
            guard let playRate = ObvAudioPlayer.PlayRate(rawValue: NSNumber(value: rate.rawValue)) else { assertionFailure(); return }
            ObvAudioPlayer.shared.setRate(rate: playRate)
            // Told to every recording being shown, the rate being the player's rather than any one recording's.
            for identifier in playbackContinuationsForAttachment.keys {
                yieldPlaybackState(of: identifier)
            }
        case .play(let fromFraction):
            Self.theAskToPlayARecording.notice("🎵 Asked to play from \(fromFraction, privacy: .public)")
            // Asked for once, and both things taken from the one answer. Written as two guards, the second could not fail — nothing is awaited between them — so
            // the line reporting its refusal was one no run could ever print.
            guard let hardlink = await hardlink(for: attachment), let hardlinkURL = hardlink.hardlinkURL else {
                Self.theAskToPlayARecording.notice("🎵 Declined: there is no file to play")
                return
            }
            let identifierOfTheOneItDisplaces = recordingHandedToThePlayer?.identifier
            Self.theAskToPlayARecording.notice("🎵 The file is \(hardlinkURL.lastPathComponent, privacy: .private(mask: .hash))")

            // Where to start, in seconds. The length has to be read from the file rather than asked of the player, which knows only the recording it is holding —
            // and this may be one it has never held. `ObvAudioPlayer.duration(of:)` is what the legacy screen uses in the same place, for the same reason.
            let durationOfTheFile = try? await ObvAudioPlayer.duration(of: hardlinkURL)
            guard let duration = durationOfTheFile, duration > 0 else {
                Self.theAskToPlayARecording.notice("🎵 Declined: the length reads \(String(describing: durationOfTheFile), privacy: .public)")
                return
            }
            // At the very end, back to the beginning: `progress > 0.98` on the legacy screen. Without it, a reader who has just heard a recording out, or who has
            // dragged to its last moments, presses play and gets a fraction of a second.
            let fraction = fromFraction > Self.fractionBeyondWhichPlayingStartsOver ? 0 : fromFraction
            let time = min(duration, max(0, fraction * duration))

            if identifierOfTheOneItDisplaces == attachment.identifier, thePlayerIsStillOnOurRecording {
                // The same recording, still held by the player: it goes on from where the reader left it.
                remember(.init(time: time, duration: duration), of: attachment.identifier)
                Self.theAskToPlayARecording.notice("🎵 Resuming at \(time, privacy: .public) of \(duration, privacy: .public)")
                ObvAudioPlayer.shared.resume(at: time)
            } else {
                // Stopped first, as on the legacy screen, so that the recording being displaced is let go of properly rather than having its player replaced under it.
                // Harmless only because nothing the player reports is used to remember anything: the `audioPlayerDidStopPlaying` this provokes arrives *after* the
                // lines below and, in an earlier version of this code, undid them — a second recording then played in silence.
                ObvAudioPlayer.shared.stop()
                if ObvAudioPlayer.shared.delegate !== playbackObserver {
                    ObvAudioPlayer.shared.delegate = playbackObserver
                }
                let previous = recordingHandedToThePlayer
                recordingHandedToThePlayer = (identifier: attachment.identifier, hardlink: hardlink)
                guard ObvAudioPlayer.shared.play(hardlink, at: time) else {
                    Self.theAskToPlayARecording.notice("🎵 Declined: the player refused the file")
                    recordingHandedToThePlayer = previous
                    return
                }
                // Written once the player has taken it, so that a refusal leaves the recording where it was rather than where it was asked to go.
                remember(.init(time: time, duration: duration), of: attachment.identifier)
                Self.theAskToPlayARecording.notice("🎵 Playing from \(time, privacy: .public) of \(duration, privacy: .public)")
                if let identifierOfTheOneItDisplaces, identifierOfTheOneItDisplaces != attachment.identifier {
                    yieldPlaybackState(of: identifierOfTheOneItDisplaces)
                }
            }
            yieldPlaybackState(of: attachment.identifier)
        }
    }


    /// At this much of the way through, pressing play starts the recording again rather than continuing it. `0.98` on the legacy screen.
    private static let fractionBeyondWhichPlayingStartsOver = 0.98


    /// Says what became of every ask to play, including the three ways it can come to nothing. **Reports unconditionally**: each of those ways used to return in
    /// silence, and a refusal nobody can see is indistinguishable from a button whose action never ran at all.
    private static let theAskToPlayARecording = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "TheAskToPlayARecording")


    /// Says that the reader has listened to a *received* recording, which is what marks the attachment as opened — and, through `MarkAsOpenedOperation`, sends the
    /// read receipt its sender is waiting for. `NewSingleDiscussionViewController.audioHasBeenPlayed(_:)` does exactly this.
    ///
    /// Posted as a notification rather than carried up the delegate chain, and deliberately: this is a *report of something that has happened*, which is the shape
    /// `ObvMessengerInternalNotification` exists for and the shape the rest of the app uses for it. Requests still go through the delegate.
    /// Tells the sender their recording has been listened to, once, the first time it is heard.
    ///
    /// **Said from what the player reports rather than from the ask to play, because the two are not the same thing.** `ObvAudioPlayer.play(_:at:)` answers `true`
    /// for a file it has not read — an `AVPlayer` cannot say whether it will play until its item is ready — so a recording neither reader can decode would tell
    /// its sender it had been listened to, and then fail a moment later with the receipt already gone.
    ///
    /// The player is *asked* whether there is a sound rather than trusted to be making one: ``ObvAudioPlayer/resume(at:)`` reports a position before there is any,
    /// so a recording paused before its first report would otherwise slip through on the next press of play.
    private func theSenderIsToldTheRecordingWasListenedTo(_ identifier: MessageAttachment.Identifier) {
        guard theRecordingWhoseListeningWasReported != identifier else { return }
        guard ObvAudioPlayer.shared.isPlaying else { return }
        theRecordingWhoseListeningWasReported = identifier
        reportThatAReceivedRecordingWasOpened(identifier)
    }


    private func reportThatAReceivedRecordingWasOpened(_ identifier: MessageAttachment.Identifier) {
        guard case .objectID(let joinObjectID) = identifier else { return }
        guard let receivedJoin = try? viewContext.existingObject(with: joinObjectID) as? ReceivedFyleMessageJoinWithStatus else { return }
        ObvMessengerInternalNotification.userHasOpenedAReceivedAttachment(receivedFyleJoinID: receivedJoin.typedObjectID).postOnDispatchQueue()
    }


    /// A `Fyle` under the name it was sent with, which is the only form the player accepts.
    private func hardlink(for attachment: MessageAttachment) async -> HardLinkToFyle? {
        guard case .objectID(let joinObjectID) = attachment.identifier else { return nil }
        guard let join = try? viewContext.existingObject(with: joinObjectID) as? FyleMessageJoinWithStatus else { return nil }
        guard let fyleElement = join.fyleElement else { return nil }
        guard let delegate else { assertionFailure(); return nil }
        return try? await delegate.requestHardLinkToFyle(self, fyleElement: fyleElement)
    }


    // MARK: What the player reports

    /// **None of these remembers anything but a position, and only for the recording the player is known to be holding.** Each says only that the player has moved,
    /// and the answer to *what it is doing now* is read back from the player when the state is next composed. That is what makes them safe to arrive late, and out
    /// of order, and about a recording that has since been displaced.
    ///
    /// It is also how the legacy screen works, one coordinator per cell asking `hardlink == audioPlayer.current` in every callback. Departing from it cost two
    /// separate bugs in which a recording played while its view showed nothing at all.
    fileprivate func playerIsPlaying(currentTime: TimeInterval) {
        guard let identifier = recordingHandedToThePlayer?.identifier, thePlayerIsStillOnOurRecording else { return }
        remember(.init(time: currentTime, duration: ObvAudioPlayer.shared.totalDuration ?? whereEachRecordingStands[identifier]?.duration), of: identifier)
        theSenderIsToldTheRecordingWasListenedTo(identifier)
        yieldToTheRecordingHandedOver()
    }


    /// Paused. The position is kept, so pressing play carries on from it.
    fileprivate func playerPaused() {
        yieldToTheRecordingHandedOver()
    }


    /// Reached the end. Back to the beginning, so that pressing play again plays the recording rather than doing nothing.
    fileprivate func playerFinished() {
        guard let identifier = recordingHandedToThePlayer?.identifier, thePlayerIsStillOnOurRecording else { return }
        remember(.init(time: 0, duration: ObvAudioPlayer.shared.totalDuration ?? whereEachRecordingStands[identifier]?.duration), of: identifier)
        yieldToTheRecordingHandedOver()
    }


    /// Stopped outright, which is what leaving the discussion does. Nothing to write: where the recording stands is already remembered, and outlives the player
    /// letting go of it — a reader who comes back to the discussion finds it where they left it.
    fileprivate func playerStopped() {
        yieldToTheRecordingHandedOver()
    }


    /// Something else has taken the player — the legacy screen, or another recording on this one. Again nothing to write, for the same reason.
    fileprivate func playerWasTakenAway() {
        yieldToTheRecordingHandedOver()
    }


    private func yieldToTheRecordingHandedOver() {
        guard let identifier = recordingHandedToThePlayer?.identifier else { return }
        yieldPlaybackState(of: identifier)
    }


    /// Stands between the player and this data source.
    ///
    /// A class of its own because `ObvAudioPlayerDelegate` is called from a `Timer` and is not main-actor bound, while everything here is. It does nothing but hop.
    private lazy var playbackObserver = AudioPlaybackObserver(dataSource: self)


    // MARK: The shape of a recording

    /// The shape of a recording, measured once and remembered.
    ///
    /// Read through a **hardlink**, for the reason the thumbnails are: `AVURLAsset` decides what it has been given from the name, and a `Fyle` is stored under the
    /// hexadecimal of its own hash.
    ///
    /// Nil while the file is not here, which the view draws as a flat line — the space is reserved either way, so nothing moves when the answer arrives.
    func recordingForAudioAttachment(_ attachment: MessageAttachment, numberOfSamples: Int) async -> AudioRecording? {
        guard case .objectID(let joinObjectID) = attachment.identifier else { return nil }
        if let remembered = Self.cachedRecordings.object(forKey: Self.cacheKeyForWaveform(sha256: attachment.sha256, numberOfSamples: numberOfSamples)) {
            return remembered.recording
        }
        guard let join = try? viewContext.existingObject(with: joinObjectID) as? FyleMessageJoinWithStatus else { return nil }
        guard let fyle = join.fyle, fyle.getFileSize() != nil else { return nil }
        guard let delegate else { assertionFailure(); return nil }
        guard let fyleElement = join.fyleElement else { return nil }
        guard let hardlink = try? await delegate.requestHardLinkToFyle(self, fyleElement: fyleElement) else { return nil }
        guard let hardlinkURL = hardlink.hardlinkURL else { return nil }
        guard let recording = await Self.recording(at: hardlinkURL, numberOfSamples: numberOfSamples) else { return nil }
        Self.cachedRecordings.setObject(CachedRecording(recording), forKey: Self.cacheKeyForWaveform(sha256: attachment.sha256, numberOfSamples: numberOfSamples))
        return recording
    }


    /// The file an attachment is, for a drag out of the discussion.
    ///
    /// **A hardlink, which is what the whole screen hands to anything outside it**: the viewer of Step 13 opens one, the Share action gives them away, the audio
    /// above is read through one. A `Fyle` is stored under the hexadecimal of its own hash, so the hardlink is also what gives the file back its name and extension —
    /// which is what the application receiving a drop reads to know what it has been given.
    ///
    /// Resolved when the drop is accepted rather than when the drag begins, which is `TheFileOfAnAttachment`'s doing, so this is never asked for a drag that goes
    /// nowhere.
    func getTheFileOfAnAttachment(_ attachment: MessageAttachment) async throws -> URL {
        guard case .objectID(let joinObjectID) = attachment.identifier else { throw ObvError.couldNotDetermineAttachmentIdentifier }
        guard let join = try? viewContext.existingObject(with: joinObjectID) as? FyleMessageJoinWithStatus else { throw ObvError.attachmentIsNotPersisted }
        guard let fyleElement = join.fyleElement else { throw ObvError.theAttachmentHasNoFileToGive }
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        let hardlink = try await delegate.requestHardLinkToFyle(self, fyleElement: fyleElement)
        guard let hardlinkURL = hardlink.hardlinkURL else { throw ObvError.theAttachmentHasNoFileToGive }
        return hardlinkURL
    }


    /// Keyed on the file and on how many bars were asked for, since a different number is a different measurement. Counted rather than sized: a few hundred floats
    /// apiece, where the image cache next door holds megabytes.
    /// **`nonisolated(unsafe)` because `NSCache` is thread-safe and does not say so in a way the compiler can read.** Apple's guarantee is explicit — items may be
    /// added, removed and queried from several threads without locking it yourself — and there is no conditional conformance to lean on instead: the cache stays
    /// non-`Sendable` even when its key and its value are both `Sendable`, which was tried first. So this is the one place the fact has to be asserted, and the
    /// assertion is Apple's rather than ours.
    nonisolated(unsafe) private static let cachedRecordings: NSCache<NSString, CachedRecording> = {
        let cache = NSCache<NSString, CachedRecording>()
        cache.countLimit = 256
        return cache
    }()


    nonisolated private static func cacheKeyForWaveform(sha256: Data, numberOfSamples: Int) -> NSString {
        "\(sha256.base64EncodedString())-\(numberOfSamples)" as NSString
    }


    /// `NSCache` holds objects, and a struct is not one.
    ///
    /// **`Sendable` because the box itself travels**, not because it unlocks anything above — an `NSCache` is not `Sendable` whatever it holds, which was measured
    /// rather than assumed. What this buys is the values: they are handed out of the cache to callers in other isolation domains, and this conformance is checked by
    /// the compiler rather than promised. Give this class a `var`, or a property that is not `Sendable`, and it stops compiling here rather than going wrong
    /// somewhere else.
    private final class CachedRecording: Sendable {
        let recording: AudioRecording
        init(_ recording: AudioRecording) { self.recording = recording }
    }


    /// How loud the recording is at each of `numberOfSamples` moments, between 0 and 1.
    ///
    /// **The peak of each stretch, not its average.** Taken from `ComposeAudioPlayerView.extractWaveformSamples(from:count:)`, and deliberately *not* from
    /// `AudioWaveFormView`'s version on the legacy discussion screen, which does two things that make a poor waveform:
    ///
    /// - it takes the **root mean square** of each stretch, and a mean of speech sits in a narrow band — normalised, nearly every bar then comes out the same
    ///   height, which is a picture of nothing;
    /// - it reads **half a second** at intervals of `duration / numberOfSamples`, so anything longer than 17.5s is measured with gaps between the windows and
    ///   anything shorter is measured twice over. It samples the recording rather than measuring it.
    ///
    /// The file is read **once**, by one reader, and every frame contributes to the bar whose stretch it falls in. Bar boundaries are computed by proportion rather
    /// than from a chunk size, so the last bar reaches the end of the recording instead of stopping short of it.
    ///
    /// `nonisolated` **and** `async`, so that it runs on the cooperative pool rather than on the main actor, while still belonging to the calling task tree — a row
    /// scrolled away cancels its own measurement.
    nonisolated private static func recording(at url: URL, numberOfSamples: Int) async -> AudioRecording? {

        guard !Task.isCancelled else { return nil }
        guard numberOfSamples > 0 else { return nil }

        let asset = AVURLAsset(url: url)
        guard let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first else { return nil }
        // Taken from the same asset as the shape, which is the whole reason the two are answered together: a reader dragging along a recording that has never been
        // played needs its length in order to be shown a time, and nothing else on this screen knows it.
        guard let duration = try? await asset.load(.duration), duration.seconds > 0 else { return nil }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ]

        guard let assetReader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        assetReader.add(output)
        guard assetReader.startReading() else { return nil }
        defer { assetReader.cancelReading() }

        // How far the loudest frame of the recording so far departs from silence, one entry per frame. A recording of any length a reader would send fits in memory
        // as floats; a minute at 44.1kHz is under a megabyte.
        var magnitudes = [Float]()

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard !Task.isCancelled else { return nil }
            defer { CMSampleBufferInvalidate(sampleBuffer) }
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let numberOfBytes = CMBlockBufferGetDataLength(blockBuffer)
            guard numberOfBytes % MemoryLayout<Float>.size == 0 else { continue }
            var frames = [Float](repeating: 0, count: numberOfBytes / MemoryLayout<Float>.size)
            let copied = frames.withUnsafeMutableBytes { bytes -> Bool in
                guard let baseAddress = bytes.baseAddress else { return false }
                return CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: numberOfBytes, destination: baseAddress) == kCMBlockBufferNoErr
            }
            guard copied else { continue }
            // Interleaved channels are treated as one stream, which costs nothing here: a peak is a peak whichever channel it came from.
            magnitudes.append(contentsOf: frames.lazy.map({ abs($0) }))
        }

        guard !magnitudes.isEmpty else { return nil }

        var peaks = [Float]()
        peaks.reserveCapacity(numberOfSamples)
        for index in 0..<numberOfSamples {
            let start = magnitudes.count * index / numberOfSamples
            let end = magnitudes.count * (index + 1) / numberOfSamples
            peaks.append(start < end ? (magnitudes[start..<end].max() ?? 0) : 0)
        }

        guard let loudest = peaks.max(), loudest > 0 else { return nil }
        return .init(samples: peaks.map({ $0 / loudest }), duration: duration.seconds)

    }


    // MARK: AnimatedImageDataSource

    /// The frames of an animated attachment, paced as its file asks — see ``AnimatedImageFrames``, which does the whole of the work.
    ///
    /// All that happens here is finding the file, and the two guards that finding it involves are the ones every other picture on this screen goes through: the
    /// **join decides** whether there is a file, and the file is read through its `Fyle`, whose name says nothing about what it is — hence the UTI, handed on as a
    /// hint. Nothing is cached at this level, the frames of an animation being a sequence rather than an answer; what bounds the memory is the producer.
    ///
    /// An attachment whose bytes are not here yields nothing and finishes at once. The view then keeps showing the still picture it already had, and asks again when
    /// the phase says the file has arrived.
    func getAsyncStreamOfFramesForAnimatedImage(_ attachment: MessageAttachment, maxPixelSize: Int) -> AsyncStream<CGImage> {
        guard case .objectID(let joinObjectID) = attachment.identifier,
              let join = try? viewContext.existingObject(with: joinObjectID) as? FyleMessageJoinWithStatus,
              let fyle = join.fyle,
              fyle.fileExistsOnDisk else {
            return AsyncStream { $0.finish() }
        }
        return AnimatedImageFrames.stream(fileURL: fyle.url, uti: join.uti, maxPixelSize: maxPixelSize)
    }


    // MARK: LinkPreviewDataSource

    /// What the link preview of a message says, read from whatever holds it.
    ///
    /// **The two routes end in the same place**, a file holding an `ObvEncoded` `ObvLinkMetadata`: one is the fyle of an attachment the sender sent, the other a file
    /// this device fetched and keeps under the hash of the URL. So only *finding* the file differs, and it is the one thing this method does before handing over to a
    /// single reader.
    ///
    /// The guard on the join comes **before** the cache, as it does for images and for the same reason: the cache is keyed on the file and outlives the messages that
    /// brought it, so answering from it alone would show a reader a preview of an attachment that is no longer on the device.
    func linkPreviewMetadata(for source: LinkPreviewInMessage, maxPixelSize: Int) async -> LinkPreviewMetadata? {
        switch source {
        case .attached(let attachment, _):
            guard case .objectID(let joinObjectID) = attachment.identifier else { return nil }
            guard let join = try? viewContext.existingObject(with: joinObjectID) as? FyleMessageJoinWithStatus else { return nil }
            guard let fyle = join.fyle, fyle.getFileSize() != nil else { return nil }
            let key = Self.cacheKeyForLinkPreview(of: attachment.sha256.base64EncodedString(), maxPixelSize: maxPixelSize)
            if let remembered = Self.cachedLinkPreviews.object(forKey: key) { return remembered.metadata }
            // The name a preview is attached under *is* the URL it renders, which is what `ObvLinkMetadata.decode` wants as its fallback: a sender whose encoded
            // metadata carries no URL still leaves us one.
            let metadata = await Self.linkPreviewMetadata(readFrom: fyle.url, fallbackURL: URL(string: join.fileName), maxPixelSize: maxPixelSize)
            if let metadata { Self.cachedLinkPreviews.setObject(CachedLinkPreview(metadata), forKey: key) }
            return metadata
        case .toBeFetched(let url):
            let key = Self.cacheKeyForLinkPreview(of: url.absoluteString, maxPixelSize: maxPixelSize)
            if let remembered = Self.cachedLinkPreviews.object(forKey: key) { return remembered.metadata }
            guard let delegate else { assertionFailure(); return nil }
            guard let fileURL = try? await delegate.requestFileHoldingLinkPreviewMetadata(self, ofLink: url) else { return nil }
            let metadata = await Self.linkPreviewMetadata(readFrom: fileURL, fallbackURL: url, maxPixelSize: maxPixelSize)
            if let metadata { Self.cachedLinkPreviews.setObject(CachedLinkPreview(metadata), forKey: key) }
            return metadata
        }
    }


    /// Every link preview read for this screen. Counted rather than weighed: a preview's picture is bounded by the width of the card it is drawn on, so a hundred of
    /// them is a few megabytes — where the cache of attachment images next door holds photographs.
    nonisolated(unsafe) private static let cachedLinkPreviews: NSCache<NSString, CachedLinkPreview> = {
        let cache = NSCache<NSString, CachedLinkPreview>()
        cache.countLimit = 128
        return cache
    }()


    nonisolated private static func cacheKeyForLinkPreview(of source: String, maxPixelSize: Int) -> NSString {
        "\(source)-\(maxPixelSize)" as NSString
    }


    /// `NSCache` holds objects, and a struct is not one.
    private final class CachedLinkPreview {
        let metadata: LinkPreviewMetadata
        init(_ metadata: LinkPreviewMetadata) { self.metadata = metadata }
    }


    /// Reads a file holding an encoded ``ObvLinkMetadata`` and turns it into what the view draws.
    ///
    /// `nonisolated` **and** `async`, as the decoders are, so that the read and the decode happen on the cooperative pool while still belonging to the calling task
    /// tree: a row scrolled away cancels its own work.
    nonisolated private static func linkPreviewMetadata(readFrom fileURL: URL, fallbackURL: URL?, maxPixelSize: Int) async -> LinkPreviewMetadata? {
        guard !Task.isCancelled else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let obvEncoded = ObvEncoded(withRawData: data) else { return nil }
        guard let decoded = ObvLinkMetadata.decode(obvEncoded, fallbackURL: fallbackURL) else { return nil }
        let image = await linkPreviewImage(from: decoded.pngData, maxPixelSize: maxPixelSize)
        let domain = domain(of: decoded.url)
        return .init(title: nilIfEmpty(decoded.title),
                     desc: nilIfEmpty(decoded.desc),
                     domain: nilIfEmpty(domain),
                     url: webURL(of: decoded.url),
                     image: image,
                     showsTheWholeDescription: showsTheWholeDescription(forDomain: domain))
    }


    nonisolated private static func nilIfEmpty(_ string: String?) -> String? {
        guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }


    /// The host of a preview's URL, without a leading `www.` — all the legacy screen shows of it. In one place, so that the shape read while a model is built and the
    /// metadata read afterwards cannot disagree about what a domain is.
    nonisolated private static func domain(of url: URL?) -> String? {
        url?.toHttpsURL?.host?.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
    }


    /// Where a preview's card may take the reader, which is nil unless that is somewhere the app is willing to go.
    ///
    /// **The URL of an attached preview is whatever the sender encoded into the file.** `ObvLinkMetadata.decode` builds it with a bare `URL(_:)`, and nothing
    /// between the attachment arriving and the model being built compares it against the link the message body actually carries — so it may name any host, under
    /// any scheme. `toHttpsURL` is the app's existing answer to that question: it upgrades `http`, passes `https`, `tel` and `calshow`, and returns nil for
    /// everything else. It is the same test `UIApplication.userSelectedURL(_:within:)` applies at the moment of opening, asked one step earlier so that a card
    /// whose URL would be refused there carries no URL at all and is simply not tappable.
    ///
    /// **Belt to the braces of `LinkPreviewView`, which routes its tap through that same sanitiser** — the point of doing it here as well is that the model can no
    /// longer hand the UI layer something it must remember not to open.
    ///
    /// The card is still *drawn*, with whatever title and picture the sender chose, and only its tap is gone. That is deliberate and is what the legacy screen
    /// does: it shows the card and its tap reaches `userSelectedURL`, which refuses and returns. Suppressing the card outright would say more about the sender's
    /// intent than the legacy screen does and would be a divergence in a step whose purpose is transcription.
    ///
    /// This adds no new reachability for `toHttpsURL`'s `assertionFailure` on an unknown scheme: ``domain(of:)`` above already puts the same sender-supplied URL
    /// through the same function, on both of these paths, and has since the shape was introduced.
    nonisolated private static func webURL(of url: URL?) -> URL? {
        url?.toHttpsURL
    }


    /// Whether a domain is one of the handful whose preview *is* the text of a post, and whose description is therefore not clamped.
    nonisolated private static func showsTheWholeDescription(forDomain domain: String?) -> Bool {
        domain.map({ ObvMessengerConstants.LinkPreview.domainsWithLongDescription.contains($0) }) ?? false
    }


    // MARK: The shape of a link preview

    /// What an attached preview's card measures, read while the message's model is built — and nil while the file holding it has not arrived, which is the one case
    /// where the card cannot be anything but a spinner in a 280×140 box.
    ///
    /// **This is the same read as ``linkPreviewMetadata(readFrom:fallbackURL:maxPixelSize:)`` minus its expensive half.** The file is read, the `ObvEncoded` parsed
    /// and the `ObvLinkMetadata` decoded — all synchronous, which is what lets this happen on the model-building path at all — and the picture is *measured* rather
    /// than decoded: `CGImageSourceCopyPropertiesAtIndex` answers its dimensions from the header, exactly as the decision between an icon and a picture already
    /// relies on. Nothing is rasterised here, and the two pictures still arrive through the request the view makes.
    ///
    /// Cached by sha256 alone, unlike the metadata beside it, which is keyed by the size it was decoded at as well: what this holds is a handful of strings and a
    /// ratio, none of which depends on a size, and a preview being a file it can never need invalidating.
    nonisolated private static func shapeOfLinkPreview(of join: FyleMessageJoinWithStatus) -> LinkPreviewShape? {

        guard let fyle = join.fyle else { return nil }

        let cacheKey = fyle.sha256.base64EncodedString() as NSString
        if let remembered = cachedLinkPreviewShapes.object(forKey: cacheKey) {
            return remembered.shape
        }

        guard fyle.fileExistsOnDisk else { return nil }

        // The name a preview is attached under *is* the URL it renders, which is what `ObvLinkMetadata.decode` wants as its fallback.
        guard let data = try? Data(contentsOf: fyle.url, options: .mappedIfSafe) else { return nil }
        guard let obvEncoded = ObvEncoded(withRawData: data) else { return nil }
        guard let decoded = ObvLinkMetadata.decode(obvEncoded, fallbackURL: URL(string: join.fileName)) else { return nil }

        let domain = domain(of: decoded.url)
        let shape = LinkPreviewShape(title: nilIfEmpty(decoded.title),
                                     desc: nilIfEmpty(decoded.desc),
                                     domain: nilIfEmpty(domain),
                                     url: webURL(of: decoded.url),
                                     showsTheWholeDescription: showsTheWholeDescription(forDomain: domain),
                                     picture: pictureOfLinkPreview(from: decoded.pngData))

        cachedLinkPreviewShapes.setObject(CachedLinkPreviewShape(shape), forKey: cacheKey)
        return shape

    }


    /// The space a preview's picture will take, measured from its header and never decoded.
    ///
    /// The rule telling an icon from a picture is `LinkPreviewImage`'s own and is applied to the same numbers: under
    /// ``smallestSideOfAPictureShownWhole`` in *both* dimensions it is a logo drawn 40×40 beside the title, and anything larger is the picture at the top of the
    /// card. Reading it here rather than inferring it later is what lets the row be the right height before any picture exists.
    nonisolated private static func pictureOfLinkPreview(from pngData: Data?) -> LinkPreviewShape.Picture {
        guard let pngData else { return .none }
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil) else { return .none }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int,
              pixelWidth > 0, pixelHeight > 0 else { return .none }
        let isALogoRatherThanAPicture = pixelWidth < smallestSideOfAPictureShownWhole && pixelHeight < smallestSideOfAPictureShownWhole
        if isALogoRatherThanAPicture {
            return .icon
        } else {
            return .large(aspectRatio: CGFloat(pixelWidth) / CGFloat(pixelHeight))
        }
    }


    /// Keyed on the file alone: a preview is a file, and a file does not change. Counted, and generously — what one holds is a few strings and a ratio.
    nonisolated(unsafe) private static let cachedLinkPreviewShapes: NSCache<NSString, CachedLinkPreviewShape> = {
        let cache = NSCache<NSString, CachedLinkPreviewShape>()
        cache.countLimit = 512
        return cache
    }()


    /// `NSCache` holds objects, and a struct is not one.
    private final class CachedLinkPreviewShape {
        let shape: LinkPreviewShape
        init(_ shape: LinkPreviewShape) { self.shape = shape }
    }


    /// The picture a preview carries, decoded, and told apart into the two things the legacy screen does with one.
    ///
    /// **The size of the original decides, so it is read before anything is decoded.** Under 400px in *both* dimensions and it is a logo, drawn 40×40 beside the
    /// title; anything larger is the picture at the top of the card, drawn its full width. `CGImageSourceCopyPropertiesAtIndex` answers that from the file's header,
    /// so the choice costs no decode — and it has to be made from the original, downsampling being what would destroy the evidence.
    ///
    /// An icon is decoded at the same bound as a large picture, which over-serves it by a little and is not worth a second number: by the very definition that makes
    /// it an icon it is under 400px, and a thumbnail request never scales anything up.
    nonisolated private static func linkPreviewImage(from pngData: Data?, maxPixelSize: Int) async -> LinkPreviewImage {
        guard !Task.isCancelled else { return .none }
        guard maxPixelSize > 0, let pngData else { return .none }
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil) else { return .none }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int,
              pixelWidth > 0, pixelHeight > 0 else { return .none }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return .none }
        let isALogoRatherThanAPicture = pixelWidth < Self.smallestSideOfAPictureShownWhole && pixelHeight < Self.smallestSideOfAPictureShownWhole
        if isALogoRatherThanAPicture {
            return .icon(image)
        } else {
            return .large(image, aspectRatio: CGFloat(pixelWidth) / CGFloat(pixelHeight))
        }
    }


    /// `SinglePreviewView.thresholdForIconSize`, in pixels: below it in both dimensions, a preview's image is the site's logo rather than a picture of the page.
    nonisolated private static let smallestSideOfAPictureShownWhole = 400


    // MARK: PollDataSource

    /// Follows one poll: what it asks, what has been answered, and by how many.
    ///
    /// **Two controllers, and the second is the one that matters**: the poll, for its question, its kind and its expiry, and its *candidates*, whose `votes`
    /// relationship is what changes when anyone votes. Watching the message instead would see nothing at all — a vote writes `PersistedPollVote` objects and touches
    /// neither the message nor the poll — which is why the legacy screen has to fault the message in the view context after every vote, a nudge this screen never
    /// receives.
    ///
    /// That a candidate is reported as updated when one of its votes changes is not an assumption: it is what makes `PollViewDataSource`, and so the poll screen,
    /// work today.
    func getAsyncStreamOfPollState(forPollWith identifier: PollInMessage.Identifier) -> AsyncStream<MessagePollViewModel> {
        AsyncStream { continuation in
            guard case .objectID(let pollObjectID) = identifier else {
                continuation.finish()
                return
            }
            let manager = PollStateStreamManager(pollObjectID: .init(objectID: pollObjectID), context: backgroundContext)
            let task = Task {
                do {
                    let (_, states) = try await manager.startStream()
                    for await state in states {
                        continuation.yield(state)
                    }
                } catch {
                    assertionFailure()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
                manager.finishStream()
            }
        }
    }


    // MARK: ObvAvatarViewDataSource

    /// Forwarded, never answered here: a photo cache is an app-wide thing, and the discussion screen having one of its own would decode the same pictures a second
    /// time. `ObvAvatarViewAppDataSource` is the one the whole app uses, and `ObvDataSources` hands it over at init.
    func fetchAvatar(_ view: ObvAvatarView, photoURL: URL, avatarSize: ObvAvatarSize) async throws -> UIImage? {
        guard let avatarViewDataSource else { assertionFailure(); return nil }
        return try await avatarViewDataSource.fetchAvatar(view, photoURL: photoURL, avatarSize: avatarSize)
    }


    func fetchAvatarFromCache(_ view: ObvAvatarView, photoURL: URL, avatarSize: ObvAvatarSize) -> UIImage? {
        guard let avatarViewDataSource else { assertionFailure(); return nil }
        return avatarViewDataSource.fetchAvatarFromCache(view, photoURL: photoURL, avatarSize: avatarSize)
    }


    // MARK: LocationDataSource

    /// Follows one place: where it is, what it is called, and when its sharing runs out.
    ///
    /// **It watches the location and not the message**, which is the whole reason this stream exists — see
    /// `PersistedLocation.getFetchedResultsController(objectID:within:)`. One controller per place being shown, which is at most one per visible cell.
    ///
    /// A location that is deleted — the end of sharing — makes the controller yield nothing, and the state then carries no coordinate. That is reported rather than
    /// the stream being finished: a bubble already showing a map has to be told to stop.
    func getAsyncStreamOfLocationState(forLocationWith identifier: LocationInMessage.Identifier) -> AsyncStream<LocationState> {
        AsyncStream { continuation in
            guard case .objectID(let locationObjectID) = identifier else {
                continuation.finish()
                return
            }
            let manager = LocationStateStreamManager(locationObjectID: locationObjectID, context: backgroundContext)
            let task = Task {
                do {
                    let (_, states) = try await manager.startStream()
                    for await state in states {
                        continuation.yield(state)
                    }
                } catch {
                    assertionFailure()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
                manager.finishStream()
            }
        }
    }

    /// A still picture of the map around a place.
    ///
    /// Remembered, because rasterising a map is the most expensive picture this screen asks for — it may fetch tiles from the network — and because the answer for
    /// a given place, size and appearance never changes.
    func mapSnapshot(centeredOn coordinate: LocationCoordinate, pointSize: CGSize, displayScale: CGFloat, appearance: MapAppearance) async -> CGImage? {
        guard pointSize.width > 0, pointSize.height > 0, displayScale > 0 else { return nil }
        let key = Self.cacheKeyForMapSnapshot(coordinate: coordinate, pointSize: pointSize, displayScale: displayScale, appearance: appearance)
        if let remembered = Self.cachedMapSnapshots.object(forKey: key) { return remembered }
        guard let picture = await Self.rasterisedMapSnapshot(centeredOn: coordinate, pointSize: pointSize, displayScale: displayScale, appearance: appearance) else { return nil }
        Self.cachedMapSnapshots.setObject(picture, forKey: key, cost: picture.bytesPerRow * picture.height)
        return picture
    }


    /// Every map rasterised for this screen, weighed as the cache of attachment images is: a 200pt square at three times the scale is some 1.4MB, so a discussion
    /// full of places is a handful of them.
    nonisolated(unsafe) private static let cachedMapSnapshots: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()


    nonisolated private static func cacheKeyForMapSnapshot(coordinate: LocationCoordinate, pointSize: CGSize, displayScale: CGFloat, appearance: MapAppearance) -> NSString {
        // Quantised again here, though the caller is expected to have done it: a cache that answers only to coordinates rounded exactly as one view happens to round
        // them is a cache waiting to miss.
        let place = coordinate.quantisedToAboutAMetre
        return "\(place.latitude),\(place.longitude)-\(pointSize.width)x\(pointSize.height)@\(displayScale)-\(appearance)" as NSString
    }


    /// Rasterises the region the legacy screen shows, off the main actor.
    ///
    /// `MKCoordinateSpan` of **0.002°** in both directions, as `LocationView.refresh()` sets on its `MKMapView` — about 220m across, which at 200pt makes a point a
    /// little over a metre.
    ///
    /// The appearance travels as a `UITraitCollection`, which is how `MKMapSnapshotter` is told which tiles to draw: the light and the dark map are different
    /// pictures, and a snapshot cannot be recoloured afterwards.
    nonisolated private static func rasterisedMapSnapshot(centeredOn coordinate: LocationCoordinate, pointSize: CGSize, displayScale: CGFloat, appearance: MapAppearance) async -> CGImage? {

        guard !Task.isCancelled else { return nil }

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
                                            span: MKCoordinateSpan(latitudeDelta: Self.spanOfTheMapShown, longitudeDelta: Self.spanOfTheMapShown))
        options.size = pointSize
        options.scale = displayScale
        options.traitCollection = UITraitCollection(userInterfaceStyle: appearance == .dark ? .dark : .light)

        let snapshotter = SnapshotterHeldAcrossACancellation(MKMapSnapshotter(options: options))

        // **Cancelled means cancelled, tiles included.** A sender who moves leaves a render behind on every step, and rasterising a map may go to the network for
        // its tiles — so a task that is no longer wanted stops the work rather than merely discarding its answer.
        //
        // The `CGImage` is taken *inside* the completion handler and it alone crosses back: what the snapshotter hands over is a `UIImage`, which is not `Sendable`
        // and has no business leaving the queue it was made on.
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<CGImage?, Never>) in
                snapshotter.snapshotter.start(with: DispatchQueue.global(qos: .userInitiated)) { snapshot, _ in
                    continuation.resume(returning: snapshot?.image.cgImage)
                }
            }
        } onCancel: {
            snapshotter.snapshotter.cancel()
        }

    }


    /// Carries an `MKMapSnapshotter` into a cancellation handler, which must be `@Sendable` where the snapshotter is not.
    ///
    /// Unchecked, and safe as used: the two things done to it — starting it once, and cancelling it — are what `MKMapSnapshotter` exists to be asked from wherever
    /// the request was made.
    private final class SnapshotterHeldAcrossACancellation: @unchecked Sendable {
        let snapshotter: MKMapSnapshotter
        init(_ snapshotter: MKMapSnapshotter) { self.snapshotter = snapshotter }
    }


    /// `LocationView`'s own zoom: the value it passes as both deltas of its `MKCoordinateSpan`.
    nonisolated private static let spanOfTheMapShown = 0.002


    /// A picture of the file, by whichever of the two renderers suits it, falling back to the other.
    ///
    /// **The order matters, and it is decided by what the file is.** ImageIO is a decoder of *images*, and the right thing for one: fast, in this process, and
    /// exact. It will also rasterise a PDF, which is why documents appeared to work — but the page it produces is visibly softer than the same page rendered by
    /// QuickLook, which is what the legacy screen shows and what a reader compares us against. So a document is rendered by QuickLook first, and an image decoded
    /// by ImageIO first.
    ///
    /// Each still falls back to the other, so an attachment of a kind nobody foresaw gets a picture rather than nothing.
    private func pictureOfTheFile(at url: URL, forJoinWith joinObjectID: NSManagedObjectID, maxPixelSize: Int) async -> CGImage? {
        guard let join = try? viewContext.existingObject(with: joinObjectID) as? FyleMessageJoinWithStatus else {
            return await Self.imageDecodedByImageIO(at: url, maxPixelSize: maxPixelSize)
        }
        if join.isImageType {
            if let decoded = await Self.imageDecodedByImageIO(at: url, maxPixelSize: maxPixelSize) { return decoded }
            return await thumbnailFromQuickLook(forJoin: join, maxPixelSize: maxPixelSize)
        } else {
            if let rendered = await thumbnailFromQuickLook(forJoin: join, maxPixelSize: maxPixelSize) { return rendered }
            return await Self.imageDecodedByImageIO(at: url, maxPixelSize: maxPixelSize)
        }
    }


    /// A picture of an attachment as QuickLook renders it, by way of a hardlink.
    ///
    /// Here rather than among the `nonisolated` helpers below because the hardlink is asked of the delegate, which is `@MainActor`.
    private func thumbnailFromQuickLook(forJoin join: FyleMessageJoinWithStatus, maxPixelSize: Int) async -> CGImage? {
        guard let delegate else { assertionFailure(); return nil }
        guard let fyleElement = join.fyleElement else { return nil }
        guard let hardlink = try? await delegate.requestHardLinkToFyle(self, fyleElement: fyleElement) else { return nil }
        guard let hardlinkURL = hardlink.hardlinkURL else { return nil }
        return await Self.thumbnailFromQuickLook(at: hardlinkURL, maxPixelSize: maxPixelSize)
    }


    /// Whether an attachment whose file is not here is moving, has just been asked for, or is waiting to be.
    ///
    /// The join cannot say that the reader has *just* asked: the engine has not answered yet, so it still reads `downloadable`. That is the one thing
    /// ``attachmentsAskedFor`` remembers, and the reason the control can acknowledge a tap at once rather than after a round trip.
    private func phaseOfAnAttachmentThatIsNotHereYet(joinObjectID: NSManagedObjectID, isDownloading: Bool) -> AttachmentState.Phase {
        if isDownloading { return .downloading }
        return attachmentsAskedFor.contains(joinObjectID) ? .askedToDownload : .downloadable
    }


    /// The attachments the reader has asked for and the engine has not yet begun.
    ///
    /// Held here and not in a view: a row scrolled out of the list and back is built afresh, and a reader who tapped and scrolled away must not come back to a
    /// control that has forgotten them.
    private var attachmentsAskedFor = Set<NSManagedObjectID>()


    /// The views currently showing an attachment, so that a tap can be answered *now*.
    ///
    /// The continuations themselves, and not the stream managers that feed them. A manager reports what Core Data says, and Core Data says nothing when the
    /// reader taps: the request is ours until the engine acts on it. So the new phase has to be pushed from here, or the control would go on waiting for the
    /// engine exactly as the legacy one does.
    private var stateContinuationsForJoin = [NSManagedObjectID: [UUID: AsyncStream<AttachmentState>.Continuation]]()


    /// The last state pushed for each attachment being shown, which is what a tap starts from: only the phase can have changed, the image being the reader's
    /// business and not the engine's.
    private var latestStateForJoin = [NSManagedObjectID: AttachmentState]()


    /// A lookup and nothing more, as the protocol requires. Keyed on the *file* and the size, so a photograph attached to two messages is decoded once for
    /// both, and the same photograph drawn at 200pt and as a 120pt tile is decoded once for each.
    ///
    /// Guarded by the join, because that key outlives the messages: delete a message and receive the same photograph again, and the cache still holds it while
    /// the file itself is gone. Answering from the cache alone would show the reader a picture that is not on the device, and that they would find missing at
    /// the next launch. The guard is a lookup on the view context and a file size, which is what the protocol allows.
    func cachedImageForAttachment(_ attachment: MessageAttachment, pixelSize: CGSize) -> CGImage? {
        guard case .objectID(let joinObjectID) = attachment.identifier else { return nil }
        guard let join = try? viewContext.existingObject(with: joinObjectID) as? FyleMessageJoinWithStatus else { return nil }
        guard let fyle = join.fyle, fyle.getFileSize() != nil else { return nil }
        return Self.cachedImages.object(forKey: Self.cacheKey(sha256: attachment.sha256, pixelSize: pixelSize))
    }


    nonisolated private static func cacheKey(sha256: Data, pixelSize: CGSize) -> NSString {
        "\(sha256.base64EncodedString())-\(Int(pixelSize.width))x\(Int(pixelSize.height))" as NSString
    }


    /// The key under which the *latest* picture decoded for a file is kept, whatever size it was asked for — see ``cachedImageOfAnySizeForAttachment(_:)``.
    nonisolated private static func cacheKeyForAnySize(sha256: Data) -> NSString {
        "\(sha256.base64EncodedString())-anySize" as NSString
    }


    /// A picture of this attachment at **whatever size one happens to have been decoded**, or nil if none has.
    ///
    /// For the one caller that cannot name a size: a drag out of the discussion, whose preview must be answered in the instant the drag begins,
    /// at 50 by 50 — a size nothing on this screen ever displays, so asking for it exactly can only miss. See
    /// `TheAttachmentsOfAMessageDraggedOut`.
    ///
    /// **Never a decode.** A drag that had to wait would be a drag that stutters; an attachment nobody has looked at yet is carried as an icon
    /// instead, which is the honest answer.
    ///
    /// **What "has been decoded" means was wrong until 2026-08-15**, and it showed as a file icon under the reader's finger for a photograph
    /// they could see: the key was written where a picture is decoded and *not* where one is served from the exact-size cache, so once evicted
    /// it was never written again. It is now written on both paths — see ``state(of:for:pixelSize:sha256:)``.
    func cachedImageOfAnySizeForAttachment(_ attachment: MessageAttachment) -> CGImage? {
        guard case .objectID(let joinObjectID) = attachment.identifier else { return nil }
        guard let join = try? viewContext.existingObject(with: joinObjectID) as? FyleMessageJoinWithStatus else { return nil }
        guard let fyle = join.fyle, fyle.getFileSize() != nil else { return nil }
        return Self.cachedImages.object(forKey: Self.cacheKeyForAnySize(sha256: attachment.sha256))
    }


    /// Every image decoded for this screen, bounded by **what they weigh** rather than by how many there are.
    ///
    /// That distinction matters here and not for ``cachedCellModels``: a few hundred models are nothing, whereas a few hundred photographs at 200pt on a 3×
    /// screen would be the better part of a gigabyte. `NSCache` also gives its contents up under memory pressure, which is exactly what should happen to
    /// pictures.
    ///
    /// `nonisolated(unsafe)` for the same reason as the cache of models: Apple documents `NSCache` as safe to use from several threads at once, which the
    /// compiler cannot know.
    nonisolated(unsafe) private static let cachedImages: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()


    /// Decodes the small blob a message carries so that something can be shown before its file arrives. It is already small, so it is decoded as it is rather
    /// than downsampled — the point of it is to be shown blurred.
    nonisolated private static func decodedImage(from data: Data) async -> CGImage? {
        guard !Task.isCancelled else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // bake in the EXIF orientation
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }


    /// What ImageIO can make of the file: a picture of it for every image format and for PDF, which it rasterises, and nothing at all for a video —
    /// `CGImageSourceCreateWithURL` simply declines one.
    ///
    /// `nonisolated` **and** `async`, so that it runs on the cooperative pool rather than on the main actor — while still belonging to the calling task tree,
    /// so that a row scrolled away cancels its own decode. A detached task would not.
    ///
    /// Returns a `CGImage`, already decoded and with the EXIF orientation baked into the pixels, as everything producing an image for this screen must: nothing lazy can
    /// then happen on the main thread while the list is being scrolled.
    nonisolated private static func imageDecodedByImageIO(at url: URL, maxPixelSize: Int) async -> CGImage? {
        // The decode itself cannot be interrupted, so bail before starting it if we are already cancelled — by the time a queued decode is scheduled, the
        // message it belonged to may well have scrolled away.
        guard !Task.isCancelled else { return nil }
        guard maxPixelSize > 0 else { return nil }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // bake in the EXIF orientation
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }


    /// What QuickLook can make of the file: a frame of a video, a page of a document, a rendering of whatever the system knows how to open.
    ///
    /// **The URL must be a hardlink, not the fyle itself.** A `Fyle` is stored under the hexadecimal of its own hash and nothing else — no extension — and while
    /// ImageIO sniffs the bytes and does not care, QuickLook decides what a file is from its name. Handed the hash, it declines a film. Presenting a fyle under
    /// the name it was sent with is precisely what `HardLinksToFylesManager` exists for, and the caller above asks it.
    ///
    /// Asked for in pixels, by requesting points at a scale of one — this is the only place in the pipeline that has to say which it means,
    /// `QLThumbnailGenerator` taking both, and everything the data source deals in being pixels. `.thumbnail` rather than `.icon`, as on the legacy screen: a
    /// picture of the contents, and not the generic badge of a file type.
    ///
    /// It answers from another process, so it is slower than the decode above by far more than the arithmetic suggests — which is the reason it is a fallback and
    /// not the first thing asked. The answer is cached like any other, so the cost is paid once per file and size.
    nonisolated private static func thumbnailFromQuickLook(at hardlinkURL: URL, maxPixelSize: Int) async -> CGImage? {
        guard !Task.isCancelled else { return nil }
        guard maxPixelSize > 0 else { return nil }
        let request = QLThumbnailGenerator.Request(fileAt: hardlinkURL,
                                                   size: CGSize(width: maxPixelSize, height: maxPixelSize),
                                                   scale: 1,
                                                   representationTypes: .thumbnail)
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        return representation.cgImage
    }


    /// The images attached to a message, in the order they were attached.
    ///
    /// The GIF is pulled out first, exactly as the legacy screen does in `SentMessageCell` and `ReceivedMessageCell`: a message with one GIF and one photo is
    /// not a "two images" message, the GIF having a presentation of its own — ``gifInMessage(of:)``.
    ///
    /// A wiped message has no attachments to show, which the legacy screen expresses by emptying every list at the point of collection.
    nonisolated private static func imageAttachments(of message: PersistedMessage) -> [MessageAttachment] {
        guard !message.isWiped else { return [] }
        let gifObjectID = gifJoin(of: message)?.objectID
        return imageJoins(of: message)
            .filter({ $0.objectID != gifObjectID })
            .compactMap({ attachment(of: $0) })
    }


    /// The joins of a message that the model calls images, GIF included — the one list both ``imageAttachments(of:)`` and ``gifJoin(of:)`` read from, so that
    /// neither can disagree with the other about what an image of this message is.
    nonisolated private static func imageJoins(of message: PersistedMessage) -> [FyleMessageJoinWithStatus] {
        switch message {
        case let sentMessage as PersistedMessageSent: return sentMessage.fyleMessageJoinWithStatusesOfImageType
        case let receivedMessage as PersistedMessageReceived: return receivedMessage.fyleMessageJoinWithStatusesOfImageType
        default: return []
        }
    }


    /// The one join of a message shown as an animated image, and the **single** place that decides which one that is.
    ///
    /// A GIF first, and a WebP only if there is none — which is the legacy rule, written this way there and worth keeping identical: a message carrying both
    /// animates the GIF and shows the WebP as one of its images.
    nonisolated private static func gifJoin(of message: PersistedMessage) -> FyleMessageJoinWithStatus? {
        let joins = imageJoins(of: message)
        return joins.first(where: { $0.uti == UTType.gif.identifier })
            ?? joins.first(where: { $0.uti == UTType.webP.identifier })
    }


    /// The animated image of a message, with the shape of its canvas when the file is here to say what that shape is.
    ///
    /// **The canvas is measured here rather than in the view**, and that is what keeps this screen from reflowing: this runs on a background context while the
    /// model is being built, so a GIF whose bytes are already on disk reaches its row at its true size on the first frame it is drawn on. The legacy screen
    /// reserves 200×150 and resizes even for a file it already has. See ``GifInMessage`` for the case that cannot be helped — a GIF not yet downloaded, whose
    /// ratio nothing on this device knows.
    nonisolated private static func gifInMessage(of message: PersistedMessage) -> GifInMessage? {
        guard !message.isWiped else { return nil }
        guard let join = gifJoin(of: message) else { return nil }
        guard let attachment = attachment(of: join) else { return nil }
        return .init(attachment: attachment, canvasSize: canvasSizeOfAnimatedImage(of: join))
    }


    /// The size of an animated image's canvas, in pixels, read from the file's header — and nil while there is no file to read.
    ///
    /// Three things about this read are deliberate:
    ///
    /// - **It is the header and not the image.** `CGImageSourceCopyProperties` describes the *container*, so nothing is decoded and no frame is built: what it
    ///   costs is the few bytes at the front of the file, which is why it is affordable on the path that builds every model.
    /// - **No hardlink**, unlike the waveform and the document preview. ImageIO decides what it has been given from the name too, and a `Fyle` is stored under
    ///   the hexadecimal of its own hash with no extension — but here it can simply be *told*, through `kCGImageSourceTypeIdentifierHint` and the join's own
    ///   UTI. Animating the file will still need a hardlink; measuring it does not. The hint carries the join's UTI rather than `UTType.gif` as the legacy
    ///   screen hardcodes, which is what makes the WebP case honest.
    /// - **The canvas, not the first frame.** An animated image may hold frames smaller than the canvas they are composed onto, and one whose first frame is a
    ///   corner of the picture would otherwise be drawn at the shape of that corner. A file that names no canvas is left at nil, as on the legacy screen, and
    ///   the view then reserves 200×150.
    nonisolated private static func canvasSizeOfAnimatedImage(of join: FyleMessageJoinWithStatus) -> CGSize? {

        guard let fyle = join.fyle else { return nil }

        // Keyed on the file alone: the canvas of a GIF is a property of its bytes, so a GIF forwarded to ten discussions is measured once, and no entry ever
        // needs invalidating.
        let cacheKey = fyle.sha256.base64EncodedString() as NSString
        if let remembered = cachedCanvasSizes.object(forKey: cacheKey) {
            return remembered.canvasSize
        }

        // **The file decides.** A join whose bytes have not arrived has a `Fyle` all the same — created with the sha256 the metadata announced — so the URL
        // exists long before anything is at it.
        guard fyle.fileExistsOnDisk else { return nil }

        let options = [kCGImageSourceTypeIdentifierHint: join.uti] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(fyle.url as CFURL, options),
              let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
              let dictionaryOfTheKind = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] ?? properties[kCGImagePropertyWebPDictionary] as? [CFString: Any],
              let width = dictionaryOfTheKind[kCGImagePropertyGIFCanvasPixelWidth] as? NSNumber ?? dictionaryOfTheKind[kCGImagePropertyWebPCanvasPixelWidth] as? NSNumber,
              let height = dictionaryOfTheKind[kCGImagePropertyGIFCanvasPixelHeight] as? NSNumber ?? dictionaryOfTheKind[kCGImagePropertyWebPCanvasPixelHeight] as? NSNumber else {
            return nil
        }

        let canvasSize = CGSize(width: CGFloat(truncating: width), height: CGFloat(truncating: height))
        cachedCanvasSizes.setObject(CachedCanvasSize(canvasSize), forKey: cacheKey)
        return canvasSize

    }


    /// Counted rather than sized: two numbers apiece, where the image cache next door holds megabytes. Bounded all the same, this data source living for as long
    /// as the process does.
    nonisolated(unsafe) private static let cachedCanvasSizes: NSCache<NSString, CachedCanvasSize> = {
        let cache = NSCache<NSString, CachedCanvasSize>()
        cache.countLimit = 256
        return cache
    }()


    /// `NSCache` holds objects, and a `CGSize` is not one.
    private final class CachedCanvasSize {
        let canvasSize: CGSize
        init(_ canvasSize: CGSize) { self.canvasSize = canvasSize }
    }


    /// The one attachment of a message shown as a document preview: the first paginated document, if it has one.
    ///
    /// Only the first, as on the legacy screen — a message carrying three contracts shows the first and lists the other two. Which kinds count is
    /// ``FyleMessageJoinWithStatus/isDocumentType``, which is wider here than there and says why.
    nonisolated private static func documentAttachment(of message: PersistedMessage) -> MessageAttachment? {
        guard !message.isWiped else { return nil }
        let joins: [FyleMessageJoinWithStatus]
        switch message {
        case let sentMessage as PersistedMessageSent: joins = sentMessage.fyleMessageJoinWithStatuses
        case let receivedMessage as PersistedMessageReceived: joins = receivedMessage.fyleMessageJoinWithStatuses
        default: return nil
        }
        guard let firstDocument = joins.first(where: { $0.isDocumentType }) else { return nil }
        return attachment(of: firstDocument)
    }


    /// The one attachment of a message shown as a video preview: the first video, if it has one.
    ///
    /// Only the first, as with the document and the recording. **By type and not by availability**: a video is usually too large to be fetched automatically, and
    /// it gets its preview all the same, with the download control drawn on it — which is what an image too large to fetch already does. See
    /// ``MessageContent/Ordinary/video``.
    nonisolated private static func videoAttachment(of message: PersistedMessage) -> MessageAttachment? {
        guard !message.isWiped else { return nil }
        let joins: [FyleMessageJoinWithStatus]
        switch message {
        case let sentMessage as PersistedMessageSent: joins = sentMessage.fyleMessageJoinWithStatuses
        case let receivedMessage as PersistedMessageReceived: joins = receivedMessage.fyleMessageJoinWithStatuses
        default: return nil
        }
        guard let firstVideo = joins.first(where: { $0.isVideoType }) else { return nil }
        return attachment(of: firstVideo)
    }


    /// The one attachment of a message shown as an audio player: the first recording, if it has one.
    ///
    /// Only the first, as on the legacy screen — a message carrying three voice notes plays the first and lists the other two.
    nonisolated private static func audioAttachment(of message: PersistedMessage) -> MessageAttachment? {
        guard !message.isWiped else { return nil }
        let audioJoins: [FyleMessageJoinWithStatus]
        switch message {
        case let sentMessage as PersistedMessageSent: audioJoins = sentMessage.fyleMessageJoinWithStatusesOfAudioType
        case let receivedMessage as PersistedMessageReceived: audioJoins = receivedMessage.fyleMessageJoinWithStatusesOfAudioType
        default: return nil
        }
        guard let firstAudio = audioJoins.first else { return nil }
        return attachment(of: firstAudio)
    }


    /// The attachments of a message shown as *cards*: everything the screen does not draw as something richer.
    ///
    /// Composed by subtraction rather than from a category of its own, exactly as the legacy screen composes it — which is what keeps an attachment of an
    /// unforeseen kind visible instead of silently absent. Two of those subtractions are worth naming:
    ///
    /// - **Link previews are excluded although nothing shows them yet.** A preview is the *rendering* of a URL already in the text, so a card for it would show
    ///   the reader a file they never sent. The legacy screen gives the first one to `SinglePreviewView` and the rest to cards; until that view exists, none of
    ///   them is shown at all — which is right, where a card would be wrong.
    /// - **The first video is excluded** since Step 63, having a presentation of its own — ``videoAttachment(of:)``. Further videos are still cards, as further
    ///   documents and further recordings are.
    /// - **The GIF is excluded**, having a presentation of its own — ``gifInMessage(of:)``. It was a card for as long as this screen had nothing that could draw
    ///   it, a card at least saying it was there; now that it is drawn at the shape of its canvas, a card beside it would be the same file twice.
    nonisolated private static func cardAttachments(of message: PersistedMessage) -> [MessageAttachment] {
        guard !message.isWiped else { return [] }
        let joins: [FyleMessageJoinWithStatus]
        switch message {
        case let sentMessage as PersistedMessageSent: joins = sentMessage.fyleMessageJoinWithStatuses
        case let receivedMessage as PersistedMessageReceived: joins = receivedMessage.fyleMessageJoinWithStatuses
        default: return []
        }
        var identifiersShownElsewhere = Set(imageAttachments(of: message).map(\.identifier))
        if let gif = gifInMessage(of: message) {
            identifiersShownElsewhere.insert(gif.attachment.identifier)
        }
        if let video = videoAttachment(of: message) {
            identifiersShownElsewhere.insert(video.identifier)
        }
        if let document = documentAttachment(of: message) {
            identifiersShownElsewhere.insert(document.identifier)
        }
        if let audio = audioAttachment(of: message) {
            identifiersShownElsewhere.insert(audio.identifier)
        }
        return joins
            .filter({ !$0.isPreviewType })
            .compactMap({ attachment(of: $0) })
            .filter({ !identifiersShownElsewhere.contains($0.identifier) })
    }


    /// Where the rendering of a link in this message is to come from, if anywhere.
    ///
    /// **The sender's preview first, always.** Only when there is none does the reader's setting come into it — and it is off by default, so for most readers this
    /// answers `nil` for a message whose sender attached nothing, which is what the legacy screen shows them too.
    ///
    /// The **first** preview, as on the legacy screen, which gives the first to `SinglePreviewView` and leaves the rest out of the cards. Ours does the same, in
    /// ``cardAttachments(of:)``.
    nonisolated private static func linkPreview(of message: PersistedMessage) -> LinkPreviewInMessage? {
        guard !message.isWiped else { return nil }
        switch message {
        case let sentMessage as PersistedMessageSent:
            // A message the reader sent has the preview they composed it with, or none: nothing is ever fetched for one.
            guard let join = sentMessage.fyleMessageJoinWithStatusesOfPreviewType.first else { return nil }
            return attachment(of: join).map({ .attached($0, shape: shapeOfLinkPreview(of: join)) })
        case let receivedMessage as PersistedMessageReceived:
            if let join = receivedMessage.fyleMessageJoinWithStatusesOfPreviewType.first {
                return attachment(of: join).map({ .attached($0, shape: shapeOfLinkPreview(of: join)) })
            }
            guard ObvMessengerSettings.Discussions.fetchMissingLinkPreviewFromMessageReceived else { return nil }
            // Cheap for the messages that carry no link at all: `getHttpsURLs()` returns before building a detector unless the text contains "https".
            guard let url = receivedMessage.textBody?.getHttpsURLs().first else { return nil }
            return .toBeFetched(url: url)
        default:
            return nil
        }
    }


    /// The body as this screen shows it, which is not always the body as it was sent: the URL rendered by a preview is taken off the end of it, leaving no body at
    /// all when the URL was the whole message.
    ///
    /// **Only for a preview the sender attached**, and this is deliberate. The URL is read from the preview's `fileName`, which *is* the URL as a string — set from
    /// `url?.absoluteString` when a preview is attached — so nothing has to be decoded and nothing has to be waited for, where the legacy screen strips only once
    /// the metadata has been decoded and so visibly reflows the message. A preview still to be fetched is left alone for a plainer reason: it may never arrive, and
    /// a reader would then be shown a message whose link had silently gone missing.
    /// The body of a message as it is to be drawn: what was written, marked up, with everything in it that can be tapped made tappable.
    ///
    /// The order is the legacy screen's, and it matters at the one place the two overlap: **data detection first, mentions after**, so that a name that happens to
    /// look like something detectable is still a mention.
    nonisolated private static func textBody(of message: PersistedMessage, renderedBy linkPreview: LinkPreviewInMessage?) -> AttributedString? {
        let body = message.getDisplayableAttributedBody(removingTrailingURL: urlRenderedByThePreview(linkPreview))
        return body.map({ mentionsAsLinks(in: dataDetectedAsLinks(in: $0)) })
    }


    /// The URL a preview renders, which is taken off the end of the body — and nil whenever it is to be left where it is.
    nonisolated private static func urlRenderedByThePreview(_ linkPreview: LinkPreviewInMessage?) -> URL? {
        guard ObvMessengerSettings.Interface.hideTrailingURLInMessagesWhenPreviewIsAvailable else { return nil }
        guard case .attached(let preview, _) = linkPreview else { return nil }
        guard let fileName = preview.fileName else { return nil }
        return URL(string: fileName)
    }


    /// Everything in a body that is worth tapping although nobody wrote it as a link: a telephone number, an address, a date, a bare URL.
    ///
    /// **Run here, while the model is built, and not asked for afterwards.** The legacy screen detects asynchronously and caches the answer, because it detects on
    /// the main thread and cannot afford to; a cell then reconfigures itself when the answer lands. Ours is already built on a background context, in a batch,
    /// ahead of the cells that will want it — so the detection is simply part of building the body, and no message ever changes after it is drawn. That is the same
    /// argument made about a poll's shape: what a row *is* belongs in the model, and only what changes inside it belongs in a stream.
    ///
    /// The detector is asked for the four kinds `getLinkForAttributedString()` knows how to turn into a link, rather than for everything: the others come back
    /// with no link to make, and asking for them trips that method's own assertion.
    ///
    /// Ranges cross by way of `NSMutableAttributedString`, as they do on the legacy screen: the detector counts in UTF-16 and an `AttributedString` does not, and
    /// the mention attribute has to survive the trip — hence `including: \.olvidApp`.
    nonisolated private static func dataDetectedAsLinks(in body: AttributedString) -> AttributedString {

        let plainBody = String(body.characters)
        guard !plainBody.isEmpty else { return body }

        guard let detector = try? NSDataDetector(types: typesWorthDetecting.rawValue) else { assertionFailure(); return body }
        let matches = detector.matches(in: plainBody, range: NSRange(location: 0, length: plainBody.utf16.count))
        guard !matches.isEmpty else { return body }

        guard let annotated = try? NSMutableAttributedString(body, including: \.olvidApp) else { assertionFailure(); return body }
        for match in matches {
            guard let link = match.getLinkForAttributedString() else { continue }
            annotated.addAttribute(.link, value: link, range: match.range)
        }

        return (try? AttributedString(annotated, including: \.olvidApp)) ?? body

    }


    /// What the detector is asked to find: the kinds a tap can lead somewhere for.
    nonisolated private static let typesWorthDetecting: NSTextCheckingResult.CheckingType = [.phoneNumber, .address, .date, .link]


    /// Every mention in a body turned into a link, so that a reader can tap it.
    ///
    /// **Done here because only the app can read a mention.** `ObvMentionAttribute` lives in the `olvidApp` attribute scope, which the screen's module knows
    /// nothing of; what it does know is that a mention is a link with a scheme of its own — see ``MentionInAMessage``. So who was mentioned is written into the
    /// link, and read back out of it when the reader taps. The legacy screen does the same thing with a counter it resolves against the attributed string, which
    /// is not available to a view that cannot see the attribute.
    ///
    /// The identity travels **base64url-encoded**: it is bytes, a URL is text, and the ordinary base64 alphabet would need escaping in one.
    nonisolated private static func mentionsAsLinks(in body: AttributedString) -> AttributedString {
        var body = body
        for (mentionedCryptoId, range) in body.runs[\.mention] {
            guard let mentionedCryptoId else { continue }
            let whoTheyAre = mentionedCryptoId.getIdentity().base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            guard let link = MentionInAMessage.url(forWhoeverIsMentioned: whoTheyAre) else { assertionFailure(); continue }
            body[range].link = link
        }
        return body
    }


    /// Whoever a mention's link stands for, which is what ``mentionsAsLinks(in:)`` wrote into it.
    nonisolated static func whoeverIsMentioned(in url: URL) -> ObvCryptoId? {
        guard let whoTheyAre = MentionInAMessage.whoeverIsMentioned(in: url) else { return nil }
        var base64 = whoTheyAre
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let identity = Data(base64Encoded: base64) else { assertionFailure(); return nil }
        return try? ObvCryptoId(identity: identity)
    }


    /// What this screen needs to know about one attached file. Its image is *not* among it: that is asked for separately, by sha256 and by the size it is to be
    /// drawn at, so that a picture arriving updates one image rather than the message it belongs to.
    nonisolated private static func attachment(of join: FyleMessageJoinWithStatus) -> MessageAttachment? {
        guard let sha256 = join.fyle?.sha256 else { return nil }
        return .init(identifier: .objectID(join.objectID),
                     sha256: sha256,
                     index: join.index,
                     fileName: join.fileName,
                     fileSize: Int(join.totalByteCount),
                     uti: join.uti)
    }


    /// Resolves the status indicator of a sent message exactly as the legacy screen does: through the canonical mapping of
    /// ``PersistedMessageSent/MessageStatus/getSymbolIcon(messageHasMoreThanOneRecipient:)``, and showing no indicator at all when the message has no
    /// recipient.
    nonisolated private static func statusIcon(of sentMessage: PersistedMessageSent) -> SentMessageCellView.Model.StatusIcon {
        let status = sentMessage.status
        guard status != .hasNoRecipient else { return .none }
        let symbolIcon = status.getSymbolIcon(messageHasMoreThanOneRecipient: sentMessage.hasMoreThanOneRecipient)
        if let systemIcon = symbolIcon as? SystemIcon {
            return .system(systemIcon)
        } else if let customIcon = symbolIcon as? CustomIcon {
            return .custom(customIcon)
        } else {
            assertionFailure()
            return .none
        }
    }

    /// The kinds of messages the SwiftUI screen can display.
    ///
    /// All three of them, since Step 18b. The two categories of system message this screen draws itself are excluded by the *fetch* rather than here — a category is an
    /// attribute, which an object ID cannot be asked for without materializing the message. See ``messagesShownByTheScreen``.
    private static let entityNamesOfSupportedMessages: Set<String> = [
        PersistedMessageSent.entityName,
        PersistedMessageReceived.entityName,
        PersistedMessageSystem.entityName,
    ]

    // Errors

    enum ObvError: Error {
        case couldNotFindPoll
        case couldNotFindDiscussion
        case couldNotFindMessage
        case unexpectedCellIdentifierType
        case unexpectedMessageKind
        case attachmentIsNotPersisted
        /// A sent attachment uploads through the send manager, which this data source does not reach.
        case progressIsOnlyAvailableForAReceivedAttachment
        case progressIsOnlyAvailableForAnAttachmentBeingTransferred
        case couldNotDetermineAttachmentIdentifier
        case delegateIsNil
        /// There is no file to hand over: an attachment still downloading, or one whose message has gone since the drag began.
        case theAttachmentHasNoFileToGive
    }

}


// MARK: - The player's delegate

/// Carries what `ObvAudioPlayer` reports to the data source.
///
/// It exists only to cross an isolation boundary: the player calls its delegate from a `Timer`, without isolation of its own, while the data source is
/// `@MainActor`. It holds the data source weakly — the player holds *this* weakly in turn, and neither should keep a discussion alive.
private final class AudioPlaybackObserver: ObvAudioPlayerDelegate {

    private weak var dataSource: SingleDiscussionViewAppDataSource?

    init(dataSource: SingleDiscussionViewAppDataSource) {
        self.dataSource = dataSource
    }

    func audioIsPlaying(currentTime: TimeInterval) {
        Task { @MainActor [weak dataSource] in dataSource?.playerIsPlaying(currentTime: currentTime) }
    }

    func audioPlayerDidPause() {
        Task { @MainActor [weak dataSource] in dataSource?.playerPaused() }
    }

    func audioPlayerDidStopPlaying() {
        Task { @MainActor [weak dataSource] in dataSource?.playerStopped() }
    }

    func audioPlayerDidFinishPlaying() {
        Task { @MainActor [weak dataSource] in dataSource?.playerFinished() }
    }

    /// The player is about to belong to somebody else — the legacy screen, most likely. Whatever this screen was playing has fallen silent.
    func playerWillChangeCurrentFyle(previousHardlink: HardLinkToFyle?) {
        Task { @MainActor [weak dataSource] in dataSource?.playerWasTakenAway() }
    }

}


// MARK: - Internal managers

extension SingleDiscussionViewAppDataSource {

    /// This manager produces the stream of the identifiers of all the cells of a discussion, in the order they are displayed.
    private final class SingleDiscussionViewModelStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<SingleDiscussionView.Model, PersistedMessage>, @unchecked Sendable {

        /// Which messages count as new since the reader arrived or last replied, and legacy's `objectIDsOfMessagesToConsiderInNewMessagesCell`.
        private var theOnesThatCount: Set<NSManagedObjectID>

        /// What the discussion held the last time a model was built, which is what turns legacy's five notifications into one comparison. Nil until the first one.
        private var theObjectIDsLastSeen: Set<NSManagedObjectID>?

        /// The discussion this follows, kept so that the first model can ask what is *still* unread — see ``keepsTheMarkerUpToDate(among:)``.
        private let discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>

        /// Which discussion this is, so that the data source can tell the right manager that the reader has gone away.
        let discussionIdentifier: ObvDiscussionIdentifier

        /// Set by ``theReaderHasGoneAway()`` when the marker is to start again, and read and cleared on the next model. Touched only on the context's queue, like
        /// ``theMarkerStartsAgainWithTheNextArrival``, so the two change in the order their triggers came.
        private var theReaderWentAway = false


        /// The reader has left this discussion, or the app has gone away with it open, and legacy's `theUserLeftTheDiscussion`.
        ///
        /// **It asks for a model rather than computing one**, so that the set is re-derived where everything else about it is, on the queue of the context, with the
        /// fetched objects in hand. `getFetchedObjectsAndYieldModelIfNeeded()` yields only when the model differs, so a discussion whose marker was already empty
        /// says nothing.
        ///
        /// The flag is set on the context's queue before the model is asked for, and that queue runs blocks in order, so the model always sees it.
        func theReaderHasGoneAway() {
            frc.managedObjectContext.perform { [weak self] in
                self?.theReaderWentAway = true
            }
            Task { [weak self] in try? await self?.getFetchedObjectsAndYieldModelIfNeeded() }
        }


        /// Set when the reader has looked away without leaving, so that the marker starts again with the next message that counts. Written and read on the
        /// context's queue, where models are built.
        private var theMarkerStartsAgainWithTheNextArrival = false

        /// Called when that deferred start happens, so that the data source forgets the seed, as it does when the marker starts again at once.
        private let theMarkerHasStartedAgainWithAnArrival: @Sendable () -> Void


        /// The reader has looked away without leaving, and this window is still on screen.
        ///
        /// The marker starts again with the next message that arrives, not now. If it started again now, its row would leave or move in front of the reader,
        /// and every row around it would move. With the next arrival, the marker ends up in the same place, above what came in while the reader was away, and
        /// it moves in the same update that adds the message.
        func theReaderHasLookedAway() {
            frc.managedObjectContext.perform { [weak self] in
                self?.theMarkerStartsAgainWithTheNextArrival = true
                SingleDiscussionViewAppDataSource.saysWhatHappensToTheMarker("the reader looked away: the marker WAITS for an arrival to start again")
            }
        }


        /// The reader is back before anything arrived, so the marker stays as it was.
        func theReaderIsBack() {
            frc.managedObjectContext.perform { [weak self] in
                guard let self else { return }
                SingleDiscussionViewAppDataSource.saysWhatHappensToTheMarker(self.theMarkerStartsAgainWithTheNextArrival ? "the reader is back before any arrival: the marker stays" : "the reader is back, and nothing was waiting")
                self.theMarkerStartsAgainWithTheNextArrival = false
            }
        }


        /// What is unread *now*, of the messages this screen lists — the two kinds legacy counts, asked of the store rather than remembered.
        private func whatIsStillUnread(among objectIDsTheScreenLists: Set<NSManagedObjectID>) -> Set<NSManagedObjectID> {
            guard let (theOnes, _) = try? SingleDiscussionViewAppDataSource.getNewMessages(discussionObjectID: discussionObjectID,
                                                                                          among: objectIDsTheScreenLists,
                                                                                          within: frc.managedObjectContext) else { return [] }
            return theOnes
        }

        init(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, discussionIdentifier: ObvDiscussionIdentifier, showing messagesShownByTheScreen: PersistedMessage.MessagesShownByTheScreen, startingFrom theOnesThatCount: Set<NSManagedObjectID>, context: NSManagedObjectContext, whenTheMarkerStartsAgainWithAnArrival theMarkerHasStartedAgainWithAnArrival: @escaping @Sendable () -> Void) {
            self.theOnesThatCount = theOnesThatCount
            self.discussionObjectID = discussionObjectID
            self.discussionIdentifier = discussionIdentifier
            self.theMarkerHasStartedAgainWithAnArrival = theMarkerHasStartedAgainWithAnArrival
            let frc = PersistedMessage.getFetchedResultsControllerForAllMessagesWithinDiscussion(
                discussionObjectID: discussionObjectID,
                showing: messagesShownByTheScreen,
                within: context)
            super.init(frc: frc)
        }

        /// The class, the `objectID` and the `sectionIdentifier` of every fetched message are read, the last for the list's sections. This is
        /// **not** free: the controller fetches in batches, and going through every object loads every batch, a pass over the whole discussion each time.
        ///
        /// Exactly **one** model is built: the last. Its model is streamed with the identifiers so that a message just sent or received shows its
        /// content on the frame it appears on, instead of a redacted skeleton that turns into a bubble a few milliseconds later — and so that the screen can
        /// tell a sent message from a received one, which decides how insistently the list follows it.
        override func createModel(fetchedObjects: [PersistedMessage]) throws -> SingleDiscussionView.Model {
            let supportedMessages = fetchedObjects
                .filter({ $0 is PersistedMessageSent || $0 is PersistedMessageReceived || $0 is PersistedMessageSystem })
            let cellIdentifiers = supportedMessages
                .map({ SingleDiscussionView.CellIdentifier.objectID($0.objectID) })
            let lastCellModel = supportedMessages.last.flatMap({ try? SingleDiscussionViewAppDataSource.createModel(of: $0) })
            keepsTheMarkerUpToDate(among: supportedMessages)
            return .init(cellIdentifiers: cellIdentifiers,
                         lastCellModel: lastCellModel,
                         newMessages: SingleDiscussionViewAppDataSource.newMessages(from: theOnesThatCount),
                         theSections: SingleDiscussionViewAppDataSource.theSections(ofCellsWithSectionIdentifiers: supportedMessages.map(\.sectionIdentifier)))
        }


        /// Keeps ``theOnesThatCount`` up to date, which is what the unread marker is drawn from.
        ///
        /// **Legacy's five triggers are one comparison here.** It watches insertions of received messages, insertions of relevant system messages, insertions of
        /// *sent* messages, and deletions of either kind, through five separate observers on `NSManagedObjectContextObjectsDidChange`. A fetched results controller
        /// already reports every one of those as a change to the same list, so what each of them said can be read off the difference between this fetch and the
        /// previous one. There is nothing to observe and nothing to keep in step.
        ///
        /// **The set does not shrink when a message is read**, and that is legacy's meaning rather than an oversight: the marker says *new since you entered or last
        /// replied*, so it stays above messages the reader has since read, and only a deletion, a message they send, or leaving takes anything out of it.
        ///
        /// **On the first call the seed stands, and whatever is still unread joins it.** With nothing to compare against, every message in the discussion would read
        /// as an arrival — the same trap the screen's own `followsAMessageThatHasJustArrived` guards against — so the comparison starts on the second call. But the
        /// seed alone is not enough, because **this manager is rebuilt while the screen stays up**: the model is followed from a `.task`, and showing
        /// anything full screen takes the view out of the hierarchy, so opening a photograph cancels it and coming back starts a new manager from the
        /// value computed at entry — losing whatever arrived in between. Unioning with what is *still* unread closes that, and it can only ever **add**: a message
        /// already marked read is one that was in the seed, so nothing it might miss is anything the union could have removed.
        ///
        /// This is the one place a query is right. Doing it *instead* of the seed would be wrong, for the reason written where the seed is computed.
        ///
        /// **Only what appeared is materialized.** Everything else here reads a class and an object ID, neither of which fulfills a fault, which is what lets this
        /// manager cost nothing on a discussion of thousands. Asking a *system* message whether it counts towards unread does need the object, and there are never
        /// more than a handful of them at once.
        private func keepsTheMarkerUpToDate(among supportedMessages: [PersistedMessage]) {

            let objectIDsNow = Set(supportedMessages.map({ $0.objectID }))
            defer { theObjectIDsLastSeen = objectIDsNow }

            // **The reader went away, so the marker starts again from whatever is genuinely still unread** — legacy's `theUserLeftTheDiscussion`, which empties the
            // set and re-derives it. A **replace**, and that is the whole difference from the union below: by now the messages the reader saw have been marked read,
            // so re-deriving comes back with nothing and the marker goes. A union could never express that, and this is why the two cases cannot share one line.
            if theReaderWentAway {
                theReaderWentAway = false
                startsTheMarkerAgain(among: objectIDsNow, "AT ONCE")
                return
            }

            guard let theObjectIDsLastSeen else {
                let before = theOnesThatCount.count
                theOnesThatCount.formUnion(whatIsStillUnread(among: objectIDsNow))
                SingleDiscussionViewAppDataSource.saysWhatHappensToTheMarker("the first model: \(before) from the seed, \(theOnesThatCount.count) with what is still unread")
                return
            }

            // A message deleted leaves the set, whether or not it was one of these — legacy's two deletion observers.
            theOnesThatCount.subtract(theObjectIDsLastSeen.subtracting(objectIDsNow))

            let whatAppeared = objectIDsNow.subtracting(theObjectIDsLastSeen)
            guard !whatAppeared.isEmpty else { return }
            let messagesThatAppeared = supportedMessages.filter({ whatAppeared.contains($0.objectID) })

            // **A message the reader sent clears the whole thing**, which is what makes the marker go away when they reply — legacy's
            // `updateNewMessageCellOnInsertionOfSentMessage`. Tested first, and it wins over anything that arrived in the same breath: replying means the reader has
            // dealt with the discussion, whatever landed alongside.
            if messagesThatAppeared.contains(where: { $0 is PersistedMessageSent }) {
                SingleDiscussionViewAppDataSource.saysWhatHappensToTheMarker("a message was SENT: \(theOnesThatCount.count) → 0")
                theOnesThatCount.removeAll()
                // Nothing is left for a waiting start to replace: the next arrival starts a new marker by itself.
                theMarkerStartsAgainWithTheNextArrival = false
                return
            }

            let theOnesThatCountAmongWhatAppeared = messagesThatAppeared.filter { message in
                if message is PersistedMessageReceived { return true }
                // The same two tests legacy makes: a system message counts only if it counts towards the unread total *and* names a contact — a missed call, not
                // a change of shared settings.
                guard let systemMessage = message as? PersistedMessageSystem else { return false }
                return systemMessage.isRelevantForCountingUnread && systemMessage.optionalContactIdentity != nil
            }.map(\.objectID)

            // **The reader looked away and a message that counts has arrived**, so the marker starts again now, in the same update that adds the message. It is
            // rebuilt from what is still unread, which includes the arrival, so the marker ends up above what came in while the reader was away. A message that
            // does not count, such as a change of shared settings, does not start it, so nothing moves.
            if theMarkerStartsAgainWithTheNextArrival, !theOnesThatCountAmongWhatAppeared.isEmpty {
                startsTheMarkerAgain(among: objectIDsNow, "WITH AN ARRIVAL")
                theMarkerHasStartedAgainWithAnArrival()
                return
            }

            let before = theOnesThatCount.count
            theOnesThatCount.formUnion(theOnesThatCountAmongWhatAppeared)
            SingleDiscussionViewAppDataSource.saysWhatHappensToTheMarker("\(messagesThatAppeared.count) message(s) appeared, \(theOnesThatCountAmongWhatAppeared.count) of which count: \(before) → \(theOnesThatCount.count)\(theMarkerStartsAgainWithTheNextArrival ? ", and the start still waits" : "")")

        }


        /// The marker starts again from what is still unread: a replace, not a union. A start that was waiting for an arrival is replaced by this one.
        private func startsTheMarkerAgain(among objectIDsNow: Set<NSManagedObjectID>, _ how: String) {
            theMarkerStartsAgainWithTheNextArrival = false
            let before = theOnesThatCount.count
            theOnesThatCount = whatIsStillUnread(among: objectIDsNow)
            SingleDiscussionViewAppDataSource.saysWhatHappensToTheMarker("started again \(how): \(before) → \(theOnesThatCount.count) message(s)")
        }

    }


    /// What one attachment can currently offer to whoever is showing it.
    ///
    /// Deliberately not an image: this is produced on the queue of a background context, synchronously, and decoding is neither. It says what there is, and the
    /// decoding happens afterwards.
    private enum AttachmentImageSource: Sendable, Equatable {
        /// The file is not here. It may carry the small blurred blob the message brought, and it may be on its way.
        case notDownloaded(downsizedThumbnail: Data?, isDownloading: Bool)
        /// The file is on this device. `isUploading` says its bytes are still going **out**, which is the only difference a *sent*
        /// attachment can have while its file is already here.
        ///
        /// **It has to be part of this value.** The stream yields when the source changes, so if an upload finishing left the source
        /// equal — the same file at the same URL — nothing would be said and the arc would stay on the screen for ever.
        case file(URL, isUploading: Bool)
        case cancelledByServer
        /// A file the reader chose not to bring over when the history was transferred. Nothing will ever fetch it — see
        /// ``AttachmentState/Phase/leftBehindByAHistoryTransfer``.
        case leftBehindByAHistoryTransfer
        /// A join created by a notification, before the message it belongs to arrived. It becomes downloadable on its own — see
        /// ``AttachmentState/Phase/knownOnlyFromANotification``.
        case knownOnlyFromANotification
    }


    /// This manager produces the stream of what a single attachment can offer, and says so again each time that changes.
    ///
    /// It watches the **join**, which is this attachment of this message, and not the file: the file is shared by every message it is attached to, whereas the
    /// blob standing in for it and the moment it arrives belong to the one attachment being shown.
    private final class AttachmentImageSourceStreamManager: ObvDataSourceStreamManagerWithTwoFetchedResultsController<AttachmentImageSource, FyleMessageJoinWithStatus, PersistedMessageSentRecipientInfos>, @unchecked Sendable {

        /// **Two controllers, and the second is not about the picture at all.** It watches the *recipients* of the message this attachment
        /// belongs to, because that is where the engine identifier of an upload appears — one per recipient, as each is posted to. Nothing
        /// watching the join can see one arrive, and until one has, there is no upload: a message in a group nobody has accepted yet sits for
        /// days with an attachment that is going nowhere. Step 36.
        ///
        /// For a *received* attachment the second controller matches no row and costs nothing, its predicate naming a message that is not a
        /// sent one.
        init(joinObjectID: NSManagedObjectID, messageObjectID: NSManagedObjectID, context: NSManagedObjectContext) {
            let frc1 = FyleMessageJoinWithStatus.getFetchedResultsController(objectID: joinObjectID, within: context)
            let frc2 = PersistedMessageSentRecipientInfos.getFetchedResultsControllerForInfos(ofMessageWithObjectID: messageObjectID, within: context)
            super.init(frc1: frc1, frc2: frc2)
        }

        override func createModel(fetchedObjects1: [FyleMessageJoinWithStatus], fetchedObjects2: [PersistedMessageSentRecipientInfos]) throws -> AttachmentImageSource {
            guard let join = fetchedObjects1.first else { return .notDownloaded(downsizedThumbnail: nil, isDownloading: false) }
            // The file first: once there is one, the blob that stood in for it has nothing left to say.
            if let fyle = join.fyle, fyle.getFileSize() != nil {
                // **A sent attachment's file is here from the start** — it is what the reader chose — so this is also the state an
                // upload is in while it runs. `uploadable` counts with `uploading`, as `SentMessageCell` treats them as one: an
                // attachment waiting its turn shows an empty arc rather than nothing. Step 36.
                // **Uploading means posted and going, not merely waiting its turn.** The status alone says `uploadable` from the moment the
                // message is written until it is complete — including all the time it spends waiting for somebody to accept a group
                // invitation, which may be days. A ring shown then turns for ever and says *sending* about something that is not being sent.
                //
                // So an upload is one the engine has been given: posted to at least one recipient, and therefore carrying an identifier to be
                // followed by. That also removes the waiting this used to need — by the time a view is told `uploading`, there is always
                // something to follow.
                let isUploading: Bool = if let sentJoin = join as? SentFyleMessageJoinWithStatus {
                    switch sentJoin.status {
                    case .uploadable, .uploading: sentJoin.obvAttachmentIdentifierOfTheFirstUpload != nil
                    default: false
                    }
                } else {
                    false
                }
                return .file(fyle.url, isUploading: isUploading)
            }
            if let receivedJoin = join as? ReceivedFyleMessageJoinWithStatus, receivedJoin.status == .cancelledByServer {
                return .cancelledByServer
            }
            if let sentJoin = join as? SentFyleMessageJoinWithStatus, sentJoin.status == .cancelledByServer {
                return .cancelledByServer
            }
            // **Both of these were falling through to `notDownloaded`**, hence to a control offering to fetch the file — merely premature for the second, and
            // wrong for the first, there being nothing anywhere to fetch. Step 30. Both are properties of this *join*, which is why they are read here and not
            // resolved for the whole message.
            if (join as? ReceivedFyleMessageJoinWithStatus)?.status == .untransferred || (join as? SentFyleMessageJoinWithStatus)?.status == .untransferred {
                return .leftBehindByAHistoryTransfer
            }
            if (join as? ReceivedFyleMessageJoinWithStatus)?.status == .notYetDownloadableAsReceivedByUserNotification {
                return .knownOnlyFromANotification
            }
            let isDownloading = (join as? ReceivedFyleMessageJoinWithStatus)?.status == .downloading
                || (join as? SentFyleMessageJoinWithStatus)?.status == .downloading
            return .notDownloaded(downsizedThumbnail: join.downsizedThumbnail, isDownloading: isDownloading)
        }

    }


    /// This manager reports how far the upload of one sent attachment has got, and says so again each time that changes.
    ///
    /// It watches the **join**, exactly as ``AttachmentImageSourceStreamManager`` does, because that is where the fraction is: the
    /// coordinator polls the engine and writes `fractionCompleted` onto this object as a transient attribute. Nothing here talks to the
    /// engine — see `getAsyncStreamOfProgressForAttachment(_:)`.
    ///
    /// **It reports 0 rather than nothing for an attachment waiting its turn**, so an empty arc is drawn where legacy draws one, and
    /// stops reporting once the upload is done, which is what takes the arc away.
    private final class SentAttachmentProgressStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<AttachmentProgress, FyleMessageJoinWithStatus>, @unchecked Sendable {

        init(joinObjectID: NSManagedObjectID, context: NSManagedObjectContext) {
            let frc = FyleMessageJoinWithStatus.getFetchedResultsController(objectID: joinObjectID, within: context)
            super.init(frc: frc)
        }

        override func createModel(fetchedObjects: [FyleMessageJoinWithStatus]) throws -> AttachmentProgress {
            guard let join = fetchedObjects.first as? SentFyleMessageJoinWithStatus else {
                return .init(fractionCompleted: 0)
            }
            switch join.status {
            case .uploadable, .uploading:
                // **Both, and `uploadable` is the one that matters**: nothing ever sets a locally sent join to `uploading`, so that is
                // the status an upload in flight actually has. It reads 0 until the engine reports, which draws an empty arc — saying
                // *this is going* where nothing at all would say *this is done*.
                return .init(fractionCompleted: join.fractionCompleted)
            case .complete, .downloadable, .downloading, .cancelledByServer, .untransferred:
                // Nothing left to report. The phase has changed too, so the view has already stopped following this.
                return .init(fractionCompleted: 1)
            }
        }

    }


    /// This manager produces the model of the poll bubble, and says it again each time the poll or any of its answers changes.
    ///
    /// It resolves what a view must not: the answers in `sortIndex` order, their share over *voters* rather than over votes, and the rule that a reader who chose
    /// "None" is shown as having chosen nothing else. That last one is `poll.hasVoteNone`, and it is a fact about votes rather than about drawing.
    private final class PollStateStreamManager: ObvDataSourceStreamManagerWithThreeFetchedResultsController<MessagePollViewModel, PersistedPoll, PersistedPollCandidate, PersistedPollVote>, @unchecked Sendable {

        init(pollObjectID: TypeSafeManagedObjectID<PersistedPoll>, context: NSManagedObjectContext) {
            // The poll, for its question, its kind and its expiry…
            let frc1 = PersistedPoll.getFetchedResultsController(objectID: pollObjectID, within: context)
            // …its answers, for their text and their order…
            let frc2 = PersistedPollCandidate.getFetchedResultsController(pollObjectID: pollObjectID, within: context)
            // …and **the votes**, which are the only thing that changes when anyone votes. Watching the first two is not enough: casting a vote inserts or updates a
            // `PersistedPollVote` and leaves the poll and its answers as they were, so the bars stood still until a reader left the discussion and came back.
            let frc3 = PersistedPollVote.getFetchedResultsController(pollObjectID: pollObjectID, within: context)
            super.init(frc1: frc1, frc2: frc2, frc3: frc3)
        }

        override func createModel(fetchedObjects1: [PersistedPoll], fetchedObjects2: [PersistedPollCandidate], fetchedObjects3: [PersistedPollVote]) throws -> MessagePollViewModel {

            guard let poll = fetchedObjects1.first else {
                // The poll is deleted with its message, so this is a message on its way out.
                throw ObvError.couldNotFindPoll
            }

            let numberOfVoters = poll.totalNumberOfResponses
            let readerChoseNone = poll.hasVoteNone

            let candidates: [MessagePollCandidateViewModel] = fetchedObjects2
                .sorted(by: \.sortIndex)
                .compactMap { candidate in

                    guard let candidateUUID = candidate.uuid else { return nil }

                    // A reader who chose "None" is shown as having chosen nothing else — the same rule the model enforces on a contact's votes as they arrive.
                    let chosenByTheReader: Bool
                    if readerChoseNone {
                        chosenByTheReader = candidate.isNone
                    } else {
                        chosenByTheReader = !candidate.ownedVotes.isEmpty
                    }

                    let share = numberOfVoters > 0 ? Double(poll.numberOfResponses(for: candidate)) / Double(numberOfVoters) * 100.0 : 0

                    return .init(uuid: candidateUUID, text: candidate.text, hasVoted: chosenByTheReader, totalPercent: share)
                }

            return .init(question: poll.question,
                         multipleChoice: poll.multipleChoice,
                         candidates: candidates,
                         expirationDate: poll.expiration,
                         totalNumberOfResponses: numberOfVoters)

        }

    }


    /// This manager produces the stream of what one place currently is, and says so again each time it changes.
    ///
    /// It watches the **location**, and not any message showing it, because that is where a sender's movement is written: `updateContentForContinuousLocation` writes
    /// the coordinate, the address and the count on the location and touches nothing else. It is also why one such stream can serve the same sharer in two
    /// discussions at once — a continuous location is a single object referenced by a message per discussion.
    private final class LocationStateStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<LocationState, PersistedLocation>, @unchecked Sendable {

        init(locationObjectID: NSManagedObjectID, context: NSManagedObjectContext) {
            let frc = PersistedLocation.getFetchedResultsController(objectID: locationObjectID, within: context)
            super.init(frc: frc)
        }

        /// No location left means sharing is over, which is said with a state carrying no coordinate rather than by falling silent.
        override func createModel(fetchedObjects: [PersistedLocation]) throws -> LocationState {
            guard let location = fetchedObjects.first else {
                return .init(coordinate: nil, address: nil, expiration: nil)
            }
            return .init(coordinate: .init(latitude: location.latitude, longitude: location.longitude),
                         address: location.address,
                         expiration: location.sharingExpiration)
        }

    }


    /// The cells of the discussion following their model, all of them fed by one controller. See ``TheMessagesOfTheCellsFollowing``.
    ///
    /// **The controller is asked about one set of cells at a time**, the cells as they are when it starts, so a cell that appears and goes while it is busy is
    /// never asked about. A fast scroll creates and abandons hundreds of cells, and when each had a controller of its own, every one of them was fetched and
    /// modelled on the background context, in order, while the cells still on the screen waited behind them.
    @MainActor
    private final class TheCellsFollowingTheirModel {

        private let theMessages: TheMessagesOfTheCellsFollowing
        private var cells = [UUID: TheMessagesOfTheCellsFollowing.ACell]()
        private var isAskingTheController = false
        private var theCellsChangedWhileItWasAsked = false

        init(context: NSManagedObjectContext) {
            self.theMessages = TheMessagesOfTheCellsFollowing(context: context)
        }

        func follow(_ messageObjectID: NSManagedObjectID) -> (streamUUID: UUID, stream: AsyncStream<SingleDiscussionCellView.Model>) {
            // A cell only ever needs the latest model.
            let (stream, continuation) = AsyncStream.makeStream(of: SingleDiscussionCellView.Model.self, bufferingPolicy: .bufferingNewest(1))
            let streamUUID = UUID()
            cells[streamUUID] = .init(messageObjectID: messageObjectID, continuation: continuation)
            theMessages.aCellIsFollowing(streamUUID)
            asksTheControllerIfNotAlreadyDoingSo()
            return (streamUUID, stream)
        }

        func stopsFollowing(_ streamUUID: UUID) {
            guard let cell = cells.removeValue(forKey: streamUUID) else { return }
            theMessages.aCellHasStoppedFollowing(streamUUID)
            cell.continuation.finish()
            // Asked again even for a cell that went, so that the controller stops watching messages nobody shows.
            asksTheControllerIfNotAlreadyDoingSo()
        }

        private func asksTheControllerIfNotAlreadyDoingSo() {
            guard !isAskingTheController else {
                theCellsChangedWhileItWasAsked = true
                return
            }
            isAskingTheController = true
            Task {
                defer { isAskingTheController = false }
                repeat {
                    theCellsChangedWhileItWasAsked = false
                    await theMessages.fetchesTheMessages(of: cells)
                } while theCellsChangedWhileItWasAsked
            }
        }

    }


    /// **One controller for the messages of every cell following its model**, which it finds by primary key, and the message each one replies to.
    ///
    /// The second is watched because a cell quotes the message it replies to, and nothing about the quoting row changes when the quoted one does: opening a
    /// read-once message left every reply to it saying *Ephemeral message*. A reply that arrives before the message it answers is covered as well: when that
    /// message arrives, the reply's own row changes, its relationship being set then, and the reply names it from then on.
    ///
    /// Touched on the queue of the context only, except for the cells still following, which are under a lock so that a cell gone while a model is being built
    /// for it is skipped.
    private final class TheMessagesOfTheCellsFollowing: NSObject, NSFetchedResultsControllerDelegate, @unchecked Sendable {

        struct ACell: Sendable {
            let messageObjectID: NSManagedObjectID
            let continuation: AsyncStream<SingleDiscussionCellView.Model>.Continuation
        }

        private let context: NSManagedObjectContext
        private let controller: NSFetchedResultsController<PersistedMessage>
        private let theCellsStillFollowing = OSAllocatedUnfairLock(initialState: Set<UUID>())

        /// The cells as they were the last time the controller was asked.
        private var cells = [UUID: ACell]()
        /// The last model sent for each message followed, which a second cell following the same message is given, and against which a change is compared.
        private var lastModels = [NSManagedObjectID: SingleDiscussionCellView.Model]()
        /// The message each message followed replies to, read off the messages once fetched.
        private var theMessageEachRepliesTo = [NSManagedObjectID: NSManagedObjectID]()
        /// What the controller was last asked for, so that it is not asked again for the same set.
        private var theObjectIDsFetched = Set<NSManagedObjectID>()
        /// The messages the controller reported as changed, until it says it is done.
        private var theObjectIDsChanged = Set<NSManagedObjectID>()

        private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "TheMessagesOfTheCellsFollowing")

        init(context: NSManagedObjectContext) {
            self.context = context
            self.controller = PersistedMessage.getFetchedResultsControllerForMessages(withObjectIDs: [], within: context)
            super.init()
            controller.delegate = self
        }

        func aCellIsFollowing(_ streamUUID: UUID) {
            theCellsStillFollowing.withLock { _ = $0.insert(streamUUID) }
        }

        func aCellHasStoppedFollowing(_ streamUUID: UUID) {
            theCellsStillFollowing.withLock { _ = $0.remove(streamUUID) }
        }

        private func isStillFollowing(_ streamUUID: UUID) -> Bool {
            theCellsStillFollowing.withLock { $0.contains(streamUUID) }
        }

        /// Has the controller watch the messages of these cells, and gives each cell that is new its model.
        func fetchesTheMessages(of cellsNow: [UUID: ACell]) async {
            await context.perform { [self] in
                let theNewCells = cellsNow.filter({ cells[$0.key] == nil })
                cells = cellsNow
                let followed = Set(cellsNow.values.map(\.messageObjectID))
                lastModels = lastModels.filter({ followed.contains($0.key) })
                theMessageEachRepliesTo = theMessageEachRepliesTo.filter({ followed.contains($0.key) })
                fetchesWhatIsFollowed()
                for (streamUUID, cell) in theNewCells where isStillFollowing(streamUUID) {
                    if lastModels[cell.messageObjectID] == nil {
                        lastModels[cell.messageObjectID] = model(of: cell.messageObjectID)
                    }
                    guard let model = lastModels[cell.messageObjectID] else { continue }
                    cell.continuation.yield(model)
                }
            }
        }

        /// Points the controller at the messages followed and at the ones they reply to — fetching twice when a message just fetched replies to one that was
        /// not, the first fetch being what says so.
        private func fetchesWhatIsFollowed() {
            for _ in 0..<2 {
                let theObjectIDs = Set(cells.values.map(\.messageObjectID)).union(theMessageEachRepliesTo.values)
                if theObjectIDs != theObjectIDsFetched {
                    do {
                        try PersistedMessage.fetchesTheMessages(withObjectIDs: theObjectIDs, with: controller)
                        theObjectIDsFetched = theObjectIDs
                    } catch {
                        Self.logger.fault("Could not fetch the messages of the cells: \(error.localizedDescription, privacy: .public)")
                        assertionFailure()
                        return
                    }
                }
                guard learnsWhatTheyReplyTo() else { return }
            }
        }

        /// Reads which message each message followed replies to, and says whether one of them has not been fetched.
        private func learnsWhatTheyReplyTo() -> Bool {
            let followed = Set(cells.values.map(\.messageObjectID))
            for message in controller.fetchedObjects ?? [] where followed.contains(message.objectID) {
                theMessageEachRepliesTo[message.objectID] = message.messageRepliedTo?.objectID
            }
            return !Set(theMessageEachRepliesTo.values).isSubset(of: theObjectIDsFetched)
        }

        private func model(of messageObjectID: NSManagedObjectID) -> SingleDiscussionCellView.Model? {
            guard let message = try? context.existingObject(with: messageObjectID) as? PersistedMessage, !message.isDeleted else { return nil }
            return try? SingleDiscussionViewAppDataSource.createModel(of: message)
        }

        // MARK: NSFetchedResultsControllerDelegate

        func controller(_ controller: NSFetchedResultsController<any NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
            guard let message = anObject as? PersistedMessage else { return }
            theObjectIDsChanged.insert(message.objectID)
        }

        /// Builds again the model of every message followed that changed, or whose quoted message did, and sends it to its cells when it says something new.
        func controllerDidChangeContent(_ controller: NSFetchedResultsController<any NSFetchRequestResult>) {
            let changed = theObjectIDsChanged
            theObjectIDsChanged.removeAll()
            let followed = Set(cells.values.map(\.messageObjectID))
            let theRepliesToWhatChanged = theMessageEachRepliesTo.filter({ changed.contains($0.value) }).keys
            for messageObjectID in changed.intersection(followed).union(theRepliesToWhatChanged) {
                guard let model = model(of: messageObjectID), model != lastModels[messageObjectID] else { continue }
                lastModels[messageObjectID] = model
                for (streamUUID, cell) in cells where cell.messageObjectID == messageObjectID && isStillFollowing(streamUUID) {
                    cell.continuation.yield(model)
                }
            }
            // A reply whose message has just arrived names it now. Fetched in a block of its own rather than from inside the controller's own callback.
            if learnsWhatTheyReplyTo() {
                context.perform { [weak self] in self?.fetchesWhatIsFollowed() }
            }
        }

    }

}
