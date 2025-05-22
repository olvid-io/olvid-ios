/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import CoreData
import os.log
import QuickLook
import MobileCoreServices
import AVFoundation
import Combine
import TipKit
import ObvTypes
import OlvidUtils
import ObvUI
import ObvPlatformBase
import ObvUICoreData
import ObvComponentsTextInputShortcutsResultView
import _Discussions_Mentions_Builders_Shared
import ObvDiscussionsScrollToBottomButton
import UniformTypeIdentifiers
import ObvDesignSystem
import ObvSettings
import LinkPresentation
import ObvAppCoreConstants
import ObvLocation
import ObvAppTypes


final class NewSingleDiscussionViewController: UIViewController, NSFetchedResultsControllerDelegate, UICollectionViewDelegate, ViewShowingHardLinksDelegate, CustomQLPreviewControllerDelegate, UICollectionViewDataSourcePrefetching, CellReconfigurator, SomeSingleDiscussionViewController, UIGestureRecognizerDelegate, ObvErrorMaker, TextBubbleDelegate, NewComposeMessageViewDatasource, UICollectionViewDropDelegate, UICollectionViewDragDelegate, UISearchControllerDelegate {
    
    static let errorDomain = "NewSingleDiscussionViewController"
    let currentOwnedCryptoId: ObvCryptoId
    static let sectionHeaderElementKind = UICollectionView.elementKindSectionHeader
    private let discussion: PersistedDiscussion
    private var collectionView: DiscussionCollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, NSManagedObjectID>!
    private var frc: NSFetchedResultsController<PersistedMessage>!
    private var currentContentHeight = CGFloat(0)
    private var viewDidAppearWasCalled = false
    private var composeMessageView: NewComposeMessageView!
    private let draftObjectID: TypeSafeManagedObjectID<PersistedDraft>
    let discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>
    let discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>
    private var observationTokens = [NSObjectProtocol]()
    private var unreadMessagesSystemMessage: PersistedMessageSystem?
    private let initialScroll: InitialScroll
    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: NewSingleDiscussionViewController.self))
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: NewSingleDiscussionViewController.self))
    private static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: NewSingleDiscussionViewController.self))
    private let internalQueue = DispatchQueue(label: "NewSingleDiscussionViewController internal queue")
    private let hidingView = UIView()
    private var initialScrollWasPerformed = false
    private var currentKbdSize = CGRect.zero
    private let queueForApplyingSnapshots = DispatchQueue(label: "NewSingleDiscussionViewController queue for snapshots")
    private let cacheDelegate = DiscussionCacheManager(previewFetcherDelegate: MissingReceivedLinkPreviewFetcher())
    private var messagesToMarkAsNotNewWhenScrollingEnds = [MessageIdentifier]()
    private var atLeastOneSnapshotWasApplied = false
    private var isRegisteredToKeyboardNotifications = false
    private var visibilityTrackerForSensitiveMessages: VisibilityTrackerForSensitiveMessages
    private lazy var scrollToBottomButton = ScrollToBottomButton(observing: collectionView, initialVerticalVisibilityThreshold: 0)
    private let viewDidLayoutSubviewsSubject = PassthroughSubject<Void, Never>()
    private var isDragSessionInProgress = false
    private static let spaceBellowLastCell: CGFloat = 8.0
    private var hideGroupMemberChangeMessages = ObvMessengerSettings.ContactsAndGroups.hideGroupMemberChangeMessages
    private var objectIDSentMessageJustSent: TypeSafeManagedObjectID<PersistedMessageSent>?

    // Search related variables
    private var isUserPerformingSearch = false
    private let singleDiscussionSearchView = SingleDiscussionSearchView()
    private let searchController = UISearchController(searchResultsController: nil)
    private let searchControllerDelegate: SingleDiscussionSearchControllerDelegate
    private var messagesContainingSearchedText: [TypeSafeManagedObjectID<PersistedMessage>]?

    /// Defines the kind of view shown above the keyboard. In general, it's the composition view. But it can be the search view during a search.
    private var accessoryViewKindShown: AccessoryViewKind = .none
    
    // MARK: attribute - private - ObvLinkMedata
    private var previewMetadataInComposeView: ObvLinkMetadata?
    

    // MARK: attribute - private - context menu manager used to display a custom view alongside UIContextMenu
    private var contextMenuManager: ContextMenuManager?
    private var contextReactionRootView: HidableView?
    private var contextViewToSnapshot: UIView?
    
    /// We must adapt the collection view's insets when the frame of the main content view of the composition view changes, when the keyboard shows/hides, but only when we are not scrolling.
    /// To do so, we three values representing those states, and adapt the insets when appropriate. We use the ``NewComposeMessageView`` published main content view frame, the published ``currentScrolling`` value, and the following ``toggledWhenKeyboardDidHideOrShow`` variable, toggled whenever the keyboard changes state.
    // Adapting the scroll view's insets depending on the height of the composition view, the virtual keyboard status, and the scrolling status
    @Published private var toggledWhenKeyboardDidHideOrShow = false
        
    @Published private var messagesToReconfigure = Set<TypeSafeManagedObjectID<PersistedMessage>>()

    private var cancellables = [AnyCancellable]()

    // Single and double tap gesture recognizers on cells
    private var singleTapOnCell: UITapGestureRecognizer!
    private var doubleTapOnCell: UITapGestureRecognizer!
    
    /// The following variables are used to determine whether we should automatically scroll when the collection
    /// view is updated.
    private var lastScrollWasManual = false
    private var lastReceivedMessageObjectId: TypeSafeManagedObjectID<PersistedMessageReceived>?
    private var lastSentMessageObjectId: TypeSafeManagedObjectID<PersistedMessageSent>?
    private var lastSystemMessageObjectId: TypeSafeManagedObjectID<PersistedMessageSystem>?
    @Published private var currentScrolling = ScrollingType.none

    private let defaultAnimationValues: (duration: Double, options: UIView.AnimationOptions) = (0.25, UIView.AnimationOptions([.curveEaseInOut]))
    
    private var isRegisteredToNotifications = false

    private var timerForRefreshingCellCountdowns: Timer?

    private var filesViewer: FilesViewer?
    
    /// Tip related variables
    private weak var viewSavedToDisplayTip: NSObjectProtocol? // A UIPopoverPresentationControllerSourceItem, either the ellipsis button (iOS) or the search bar (macOS)
    private weak var tipPopoverController: AnyObject? // In practice, this is a TipUIPopoverViewController
    private var tipObservationTask: Task<Void, Never>?
    private var shareLocationTip: Any? = {
        if #available(iOS 17, *) {
            return OlvidTip.ShareLocation()
        } else {
            return nil
        }
    }()
    private var keyboardShortcutForSendingMessage: Any? = {
        if #available(iOS 17, *) {
            return OlvidTip.KeyboardShortcutForSendingMessage()
        } else {
            return nil
        }
    }()

    /// Allows to keep track of the message the user wants to forward until she chose the appropriate discussions.
    private var messageToForward: PersistedMessage?

    /// The counter in the system message showing the number of new messages corresponds to the number of elements in this set.
    /// When instanciating this view controller, we query the database to get the objectIDs of all new received and system messages, and we
    /// use them to create this set. When loading this view controller, we insert the system message indicating the number of new messages
    /// if this array is non-empty. We insert it just above the first new message (either received or system).
    /// When in the discussion :
    /// - If a new message is received, its objectID is inserted into this set and the system message is inserted or updated
    /// - If a new (relevant) system message is added, its objectID is inserted into this set and the system message is inserted or updated
    /// - When a message gets deleted, we remove its objectID from the set and the system message is inserted or updated
    /// - When  sending a message, we remove all the objectIDs from the set and remove the system message
    /// Note that this system message is semewhat decorrelated from the database. For example, marking a message as "not new" while in the discussion
    /// does not update the system message.
    /// This set must be accessed on the main thread.
    private var objectIDsOfMessagesToConsiderInNewMessagesCell = Set<TypeSafeManagedObjectID<PersistedMessage>>()
        
    weak var delegate: SingleDiscussionViewControllerDelegate?

    private let dateFormaterForHeaders: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale.current
        df.doesRelativeDateFormatting = false
        df.timeStyle = .none
        df.setLocalizedDateFormatFromTemplate("EEE d MMMM yyyy")
        return df
    }()

    private let dateFormaterForHeadersCurrentYear: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale.current
        df.doesRelativeDateFormatting = false
        df.timeStyle = .none
        df.setLocalizedDateFormatFromTemplate("EEE d MMMM")
        return df
    }()

    private let dateFormaterForHeadersTodayOrYesterday: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale.current
        df.doesRelativeDateFormatting = true
        df.timeStyle = .none
        df.dateStyle = .short
        return df
    }()
    
    private let dateFormaterForHeadersWeekday: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale.current
        df.doesRelativeDateFormatting = true
        df.timeStyle = .none
        df.timeStyle = .none
        df.setLocalizedDateFormatFromTemplate("EEEE")
        return df
    }()

    private let dateFormaterForHeadersDay: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale.current
        df.doesRelativeDateFormatting = true
        df.timeStyle = .none
        df.timeStyle = .none
        df.setLocalizedDateFormatFromTemplate("d")
        return df
    }()

    enum InitialScroll {
        case specificMessage(_: PersistedMessage)
        case newMessageSystemOrLastMessage
    }

    init(discussion: PersistedDiscussion, delegate: SingleDiscussionViewControllerDelegate, initialScroll: InitialScroll) throws {
        guard let ownCryptoId = discussion.ownedIdentity?.cryptoId else {
            throw Self.makeError(message: "Could not determine owned identity")
        }
        self.discussion = discussion
        self.currentOwnedCryptoId = ownCryptoId
        self.draftObjectID = discussion.draft.typedObjectID
        self.discussionObjectID = discussion.typedObjectID
        self.discussionPermanentID = discussion.discussionPermanentID
        self.initialScroll = initialScroll
        self.visibilityTrackerForSensitiveMessages = VisibilityTrackerForSensitiveMessages(discussionPermanentID: discussion.discussionPermanentID)
        self.searchControllerDelegate = SingleDiscussionSearchControllerDelegate(discussionObjectID: discussion.typedObjectID)
        super.init(nibName: nil, bundle: nil)
        self.composeMessageView = NewComposeMessageView(
            draft: discussion.draft,
            viewShowingHardLinksDelegate: self,
            cacheDelegate: cacheDelegate,
            delegate: self,
            datasource: self,
            attachmentsCollectionViewControllerDelegate: self
        )
        self.visibilityTrackerForSensitiveMessages.delegate = self

        self.delegate = delegate
        
        do {
            try computeInitialValueOfObjectIDsOfMessagesToConsiderInNewMessagesCell()
        } catch {
            assertionFailure()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        cancellables.forEach { $0.cancel() }
    }
        
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        self.composeMessageView.delegateViewController = self
        configureNavigationTitle()

        insertOrUpdateSystemMessageCountingNewMessages(removeExisting: true)

        configureHierarchy()
        configureDataSource()
        
        // Managing the system message indicating new messages
        updateNewMessageCellOnDeletionOfReceivedMessages()
        updateNewMessageCellOnDeletionOfRelevantSystemMessages()
        updateNewMessageCellOnInsertionOfReceivedMessages()
        updateNewMessageCellOnInsertionOfRelevantSystemMessages()
        updateNewMessageCellOnInsertionOfSentMessage()
        
        observePersistedDiscussionChanges()
        observePersistedObvContactIdentityChanges()
        observeRouteChange()
        registerForKeyboardNotifications()
        
        observeMessagesToReconfigure()
        observeDeletedFyleMessageJoinNotifications()
        
        observeTapsOnCollectionView()

        observeNicknameChanges()
        configureScrollToBottomButton()
        
        observeKeyboardAndCompositionViewChangesToAdaptCollectionViewsInsets()
        
        configureSearchController()
        
        continuouslyObserveTraitCollectionActiveAppearance()
        
        // For mac catalyst, we are adding a long press gesture recognizer for the reaction context menu
        if ObvMessengerConstants.targetEnvironmentIsMacCatalyst {
            setupLongGestureRecognizerForCatalyst()
        }
    }
    
    
    /// We observe the `traitCollectionActiveAppearance` to make sure we mark new messages as "not new" when ever
    /// the application window turns back to "active". This is important under macOS only.
    private func continuouslyObserveTraitCollectionActiveAppearance() {
        OlvidUserActivitySingleton.shared.$traitCollectionActiveAppearance
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] traitCollectionActiveAppearance in
                guard traitCollectionActiveAppearance == .active else { return }
                self?.markNewVisibleReceivedAndRelevantSystemMessagesAsNotNew()
            }
            .store(in: &cancellables)
    }
    
    
    
    private func configureScrollToBottomButton() {
        let verticalVisibilityPublisher = Publishers.CombineLatest(
            viewDidLayoutSubviewsSubject,
            collectionView.publisher(for: \.contentSize, options: [.initial, .new]))
            .map(\.1)
            .compactMap { [weak collectionView] contentSize -> CGFloat? in
                guard let collectionView else {
                    return nil
                }
                
                let contentHeight = contentSize.height
                
                let pageHeight = collectionView.frame.height
                
                return contentHeight - (pageHeight * 2) - collectionView.adjustedContentInset.top
            }
        
        verticalVisibilityPublisher
            .assign(to: &scrollToBottomButton.$verticalVisibilityThreshold)
    }
    

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // When the subiews are laid out, we use this published to update the scrollToBottomButton.
        viewDidLayoutSubviewsSubject
            .send()
    }

    private func configureTimerForRefreshingCellCountdowns() {
        guard timerForRefreshingCellCountdowns == nil else { return }
        timerForRefreshingCellCountdowns = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(refreshCellCountdowns), userInfo: nil, repeats: true)
    }
    
    private func invalidateTimerForRefreshingCellCountdowns() {
        timerForRefreshingCellCountdowns?.invalidate()
        timerForRefreshingCellCountdowns = nil
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // This makes gives a chance to the layout to reset itself if required.
        // This typically happens when rotating the screen.
        collectionView.collectionViewLayout.invalidateLayout()
    }

    // When the view will transition, we remove the context reaction view if needed
    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        self.hideContextReactionViewIfNeeded(animated: false)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        registerForNotification()

        // This constraint was *not* set in viewDidLoad. We want to reset it every time the main view will appear
        // Otherwise, it seems that the constraint "disappears" each time another VC is presented over this one.
        // This constrain pins the mainContentView of the composition view at the top of the keyboard. Note that the composition
        // view itself is pinned at the bottom, allowing to ensure that its effect view extends to the bottom, avoiding a "gap"
        // on iPhones with rounded screen cordners.
        view.keyboardLayoutGuide.topAnchor.constraint(equalTo: composeMessageView.mainContentView.bottomAnchor).isActive = true
        
        view.keyboardLayoutGuide.topAnchor.constraint(equalTo: singleDiscussionSearchView.mainContentView.bottomAnchor).isActive = true

        configureAcessoryViewVisibility(animate: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewDidAppearWasCalled = true
        composeMessageView.discussionViewDidAppear()
        configureTimerForRefreshingCellCountdowns()
                
        // ObvDisplayableLogs.shared.log("[NewSingleDiscussionViewController] Will call to markNewVisibleReceivedAndRelevantSystemMessagesAsNotNew from viewDidAppear")
        markNewVisibleReceivedAndRelevantSystemMessagesAsNotNew()
        insertSystemMessageIfCurrentDiscussionIsEmpty()
        
        performInitialScrollIfAppropriateAndRemoveHidingView()
        
        // This hack re-enables the compose message view in case it was prevented from editing
        if composeMessageView.preventTextViewFromEditing {
            DispatchQueue.main.async { [weak self] in
                self?.composeMessageView.endEditing(false)
                self?.composeMessageView.preventTextViewFromEditing = false
            }
        }
        
        configureTipsOnViewDidAppear(animated: animated)
        
    }
    
    
    private func configureTipsOnViewDidAppear(animated: Bool) {
        
        // Add a tip on the ellipsisButton
        
        if #available(iOS 17.0, *) {
            guard let shareLocationTip = shareLocationTip as? OlvidTip.ShareLocation,
                  let keyboardShortcutForSendingMessage = keyboardShortcutForSendingMessage as? OlvidTip.KeyboardShortcutForSendingMessage else {
                assertionFailure()
                return
            }
            tipObservationTask = tipObservationTask ?? Task { @MainActor in
                for await shouldDisplay in shareLocationTip.shouldDisplayUpdates {
                    if shouldDisplay {
                        guard let sourceItem = composeMessageView.viewForShareLocationTip else { assertionFailure(); break }
                        let popoverController = TipUIPopoverViewController(shareLocationTip, sourceItem: sourceItem)
                        present(popoverController, animated: true)
                        tipPopoverController = popoverController
                    } else {
                        if presentedViewController is TipUIPopoverViewController {
                            dismiss(animated: animated)
                            tipPopoverController = nil
                        }
                    }
                }
                guard tipPopoverController == nil else { return }
                if ObvMessengerConstants.targetEnvironmentIsMacCatalyst {
                    for await shouldDisplay in keyboardShortcutForSendingMessage.shouldDisplayUpdates {
                        if shouldDisplay {
                            guard let sourceItem = composeMessageView else { assertionFailure(); return }
                            let popoverController = TipUIPopoverViewController(keyboardShortcutForSendingMessage, sourceItem: sourceItem)
                            present(popoverController, animated: true)
                            tipPopoverController = popoverController
                        } else {
                            if presentedViewController is TipUIPopoverViewController {
                                dismiss(animated: animated)
                                tipPopoverController = nil
                            }
                        }
                    }
                }
            }
        }
        
    }
    
    
    private func performInitialScrollIfAppropriateAndRemoveHidingView() {
        assert(Thread.isMainThread)
        guard viewDidAppearWasCalled else {
            // ObvDisplayableLogs.shared.log("[Discussion] Since viewDidAppearWasCalled is false, we do not scroll yet")
            return
        }
        guard atLeastOneSnapshotWasApplied else {
            // ObvDisplayableLogs.shared.log("[Discussion] Since atLeastOneSnapshotWasApplied is false, we do not scroll yet")
            return
        }
        guard !initialScrollWasPerformed else {
            // ObvDisplayableLogs.shared.log("[Discussion] Since initialScrollWasPerformed was already performed, we do not scroll")
            return
        }
        initialScrollWasPerformed = true
        let completion = { [weak self] in
            self?.scrollViewDidEndAutomaticScroll()
            // ObvDisplayableLogs.shared.log("[Discussion] Removing hiding view")
            UIView.animate(withDuration: 0.3) {
                self?.hidingView.alpha = 0
            } completion: { _ in
                self?.hidingView.isHidden = true
                self?.scrollToBottomButton.isTrackingEnabled = true
                // ObvDisplayableLogs.shared.log("[NewSingleDiscussionViewController] Will call to markNewVisibleReceivedAndRelevantSystemMessagesAsNotNew from performInitialScrollIfAppropriateAndRemoveHidingView")
                self?.markNewVisibleReceivedAndRelevantSystemMessagesAsNotNew()
            }
        }
        switch initialScroll {
        case .specificMessage(let message):
            guard let indexPath = frc.indexPath(forObject: message) else { return }
            let completionAndAnimate = { [weak self] in
                completion()
                // Waiting some time before animating the item prevents an animation glitch under iOS 18
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) { [weak self] in
                    self?.animateItem(at: indexPath)
                }
            }
            collectionView.adjustedScrollToItem(at: indexPath, at: .centeredVertically, completion: completionAndAnimate)
        case .newMessageSystemOrLastMessage:
            if let unreadMessagesSystemMessage {
                guard let indexPath = frc.indexPath(forObject: unreadMessagesSystemMessage) else { assertionFailure(); return }
                collectionView.adjustedScrollToItem(at: indexPath, at: .centeredVertically, completion: completion)
            } else {
                collectionView.adjustedScrollToBottom(completion: completion)
            }
        }
    }
    
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        composeMessageView.discussionViewWillDisappear()
        invalidateTimerForRefreshingCellCountdowns()
        processReceivedMessagesThatBecameNotNewDuringScrolling()
        if self.filesViewer == nil {
            // If the user is swiping to dismiss while the text view is editing, this code dismisses the keyboard and prevents it re-appearing if the user changes its mind and swipe back. The text view is reactivated in viewWillAppear.
            composeMessageView.animatedEndEditing(completion: { _ in })
            composeMessageView.preventTextViewFromEditing = true
        }
        removeTipsOnViewWillDisappear(animated: animated)
        
        hideContextReactionViewIfNeeded(animated: false)
    }
    
    
    private func removeTipsOnViewWillDisappear(animated: Bool) {
        tipObservationTask?.cancel()
        tipObservationTask = nil
    }
    

    private func registerForNotification() {
        guard !isRegisteredToNotifications else { return }
        isRegisteredToNotifications = true
        let sceneDidActivateNotification = UIScene.didActivateNotification
        let sceneDidEnterBackgroundNotification = UIScene.didEnterBackgroundNotification
        let log = self.log
        let discussionObjectID = self.discussionObjectID
        let discussionPermanentID = self.discussionPermanentID
        observationTokens.append(contentsOf: [
            ObvMessengerCoreDataNotification.observeDiscussionLocalConfigurationHasBeenUpdated { [weak self] value, objectId in
                OperationQueue.main.addOperation {
                    guard case .muteNotificationsEndDate = value else { return }
                    guard let discussion = try? PersistedDiscussion.get(objectID: discussionObjectID, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
                    guard discussion.localConfiguration.typedObjectID == objectId else { return }
                    self?.configureNavigationTitle()
                }
            },
            ObvMessengerCoreDataNotification.observePersistedContactGroupHasUpdatedContactIdentities { [weak self] _,_,_ in
                OperationQueue.main.addOperation {
                    self?.configureAcessoryViewVisibility(animate: true)
                }
            },
            ObvMessengerCoreDataNotification.observePersistedGroupV2UpdateIsFinished { [weak self] groupV2ObjectID, _, _ in
                OperationQueue.main.addOperation {
                    guard let group = try? PersistedGroupV2.get(objectID: groupV2ObjectID, within: ObvStack.shared.viewContext) else { return }
                    guard group.discussion?.typedObjectID.downcast == discussionObjectID else { return }
                    self?.configureAcessoryViewVisibility(animate: true)
                }
            },
            ObvMessengerInternalNotification.observeCurrentDiscussionDidChange { [weak self] previousDiscussion, currentDiscussion in
                Task { [weak self] in
                    guard let self else { return }
                    // Check that this discussion was left by the user
                    guard discussionPermanentID == previousDiscussion, discussionPermanentID != currentDiscussion else { return }
                    await self.theUserLeftTheDiscussion()
                }
            },
            ObvMessengerCoreDataNotification.observePersistedContactIsActiveChanged { [weak self] _ in
                OperationQueue.main.addOperation {
                    self?.configureAcessoryViewVisibility(animate: true)
                }
            },
            ObvMessengerCoreDataNotification.observePersistedDiscussionStatusChanged { [weak self] _, _ in
                OperationQueue.main.addOperation {
                    self?.configureAcessoryViewVisibility(animate: true)
                }
            },
            KeyboardNotification.observeKeyboardDidInputEscapeKeyNotification { [weak self] in
                OperationQueue.main.addOperation {
                    self?.hideContextReactionViewIfNeeded(animated: true)
                }
            },
            NotificationCenter.default.addObserver(forName: sceneDidActivateNotification, object: nil, queue: nil) { [weak self] _ in
                OperationQueue.main.addOperation {
                    // When the scene activates, we want to mark as not new the messages that were received while in background and that are now visible on screen.
                    self?.markNewVisibleReceivedAndRelevantSystemMessagesAsNotNew()
                }
            },
            NotificationCenter.default.addObserver(forName: sceneDidEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
                Task { [weak self] in
                    guard OlvidUserActivitySingleton.shared.currentDiscussionPermanentID == discussionPermanentID else { return }
                    os_log("🛫 Start call to theUserLeftTheDiscussion as scene enters background", log: log, type: .info)
                    await self?.theUserLeftTheDiscussion()
                    os_log("🛫 End call to theUserLeftTheDiscussion as scene enters background", log: log, type: .info)
                }
            },
            ObvMessengerCoreDataNotification.observeStatusOfSentFyleMessageJoinDidChange { [weak self] (sentJoinID, messageID, discussionID) in
                Task {
                    await self?.processStatusOfSentFyleMessageJoinDidChange(sentJoinID: sentJoinID, messageID: messageID, discussionID: discussionID)
                }
            },
        ])
    }
    
    
    func addAttachmentFromAirDropFile(at fileURL: URL) {
        self.composeMessageView.addAttachmentFromAirDropFile(at: fileURL)
    }
}




// MARK: - Initial setup and cell configuration

extension NewSingleDiscussionViewController {
    
    func configureNavigationTitle() {
        
        assert(Thread.isMainThread)
        
        guard let discussion = try? PersistedDiscussion.get(objectID: discussionObjectID, within: ObvStack.shared.viewContext) else { return }
        navigationItem.titleView = nil
        switch discussion.status {
        case .locked:
            navigationItem.titleView = SingleDiscussionTitleView(title: discussion.title, subtitle: discussion.subtitle)
        case .preDiscussion, .active:
            switch try? discussion.kind {
            case .oneToOne(withContactIdentity: let contact):
                if let contact = contact {
                    navigationItem.titleView = SingleDiscussionTitleView(objectID: contact.typedObjectID)
                }
            case .groupV1(withContactGroup: let contactGroup):
                if let group = contactGroup {
                    navigationItem.titleView = SingleDiscussionTitleView(objectID: group.typedObjectID)
                }
            case .groupV2(withGroup: let group):
                if let group = group {
                    navigationItem.titleView = SingleDiscussionTitleView(objectID: group.typedObjectID)
                }
            case .none:
                break
            }
        }
        if navigationItem.titleView == nil {
            navigationItem.titleView = SingleDiscussionTitleView(title: discussion.title, subtitle: discussion.subtitle)
        }
        
        // The title of the navigationItem is not displayed, since we always set a titleView. Yet, we set it so as to
        // display proper button titles in the menu displayed when performing a long press on the back button of the navigation stack.
        self.navigationItem.title = (navigationItem.titleView as? SingleDiscussionTitleView)?.title
        
        var menuElements = [UIMenuElement]()
        
        do {
            
            if discussion.status == .active {
                menuElements += [
                    UIAction(
                        title: Strings.discussionSettings,
                        image: UIImage(systemIcon: .gearshapeFill),
                        handler: { [weak self] _ in self?.settingsButtonTapped() }
                    ),
                    UIAction(
                        title: CommonString.Word.Gallery,
                        image: UIImage(systemIcon: .photoOnRectangleAngled),
                        handler: { [weak self] _ in self?.galleryButtonTapped() })
                ]
            }
            
            if discussion.status == .active && discussion.isCallAvailable {
                menuElements += [
                    UIAction(
                        title: CommonString.Word.Call,
                        image: UIImage(systemIcon: .phoneFill),
                        handler: { [weak self] _ in self?.callButtonTapped() }
                    )
                ]
            }
            
            // Add a search element (not under macOS, where the search bar is always shown)
            if addSearchItemInMenu {
                menuElements += [
                    UIAction(
                        title: CommonString.Word.Search,
                        image: UIImage(systemIcon: .magnifyingglass),
                        handler: { [weak self] _ in self?.searchButtonTapped() }
                    )
                ]
            }
            
        }
        
        var items: [UIBarButtonItem] = []

        // Create a menu if appropriate

        if !menuElements.isEmpty {
            
            let menu = UIMenu(title: "", children: menuElements)
            let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
            let ellipsisImage = UIImage(systemIcon: .ellipsisCircle, withConfiguration: symbolConfiguration)
            let ellipsisButton = UIBarButtonItem(
                title: nil,
                image: ellipsisImage,
                primaryAction: nil,
                menu: menu)
            items += [ellipsisButton]
            
            // If we added the search menu item, we want to use the ellipsis button a source for the tip allowing to discover the search
            if addSearchItemInMenu {
                viewSavedToDisplayTip = ellipsisButton
            }

        }
        
        // Configure the unmute button if necessary (as a menu, with a primary action)

        if let muteNotificationEndDate = discussion.localConfiguration.currentMuteNotificationsEndDate {
            
            let title: String
            if muteNotificationEndDate.timeIntervalSinceNow > TimeInterval(years: 10) {
                title = String(localized: "MUTED_NOTIFICATIONS_FOOTER_INDEFINITELY")
            } else {
                let unmuteDateFormatted = muteNotificationEndDate.formatted()
                title = Strings.mutedNotificationsConfirmation(unmuteDateFormatted)
            }
            let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
            let unmuteImage = UIImage(systemIcon: .moonZzzFill, withConfiguration: symbolConfiguration)
            let unmuteAction = UIAction.init(title: Strings.unmuteNotifications, image: UIImage(systemIcon: .moonZzzFill)) { _ in
                ObvMessengerInternalNotification.userWantsToUpdateDiscussionLocalConfiguration(value: .muteNotificationsEndDate(nil), localConfigurationObjectID: discussion.localConfiguration.typedObjectID).postOnDispatchQueue()
            }
            let menuElements: [UIMenuElement] = [unmuteAction]
            let menu = UIMenu(title: title, children: menuElements)
            let unmuteButton = UIBarButtonItem(
                title: nil,
                image: unmuteImage,
                primaryAction: nil,
                menu: menu)
            items += [unmuteButton]
        }

        navigationItem.rightBarButtonItems = items

        navigationItem.titleView?.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(titleViewWasTapped)))

    }
    
    @objc private func titleViewWasTapped() {
        assert(delegate != nil)
        guard let discussion = try? PersistedDiscussion.get(objectID: discussionObjectID, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
        delegate?.userTappedTitleOfDiscussion(discussion)
    }
    
    
    private func configureHierarchy() {
        
        collectionView = DiscussionCollectionView(frame: view.bounds, collectionViewLayout: createLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = AppTheme.shared.colorScheme.discussionScreenBackground
        view.addSubview(collectionView)
        collectionView.delaysContentTouches = false
        collectionView.delegate = self
        collectionView.keyboardDismissMode = .interactive
        collectionView.alwaysBounceVertical = true
        collectionView.scrollsToTop = false
        collectionView.contentInsetAdjustmentBehavior = .automatic
        collectionView.dropDelegate = self
        collectionView.dragDelegate = self

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
        ])
        
        collectionView.prefetchDataSource = self

        view.addSubview(hidingView)
        hidingView.translatesAutoresizingMaskIntoConstraints = false
        view.pinAllSidesToSides(of: hidingView)
        hidingView.backgroundColor = .systemBackground
        
        let spinner = UIActivityIndicatorView(style: .large)
        hidingView.addSubview(spinner)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: hidingView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: hidingView.centerYAnchor),
        ])
        spinner.startAnimating()

        view.addSubview(scrollToBottomButton)

        let attachmentsDropViewLayoutGuide = UILayoutGuide()

        view.addLayoutGuide(attachmentsDropViewLayoutGuide)

        configureComposeMessageViewHierarchy()
        
        configureSearchViewHierarchy()

        NSLayoutConstraint.activate([
            scrollToBottomButton.bottomAnchor.constraint(equalTo: composeMessageView!.topAnchor, constant: -24),
            scrollToBottomButton.trailingAnchor.constraint(equalTo: collectionView.safeAreaLayoutGuide.trailingAnchor, constant: -16),

            attachmentsDropViewLayoutGuide.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            attachmentsDropViewLayoutGuide.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),

            attachmentsDropViewLayoutGuide.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            composeMessageView!.topAnchor.constraint(equalToSystemSpacingBelow: attachmentsDropViewLayoutGuide.bottomAnchor, multiplier: 1),
        ])

    }

    
    private func configureComposeMessageViewHierarchy() {

        view.addSubview(composeMessageView!)
        composeMessageView.translatesAutoresizingMaskIntoConstraints = false

        composeMessageView!.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true

        // The bottomAnchor of the composeMessageView is pinned to the view's keyboardLayoutGuide in viewWillAppear.
        // In practice, this allows to reset this constraint after a new VC was presented or pushed over this one.
        NSLayoutConstraint.activate([
            composeMessageView!.widthAnchor.constraint(equalTo: view.widthAnchor),
            composeMessageView!.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        ])
    }
    
    
    /// In production, this method always returns the custom ``DiscussionLayout``. When beta options are available, the user
    /// can modify the ``discussionLayoutType`` setting so as to try alternative layouts and test their efficiency.
    private func createLayout() -> UICollectionViewLayout {
        switch ObvMessengerSettings.Interface.discussionLayoutType {
        case .productionLayout:
            let layout = DiscussionLayout()
            return layout
        case .listLayout:
            var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
            configuration.showsSeparators = false
            configuration.headerMode = .supplementary
            let layout = UICollectionViewCompositionalLayout.list(using: configuration)
            return layout
        }
        
        
    }

    private func configureDataSource() {
        
        let collectionView = self.collectionView!
        self.frc = PersistedMessage.getFetchedResultsControllerForAllMessagesWithinDiscussion(
            discussionObjectID: discussionObjectID,
            includeMembersOfGroupV2WereUpdated: !hideGroupMemberChangeMessages,
            within: ObvStack.shared.viewContext)
        self.frc.delegate = self
        
        let sentMessageCellRegistration = UICollectionView.CellRegistration<SentMessageCell, PersistedMessageSent> { [weak self] (cell, indexPath, message) in
            self?.updateSentMessageCell(cell, at: indexPath, with: message)
        }

        let receivedMessageCellRegistration = UICollectionView.CellRegistration<ReceivedMessageCell, PersistedMessageReceived> { [weak self] (cell, indexPath, message) in
            self?.updateReceivedMessageCell(cell, at: indexPath, with: message)
        }
        
        let systemMessageCellRegistration = UICollectionView.CellRegistration<SystemMessageCell, PersistedMessageSystem> { [weak self] (cell, indexPath, message) in
            self?.updateSystemMessageCell(cell, at: indexPath, with: message)
        }
        
        let invisibleCellRegistration = UICollectionView.CellRegistration<InvisibleCell, NSManagedObjectID> { (_, _, _) in }

        let headerRegistration = UICollectionView.SupplementaryRegistration<DateSupplementaryView>(elementKind: NewSingleDiscussionViewController.sectionHeaderElementKind) { [weak self] (dateSupplementaryView, string, indexPath) in
            self?.updateDateSupplementaryView(dateSupplementaryView, at: indexPath)
        }

        self.dataSource = UICollectionViewDiffableDataSource<Int, NSManagedObjectID>(collectionView: collectionView) { (collectionView: UICollectionView, indexPath: IndexPath, objectID: NSManagedObjectID) -> UICollectionViewCell? in
            guard let message = try? PersistedMessage.get(with: objectID, within: ObvStack.shared.viewContext) else {
                // This may happen if the message was just deleted. In that case, we return an "invisible" cell that will soon be deleted by the collection view anyway.
                // This technique avoids to return nil, preventing a crash of the entire app.
                return collectionView.dequeueConfiguredReusableCell(using: invisibleCellRegistration, for: indexPath, item: objectID)
            }
            if let messageSent = message as? PersistedMessageSent {
                return collectionView.dequeueConfiguredReusableCell(using: sentMessageCellRegistration, for: indexPath, item: messageSent)
            } else if let messageReceived = message as? PersistedMessageReceived {
                return collectionView.dequeueConfiguredReusableCell(using: receivedMessageCellRegistration, for: indexPath, item: messageReceived)
            } else if let messageSystem = message as? PersistedMessageSystem {
                return collectionView.dequeueConfiguredReusableCell(using: systemMessageCellRegistration, for: indexPath, item: messageSystem)
            } else {
                // See the comment above, where we also return an "invisible" cell.
                return collectionView.dequeueConfiguredReusableCell(using: invisibleCellRegistration, for: indexPath, item: objectID)
            }
        }
                        
        self.dataSource.supplementaryViewProvider = { (view, kind, index) in
            assert(kind == NewSingleDiscussionViewController.sectionHeaderElementKind)
            return collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: index)
        }

        try? frc.performFetch()
        
    }
    
    
    private func updateDateSupplementaryView(_ dateSupplementaryView: DateSupplementaryView, at indexPath: IndexPath) {
        guard let title = getSectionTitle(at: indexPath) else {
            dateSupplementaryView.text = nil
            return
        }
        if dateSupplementaryView.text != title {
            dateSupplementaryView.text = title
        }
    }
    
    
    private func updateSystemMessageCell(_ cell: SystemMessageCell, at indexPath: IndexPath, with message: PersistedMessageSystem) {
        cell.updateWith(message: message, indexPath: indexPath)
    }
    
    
    private func updateReceivedMessageCell(_ cell: ReceivedMessageCell, at indexPath: IndexPath, with message: PersistedMessageReceived) {
        var prvMessageIsFromSameContact = false
        if let discussionEntityName = discussionObjectID.entityName {
            if [PersistedGroupDiscussion.entityName, PersistedGroupV2Discussion.entityName].contains(discussionEntityName) {
                prvMessageIsFromSameContact = previousMessageIsFromSameContact(message: message)
            }
        }
        let searchedTextToHighlight = getSearchedTextToHighlight(for: message)
        cell.updateWith(message: message,
                        searchedTextToHighlight: searchedTextToHighlight,
                        indexPath: indexPath,
                        draftObjectID: draftObjectID,
                        previousMessageIsFromSameContact: prvMessageIsFromSameContact,
                        cacheDelegate: cacheDelegate,
                        cellReconfigurator: self,
                        textBubbleDelegate: self,
                        audioPlayerViewDelegate: self,
                        shortcutMenuDelegate: self,
                        replyToDelegate: self,
                        locationViewDelegate: self)
    }

    
    private func updateSentMessageCell(_ cell: SentMessageCell, at indexPath: IndexPath, with message: PersistedMessageSent) {
        let searchedTextToHighlight = getSearchedTextToHighlight(for: message)
        cell.updateWith(message: message,
                        searchedTextToHighlight: searchedTextToHighlight,
                        indexPath: indexPath,
                        draftObjectID: draftObjectID,
                        cacheDelegate: cacheDelegate,
                        cellReconfigurator: self,
                        textBubbleDelegate: self,
                        shortcutMenuDelegate: self,
                        replyToDelegate: self,
                        locationViewDelegate: self)
    }
    
    
    /// This helper method is used when configuring the cell of sent or received message.
    /// The messagesContainingSearchedText is non-nil during a search.
    /// If the message corresponding to this cell appears in this messagesContainingSearchedText array, the message
    /// certainly contains the searched word, found in the text attribute of the searchBar. In that case, we retrieve the searched
    /// term and returning, making it possible to pass it to the cell as an indication of what to highlight in, e.g., the text bubble.
    private func getSearchedTextToHighlight(for message: PersistedMessage) -> String? {
        if messagesContainingSearchedText?.contains(message.typedObjectID) == true {
            return self.searchController.searchBar.text
        } else {
            return nil
        }
    }
    
        
    private func getSectionTitle(at indexPath: IndexPath) -> String? {
        guard let sections = frc.sections else {
            fatalError("No sections in fetchedResultsController")
        }
        guard indexPath.section < sections.count else { return nil }
        let sectionInfo = sections[indexPath.section]
        let sectionIdentifier = sectionInfo.name
        guard let components = PersistedMessage.getDateComponents(fromSectionIdentifier: sectionIdentifier), let date = components.date else {
            assertionFailure()
            return ""
        }
        let calendar = Calendar.current
        let sectionTitle: String
        if calendar.isDateInToday(date) || calendar.isDateInYesterday(date) {
            sectionTitle = dateFormaterForHeadersTodayOrYesterday.string(from: date).capitalized
        } else if let year = components.year, year == calendar.component(.year, from: Date()) {
            if let month = components.month, month == calendar.component(.month, from: Date()) {
                sectionTitle = [dateFormaterForHeadersWeekday.string(from: date).capitalized, dateFormaterForHeadersDay.string(from: date)].joined(separator: " ")
            } else {
                sectionTitle = dateFormaterForHeadersCurrentYear.string(from: date).capitalized
            }
        } else {
            sectionTitle = dateFormaterForHeaders.string(from: date).capitalized
        }
        return sectionTitle
    }


    
    @objc(refreshCellCountdowns)
    private func refreshCellCountdowns() {
        collectionView?.visibleCells.forEach {
            if let sentMessageCell = $0 as? SentMessageCell {
                guard sentMessageCell.message?.isEphemeralMessage == true else { return }
                sentMessageCell.refreshCellCountdown()
            } else if let receivedMessageCell = $0 as? ReceivedMessageCell {
                guard receivedMessageCell.message?.isEphemeralMessage == true else { return }
                receivedMessageCell.refreshCellCountdown()
            }
        }
    }

    
    private func settingsButtonTapped() {
        guard let discussion = try? PersistedDiscussion.get(objectID: discussionObjectID, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
        guard let vc = DiscussionSettingsHostingViewController(discussionSharedConfiguration: discussion.sharedConfiguration, discussionLocalConfiguration: discussion.localConfiguration) else {
            assertionFailure()
            return
        }
        present(vc, animated: true)
    }
    
    
    private func galleryButtonTapped() {
        let vc = DiscussionGalleryViewController(discussionObjectID: discussionObjectID)
        let nav = ObvNavigationController(rootViewController: vc)
        present(nav, animated: true)
    }

    
    @objc func callButtonTapped() {
        // Dismiss the keyboard (since we will most probably switch to the call view controller)
        // Then try to call
        guard let discussion = try? PersistedDiscussion.get(objectID: discussionObjectID, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
        switch try? discussion.kind {
        case .oneToOne(withContactIdentity: let contactIdentity):
            guard let contactCryptoId = contactIdentity?.cryptoId,
                  let ownedCryptoId = contactIdentity?.ownedIdentity?.cryptoId else {
                return
            }
            ObvMessengerInternalNotification.userWantsToCallOrUpdateCallCapabilityButWeShouldCheckSheIsAllowedTo(ownedCryptoId: ownedCryptoId, contactCryptoIds: Set([contactCryptoId]), groupId: nil, startCallIntent: nil)
                .postOnDispatchQueue(internalQueue)
        case .groupV1(withContactGroup: let contactGroup):
            if let contactGroup = contactGroup, let groupV1Identifier = try? contactGroup.getGroupId() {
                let contactCryptoIds = contactGroup.contactIdentities.compactMap { $0.cryptoId }
                guard let ownedCryptoId = contactGroup.ownedIdentity?.cryptoId else { return }
                ObvMessengerInternalNotification.userWantsToSelectAndCallContacts(ownedCryptoId: ownedCryptoId, contactCryptoIds: Set(contactCryptoIds), groupId: .groupV1(groupV1Identifier: groupV1Identifier))
                    .postOnDispatchQueue(internalQueue)
            }
        case .groupV2(withGroup: let group):
            if let group {
                guard let ownedCryptoId = try? group.ownCryptoId else { return }
                let contactCryptoIds = group.contactsAmongNonPendingOtherMembers.compactMap { $0.cryptoId }
                let groupV2Identifier = group.groupIdentifier
                ObvMessengerInternalNotification.userWantsToSelectAndCallContacts(ownedCryptoId: ownedCryptoId, contactCryptoIds: Set(contactCryptoIds), groupId: .groupV2(groupV2Identifier: groupV2Identifier))
                    .postOnDispatchQueue(internalQueue)
            }
        case .none:
            assertionFailure()
        }
    }


    // Refresh the discussion title if it is updated
    private func observePersistedDiscussionChanges() {
        let notification = NSNotification.Name.NSManagedObjectContextObjectsDidChange
        observationTokens.append(NotificationCenter.default.addObserver(forName: notification, object: nil, queue: nil) { [weak self] notification in
            guard let notificationContext = notification.object as? NSManagedObjectContext else { assertionFailure(); return }
            guard notificationContext == ObvStack.shared.viewContext else { return }
            guard let refreshedObject = notification.userInfo?[NSRefreshedObjectsKey] as? Set<NSManagedObject> else { return }
            OperationQueue.main.addOperation { [weak self] in
                guard let self else { return }
                guard viewDidAppearWasCalled else { return }
                
                /// Computes the set of refreshed discussions
                let currentDiscussionDidChange = refreshedObject
                    .compactMap({ $0 as? PersistedDiscussion })
                    .map({ $0.typedObjectID })
                    .contains(where: { $0 == self.discussionObjectID })
                
                if currentDiscussionDidChange {
                    self.configureNavigationTitle()
                }
            }
        })
    }


    private func observePersistedObvContactIdentityChanges() {
        let notification = NSNotification.Name.NSManagedObjectContextObjectsDidChange
        observationTokens.append(NotificationCenter.default.addObserver(forName: notification, object: nil, queue: nil) { [weak self] notification in
            guard let notificationContext = notification.object as? NSManagedObjectContext else { assertionFailure(); return }
            guard notificationContext == ObvStack.shared.viewContext else { return }
            guard let refreshedObject = notification.userInfo?[NSRefreshedObjectsKey] as? Set<NSManagedObject> else { return }
            OperationQueue.main.addOperation { [weak self] in
                guard let self else { return }
                guard self.viewDidAppearWasCalled else { return }
                let refreshedContactObject = refreshedObject
                    .compactMap({ $0 as? PersistedObvContactIdentity })
                
                /// Computes the set of contact groups where at least one contact has been refreshed and check whether the current discussion is one of the discussions associated to those group
                
                if refreshedContactObject
                    .flatMap({ $0.contactGroups })
                    .contains(where: { $0.discussion.typedObjectID.downcast == self.discussionObjectID }) {
                    /// If the current discussion has changed, reconfigure the title
                    self.configureNavigationTitle()
                    
                    /// We know here that at least one contact of the group was refreshed.
                    ObvStack.shared.viewContext.registeredObjects
                        .compactMap { $0 as? PersistedMessageReceived }
                        .filter {
                            guard let contact = $0.contactIdentity else { return false }
                            return refreshedContactObject.contains(contact)
                        }
                        .forEach { ObvStack.shared.viewContext.refresh($0, mergeChanges: true) }
                } else if refreshedContactObject
                    .compactMap({ $0.oneToOneDiscussion })
                    .contains(where: { $0.typedObjectID.downcast == self.discussionObjectID }) {
                    /// If the current discussion has changed, reconfigure the title
                    self.configureNavigationTitle()
                }
            }
        })
    }

    private func observeRouteChange() {
        observationTokens.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] _ in
            OperationQueue.main.addOperation {
                self?.collectionView?.visibleCells.forEach { cell in
                    guard let audioPlayerView = cell.deepSearchSubView(ofClass: AudioPlayerView.self) else { return }
                    audioPlayerView.configureSpeakerButton()
                }
            }
        })
    }

    
    private func insertSystemMessageIfCurrentDiscussionIsEmpty() {
        guard let discussion = try? PersistedDiscussion.get(objectID: discussionObjectID, within: ObvStack.shared.viewContext) else { return }
        guard discussion.messages.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            try? await delegate?.insertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty(self, discussionObjectID: discussionObjectID, markAsRead: true)
        }
    }

    private func reconfigureCellsShowingCallLogItemRejectedIncomingCallBecauseOfDeniedRecordPermission() {
        assert(Thread.isMainThread)
        guard let messagesSystem = self.frc.fetchedObjects?.compactMap({ $0 as? PersistedMessageSystem }) else { return }
        var itemsToReconfigure = [NSManagedObjectID]()
        for message in messagesSystem {
            guard let callLogItem = message.optionalCallLogItem,
                  let callReportKind = callLogItem.callReportKind,
                  callReportKind == .rejectedIncomingCallBecauseOfDeniedRecordPermission else {
                      continue
                  }
            itemsToReconfigure += [message.objectID]
        }
        self.queueForApplyingSnapshots.async {
            debugPrint("😤 Will call apply for the new snapshot")
            var snapshot = self.dataSource.snapshot()
            snapshot.reconfigureItems(itemsToReconfigure)
            self.dataSource.apply(snapshot, animatingDifferences: true) 
        }
    }

}

// MARK: - Implementing MessageReactionsListHostingViewControllerDelegate

extension NewSingleDiscussionViewController: MessageReactionsListHostingViewControllerDelegate {
    
    func userWantsToUpdateReaction(_ messageReactionsListHostingViewController: MessageReactionsListHostingViewController, ownedCryptoId: ObvTypes.ObvCryptoId, messageObjectID: ObvUICoreData.TypeSafeManagedObjectID<ObvUICoreData.PersistedMessage>, newEmoji: String?) async throws {
        guard let delegate else { assertionFailure(); throw Self.makeError(message: "delegate is nil") }
        try await delegate.userWantsToUpdateReaction(self, ownedCryptoId: ownedCryptoId, messageObjectID: messageObjectID, newEmoji: newEmoji)
    }
    
}


// MARK: - Implementing VisibilityTrackerForSensitiveMessagesDelegate

extension NewSingleDiscussionViewController: VisibilityTrackerForSensitiveMessagesDelegate {
    
    func updatedSetOfCurrentlyDisplayedMessagesWithLimitedVisibility(_ visibilityTrackerForSensitiveMessages: VisibilityTrackerForSensitiveMessages, discussionPermanentID: ObvUICoreData.ObvManagedObjectPermanentID<ObvUICoreData.PersistedDiscussion>, messagePermanentIDs: Set<ObvUICoreData.ObvManagedObjectPermanentID<ObvUICoreData.PersistedMessage>>) async throws {
        guard let delegate else { assertionFailure(); throw Self.makeError(message: "delegate is nil") }
        try await delegate.updatedSetOfCurrentlyDisplayedMessagesWithLimitedVisibility(self, discussionPermanentID: discussionPermanentID, messagePermanentIDs: messagePermanentIDs)
    }
    
}


// MARK: - Implementing search within this discussion

extension NewSingleDiscussionViewController {
    
    private var addSearchItemInMenu: Bool {
        !ObvMessengerConstants.targetEnvironmentIsMacCatalyst
    }
    
    
    /// Called in ``viewDidLoad()``, in order to add the `searchController` to the navigation.
    /// We set the `isActive` property to `false` so that the search bar is initally hidden, and only shown
    /// when the user taps on the search button (in which case ``searchButtonTapped()`` is called).
    private func configureSearchController() {
        self.searchController.delegate = self
        self.searchController.searchResultsUpdater = searchControllerDelegate
        self.searchController.searchBar.delegate = searchControllerDelegate
        self.searchController.searchBar.searchBarStyle = .prominent
        self.searchController.hidesNavigationBarDuringPresentation = true
        self.searchController.searchBar.autocapitalizationType = .none
        self.navigationItem.searchController = self.searchController
        self.navigationItem.searchController?.isActive = false
        singleDiscussionSearchView.setResultsPublisher(resultsPublisher: searchControllerDelegate.$searchResults)
        continuouslyUpdateSearchResults()
        continuouslyReloadDiscussionOnSettings()
        continuouslyProcessSearchedMessageToScrollTo()
        
        // If we don't add a search menu item, we want to use the search bar to display the tip about search
        if !addSearchItemInMenu {
            self.viewSavedToDisplayTip = self.searchController.searchBar
        }
        
    }


    /// Called when configuring the search controller, this method observes the search results published by the search controller delegate.
    /// When the results change, we reconfigure the cell corresponding to the previous results (so as to make sure no previously searched word
    /// is highlighted), we save the results locally (this will be used by the code that reconfigures a cell, to determine if the cell contains the searched word),
    /// and we reconfigure all the cells displaying a message appearing in the results (so as to highlight the search word).
    private func continuouslyUpdateSearchResults() {
        searchControllerDelegate.$searchResults
            .receive(on: OperationQueue.main)
            .sink { [weak self] results in
                guard let self else { return }
                messagesToReconfigure.formUnion(messagesContainingSearchedText ?? [])
                messagesContainingSearchedText = results
                messagesToReconfigure.formUnion(messagesContainingSearchedText ?? [])
            }
            .store(in: &cancellables)
    }
    
    
    /// When the user changes the ``hideGroupMemberChangeMessages`` setting while a discussion is shown, we want to refresh to this discussion
    /// to make sure the latest value of the setting is respected.
    private func continuouslyReloadDiscussionOnSettings() {
        ObvMessengerSettingsObservableObject.shared.$hideGroupMemberChangeMessages
            .removeDuplicates()
            .receive(on: OperationQueue.main)
            .sink { [weak self] value in
                guard let self else { return }
                guard self.hideGroupMemberChangeMessages != value else { return }
                self.hideGroupMemberChangeMessages = value
                self.frc?.fetchRequest.predicate = PersistedMessage.getFetchRequestPredicateForAllMessagesWithinDiscussion(
                    discussionObjectID: self.discussionObjectID,
                    includeMembersOfGroupV2WereUpdated: !hideGroupMemberChangeMessages,
                    within: ObvStack.shared.viewContext)
                try? self.frc?.performFetch()
            }
            .store(in: &cancellables)
    }
    
    
    /// Called when configuring the search controller, this method observes the "search result to scroll to" published by the search controller delegate.
    /// When a new value is published, we scroll to the message.
    private func continuouslyProcessSearchedMessageToScrollTo() {
        singleDiscussionSearchView.$searchResultToScrollTo
            .receive(on: OperationQueue.main)
            .sink { [weak self] messageObjectID in
                guard let messageObjectID else { return }
                guard let message = try? PersistedMessage.get(with: messageObjectID, within: ObvStack.shared.viewContext) else { return }
                self?.scrollTo(message: message)
            }
            .store(in: &cancellables)
    }
    

    private func configureSearchViewHierarchy() {
        view.addSubview(singleDiscussionSearchView)
        singleDiscussionSearchView.translatesAutoresizingMaskIntoConstraints = false

        // The bottom anchor of the search view is pinned to the bottom of the screen. Note that its main content
        // view is pinned to the top of the keyboard.
        singleDiscussionSearchView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true

        NSLayoutConstraint.activate([
            singleDiscussionSearchView.widthAnchor.constraint(equalTo: view.widthAnchor),
            singleDiscussionSearchView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        ])
    }

    
    @objc private func searchButtonTapped() {
        userWantsToStartNewSearch()
    }
    
    
    /// In practice, this is called by our parent `MainFlowViewController` when the user types the keyboard shortcut for search.
    override func find(_ sender: Any?) {
        userWantsToStartNewSearch()
    }
    
    
    /// In practice, this is called by our parent `MainFlowViewController` when the user types the keyboard shortcut for "Find next".
    ///
    /// We pass this information to the `SingleDiscussionSearchView` that centralizes the logic allowing to cycle through the search results.
    override func findNext(_ sender: Any?) {
        singleDiscussionSearchView.findNext(sender)
    }
    
    
    /// In practice, this is called by our parent `MainFlowViewController` when the user types the keyboard shortcut for "Find previous".
    ///
    /// We pass this information to the `SingleDiscussionSearchView` that centralizes the logic allowing to cycle through the search results.
    override func findPrevious(_ sender: Any?) {
        singleDiscussionSearchView.findPrevious(sender)
    }
    
    
    private func userWantsToStartNewSearch() {
        if isUserPerformingSearch { return }
        isUserPerformingSearch = true
        self.navigationItem.searchController?.isActive = true
        configureAcessoryViewVisibility(animate: true)
    }
    
    
    // Part of the UISearchControllerDelegate protocol. Called when the user hits cancel in the search controller.
    // In that case, we want to hide the search accessory and show the normal compose view if appropriate.
    func willDismissSearchController(_ searchController: UISearchController) {
        isUserPerformingSearch = false
        configureAcessoryViewVisibility(animate: true)
        messagesToReconfigure.formUnion(messagesContainingSearchedText ?? [])
        self.messagesContainingSearchedText = nil
    }
    
    
    // Part of the UISearchControllerDelegate protocol. Called when the search controller is presented.
    // We use a trick allowing to make the searchBar become the first responder immediately.
    func didPresentSearchController(_ searchController: UISearchController) {
        // Under macOS, there is no search entry in the menu.
        // The user triggers the search by tapping in the search bar, which triggers a call to this method.
        // For this reason, we need to call the ``userWantsToStartNewSearch()`` method here.
        // Under iOS, it will be called twice, which is ok.
        userWantsToStartNewSearch()
        DispatchQueue.main.async { [weak self] in
            self?.searchController.searchBar.becomeFirstResponder()
        }
    }
    
}


// MARK: - NSFetchedResultsControllerDelegate

extension NewSingleDiscussionViewController {
    
    /// Shall only be called from
    /// `func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference)`
    private func scrollToBottomAfterApplyingSnapshot(controller: NSFetchedResultsController<NSFetchRequestResult>) -> Bool {
                
        guard let fetchedObjects = controller.fetchedObjects else { return false }
        
        var newMessageWasReceived = false // PersistedMessageReceived
        var newMessageWasSent = false // PersistedMessageSent
        var newSystemMessage = false // Any system message unless the category is numberOfNewMessages
                    
        let lastReceivedMessageObjectId = (fetchedObjects.last(where: { $0 is PersistedMessageReceived }) as? PersistedMessageReceived)?.typedObjectID
        newMessageWasReceived = self.lastReceivedMessageObjectId != lastReceivedMessageObjectId
        self.lastReceivedMessageObjectId = lastReceivedMessageObjectId
        
        let lastSentMessageObjectId = (fetchedObjects.last(where: { $0 is PersistedMessageSent }) as? PersistedMessageSent)?.typedObjectID
        newMessageWasSent = self.lastSentMessageObjectId != lastSentMessageObjectId
        self.lastSentMessageObjectId = lastSentMessageObjectId
        
        if let lastSystemMessageObjectId = (fetchedObjects.last(where: {
            guard let messageSystem = $0 as? PersistedMessageSystem else { return false }
            return messageSystem.category != .numberOfNewMessages
        }) as? PersistedMessageSystem)?.typedObjectID {
            newSystemMessage = self.lastSystemMessageObjectId != lastSystemMessageObjectId
            self.lastSystemMessageObjectId = lastSystemMessageObjectId
        }
            
        if !atLeastOneSnapshotWasApplied {
            return false
        } else if currentScrolling != .none {
            return false
        } else {
            return newMessageWasSent || (newMessageWasReceived && !lastScrollWasManual) || newSystemMessage
        }

    }
    
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        
        let collectionView = self.collectionView!
        guard let dataSource = collectionView.dataSource as? UICollectionViewDiffableDataSource<Int, NSManagedObjectID> else { assertionFailure(); return }
        
        let newSnapshot = snapshot as NSDiffableDataSourceSnapshot<Int, NSManagedObjectID>
        
        // Determine whether we should scroll after updating the collection view
        let shouldScrollToBottom = scrollToBottomAfterApplyingSnapshot(controller: controller)
        debugPrint("🦄 shouldScrollToBottom: \(shouldScrollToBottom)")
        
        // We want to perform automatic scrolling to the bottom when the local user sends a message.
        // Although `shouldScrollToBottom` is set to true in this scenario, it may happen that we attempt to scroll before the collection view
        // has had time to display the cell. This can result in the scroll ending just above the sent message cell. To address this issue, we
        // detect here whether the local user has sent a new message and store its identifier if this is the case. This identifier will be used (and reset)
        // when `collectionView(_:willDisplay:forItemAt:)` is called to perform an asynchronous scroll to bottom when the cell corresponding to this
        // message is displayed. If the initial scroll attempt in this method falls short and stops just above the sent message cell, the
        // `collectionView(_:willDisplay:forItemAt:)` method will be invoked to "complete" the scroll.
        
        do {
            let currentSnapshot = dataSource.snapshot()
            let newItemIdentifiers = newSnapshot.itemIdentifiers
            let currentItemIdentifiers = currentSnapshot.itemIdentifiers
            if newItemIdentifiers.count == currentItemIdentifiers.count+1,
               newItemIdentifiers.starts(with: currentItemIdentifiers),
               let lastNewItemIdentifier = newItemIdentifiers.last,
               let lastNewItemAsSentMessage = frc.managedObjectContext.registeredObjects.first(where: { $0.objectID == lastNewItemIdentifier }) as? PersistedMessageSent {
                self.objectIDSentMessageJustSent = lastNewItemAsSentMessage.typedObjectID
            }
        }
        
        // AppStateManager.shared.addCompletionHandlerToExecuteWhenInitializedAndActive { [weak self] in
            
        queueForApplyingSnapshots.async {
            
            debugPrint("😤💿 Will call apply for the new snapshot")
            
            dataSource.apply(newSnapshot, animatingDifferences: true) { [weak self] in
                debugPrint("😤💿 Did call apply for the new snapshot")
                DispatchQueue.main.async {
                    guard let _self = self else { return }
                    _self.atLeastOneSnapshotWasApplied = true
                    if _self.initialScrollWasPerformed {
                        guard _self.viewDidAppearWasCalled else { return }
                        if shouldScrollToBottom {
                            _self.simpleScrollToBottom()
                        }
                    } else {
                        _self.performInitialScrollIfAppropriateAndRemoveHidingView()
                    }
                }
            }
            
        }
            
        // }
        
    }

}


// MARK: - CellReconfigurator

extension NewSingleDiscussionViewController {
    
    /// Called exactly once, from viewDidLoad
    private func observeMessagesToReconfigure() {
        cancellables.append(
            $messagesToReconfigure
                .filter { !$0.isEmpty }
                .debounce(for: 0.3, scheduler: RunLoop.main)
                .map { [weak self] messageObjectIDs -> [NSManagedObjectID] in
                    assert(Thread.isMainThread)
                    self?.messagesToReconfigure.removeAll()
                    return messageObjectIDs.map { $0.objectID }
                }
                .receive(on: queueForApplyingSnapshots)
                .sink { [weak self] objectIDs in
                    guard var snapshot = self?.dataSource.snapshot() else { return }
                    let messageObjectIDsToReconfigure = objectIDs.filter({ snapshot.itemIdentifiers.contains($0)})
                    guard !messageObjectIDsToReconfigure.isEmpty else { return }
                    snapshot.reconfigureItems(messageObjectIDsToReconfigure)
                    self?.dataSource.apply(snapshot, animatingDifferences: false)
                }
        )
    }
    
    
    func cellNeedsToBeReconfiguredAndResized(messageID: TypeSafeManagedObjectID<PersistedMessage>) {
        assert(Thread.isMainThread)
        guard viewDidAppearWasCalled else { return }
        messagesToReconfigure.insert(messageID)
    }
    
    
    /// When the status of an attachment sent from another owned device changes, we reconfigure de cell of the corresponding message. This, e.g., makes it possible to actually see the photo once it is fully downloaded.
    @MainActor
    private func processStatusOfSentFyleMessageJoinDidChange(sentJoinID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>, messageID: TypeSafeManagedObjectID<PersistedMessageSent>, discussionID: TypeSafeManagedObjectID<PersistedDiscussion>) async {
        guard self.discussionObjectID == discussionID else { return }
        cellNeedsToBeReconfiguredAndResized(messageID: messageID.downcast)
    }
    
}


// MARK: - Managing the "new messages" system message

extension NewSingleDiscussionViewController {

    /// This method is called once, during init, to compute the initial value of the `objectIDsOfMessagesToConsiderInNewMessagesCell` set.
    private func computeInitialValueOfObjectIDsOfMessagesToConsiderInNewMessagesCell() throws {
        guard let discussion = try PersistedDiscussion.get(objectID: discussionObjectID, within: ObvStack.shared.viewContext) else {
            throw Self.makeError(message: "Could not find discussion")
        }
        let newReceivedMessages = try PersistedMessageReceived.getAllNew(in: discussion)
        let newSystemMessages = try PersistedMessageSystem.getAllNewRelevantSystemMessages(in: discussion)
        let objectIDsOfNewReceivedMsgs = newReceivedMessages.map({ $0.typedObjectID.downcast })
        let objectIDsOfNewSystemdMsgs = newSystemMessages.map({ $0.typedObjectID.downcast })
        objectIDsOfMessagesToConsiderInNewMessagesCell.formUnion(objectIDsOfNewReceivedMsgs)
        objectIDsOfMessagesToConsiderInNewMessagesCell.formUnion(objectIDsOfNewSystemdMsgs)
    }
    
    
    private func insertOrUpdateSystemMessageCountingNewMessages(removeExisting: Bool) {
        do {
            guard let discussion = try PersistedDiscussion.getManagedObject(withPermanentID: discussionPermanentID, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
            if removeExisting || objectIDsOfMessagesToConsiderInNewMessagesCell.isEmpty {
                unreadMessagesSystemMessage = nil
                try PersistedMessageSystem.removeAnyNewMessagesSystemMessages(withinDiscussion: discussion)
            }
            let appropriateNumberOfNewMessages = objectIDsOfMessagesToConsiderInNewMessagesCell.count
                
            let messages = try objectIDsOfMessagesToConsiderInNewMessagesCell.compactMap({ try PersistedMessage.get(with: $0.objectID, within: ObvStack.shared.viewContext) })
            guard let firstNewMessage = messages.sorted(by: { $0.sortIndex < $1.sortIndex }).first else { return }

            let timestampForFirstNewMessageLimit = firstNewMessage.timestamp

            let sortIndexForFirstNewMessageLimit: Double
            
            if let messageAboveFirstUnNewReceivedMessage = try? PersistedMessage.getMessage(beforeSortIndex: firstNewMessage.sortIndex, in: discussion) {
                if (messageAboveFirstUnNewReceivedMessage as? PersistedMessageSystem)?.category == .numberOfNewMessages {
                    // The message just above the first new message is a PersistedMessageSystem showing the number of new messages
                    // We can simply use its sortIndex
                    sortIndexForFirstNewMessageLimit = messageAboveFirstUnNewReceivedMessage.sortIndex
                } else {
                    // The message just above the first new message is *not* a PersistedMessageSystem showing the number of new messages
                    // We compute the mean of the sort indexes of the two messages to get a sortIndex appropriate to "insert" a new message between the two
                    let preceedingSortIndex = messageAboveFirstUnNewReceivedMessage.sortIndex
                    sortIndexForFirstNewMessageLimit = (firstNewMessage.sortIndex + preceedingSortIndex) / 2.0
                }
            } else {
                // There is no message above, we simply take a smaller sort index
                let preceedingSortIndex = firstNewMessage.sortIndex - 1
                sortIndexForFirstNewMessageLimit = (firstNewMessage.sortIndex + preceedingSortIndex) / 2.0
            }
            
            unreadMessagesSystemMessage = try PersistedMessageSystem.insertOrUpdateNumberOfNewMessagesSystemMessage(within: discussion,
                                                                                                                    timestamp: timestampForFirstNewMessageLimit,
                                                                                                                    sortIndex: sortIndexForFirstNewMessageLimit,
                                                                                                                    appropriateNumberOfNewMessages: appropriateNumberOfNewMessages)
            
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }

    
    /// When a new message is sent (which is equivalent of a new `PersistedMessageSent` after viewDidAppear was called), we remove the system message showing new received messages count
    private func updateNewMessageCellOnInsertionOfSentMessage() {
        let notification = NSNotification.Name.NSManagedObjectContextObjectsDidChange
        observationTokens.append(NotificationCenter.default.addObserver(forName: notification, object: nil, queue: nil) { [weak self] notification in
            guard let notificationContext = notification.object as? NSManagedObjectContext else { assertionFailure(); return }
            guard notificationContext == ObvStack.shared.viewContext else { return }
            guard let insertedObjects = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> else { return }
            OperationQueue.main.addOperation {
                guard let self else { return }
                guard self.viewDidAppearWasCalled else { return }
                guard !self.objectIDsOfMessagesToConsiderInNewMessagesCell.isEmpty else { return }
                let newSentMessages = insertedObjects
                    .compactMap({ $0 as? PersistedMessageSent })
                    .filter({ $0.discussion?.typedObjectID == self.discussionObjectID })
                guard !newSentMessages.isEmpty else { return }
                self.objectIDsOfMessagesToConsiderInNewMessagesCell.removeAll()
                // We asynchronously call `insertOrUpdateSystemMessageCountingNewMessages`.
                // This ensures that we do not include an item deletion (the system message) as well as an item insertion (the new sent message) in the diffable datasource snapshot. In theory, this should work. In practice, the animations look ugly. Forcing two distinct snapshots (the first for the sent message inserting, the second for the deletion of the system message counting new messages) results in nice looking animations. Yes, this is a hack.
                DispatchQueue.main.async { [weak self] in
                    self?.insertOrUpdateSystemMessageCountingNewMessages(removeExisting: false)
                }
            }
        })
    }

    
    /// We observe insertion of received messages so as to update the system message cell counting new messages.
    private func updateNewMessageCellOnInsertionOfReceivedMessages() {
        let notification = NSNotification.Name.NSManagedObjectContextObjectsDidChange
        observationTokens.append(NotificationCenter.default.addObserver(forName: notification, object: nil, queue: nil) { [weak self] notification in
            guard let notificationContext = notification.object as? NSManagedObjectContext else { assertionFailure(); return }
            guard notificationContext == ObvStack.shared.viewContext else { return }
            guard let insertedObjects = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> else { return }
            OperationQueue.main.addOperation {
                guard let self else { return }
                guard self.viewDidAppearWasCalled else { return }
                let insertedReceivedMessages = insertedObjects
                    .compactMap({ $0 as? PersistedMessageReceived })
                    .filter({ $0.discussion?.typedObjectID == self.discussionObjectID })
                let objectIDsOfInsertedReceivedMessages = Set(insertedReceivedMessages.map({ $0.typedObjectID.downcast }))
                guard !objectIDsOfInsertedReceivedMessages.isSubset(of: self.objectIDsOfMessagesToConsiderInNewMessagesCell) else { return }
                self.objectIDsOfMessagesToConsiderInNewMessagesCell.formUnion(objectIDsOfInsertedReceivedMessages)
                self.insertOrUpdateSystemMessageCountingNewMessages(removeExisting: false)
            }
        })
    }
    
    
    /// We observe insertion of relevant system messages so as to update the system message cell counting new messages.
    private func updateNewMessageCellOnInsertionOfRelevantSystemMessages() {
        let notification = NSNotification.Name.NSManagedObjectContextObjectsDidChange
        observationTokens.append(NotificationCenter.default.addObserver(forName: notification, object: nil, queue: nil) { [weak self] notification in
            guard let notificationContext = notification.object as? NSManagedObjectContext else { assertionFailure(); return }
            guard notificationContext == ObvStack.shared.viewContext else { return }
            guard let insertedObjects = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> else { return }
            OperationQueue.main.addOperation {
                guard let self else { return }
                guard self.viewDidAppearWasCalled else { return }
                let insertedSystemMessages = insertedObjects
                    .compactMap({ $0 as? PersistedMessageSystem })
                    .filter({ $0.discussion?.typedObjectID == self.discussionObjectID })
                let insertedRelevantSystemMessages = insertedSystemMessages
                    .filter({ $0.isRelevantForCountingUnread })
                    .filter({ $0.optionalContactIdentity != nil })
                let objectIDsOfInsertedRelevantSystemMessages = Set(insertedRelevantSystemMessages.map({ $0.typedObjectID.downcast }))
                guard !objectIDsOfInsertedRelevantSystemMessages.isSubset(of: self.objectIDsOfMessagesToConsiderInNewMessagesCell) else { return }
                self.objectIDsOfMessagesToConsiderInNewMessagesCell.formUnion(objectIDsOfInsertedRelevantSystemMessages)
                self.insertOrUpdateSystemMessageCountingNewMessages(removeExisting: false)
            }
        })
    }

    /// We observe deletion of received messages so as to update the system message cell counting new messages.
    private func updateNewMessageCellOnDeletionOfReceivedMessages() {
        observationTokens.append(ObvMessengerCoreDataNotification.observePersistedMessageReceivedWasDeleted { [weak self] (objectID, _, _, _, discussionObjectID) in
            OperationQueue.main.addOperation {
                guard let _self = self else { return }
                guard discussionObjectID == _self.discussionObjectID else { return }
                let messageObjectID = TypeSafeManagedObjectID<PersistedMessage>(objectID: objectID)
                guard _self.objectIDsOfMessagesToConsiderInNewMessagesCell.contains(messageObjectID) else { return }
                _self.objectIDsOfMessagesToConsiderInNewMessagesCell.remove(messageObjectID)
                _self.insertOrUpdateSystemMessageCountingNewMessages(removeExisting: false)
            }
        })
    }
    
    
    /// We observe deletion of system messages so as to update the system message cell counting new messages if appropriate.
    private func updateNewMessageCellOnDeletionOfRelevantSystemMessages() {
        observationTokens.append(ObvMessengerCoreDataNotification.observePersistedMessageSystemWasDeleted { [weak self] (objectID, discussionObjectID) in
            OperationQueue.main.addOperation {
                guard let _self = self else { return }
                guard discussionObjectID == _self.discussionObjectID else { return }
                let messageObjectID = TypeSafeManagedObjectID<PersistedMessage>(objectID: objectID)
                guard _self.objectIDsOfMessagesToConsiderInNewMessagesCell.contains(messageObjectID) else { return }
                _self.objectIDsOfMessagesToConsiderInNewMessagesCell.remove(messageObjectID)
                _self.insertOrUpdateSystemMessageCountingNewMessages(removeExisting: false)
            }
        })
    }

}


// MARK: - Marking messages as "not new"

extension NewSingleDiscussionViewController {
    
    @MainActor
    private func theUserLeftTheDiscussion() async {
        os_log("🛫 The user left the discussion", log: log, type: .info)
        processReceivedMessagesThatBecameNotNewDuringScrolling()
        if !objectIDsOfMessagesToConsiderInNewMessagesCell.isEmpty {
            objectIDsOfMessagesToConsiderInNewMessagesCell.removeAll()
            // We check whether the discussion was left because the discussion was deleted. If this is not the case, we update the message system counting new messages.
            if (try? PersistedDiscussion.get(objectID: discussionObjectID, within: ObvStack.shared.viewContext)) != nil {
                try? computeInitialValueOfObjectIDsOfMessagesToConsiderInNewMessagesCell()
                insertOrUpdateSystemMessageCountingNewMessages(removeExisting: false)
                // If we have a unreadMessagesSystemMessage, it was just updated. The frc will eventually reload it.
                // We want to perform the same scroll than the initial scroll in order to show this sytem message the next time the user enters the discussion. Note that this is only required to handle the case where the user puts Olvid into the background while being in this discussion, or while navigation from this discussion to another one.
                if unreadMessagesSystemMessage != nil {
                    initialScrollWasPerformed = false
                    // ObvDisplayableLogs.shared.log("[Discussion] Showing hiding view again as the user left the discussion")
                    hidingView.alpha = 1
                    hidingView.isHidden = false
                }
            }
        }

    }
    
    
    /// This method sends a notification allowing the database to mark the message as not new (which will eventually send read receipt if this setting is set)
    private func markAsNotNewTheMessageInCell(_ cell: UICollectionViewCell) {
        guard OlvidUserActivitySingleton.shared.currentDiscussionPermanentID == self.discussionPermanentID else { return }
        guard viewDidAppearWasCalled else { return }
        
        // If the scene is not foreground active, we do not mark visible messages as not new.
        // When going back to the `active` state, a call to `markNewVisibleReceivedAndRelevantSystemMessagesAsNotNew(..)` will be made.
        // This will allow to mark visible messages as not new.
        // 2024-11-18: we use to only ensure that `windowSceneActivationState == .foregroundActive`. This was not sufficient under macOS, where
        // this test passes when the Olvid window is behind another window (a situation where messages should not be marked as not new).
        // 2024-11-19: The traitCollectionActiveAppearance == .active test is not used under iOS as we experienced bugs preventing messages to be marked as not new

        let windowSceneActivationState = self.windowSceneActivationState
        guard windowSceneActivationState == .foregroundActive else {
            Self.logger.debug("🌟[1] Not marking message as read as windowSceneActivationState != .foregroundActive (windowSceneActivationState is \(String(describing: windowSceneActivationState?.obvDebugDescription))")
            return
        }

        if ObvAppCoreConstants.targetEnvironmentIsMacCatalyst {
            let traitCollectionActiveAppearance = OlvidUserActivitySingleton.shared.traitCollectionActiveAppearance
            guard traitCollectionActiveAppearance == .active else {
                Self.logger.debug("🌟[1] Not marking message as read as OlvidUserActivitySingleton.shared.traitCollectionActiveAppearance != .active (traitCollectionActiveAppearance is \(String(describing: traitCollectionActiveAppearance?.obvDebugDescription))")
                return
            }
        }

        let messageId: MessageIdentifier
        if let receivedCell = cell as? ReceivedMessageCell, let receivedMessage = receivedCell.message, receivedMessage.status == .new {
            messageId = .received(id: .objectID(objectID: receivedMessage.objectID))
        } else if let systemCell = cell as? SystemMessageCell, let systemMessage = systemCell.message, systemMessage.status == .new {
            if systemMessage.isRelevantForCountingUnread {
                messageId = .system(id: .objectID(objectID: systemMessage.objectID))
            } else {
                return
            }
        } else {
            return
        }
        
        // If we are currently scrolling, we do *not* notify that a message has been read.
        // This would introduce animation glitches. Instead, we postpone the notification
        if currentScrolling == .none {
            // ObvDisplayableLogs.shared.log("[NewSingleDiscussionViewController] Posting messagesAreNotNewAnymore notification in markAsNotNewTheMessageInCell for \([messageObjectId].count) messages")
            guard let discussionId = try? discussion.identifier else { assertionFailure(); return }
            Self.logger.debug("🌟[1] Will mark one message as read")
            guard let delegate else { assertionFailure(); return }
            Task { [weak self] in
                guard let self else { return }
                try? await delegate.messagesAreNotNewAnymore(self, ownedCryptoId: currentOwnedCryptoId, discussionId: discussionId, messageIds: [messageId])
            }
        } else {
            let currentScrollingDebugDescription = currentScrolling.debugDescription
            Self.logger.debug("🌟[1] Will mark message as read when scrolling ends. Current scrolling is \(currentScrollingDebugDescription)")
            // ObvDisplayableLogs.shared.log("[NewSingleDiscussionViewController] As currentScrolling is \(currentScrolling.debugDescription), we do not post messagesAreNotNewAnymore notification for \([messageObjectId].count) messages")
            // We insert the messageId in the list only if it does not already exists init (note that this code works because the messageIds have a well defined objectID in our particular case).
            if messagesToMarkAsNotNewWhenScrollingEnds.first(where: { $0.objectID == messageId.objectID }) == nil {
                messagesToMarkAsNotNewWhenScrollingEnds.append(messageId)
            }
        }
    }

    
    /// Marks all new received and relevant system messages that are visible as "not new"
    private func markNewVisibleReceivedAndRelevantSystemMessagesAsNotNew() {

        // ObvDisplayableLogs.shared.log("[NewSingleDiscussionViewController] Call to markNewVisibleReceivedAndRelevantSystemMessagesAsNotNew")
        
        // If the scene is not foreground active, we do not mark visible messages as not new.
        // When going back to the `active` state, a call to `markNewVisibleReceivedAndRelevantSystemMessagesAsNotNew(..)` will be made.
        // This will allow to mark visible messages as not new.
        // 2024-11-18: we use to only ensure that `windowSceneActivationState == .foregroundActive`. This was not sufficient under macOS, where
        // this test passes when the Olvid window is behind another window (a situation where messages should not be marked as not new).
        // 2024-11-19: The traitCollectionActiveAppearance == .active test is not used under iOS as we experienced bugs preventing messages to be marked as not new
        
        let windowSceneActivationState = self.windowSceneActivationState
        guard windowSceneActivationState == .foregroundActive else {
            Self.logger.debug("🌟[2] Not marking message as read as windowSceneActivationState != .foregroundActive (windowSceneActivationState is \(String(describing: windowSceneActivationState?.obvDebugDescription))")
            return
        }

        if ObvAppCoreConstants.targetEnvironmentIsMacCatalyst {
            let traitCollectionActiveAppearance = OlvidUserActivitySingleton.shared.traitCollectionActiveAppearance
            guard traitCollectionActiveAppearance == .active else {
                Self.logger.debug("🌟[2] Not marking message as read as OlvidUserActivitySingleton.shared.traitCollectionActiveAppearance != .active (traitCollectionActiveAppearance is \(String(describing: traitCollectionActiveAppearance?.obvDebugDescription))")
                return
            }
        }
        
        // ObvDisplayableLogs.shared.log("[NewSingleDiscussionViewController] Performing markNewVisibleReceivedAndRelevantSystemMessagesAsNotNew")
        
        let visibleReceivedCells = collectionView.visibleCells.compactMap({ $0 as? ReceivedMessageCell })
        let visibleSystemCells = collectionView.visibleCells.compactMap({ $0 as? SystemMessageCell })

        let visibleNewReceivedMessages = visibleReceivedCells.compactMap({ $0.message }).filter({ $0.status == .new })
        let visibleNewSystemMessages = visibleSystemCells.compactMap({ $0.message }).filter({ $0.status == .new })

        let messageIdsOfNewVisibleReceivedMessages = visibleNewReceivedMessages.map({ $0.identifier })
        let messageIdsOfNewVisibleSystemMessages = visibleNewSystemMessages.map({ $0.identifier })

        let messageIdsOfNewVisibleMessages = messageIdsOfNewVisibleReceivedMessages + messageIdsOfNewVisibleSystemMessages

        if !messageIdsOfNewVisibleMessages.isEmpty {
            // ObvDisplayableLogs.shared.log("[NewSingleDiscussionViewController] Posting messagesAreNotNewAnymore notification in markNewVisibleReceivedAndRelevantSystemMessagesAsNotNew for \(objectIDsOfNewVisibleMessages.count) messages")
            guard let discussionId = try? discussion.identifier else { assertionFailure(); return }
            Self.logger.debug("🌟[2] Will mark \(messageIdsOfNewVisibleMessages.count) message as read")
            guard let delegate else { assertionFailure(); return }
            Task { [weak self] in
                guard let self else { return }
                try? await delegate.messagesAreNotNewAnymore(self, ownedCryptoId: currentOwnedCryptoId, discussionId: discussionId, messageIds: messageIdsOfNewVisibleMessages)
            }
        }

    }
    
}



// MARK: - UIScrollViewDelegate / Managing automatic scroll to bottom

extension NewSingleDiscussionViewController {
    
    func scrollViewDidEndAutomaticScroll() {
        currentScrolling = .none
        evaluateScrollDependencies()
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if currentScrolling == .none {
            currentScrolling = .automatically
        }
        evaluateScrollDependencies()
    }

    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        self.currentScrolling = .none
        evaluateScrollDependencies()
    }
    
    
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        self.currentScrolling = .none
        evaluateScrollDependencies()
    }
    
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        currentScrolling = .manually
        evaluateScrollDependencies()
    }
    
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard currentScrolling == .manually && decelerate == false else { return }
        self.currentScrolling = .none
        evaluateScrollDependencies()
    }

    
    private func evaluateScrollDependencies() {
        debugPrint("🐸 \(currentScrolling.debugDescription)")

        switch currentScrolling {
        case .none:
            evaluateIfScrollOnNewIncomingMessageShouldBeActive()
            processReceivedMessagesThatBecameNotNewDuringScrolling()

        case .automatically:
            break

        case .manually:
            self.lastScrollWasManual = true
        }
    }
    
    
    /// This method evaluate if we should automatically scroll the next time a message is received.
    /// To do so, we check whether the content offset (scrolling position) is close enough to the bottom. In that case,
    /// we set `shouldScrollOnNewReceivedMessage` to `true` but only if we are not currently scrolling manually.
    private func evaluateIfScrollOnNewIncomingMessageShouldBeActive() {
        let distanceFromBottom = max(0, collectionView.contentSize.height + collectionView.adjustedContentInset.bottom - (collectionView.contentOffset.y + collectionView.frame.size.height))
        if distanceFromBottom < 60.0 {
            self.lastScrollWasManual = (currentScrolling == .manually)
        }
    }

    
    private func processReceivedMessagesThatBecameNotNewDuringScrolling() {
        // No need to check whether the window is foreground active
        guard !messagesToMarkAsNotNewWhenScrollingEnds.isEmpty else { return }
        guard currentScrolling == .none else { return }
        // ObvDisplayableLogs.shared.log("[NewSingleDiscussionViewController] Posting messagesAreNotNewAnymore notification in processReceivedMessagesThatBecameNotNewDuringScrolling for \(messagesToMarkAsNotNewWhenScrollingEnds.count) messages")
        guard let discussionId = try? discussion.identifier else { assertionFailure(); return }
        let messagesToMarkAsNotNewWhenScrollingEndsCount = messagesToMarkAsNotNewWhenScrollingEnds.count
        Self.logger.debug("🌟[3] Will mark \(messagesToMarkAsNotNewWhenScrollingEndsCount) message as read")
        guard let delegate else { assertionFailure(); return }
        Task { [weak self] in
            guard let self else { return }
            try? await delegate.messagesAreNotNewAnymore(self, ownedCryptoId: currentOwnedCryptoId, discussionId: discussionId, messageIds: messagesToMarkAsNotNewWhenScrollingEnds)
            messagesToMarkAsNotNewWhenScrollingEnds.removeAll()
        }
    }
    
}




// MARK: - UICollectionViewDelegate

extension NewSingleDiscussionViewController {
    
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {

        guard let discussionCollectionView = collectionView as? DiscussionCollectionView else { assertionFailure(); return }
        
        markAsNotNewTheMessageInCell(cell)
        visibilityTrackerForSensitiveMessages.refreshObjectIDsOfVisibleMessagesWithLimitedVisibility(in: collectionView)
        
        if let messageReceived = frc.safeObject(at: indexPath) as? PersistedMessageReceived {
            cacheDelegate.requestMissingPreviewIfNeededForMessage(with: messageReceived.typedObjectID)
        }
        
        // When the local user just sent a message (in which case, objectIDSentMessageJustSent is non nil), we scroll to it. To do so, we check if:
        // - the cell that will be displayed corresponds to this "just sent" message
        // - the collection view is not being scrolled manually
        // - the cell is the last one in the collection view
        // If all these conditions are met, we perform a scroll to the cell that will be displayed. We do so asynchronously, to ensure the cell is part
        // of the collection view by the time we perform the scroll. Note that automatic scrolling is also performed in `controller(_:didChangeContentWith:)`,
        // but the call made there sometimes happens before the collection view has a chance to display the message. However, this other call is necessary for
        // the rare case where the user first scrolls to the middle of the discussion and then sends a message. In that case, this method may not be
        // called since the collection view won't display the cell.

        defer { self.objectIDSentMessageJustSent = nil }
        if let sentMessage = frc.safeObject(at: indexPath) as? PersistedMessageSent, self.objectIDSentMessageJustSent == sentMessage.typedObjectID {
            let isLastCell = discussionCollectionView.lastIndexPath == indexPath
            let isNotScrollingManually = currentScrolling != .manually
            if isLastCell && isNotScrollingManually {
                DispatchQueue.main.async { [weak self] in
                    self?.simpleScrollToBottom()
                }
            }
        }
        
    }


    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        markAsNotNewTheMessageInCell(cell)
        visibilityTrackerForSensitiveMessages.refreshObjectIDsOfVisibleMessagesWithLimitedVisibility(in: collectionView)
    }
    
}


// MARK: - ReactionContextViewActionProtocol

extension NewSingleDiscussionViewController: ReactionContextViewActionProtocol {
    
    /// This delegate method is called when the user selects an emoji, in which case we clear the reaction context view and we update the message with the emoji selected.
    @MainActor
    func userDidSelectEmoji(to messageId: TypeSafeManagedObjectID<PersistedMessage>, emoji: String) async {

        guard let message = try? PersistedMessage.get(with: messageId, within: ObvStack.shared.viewContext),
              let ownedCryptoId = message.discussion?.ownedIdentity?.cryptoId else {
            return
        }
        
        self.hideContextReactionViewIfNeeded(animated: true)
        self.collectionView.contextMenuInteraction?.dismissMenu()
        
        try? await Task.sleep(seconds: 0.6) // Prevents an animation glitch if the reaction appears too soon
        
        guard let delegate else { assertionFailure(); return }
        
        Task { [weak self] in
            guard let self else { return }
            try? await delegate.userWantsToUpdateReaction(self, ownedCryptoId: ownedCryptoId, messageObjectID: messageId, newEmoji: emoji)
        }
        
    }
    
    /// If the user wants to open emoji picker (e.g., by tapping the 'plus' button in the reaction context view), we clear the reaction context view and we call the method to display the emoji picker view.
    @MainActor
    func userWantsToOpenEmojiPicker(for messageId: TypeSafeManagedObjectID<PersistedMessage>) async {
        self.hideContextReactionViewIfNeeded(animated: true)
        self.collectionView.contextMenuInteraction?.dismissMenu()
        self.userWantsToReactToMessage(messageID: messageId)
    }
    
}

// MARK: - LocationViewDelegate
extension NewSingleDiscussionViewController: LocationViewDelegate {
    
    func locationViewUserWantsToOpenMapAt(latitude: Double, longitude: Double, locationView: LocationView) {
        Task { await UIApplication.shared.userWantsToOpenMapAt(latitude: latitude, longitude: longitude, address: nil, within: self) }
    }
    
    
    func locationViewUserWantsToStopSharingLocation(_ locationView: LocationView) {
        if #available(iOS 17.0, *) {
            guard let delegate else { assertionFailure(); return }
            guard let discussionIdentifier = self.discussion.discussionIdentifier else { assertionFailure(); return }
            Task {
                do {
                    try await delegate.userWantsToStopSharingLocationInDiscussion(self, discussionIdentifier: discussionIdentifier)
                } catch {
                    assertionFailure()
                }
            }
        }
    }
}

// MARK: - UIContextMenuConfiguration

extension NewSingleDiscussionViewController: ContextMenuManagerDelegate, CellMessageShortcutMenuDelegate  {
    

    /// For catalyst, we have to give the UIMenu object to the message cell in order to set to the shortcut button on hover.
    @MainActor
    func getMenuForCellWithMessage(cell: any CellWithMessage) -> UIMenu? {
        return createMenu(for: cell)
    }
    
    
    /// For catalyst, this method is used to display reaction context menu when the user clicks on the reaction shortcut button on hover.
    @MainActor
    func showContextReactionView(for cell: any CellWithMessage, on view: UIView) {
        
        guard self.contextReactionRootView == nil else {
            return
        }

        guard let persistedMessageObjectID = cell.persistedMessageObjectID else { assertionFailure(); return }
        guard let persistedMessage = try? PersistedMessage.get(with: persistedMessageObjectID, within: ObvStack.shared.viewContext) else { return }
        guard (try? persistedMessage.ownedIdentityIsAllowedToSetReaction) == true else { return }

        var location = view.convert(view.center, to: self.view)
        
        // moving the reaction view a little bit upward to add margin from the mouse pointer and the view
        location.y -= 10.0
        self.addContextReactionViewIfNeeded(messageId: persistedMessageObjectID, atLocation: location)
        
    }
    
    
    private func setupLongGestureRecognizerForCatalyst() {
        let longPressedGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(gestureRecognizer:)))
        longPressedGesture.minimumPressDuration = 0.2
        longPressedGesture.delegate = self
        longPressedGesture.delaysTouchesBegan = false
        collectionView?.addGestureRecognizer(longPressedGesture)
    }
    
    
    /// When the long press is triggered, we check which cell corresponds to the press location, check that the user can react to the message, and we display the reaction context menu if needed.
    @objc func handleLongPress(gestureRecognizer: UILongPressGestureRecognizer) {

        guard self.contextReactionRootView == nil else {
            return
        }
        
        guard gestureRecognizer.state == .began else {
            return
        }

        let location = gestureRecognizer.location(in: collectionView)

        guard let indexPath = collectionView?.indexPathForItem(at: location) else { return }

        guard let cell = collectionView.cellForItem(at: indexPath) as? CellWithMessage,
              let messageId = cell.persistedMessageObjectID else { return }
        
        guard let persistedMessage = try? PersistedMessage.get(with: messageId, within: ObvStack.shared.viewContext) else { return }
        guard (try? persistedMessage.ownedIdentityIsAllowedToSetReaction) == true else { return }
        
        addContextReactionViewIfNeeded(messageId: messageId, atLocation: gestureRecognizer.location(in: self.view))
        
    }
    

    // This method adds the reaction context view for the corresponding message, above the mouse pointer location.
    private func addContextReactionViewIfNeeded(messageId: TypeSafeManagedObjectID<PersistedMessage>, atLocation location: CGPoint, viewToHighlight: UIView? = nil) {
        
        guard let reactionView = getReactionContextView(for: messageId) else { return }

        // We force the frame to be set to its intrinsic content size in order to position it at the correct place afterwise.
        reactionView.frame = CGRect(origin: .zero, size: reactionView.intrinsicContentSize)
        
        // This view will dim the whole discussion content and enable the view to hide itself on tap.
        let reactionContainerView = HidableView()
        
        if let viewToHighlight = viewToHighlight {
            reactionContainerView.addBlurEffect(alpha: 0.0)
            UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 0.2, delay: 0.0) {
                reactionContainerView.setBlurEffectAlpha(to: 1.0)
            }
            createOverlay(on: reactionContainerView, viewToSnapshot: viewToHighlight, reactionViewHeight: reactionView.intrinsicContentSize.height)
        } else {
            reactionContainerView.backgroundColor = .clear
        }

        reactionContainerView.translatesAutoresizingMaskIntoConstraints = false
        
        reactionView.translatesAutoresizingMaskIntoConstraints = false
        
        (self.view.window ?? self.view).addSubview(reactionContainerView)
        reactionContainerView.addSubview(reactionView)
        
        let constraints: [NSLayoutConstraint] = {
            var constraints: [NSLayoutConstraint] = []
            
            let auxiliarySize: CGSize = reactionView.frame.size
            let parentWidth: CGFloat = view.bounds.width
            let parentHeight: CGFloat = view.bounds.height
            let centerY: CGFloat = location.y
            let minAuxiliaryY: CGFloat = centerY - 10.0 - auxiliarySize.height
            let maxAuxiliaryY: CGFloat = centerY - 10.0
            
            var positionY: CGFloat = minAuxiliaryY
            
            let reactionMargin: CGFloat = (navigationController?.navigationBar.frame.maxY ?? 0) + 8.0
            
            if maxAuxiliaryY > parentHeight {
                positionY = parentHeight - auxiliarySize.height - 10.0
            } else if minAuxiliaryY < reactionMargin { // Keep a top padding
                positionY = reactionMargin
            }
            
            constraints +=  [
                reactionView.topAnchor.constraint(equalTo: view.topAnchor, constant: positionY),
            ]
            
            // If a message is highlighted, we pin the reaction context menu to the trailing or leading of the cell, depending of the type of message received.
            if let viewToHighlight, let persistedMessage = try? PersistedMessage.get(with: messageId, within: ObvStack.shared.viewContext), persistedMessage.kind == .received || persistedMessage.kind == .sent {
                if persistedMessage.kind == .received {
                    constraints +=  [
                        reactionView.leadingAnchor.constraint(equalTo: viewToHighlight.leadingAnchor),
                    ]
                } else if persistedMessage.kind == .sent {
                    constraints +=  [
                        reactionView.trailingAnchor.constraint(equalTo: viewToHighlight.trailingAnchor),
                    ]
                }
            } else { // If no view should be highlighted (in case of a long press or with the shortcut on Mac catalyst), we simply center the reaction view to the location asked
                let centerX: CGFloat = location.x
                let minAuxiliaryX: CGFloat = centerX - (auxiliarySize.width / 2.0)
                let maxAuxiliaryX: CGFloat = centerX + (auxiliarySize.width / 2.0)
                var positionX: CGFloat = minAuxiliaryX
                let reactionPadding: CGFloat = 10.0
                
                if maxAuxiliaryX > parentWidth {
                    positionX = parentWidth - auxiliarySize.width - reactionPadding
                } else if minAuxiliaryX < 0.0 {
                    positionX = reactionPadding
                }

                constraints +=  [
                    reactionView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: positionX),
                ]
            }
            constraints +=  [
                reactionContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                reactionContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                reactionContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                reactionContainerView.topAnchor.constraint(equalTo: view.topAnchor)
            ]
            
            return constraints
        }()
        
        NSLayoutConstraint.activate(constraints)
                
        self.contextReactionRootView = reactionContainerView
        
        self.contextReactionRootView?.executeOnAnimation = { [weak self] in
            if let contextViewToSnapshot = self?.contextViewToSnapshot {
                contextViewToSnapshot.alpha = 1.0
            }
        }
        
        self.contextReactionRootView?.onCompletion = { [weak self] in
            self?.contextViewToSnapshot = nil
            self?.contextReactionRootView = nil
        }
    }
    
    
    /// Exclusively called from ``addContextReactionViewIfNeeded(messageId:gestureLocation:viewToHighlight:)``
    private func createOverlay(on parentView: UIView, viewToSnapshot: UIView, reactionViewHeight: CGFloat) {
        
        self.contextViewToSnapshot = viewToSnapshot

        let overlayMinPosY = (navigationController?.navigationBar.frame.maxY ?? 0) + reactionViewHeight + 14.0
        
        let originFrame = viewToSnapshot.convert(viewToSnapshot.bounds, to: self.view)
        var targetFrame = originFrame
        
        var shouldAnimateOverlay = false
        
        if targetFrame.minY < overlayMinPosY {
            targetFrame.origin.y = overlayMinPosY
            shouldAnimateOverlay = true
        }
        
        if let snapshotView = viewToSnapshot.snapshotView(afterScreenUpdates: false) {
            snapshotView.isUserInteractionEnabled = false
            parentView.addSubview(snapshotView)
            snapshotView.frame = originFrame
            contextViewToSnapshot?.alpha = 0.0

            if shouldAnimateOverlay {
                UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 2, options: .curveEaseInOut) {
                    snapshotView.frame = targetFrame
                }
            }
        }
    }

    
    
    private func hideContextReactionViewIfNeeded(animated: Bool) {
        if let contextReactionView = self.contextReactionRootView {
            self.contextReactionRootView?.animateOnHide = animated
            contextReactionView.hide()
        }
    }
    
    
    // below iOS 16
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {

        guard let cell = collectionView.cellForItem(at: indexPath) as? CellWithMessage, let contextMenuMessageId = cell.persistedMessageObjectID else { return nil }
        
        let actionProvider = makeActionProvider(for: cell)
        
        let menuConfiguration = UIContextMenuConfiguration(indexPath: indexPath,
                                                           previewProvider: nil,
                                                           actionProvider: actionProvider)
        
        self.contextMenuManager = ContextMenuManager(contextMenuInteraction: collectionView.contextMenuInteraction,
                                                     menuTargetView: cell.viewForTargetedPreview,
                                                     messageId: contextMenuMessageId)
        
        self.contextMenuManager?.delegate = self
        
        return menuConfiguration
    }

    
    func collectionView(_ collectionView: UICollectionView, previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        return makeTargetedPreview(for: configuration)
    }
    
    
    func collectionView(_ collectionView: UICollectionView, previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        return makeTargetedPreview(for: configuration)
    }
    
    
    // iOS 16+
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first, let cell = collectionView.cellForItem(at: indexPath) as? CellWithMessage, let contextMenuMessageId = cell.persistedMessageObjectID else { return nil }
        
        let actionProvider = makeActionProvider(for: cell)
        
        let menuConfiguration = UIContextMenuConfiguration(indexPath: indexPath,
                                                           previewProvider: nil,
                                                           actionProvider: actionProvider)
        
        self.contextMenuManager = ContextMenuManager(contextMenuInteraction: collectionView.contextMenuInteraction,
                                                     menuTargetView: cell.viewForTargetedPreview, 
                                                     messageId: contextMenuMessageId)
        
        self.contextMenuManager?.delegate = self
        
        return menuConfiguration
    }
    
    
    func contextMenuRequestsAuxiliaryPreview(_ contextMenu: ContextMenuManager, forMessageWithIdentifier messageId: TypeSafeManagedObjectID<PersistedMessage>) -> UIView? {
        
        let view = getReactionContextView(for: messageId)
        
        // We force the frame to be set to its intrinsic content size in order to location it at the correct place afterwards.
        view?.frame = CGRect(origin: .zero, size: view?.intrinsicContentSize ?? .zero)
        return view
        
    }
    
    
    private func getReactionContextView(for messageId:TypeSafeManagedObjectID<PersistedMessage>) -> UIView? {
        let reactionViewController = ReactionContextHostingViewController(messageId: messageId, delegate: self)
        
        let view = reactionViewController.view
        return view
    }
    
    
    func collectionView(_ collectionView: UICollectionView, contextMenuConfiguration configuration: UIContextMenuConfiguration, highlightPreviewForItemAt indexPath: IndexPath) -> UITargetedPreview? {
        return makeTargetedPreview(for: configuration)
    }

    
    func collectionView(_ collectionView: UICollectionView, contextMenuConfiguration configuration: UIContextMenuConfiguration, dismissalPreviewForItemAt indexPath: IndexPath) -> UITargetedPreview? {
        return makeTargetedPreview(for: configuration)
    }
    
    
    private func makeTargetedPreview(for configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        guard let indexPath = configuration.indexPath else { return nil }
        
        guard let cell = collectionView.cellForItem(at: indexPath) as? CellWithMessage else { return nil }
        
        let viewForTargetedPreview = cell.viewForTargetedPreview
        
        let parameters = UIPreviewParameters()
        parameters.visiblePath = UIBezierPath(roundedRect: viewForTargetedPreview.bounds, cornerRadius: MessageCellConstants.BubbleView.largeCornerRadius - 1.0)
        parameters.backgroundColor = .clear
        
        return UITargetedPreview(view: viewForTargetedPreview, parameters: parameters)
    }
    
    
    func collectionView(_ collectionView: UICollectionView, willDisplayContextMenu configuration: UIContextMenuConfiguration, animator: (any UIContextMenuInteractionAnimating)?) {
        guard let contextMenuInteraction = collectionView.contextMenuInteraction else { return }
        // In case the owned identity is allowed to add a reaction on the message corresponding to the cell, we show a "reactions" context menu in addition to the standard menu
        guard let indexPath = configuration.indexPath,
              let cell = collectionView.cellForItem(at: indexPath) as? CellWithMessage,
              let persistedMessageObjectID = cell.persistedMessageObjectID,
              let persistedMessage = try? PersistedMessage.get(with: persistedMessageObjectID, within: ObvStack.shared.viewContext),
              (try? persistedMessage.ownedIdentityIsAllowedToSetReaction) == true 
        else {
            return
        }
        contextMenuManager?.notifyOnContextMenuInteraction(contextMenuInteraction, willDisplayMenuFor: configuration, animator: animator)
    }

    
    func collectionView(_ collectionView: UICollectionView, willEndContextMenuInteraction configuration: UIContextMenuConfiguration, animator: (any UIContextMenuInteractionAnimating)?) {
        guard let contextMenuInteraction = collectionView.contextMenuInteraction else { return }
        contextMenuManager?.notifyOnContextMenuInteraction(contextMenuInteraction, willEndFor: configuration, animator: animator)
    }
        

    @MainActor
    private func createMenu(for cell: CellWithMessage) -> UIMenu? {
        guard let persistedMessageObjectID = cell.persistedMessageObjectID else { assertionFailure(); return nil }
        guard let persistedMessage = try? PersistedMessage.get(with: persistedMessageObjectID, within: ObvStack.shared.viewContext) else { assertionFailure(); return nil }
        
        var children = [UIMenuElement]()
        
        // Message infos action
        if persistedMessage.infoActionCanBeMadeAvailable {
            let action = UIAction(title: "Info") { [weak self] (_) in
                if let vc = cell.infoViewController {
                    let nav = UINavigationController(rootViewController: vc)
                    let appearance = UINavigationBarAppearance()
                    appearance.configureWithOpaqueBackground()
                    nav.navigationBar.standardAppearance = appearance
                    nav.navigationBar.scrollEdgeAppearance = appearance
                    self?.navigationController?.present(nav, animated: true)
                }
            }
            action.image = UIImage(systemIcon: .infoCircle)
            children.append(action)
        }
        
        // Add a reaction action
        if (try? persistedMessage.ownedIdentityIsAllowedToSetReaction) == true {
            let title = persistedMessage.deleteOwnReactionActionCanBeMadeAvailable ? CommonString.Title.changeAReactionText : CommonString.Title.addAReactionText
            let action = UIAction(title: title) { [weak self] (_) in
                guard let self else { return }
                self.userWantsToReactToMessage(messageID: persistedMessageObjectID)
            }
            action.image = UIImage(systemIcon: persistedMessage.deleteOwnReactionActionCanBeMadeAvailable ? .arrowClockwiseHeart : .heart)
            children.append(action)
        }
        
        // Delete reaction action
        if persistedMessage.deleteOwnReactionActionCanBeMadeAvailable {
            let action = UIAction(title: CommonString.Title.deleteOwnReaction) { [weak self] (_) in
                guard let self else { return }
                guard let ownedCryptoId = persistedMessage.discussion?.ownedIdentity?.cryptoId else { assertionFailure(); return }
                guard let delegate else { assertionFailure(); return }
                let messageId = persistedMessage.typedObjectID
                Task { [weak self] in
                    guard let self else { return }
                    try? await delegate.userWantsToUpdateReaction(self, ownedCryptoId: ownedCryptoId, messageObjectID: messageId, newEmoji: nil)
                }
            }
            action.image = UIImage(systemIcon: .heartSlash)
            children.append(action)
        }

        // Copy Text action
        if let textToCopy = cell.textToCopy, persistedMessage.copyActionCanBeMadeAvailable {
            let action = UIAction(title: CommonString.Title.copyText) { (_) in
                UIPasteboard.general.string = textToCopy
            }
            action.image = UIImage(systemIcon: .docOnDoc)
            children.append(action)
        }

        // Share action
        if persistedMessage.shareActionCanBeMadeAvailable {

            // Share all photos at once
            if let itemProvidersForImages = cell.itemProvidersForImages, itemProvidersForImages.count > 0 {
                let action = UIAction(title: Strings.sharePhotos(itemProvidersForImages.count)) { [weak self] (_) in
                    let uiActivityVC = UIActivityViewController(activityItems: itemProvidersForImages, applicationActivities: nil)
                    uiActivityVC.popoverPresentationController?.sourceView = cell
                    uiActivityVC.completionWithItemsHandler = { [weak self] (activityType, completed, returnedItems, activityError) in
                        guard completed, activityError == nil else {
                            return
                        }
                        self?.postUserHasOpenedAReceivedAttachmentNotification(for: persistedMessage)
                    }
                    self?.present(uiActivityVC, animated: true)
                }
                action.image = UIImage(systemIcon: .squareAndArrowUp)
                children.append(action)
            }

            // Share all attachments (photos and other) at once
            if let itemProvidersForAllAttachments = cell.activityItemProvidersForAllAttachments, !itemProvidersForAllAttachments.isEmpty, cell.itemProvidersForImages?.count != itemProvidersForAllAttachments.count {
                let action = UIAction(title: Strings.shareAttachments(itemProvidersForAllAttachments.count)) { [weak self] (_) in
                    let uiActivityVC = UIActivityViewController(activityItems: itemProvidersForAllAttachments, applicationActivities: nil)
                    uiActivityVC.popoverPresentationController?.sourceView = cell
                    uiActivityVC.completionWithItemsHandler = { [weak self] (activityType, completed, returnedItems, activityError) in
                        guard completed, activityError == nil else {
                            return
                        }
                        self?.postUserHasOpenedAReceivedAttachmentNotification(for: persistedMessage)
                    }
                    self?.present(uiActivityVC, animated: true)
                }
                action.image = UIImage(systemIcon: .squareAndArrowUp)
                children.append(action)
            }
        }
        
        // Save to Files (iOS/iPadOS) or present a standard save panel (macOS)
        
        if persistedMessage.shareActionCanBeMadeAvailable {
            
            if let hardlinkURLsForAllAttachments = cell.hardlinkURLsForAllAttachments, !hardlinkURLsForAllAttachments.isEmpty {
                let action = UIAction(title: Strings.saveAttachments(hardlinkURLsForAllAttachments.count)) { [weak self] (_) in
                    let picker = UIDocumentPickerViewController(forExporting: hardlinkURLsForAllAttachments, asCopy: true)
                    picker.shouldShowFileExtensions = true
                    self?.present(picker, animated: true)
                }
                action.image = UIImage(systemIcon: .squareAndArrowDownOnSquare)
                children.append(action)
            }
            
        }
        
        // Reply to message action
        if let draftObjectID = cell.persistedDraftObjectID, persistedMessage.replyToActionCanBeMadeAvailable {
            let action = UIAction(title: CommonString.Word.Reply) { [weak self] _ in
                guard let self else { return }
                Task { [weak self] in
                    guard let self else { return }
                    try? await delegate?.userWantsToReplyToMessage(self, messageObjectID: persistedMessageObjectID, draftObjectID: draftObjectID)
                }
            }
            action.image = UIImage(systemIcon: .arrowshapeTurnUpLeft2)
            children.append(action)
        }

        // Edit message action
        if persistedMessage.editBodyActionCanBeMadeAvailable, let sentMessage = persistedMessage as? PersistedMessageSent {
            let action = UIAction(title: CommonString.Word.Edit) { [weak self] (_) in
                guard let ownedCryptoId = self?.currentOwnedCryptoId else { assertionFailure(); return }
                let currentTextBody = persistedMessage.textBody
                let vc = BodyEditViewController(currentBody: currentTextBody) { [weak self] in
                    self?.presentedViewController?.dismiss(animated: true)
                } send: { [weak self] (newTextBody) in
                    guard let _self = self else { return }
                    self?.presentedViewController?.dismiss(animated: true, completion: {
                        guard newTextBody != currentTextBody else { return }
                        ObvMessengerInternalNotification.userWantsToSendEditedVersionOfSentMessage(
                            ownedCryptoId: ownedCryptoId,
                            sentMessageObjectID: sentMessage.typedObjectID,
                            newTextBody: newTextBody ?? "")
                            .postOnDispatchQueue(_self.internalQueue)
                    })
                }
                self?.present(vc, animated: true)
                return
            }
            action.image = UIImage(systemIcon: .pencil(.circle))
            children.append(action)
        }

        // Forward message action
        if persistedMessage.forwardActionCanBeMadeAvailable {
            let action = UIAction(title: CommonString.Word.Forward) { [weak self] (_) in
                guard let ownedCryptoId = persistedMessage.discussion?.ownedIdentity?.cryptoId else { return }
                let vc: UIViewController
                if #available(iOS 16, *) {
                    let viewModel = NewDiscussionsSelectionViewController.ViewModel(
                        viewContext: ObvStack.shared.viewContext,
                        preselectedDiscussions: [],
                        ownedCryptoId: ownedCryptoId,
                        restrictToActiveDiscussions: true,
                        attachSearchControllerToParent: false,
                        buttonTitle: CommonString.Word.Forward,
                        buttonSystemIcon: .arrowshapeTurnUpForwardFill)
                    vc = NewDiscussionsSelectionViewController(viewModel: viewModel, delegate: self)
                } else {
                    vc = DiscussionsSelectionViewController(ownedCryptoId: ownedCryptoId,
                                                            within: ObvStack.shared.viewContext,
                                                            preselectedDiscussions: Set(),
                                                            delegate: self,
                                                            acceptButtonTitle: CommonString.Word.Forward)
                }
                self?.messageToForward = persistedMessage
                let cancelAction = UIAction { [weak self] _ in
                    self?.messageToForward = nil
                    self?.presentedViewController?.dismiss(animated: true)
                }
                vc.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: cancelAction)
                let nav = ObvNavigationController(rootViewController: vc)
                self?.present(nav, animated: true)
                return
            }
            action.image = UIImage(systemIcon: ObvMessengerConstants.forwardIcon)
            children.append(action)
        }

        // Call action
        if persistedMessage.callActionCanBeMadeAvailable {
            let action = UIAction(title: CommonString.Word.Call) { (_) in
                guard let systemMessage = persistedMessage as? PersistedMessageSystem else { return }
                guard let item = systemMessage.optionalCallLogItem else { return }
                let groupId = item.groupIdentifier

                let contactCryptoIds = item.logContacts.compactMap { $0.contactIdentity?.cryptoId }
                let ownedCryptoIds = item.logContacts.compactMap { $0.contactIdentity?.ownedIdentity?.cryptoId }
                guard ownedCryptoIds.count == 1 else { assertionFailure(); return }
                guard let ownedCryptoId = ownedCryptoIds.first else { return }
                
                if contactCryptoIds.count == 1 {
                    ObvMessengerInternalNotification.userWantsToCallOrUpdateCallCapabilityButWeShouldCheckSheIsAllowedTo(ownedCryptoId: ownedCryptoId, contactCryptoIds: Set(contactCryptoIds), groupId: groupId, startCallIntent: nil)
                        .postOnDispatchQueue()
                } else {
                    ObvMessengerInternalNotification.userWantsToSelectAndCallContacts(ownedCryptoId: ownedCryptoId, contactCryptoIds: Set(contactCryptoIds), groupId: groupId)
                        .postOnDispatchQueue()
                }
            }
            action.image = UIImage(systemIcon: .phoneFill)
            children.append(action)
        }

        // Delete message action
        if !persistedMessage.deletionTypesThatCanBeMadeAvailableForThisMessage.isEmpty {
            let action = UIAction(title: CommonString.Word.Delete) { [weak self] (_) in
                // Do not show any confirmation if the user deletes a wiped message.
                let confirmedDeletionType: DeletionType? = persistedMessage.isWiped ? .fromThisDeviceOnly : nil
                self?.deletePersistedMessage(objectId: persistedMessageObjectID.objectID, confirmedDeletionType: confirmedDeletionType, withinCell: cell)
            }
            action.image = UIImage(systemIcon: .trash)
            action.attributes = [.destructive]
            children.append(action)
        }

        
        return UIMenu(title: "", image: nil, identifier: nil, options: .displayInline, children: children)
    }
    
    
    private func makeActionProvider(for cell: CellWithMessage) -> (([UIMenuElement]) -> UIMenu?) {
        return { (suggestedActions) in
            return self.createMenu(for: cell)
        }
    }
    
    
    /// Helper method called after the user decided to forward a message from this discussion to another. In case the message was forwarded to exactly one discussion, we navigate to that discussion.
    private func navigateIfAppropriateToDiscussionWhereMessageWasForwarded(discussionPermanentIDs: Set<ObvManagedObjectPermanentID<PersistedDiscussion>>, persistedMessage: PersistedMessage) {
        guard let persistedMessageDiscussion = persistedMessage.discussion else { assertionFailure(); return }
        if discussionPermanentIDs.count == 1,
           let discussionPermanentID = discussionPermanentIDs.first,
           discussionPermanentID != persistedMessageDiscussion.discussionPermanentID,
           let ownedCryptoId = persistedMessageDiscussion.ownedIdentity?.cryptoId {
            // We assume the discussion belongs the current owned identity
            let deepLink = ObvDeepLink.singleDiscussion(ownedCryptoId: ownedCryptoId, objectPermanentID: discussionPermanentID)
            ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                .postOnDispatchQueue()
        }
    }
    
    

    private func postUserHasOpenedAReceivedAttachmentNotification(for message: PersistedMessage) {
        guard let receivedMessage = message as? PersistedMessageReceived else { return }
        let joins = receivedMessage.fyleMessageJoinWithStatuses
        for join in joins {
            ObvMessengerInternalNotification.userHasOpenedAReceivedAttachment(receivedFyleJoinID: join.typedObjectID).postOnDispatchQueue()
        }
    }
    
    private func deletePersistedMessage(objectId: NSManagedObjectID, confirmedDeletionType: DeletionType?, withinCell cell: CellWithMessage) {
        
        assert(Thread.isMainThread)
        
        switch confirmedDeletionType {
        
        case .none:
            
            guard let persistedMessage = try? PersistedMessage.get(with: objectId, within: ObvStack.shared.viewContext) else { return }
            guard let discussion = persistedMessage.discussion else { return }
            guard discussion.typedObjectID == self.discussionObjectID else { return }
            let ownedIdentityHasHasAnotherReachableDevice = discussion.ownedIdentity?.hasAnotherDeviceWhichIsReachable ?? false
            
            let multipleContacts: Bool
            do {
                switch try discussion.kind {
                case .oneToOne:
                    multipleContacts = false
                case .groupV1(withContactGroup: let group):
                    if let group {
                        multipleContacts = group.contactIdentities.count > 1
                    } else {
                        assertionFailure()
                        multipleContacts = false
                    }
                case .groupV2(withGroup: let group):
                    if let group {
                        multipleContacts = group.otherMembers.count > 1
                    } else {
                        assertionFailure()
                        multipleContacts = false
                    }
                }
            } catch {
                assertionFailure()
                multipleContacts = true
            }
            
            let numberOfAttachedFyles: Int
            if let persistedMessageSent = persistedMessage as? PersistedMessageSent {
                numberOfAttachedFyles = persistedMessageSent.fyleMessageJoinWithStatuses.filter({ !$0.isWiped }).count
            } else if let persistedMessageReceived = persistedMessage as? PersistedMessageReceived {
                numberOfAttachedFyles = persistedMessageReceived.fyleMessageJoinWithStatuses.filter({ !$0.isWiped }).count
            } else {
                numberOfAttachedFyles = 0
            }
            
            let userAlertTitle: String
            if numberOfAttachedFyles > 0 {
                userAlertTitle = Strings.deleteMessageAndAttachmentsTitle
            } else {
                userAlertTitle = Strings.deleteMessageTitle
            }
            let userAlertMessage = Strings.deleteMessageAndAttachmentsMessage(numberOfAttachedFyles)
            
            let alert = UIAlertController(title: userAlertTitle, message: userAlertMessage, preferredStyle: .actionSheet)
            
            for deletionType in persistedMessage.deletionTypesThatCanBeMadeAvailableForThisMessage.sorted() {
                let title = CommonString.AlertButton.deletionActionTitle(for: deletionType, ownedIdentityHasHasAnotherReachableDevice: ownedIdentityHasHasAnotherReachableDevice, multipleContacts: multipleContacts)
                alert.addAction(UIAlertAction(title: title, style: .destructive, handler: { [weak self] (action) in
                    self?.deletePersistedMessage(objectId: objectId, confirmedDeletionType: deletionType, withinCell: cell)
                }))
            }

            alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))

            alert.popoverPresentationController?.sourceView = cell.viewForTargetedPreview
            present(alert, animated: true, completion: nil)
            
        case .some(let deletionType):
            
            assert(Thread.isMainThread)
            
            guard let discussion = try? PersistedDiscussion.get(objectID: discussionObjectID, within: ObvStack.shared.viewContext) else {
                return
            }
            
            guard let ownedCryptoId = discussion.ownedIdentity?.cryptoId else {
                return
            }
            
            ObvMessengerInternalNotification.userRequestedDeletionOfPersistedMessage(ownedCryptoId: ownedCryptoId, persistedMessageObjectID: objectId, deletionType: deletionType)
                .postOnDispatchQueue(internalQueue)

        }
        
    }

}


// MARK: - Utils

extension NewSingleDiscussionViewController {
    
    private func simpleScrollToBottom() {
        
        if #available(iOS 18, *) {
            
            currentScrolling = .automatically
            UIViewPropertyAnimator.runningPropertyAnimator(withDuration: .init(0.2), delay: 0) { [weak self] in
                guard let lastIndexPath = self?.collectionView.lastIndexPath else {
                    self?.currentScrolling = .none
                    return
                }
                self?.collectionView.scrollToItem(at: lastIndexPath, at: .bottom, animated: false)
            } completion: { [weak self] _ in
                guard let lastIndexPath = self?.collectionView.lastIndexPath else {
                    self?.currentScrolling = .none
                    return
                }
                self?.collectionView.scrollToItem(at: lastIndexPath, at: .bottom, animated: false)
                self?.currentScrolling = .none
            }
            
        } else {
            
            guard let lastIndexPath = collectionView.lastIndexPath else { return }
            currentScrolling = .automatically
            collectionView.scrollToItem(at: lastIndexPath, at: .bottom, animated: true)
            currentScrolling = .none
            
        }

    }

    private func scrollToItemAtIndexPath(_ indexPath: IndexPath) {
        let animationValues = defaultAnimationValues
        guard let collectionView = self.collectionView else { return }

        UIViewPropertyAnimator.runningPropertyAnimator(withDuration: animationValues.duration, delay: 0.0, options: animationValues.options) {
            collectionView.adjustedScrollToItem(at: indexPath, at: .centeredVertically, completion: {})
        } completion: { _ in
            UIView.animate(withDuration: animationValues.duration, delay: 0.0, options: animationValues.options) {
                collectionView.adjustedScrollToItem(at: indexPath, at: .centeredVertically, completion: {})
            } completion: { _ in
                guard let cell = collectionView.cellForItem(at: indexPath) else { return }
                UIView.animateKeyframes(withDuration: 0.3, delay: 0.1, options: []) {
                    cell.transform = .init(scaleX: 1.1, y: 1.1)
                } completion: { _ in
                    UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0, options: []) {
                        cell.transform = .identity
                    }
                }
            }
        }
    }

    private func animateItem(at indexPath: IndexPath) {
        guard let cell = collectionView.cellForItem(at: indexPath) else { return }
        UIView.animateKeyframes(withDuration: 0.5, delay: 0.2, options: []) {
            cell.transform = .init(scaleX: 1.1, y: 1.1)
        } completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0, options: []) {
                cell.transform = .identity
            }
        }
    }

    
    func scrollTo(message: PersistedMessage) {
        assert(Thread.isMainThread)
        guard let frc = self.frc else { return }
        guard let message = try? PersistedMessage.get(with: message.typedObjectID, within: frc.managedObjectContext) else { return }
        guard let indexPath = frc.indexPath(forObject: message) else { return }
        scrollToItemAtIndexPath(indexPath)
    }
    
    
    enum ScrollingType: CustomDebugStringConvertible {

        case none
        case manually
        case automatically

        var debugDescription: String {
            switch self {
            case .none: return "none"
            case .manually: return "manually"
            case .automatically: return "automatically"
            }
        }
    }
    
    
    private func previousMessageIsFromSameContact(message: PersistedMessageReceived) -> Bool {
        guard let indexPath = frc.indexPath(forObject: message) else { return false }
        guard indexPath.item > 0 else { return false }
        let previousIndexPath = IndexPath(item: indexPath.item-1, section: indexPath.section)
        guard let previousMessage = frc.safeObject(at: previousIndexPath) as? PersistedMessageReceived else { return false }
        return message.contactIdentity == previousMessage.contactIdentity
    }
    
    
}


// MARK: - Adapting the collection view's insets

extension NewSingleDiscussionViewController {
    
    /// Called in ``func viewDidLoad()``, this method observe significant layout changes in order to update the collection view's insets.
    ///
    /// We combines the latest values of the following variables:
    /// - The published values of the compostion view ``mainContentViewFrame``.
    /// - The published values of the search view ``mainContentViewFrame``.
    /// - The published values of ``toggledWhenKeyboardDidHideOrShow``, which is toggled each time the keyboard hides or shows.
    /// - The published values of the ``currentScrolling`` variable, since we want to prevent the modification of the collection view's insets while scrolling, and postpone these modifications to the time the scrolling is finished. In practice, it is also ok to update the insets when ``isTracking`` is `false`.
    private func observeKeyboardAndCompositionViewChangesToAdaptCollectionViewsInsets() {
        Publishers.CombineLatest4(composeMessageView.$mainContentViewFrame, singleDiscussionSearchView.$mainContentViewFrame, $toggledWhenKeyboardDidHideOrShow, $currentScrolling)
            .sink { [weak self] (currentComposeViewMainContentViewFrame, searchViewFrame, toggledWhenKeyboardDidHideOrShow, currentScrolling) in
                guard let self else { return }
                let contentViewFrameHeight: CGFloat
                switch self.accessoryViewKindShown {
                case .none: contentViewFrameHeight = 0.0
                case .messageCompose: contentViewFrameHeight = currentComposeViewMainContentViewFrame.height
                case .searchBrowsing: contentViewFrameHeight = searchViewFrame.height
                }
                self.adaptCollectionViewInsetsToComposeMessageView(contentViewFrameHeight: contentViewFrameHeight)
            }
            .store(in: &cancellables)
    }


    /// In practice, the `contentViewFrameHeight` corresponds either to the frame of the `mainContentViewFrame` of the compose view or of the search view. It is 0 when no view
    /// should appear above the keyboard (which happens, e.g., when a discussion is locked).
    private func adaptCollectionViewInsetsToComposeMessageView(contentViewFrameHeight: CGFloat) {

        guard let collectionView else { return }
        //guard let composeMessageView, let collectionView else { return }
        //guard !composeMessageView.preventTextViewFromEditing else { return }
        guard currentScrolling != .manually || !collectionView.isTracking else { return }

        let bottom = contentViewFrameHeight + view.keyboardLayoutGuide.layoutFrame.height - view.safeAreaInsets.bottom + Self.spaceBellowLastCell
        guard collectionView.contentInset.bottom != bottom else { return }
        
        let currentHeightBelowContent = max(0, collectionView.bounds.height - collectionView.adjustedContentInset.bottom - collectionView.adjustedContentInset.top - collectionView.contentSize.height)
        let amountToScroll = max(0, bottom - collectionView.contentInset.bottom - currentHeightBelowContent)
        
        if bottom > collectionView.contentInset.bottom {
            // Virtual keyboard is going up, we don't explicitely animate
            setCollectionViewContentInsetBottom(to: bottom)
        } else {
            // Virtual keyboard is dismissing, we do animate
            UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 0.2, delay: 0) { [weak self] in
                self?.setCollectionViewContentInsetBottom(to: bottom)
            }
        }
        
        // Scroll if required
        
        collectionView.contentOffset = CGPoint(x: collectionView.contentOffset.x, y: collectionView.contentOffset.y + amountToScroll)
        
        scrollViewDidEndAutomaticScroll()

    }

    
    /// Method called from ``func adaptCollectionViewInsetsToComposeMessageView(mainContentViewFrame: CGRect)``.
    private func setCollectionViewContentInsetBottom(to bottom: CGFloat) {
        collectionView.contentInset = UIEdgeInsets(
            top: collectionView.contentInset.top,
            left: collectionView.contentInset.left,
            bottom: bottom,
            right: collectionView.contentInset.right)
        collectionView.scrollIndicatorInsets = UIEdgeInsets(
            top: collectionView.contentInset.top,
            left: collectionView.verticalScrollIndicatorInsets.left,
            bottom: bottom,
            right: collectionView.verticalScrollIndicatorInsets.left)
    }

}

// MARK: - Implementing AttachmentsCollectionViewControllerDelegate

extension NewSingleDiscussionViewController: AttachmentsCollectionViewControllerDelegate {
    
    func userWantsToDeleteAttachmentsFromDraft(_ attachmentsCollectionViewController: AttachmentsCollectionViewController, draftObjectID: ObvUICoreData.TypeSafeManagedObjectID<ObvUICoreData.PersistedDraft>, draftTypeToDelete: DeleteAllDraftFyleJoinOfDraftOperation.DraftType) async {
        guard let delegate else { assertionFailure(); return }
        await delegate.userWantsToDeleteAttachmentsFromDraft(self, draftObjectID: draftObjectID, draftTypeToDelete: draftTypeToDelete)
    }
    
}

// MARK: - Implementing NewComposeMessageViewDelegate for sending drafts

extension NewSingleDiscussionViewController: NewComposeMessageViewDelegate {
    
    /// This method is called when the user taps the location button in the view allowint to compose a message.
    func userWantsToShowMapToSendOrShareLocationContinuously(_ newComposeMessageView: NewComposeMessageView, discussionIdentifier: ObvDiscussionIdentifier) async throws {
        guard let delegate else { assertionFailure(); throw Self.makeError(message: "Delegate is nil") }
        try await delegate.userWantsToShowMapToSendOrShareLocationContinuously(self, discussionIdentifier: discussionIdentifier)
    }
    
    func userWantsToUpdateDraftExpiration(_ newComposeMessageView: NewComposeMessageView, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, value: PersistedDiscussionSharedConfigurationValue?) async throws {
        guard let delegate else { assertionFailure(); throw Self.makeError(message: "Delegate is nil") }
        try await delegate.userWantsToUpdateDraftExpiration(self, draftObjectID: draftObjectID, value: value)
    }
    
    
    func userWantsToRemoveReplyToMessage(_ newComposeMessageView: NewComposeMessageView, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws {
        guard let delegate else { assertionFailure(); throw Self.makeError(message: "Delegate is nil") }
        try await delegate.userWantsToRemoveReplyToMessage(self, draftObjectID: draftObjectID)
    }
    
    
    func userWantsToUpdateDraftBodyAndMentions(_ newComposeMessageView: NewComposeMessageView, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, body: String, mentions: Set<MessageJSON.UserMention>) async throws {
        guard let delegate else { assertionFailure(); throw Self.makeError(message: "Delegate is nil") }
        try await delegate.userWantsToUpdateDraftBodyAndMentions(self, draftObjectID: draftObjectID, body: body, mentions: mentions)
    }
    
    
    /// Called by the `NewComposeMessageView` when the user wants to send a draft.
    func userWantsToSendDraft(_ newComposeMessageView: NewComposeMessageView, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, textBody: String, mentions: Set<MessageJSON.UserMention>) async throws {
        guard let delegate else { assertionFailure(); throw Self.makeError(message: "Delegate is nil") }
        try await delegate.userWantsToSendDraft(self, draftPermanentID: draftPermanentID, textBody: textBody, mentions: mentions)
    }
    
    
    func userWantsToAddAttachmentsToDraft(_ newComposeMessageView: NewComposeMessageView, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, itemProviders: [NSItemProvider]) async throws {
        guard let delegate else { assertionFailure(); throw Self.makeError(message: "Delegate is nil") }
        try await delegate.userWantsToAddAttachmentsToDraft(self, draftPermanentID: draftPermanentID, itemProviders: itemProviders)
    }
    
    
    func userWantsToAddAttachmentsToDraftFromURLs(_ newComposeMessageView: NewComposeMessageView, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, urls: [URL]) async throws {
        guard let delegate else { assertionFailure(); throw Self.makeError(message: "Delegate is nil") }
        try await delegate.userWantsToAddAttachmentsToDraftFromURLs(self, draftPermanentID: draftPermanentID, urls: urls)
    }
    
}

// MARK: - NewComposeMessageViewDelegate for handling preview links

extension NewSingleDiscussionViewController {
    
    func newComposeMessageViewWantsToRemovePreview(_ newComposeMessageView: NewComposeMessageView) {
        sendUserWantsToRemovePreviewAttachmentsToDraft(draftObjectID: discussion.draft.typedObjectID)
    }

    /// Called by the ``NewComposeMessageView`` whenever a new link is detected or deleted
    func newComposeMessageViewHasDetectedLink(_ newComposeMessageView: NewComposeMessageView) {

        if let link = newComposeMessageView.currentHttpsURLDetected {
            guard previewMetadataInComposeView?.url != link else { return }
            Task {
                do {
                    sendUserWantsToRemovePreviewAttachmentsToDraft(draftObjectID: discussion.draft.typedObjectID)
                    
                    guard ObvMessengerSettings.Discussions.attachLinkPreviewToMessageSent else { return }
                    
                    let previewMetadataProvider = LPMetadataProvider()
                    let linkMetadataFromProvider = try await previewMetadataProvider.startFetchingMetadata(for: link)
                    
                    // We check that the link detected is the one get by the provider to avoid a preview to be fetched after another one. We also check that the compose view is still detecting the current url to avoid adding a preview after a message has been sent.
                    guard linkMetadataFromProvider.originalURL == newComposeMessageView.currentHttpsURLDetected else {
                        return
                    }
                    
                    let linkMetadata = await ObvLinkMetadata.from(linkMetadata: linkMetadataFromProvider)
                    
                    self.previewMetadataInComposeView = linkMetadata
                    if let discussionDraftObjectPermanentID = try? discussion.draft.objectPermanentID {
                        try? await sendUserWantsToAddAttachmentstoDraft(draftPermanentID: discussionDraftObjectPermanentID, linkMetadata: linkMetadata)
                    }
                } catch {
                    sendUserWantsToRemovePreviewAttachmentsToDraft(draftObjectID: discussion.draft.typedObjectID)
                    previewMetadataInComposeView = nil
                }
            }
        } else {
            Task {
                do {
                    sendUserWantsToRemovePreviewAttachmentsToDraft(draftObjectID: discussion.draft.typedObjectID)
                    previewMetadataInComposeView = nil
                }
            }
        }
    }
    

    private func sendUserWantsToAddAttachmentstoDraft(draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, linkMetadata: ObvLinkMetadata) async throws {
        let itemProvider = NSItemProvider(item: linkMetadata, typeIdentifier: UTType.olvidLinkPreview.identifier)
        try await delegate?.userWantsToAddAttachmentsToDraft(self, draftPermanentID: draftPermanentID, itemProviders: [itemProvider])
    }

    
    private func sendUserWantsToRemovePreviewAttachmentsToDraft(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) {
        guard let delegate = self.delegate else { assertionFailure(); return }
        Task { [weak self] in
            guard let self else { return }
            await delegate.userWantsToDeleteAttachmentsFromDraft(self, draftObjectID: draftObjectID, draftTypeToDelete: .preview)
        }
    }
}

// MARK: - NewComposeMessageViewDelegate for handling the scroll

extension NewSingleDiscussionViewController {
        
    func newComposeMessageViewShortcutPickerAboveSiblingView(_ newComposeMessageView: NewComposeMessageView) -> UIView {
        return scrollToBottomButton
    }

    func newComposeMessageViewShortcutPickerSuperview(_ newComposeMessageView: NewComposeMessageView) -> UIView {
        return view
    }

    func newComposeMessageViewShortcutPickerGeometryPlacementSiblingView(_ newComposeMessageView: NewComposeMessageView) -> UIView {
        return composeMessageView!
    }

    private func registerForKeyboardNotifications() {
        guard !isRegisteredToKeyboardNotifications else { return }
        defer { isRegisteredToKeyboardNotifications = true }
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidHideOrShow(_:)), name: UIResponder.keyboardDidHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidHideOrShow(_:)), name: UIResponder.keyboardDidShowNotification, object: nil)
        if #unavailable(iOS 15.5) {
            // This observers updates the in-house keyboard layout guide. It will be removed as soon as Apple's keyboardLayoutGuide works as expected
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShowOrHide(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShowOrHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        }
    }

    
    @objc private func keyboardDidHideOrShow(_ notification: Notification) {
        toggledWhenKeyboardDidHideOrShow.toggle()
        guard composeMessageView.preventTextViewFromEditing == false else { return }
        composeMessageView.setNeedsLayout()
        UIView.animate(withDuration: 0.3) { [weak self] in
            self?.composeMessageView.layoutIfNeeded()
        }
    }

    // Should only be used for iOS < 15.5
    @available(iOS, introduced: 15.0, deprecated: 15.5, message: "Used to simulated Apple's built-in keyboardLayoutGuide as it is bugged for iOS before 15.5")
    @objc private func keyboardWillShowOrHide(_ notification: Notification) {
        let info = notification.userInfo
        guard let endRect = info?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { assertionFailure(); return }
        var offset = view.bounds.size.height - endRect.origin.y
        if offset == 0 {
            offset = view.safeAreaInsets.bottom
        }
        let duration = info?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 2.0
        
        let viewOriginInWindow = view.convert(view.frame.origin, to: nil) // Non-zero when displaying the call banner
        offset += viewOriginInWindow.y
        
        UIView.animate(withDuration: duration) { [weak self] in
            self?.view.layoutIfNeeded()
        }
    }
    
}


// MARK: - Compose view visibility

extension NewSingleDiscussionViewController {

    /// Call this method when this view controller changes in a way that potentially requires to change the view that is currently visible above the the keyboard.
    /// This is for example the case when the user starts a search.
    private func configureAcessoryViewVisibility(animate: Bool) {
        assert(Thread.isMainThread)
        
        guard let composeMessageView = self.composeMessageView else { assertionFailure(); return }

        let accessoryViewKindToShow = self.accessoryViewKindToShow
        guard accessoryViewKindShown != accessoryViewKindToShow || !animate else { return }
        accessoryViewKindShown = accessoryViewKindToShow
                               
        if animate {
            switch accessoryViewKindToShow {
            case .none:
                UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 0.3, delay: 0.0) { [weak self] in
                    self?.composeMessageView.alpha = 0
                    self?.singleDiscussionSearchView.alpha = 0
                } completion: { [weak self] _ in
                    self?.composeMessageView.isHidden = true
                    self?.singleDiscussionSearchView.isHidden = true
                }
            case .messageCompose:
                composeMessageView.alpha = 0.0
                composeMessageView.isHidden = false
                UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 0.3, delay: 0.0) { [weak self] in
                    self?.composeMessageView.alpha = 1
                    self?.singleDiscussionSearchView.alpha = 0
                } completion: { [weak self] _ in
                    self?.singleDiscussionSearchView.isHidden = true
                }
            case .searchBrowsing:
                singleDiscussionSearchView.alpha = 0.0
                singleDiscussionSearchView.isHidden = false
                UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 0.3, delay: 0.0) { [weak self] in
                    self?.composeMessageView.alpha = 0
                    self?.singleDiscussionSearchView.alpha = 1
                } completion: { [weak self] _ in
                    self?.composeMessageView.isHidden = true
                }
            }
        } else {
            self.composeMessageView.isHidden = (accessoryViewKindToShow != .messageCompose)
            self.singleDiscussionSearchView.isHidden = (accessoryViewKindToShow != .searchBrowsing)
        }
        
    }
 
    
    private enum AccessoryViewKind {
        case none
        case messageCompose
        case searchBrowsing
    }
    
    
    private var accessoryViewKindToShow: AccessoryViewKind {
        assert(Thread.isMainThread)
        if isUserPerformingSearch {
            return .searchBrowsing
        }
        do {
            guard let discussion = try PersistedDiscussion.get(objectID: discussionObjectID, within: ObvStack.shared.viewContext) else {
                return .none
            }
            // We do not show the compose view for locked discussions
            switch discussion.status {
            case .preDiscussion, .locked:
                return .none
            case .active:
                break
            }
            switch try? discussion.kind {
            case .oneToOne(withContactIdentity: let contactIdentity):
                // We do not show the compose view for a one-to-one discussion with a contact s.t. isActive == false
                if contactIdentity?.isActive != true {
                    return .none
                }
            case .groupV1(withContactGroup: let contactGroup):
                // We do no not show the compose view if we have no one to write to in a group discussion
                guard let contactGroup = contactGroup else { assertionFailure(); return .none }
                if !contactGroup.hasAtLeastOneRemoteContactDevice() {
                    return .none
                }
            case .groupV2(withGroup: let group):
                // We allow the owned identity to write in a group v2 even if there is noone to write to.
                guard let group = group else { assertionFailure(); return .none }
                guard group.ownedIdentityIsAllowedToSendMessage else { return .none }
            case .none:
                assertionFailure()
            }
        } catch {
            assertionFailure(error.localizedDescription)
            return .none
        }
        return .messageCompose
    }

}



// MARK: - Localization

extension NewSingleDiscussionViewController {
    
    struct Strings {
        
        static let deleteMessageAndAttachmentsTitle = NSLocalizedString("Delete Message and Attachments", comment: "Title of alert")
        
        static let deleteMessageTitle = NSLocalizedString("Delete Message", comment: "Title of alert")

        static let deleteMessageAndAttachmentsMessage = { (numberOfAttachedFyles: Int) in
            String.localizedStringWithFormat(NSLocalizedString("You are about to delete a message together with its count attachments", comment: "Message of alert"), numberOfAttachedFyles)
        }

        static let sharePhotos = { (count: Int) in
            return String.localizedStringWithFormat(NSLocalizedString("share count photos", comment: "Localized dict string allowing to display a title"), count)
        }
        
        static let shareAttachments = { (count: Int) in
            return String.localizedStringWithFormat(NSLocalizedString("share count attachments", comment: "Localized dict string allowing to display a title"), count)
        }

        static let saveAttachments = { (count: Int) in
            return String.localizedStringWithFormat(NSLocalizedString("save count attachments", comment: "Localized dict string allowing to display a title"), count)
        }

        static var replyingToYourself: String {
            NSLocalizedString("REPLYING_TO_YOURSELF", comment: "")
        }

        static var replying: String {
            NSLocalizedString("REPLYING", comment: "")
        }

        static let mutedNotificationsConfirmation = { (date: String) in String.localizedStringWithFormat(NSLocalizedString("MUTED_NOTIFICATIONS_CONFIRMATION_%@", comment: ""), date)}
        
        static var discussionSettings: String {
            NSLocalizedString("DISCUSSION_SETTINGS", comment: "")
        }

        static var unmuteNotifications: String {
            NSLocalizedString("UNMUTE_NOTIFICATIONS", comment: "")
        }
    }
    
}


// MARK: - Tapping on cells, UIGestureRecognizerDelegate and TextBubbleDelegate

extension NewSingleDiscussionViewController {
    
    private func observeTapsOnCollectionView() {

        self.singleTapOnCell = UITapGestureRecognizer(target: self, action: #selector(tapPerformed))
        self.singleTapOnCell.delegate = self
        self.collectionView.addGestureRecognizer(singleTapOnCell)
        
        self.doubleTapOnCell = UITapGestureRecognizer(target: self, action: #selector(doubleTapPerformed))
        self.doubleTapOnCell.numberOfTapsRequired = 2
        self.doubleTapOnCell.delegate = self
        self.collectionView.addGestureRecognizer(doubleTapOnCell)
        
    }
    
    
    /// Implementing `TextBubbleDelegate`, allowing the `TextBubble` to request the gesture that should fail befor accepting a tap, e.g., on links.
    var gestureThatLinkTapShouldRequireToFail: UIGestureRecognizer? {
        doubleTapOnCell
    }

    
    @objc func tapPerformed(recognizer: UITapGestureRecognizer) {

        guard recognizer.state == .ended else { return }
        let location = recognizer.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: location) else { return }
        guard let cell = collectionView.cellForItem(at: indexPath) else { return }
        guard let cellWithTappableStuff = cell as? UIViewWithTappableStuff else { return }
        tapPerformedOn(cellWithTappableStuff, tapGestureRecognizer: recognizer)

    }

    
    @objc func doubleTapPerformed(recognizer: UITapGestureRecognizer) {
        
        guard recognizer.state == .ended else { return }
        
        let location = recognizer.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: location) else { return }
        guard let cell = collectionView.cellForItem(at: indexPath) else { return }
        guard let cellWithMessage = cell as? CellWithMessage else { return }
        
        composeMessageView.animatedEndEditing { [weak self] _ in
            self?.showReactionOnDoubleTap(from: cellWithMessage)
        }

    }
    
    private func showReactionOnDoubleTap(from cellWithMessage: CellWithMessage) {
        guard self.contextReactionRootView == nil else {
            return
        }
        
        guard let messageId = cellWithMessage.persistedMessageObjectID else {
            return
        }
        
        let targetingPoint = CGPoint(x: cellWithMessage.viewForTargetedPreview.center.x, y: 0.0)
        var cellLocation = cellWithMessage.viewForTargetedPreview.convert(targetingPoint, to: self.view)
        cellLocation.x = cellWithMessage.viewForTargetedPreview.center.x + 10.0
        
        guard let persistedMessage = try? PersistedMessage.get(with: messageId, within: ObvStack.shared.viewContext) else { return }
        guard !persistedMessage.isWiped else { return }
        guard (try? persistedMessage.ownedIdentityIsAllowedToSetReaction) == true else { return }
                
        addContextReactionViewIfNeeded(messageId: messageId, atLocation: cellLocation, viewToHighlight: cellWithMessage.viewForTargetedPreview)
    }
    
    private func tapPerformedOn(_ viewWithTappableStuff: UIViewWithTappableStuff, tapGestureRecognizer: UITapGestureRecognizer) {
        guard let tappedStuff = viewWithTappableStuff.tappedStuff(tapGestureRecognizer: tapGestureRecognizer) else { return }
        switch tappedStuff {
            
        case let .openLink(url: url):
            Task { await UIApplication.shared.userSelectedURL(url, within: self) }
        
        case let .openExternalMapAt(latitude: latitude, longitude: longitude, address: address):
            Task { await UIApplication.shared.userWantsToOpenMapAt(latitude: latitude, longitude: longitude, address: address, within: self) }
            
        case let .openMap(messageObjectID: messageObjectID):
            if #available(iOS 17.0, *) {
                Task {
                    await displayMapForSharedLocation(messageObjectID: messageObjectID)
                }
            }
            
        case .behaveAsIfTheDiscussionTitleWasTapped:
            titleViewWasTapped()
            
        case .hardlink(let hardLink):
            userDidTapOnFyleMessageJoinWithHardLink(hardlinkTapped: hardLink)
            
        case .messageThatRequiresUserAction(messageObjectID: let messageObjectID):
            guard let discussionId = try? discussion.identifier else { assertionFailure(); return }
            Task { [weak self] in
                guard let self else { return }
                guard let delegate else { assertionFailure(); return }
                try? await delegate.userWantsToReadReceivedMessageThatRequiresUserAction(self,
                                                                                         ownedCryptoId: currentOwnedCryptoId,
                                                                                         discussionId: discussionId,
                                                                                         messageId: .objectID(objectID: messageObjectID.objectID))
            }
            
        case .receivedFyleMessageJoinWithStatusToResumeDownload(receivedJoinObjectID: let receivedJoinObjectID):
            guard let delegate else { assertionFailure(); return }
            Task { [weak self] in
                guard let self else { return }
                try? await delegate.userWantsToDownloadReceivedFyleMessageJoinWithStatus(self, receivedJoinObjectID: receivedJoinObjectID)
            }
            
        case .receivedFyleMessageJoinWithStatusToPauseDownload(receivedJoinObjectID: let receivedJoinObjectID):
            guard let delegate else { assertionFailure(); return }
            Task { [weak self] in
                guard let self else { return }
                try? await delegate.userWantsToPauseDownloadReceivedFyleMessageJoinWithStatus(self, receivedJoinObjectID: receivedJoinObjectID)
            }
            
        case .sentFyleMessageJoinWithStatusReceivedFromOtherOwnedDeviceToResumeDownload(sentJoinObjectID: let sentJoinObjectID):
            guard let delegate else { assertionFailure(); return }
            Task { [weak self] in
                guard let self else { return }
                try? await delegate.userWantsToDownloadSentFyleMessageJoinWithStatusFromOtherOwnedDevice(self, sentJoinObjectID: sentJoinObjectID)
            }

        case .sentFyleMessageJoinWithStatusReceivedFromOtherOwnedDeviceToPauseDownload(sentJoinObjectID: let sentJoinObjectID):
            guard let delegate else { assertionFailure(); return }
            Task { [weak self] in
                guard let self else { return }
                try? await delegate.userWantsToPauseSentFyleMessageJoinWithStatusFromOtherOwnedDevice(self, sentJoinObjectID: sentJoinObjectID)
            }

        case .reaction(messageObjectID: let messageObjectID):
            userTappedOnReactionView(messageObjectID: messageObjectID)
            
        case .missedMessageBubble:
            ObvMessengerInternalNotification.userDidTapOnMissedMessageBubble
                .postOnDispatchQueue()
            
        case .circledInitials(contactObjectID: let contactObjectID):
            assert(delegate != nil)
            delegate?.userDidTapOnContactImage(contactObjectID: contactObjectID)
            
        case .replyTo(replyToMessageObjectID: let replyToMessageObjectID):
            userDidTapOnReplyTo(replyToMessageObjectID: replyToMessageObjectID)
            
        case .systemCellShowingCallLogItemRejectedIncomingCallBecauseOfDeniedRecordPermission:
            systemCellShowingCallLogItemRejectedIncomingCallBecauseOfDeniedRecordPermissionWasTapped()
            
        case .systemCellShowingCallLogItemRejectedBecauseOfVoIPSettings:
            ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: ObvDeepLink.voipSettings)
                .postOnDispatchQueue()
                        
        case .systemCellShowingUpdatedDiscussionSharedSettings:
            settingsButtonTapped()
            
        }
    }
    
    
    /// This gets called when a message attachment is tapped (either an image, a non-image file, ...). We receive the `HardLinkToFyle` that was used to display the preview.
    /// We use it to query each visible cell in order to first determine which cell is concerned. This is possible because a `HardLinkToFyle` uniquely determines
    /// a `SentFyleMessageJoinWithStatus` instance.
    private func userDidTapOnFyleMessageJoinWithHardLink(hardlinkTapped: HardLinkToFyle) {
        assert(Thread.isMainThread)
        guard let cell = findCellShowingHardlink(hardlinkTapped) else { assertionFailure(); return }
        guard let message = cell.persistedMessage else { assertionFailure(); return }
        guard let join = message.fyleMessageJoinWithStatus?.first(where: { $0.fyle?.url == hardlinkTapped.fyleURL }) else { assertionFailure(); return }
        guard let frc = try? FyleMessageJoinWithStatus.getFetchedResultsControllerForAllJoinsWithinMessage(message) else { assertionFailure(); return }
        do {
            try frc.performFetch()
        } catch {
            os_log("Could not perform fetch %{public}@", log: log, type: .fault, error.localizedDescription)
            return
        }
        filesViewer = FilesViewer(frc: frc, qlPreviewControllerDelegate: self)
        composeMessageView.animatedEndEditing { [weak self] _ in
            guard let _self = self else { return }
            do {
                try _self.filesViewer?.tryToShowFyleMessageJoinWithStatus(join, within: _self)
            } catch {
                os_log("Could not show join %{public}@", log: _self.log, type: .fault, error.localizedDescription)
            }
        }
    }

    
    private func systemCellShowingCallLogItemRejectedIncomingCallBecauseOfDeniedRecordPermissionWasTapped() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { (granted) in
                DispatchQueue.main.async { [weak self] in
                    self?.reconfigureCellsShowingCallLogItemRejectedIncomingCallBecauseOfDeniedRecordPermission()
                }
            }
        case .denied:
            ObvMessengerInternalNotification.rejectedIncomingCallBecauseUserDeniedRecordPermission
                .postOnDispatchQueue()
        case .granted:
            break
        @unknown default:
            assertionFailure()
        }
    }

    
    private func userDidTapOnReplyTo(replyToMessageObjectID: NSManagedObjectID) {
        guard let frc = self.frc else { return }
        guard let message = try? PersistedMessage.get(with: replyToMessageObjectID, within: frc.managedObjectContext) else { return }
        guard let indexPath = frc.indexPath(forObject: message) else { return }
        self.scrollToItemAtIndexPath(indexPath)
    }

    
    private func userDoubleTappedOnMessage(messageID: TypeSafeManagedObjectID<PersistedMessage>) {
        userWantsToReactToMessage(messageID: messageID)
    }

    @MainActor
    private func userWantsToReactToMessage(messageID: TypeSafeManagedObjectID<PersistedMessage>) {
        guard let message = try? PersistedMessage.get(with: messageID, within: ObvStack.shared.viewContext) else { return }
        guard let ownedCryptoId = message.discussion?.ownedIdentity?.cryptoId else { return }
        guard !message.isWiped else { return }
        guard (try? message.ownedIdentityIsAllowedToSetReaction) == true else { return }
        var selectedEmoji: String?
        if let ownReaction = message.reactionFromOwnedIdentity() {
            selectedEmoji = ownReaction.emoji
        }
        let model = EmojiPickerViewModel(selectedEmoji: selectedEmoji) { [weak self] emoji in
            guard let self else { return }
            guard let delegate else { assertionFailure(); return }
            Task { [weak self] in
                guard let self else { return }
                try? await delegate.userWantsToUpdateReaction(self, ownedCryptoId: ownedCryptoId, messageObjectID: messageID, newEmoji: emoji)
            }
        }
        let vc = EmojiPickerHostingViewController(model: model)
        
        if ObvMessengerConstants.targetEnvironmentIsMacCatalyst {
            
            let nav = UINavigationController(rootViewController: vc)
            present(nav, animated: true)

        } else {

            if let sheet = vc.sheetPresentationController {
                sheet.detents = [ .medium() ]
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = 30.0
            }
            present(vc, animated: true)

        }
        
    }

    
    private func userTappedOnReactionView(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>) {
        guard let message = try? PersistedMessage.get(with: messageObjectID, within: ObvStack.shared.viewContext) else { return }

        guard let vc = MessageReactionsListHostingViewController(message: message, delegate: self) else {
            assertionFailure()
            return
        }
        
        if ObvMessengerConstants.targetEnvironmentIsMacCatalyst {
            
            let nav = UINavigationController(rootViewController: vc)
            present(nav, animated: true)
            
        } else {
            
            if let sheet = vc.sheetPresentationController {
                sheet.detents = [ .medium(), .large() ]
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = 30.0
            }
            present(vc, animated: true)
            
        }
        
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive event: UIEvent) -> Bool {
        // Long Press should not receive touch if the view touched is an UIButton to prevent any delay on interaction.
        if event.allTouches?.first?.view is UIButton {
            return false
        }
        return true
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Don't recognize the single tap on cell until the double-tap on cell fails
        return gestureRecognizer == self.singleTapOnCell && otherGestureRecognizer == self.doubleTapOnCell
    }

}

// MARK: - ViewShowingHardLinksDelegate / CustomQLPreviewControllerDelegate / Previewing attachments

extension NewSingleDiscussionViewController {
    
    func userDidTapOnDraftFyleJoinWithHardLink(at indexPath: IndexPath) {
        guard let frc = composeMessageView.attachmentsCollectionViewController.frc else { assertionFailure(); return }
        filesViewer = FilesViewer(frc: frc, qlPreviewControllerDelegate: self)
        composeMessageView.animatedEndEditing { [weak self] _ in
            assert(Thread.isMainThread)
            guard let _self = self else { return }
            self?.filesViewer?.tryToShowFile(atIndexPath: indexPath, within: _self)
        }
    }

    
    private func findCellShowingHardlink(_ hardlink: HardLinkToFyle) -> MessageCellShowingHardLinks? {
        let allVisibleCellsShowingHardlinks = collectionView.visibleCells.compactMap({ $0 as? MessageCellShowingHardLinks })
        for cell in allVisibleCellsShowingHardlinks {
            let allHardlinkShownByCell = cell.getAllShownHardLink().map({ $0.hardlink })
            if allHardlinkShownByCell.contains(hardlink) {
                return cell
            }
        }
        return nil
    }


    func previewController(_ controller: QLPreviewController, transitionViewFor item: QLPreviewItem) -> UIView? {
        guard let filesViewer = self.filesViewer else { assertionFailure(); return nil }
        switch filesViewer.frcType {
        case .fyleMessageJoinWithStatus(frc: let frc):
            guard let currentPreviewJoin = filesViewer.currentPreviewFyleMessageJoinWithStatus else { assertionFailure(); return nil }
            guard let message = frc.fetchedObjects?.first?.message else { return nil }
            guard let cell = collectionView.visibleCells.compactMap({ $0 as? CellWithMessage }).first(where: { $0.persistedMessageObjectID == message.typedObjectID }) as? ViewShowingHardLinks else { return nil }
            let allHardLinkShownByCell = cell.getAllShownHardLink()
            let attachmentIndex = Int(allHardLinkShownByCell.firstIndex(where: { $0.hardlink.fyleURL == currentPreviewJoin.fyle?.url }) ?? 0)
            return allHardLinkShownByCell[attachmentIndex].viewShowingHardLink
        case .persistedDraftFyleJoin:
            let attachmentIndex = controller.currentPreviewItemIndex
            let indexPath = IndexPath(item: attachmentIndex, section: 0)
            return composeMessageView.attachmentsCollectionViewController.getView(at: indexPath)
        }
    }

    func previewController(hasDisplayed joinID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) {
        ObvMessengerInternalNotification.userHasOpenedAReceivedAttachment(receivedFyleJoinID: joinID).postOnDispatchQueue()
    }
    
    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        self.filesViewer = nil
    }

    
    /// We observe notifications of deleted fyle message joins (i.e., attachments) so as to be able to dismiss the File Viewer if:
    /// - there is one presented ;-)
    /// - it is currently configured to show one of the deleted attachments
    /// This typically occurs for attachments with limited visibility. The first time we tap on such an attachment, the counter starts.  When it is over, we delete de whole message, including the attachments.
    /// In that case, we do not allow the user to continue viewing any of those attachments so we dismiss the file viewer.
    private func observeDeletedFyleMessageJoinNotifications() {
        let NotificationName = NSNotification.Name.NSManagedObjectContextObjectsDidChange
        let token = NotificationCenter.default.addObserver(forName: NotificationName, object: nil, queue: nil) { [weak self] (notification) in
            
            // Make sure we are considering changes made in the view context, i.e., posted on the main thread
            
            guard Thread.isMainThread else { return }
            
            // Construct a set of FyleMessageJoinWithStatus currently shown by the file viewer
            
            guard let filesViewer = self?.filesViewer else { return }
            guard case .fyleMessageJoinWithStatus(frc: let frcOfFilesViewer) = filesViewer.frcType else { return }
            guard let shownObjectIDs = frcOfFilesViewer.fetchedObjects?.map({ $0.objectID }) else { return }

            // Construct a set of deleted/wiped FyleMessageJoinWithStatus
            
            var objectIDs = Set<NSManagedObjectID>()
            do {
                if let deletedObjects = notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject>, !deletedObjects.isEmpty {
                    let deletedFyleMessageJoinWithStatuses = deletedObjects.compactMap({ $0 as? FyleMessageJoinWithStatus })
                    objectIDs.formUnion(Set(deletedFyleMessageJoinWithStatuses.map({ $0.objectID })))
                }
                if let updatedObjects = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject>, !updatedObjects.isEmpty {
                    let wipedFyleMessageJoinWithStatuses = updatedObjects
                        .compactMap { $0 as? FyleMessageJoinWithStatus }
                        .filter { $0.isWiped }
                    objectIDs.formUnion(Set(wipedFyleMessageJoinWithStatuses.map({ $0.objectID })))
                }
            }
            
            guard !objectIDs.isEmpty else { return }
            
            // Construct a set of FyleMessageJoinWithStatus shown by the file viewer
            
            guard !objectIDs.isDisjoint(with: shownObjectIDs) else { return }
            DispatchQueue.main.async {
                (self?.presentedViewController as? QLPreviewController)?.dismiss(animated: true, completion: {
                    self?.filesViewer = nil
                })
            }
        }
        observationTokens.append(token)
    }

}


// MARK: - UICollectionViewDataSourcePrefetching

extension NewSingleDiscussionViewController {
    
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            guard let message = frc.safeObject(at: indexPath) else { continue }
            guard message is PersistedMessageSent || message is PersistedMessageReceived else { continue }
            cacheDelegate.requestAllRelevantHardlinksForMessage(with: message.typedObjectID, completionWhenHardlinksCached: { _ in })
            if let text = message.displayableAttributedBody {
                cacheDelegate.requestDataDetection(attributedString: text, completionWhenDataDetectionCached: { _ in })
            }
            // We only try to fetch preview for message received.
            if let messageReceived = message as? PersistedMessageReceived {
                cacheDelegate.requestMissingPreviewIfNeededForMessage(with: messageReceived.typedObjectID)
            }
        }
    }
    
    
    
}

// MARK: - AudioPlayerViewDelegate

extension NewSingleDiscussionViewController: AudioPlayerViewDelegate {

    func audioHasBeenPlayed(_ hardlink: HardLinkToFyle) {
        guard let cell = findCellShowingHardlink(hardlink) else { assertionFailure(); return }
        guard let message = cell.persistedMessage else { assertionFailure(); return }
        guard let join = message.fyleMessageJoinWithStatus?.first(where: { $0.fyle?.url == hardlink.fyleURL }) else { assertionFailure(); return }
        guard let receivedJoin = join as? ReceivedFyleMessageJoinWithStatus else { return }
        ObvMessengerInternalNotification.userHasOpenedAReceivedAttachment(receivedFyleJoinID: receivedJoin.typedObjectID).postOnDispatchQueue()
    }
}

// MARK: - Extension to handle Map
@available(iOS 17.0, *)
extension NewSingleDiscussionViewController {
    
    private func displayMapForSharedLocation(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>) async {

        guard let delegate else { assertionFailure(); return }

        await composeMessageView.animatedEndEditing()

        do {
            try await delegate.userWantsToShowMapToConsultLocationSharedContinously(self, messageObjectID: messageObjectID)
        } catch {
            Self.logger.fault("Could not show map to consult location shared continously: \(error)")
        }
        
    }
    
}

// MARK: - TextBubbleDelegate

extension NewSingleDiscussionViewController {
    
    func textBubble(_ textBubble: TextBubble, userDidTapOn mentionableIdentity: ObvMentionableIdentityAttribute.Value) async {
        await delegate?.singleDiscussionViewController(self, userDidTapOn: mentionableIdentity)
    }
    
    
    func textView(_ textBubble: TextBubble, shouldInteractWith URL: URL, interaction: UITextItemInteraction) -> Bool {
        Task { await UIApplication.shared.userSelectedURL(URL, within: self) }
        return false
    }
    
}


// MARK: - Implementing CellReplyToDelegate

extension NewSingleDiscussionViewController: CellReplyToDelegate {
    
    func userWantsToReplyToMessage(messageObjectID: ObvUICoreData.TypeSafeManagedObjectID<ObvUICoreData.PersistedMessage>, draftObjectID: ObvUICoreData.TypeSafeManagedObjectID<ObvUICoreData.PersistedDraft>) async throws {
        try await delegate?.userWantsToReplyToMessage(self, messageObjectID: messageObjectID, draftObjectID: draftObjectID)
    }
    
}


// MARK: - Mentions Reconfigure Mention Cells

private extension NewSingleDiscussionViewController {
    func observeNicknameChanges() {
        observationTokens.append(ObvMessengerCoreDataNotification.observePersistedContactHasNewCustomDisplayName { [weak self] _ in
            guard let self = self else {
                return
            }

            DispatchQueue.main.async {
                self.reloadDiscussionCellsAfterNicknameChange()
            }
        })
    }

    /// Method to be called whenever a nickname gets changed
    private func reloadDiscussionCellsAfterNicknameChange() {
        self.collectionView.reloadData()
    }
}

// MARK: - NewComposeMessageViewDatasource

extension NewSingleDiscussionViewController {
    
    func newComposeMessageView(_ newComposeMessageView: NewComposeMessageView, itemsForTextShortcut shortcut: NewComposeMessageViewTypes.TextShortcut, text: String) -> [NewComposeMessageViewTypes.TextShortcutItem] {
        
        switch shortcut {
        case .mention:

            guard let discussionKind = try? discussion.kind else {
                assertionFailure("failed to retrieve discussion kind")

                return []
            }

            guard let ownedIdentity = discussion.ownedIdentity else {
                assertionFailure("our owned identity does not exist, can't mention")
                return []
            }

            let mentionableIdentities: [MentionableIdentity]

            switch discussionKind {
            case .oneToOne(withContactIdentity: let otherContactIdentity):
                guard let otherContactIdentity else {
                    return []
                }

                mentionableIdentities = [otherContactIdentity,
                                         ownedIdentity]

            case .groupV1(withContactGroup: let contactGroup):
                guard let contactGroup else {
                    return []
                }

                mentionableIdentities = (contactGroup.sortedContactIdentities as [MentionableIdentity])..{
                    $0.append(ownedIdentity)

                    $0.sort(by: \.mentionDisplayName)
                }

            case .groupV2(withGroup: let group):
                guard let group else {
                    return []
                }

                mentionableIdentities = (group.otherMembersSorted as [MentionableIdentity])..{
                    $0.append(ownedIdentity)

                    $0.sort(by: \.mentionDisplayName)
                }
            }

            let baseResults = mentionableIdentities
                .map(NewComposeMessageViewTypes.TextShortcutItem.init)

            let searchQuery = String(text.dropFirst(MentionsConstants.mentionPrefix.count))

            guard searchQuery.isEmpty == false else {
                return baseResults
            }

            let predicate = NSPredicate(format: "self CONTAINS[cd] %@", searchQuery)

            return baseResults
                .filter { item in
                    return predicate.evaluate(with: item.searchMatcher)
                }
        }
    }
}

@available(iOS 14.0, *)
private extension NewComposeMessageViewTypes.TextShortcutItem {
    init(_ member: MentionableIdentity) {
        let attributes = [NSAttributedString.Key: Any].compositionMentionAttributes(member)

        self.init(searchMatcher: member.mentionSearchMatcher,
                  title: MentionsConstants.mentionPrefix + member.mentionPickerTitle,
                  subtitle: member.mentionPickerSubtitle,
                  accessory: .circledInitialsView(configuration: member.circledInitialsConfiguration),
                  value: .init(string: MentionsConstants.mentionPrefix + member.mentionPersistedName,
                               attributes: attributes))
    }
}


// MARK: - NewDiscussionsSelectionViewControllerDelegate

@available(iOS 16.0, *)
extension NewSingleDiscussionViewController: NewDiscussionsSelectionViewControllerDelegate {
    
    func userAcceptedlistOfSelectedDiscussions(_ listOfSelectedDiscussions: [TypeSafeManagedObjectID<PersistedDiscussion>], in newDiscussionsSelectionViewController: UIViewController) {
        newDiscussionsSelectionViewController.dismiss(animated: true) { [weak self] in
            guard let messageToForward = self?.messageToForward else { assertionFailure(); return }
            self?.messageToForward = nil
            guard !listOfSelectedDiscussions.isEmpty else { return }
            let discussionPermanentIDs: Set<ObvManagedObjectPermanentID<PersistedDiscussion>> = Set(listOfSelectedDiscussions.compactMap { discussionID in
                guard let discussion = try? PersistedDiscussion.get(objectID: discussionID.objectID, within: ObvStack.shared.viewContext) else { assertionFailure(); return nil }
                return discussion.discussionPermanentID
            })
            ObvMessengerInternalNotification.userWantsToForwardMessage(messagePermanentID: messageToForward.messagePermanentID, discussionPermanentIDs: discussionPermanentIDs)
                .postOnDispatchQueue()
            self?.navigateIfAppropriateToDiscussionWhereMessageWasForwarded(discussionPermanentIDs: discussionPermanentIDs, persistedMessage: messageToForward)
        }
    }

}


// MARK: - DiscussionsSelectionViewControllerDelegate

extension NewSingleDiscussionViewController: DiscussionsSelectionViewControllerDelegate {
    
    func userAcceptedlistOfSelectedDiscussions(_ listOfSelectedDiscussions: Set<ObvManagedObjectPermanentID<PersistedDiscussion>>, in discussionsSelectionViewController: UIViewController) {
        discussionsSelectionViewController.dismiss(animated: true) { [weak self] in
            guard let messageToForward = self?.messageToForward else { assertionFailure(); return }
            self?.messageToForward = nil
            guard !listOfSelectedDiscussions.isEmpty else { return }
            let discussionPermanentIDs = listOfSelectedDiscussions
            ObvMessengerInternalNotification.userWantsToForwardMessage(messagePermanentID: messageToForward.messagePermanentID, discussionPermanentIDs: discussionPermanentIDs)
                .postOnDispatchQueue()
            self?.navigateIfAppropriateToDiscussionWhereMessageWasForwarded(discussionPermanentIDs: discussionPermanentIDs, persistedMessage: messageToForward)
        }
    }

}


// MARK: - UICollectionViewDropDelegate

extension NewSingleDiscussionViewController {
    
    func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool {
        debugPrint("🫵 \(self.debugDescription) canHandle")
        guard !isDragSessionInProgress else { return false }
        return true
    }
    
    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        guard !isDragSessionInProgress else {
            return UICollectionViewDropProposal(operation: .forbidden)
        }
        return UICollectionViewDropProposal(operation: .copy)
    }
    
    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        
        let itemProviders = coordinator.items.map(\.dragItem.itemProvider)
        Task {
            await composeMessageView.addAttachments(from: itemProviders, attachTextItems: true)
        }

    }
    
}


// MARK: - UICollectionViewDragDelegate

extension NewSingleDiscussionViewController {
    
    func collectionView(_ collectionView: UICollectionView, dragSessionWillBegin session: UIDragSession) {
        isDragSessionInProgress = true
    }
    
    func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: UIDragSession) {
        isDragSessionInProgress = false
    }
    
    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard let cell = collectionView.cellForItem(at: indexPath) as? CellWithMessage else { return [] }
        return cell.uiDragItemsForAllAttachments ?? []
    }
    
}


// MARK: - Private helpers

fileprivate extension UIWindowScene.ActivationState {
    
    var obvDebugDescription: String {
        switch self {
        case .unattached: return "unattached"
        case .foregroundActive: return "foregroundActive"
        case .foregroundInactive: return "foregroundInactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
    }
    
}


fileprivate extension UIUserInterfaceActiveAppearance {
    
    var obvDebugDescription: String {
        switch self {
        case .unspecified: return "unspecified"
        case .inactive: return "inactive"
        case .active: return "active"
        @unknown default: return "unknown"
        }
    }
    
}
