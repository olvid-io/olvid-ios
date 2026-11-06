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
import UIKit
import os.log
@preconcurrency import ObvUICoreData
import ObvAppCoreConstants
import ObvSettings
import OlvidUtils
@preconcurrency import ObvEngine // `ObvEngine` is not `Sendable`, as in the notification service extension
import ObvShareExtension
import SwiftUI
import ObvSharedDataSources
import ObvTypes
import CoreData
import ObvAppTypes
import ObvOwnedIdentityChooser
import ObvDiscussionChooser
import Intents
import ObvUI
import UniformTypeIdentifiers
import ObvCoreDataStack
import AVFoundation
import ObvCrypto

/// The main view controller for the Share Extension.
/// Handles authentication, initialization of the engine, and coordination between the authentication view and the share view.
@objc(ShareExtensionViewController)
final class ShareExtensionViewController: UIViewController {
    
    // MARK: - Properties
    
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: "ShareExtensionViewController"))

    /// Memory lines go to their own category, alongside the ones the preview views write, so that the whole run reads
    /// down a single stream. Ordering is what these lines are for, and a filter that has to merge two categories is a
    /// filter that can reorder them.
    private static let memoryLogger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "PreviewMemory")
    private let runningLog = RunningLogError()
    
    /// Errors thrown while initializing the share extension.
    private enum ObvError: LocalizedError {
        case couldNotFindAnyOwnedIdentity
        case couldNotInitializeObliviousEngine
        var errorDescription: String? {
            switch self {
            case .couldNotFindAnyOwnedIdentity: return "Cannot find any owned identity"
            case .couldNotInitializeObliviousEngine: return "Could not initialize the Oblivious Engine"
            }
        }
    }

    /// Manages local authentication (biometric or passcode)
    private let localAuthenticationDelegate: LocalAuthenticationDelegate = LocalAuthenticationManager()
    
    /// The Oblivious Engine instance, limited to sending capabilities only
    private var obvEngine: ObvEngine!
    
    /// Serial queue for all internal operations
    private let internalQueue = OperationQueue.createSerialQueue(name: "ShareExtensionViewController internal queue", qualityOfService: .userInitiated)
    
    /// Shared user defaults for app group communication
    private let userDefaults = UserDefaults(suiteName: ObvAppCoreConstants.appGroupIdentifier)
    
    /// The one-shot initialization, retained so a second caller *awaits the in-flight run* instead of
    /// returning straight away. `viewDidAppear` initializes and then authenticates, and it can fire while
    /// `viewDidLoad`'s initialization is still running — on macOS Catalyst it reliably does. A plain
    /// "already triggered" flag let that second caller skip ahead and try to authenticate before
    /// `initialize()` had created `localAuthenticationViewController`, so the optional-chained call did
    /// nothing at all and the extension sat forever on the authentication screen.
    private var initializationTask: Task<Void, Never>?
    
    /// Tracks the current authentication state
    private var isAuthenticated = false
    
    /// The hosting controller for the main share extension UI
    private var shareExtensionViewHostingController: ShareExtensionViewHostingController?
    
    /// The view controller handling local authentication
    private var localAuthenticationViewController: LocalAuthenticationViewController?
    
    /// Operation to wipe ephemeral messages after too many failed authentication attempts
    private var wipeOp: WipeAllReadOnceAndLimitedVisibilityMessagesAfterLockOutOperation?

    /// The notification observations, removed when the holder goes, which is when this controller goes.
    private var observationTokens: NotificationObservationTokens?

    /// Consumes App-database writes made by other processes (mainly the main app creating, renaming,
    /// archiving or deleting owned identities and discussions) so the extension's long-lived Core Data
    /// coordinator doesn't keep serving a stale row cache when building the profile/discussion pickers.
    /// Built once, after `ObvStack` is ready, and retained for the extension's process lifetime so it
    /// keeps observing `NSPersistentStoreRemoteChange` across successive share invocations.
    private var appHistoryMerger: ObvPersistentHistoryMerger?


    // MARK: - Lifecycle Methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        observeNotifications()
        Task {
            await initializeIfNeeded()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // A catch-all inside the window: if the 22.9 MB lands before this line, it belongs to UIKit putting the view
        // on screen rather than to anything the app scheduled.
        PreviewMemory.mark("outer.viewDidAppear")
        Task {
            await initializeIfNeeded()
            await authenticateIfRequired()
        }
    }
    
    /// Performs authentication if required based on the current authentication state
    private func authenticateIfRequired() async {
        if !self.isAuthenticated {
            await localAuthenticationViewController?.performLocalAuthentication(
                customPasscodePresentingViewController: self,
                uptimeAtTheTimeOfChangeoverToNotActiveState: nil)
        }
    }
    
    /// Observes system notifications to handle background transitions and lock screen scenarios
    private func observeNotifications() {
        observationTokens = NotificationObservationTokens([
            NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    // Drop the authenticated state on background so that a re-foreground always
                    // re-evaluates authentication (via `viewDidAppear` → `authenticateIfRequired()`),
                    // even if the dismissal below is delayed or bypassed. Without this, `isAuthenticated`
                    // stays `true` for the instance's lifetime and a reused/re-foregrounded controller
                    // would skip auth. For the `.none` policy this re-auth is a no-op.
                    self.isAuthenticated = false
                    if ObvMessengerSettings.Privacy.localAuthenticationPolicy.lockScreen {
                        // Cancel to close the view if the share extension enters background mode, to avoid staying authenticated indefinitely in background.
                        self.cancelRequest()
                    }
                    self.earlyAbortWipe()
                }
            },
        ])
    }
    
    /// Initializes the share extension exactly once. A caller arriving while initialization is already in
    /// flight waits for it to finish rather than returning early — see ``initializationTask``.
    @MainActor
    private func initializeIfNeeded() async {

        // Store the task *before* the first suspension point. This method is `@MainActor` and nothing
        // suspends between the check and the assignment, so two callers cannot both start an
        // initialization — which would build the stack and the engine twice.
        if let initializationTask {
            return await initializationTask.value
        }
        let initializationTask = Task { @MainActor in await self.initializeShowingErrorScreenOnFailure() }
        self.initializationTask = initializationTask
        await initializationTask.value

    }

    /// Runs ``initialize()``, putting the appropriate error screen up if it throws.
    @MainActor
    private func initializeShowingErrorScreenOnFailure() async {
        do {
            try await initialize()
        } catch {
            Self.logger.fault("📤 Could not initialize the ObvStack and Engine within the main share view controller: \(error.localizedDescription, privacy: .public)")
            // Our own `ObvError`s (no owned identity, engine init failure) mean the app must be launched.
            // Check them first: an `ObvError` bridges to an `NSError` whose `code` is the case ordinal,
            // which could otherwise collide with `migrationRequiredButNotEnabled` (code 1) below.
            let reason: ShareExtensionErrorView.Reason
            if error is ObvError {
                reason = .shouldLaunchTheApp
            } else if (error as NSError).code == CoreDataStackErrorCodes.migrationRequiredButNotEnabled.rawValue {
                reason = .shouldUpdateToLatestVersion
            } else {
                reason = .shouldLaunchTheApp
            }
            let errorView = ShareExtensionErrorView(reason: reason) { [weak self] in
                self?.cancelRequest()
            }
            displayContentController(content: UIHostingController(rootView: errorView))
            return
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.earlyAbortWipe()
    }
    
    /// If the share view is dismissed or put in background while a wipe operation is running, 
    /// we stop the operation to ensure enough time to save the context even if some messages were not deleted.
    /// The operation takes care to inform the app to finish the wipe.
    private func earlyAbortWipe() {
        // If `wipeOp` is nil, no wipe is in progress
        wipeOp?.earlyAbortWipe = true
    }
    
    /// Initializes the CoreData stack, Oblivious Engine, and all view controllers
    private func initialize() async throws {

        // **The share extension's process is reused between shares**, which was measured rather than assumed: a second
        // share four minutes after the first ran in the same pid, and its baseline was 18.2 MB against 8.8 MB. The
        // preview store is a singleton, so without this the pictures of the previous share would be charged against
        // the budget of this one.
        PreviewImageStore.shared.reset()

        // Initialize the CoreData Stack
        try ObvStack.initSharedInstance(transactionAuthor: ObvUICoreDataConstants.AppCategory.shareExtension.transactionAuthor, runningLog: runningLog, enableMigrations: false)

        // Build the App-DB persistent-history merger once, now that ObvStack is ready, and retain it
        // for the process lifetime so it keeps consuming `NSPersistentStoreRemoteChange` across
        // successive share invocations. Without this, the extension's long-lived coordinator serves a
        // stale row cache: profiles/discussions the main app has since added, renamed, archived or
        // deleted would still show their old state in the pickers. The merger also records this
        // consumer's history cursor in the shared token store, so the app's launch-time prune won't
        // delete history this extension still needs.
        if appHistoryMerger == nil {
            let mergerTargetContext = ObvStack.shared.newBackgroundContext()
            mergerTargetContext.automaticallyMergesChangesFromParent = true
            appHistoryMerger = ObvPersistentHistoryMerger(
                backgroundContext: mergerTargetContext,
                logSubsystem: ObvAppCoreConstants.logSubsystem,
                localTransactionAuthor: ObvUICoreDataConstants.AppCategory.shareExtension.transactionAuthor,
                contextCreator: ObvStack.shared,
                persistentStoreCoordinator: ObvStack.shared.persistentStoreCoordinator,
                tokenStore: ObvStack.historyConsumerTokenStore)
        }

        // Force-consume any App-database writes made by other processes before reading below. The merger
        // otherwise only warms the coordinator's row cache reactively, on `NSPersistentStoreRemoteChange`.
        // On a warm re-invocation (the share process is reused, so the coordinator is long-lived) this
        // closes the race where the main app has added/renamed/archived/deleted profiles or discussions
        // but that notification hasn't been delivered yet — without it, the reads below (owned-identity
        // check, initial pickers) would run against a stale row cache. No-op on a cold launch.
        await appHistoryMerger?.mergePendingTransactionsAndWait()

        // Initialize the Oblivious Engine
        try await initializeObliviousEngine(runningLog: runningLog)
        
        PreviewMemory.mark("initialize.engineUp")

        // Make sure at least one owned identity has been generated within the main app
        let allOwnedIdentities = try PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentities(within: ObvStack.shared.viewContext)
        guard !allOwnedIdentities.isEmpty else {
            throw ObvError.couldNotFindAnyOwnedIdentity
        }

        // If a conversation identifier is provided (e.g., from Siri Intent), pre-select that discussion
        let initialDiscussionIdentifiers: [ObvDiscussionIdentifier]
        let providedCryptoId: ObvCryptoId?

        if let conversationIdentifier = conversationIdentifier,
           let discussionIdentifier = ObvDiscussionIdentifier(conversationIdentifier),
           (try? PersistedDiscussion.isPersistedDiscussionExisting(discussionIdentifier: discussionIdentifier, within: ObvStack.shared.viewContext)) == true {
            let discussionIdentifiers = [discussionIdentifier]
            initialDiscussionIdentifiers = discussionIdentifiers
            providedCryptoId = Self.computeOwnedCryptoIdForChosenDiscussions(discussionIdentifiers)
        } else {
            initialDiscussionIdentifiers = []
            providedCryptoId = nil
        }

        // Resolve the selected owned identity up front so the view-model stream is always started with a
        // concrete, valid crypto id, keeping the data source a pure reflector of its `currentOwnedCryptoId`.
        // Prefer the provided (e.g. Siri) identity, then the app's latest current (non-hidden) identity if
        // it is still available, then the first available one.
        let initialCryptoId: ObvCryptoId?
        if let providedCryptoId, allOwnedIdentities.contains(where: { $0.cryptoId == providedCryptoId }) {
            initialCryptoId = providedCryptoId
        } else {
            let latestNonHiddenCryptoId = LatestCurrentOwnedIdentityStorage.shared.getLatestCurrentOwnedIdentityStoredSynchronously()?.nonHiddenCryptoId
            initialCryptoId = (allOwnedIdentities.first(where: { $0.cryptoId == latestNonHiddenCryptoId }) ?? allOwnedIdentities.first)?.cryptoId
        }

        // Keep the initial From and To consistent. The two are resolved from different sources above:
        // `initialCryptoId` is filtered against the *non-hidden* owned identities, while the pre-selected
        // discussion only had to exist (`isPersistedDiscussionExisting` does not filter on hidden). A
        // discussion belonging to a hidden profile would therefore leave the compose view showing one
        // profile as the sender while addressing another profile's discussion — and since the send path
        // takes the owned identity from the discussion rather than from the displayed profile, the message
        // would actually go out as the hidden one.
        //
        // Unreachable today: the only source of a pre-selected discussion is a donated `INSendMessageIntent`,
        // and hidden profiles are never donated. But that invariant lives in the donation code, not here, so
        // enforce it locally rather than depending on it.
        let consistentInitialDiscussionIdentifiers = initialDiscussionIdentifiers.filter { $0.ownedCryptoId == initialCryptoId }

        let sharedState = SharedState(initialOwnedCryptoId: initialCryptoId,
                                      initialSelectedDiscussionIdentifiers: consistentInitialDiscussionIdentifiers,
                                      initialMediaQuality: ObvMessengerSettings.Discussions.mediaQualityForSharing)
        
        let actions = Actions(sharedState: sharedState, delegate: self)

        let dataSource = ShareExtensionViewAppDataSource(viewContext: ObvStack.shared.viewContext,
                                                         backgroundContext: ObvStack.shared.newBackgroundContext())
        let avatarDataSource = ObvAvatarViewAppDataSource(delegate: self)
        
        let dataSources = ShareExtensionView.DataSources(dataSource: dataSource,
                                                         avatarViewDataSource: avatarDataSource)
        
        let shareExtensionViewHostingController = ShareExtensionViewHostingController(sharedState: sharedState,
                                                                                      delegate: self,
                                                                                      dataSources: dataSources,
                                                                                      actions: actions,
                                                                                      obvEngine: self.obvEngine,
                                                                                      internalQueue: internalQueue,
                                                                                      userDefaults: userDefaults)
        
        self.addChild(shareExtensionViewHostingController)
        shareExtensionViewHostingController.didMove(toParent: self)
        self.shareExtensionViewHostingController = shareExtensionViewHostingController
        
        let localAuthenticationViewController = LocalAuthenticationViewController(localAuthenticationDelegate: localAuthenticationDelegate,
                                                                                  delegate: self)
        
        self.addChild(localAuthenticationViewController)
        localAuthenticationViewController.didMove(toParent: self)
        self.localAuthenticationViewController = localAuthenticationViewController
        
        PreviewMemory.mark("initialize.controllersBuilt")

        showAppropriateViewController()

        // The baseline nobody had. Two Core Data stacks, a persistent-history replay and a send-capable engine are up
        // before a single photograph is touched, and every argument about how large a preview may be is really an
        // argument about what is left after this line. Logged unconditionally, once, so the number is in the same
        // stream as the previews that spend it.
        Self.memoryLogger.notice("📤🧠 baseline after initialize() \(PreviewMemory.description(), privacy: .public)")
    }


    /// The extension is being asked to give memory back.
    ///
    /// There was no such override until this commit, so a warning has always arrived and been discarded — which means
    /// nobody knows whether one is ever delivered before jetsam acts, or whether the kill simply arrives first. That is
    /// worth knowing on its own: if this never fires in a run that dies, then a memory-pressure hook is not a defence
    /// and the bound has to hold without one.
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        Self.memoryLogger.error("📤🧠 memoryWarning \(PreviewMemory.description(), privacy: .public)")
        // A last resort, and deliberately not something the bound relies on: under the design this replaces, a warning
        // fired on every single page interaction, which makes it evidence of trouble rather than a defence against it.
        PreviewImageStore.shared.dropEverythingButTheCentre()
    }
    
    public class func computeOwnedCryptoIdForChosenDiscussions(_ discussionIdentifiers: [ObvDiscussionIdentifier]) -> ObvCryptoId? {
        let persistedDiscussions = discussionIdentifiers.compactMap { try? PersistedDiscussion.getPersistedDiscussion(discussionIdentifier: $0, within: ObvStack.shared.viewContext) }
        
        let discussionsToConsider = persistedDiscussions.filter({ $0.ownedIdentity != nil })
        let concernOwnedIdentities = Set(discussionsToConsider.compactMap({ $0.ownedIdentity }))
        
        if concernOwnedIdentities.count > 1 {
            // We shouldn't be able to receive discussions from multiple owned identities here
            return nil
        }
        
        var updatedCryptoId: ObvCryptoId?
        
        if let concernOwnedIdentity = concernOwnedIdentities.first {
            /* When using the share extension via Siri (where the user selects a specific discussion to share with),
             * the chosen discussion will already be determined. We then pick the owned identity associated
             * with that discussion.
             */
            updatedCryptoId = concernOwnedIdentity.cryptoId
        }
        
        return updatedCryptoId
    }
    
    /// Displays the appropriate view controller based on authentication state.
    /// Shows authentication view if not authenticated, otherwise shows the share view.
    private func showAppropriateViewController() {
        
        guard let localAuthenticationViewController = localAuthenticationViewController else { assertionFailure(); return }
        guard let shareViewHostingController = shareExtensionViewHostingController else { assertionFailure(); return }

        let vcToShow = !self.isAuthenticated ? localAuthenticationViewController : shareViewHostingController
        let vcToHide = self.isAuthenticated ? localAuthenticationViewController : shareViewHostingController

        guard vcToShow.view.superview == nil else {
            // Nothing to do, the vc to show is already shown
            return
        }
        
        self.view.addSubview(vcToShow.view)
        vcToShow.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.pinAllSidesToSides(of: vcToShow.view)
        vcToShow.view.alpha = 0.0

        guard vcToHide.view.superview != nil else {
            // There is no vc to hide, we only show the vc to show without animation
            vcToShow.view.alpha = 1.0
            return
        }
        
        // If we reach this point, we can animate the transition from the vc to hide to the vc to show
        
        assert(vcToHide.view.superview != nil)
        assert(vcToShow.view.superview != nil)

        UIView.animate(withDuration: 0.1) {
            vcToShow.view.alpha = 1.0
        } completion: { finished in
            vcToHide.view.removeFromSuperview()
        }
    }
}

// MARK: - LocalAuthenticationViewControllerDelegate & WipeAllReadOnceAndLimitedVisibilityMessagesAfterLockOutOperationDelegate

extension ShareExtensionViewController: LocalAuthenticationViewControllerDelegate, WipeAllReadOnceAndLimitedVisibilityMessagesAfterLockOutOperationDelegate {

    /// Called when the user successfully authenticates
    /// - Parameter authenticationWasPerformed: Indicates whether authentication was actually performed or bypassed
    func userLocalAuthenticationDidSucceed(authenticationWasPerformed: Bool) async {
        assert(Thread.isMainThread)
        self.isAuthenticated = true
        showAppropriateViewController()
    }
    
    /// Called when too many wrong passcode attempts cause a lockout.
    /// Initiates a wipe of ephemeral messages if configured to do so.
    func tooManyWrongPasscodeAttemptsCausedLockOut() async {
        assert(Thread.isMainThread)
        let flowId = FlowIdentifier()
        let obvContext = ObvStack.shared.newBackgroundContext(flowId: flowId)

        guard ObvMessengerSettings.Privacy.lockoutCleanEphemeral else { return }

        wipeOp = WipeAllReadOnceAndLimitedVisibilityMessagesAfterLockOutOperation(userDefaults: userDefaults,
                                                                                  appType: .shareExtension,
                                                                                  wipeType: .startWipeFromAppOrShareExtension,
                                                                                  delegate: self)
        guard let wipeOp = wipeOp else { assertionFailure(); return }

        wipeOp.viewContext = ObvStack.shared.viewContext
        wipeOp.obvContext = obvContext

        let saveOp = SaveContextOperation(userDefaults: userDefaults)
        saveOp.viewContext = ObvStack.shared.viewContext
        saveOp.obvContext = obvContext
        saveOp.addDependency(wipeOp)
        
        // Use addBarrierBlock to add operations from async context
        internalQueue.addBarrierBlock { [weak self] in
            guard let self else { return }
            self.internalQueue.addOperation(wipeOp)
            self.internalQueue.addOperation(saveOp)
        }
    }
    
    /// Records in user defaults that the extension failed to wipe all ephemeral messages before a certain date.
    /// This allows the main app to complete the wipe operation later.
    /// - Parameter timestampOfLastMessageToWipe: The timestamp of the last message that needs to be wiped
    ///
    /// `nonisolated` because the wipe operation calls it from a queue of its own, once the context is saved. The record
    /// is written and the Darwin notification posted right there, synchronously: the caller is typically a wipe
    /// aborted because the extension is going to the background or away, and a hop to the main actor might never run
    /// before the process is suspended, which would leave the main app unaware that read-once messages remain to be
    /// wiped. The suite is opened here rather than read from `userDefaults`, which is main-actor and not `Sendable`.
    nonisolated func setExtensionFailedToWipeAllEphemeralMessagesBeforeDateOnUserDefaults(timestampOfLastMessageToWipe: Date?) {
        guard let userDefaults = UserDefaults(suiteName: ObvAppCoreConstants.appGroupIdentifier) else { assertionFailure(); return }
        userDefaults.setExtensionFailedToWipeAllEphemeralMessagesBeforeDate(with: timestampOfLastMessageToWipe)
        ObvDarwinNotificationCenter.shared.post(ObvDarwinNotificationName.shareExtensionFailedToWipeAllEphemeralMessagesBeforeDate)
    }
}

/// Implementation of ShareExtensionViewActions protocol.
/// Handles user actions from the share extension UI.
@MainActor
private final class Actions: ShareExtensionViewActions {

    weak var delegate: ShareExtensionViewHostingControllerDelegate?
    
    let sharedState: SharedState
    
    init(sharedState: SharedState, delegate: ShareExtensionViewHostingControllerDelegate?) {
        self.sharedState = sharedState
        self.delegate = delegate
    }
    
    /// Called when the user selects a different owned identity/profile
    func userChoseProfile(_ view: ObvOwnedIdentityChooser.OwnedIdentityChooserNavigationStack, chosenOwnedCryptoId: ObvTypes.ObvCryptoId) async throws {
        guard chosenOwnedCryptoId != sharedState.selectedOwnedCryptoId else { return }
        
        sharedState.selectedOwnedCryptoId = chosenOwnedCryptoId
        sharedState.selectedDiscussionIdentifiers = []
    }
    
    /// Placeholder for editing current owned identity (not implemented in share extension)
    func userWantsToEditCurrentOwnedIdentity(_ view: ObvOwnedIdentityChooser.OwnedIdentityChooserNavigationStack, currentOwnedCryptoId: ObvTypes.ObvCryptoId) async { }
    
    /// Placeholder for adding new profile (not implemented in share extension)
    func userWantsToAddNewProfile(_ view: ObvOwnedIdentityChooser.OwnedIdentityChooserNavigationStack) async { }
    
    /// Called when the user selects discussions to share with
    func userChoseDiscussions(_ view: ObvDiscussionChooser.DiscussionChooserNavigationStack, chosenDiscussionIdentifiers: [ObvDiscussionIdentifier]) async throws {

        if let selectedOwnedCryptoIdToUpdate = ShareExtensionViewController.computeOwnedCryptoIdForChosenDiscussions(chosenDiscussionIdentifiers) {
            sharedState.selectedOwnedCryptoId = selectedOwnedCryptoIdToUpdate
        }

        sharedState.selectedDiscussionIdentifiers = chosenDiscussionIdentifiers
    }
    
    /// Called when the user wants to close/cancel the share extension
    func userWantsToCloseShare(from view: ObvShareExtension.ShareExtensionView) {
        delegate?.cancelRequest()
    }

    /// Called when the user switches between HD and SD. The view has already applied the choice to the
    /// shared state, so all that is left is to remember it for the next share.
    func userChoseMediaQuality(_ mediaQuality: ObvMediaQuality) {
        ObvMessengerSettings.Discussions.mediaQualityForSharing = mediaQuality
    }
    
    /// Called when the user taps the send button
    func userWantsToSendMessage(from view: ObvShareExtension.ShareComposeView,
                                shareableItems: [ObvShareExtension.SharedState.ShareableItem],
                                textBody: String,
                                from: ObvTypes.ObvCryptoId,
                                to: [ObvDiscussionIdentifier]) {
        sharedState.isSending = true
        
        // Call the delegate to send the messages
        Task {
            await delegate?.userWantsToSendMessages(
                shareableItems: shareableItems,
                textBody: textBody,
                mediaQuality: sharedState.mediaQuality,
                from: from,
                to: to
            )
        }
    }
}

// MARK: - ObvAvatarViewAppDataSourceDelegate

extension ShareExtensionViewController: ObvAvatarViewAppDataSourceDelegate {
    
    /// Fetches user data for avatar display (not implemented in share extension)
    nonisolated func getUserDataNow(ownedCryptoId: ObvTypes.ObvCryptoId, encodedServerKeyAndLabel: Data?) async throws -> Data? {
        assertionFailure("Not expected to be called in the share extension")
        return nil
    }

    /// Provides access to perform background tasks on Core Data contexts.
    ///
    /// `nonisolated`, as the avatar data source calls it from its own tasks, and the shared stack needs no view
    /// controller state.
    nonisolated func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        ObvStack.shared.performBackgroundTask(block)
    }
    
}

// MARK: - Oblivious Engine Initialization

extension ShareExtensionViewController {
    
    /// Initializes the Oblivious Engine in send-only mode for the share extension
    /// - Parameter runningLog: Log object to track initialization errors
    private func initializeObliviousEngine(runningLog: RunningLogError) async throws {
        do {
            obvEngine = try await ObvEngine.startLimitedToSending(
                logPrefix: "LimitedEngine",
                sharedContainerIdentifier: ObvAppCoreConstants.appGroupIdentifier,
                mainContainerURL: ObvUICoreDataConstants.ContainerURL.mainEngineContainer.url,
                supportBackgroundTasks: ObvMessengerConstants.isRunningOnRealDevice,
                remoteNotificationByteIdentifierForServer: ObvAppCoreConstants.remoteNotificationByteIdentifierForServer,
                appType: .shareExtension,
                runningLog: runningLog
            )
            Self.logger.info("📤 The Oblivious Engine was initialized")
        } catch {
            throw ObvError.couldNotInitializeObliviousEngine
        }
        
    }
}

// MARK: - Extension Context Management

extension ShareExtensionViewController {
    
    /// Cancels the share extension request with an error
    /// - Parameter error: The error that caused the cancellation
    private func cancelRequest(error: any Error) {
        extensionContext?.cancelRequest(withError: error)
    }
    
    /// Completes the share extension request successfully
    private func completeRequest() {
        shareExtensionViewHostingController = nil
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}

// MARK: - ShareExtensionViewHostingControllerDelegate

extension ShareExtensionViewController: ShareExtensionViewHostingControllerDelegate {

    /// Returns the first input item from the extension context (contains shared content)
    var firstInputItems: NSExtensionItem? {
        extensionContext?.inputItems.first as? NSExtensionItem
    }

    /// Returns the conversation identifier if the share was initiated from a Siri intent
    var conversationIdentifier: String? {
        guard let intent = extensionContext?.intent else { return nil }
        guard let sendMessageIntent = intent as? INSendMessageIntent else { return nil }
        return sendMessageIntent.conversationIdentifier
    }

    /// Cancels the share extension request
    func cancelRequest() {
        Self.logger.info("📤 Cancel request.")
        completeRequest()
    }

    /// Presents the "nothing to share" error screen (e.g. when the shared files could not be prepared),
    /// dismissing the extension when the user acknowledges it.
    func hostingControllerFoundNothingToShare() {
        Self.logger.fault("📤 Nothing to share.")
        let errorView = ShareExtensionErrorView(reason: .nothingToShare) { [weak self] in
            self?.cancelRequest()
        }
        displayContentController(content: UIHostingController(rootView: errorView))
    }

    /// Forwards the send messages request to the hosting controller
    func userWantsToSendMessages(
        shareableItems: [ObvShareExtension.SharedState.ShareableItem],
        textBody: String,
        mediaQuality: ObvMediaQuality,
        from: ObvTypes.ObvCryptoId,
        to discussionIdentifiers: [ObvDiscussionIdentifier]
    ) async {
        await shareExtensionViewHostingController?.userWantsToSendMessages(
            shareableItems: shareableItems,
            textBody: textBody,
            mediaQuality: mediaQuality,
            from: from,
            to: discussionIdentifiers
        )
    }

}

/// Protocol defining the delegate methods for ShareExtensionViewHostingController.
///
/// Main-actor isolated: its only implementation is the view controller, and every caller is a view controller or
/// the actions object, which are main-actor too.
@MainActor
protocol ShareExtensionViewHostingControllerDelegate: AnyObject {
    /// Provides access to the first input item containing shared content
    var firstInputItems: NSExtensionItem? { get }
    
    /// Provides the conversation identifier if sharing from a Siri intent
    var conversationIdentifier: String? { get }

    /// Cancels the share extension request
    func cancelRequest()

    /// Called when the shared files were provided but none could be prepared for sharing, so the extension
    /// should present the "nothing to share" error screen instead of an empty compose view.
    func hostingControllerFoundNothingToShare()

    /// Sends messages to the selected discussions
    func userWantsToSendMessages(
        shareableItems: [ObvShareExtension.SharedState.ShareableItem],
        textBody: String,
        mediaQuality: ObvMediaQuality,
        from: ObvTypes.ObvCryptoId,
        to: [ObvDiscussionIdentifier]
    ) async
}

// MARK: - ShareExtensionViewHostingController

/// The main hosting controller for the SwiftUI-based share extension view
final private class ShareExtensionViewHostingController: UIHostingController<ShareExtensionView> {
    
    // MARK: - Properties
    
    private static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: "ShareExtensionViewHostingController"))
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: "ShareExtensionViewHostingController"))

    /// See the identically-named logger on ``ShareExtensionViewController``: one category for every memory line, so a
    /// run reads down a single stream in the order things happened.
    private static let memoryLogger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "PreviewMemory")

    /// Shared state object for the share extension UI
    private let sharedState: SharedState
    
    /// Unique identifier for this flow
    private let flowId: FlowIdentifier
    
    /// The Oblivious Engine instance (send-only mode)
    private let obvEngine: ObvEngine
    
    /// Background context for Core Data operations
    private let obvContext: ObvContext
    
    /// Serial queue for all internal operations
    private let internalQueue: OperationQueue
    
    /// Shared user defaults for app group communication
    private let userDefaults: UserDefaults?

    /// Provider of FyleJoin objects (file attachments) from loaded item providers
    private var fyleJoinsProvider: FyleJoinsProvider?
    
    /// Manager for creating hard links to files
    private var hardLinksToFylesManager: HardLinksToFylesManager!
    
    /// Cache of link metadata for URLs in the shared content
    private var cacheOfLinkMetadata = [URL: ObvLinkMetadata]()
    
    /// Helper for loading item providers asynchronously
    private let loadItemProviderHelper = LoadItemProviderHelper()

    /// Delegate for communication with the parent view controller
    weak var delegate: ShareExtensionViewHostingControllerDelegate?
    
    // MARK: - Initialization
    // MARK: - Initialization
    
    /// Initializes the hosting controller with all required dependencies
    init(sharedState: SharedState,
         delegate: ShareExtensionViewHostingControllerDelegate,
         dataSources: ShareExtensionView.DataSources,
         actions: any ShareExtensionViewActions,
         obvEngine: ObvEngine,
         internalQueue: OperationQueue,
         userDefaults: UserDefaults?) {
        
        self.sharedState = sharedState
        self.delegate = delegate
        self.flowId = FlowIdentifier()
        self.obvContext = ObvStack.shared.newBackgroundContext(flowId: self.flowId)
        // `obvContext` is the send context and is *not* a target of the app-history merger, so it can
        // hold a stale row cache when the main app modified discussions/profiles from another process.
        // A zero staleness interval makes every fault it fulfills bypass the (possibly stale) row cache
        // and read current values from the store, so message creation always sees the latest state.
        self.obvContext.context.stalenessInterval = 0
        self.obvEngine = obvEngine
        self.internalQueue = internalQueue
        self.userDefaults = userDefaults
        
        // Compute the "first paint" model here (once, on the main actor) rather than inside the view's
        // init, keeping the SwiftUI view construction cheap and free of Core Data I/O.
        let initialModel = dataSources.dataSource.getInitialShareExtensionViewModel(currentOwnedCryptoId: sharedState.selectedOwnedCryptoId)
        let shareExtensionView = ShareExtensionView(sharedState: sharedState,
                                                    dataSources: dataSources,
                                                    actions: actions,
                                                    initialModel: initialModel)

        super.init(rootView: shareExtensionView)
        
        // Initialize the coordinators that allow to compute thumbnails
        self.hardLinksToFylesManager = HardLinksToFylesManager.makeHardLinksToFylesManagerForShareExtension()
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    /// Reported once, because the first layout of the SwiftUI hierarchy happens on its own runloop turn and is the
    /// one step in the gap that source order says nothing about.
    private var theFirstLayoutHasBeenReported = false

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !theFirstLayoutHasBeenReported else { return }
        theFirstLayoutHasBeenReported = true
        PreviewMemory.mark("hosting.firstLayout")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        PreviewMemory.mark("hosting.viewDidLoad")
        
        Task {
            do {
                try await initializeOperations()
            } catch {
                Self.logger.fault("Failed to load attachments: \(error.localizedDescription, privacy: .public)")

                // Every error this can throw — no input item, no attachment, nothing loadable — means the
                // same thing to the user, and it is what the "nothing to share" screen already says. Show it
                // rather than dismissing silently, which left the share sheet vanishing with no explanation.
                // It also matches the hardlink path, which already shows this screen when files were
                // provided but none could be prepared. The screen dismisses the extension on OK.
                delegate?.hostingControllerFoundNothingToShare()
            }
        }
    }
    
    /// Error types specific to the share extension operations
    private enum ObvError: LocalizedError {
        case noInputItemToProcess
        case noAttachmentToProcess
        case couldNotLoadAnyAttachment
        case couldNotCreateAllMessagesToSend
        case couldNotResolveAllChosenDiscussions
        case sendUnprocessedMessageOperationFailed
        case saveContextOperationFailedWhileSending
        var errorDescription: String? {
            switch self {
            case .noInputItemToProcess: return "No input item to process"
            case .noAttachmentToProcess: return "No attachment to process"
            case .couldNotLoadAnyAttachment: return "Could not load any attachment"
            case .couldNotCreateAllMessagesToSend: return "Could not create all messages to send"
            case .couldNotResolveAllChosenDiscussions: return "Could not resolve all the chosen discussions"
            case .sendUnprocessedMessageOperationFailed: return "SendUnprocessedPersistedMessageSentOperation failed"
            case .saveContextOperationFailedWhileSending: return "SaveContextOperation failed in sendUnprocessedMessageToSend"
            }
        }
    }
    
    // MARK: - Initialization Operations
    
    /// Queues operations that can be executed independently of the discussion selected by the user.
    /// The results of these operations will be used later when sending messages.
    /// The RequestHardLinksToFylesOperation is not required to send messages, but is used to show previews of attachments in ShareExtensionView.
    private func initializeOperations() async throws {

        // Entered on a `Task` from `viewDidLoad`, so this is a *later* runloop turn than the baseline line — which is
        // exactly why the gap between the two cannot be read off the source.
        PreviewMemory.mark("operations.begin")

        // Load the item providers
        
        self.sharedState.isLoading = true
        
        guard let content = delegate?.firstInputItems else {
            // Balance the `isLoading = true` above and throw, so the caller's `catch` dismisses the
            // extension. Returning early here would leave the UI stuck on the loading placeholder.
            Self.logger.fault("No input item to process within the share extension")
            self.sharedState.isLoading = false
            throw ObvError.noInputItemToProcess
        }
        let logger = Self.logger

        PreviewMemory.mark("operations.gotInputItems")

        guard let itemProviders = content.attachments else {
            Self.logger.fault("No attachment to process within the share extension")
            Task { @MainActor in
                self.sharedState.isLoading = false
            }
            throw ObvError.noAttachmentToProcess
        }
        
        // Bracketing the load, because `LoadItemProviderHelper` starts one task per provider with no concurrency cap,
        // and for a provider registered as exactly `public.image` it goes through `UIImage` and `pngData()` — a full
        // bitmap *and* a full PNG, per item, at the same time. Photos-app JPEGs take the disk-to-disk path and cost
        // nothing, so whether this matters depends entirely on which app the reader shared from. Two lines say which.
        Self.memoryLogger.notice("📤🧠 load.begin providers=\(itemProviders.count, privacy: .public) \(PreviewMemory.description(), privacy: .public)")
        let loadedItemProviders = try await self.loadItemProviderHelper.load(itemProviders, source: .shareExtension, progressProvider: nil)
        Self.memoryLogger.notice("📤🧠 load.end   loaded=\(loadedItemProviders.count, privacy: .public) \(PreviewMemory.description(), privacy: .public)")

        guard !loadedItemProviders.isEmpty else {
            Self.logger.fault("No attachment to process within the share extension")
            self.sharedState.isLoading = false
            throw ObvError.couldNotLoadAnyAttachment
        }
        
        // Compute Fyle objects and text strings from LoadedItemProvider objects
        
        let op1 = CreateFylesFromLoadedFileRepresentationsOperation(loadedItemProviders: loadedItemProviders)
        self.fyleJoinsProvider = op1
        op1.viewContext = ObvStack.shared.viewContext
        op1.obvContext = obvContext
        op1.completionBlock = { [weak self, weak op1] in
            // Capture the operation weakly to avoid an op → completionBlock → op retain cycle. It is alive
            // while its own completion runs, so the guard succeeds.
            guard let self, let op1 else { return }
            logger.info("📤 Create Fyles From Loaded File Representations Operation done.")
            guard let bodyTexts = op1.bodyTexts else { assertionFailure(); return }
            Task { @MainActor in
                self.sharedState.textBody = bodyTexts.joined(separator: "\n\n")
            }
        }
        internalQueue.addOperation(op1) // Don't wait
        
        // Check if we have files to process
        let hasFiles = !loadedItemProviders.toAttach.isEmpty
        
        // Check if we will fetch link previews
        let willFetchLinkPreview = ObvMessengerSettings.Discussions.attachLinkPreviewToMessageSent
        
        // If there are no files and no link preview to fetch, stop loading now
        if !hasFiles && !willFetchLinkPreview {
            Task { @MainActor in
                self.sharedState.isLoading = false
            }
        }
        
        // Create hard links to files for previewing attachments
        let op2 = RequestHardLinksToFylesOperation(hardLinksToFylesManager: hardLinksToFylesManager, fyleJoinsProvider: op1)
        op2.completionBlock = { [weak self, weak op2] in
            // Capture the operation weakly to avoid an op → completionBlock → op retain cycle. It is alive
            // while its own completion runs, so the guard succeeds.
            guard let self, let op2 else { return }
            logger.info("📤 Request HardLinks To Fyle Operation done.")

            // Called on the paths where there are no attachments to preview/share. Files *were* provided
            // (`hasFiles`) but none could be prepared, so surface the "nothing to share" error screen. When
            // no files were provided (a text- or URL-only share) reaching here is normal, so we only leave
            // the loading state and let the text/link path proceed.
            let handleNothingToShare = { @MainActor in
                // Leave the loading state alone while a link preview is still being fetched. `op4` resolves
                // it either way — through `addLinkMetadata` on success, explicitly on failure — and clearing
                // it here would empty `shareableItems` (see `isLoading`'s `didSet`) and show the "nothing to
                // share" empty state for the whole duration of the fetch. That is what sharing a web page
                // looked like: this operation finds no hardlink, because a URL is pasted rather than
                // attached, and runs before `op4` on the same serial queue.
                if !willFetchLinkPreview {
                    self.sharedState.isLoading = false
                }
                if hasFiles {
                    self.delegate?.hostingControllerFoundNothingToShare()
                }
            }

            guard let indexedHardlinks = op2.indexedHardlinks else {
                assertionFailure()
                Task { @MainActor in handleNothingToShare() }
                return
            }
            guard !indexedHardlinks.isEmpty else {
                logger.fault("📤 The set of hardlinks is empty. Nothing to share.")
                Task { @MainActor in handleNothingToShare() }
                return
            }

            // Build the HardLink values while preserving each one's originating FyleJoin index, so that
            // selection (`selectedHardlinkIndices.contains(fyleJoin.index)`) and transcoding resolve the
            // correct file even when some fyles produced no hardlink.
            let hardlinkToShare = indexedHardlinks.compactMap { indexed -> SharedState.HardLink? in
                guard let hardlink = indexed.hardlink else { return nil }
                return SharedState.HardLink(index: indexed.index, hardlinkToFyle: hardlink)
            }

            guard !hardlinkToShare.isEmpty else {
                logger.fault("📤 The set of hardlinks is empty. Nothing to share.")
                Task { @MainActor in handleNothingToShare() }
                return
            }
            Task { @MainActor in
                self.sharedState.setHardlinks(hardlinkToShare)
            }
        }
        op2.addDependency(op1)
        internalQueue.addOperation(op2) // Don't wait

        // If there is a URL in the loaded item providers, fetch a "link preview" for it
        // so we can add it to the message once sent.
        
        if ObvMessengerSettings.Discussions.attachLinkPreviewToMessageSent {
            let op4 = FetchAndCacheObvLinkMetadataForFirstURLInLoadedItemProvidersOperation(
                loadedItemProvidersToPaste: loadedItemProviders.toPaste,
                currentURLsInCache: Set(cacheOfLinkMetadata.keys))
            op4.addDependency(op1)
            op4.completionBlock = { [weak self, weak op4] in
                // Capture the operation weakly to avoid an op → completionBlock → op retain cycle. It is
                // alive while its own completion runs, so the guard succeeds.
                guard let op4 else { return }
                guard let (url, linkMetadata) = op4.fetchedMetadata else {
                    // No link metadata could be fetched. Leave the loading state (only if still loading, to
                    // avoid clobbering already-loaded items) so the UI doesn't stay stuck on the loading
                    // placeholder — e.g. when the only shared item is a URL whose preview fetch failed and no
                    // files were attached, nothing else would reset `isLoading`.
                    Task { @MainActor in
                        guard let self, self.sharedState.isLoading else { return }
                        self.sharedState.isLoading = false
                    }
                    return
                }
                Task { @MainActor in
                    guard let self else { return }
                    self.cacheOfLinkMetadata[url] = linkMetadata
                    self.sharedState.addLinkMetadata(linkMetadata: linkMetadata, for: url)
                }
            }
            internalQueue.addOperation(op4)
        }
                
        // Note: the global obvContext is *not* saved at this point. 
        // We will save it later in createAllMessagesToSend() to ensure atomicity.
        
    }
}

// MARK: - Message Sending

extension ShareExtensionViewHostingController {
    
    /// Called when the user wants to send messages to selected discussions.
    /// This method orchestrates the entire sending process: filtering attachments, creating messages, and sending them via the engine.
    /// - Parameters:
    ///   - shareableItems: The items (files and links) selected by the user to share
    ///   - textBody: The message text entered by the user
    ///   - mediaQuality: The quality level for media (photos/videos) - HD or SD
    ///   - from: The owned crypto ID to send from
    ///   - to: The discussions to send the message to
    func userWantsToSendMessages(shareableItems: [ObvShareExtension.SharedState.ShareableItem],
                                 textBody: String,
                                 mediaQuality: ObvMediaQuality,
                                 from: ObvTypes.ObvCryptoId,
                                 to discussionIdentifiers: [ObvDiscussionIdentifier]) async {

        assert(Thread.isMainThread)

        Self.logger.info("📤 Sending message")

        guard !discussionIdentifiers.isEmpty else {
            assertionFailure();
            sharedState.isSending = false
            return
        }

        let messageSentPermanentIDs: [MessageSentPermanentID]
        /// How many attachments each posted message carries, i.e. the per-message denominator of the upload progress.
        let attachmentCountPerMessage: Int
        do {

            // Convert discussion identifiers to persisted discussion objects. If any chosen discussion can no
            // longer be resolved (e.g. it was deleted between selection and sending), abort rather than
            // silently sending to a subset — which would look like a success while dropping recipients.
            let persistedDiscussions = discussionIdentifiers.compactMap {
                try? PersistedDiscussion.getPersistedDiscussion(discussionIdentifier: $0, within: ObvStack.shared.viewContext)
            }

            guard persistedDiscussions.count == discussionIdentifiers.count else {
                assertionFailure("Resolved \(persistedDiscussions.count) discussion(s) out of \(discussionIdentifiers.count) chosen")
                throw ObvError.couldNotResolveAllChosenDiscussions
            }

            // Extract the indices of hardlinks from the user-selected shareable items
            let selectedHardlinkIndices = Set(shareableItems.compactMap { item -> Int? in
                guard case .hardlink(let hardlink) = item else { return nil }
                return hardlink.index
            })

            // Filter fyleJoins to only include those with indices present in the selected shareable items
            // This ensures we only send the files the user wants to share
            var fyleJoins = fyleJoinsProvider?.fyleJoins?.filter { fyleJoin in
                selectedHardlinkIndices.contains(fyleJoin.index)
            } ?? []
            
            // If media quality is set to standard and we have photos/videos, transcode them
            if mediaQuality == .standard {
                fyleJoins = try await transcodeFyleJoinsIfNeeded(fyleJoins)
            }
            
            // Extract link metadata items from shareable items
            let linkMetadatas = shareableItems.compactMap { item -> ObvLinkMetadata? in
                guard case .linkMetadata(_, let metadata) = item else {
                    return nil
                }

                return metadata
            }
            
            // If link preview attachment is enabled and we have link metadata, create a FyleJoin for it
            if ObvMessengerSettings.Discussions.attachLinkPreviewToMessageSent, let linkMetadata = linkMetadatas.first {
                let itemProvider = NSItemProvider(item: linkMetadata, typeIdentifier: UTType.olvidLinkPreview.identifier)
                let loadedItemProviders = try await self.loadItemProviderHelper.load(itemProvider, source: .shareExtension, progressProvider: nil)
                let op1 = CreateFylesFromLoadedFileRepresentationsOperation(loadedItemProviders: loadedItemProviders)
                op1.viewContext = ObvStack.shared.viewContext
                op1.obvContext = obvContext
                await internalQueue.addAndAwaitOperation(op1)
                if let linkPreviewFyleJoins = op1.fyleJoins {
                    fyleJoins.append(contentsOf: linkPreviewFyleJoins)
                }
            }

            // Create all PersistedMessageSent objects for the selected discussions
            attachmentCountPerMessage = fyleJoins.count
            sharedState.sendingProgress = .preparing
            messageSentPermanentIDs = try await createAllMessagesToSend(textBody: textBody,
                                                                        fyleJoins: fyleJoins,
                                                                        discussions: persistedDiscussions)
        } catch {
            Self.logger.fault("📤 Could not create all messages to send: \(error.localizedDescription, privacy: .public)")
            let toast = Toast(style: .error, message: String(localized: "SHARE_EXTENSION_ERROR_SENDING_MESSAGE"))
            Toaster.showToast(toast: toast)
            sharedState.isSending = false
            return
        }

        // If we reach this point, all PersistedMessageSent objects are saved in the App DB, but still unprocessed.
        // We now send them one by one using the engine.
        
        // Dispatch group to track when all engine operations complete
        let dispatchGroupForEngine = DispatchGroup()

        // From here on the wait is on the network, so switch the indicator to the upload phase. It stays
        // indeterminate until the engine reports its first chunk progress below.
        sharedState.sendingProgress = .uploading(fractionCompleted: nil)

        var messageIdentifiersFromEngine = Set<Data>()

        for messageSentPermanentID in messageSentPermanentIDs {
            do {
                let identifiers = try await sendUnprocessedMessageToSend(messageSentPermanentID, dispatchGroupForEngine: dispatchGroupForEngine)
                messageIdentifiersFromEngine.formUnion(identifiers)
            } catch {
                Self.logger.fault("📤 Could not send one of the messages: \(error.localizedDescription, privacy: .public)")
                assertionFailure() // Continue anyway
                // Do *not* reset `isSending` here: the remaining messages are still being dispatched and
                // the dismiss operation below is still scheduled. Re-enabling the Send button mid-flight
                // would let the user tap Send again and produce duplicate messages. `isSending` stays true
                // until the extension is dismissed by `cancelRequest()`.
            }
        }

        // Report how far the upload has got, until the dismissal below tears this down.
        let uploadProgressPoller = Task { [weak self] in
            await self?.pollUploadProgress(messageIdentifiersFromEngine: messageIdentifiersFromEngine,
                                           attachmentCountPerMessage: attachmentCountPerMessage)
        }

        // Wait until all engine completion handlers are called before dismissing the share extension

        internalQueue.addOperation { [weak self] in
            dispatchGroupForEngine.wait()
            // At this point, we know for sure that *all* messages were sent by the engine.
            uploadProgressPoller.cancel()
            // Notify the main app so that, if it is already running and displaying the target discussion,
            // it refreshes the freshly-sent message and replays the engine's transaction history to update
            // its sent/delivered status (observed in PersistedDiscussionsUpdatesCoordinator).
            ObvDarwinNotificationCenter.shared.post(ObvDarwinNotificationName.shareExtensionDidPostMessage)
            // Cancel the request to dismiss the share extension. This runs on `internalQueue` (a background
            // queue), but dismissal touches `extensionContext`, which is main-actor only — hop to the main
            // actor. `dispatchGroupForEngine.wait()` above intentionally stays on the background queue.
            Task { @MainActor in
                // Everything is uploaded, so land the bar on complete for the frame or two before dismissal
                // rather than leaving it stopped at whatever the last poll happened to report.
                self?.sharedState.sendingProgress = .uploading(fractionCompleted: 1.0)
                self?.delegate?.cancelRequest()
            }
        }

    }

    /// Polls the engine for the upload progress of the messages just posted, publishing the overall fraction
    /// so the compose bar shows a determinate bar during the upload wait.
    ///
    /// This is the phase most in need of feedback: the extension deliberately stays alive until the engine
    /// reports the attachments as stored on the server, which on a poor network is unbounded, and without a
    /// number there is nothing to distinguish a slow upload from a hang.
    ///
    /// Returns as soon as the task is cancelled, which the dismissal path does once every message is sent.
    @MainActor
    private func pollUploadProgress(messageIdentifiersFromEngine: Set<Data>, attachmentCountPerMessage: Int) async {

        /// Identifies one attachment of one posted message, as reported by the engine.
        struct AttachmentKey: Hashable {
            let messageIdentifierFromEngine: Data
            let attachmentNumber: Int
        }

        let totalAttachmentCount = messageIdentifiersFromEngine.count * attachmentCountPerMessage

        // Nothing to measure: a message with no attachment (a plain text or link share) is posted in one
        // step, so the phase stays indeterminate rather than showing a bar that is either 0% or 100%.
        guard totalAttachmentCount > 0 else { return }

        // The engine only returns the progresses that changed since the date we pass, so accumulate them
        // across polls. Attachments never reported yet count as 0, which is what we want for the denominator.
        var fractionOfAttachment = [AttachmentKey: Double]()
        var dateOfLastPoll = Date.distantPast

        while !Task.isCancelled {

            // Take the cutoff *before* the request, so progress updates landing while it is in flight are
            // picked up by the next poll instead of being skipped.
            let dateOfThisPoll = Date()

            let progresses: [(ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data, attachmentNumber: Int, progress: Float)]
            do {
                progresses = try await obvEngine.requestUploadAttachmentProgressesUpdatedSince(date: dateOfLastPoll)
            } catch {
                // Losing progress reporting must not affect the send itself, which is driven entirely by the
                // dispatch group. Stop polling and leave the bar where it was.
                Self.logger.error("📤 Could not obtain upload progresses from the engine: \(error.localizedDescription, privacy: .public)")
                return
            }
            dateOfLastPoll = dateOfThisPoll

            // Ignore anything that isn't one of the messages we just posted. The extension process is reused
            // across successive shares, so the engine's in-memory tracker can still hold entries for an
            // earlier share's attachments.
            for progress in progresses where messageIdentifiersFromEngine.contains(progress.messageIdentifierFromEngine) {
                let key = AttachmentKey(messageIdentifierFromEngine: progress.messageIdentifierFromEngine,
                                        attachmentNumber: progress.attachmentNumber)
                // `max` keeps the bar monotonic: a chunk that has to be retried would otherwise walk it back.
                fractionOfAttachment[key] = max(fractionOfAttachment[key] ?? 0, Double(progress.progress))
            }

            let fractionCompleted = fractionOfAttachment.values.reduce(0, +) / Double(totalAttachmentCount)
            sharedState.sendingProgress = .uploading(fractionCompleted: fractionCompleted)

            try? await Task.sleep(seconds: 0.5)
        }
    }
    
    /// Creates all PersistedMessageSent objects that need to be sent. Called after the user taps the "send" button.
    /// Note: The preprocessing in `initializeOperations()` created the `fyleJoinsProvider` required here.
    /// This method saves the global `obvContext` that was *not* saved in `initializeOperations()` to ensure atomicity.
    /// - Parameters:
    ///   - textBody: The message text
    ///   - fyleJoins: The file attachments to include
    ///   - discussions: The discussions to send messages to
    /// - Returns: Array of permanent IDs for the created messages
    private func createAllMessagesToSend(textBody: String,
                                         fyleJoins: [FyleJoin],
                                         discussions: [PersistedDiscussion]) async throws -> [MessageSentPermanentID] {
        
        assert(Thread.isMainThread)
        
        let body: String? = textBody.trimmingWhitespacesAndNewlinesAndMapToNilIfZeroLength()
                
        cacheOfLinkMetadata.removeAll()
        
        // Create and queue operations to create all PersistedMessageSent objects
        
        var createMsgOps = [CreateUnprocessedPersistedMessageSentFromFylesAndStrings]()
        let logger = Self.logger
        for discussion in discussions {
            let op = CreateUnprocessedPersistedMessageSentFromFylesAndStrings(body: body, fyleJoins: fyleJoins, discussionObjectID: discussion.typedObjectID, log: Self.log)
            op.viewContext = ObvStack.shared.viewContext
            op.obvContext = obvContext
            op.completionBlock = {
                guard let index = discussions.firstIndex(of: discussion) else { return }
                logger.info("📤 [\(index + 1, privacy: .public)/\(discussions.count, privacy: .public)] Create Unprocessed Persisted Message Sent From Fyles And Strings done.")
            }
            createMsgOps.append(op)
            internalQueue.addOperation(op)
        }

        // Create the operation that saves the Core Data context
        
        let saveOp = SaveContextOperation(userDefaults: userDefaults)
        saveOp.viewContext = ObvStack.shared.viewContext
        saveOp.obvContext = obvContext
        
        // Queue the save operation and await its completion (without blocking the main thread) before
        // returning the ObjectIDs of the created persisted messages to send.

        await internalQueue.addAndAwaitOperation(saveOp)

        // Since `internalQueue` is serial, `saveOp` finishing means all previous operations are also finished.
        guard createMsgOps.allSatisfy({ !$0.isCancelled }) && !saveOp.isCancelled else {
            throw ObvError.couldNotCreateAllMessagesToSend
        }
        let messageSentPermanentIDs = createMsgOps.compactMap({ $0.messageSentPermanentID })
        assert(messageSentPermanentIDs.count == createMsgOps.count)
        return messageSentPermanentIDs
    }
    
    /// Sends an unprocessed message using the Oblivious Engine.
    /// This method performs an engine request to send the message referenced by the `messageSentPermanentID` parameter.
    /// It returns *after* the PersistedMessageSent is modified in DB using the identifier returned by the engine.
    /// - Parameters:
    ///   - messageSentPermanentID: The permanent ID of the message to send
    ///   - dispatchGroupForEngine: Dispatch group to track when all engine operations complete before dismissing the share extension
    /// - Returns: The identifiers the engine assigned to the posted message, used to attribute upload progresses to it.
    @discardableResult
    private func sendUnprocessedMessageToSend(_ messageSentPermanentID: MessageSentPermanentID, dispatchGroupForEngine: DispatchGroup) async throws -> Set<Data> {

        let obvContext = ObvStack.shared.newBackgroundContext(flowId: flowId)
        
        // Send the message with the engine.
        // Note: This code should be improved. We rely on the fact that the completion handler 
        // called by the engine is never called if the operation cancels.
        // We assume exactly one of these callbacks is called.
        // 2024-12-18: Since we set callCompletionWhenMessageAndAttachmentsAreSent=true, 
        // the completion is called when all attachments are sent (i.e., stored on the server).
        
        // When callCompletionWhenMessageAndAttachmentsAreSent is true, the engine waits until
        // the message is deleted from the outbox before calling the completion handler.
        // This is problematic on macOS, as the message is often sent by the app instead of
        // the extension (likely because the attachment is sent by a background session,
        // allowing the app to be notified instead of the share extension).
        // In that case, the share extension's engine is never notified about the message deletion,
        // so our callback is never called. Therefore, on macOS, we don't wait for the completion
        // before dismissing the share extension. When the completion is called, we tell the app again:
        // the notification posted at dismissal comes before the upload ends, and a running app learns
        // that the message is on the server only from the history replay this notification triggers.
        // Both completions are `@Sendable`, so that they do not inherit the main actor: the engine calls them on a
        // queue of its own, where a main-actor closure traps.
        #if targetEnvironment(macCatalyst)
        let op = SendUnprocessedPersistedMessageSentOperation(messageSentPermanentID: messageSentPermanentID, alsoPostToOtherOwnedDevices: true, extendedPayloadProvider: nil, obvEngine: obvEngine, callCompletionWhenMessageAndAttachmentsAreSent: true) { @Sendable in
            ObvDarwinNotificationCenter.shared.post(ObvDarwinNotificationName.shareExtensionDidPostMessage)
        }
        #else
        dispatchGroupForEngine.enter()
        // Balance the `enter()` above with *at most one* `leave()`, whether it comes from the engine
        // completion handler (which we assume, but cannot guarantee, fires exactly once) or from the cancel
        // path below. A second `leave()` would unbalance the group and crash.
        let oneShotLeave = OneShotGroupLeave(dispatchGroupForEngine)
        let op = SendUnprocessedPersistedMessageSentOperation(messageSentPermanentID: messageSentPermanentID, alsoPostToOtherOwnedDevices: true, extendedPayloadProvider: nil, obvEngine: obvEngine, callCompletionWhenMessageAndAttachmentsAreSent: true) { @Sendable in
            // Called by the engine when the message and its attachments were processed
            oneShotLeave.leave()
        }
        #endif
        op.viewContext = ObvStack.shared.viewContext
        op.obvContext = obvContext
        await internalQueue.addAndAwaitOperation(op)
        guard !op.isCancelled else {
            // The operation cancelled, so the engine will never call the completion handler that
            // balances the `enter()` above. Balance it here, otherwise `dispatchGroupForEngine.wait()`
            // blocks forever and the share extension never dismisses.
            #if !targetEnvironment(macCatalyst)
            oneShotLeave.leave()
            #endif
            throw ObvError.sendUnprocessedMessageOperationFailed
        }

        let saveOp = SaveContextOperation(userDefaults: userDefaults)
        saveOp.viewContext = ObvStack.shared.viewContext
        saveOp.obvContext = obvContext
        await internalQueue.addAndAwaitOperation(saveOp)

        if saveOp.isCancelled {
            throw ObvError.saveContextOperationFailedWhileSending
        }

        return op.messageIdentifiersFromEngine
    }
    
    /// Transcodes photos and videos to standard quality (SD) if needed, publishing progress as it goes.
    ///
    /// Progress is weighted by input file size rather than by item count. A share is very often a batch of
    /// small photos plus one large video, and with equal per-item weights that video — which dominates the
    /// wall-clock time — would account for a small slice of the bar, so the indicator would race to nearly
    /// complete and then sit still for a minute.
    /// - Parameter fyleJoins: The original fyle joins to potentially transcode
    /// - Returns: Array of fyle joins with transcoded media files replacing originals where applicable
    private func transcodeFyleJoinsIfNeeded(_ fyleJoins: [FyleJoin]) async throws -> [FyleJoin] {
        var transcodedFyleJoins: [FyleJoin] = []

        // Get the hardlinks for accessing the actual file URLs
        let hardlinks = sharedState.hardlinks

        // Weigh each transcodable item by its size on disk. Items we won't transcode carry no weight, so
        // they neither move the bar nor appear in the "n of m" count.
        let weightOfFyleJoinIndex: [Int: Double] = fyleJoins.reduce(into: [:]) { weights, fyleJoin in
            guard fyleJoin.fyle != nil else { return }
            guard let hardlink = hardlinks.first(where: { $0.index == fyleJoin.index }) else { return }
            guard Self.isTranscodableMedia(uti: fyleJoin.uti) else { return }
            // Fall back to a minimal non-zero weight when the size can't be read, so an unreadable file
            // still advances the bar instead of silently contributing nothing.
            let attributes = try? FileManager.default.attributesOfItem(atPath: hardlink.url.path)
            let fileSize = (attributes?[.size] as? NSNumber)?.doubleValue ?? 0
            weights[fyleJoin.index] = max(fileSize, 1.0)
        }

        let progress = TranscodingProgress(weightOfFyleJoinIndex: weightOfFyleJoinIndex, sharedState: sharedState)
        progress.publish()

        for fyleJoin in fyleJoins {
            guard fyleJoin.fyle != nil else {
                transcodedFyleJoins.append(fyleJoin)
                continue
            }

            // Find the corresponding hardlink for this fyleJoin by matching the index
            guard let hardlink = hardlinks.first(where: { $0.index == fyleJoin.index }) else {
                // No hardlink found, keep original
                transcodedFyleJoins.append(fyleJoin)
                continue
            }

            // Check if this is a photo or video
            guard let contentType = UTType(fyleJoin.uti) else {
                transcodedFyleJoins.append(fyleJoin)
                continue
            }
            let isImage = ObvMediaFormat.mayBeChosen(forPhotoOfType: contentType)
            let isVideo = ObvMediaFormat.mayBeChosen(forVideoOfType: contentType)

            if isImage {
                // Transcode image using the hardlink URL. ImageIO downsampling is fast enough that there is
                // no intra-item progress worth reporting; the item lands on the bar when it completes.
                if let transcodedFyleJoin = try await TranscodeUtils.transcodeImage(fyleJoin,
                                                                                    hardlinkURL: hardlink.url,
                                                                                    within: obvContext.context) {
                    transcodedFyleJoins.append(transcodedFyleJoin)
                } else {
                    // Transcoding failed: the user asked for SD but we fall back to sending the
                    // original full-resolution image. Log it so this is not silent.
                    Self.logger.error("📤 SD transcoding failed for image at index \(fyleJoin.index, privacy: .public), sending original HD file instead")
                    transcodedFyleJoins.append(fyleJoin)
                }
            } else if isVideo {
                // Transcode video using the hardlink URL
                if let transcodedFyleJoin = try await TranscodeUtils.transcodeVideo(fyleJoin,
                                                                                    hardlinkURL: hardlink.url,
                                                                                    within: obvContext.context,
                                                                                    onProgress: { fractionOfCurrentItem in
                                                                                        Task { @MainActor in
                                                                                            progress.reportProgressOfItemInFlight(index: fyleJoin.index,
                                                                                                                                  fractionCompleted: fractionOfCurrentItem)
                                                                                        }
                                                                                    }) {
                    transcodedFyleJoins.append(transcodedFyleJoin)
                } else {
                    // Transcoding failed: the user asked for SD but we fall back to sending the
                    // original full-resolution video. Log it so this is not silent.
                    Self.logger.error("📤 SD transcoding failed for video at index \(fyleJoin.index, privacy: .public), sending original HD file instead")
                    transcodedFyleJoins.append(fyleJoin)
                }
            } else {
                // Not a photo or video, keep as is
                transcodedFyleJoins.append(fyleJoin)
                continue
            }

            // Fold the finished item into the completed total. Done for failed transcodes too: the item is
            // no longer in flight either way, and the bar must not stall on a file we gave up on.
            progress.markItemCompleted(index: fyleJoin.index)
        }

        return transcodedFyleJoins
    }

    /// Whether `transcodeFyleJoinsIfNeeded` will actually re-encode a file with this UTI, i.e. whether it
    /// should count towards the transcoding progress.
    private static func isTranscodableMedia(uti: String) -> Bool {
        guard let type = UTType(uti) else { return false }
        return ObvMediaFormat.mayBeChosen(forPhotoOfType: type) || ObvMediaFormat.mayBeChosen(forVideoOfType: type)
    }


}

// MARK: - SharedState.HardLink Extension

extension SharedState.HardLink {
    
    /// Initializes a HardLink from a HardLinkToFyle object
    /// - Parameters:
    ///   - index: The index of this hardlink in the collection
    ///   - hardlinkToFyle: The source hardlink object
    init?(index: Int,
          hardlinkToFyle: HardLinkToFyle) {
        guard let hardlinkURL = hardlinkToFyle.hardlinkURL else { return nil }
        // Read the image's dimensions now, from the header only, so each attachment page can reserve its
        // real shape while the full decode is still pending. Cheap enough to do for the whole batch here:
        // no pixels are decoded, and non-images simply yield nil.
        let pixelSize = SharedState.HardLink.pixelSizeOfImage(at: hardlinkURL)
        self.init(index: index,
                  contentType: hardlinkToFyle.contentType,
                  url: hardlinkURL,
                  filename: hardlinkToFyle.fileName,
                  creationDate: hardlinkToFyle.creationDate,
                  thumbnail: .loading,
                  pixelSize: pixelSize)
    }

}

// MARK: - TranscodingProgress

/// Aggregates the per-item progress of the SD transcoding pass into the single overall fraction published on
/// `SharedState`, so the compose bar can show one determinate bar for the whole batch.
///
/// Items are weighted by their size on disk rather than counted equally — see `transcodeFyleJoinsIfNeeded`.
/// Holding the running totals here, on a main-actor type, rather than in local variables captured by the
/// export session's progress callback, keeps the mutable state single-isolated: the callback arrives from
/// the export's polling task and hops to the main actor to reach it.
@MainActor
private final class TranscodingProgress {

    /// Size-based weight of each fyle join that will actually be transcoded, keyed by fyle-join index.
    private let weightOfFyleJoinIndex: [Int: Double]
    private let totalWeight: Double
    private weak var sharedState: SharedState?

    /// Indices of the items that have finished (successfully or not).
    private var completedIndices = Set<Int>()
    /// How far the item currently being transcoded has got, 0...1.
    private var fractionOfItemInFlight: Double = 0
    private var indexOfItemInFlight: Int?

    init(weightOfFyleJoinIndex: [Int: Double], sharedState: SharedState) {
        self.weightOfFyleJoinIndex = weightOfFyleJoinIndex
        self.totalWeight = weightOfFyleJoinIndex.values.reduce(0, +)
        self.sharedState = sharedState
    }

    func reportProgressOfItemInFlight(index: Int, fractionCompleted: Double) {
        indexOfItemInFlight = index
        fractionOfItemInFlight = fractionCompleted
        publish()
    }

    func markItemCompleted(index: Int) {
        completedIndices.insert(index)
        if indexOfItemInFlight == index {
            indexOfItemInFlight = nil
            fractionOfItemInFlight = 0
        }
        publish()
    }

    func publish() {
        // Nothing to transcode: leave the phase alone rather than publishing a bar that would jump straight
        // to complete and vanish.
        guard totalWeight > 0 else { return }
        var weightCompleted = completedIndices.reduce(0.0) { $0 + (weightOfFyleJoinIndex[$1] ?? 0) }
        if let indexOfItemInFlight, !completedIndices.contains(indexOfItemInFlight) {
            weightCompleted += fractionOfItemInFlight * (weightOfFyleJoinIndex[indexOfItemInFlight] ?? 0)
        }
        sharedState?.sendingProgress = .transcoding(fractionCompleted: weightCompleted / totalWeight,
                                                    completedItemCount: completedIndices.count,
                                                    totalItemCount: weightOfFyleJoinIndex.count)
    }
}


// MARK: - OneShotGroupLeave

/// Calls `DispatchGroup.leave()` at most once, no matter how many times `leave()` is invoked. Guards the
/// share extension's send flow against a double `leave()` (e.g. the engine completion handler firing more
/// than once), which would unbalance the group and crash.
private final class OneShotGroupLeave: @unchecked Sendable {

    private let group: DispatchGroup
    private let lock = NSLock()
    private var hasLeft = false

    init(_ group: DispatchGroup) {
        self.group = group
    }

    func leave() {
        lock.lock()
        defer { lock.unlock() }
        guard !hasLeft else { return }
        hasLeft = true
        group.leave()
    }
}
