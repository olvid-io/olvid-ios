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

import UIKit
import SwiftUI
import ObvTypes
import ObvAppTypes
import ObvComposition
import ObvSettings
import ObvUICoreData
import ObvSingleDiscussion


/// Hosts the full SwiftUI implementation of the single discussion screen, ``ObvSingleDiscussion.SingleDiscussionView``.
///
/// This view controller is instantiated instead of the ``NewSingleDiscussionViewController`` when the beta-only "Discussion layout" setting
/// is set to `SwiftUI`. It is intentionally thin: it only exists to satisfy the UIKit navigation requirements expressed by the
/// ``SomeSingleDiscussionViewController`` protocol. Everything else is expected to be implemented within the `ObvSingleDiscussion` module.
final class SwiftUISingleDiscussionViewController: UIHostingController<SingleDiscussionView>, SomeSingleDiscussionViewController {

    let discussionId: ObvDiscussionIdentifier?
    let discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>
    let discussionPermanentID: DiscussionPermanentID
    let currentOwnedCryptoId: ObvCryptoId

    /// Owns the actions of the composition bar. That object references this controller weakly, see its documentation.
    private let composeActions: SwiftUISingleDiscussionComposeActions

    /// Owns the actions of the screen and of its cells that cannot be answered by the data source alone, because they present something, or because they concern the
    /// screen's own lifecycle. Weak reference to this controller, as above.
    private let screenAndCellActions: SwiftUISingleDiscussionActions

    /// The state of the composition bar is owned here, and not by the SwiftUI view, so that it outlives the evaluations of its body.
    private let composeViewSharedState: ComposeView.SharedState

    /// The way in for ⌘F, ⌘G and ⇧⌘G, which the responder chain delivers here because a responder must be a `UIResponder`. Held so that it outlives the evaluations of
    /// the view's body. Nothing is decided with it: see ``ObvSingleDiscussion.WhatTheFindShortcutsAsk``.
    private let findShortcuts = WhatTheFindShortcutsAsk()

    /// How the composition bar reaches the screen. Held here for the same reason ``findShortcuts`` is, and handed to ``composeActions`` below, the bar's own
    /// actions being what learns that the reply has been dropped. See ``ObvSingleDiscussion.WhatTheCompositionBarAsks``.
    private let compositionBar = WhatTheCompositionBarAsks()

    /// How this controller asks the screen to take the reader to a message: `scrollTo(messageObjectID:)`, and the message the app hands over when the screen is built.
    ///
    /// Owned here rather than by the view because the second of those is asked for **during `init`**, before there is a view to ask. The channel keeps the newest
    /// request, so it is delivered as soon as the list starts listening. See ``ObvSingleDiscussion.WhereTheReaderWantsToGo``.
    private let whereTheReaderWantsToGo = WhereTheReaderWantsToGo()

    weak var delegate: (any SingleDiscussionViewControllerDelegate)? {
        didSet {
            composeActions.delegate = delegate
            screenAndCellActions.delegate = delegate
        }
    }

    /// Throws if the discussion identifier or the owned identity cannot be determined, which may happen for a locked discussion.
    /// In that case, the caller is expected to fall back to the legacy ``NewSingleDiscussionViewController``.
    /// - Parameter messageToScrollTo: The message the reader asked to be taken to — a notification opened, or a result picked out of the global search — or nil to open
    /// where the discussion would open anyway. It reaches the screen through ``whereTheReaderWantsToGo`` rather than as an initial position, which is what lets one
    /// mechanism serve it, `scrollTo(messageObjectID:)`, a reply header and the search bar alike.
    init(discussion: PersistedDiscussion, dataSources: SingleDiscussionView.DataSources, actions: any SingleDiscussionAttachmentActions, composeViewDataSources: ComposeView.DataSources, messageToScrollTo: TypeSafeManagedObjectID<PersistedMessage>?) throws {
        guard let ownCryptoId = discussion.ownedIdentity?.cryptoId else {
            throw ObvError.couldNotDetermineOwnedIdentity
        }
        let discussionIdentifier = try discussion.discussionIdentifier
        self.discussionId = discussionIdentifier
        self.discussionObjectID = discussion.typedObjectID
        self.discussionPermanentID = discussion.discussionPermanentID
        self.currentOwnedCryptoId = ownCryptoId

        self.composeActions = SwiftUISingleDiscussionComposeActions(draftObjectID: discussion.draft.typedObjectID)
        self.screenAndCellActions = SwiftUISingleDiscussionActions(dataSourceActions: actions, messageReactionsViewDataSource: dataSources.messageReactionsViewDataSource, avatarViewDataSource: dataSources.cellViewDataSource)

        // Everything the composition bar needs, as the legacy screen builds it
        let initialParameters = ComposeViewParameters(
            defaultEmojiButton: ObvMessengerSettings.Emoji.defaultEmojiButton ?? ObvMessengerConstants.defaultEmoji,
            sendMessageShortcutType: .init(ObvMessengerSettings.Interface.sendMessageShortcutType))
        self.composeViewSharedState = ComposeView.SharedState(
            discussionIdentifier: discussionIdentifier,
            initialBody: discussion.draft.attributedBody,
            containerURLforTempFiles: ObvUICoreDataConstants.ContainerURL.forTempFiles.url,
            initialParameters: initialParameters)

        // The seeds of the first frame are computed here, in the owner of the views, and never within their init.
        let (initialModel, initialValues) = try dataSources.dataSource.getInitialSingleDiscussionViewModelAndValues(discussionIdentifier: discussionIdentifier)
        let initialComposeViewModel = composeViewDataSources.dataSource.getInitialComposeViewDataSourceModel(discussionIdentifier: discussionIdentifier)

        // Built once, here, so that the side effects of ComposeView.init are not repeated on every evaluation of the body of SingleDiscussionView.
        let composeBar = ComposeView(
            sharedState: composeViewSharedState,
            dataSources: composeViewDataSources,
            actions: composeActions,
            initialDataSourceViewModel: initialComposeViewModel,
            // This screen does not space the bar itself, where the legacy one keeps that space with a constraint of its own — so the bar is asked to keep it. On a
            // Mac that is the 20pt legacy leaves below it; elsewhere nothing, the home indicator providing the margin. It is inside the bar rather than under it so
            // that a file dropped in the gap is taken like any other. See `ComposeView.spaceKeptBelowTheBarOnThisPlatform`.
            spaceKeptBelowTheBar: ComposeView.spaceKeptBelowTheBarOnThisPlatform,
            // **And it must not animate a change of its own height on this screen**, where the legacy one may — this screen puts the bar in a
            // `safeAreaInset` and legacy writes `contentInset.bottom` by hand. Taken out on 2026-08-24 on the strength of one clean case and put
            // back the same evening on the strength of a worse one: sending a message with an attachment while the keyboard is up reparameterised
            // the list to 348pt and ran a 7,357pt scroll-to-the-end through it for 3.3 seconds. See `ComposeView.theBarsHeightMayBeAnimated`.
            theBarsHeightMayBeAnimated: false)

        super.init(rootView: SingleDiscussionView(
            discussionIdentifier: discussionIdentifier,
            dataSources: dataSources,
            // The wrapper, and not the injected actions: what a place needs done has to be presented, which only this controller can do.
            actions: screenAndCellActions,
            // The screen says when it appears and when it goes, rather than this controller saying it from `viewWillAppear` — see `screen-lifecycle.md`, step 31.
            screenActions: screenAndCellActions,
            initialModel: initialModel,
            initialValues: initialValues,
            composeBar: AnyView(composeBar),
            findShortcuts: findShortcuts,
            compositionBar: compositionBar,
            whereTheReaderWantsToGo: whereTheReaderWantsToGo,
            whenTheScreenHasFinishedArriving: whenTheScreenHasFinishedArriving))

        // Said before the screen exists, which the channel allows: it keeps the newest request under its lock, and hands it over the moment the list starts
        // listening. Saying it here rather than as an opening position is what keeps one mechanism for every jump — and the list drops its own entry intention when
        // it answers one, so the correction that would otherwise carry the discussion back to its end does not fight this.
        //
        // **That keeping is the channel's own doing and not the stream's**, which is worth knowing here because the comment that used to stand in this place said
        // otherwise: an `AsyncStream`'s buffer cannot hold anything before the stream exists, and for as long as this was believed, every discussion opened from a
        // notification while not already in the navigation stack opened at its end instead of on the message.
        if let messageToScrollTo {
            whereTheReaderWantsToGo.goTo(.objectID(messageToScrollTo.objectID))
        }

        self.composeActions.viewController = self
        // Step 60: dropping the reply from the bar has to put the message beside it back, and only the bar's own actions are told when that happens. See
        // `WhatTheCompositionBarAsks` for why the screen cannot see the button itself.
        self.composeActions.compositionBar = compositionBar
        // The bar's own state, so that what the `+` menu presents can close it to editing while it loads and put back whatever turned out to be text.
        self.composeActions.composeViewSharedState = composeViewSharedState
        self.screenAndCellActions.viewController = self
        // Esc drops the reply quote when the screen had nothing of its own to dismiss, and only the composition bar's actions hold the draft that takes.
        self.screenAndCellActions.composeActions = composeActions
        // The same state, for the same reason at the other end of the screen: what is dropped on the **messages** goes into the draft exactly as what is dropped on
        // the bar does — see `SingleDiscussionViewActions.userDroppedItemsOnTheMessages(discussionIdentifier:itemProviders:)`.
        self.screenAndCellActions.composeViewSharedState = composeViewSharedState
        // The title is **not** set here any more: `SingleDiscussionView` sets it with `navigationTitle`, from the header it follows, so it no longer goes stale when
        // a contact is renamed — and it is one fewer line to move when this controller goes. See `navigation-bar.md`, step 32a.
    }

    /// How the screen is told that the push which brought it in has finished — see ``WhenTheScreenHasFinishedArriving``, which says what the screen does with it.
    private let whenTheScreenHasFinishedArriving = WhenTheScreenHasFinishedArriving()


    /// **The one lifecycle line in this controller, and it reports rather than decides.** What is announced is a fact
    /// only UIKit has: for a push, this runs when the transition has completed. What it *means* is settled by the screen.
    ///
    /// **Safe to say twice**, and it is said twice: showing a photograph takes the screen out of the hierarchy and returning runs this again. The channel latches,
    /// so a second arrival is the same answer as the first.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        whenTheScreenHasFinishedArriving.theScreenHasFinishedArriving()
    }


    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - SomeSingleDiscussionViewController

    /// A file AirDropped onto this discussion, handed over by `ObvFlowController` once this screen is on top of the navigation stack.
    ///
    /// It goes the same way as a file chosen in the file browser, which is why there is nothing more to it here: closing the bar to editing while the file is copied,
    /// and opening it again however that ends, is already what that path does. The legacy screen writes those steps out again for AirDrop and arrives at the same
    /// place.
    func addAttachmentFromAirDropFile(at url: URL) {
        composeActions.aFileArrivedFromAnotherDevice(at: url)
    }

    /// Takes the reader to a message of this discussion, the screen being already on show.
    ///
    /// Asked for by `ObvFlowController` when it finds this discussion already in the navigation stack and pops back to it — opening a notification, or picking a result
    /// out of the global search. A message this screen does not hold moves nothing, silently, which is what the legacy screen does when it can resolve no index path.
    func scrollTo(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>) {
        whereTheReaderWantsToGo.goTo(.objectID(messageObjectID.objectID))
    }

    // MARK: - The keyboard's find shortcuts

    // Three overrides that decide nothing. The responder chain hands ⌘F, ⌘G and ⇧⌘G to `MainFlowViewController`, which passes them to whichever discussion is on top;
    // a responder has to be a `UIResponder`, so this is where they land, and all they do is say so. What each one *means* is answered inside the screen, in the same
    // place the search bar's own chevrons are — see `WhatTheFindShortcutsAsk`. This controller stays as thin as UIKit allows.

    override func find(_ sender: Any?) {
        findShortcuts.says(.find)
    }

    override func findNext(_ sender: Any?) {
        findShortcuts.says(.findNext)
    }

    override func findPrevious(_ sender: Any?) {
        findShortcuts.says(.findPrevious)
    }

    // MARK: - The Return keys of the composition bar

    /// ↩, ⇧↩ and ⌘↩ while the caret is in the composition bar. Each is a `UIKeyCommand` with `wantsPriorityOverSystemBehavior`, which is the only way a
    /// hardware Return reaches the bar: a key that produces a character is claimed by text input, so neither `onKeyPress` nor `keyboardShortcut` on the editor
    /// ever sees ↩ or ⇧↩, and a command without the flag is never offered them. With it, the command fires and the text is left untouched, so the bar decides what
    /// the key means — a send, a mention accepted, a newline — in one place, `ComposeView.SharedState.returnWasPressed(with:)`. The selectors are named after this
    /// class, UIKit sending a command's action to the first responder in the chain that implements it.
    ///
    /// Vended here rather than on the bar's own view, this screen building the bar itself where the legacy screen hosts it in a controller of its own. The cost
    /// is that a priority command takes Return from **every** text input on the screen, the search field included, which is what ``canPerformAction(_:withSender:)``
    /// is for.
    /// Built once: UIKit reads `keyCommands` about eighteen times per press, and the three commands never change.
    private let returnKeys: [UIKeyCommand] = {
        let returnKeys = [
            UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(SwiftUISingleDiscussionViewController.swiftUISingleDiscussionAnswersTheReturnKey)),
            UIKeyCommand(input: "\r", modifierFlags: .shift, action: #selector(SwiftUISingleDiscussionViewController.swiftUISingleDiscussionAnswersTheShiftReturnKey)),
            UIKeyCommand(input: "\r", modifierFlags: .command, action: #selector(SwiftUISingleDiscussionViewController.swiftUISingleDiscussionAnswersTheCommandReturnKey)),
        ]
        for command in returnKeys {
            command.wantsPriorityOverSystemBehavior = true
        }
        return returnKeys
    }()

    override var keyCommands: [UIKeyCommand]? {
        (super.keyCommands ?? []) + returnKeys
    }

    @objc private func swiftUISingleDiscussionAnswersTheReturnKey() {
        composeViewSharedState.returnWasPressed(with: .none)
    }

    @objc private func swiftUISingleDiscussionAnswersTheShiftReturnKey() {
        composeViewSharedState.returnWasPressed(with: .shift)
    }

    @objc private func swiftUISingleDiscussionAnswersTheCommandReturnKey() {
        composeViewSharedState.returnWasPressed(with: .command)
    }

    /// Refuses the three Return commands unless the composition bar's editor is the first responder, and leaves every other action to UIKit.
    ///
    /// A priority command would otherwise take Return in the search field too — measured on Catalyst on 2026-10-01, where refusing it there let the search behave
    /// normally and no command fired. UIKit asks about eighteen times per press, so the predicate is one read of the editor's text view and nothing else.
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        switch action {
        case #selector(swiftUISingleDiscussionAnswersTheReturnKey),
             #selector(swiftUISingleDiscussionAnswersTheShiftReturnKey),
             #selector(swiftUISingleDiscussionAnswersTheCommandReturnKey):
            return composeViewSharedState.isTheEditorTheFirstResponder
        default:
            return super.canPerformAction(action, withSender: sender)
        }
    }

    // MARK: - Esc with nothing focused

    /// A keyboard shortcut is found from the first responder, and when nothing has focus UIKit falls back to a controller that can take it. Without this, the
    /// screen's Esc button fired only while the caret was in the composition bar: measured on Catalyst on 2026-09-30, a reply quote went on Esc while typing and
    /// stayed once the reader had clicked on the messages. The legacy screen has the same override for the same reason. This decides nothing about what Esc means;
    /// `SingleDiscussionView` does.
    override var canBecomeFirstResponder: Bool {
        return true
    }

    // MARK: - Errors

    enum ObvError: Error {
        case couldNotDetermineOwnedIdentity
    }

}
