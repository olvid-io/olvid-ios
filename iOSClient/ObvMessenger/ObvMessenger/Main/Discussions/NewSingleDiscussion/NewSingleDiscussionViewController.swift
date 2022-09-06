/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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

@available(iOS 15.0, *)
final class NewSingleDiscussionViewController: UIViewController, NSFetchedResultsControllerDelegate, UICollectionViewDelegate, DiscussionViewController, ViewShowingHardLinksDelegate, QLPreviewControllerDelegate, UICollectionViewDataSourcePrefetching, NewComposeMessageViewDelegate, CellReconfigurator, SomeSingleDiscussionViewController, UIGestureRecognizerDelegate, TextBubbleDelegate {
    
    static let sectionHeaderElementKind = UICollectionView.elementKindSectionHeader
    private var collectionView: DiscussionCollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, NSManagedObjectID>!
    private var frc: NSFetchedResultsController<PersistedMessage>!
    private var currentContentHeight = CGFloat(0)
    private var viewDidAppearWasCalled = false
    private var viewDidLoadWasCalled = false
    private var hideHeaderRequestId = UUID()
    private var composeMessageView: NewComposeMessageView?
    private let draftObjectID: TypeSafeManagedObjectID<PersistedDraft>
    let discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>
    private var observationTokens = [NSObjectProtocol]()
    private var unreadMessagesSystemMessage: PersistedMessageSystem?
    private let initialScroll: InitialScroll
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: NewSingleDiscussionViewController.self))
    private let internalQueue = DispatchQueue(label: "NewSingleDiscussionViewController internal queue")
    private let hidingView = UIView()
    private var initialScrollWasPerformed = false
    private var currentKbdSize = CGRect.zero
    private let queueForApplyingSnapshots = DispatchQueue(label: "NewSingleDiscussionViewController queue for snapshots")
    private let cacheDelegate = DiscussionCacheManager()
    private var cellsShowingCallLogItemRejectedIncomingCallBecauseOfDeniedRecordPermissionNeedToBeReconfigured = false
    private var messagesToMarkAsNotNewWhenScrollingEnds = Set<TypeSafeManagedObjectID<PersistedMessage>>()
    private var atLeastOneSnapshotWasApplied = false
    private var isRegisteredToKeyboardNotifications = false
    private var backgroundEffectViewForComposeView: UIVisualEffectView!

    @Published private var messagesToReconfigure = Set<TypeSafeManagedObjectID<PersistedMessage>>()
    private var cancellables = [AnyCancellable]()
    
    // Single and double tap gesture recognizers on cells
    private var singleTapOnCell: UITapGestureRecognizer!
    private var doubleTapOnCell: UITapGestureRecognizer!
    
    /// The following variables allow to simulate the keyboardLayoutGuide introduced by Apple in iOS 15. Since, for now in iOS 15.0.2, it does not work with the
    /// emoji keyboard, we simulate it.
    private let myKeyboardLayoutGuide = UILayoutGuide()
    private var myKeyboardLayoutGuideHeightConstraint: NSLayoutConstraint? // Set later

    /// The following variables are used to determine whether we should automatically scroll when the collection
    /// view is updated.
    private var lastScrollWasManual = false
    private var lastReceivedMessageObjectId: TypeSafeManagedObjectID<PersistedMessageReceived>?
    private var lastSentMessageObjectId: TypeSafeManagedObjectID<PersistedMessageSent>?
    private var lastSystemMessageObjectId: TypeSafeManagedObjectID<PersistedMessageSystem>?
    private var currentScrolling = ScrollingType.none

    private let defaultAnimationValues: (duration: Double, options: UIView.AnimationOptions) = (0.25, UIView.AnimationOptions([.curveEaseInOut]))
    
    private var isRegisteredToNotifications = false

    private var timerForRefreshingCellCountdowns: Timer?

    private var filesViewer: FilesViewer?

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
    
    private static let errorDomain = "NewSingleDiscussionViewController"
    private func makeError(message: String) -> Error {
        NSError(domain: NewSingleDiscussionViewController.errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message])
    }

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

    init(discussion: PersistedDiscussion, delegate: SingleDiscussionViewControllerDelegate, initialScroll: InitialScroll) {
        self.draftObjectID = discussion.draft.typedObjectID
        self.discussionObjectID = discussion.typedObjectID
        self.initialScroll = initialScroll
        super.init(nibName: nil, bundle: nil)
        self.composeMessageView = NewComposeMessageView(
            draft: discussion.draft,
            viewShowingHardLinksDelegate: self,
            cacheDelegate: cacheDelegate,
            delegate: self)
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
        viewDidLoadWasCalled = true
        view.backgroundColor = .systemBackground
        self.composeMessageView?.delegateViewController = self
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
        
        observeAppStateChanges()
        observePersistedDiscussionChanges()
        observePersistedObvContactIdentityChanges()
        observeRouteChange()
        registerForKeyboardNotifications()
        
        observeMessagesToReconfigure()
        observeDeletedFyleMessageJoinNotifications()
        
        observeTapsOnCollectionView()
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        registerForNotification()

        // This constraint was *not* set in viewDidLoad. We want to reset it every time the main view will appear
        // Otherwise, it seems that the constraint "desappears" each time another VC is presented over this one.
        // NOTE: replaced by myKeyboardLayoutGuide until Apple fixes the bug with keyboardLayoutGuide
        myKeyboardLayoutGuide.topAnchor.constraint(equalTo: composeMessageView!.bottomAnchor).isActive = true

        configureNewComposeMessageViewVisibility(animate: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewDidAppearWasCalled = true
        composeMessageView?.discussionViewDidAppear()
        configureTimerForRefreshingCellCountdowns()
                
        markNewVisibleReceivedAndRelevantSystemMessagesAsNotNew()
        insertSystemMessageIfCurrentDiscussionIsEmpty()
        
        performInitialScrollIfAppropriateAndRemoveHidingView()
        
        // This hack re-enables the compose message view in case it was prevented from editing
        if composeMessageView?.preventTextViewFromEditing == true {
            DispatchQueue.main.async { [weak self] in
                self?.composeMessageView?.endEditing(false)
                self?.composeMessageView?.preventTextViewFromEditing = false
            }
        }
    }
    
    
    private func performInitialScrollIfAppropriateAndRemoveHidingView() {
        assert(Thread.isMainThread)
        guard viewDidAppearWasCalled else { return }
        guard !initialScrollWasPerformed else { return }
        initialScrollWasPerformed = true
        let completion = { [weak self] in
            self?.scrollViewDidEndAutomaticScroll()
            UIView.animate(withDuration: 0.3) {
                self?.hidingView.alpha = 0
            } completion: { _ in
                self?.hidingView.isHidden = true
            }
        }
        switch initialScroll {
        case .specificMessage(let message):
            guard let indexPath = frc.indexPath(forObject: message) else { assertionFailure(); return }
            let completionAndAnimate = { [weak self] in
                completion()
                self?.animateItem(at: indexPath)
            }
            collectionView.adjustedScrollToItem(at: indexPath, at: .centeredVertically, completion: completionAndAnimate)
        case .newMessageSystemOrLastMessage:
            if let unreadMessagesSystemMessage = unreadMessagesSystemMessage {
                guard let indexPath = frc.indexPath(forObject: unreadMessagesSystemMessage) else { assertionFailure(); return }
                collectionView.adjustedScrollToItem(at: indexPath, at: .centeredVertically, completion: completion)
            } else {
                collectionView.adjustedScrollToBottom(completion: completion)
            }
        }
    }
    
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        composeMessageView?.discussionViewWillDisappear()
        invalidateTimerForRefreshingCellCountdowns()
        processReceivedMessagesThatBecameNotNewDuringScrolling()
        if self.filesViewer == nil {
            // If the user is swiping to dismiss while the text view is editing, this code dismisses the keyboard and prevents it re-appearing if the user changes its mind and swipe back. The text view is reactivated in viewWillAppear.
            composeMessageView?.animatedEndEditing(completion: { _ in })
            composeMessageView?.preventTextViewFromEditing = true
        }
    }
    

    private func registerForNotification() {
        guard !isRegisteredToNotifications else { return }
        isRegisteredToNotifications = true
        observationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeDiscussionLocalConfigurationHasBeenUpdated(queue: OperationQueue.main) { [weak self] value, objectId in
                guard let _self = self else { return }
                guard case .muteNotificationsDuration = value else { return }
                guard let discussion = try? PersistedDiscussion.get(objectID: _self.discussionObjectID, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
                guard discussion.localConfiguration.typedObjectID == objectId else { return }
                _self.configureNavigationTitle()
            },
            ObvMessengerCoreDataNotification.observePersistedContactGroupHasUpdatedContactIdentities(queue: OperationQueue.main) { [weak self] _,_,_ in
                self?.configureNewComposeMessageViewVisibility(animate: true)
            },
            ObvMessengerInternalNotification.observeCurrentUserActivityDidChange(queue: OperationQueue.main) { [weak self] (previousUserActivity, currentUserActivity) in
                // Check that this discussion was left by the user
                guard let _self = self else { return }
                guard _self.discussionObjectID == previousUserActivity.persistedDiscussionObjectID, _self.discussionObjectID != currentUserActivity.persistedDiscussionObjectID else { return }
                _self.theUserLeftTheDiscussion()
            },
            ObvMessengerCoreDataNotification.observePersistedContactIsActiveChanged(queue: OperationQueue.main) { [weak self] _ in
                self?.configureNewComposeMessageViewVisibility(animate: true)
            },
            ObvMessengerCoreDataNotification.observePersistedDiscussionStatusChanged(queue: OperationQueue.main) { [weak self] _ in
                self?.configureNewComposeMessageViewVisibility(animate: true)
            },
        ])
    }
    
    
    func addAttachmentFromAirDropFile(at fileURL: URL) {
        self.composeMessageView?.addAttachmentFromAirDropFile(at: fileURL)
    }
}




// MARK: - Initial setup and cell configuration

@available(iOS 15.0, *)
extension NewSingleDiscussionViewController {
    
    func configureNavigationTitle() {
        assert(Thread.isMainThread)
        guard let discussion = try? PersistedDiscussion.get(objectID: discussionObjectID, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
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
            case .none:
                break
            }
        }
        if navigationItem.titleView == nil {
            navigationItem.titleView = SingleDiscussionTitleView(title: discussion.title, subtitle: discussion.subtitle)
        }
        
        if discussion.status == .active {
            
            var items: [UIBarButtonItem] = []
            
            // Configure the menu for the right bar button item

            do {
                var menuElements: [UIMenuElement] = [
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
                if discussion.isCallAvailable, AppStateManager.shared.appType == .mainApp {
                    menuElements += [
                        UIAction(
                            title: CommonString.Word.Call,
                            image: UIImage(systemIcon: .phoneFill),
                            handler: { [weak self] _ in self?.callButtonTapped() }
                        )
                    ]
                }
                let menu = UIMenu(title: "", children: menuElements)
                let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
                let ellipsisImage = UIImage(systemIcon: .ellipsisCircle, withConfiguration: symbolConfiguration)
                let ellipsisButton = UIBarButtonItem(
                    title: nil,
                    image: ellipsisImage,
                    primaryAction: nil,
                    menu: menu)
                items += [ellipsisButton]
            }

            // Configure the unmute button if necessary (as a menu, with a primary action)

            if let muteNotificationEndDate = discussion.localConfiguration.currentMuteNotificationsEndDate {
                let unmuteDateFormatted = PersistedDiscussionLocalConfiguration.formatDateForMutedNotification(muteNotificationEndDate)
                let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
                let unmuteImage = UIImage(systemIcon: .moonZzzFill, withConfiguration: symbolConfiguration)
                let unmuteAction = UIAction.init(title: Strings.unmuteNotifications, image: UIImage(systemIcon: .moonZzzFill)) { _ in
                    ObvMessengerCoreDataNotification.userWantsToUpdateDiscussionLocalConfiguration(value: .muteNotificationsDuration(muteNotificationsDuration: nil), localConfigurationObjectID: discussion.localConfiguration.typedObjectID).postOnDispatchQueue()
                }
                let menuElements: [UIMenuElement] = [unmuteAction]
                let menu = UIMenu(title: Strings.mutedNotificationsConfirmation(unmuteDateFormatted), children: menuElements)
                let unmuteButton = UIBarButtonItem(
                    title: nil,
                    image: unmuteImage,
                    primaryAction: nil,
                    menu: menu)
                items += [unmuteButton]
            }

            navigationItem.rightBarButtonItems = items
        }
        
        navigationItem.titleView?.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(titleViewWasTapped)))

    }
    
    @objc private func titleViewWasTapped() {
        assert(delegate != nil)
        guard let discussion = try? PersistedDiscussion.get(objectID: discussionObjectID, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
        delegate?.userTappedTitleOfDiscussion(discussion)
    }
    
    func configureHierarchy() {
        
        collectionView = DiscussionCollectionView(frame: view.bounds, collectionViewLayout: createLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = AppTheme.shared.colorScheme.discussionScreenBackground
        view.addSubview(collectionView)
        collectionView.delegate = self
        collectionView.keyboardDismissMode = .interactive
        collectionView.alwaysBounceVertical = true
        collectionView.scrollsToTop = false
        collectionView.contentInsetAdjustmentBehavior = .automatic
        
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
        ])
        
        collectionView.prefetchDataSource = self
        
        configureComposeMessageViewHierarchy()
        
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
    }

    
    private func configureComposeMessageViewHierarchy() {
        
        // We configure the in-house layout guide and use it until Apple fixes the bug with the keyboardLayoutGuide.
        view.addLayoutGuide(myKeyboardLayoutGuide)
        
        NSLayoutConstraint.activate([
            myKeyboardLayoutGuide.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            myKeyboardLayoutGuide.widthAnchor.constraint(equalTo: view.widthAnchor),
        ])
        myKeyboardLayoutGuideHeightConstraint = myKeyboardLayoutGuide.heightAnchor.constraint(equalToConstant: view.safeAreaInsets.bottom)
        myKeyboardLayoutGuideHeightConstraint?.isActive = true
        
        backgroundEffectViewForComposeView = UIVisualEffectView()
        view.addSubview(backgroundEffectViewForComposeView)
        backgroundEffectViewForComposeView.translatesAutoresizingMaskIntoConstraints = false
        backgroundEffectViewForComposeView.effect = UIBlurEffect(style: .regular)

        view.addSubview(composeMessageView!)
        composeMessageView?.translatesAutoresizingMaskIntoConstraints = false

        // The bottomAnchor of the composeMessageView is pinned to the view's keyboardLayoutGuide in viewWillAppear.
        // In practice, this allows to reset this constraint after a new VC was presented or pushed over this one.
        NSLayoutConstraint.activate([
            composeMessageView!.widthAnchor.constraint(equalTo: view.widthAnchor),
            composeMessageView!.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundEffectViewForComposeView.topAnchor.constraint(equalTo: composeMessageView!.topAnchor),
            backgroundEffectViewForComposeView.trailingAnchor.constraint(equalTo: composeMessageView!.trailingAnchor),
            backgroundEffectViewForComposeView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backgroundEffectViewForComposeView.leadingAnchor.constraint(equalTo: composeMessageView!.leadingAnchor),
        ])
                
    }
    
    private func createLayout() -> UICollectionViewLayout {
        let layout = DiscussionLayout()
        return layout
    }


    private func configureDataSource() {
        
        let collectionView = self.collectionView!
        self.frc = PersistedMessage.getFetchedResultsControllerForAllMessagesWithinDiscussion(discussionObjectID: discussionObjectID, within: ObvStack.shared.viewContext)
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

        let headerRegistration = UICollectionView.SupplementaryRegistration<DateSupplementaryView>(elementKind: NewSingleDiscussionViewController.sectionHeaderElementKind) { [weak self] (dateSupplementaryView, string, indexPath) in
            self?.updateDateSupplementaryView(dateSupplementaryView, at: indexPath)
        }

        self.dataSource = UICollectionViewDiffableDataSource<Int, NSManagedObjectID>(collectionView: collectionView) { (collectionView: UICollectionView, indexPath: IndexPath, objectID: NSManagedObjectID) -> UICollectionViewCell? in
            guard let message = try? PersistedMessage.get(with: objectID, within: ObvStack.shared.viewContext) else { return nil }
            if let messageSent = message as? PersistedMessageSent {
                return collectionView.dequeueConfiguredReusableCell(using: sentMessageCellRegistration, for: indexPath, item: messageSent)
            } else if let messageReceived = message as? PersistedMessageReceived {
                return collectionView.dequeueConfiguredReusableCell(using: receivedMessageCellRegistration, for: indexPath, item: messageReceived)
            } else if let messageSystem = message as? PersistedMessageSystem {
                return collectionView.dequeueConfiguredReusableCell(using: systemMessageCellRegistration, for: indexPath, item: messageSystem)
            } else {
                return nil
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
            if discussionEntityName == PersistedGroupDiscussion.entityName {
                prvMessageIsFromSameContact = previousMessageIsFromSameContact(message: message)
            }
        }
        cell.updateWith(message: message, indexPath: indexPath, draftObjectID: draftObjectID, previousMessageIsFromSameContact: prvMessageIsFromSameContact, cacheDelegate: cacheDelegate, cellReconfigurator: self, textBubbleDelegate: self)
    }

    
    private func updateSentMessageCell(_ cell: SentMessageCell, at indexPath: IndexPath, with message: PersistedMessageSent) {
        cell.updateWith(message: message, indexPath: indexPath, draftObjectID: draftObjectID, cacheDelegate: cacheDelegate, cellReconfigurator: self, textBubbleDelegate: self)
    }
    
        
    private func getSectionTitle(at indexPath: IndexPath) -> String? {
        guard let sections = frc.sections else {
            fatalError("No sections in fetchedResultsController")
        }
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
        guard AppStateManager.shared.currentState.isInitializedAndActive else { return }
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
        guard let discussion = try? PersistedDiscussion.get(objectID: discussionObjectID, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
        switch try? discussion.kind {
        case .oneToOne(withContactIdentity: let contactIdentity):
            guard let contactID = contactIdentity?.typedObjectID else { return }
            ObvMessengerInternalNotification.userWantsToCallButWeShouldCheckSheIsAllowedTo(contactIDs: [contactID], groupId: nil)
                .postOnDispatchQueue(internalQueue)
        case .groupV1(withContactGroup: let contactGroup):
            if let contactGroup = contactGroup,
               let groupId = try? contactGroup.getGroupId() {
                let contactIdentities = contactGroup.contactIdentities
                ObvMessengerInternalNotification.userWantsToSelectAndCallContacts(contactIDs: contactIdentities.map({ $0.typedObjectID }), groupId: groupId)
                    .postOnDispatchQueue(internalQueue)
            }
        case .none:
            assertionFailure()
        }
    }

    
    private func observeAppStateChanges() {
        observationTokens.append(ObvMessengerInternalNotification.observeAppStateChanged(queue: OperationQueue.main) { [weak self] (previousState, currentState) in
            debugPrint("🍆 \(previousState.iOSAppState.debugDescription) --> \(currentState.iOSAppState.debugDescription)")
            guard currentState.isInitialized else { return }
            if currentState.iOSAppState == .active, self?.cellsShowingCallLogItemRejectedIncomingCallBecauseOfDeniedRecordPermissionNeedToBeReconfigured ?? false {
                self?.reconfigureCellsShowingCallLogItemRejectedIncomingCallBecauseOfDeniedRecordPermission()
            }
            switch (previousState.iOSAppState, currentState.iOSAppState) {
            case (.active, .notActive),
                 (.mayResignActive, .inBackground):
                guard ObvUserActivitySingleton.shared.currentPersistedDiscussionObjectID == self?.discussionObjectID else { return }
                self?.theUserLeftTheDiscussion()
            default:
                break
            }
        })
    }

    // Refresh the discussion title if it is updated
    private func observePersistedDiscussionChanges() {
        let notification = NSNotification.Name.NSManagedObjectContextObjectsDidChange
        observationTokens.append(NotificationCenter.default.addObserver(forName: notification, object: nil, queue: OperationQueue.main) { [weak self] notification in
            guard let _self = self else { return }
            guard _self.viewDidAppearWasCalled else { return }
            guard (notification.object as? NSManagedObjectContext) == ObvStack.shared.viewContext else { return }
            guard let refreshedObject = notification.userInfo?[NSRefreshedObjectsKey] as? Set<NSManagedObject> else { return }

            /// Computes the set of refreshed discussions
            let currentDiscussionDidChange = refreshedObject
                .compactMap({ $0 as? PersistedDiscussion })
                .map({ $0.typedObjectID })
                .contains(where: { $0 == _self.discussionObjectID })

            if currentDiscussionDidChange {
                self?.configureNavigationTitle()
            }
        })
    }


    private func observePersistedObvContactIdentityChanges() {
        let notification = NSNotification.Name.NSManagedObjectContextObjectsDidChange
        observationTokens.append(NotificationCenter.default.addObserver(forName: notification, object: nil, queue: OperationQueue.main) { [weak self] notification in
            guard let _self = self else { return }
            guard _self.viewDidAppearWasCalled else { return }
            guard (notification.object as? NSManagedObjectContext) == ObvStack.shared.viewContext else { return }
            guard let refreshedObject = notification.userInfo?[NSRefreshedObjectsKey] as? Set<NSManagedObject> else { return }
            let refreshedContactObject = refreshedObject
                .compactMap({ $0 as? PersistedObvContactIdentity })

            /// Computes the set of contact groups where at least one contact has been refreshed and check whether the current discussion is one of the discussions associated to those group

            if refreshedContactObject
                .flatMap({ $0.contactGroups })
                .contains(where: { $0.discussion.typedObjectID.downcast == _self.discussionObjectID }) {
                /// If the current discussion has changed, reconfigure the title
                self?.configureNavigationTitle()

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
                .contains(where: { $0.typedObjectID.downcast == _self.discussionObjectID }) {
                /// If the current discussion has changed, reconfigure the title
                self?.configureNavigationTitle()
            }
        })
    }

    private func observeRouteChange() {
        observationTokens.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: OperationQueue.main) { [weak self] _ in
            self?.collectionView?.visibleCells.forEach { cell in
                guard let audioPlayerView = cell.deepSearchSubView(ofClass: AudioPlayerView.self) else { return }
                audioPlayerView.configureSpeakerButton()
            }
        })
    }

    
    private func insertSystemMessageIfCurrentDiscussionIsEmpty() {
        guard let discussion = try? PersistedDiscussion.get(objectID: discussionObjectID, within: ObvStack.shared.viewContext) else { return }
        guard discussion.messages.isEmpty else { return }
        NewSingleDiscussionNotification.insertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty(discussionObjectID: discussion.typedObjectID, markAsRead: true)
            .postOnDispatchQueue(internalQueue)
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
            self.dataSource.apply(snapshot, animatingDifferences: true) { [weak self] in
                self?.cellsShowingCallLogItemRejectedIncomingCallBecauseOfDeniedRecordPermissionNeedToBeReconfigured = false
            }
        }
    }

}




// MARK: - NSFetchedResultsControllerDelegate

@available(iOS 15.0, *)
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
        
        debugPrint("😤💿 Is initialized and active is \(AppStateManager.shared.currentState.isInitializedAndActive)")
        
        AppStateManager.shared.addCompletionHandlerToExecuteWhenInitializedAndActive { [weak self] in
            
            self?.queueForApplyingSnapshots.async {
                
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
            
        }
        
    }

}


// MARK: - CellReconfigurator

@available(iOS 15.0, *)
extension NewSingleDiscussionViewController {
    
    /// Called exactly once, from viewDidLoad
    private func observeMessagesToReconfigure() {
        cancellables.append(
            $messagesToReconfigure
                .filter { !$0.isEmpty }
                .removeDuplicates()
                .debounce(for: 0.3, scheduler: RunLoop.main)
                .map { [weak self] messageObjectIDs -> [NSManagedObjectID] in
                    assert(Thread.isMainThread)
                    self?.messagesToReconfigure.removeAll()
                    return messageObjectIDs.map { $0.objectID }
                }
                .receive(on: queueForApplyingSnapshots)
                .sink { [weak self] objectIDs in
                    guard var snapshot = self?.dataSource.snapshot() else { return }
                    snapshot.reconfigureItems(objectIDs)
                    self?.dataSource.apply(snapshot, animatingDifferences: false)
                }
        )
    }
    
    
    func cellNeedsToBeReconfiguredAndResized(messageID: TypeSafeManagedObjectID<PersistedMessage>) {
        assert(Thread.isMainThread)
        guard viewDidAppearWasCalled else { return }
        messagesToReconfigure.insert(messageID)
    }
    
    
}


// MARK: - Managing the "new messages" system message

@available(iOS 15.0, *)
extension NewSingleDiscussionViewController {

    /// This method is called once, during init, to compute the initial value of the `objectIDsOfMessagesToConsiderInNewMessagesCell` set.
    private func computeInitialValueOfObjectIDsOfMessagesToConsiderInNewMessagesCell() throws {
        guard let discussion = try PersistedDiscussion.get(objectID: discussionObjectID, within: ObvStack.shared.viewContext) else {
            throw makeError(message: "Could not find discussion")
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
            guard let discussion = try PersistedDiscussion.get(objectID: discussionObjectID, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
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
        observationTokens.append(NotificationCenter.default.addObserver(forName: notification, object: nil, queue: OperationQueue.main) { [weak self] notification in
            guard let _self = self else { return }
            guard _self.viewDidAppearWasCalled else { return }
            guard !_self.objectIDsOfMessagesToConsiderInNewMessagesCell.isEmpty else { return }
            guard (notification.object as? NSManagedObjectContext) == ObvStack.shared.viewContext else { return }
            guard let insertedObjects = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> else { return }
            let newSentMessages = insertedObjects
                .compactMap({ $0 as? PersistedMessageSent })
                .filter({ $0.discussion.typedObjectID == _self.discussionObjectID })
            guard !newSentMessages.isEmpty else { return }
            _self.objectIDsOfMessagesToConsiderInNewMessagesCell.removeAll()
            // We asynchronously call `insertOrUpdateSystemMessageCountingNewMessages`.
            // This ensures that we do not include an item deletion (the system message) as well as an item insertion (the new sent message) in the diffable datasource snapshot. In theory, this should work. In practice, the animations look ugly. Forcing two distinct snapshots (the first for the sent message inserting, the second for the deletion of the system message counting new messages) results in nice looking animations. Yes, this is a hack.
            DispatchQueue.main.async {
                _self.insertOrUpdateSystemMessageCountingNewMessages(removeExisting: false)
            }
        })
    }

    
    /// We observe insertion of received messages so as to update the system message cell counting new messages.
    private func updateNewMessageCellOnInsertionOfReceivedMessages() {
        let notification = NSNotification.Name.NSManagedObjectContextObjectsDidChange
        observationTokens.append(NotificationCenter.default.addObserver(forName: notification, object: nil, queue: OperationQueue.main) { [weak self] notification in
            guard let _self = self else { return }
            guard _self.viewDidAppearWasCalled else { return }
            guard (notification.object as? NSManagedObjectContext) == ObvStack.shared.viewContext else { return }
            guard let insertedObjects = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> else { return }
            let insertedReceivedMessages = insertedObjects
                .compactMap({ $0 as? PersistedMessageReceived })
                .filter({ $0.discussion.typedObjectID == _self.discussionObjectID })
            let objectIDsOfInsertedReceivedMessages = Set(insertedReceivedMessages.map({ $0.typedObjectID.downcast }))
            guard !objectIDsOfInsertedReceivedMessages.isSubset(of: _self.objectIDsOfMessagesToConsiderInNewMessagesCell) else { return }
            _self.objectIDsOfMessagesToConsiderInNewMessagesCell.formUnion(objectIDsOfInsertedReceivedMessages)
            _self.insertOrUpdateSystemMessageCountingNewMessages(removeExisting: false)
        })
    }
    
    
    /// We observe insertion of relevant system messages so as to update the system message cell counting new messages.
    private func updateNewMessageCellOnInsertionOfRelevantSystemMessages() {
        let notification = NSNotification.Name.NSManagedObjectContextObjectsDidChange
        observationTokens.append(NotificationCenter.default.addObserver(forName: notification, object: nil, queue: OperationQueue.main) { [weak self] notification in
            guard let _self = self else { return }
            guard _self.viewDidAppearWasCalled else { return }
            guard (notification.object as? NSManagedObjectContext) == ObvStack.shared.viewContext else { return }
            guard let insertedObjects = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> else { return }
            let insertedSystemMessages = insertedObjects
                .compactMap({ $0 as? PersistedMessageSystem })
                .filter({ $0.discussion.typedObjectID == _self.discussionObjectID })
            let insertedRelevantSystemMessages = insertedSystemMessages
                .filter({ $0.isRelevantForCountingUnread })
                .filter({ $0.optionalContactIdentity != nil })
            let objectIDsOfInsertedRelevantSystemMessages = Set(insertedRelevantSystemMessages.map({ $0.typedObjectID.downcast }))
            guard !objectIDsOfInsertedRelevantSystemMessages.isSubset(of: _self.objectIDsOfMessagesToConsiderInNewMessagesCell) else { return }
            _self.objectIDsOfMessagesToConsiderInNewMessagesCell.formUnion(objectIDsOfInsertedRelevantSystemMessages)
            _self.insertOrUpdateSystemMessageCountingNewMessages(removeExisting: false)
        })
    }

    /// We observe deletion of received messages so as to update the system message cell counting new messages.
    private func updateNewMessageCellOnDeletionOfReceivedMessages() {
        observationTokens.append(ObvMessengerInternalNotification.observePersistedMessageReceivedWasDeleted(queue: OperationQueue.main) { [weak self] (objectID, _, _, _, discussionObjectID) in
            guard let _self = self else { return }
            guard discussionObjectID == _self.discussionObjectID else { return }
            let messageObjectID = TypeSafeManagedObjectID<PersistedMessage>(objectID: objectID)
            guard _self.objectIDsOfMessagesToConsiderInNewMessagesCell.contains(messageObjectID) else { return }
            _self.objectIDsOfMessagesToConsiderInNewMessagesCell.remove(messageObjectID)
            _self.insertOrUpdateSystemMessageCountingNewMessages(removeExisting: false)
        })
    }
    
    
    /// We observe deletion of system messages so as to update the system message cell counting new messages if appropriate.
    private func updateNewMessageCellOnDeletionOfRelevantSystemMessages() {
        observationTokens.append(ObvMessengerCoreDataNotification.observePersistedMessageSystemWasDeleted(queue: OperationQueue.main) { [weak self] (objectID, discussionObjectID) in
            guard let _self = self else { return }
            guard discussionObjectID == _self.discussionObjectID else { return }
            let messageObjectID = TypeSafeManagedObjectID<PersistedMessage>(objectID: objectID)
            guard _self.objectIDsOfMessagesToConsiderInNewMessagesCell.contains(messageObjectID) else { return }
            _self.objectIDsOfMessagesToConsiderInNewMessagesCell.remove(messageObjectID)
            _self.insertOrUpdateSystemMessageCountingNewMessages(removeExisting: false)
        })
    }

}


// MARK: - Marking messages as "not new"

@available(iOS 15.0, *)
extension NewSingleDiscussionViewController {
    
    private func theUserLeftTheDiscussion() {
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
                    hidingView.alpha = 1
                    hidingView.isHidden = false
                }
            }
        }

    }
    
    
    /// This method sends a notification allowing the database to mark the message as not new (which will eventually send read receipt if this setting is set)
    private func markAsNotNewTheMessageInCell(_ cell: UICollectionViewCell) {
        guard AppStateManager.shared.currentState.isInitialized else { return }
        guard ObvUserActivitySingleton.shared.currentPersistedDiscussionObjectID == discussionObjectID else { return }
        guard viewDidAppearWasCalled else { return }
        let messageObjectId: TypeSafeManagedObjectID<PersistedMessage>
        if let receivedCell = cell as? ReceivedMessageCell, let receivedMessage = receivedCell.message, receivedMessage.status == .new {
            messageObjectId = receivedMessage.typedObjectID.downcast
        } else if let systemCell = cell as? SystemMessageCell, let systemMessage = systemCell.message, systemMessage.status == .new {
            if systemMessage.isRelevantForCountingUnread {
                messageObjectId = systemMessage.typedObjectID.downcast
            } else {
                return
            }
        } else {
            return
        }
        
        // If the app is no active yet, we wait until it is before sending the `messagesAreNotNewAnymore` notification.
        
        guard AppStateManager.shared.currentState.isInitializedAndActive else {
            AppStateManager.shared.addCompletionHandlerToExecuteWhenInitializedAndActive {
                ObvDisplayableLogs.shared.log("[NewSingleDiscussionViewController] Posting messagesAreNotNewAnymore notification in markAsNotNewTheMessageInCell for \([messageObjectId].count) messages (after waiting for the active state)")
                ObvMessengerInternalNotification.messagesAreNotNewAnymore(persistedMessageObjectIDs: [messageObjectId])
                    .postOnDispatchQueue()
            }
            return
        }
        
        // If we are currently scrolling, we do *not* notify that a message has been read.
        // This would introduce animation glitches. Instead, we postpone the notification
        if currentScrolling == .none {
            ObvDisplayableLogs.shared.log("[NewSingleDiscussionViewController] Posting messagesAreNotNewAnymore notification in markAsNotNewTheMessageInCell for \([messageObjectId].count) messages")
            ObvMessengerInternalNotification.messagesAreNotNewAnymore(persistedMessageObjectIDs: [messageObjectId])
                .postOnDispatchQueue()
        } else {
            ObvDisplayableLogs.shared.log("[NewSingleDiscussionViewController] As currentScrolling is \(currentScrolling.debugDescription), we do not post messagesAreNotNewAnymore notification for \([messageObjectId].count) messages")
            messagesToMarkAsNotNewWhenScrollingEnds.insert(messageObjectId)
        }
    }

    
    /// Marks all new received and relevant system messages that are visible as "not new"
    private func markNewVisibleReceivedAndRelevantSystemMessagesAsNotNew() {

        ObvDisplayableLogs.shared.log("[NewSingleDiscussionViewController] Call to markNewVisibleReceivedAndRelevantSystemMessagesAsNotNew. AppStateManager.shared.currentState.isInitializedAndActive: \(AppStateManager.shared.currentState.isInitializedAndActive)")
        
        let visibleReceivedCells = collectionView.visibleCells.compactMap({ $0 as? ReceivedMessageCell })
        let visibleSystemCells = collectionView.visibleCells.compactMap({ $0 as? SystemMessageCell })

        let visibleNewReceivedMessages = visibleReceivedCells.compactMap({ $0.message }).filter({ $0.status == .new })
        let visibleNewSystemMessages = visibleSystemCells.compactMap({ $0.message }).filter({ $0.status == .new })

        let objectIDsOfNewVisibleReceivedMessages = Set(visibleNewReceivedMessages.map({ $0.typedObjectID.downcast }))
        let objectIDsOfNewVisibleSystemMessages = Set(visibleNewSystemMessages.map({ $0.typedObjectID.downcast }))

        let objectIDsOfNewVisibleMessages = objectIDsOfNewVisibleReceivedMessages.union(objectIDsOfNewVisibleSystemMessages)

        ObvDisplayableLogs.shared.log("[NewSingleDiscussionViewController] Posting messagesAreNotNewAnymore notification in markNewVisibleReceivedAndRelevantSystemMessagesAsNotNew for \(objectIDsOfNewVisibleMessages.count) messages")

        ObvMessengerInternalNotification.messagesAreNotNewAnymore(persistedMessageObjectIDs: objectIDsOfNewVisibleMessages)
            .postOnDispatchQueue(internalQueue)

    }
    
}



// MARK: - UIScrollViewDelegate / Managing automatic scroll to bottom

@available(iOS 15.0, *)
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
            (collectionView.collectionViewLayout as? DiscussionLayout)?.currentlyScrollingManually = false
        case .automatically:
            (collectionView.collectionViewLayout as? DiscussionLayout)?.currentlyScrollingManually = false
        case .manually:
            self.lastScrollWasManual = true
            (collectionView.collectionViewLayout as? DiscussionLayout)?.currentlyScrollingManually = true
        }
    }
    
    
    /// This method evaluate if we should automatically scroll the next time a message is received.
    /// To do so, we check whether the content offset (scrolling position) is close enough to the bottom. In that case,
    /// we set `shouldScrollOnNewReceivedMessage` to `true` but only if we are not currently scrolling manually.
    private func evaluateIfScrollOnNewIncomingMessageShouldBeActive() {
        let distanceFromBottom = max(0, collectionView.contentSize.height + collectionView.adjustedContentInset.bottom - (collectionView.contentOffset.y + collectionView.frame.size.height))
        if distanceFromBottom < 1.0 {
            self.lastScrollWasManual = (currentScrolling == .manually)
        }
    }

    
    private func processReceivedMessagesThatBecameNotNewDuringScrolling() {
        guard !messagesToMarkAsNotNewWhenScrollingEnds.isEmpty else { return }
        guard currentScrolling == .none else { return }
        ObvDisplayableLogs.shared.log("[NewSingleDiscussionViewController] Posting messagesAreNotNewAnymore notification in processReceivedMessagesThatBecameNotNewDuringScrolling for \(messagesToMarkAsNotNewWhenScrollingEnds.count) messages")
        ObvMessengerInternalNotification.messagesAreNotNewAnymore(persistedMessageObjectIDs: messagesToMarkAsNotNewWhenScrollingEnds)
            .postOnDispatchQueue(internalQueue)
        messagesToMarkAsNotNewWhenScrollingEnds.removeAll()
    }
    
}




// MARK: - UICollectionViewDelegate

@available(iOS 15.0, *)
extension NewSingleDiscussionViewController {
    
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        markAsNotNewTheMessageInCell(cell)
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        markAsNotNewTheMessageInCell(cell)
    }
    
}


// MARK: - UIContextMenuConfiguration

@available(iOS 15.0, *)
extension NewSingleDiscussionViewController {
    
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {

        guard let cell = collectionView.cellForItem(at: indexPath) as? CellWithMessage else { return nil }
        
        let actionProvider = makeActionProvider(for: cell)
        
        let menuConfiguration = UIContextMenuConfiguration(indexPath: indexPath,
                                                           previewProvider: nil,
                                                           actionProvider: actionProvider)
        
        return menuConfiguration
    }

    
    private func makeActionProvider(for cell: CellWithMessage) -> (([UIMenuElement]) -> UIMenu?) {
        return { (suggestedActions) in

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
                        self?.present(uiActivityVC, animated: true)
                    }
                    action.image = UIImage(systemIcon: .squareAndArrowUp)
                    children.append(action)
                }

                // Share all attachments (photos and other) at once
                if let itemProvidersForAllAttachments = cell.itemProvidersForAllAttachments, !itemProvidersForAllAttachments.isEmpty, cell.itemProvidersForImages?.count != itemProvidersForAllAttachments.count {
                    let action = UIAction(title: Strings.shareAttachments(itemProvidersForAllAttachments.count)) { [weak self] (_) in
                        let uiActivityVC = UIActivityViewController(activityItems: itemProvidersForAllAttachments, applicationActivities: nil)
                        uiActivityVC.popoverPresentationController?.sourceView = cell
                        self?.present(uiActivityVC, animated: true)
                    }
                    action.image = UIImage(systemIcon: .squareAndArrowUp)
                    children.append(action)
                }
            }
            
            // Reply to message action
            if let draftObjectID = cell.persistedDraftObjectID, persistedMessage.replyToActionCanBeMadeAvailable {
                let action = UIAction(title: CommonString.Word.Reply) { [weak self] _ in
                    guard let _self = self else { return }
                    NewSingleDiscussionNotification.userWantsToReplyToMessage(messageObjectID: persistedMessageObjectID, draftObjectID: draftObjectID)
                        .postOnDispatchQueue(_self.internalQueue)
                }
                action.image = UIImage(systemIcon: .arrowshapeTurnUpLeft2)
                children.append(action)
            }

            // Edit message action
            if persistedMessage.editBodyActionCanBeMadeAvailable {
                let action = UIAction(title: CommonString.Word.Edit) { [weak self] (_) in
                    let sentMessageObjectID = persistedMessage.objectID
                    let currentTextBody = persistedMessage.textBody
                    let vc = BodyEditViewController(currentBody: currentTextBody) { [weak self] in
                        self?.presentedViewController?.dismiss(animated: true)
                    } send: { [weak self] (newTextBody) in
                        guard let _self = self else { return }
                        self?.presentedViewController?.dismiss(animated: true, completion: {
                            guard newTextBody != currentTextBody else { return }
                            ObvMessengerInternalNotification.userWantsToSendEditedVersionOfSentMessage(sentMessageObjectID: sentMessageObjectID,
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
                    guard let ownedCryptoId = persistedMessage.discussion.ownedIdentity?.cryptoId else { return }
                    let vc = DiscussionsViewController(ownedCryptoId: ownedCryptoId) { discussionObjectIDs in
                        ObvMessengerInternalNotification.userWantsToForwardMessage(messageObjectID: persistedMessage.typedObjectID, discussionObjectIDs: discussionObjectIDs).postOnDispatchQueue()
                    }
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
                    let groupId = try? item.getGroupId()

                    var contactsToCall = [TypeSafeManagedObjectID<PersistedObvContactIdentity>]()
                    for logContact in item.logContacts {
                        guard let contactIdentity = logContact.contactIdentity else { continue }
                        contactsToCall.append(contactIdentity.typedObjectID)
                    }

                    if contactsToCall.count == 1 {
                        ObvMessengerInternalNotification.userWantsToCallButWeShouldCheckSheIsAllowedTo(contactIDs: contactsToCall, groupId: groupId).postOnDispatchQueue()
                    } else {
                        ObvMessengerInternalNotification.userWantsToSelectAndCallContacts(contactIDs: contactsToCall, groupId: groupId).postOnDispatchQueue()
                    }
                }
                action.image = UIImage(systemIcon: .phoneFill)
                children.append(action)
            }

            // Delete reaction action
            if persistedMessage.deleteOwnReactionActionCanBeMadeAvailable {
                let action = UIAction(title: CommonString.Title.deleteOwnReaction) { (_) in
                    guard let messageID = cell.persistedMessageObjectID else { return }
                    ObvMessengerInternalNotification.userWantsToUpdateReaction(messageObjectID: messageID, emoji: nil).postOnDispatchQueue()
                }
                action.image = UIImage(systemIcon: .heartSlashFill)
                children.append(action)
            }

            // Delete message action
            if persistedMessage.deleteMessageActionCanBeMadeAvailable {
                let action = UIAction(title: CommonString.Word.Delete) { [weak self] (_) in
                    self?.deletePersistedMessage(objectId: persistedMessageObjectID.objectID, confirmedDeletionType: nil, withinCell: cell)
                }
                action.image = UIImage(systemIcon: .trash)
                action.attributes = [.destructive]
                children.append(action)
            }

            
            return UIMenu(title: "", image: nil, identifier: nil, options: .displayInline, children: children)
        }
    }

    
    private func deletePersistedMessage(objectId: NSManagedObjectID, confirmedDeletionType: DeletionType?, withinCell cell: CellWithMessage) {
        
        assert(Thread.isMainThread)
        
        switch confirmedDeletionType {
        
        case .none:
            
            guard let persistedMessage = try? PersistedMessage.get(with: objectId, within: ObvStack.shared.viewContext) else { return }
            guard persistedMessage.discussion.typedObjectID == self.discussionObjectID else { return }
            
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
            
            alert.addAction(UIAlertAction(title: CommonString.AlertButton.performDeletionAction, style: .default, handler: { [weak self] (action) in
                self?.deletePersistedMessage(objectId: objectId, confirmedDeletionType: .local, withinCell: cell)
            }))
            
            if !persistedMessage.isRemoteWiped && (persistedMessage is PersistedMessageSent || persistedMessage is PersistedMessageReceived) {
                alert.addAction(UIAlertAction(title: CommonString.AlertButton.performGlobalDeletionAction, style: .destructive, handler: { [weak self] (action) in
                    self?.deletePersistedMessage(objectId: objectId, confirmedDeletionType: .global, withinCell: cell)
                }))
            }
                        
            alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))

            alert.popoverPresentationController?.sourceView = cell.viewForTargetedPreview
            present(alert, animated: true, completion: nil)
            
        case .some(let deletionType):
            
            ObvMessengerInternalNotification.userRequestedDeletionOfPersistedMessage(persistedMessageObjectID: objectId, deletionType: deletionType)
                .postOnDispatchQueue(internalQueue)

        }
        
    }

}


// MARK: - Utils

@available(iOS 15.0, *)
extension NewSingleDiscussionViewController {
    
    private func simpleScrollToBottom() {
        guard let lastIndexPath = collectionView.lastIndexPath else { return }
        currentScrolling = .automatically
        collectionView.scrollToItem(at: lastIndexPath, at: .bottom, animated: true)
        currentScrolling = .none
    }

    private func scrollToItemAtIndexPath(_ indexPath: IndexPath) {
        let animationValues = defaultAnimationValues
        guard let collectionView = self.collectionView else { return }

        UIView.animate(withDuration: animationValues.duration, delay: 0.0, options: animationValues.options) {
            collectionView.adjustedScrollToItem(at: indexPath, at: .centeredVertically, completion: {})
        } completion: { _ in
            UIView.animate(withDuration: animationValues.duration, delay: 0.0, options: animationValues.options) {
                collectionView.adjustedScrollToItem(at: indexPath, at: .centeredVertically, completion: {})
            } completion: { _ in
                guard let cell = collectionView.cellForItem(at: indexPath) else { return }
                UIView.animateKeyframes(withDuration: 0.5, delay: 0.2, options: []) {
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
        guard let previousMessage = frc.object(at: previousIndexPath) as? PersistedMessageReceived else { return false }
        return message.contactIdentity == previousMessage.contactIdentity
    }
    
    
}



// MARK: - NewComposeMessageViewDelegate for handling the scroll

@available(iOS 15.0, *)
extension NewSingleDiscussionViewController {
    
    func newComposeMessageView(_ newComposeMessageView: NewComposeMessageView, newFrame frame: CGRect) {

        guard viewDidLoadWasCalled else { return }
        guard !newComposeMessageView.preventTextViewFromEditing else { return }
        
        let bottom: CGFloat
        if newComposeMessageView.isHidden {
            bottom = view.keyboardLayoutGuide.layoutFrame.height - view.safeAreaInsets.bottom
        } else {
            bottom = frame.height + myKeyboardLayoutGuideHeightConstraint!.constant - view.safeAreaInsets.bottom
        }
        guard collectionView.contentInset.bottom != bottom else { return }
        
        let currentHeightBelowContent = max(0, collectionView.bounds.height - collectionView.adjustedContentInset.bottom - collectionView.adjustedContentInset.top - collectionView.contentSize.height)
        let amountToScroll = max(0, bottom - collectionView.contentInset.bottom - currentHeightBelowContent)

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

        // Scroll if required
        
        collectionView.contentOffset = CGPoint(x: collectionView.contentOffset.x, y: collectionView.contentOffset.y + amountToScroll)
        scrollViewDidEndAutomaticScroll()

    }
    
    
    private func registerForKeyboardNotifications() {
        guard !isRegisteredToKeyboardNotifications else { return }
        defer { isRegisteredToKeyboardNotifications = true }
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidHideOrShow(_:)), name: UIResponder.keyboardDidHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidHideOrShow(_:)), name: UIResponder.keyboardDidShowNotification, object: nil)
        
        // This observers updates the in-house keyboard layout guide. It will be removed as soon as Apple's keyboardLayoutGuide works as expected
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShowOrHide(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShowOrHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    
    @objc private func keyboardDidHideOrShow(_ notification: Notification) {
        guard composeMessageView?.preventTextViewFromEditing == false else { return }
        composeMessageView?.setNeedsLayout()
        UIView.animate(withDuration: 0.3) { [weak self] in
            self?.composeMessageView?.layoutIfNeeded()
        }
    }

    
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
            self?.myKeyboardLayoutGuideHeightConstraint?.constant = offset
            self?.view.layoutIfNeeded()
        }
    }
    
}


// MARK: - Compose view visibility

@available(iOS 15.0, *)
extension NewSingleDiscussionViewController {

    private func configureNewComposeMessageViewVisibility(animate: Bool) {
        assert(Thread.isMainThread)
        guard let composeMessageView = self.composeMessageView else { assertionFailure(); return }
        guard let backgroundEffectViewForComposeView = self.backgroundEffectViewForComposeView else { assertionFailure(); return }
        let shouldHideNewComposeMessageView = self.shouldHideNewComposeMessageView
        guard composeMessageView.isHidden != shouldHideNewComposeMessageView || backgroundEffectViewForComposeView.isHidden != shouldHideNewComposeMessageView else { return }
        composeMessageView.setNeedsLayout()
        UIView.animate(withDuration: animate ? 0.3 : 0.0) { [weak self] in
            self?.composeMessageView?.isHidden = shouldHideNewComposeMessageView
            backgroundEffectViewForComposeView.isHidden = shouldHideNewComposeMessageView
        } completion: { [weak self] _ in
            self?.composeMessageView?.layoutIfNeeded()
        }
    }
 
    
    private var shouldHideNewComposeMessageView: Bool {
        assert(Thread.isMainThread)
        do {
            guard let discussion = try PersistedDiscussion.get(objectID: discussionObjectID, within: ObvStack.shared.viewContext) else {
                return true
            }
            // We do not show the compose view for locked discussions
            switch discussion.status {
            case .preDiscussion, .locked:
                return true
            case .active:
                break
            }
            switch try? discussion.kind {
            case .oneToOne(withContactIdentity: let contactIdentity):
                // We do not show the compose view for a one-to-one discussion with a contact s.t. isActive == false
                if contactIdentity?.isActive != true {
                    return true
                }
            case .groupV1(withContactGroup: let contactGroup):
                // We do no not show the compose view if we have no one to write to in a group discussion
                guard let contactGroup = contactGroup else { assertionFailure(); return true }
                if !contactGroup.hasAtLeastOneRemoteContactDevice() {
                    return true
                }
            case .none:
                assertionFailure()
            }
        } catch {
            assertionFailure(error.localizedDescription)
            return true
        }
        return false
    }

}



// MARK: - Localization

@available(iOS 15.0, *)
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

@available(iOS 15.0, *)
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
        guard cell is ReceivedMessageCell || cell is SentMessageCell else { return }
        guard let cellWithMessage = cell as? CellWithMessage else { return }
        guard let messageID = cellWithMessage.persistedMessageObjectID else { return }
        userDoubleTappedOnMessage(messageID: messageID)
        
    }
    
    
    private func tapPerformedOn(_ viewWithTappableStuff: UIViewWithTappableStuff, tapGestureRecognizer: UITapGestureRecognizer) {
        guard let tappedStuff = viewWithTappableStuff.tappedStuff(tapGestureRecognizer: tapGestureRecognizer) else { return }
        switch tappedStuff {
            
        case .hardlink(let hardLink):
            userDidTapOnFyleMessageJoinWithHardLink(hardlinkTapped: hardLink)
            
        case .messageThatRequiresUserAction(messageObjectID: let messageObjectID):
            ObvMessengerInternalNotification.userWantsToReadReceivedMessagesThatRequiresUserAction(persistedMessageObjectIDs: Set([messageObjectID]))
                .postOnDispatchQueue()
            
        case .receivedFyleMessageJoinWithStatusToResumeDownload(receivedJoinObjectID: let receivedJoinObjectID):
            NewSingleDiscussionNotification.userWantsToDownloadReceivedFyleMessageJoinWithStatus(receivedJoinObjectID: receivedJoinObjectID).postOnDispatchQueue()
            
        case .receivedFyleMessageJoinWithStatusToPauseDownload(receivedJoinObjectID: let receivedJoinObjectID):
            NewSingleDiscussionNotification.userWantsToPauseDownloadReceivedFyleMessageJoinWithStatus(receivedJoinObjectID: receivedJoinObjectID).postOnDispatchQueue()
            
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
        composeMessageView?.animatedEndEditing { [weak self] _ in
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
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] (granted) in
                guard AppStateManager.shared.currentState.isInitializedAndActive else {
                    self?.cellsShowingCallLogItemRejectedIncomingCallBecauseOfDeniedRecordPermissionNeedToBeReconfigured = true
                    return
                }
                self?.reconfigureCellsShowingCallLogItemRejectedIncomingCallBecauseOfDeniedRecordPermission()
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
        guard let message = try? PersistedMessage.get(with: messageID, within: ObvStack.shared.viewContext) else { return }
        guard !message.isWiped else { return }
        var selectedEmoji: String?
        if let ownReaction = message.reactionFromOwnedIdentity() {
            selectedEmoji = ownReaction.emoji
        }
        let model = EmojiPickerViewModel(selectedEmoji: selectedEmoji) { emoji in
            ObvMessengerInternalNotification.userWantsToUpdateReaction(messageObjectID: messageID, emoji: emoji).postOnDispatchQueue()
        }
        let vc = EmojiPickerHostingViewController(model: model)
        if let sheet = vc.sheetPresentationController {
            sheet.detents = [ .medium() ]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 30.0
        }
        present(vc, animated: true)
    }

    
    private func userTappedOnReactionView(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>) {
        guard let message = try? PersistedMessage.get(with: messageObjectID, within: ObvStack.shared.viewContext) else { return }

        guard let vc = MessageReactionsListHostingViewController(message: message) else {
            assertionFailure()
            return
        }
        if let sheet = vc.sheetPresentationController {
            sheet.detents = [ .medium(), .large() ]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 30.0
        }
        present(vc, animated: true)
    }

    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Don't recognize the single tap on cell until the double-tap on cell fails
        return gestureRecognizer == self.singleTapOnCell && otherGestureRecognizer == self.doubleTapOnCell
    }

}

// MARK: - ViewShowingHardLinksDelegate / CustomQLPreviewControllerDelegate / Previewing attachments

@available(iOS 15.0, *)
extension NewSingleDiscussionViewController {
    
    func userDidTapOnDraftFyleJoinWithHardLink(at indexPath: IndexPath) {
        guard let frc = composeMessageView?.attachmentsCollectionViewController.frc else { assertionFailure(); return }
        filesViewer = FilesViewer(frc: frc, qlPreviewControllerDelegate: self)
        composeMessageView?.animatedEndEditing { [weak self] _ in
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
            return composeMessageView?.attachmentsCollectionViewController.getView(at: indexPath)
        }
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

@available(iOS 15.0, *)
extension NewSingleDiscussionViewController {
    
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            let message = frc.object(at: indexPath)
            guard message is PersistedMessageSent || message is PersistedMessageReceived else { continue }
            cacheDelegate.requestAllHardlinksForMessage(with: message.typedObjectID, completionWhenHardlinksCached: { _ in })
            if let text = message.textBodyToSend {
                cacheDelegate.requestDataDetection(text: text, completionWhenDataDetectionCached: { _ in })
            }
        }
    }
    
}
