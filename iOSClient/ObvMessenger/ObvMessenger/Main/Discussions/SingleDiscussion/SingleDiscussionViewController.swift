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
import MobileCoreServices
import QuickLook
import AVFoundation


protocol DiscussionViewController: UIViewController {
    var discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion> { get }
    func addAttachmentFromAirDropFile(at url: URL)
}

final class SingleDiscussionViewController: UICollectionViewController, DiscussionViewController, SomeSingleDiscussionViewController {
    
    var discussion: PersistedDiscussion!
    /// If `true`, all message statuses and attachment progresses are hidden
    var hideProgresses = false
    var restrictToLastMessages: Bool!
    var composeMessageViewDataSource: ComposeMessageDataSource!
    var composeMessageViewDocumentPickerDelegate: ComposeMessageViewDocumentPickerDelegate!
    weak var weakComposeMessageViewSendMessageDelegate: ComposeMessageViewSendMessageDelegate?
    var strongComposeMessageViewSendMessageDelegate: ComposeMessageViewSendMessageDelegate?
    var composeMessageViewSendMessageDelegate: ComposeMessageViewSendMessageDelegate! {
        return strongComposeMessageViewSendMessageDelegate ?? weakComposeMessageViewSendMessageDelegate
    }
    weak var uiApplication: UIApplication?
    weak var delegate: SingleDiscussionViewControllerDelegate?

    var discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion> { discussion.typedObjectID }
    
    private var fetchedResultsController: NSFetchedResultsController<PersistedMessage>!

    private var composeMessageView: ComposeMessageView!

    private var viewDidAppearWasCalled = false
    private var scrollToSystemMessageIndicatingNewMesssagesWasCalled = false
    private var userIsPullingTheSingleDiscussionViewControllerBack = false
    
    // The following variables allow to get around ponctual issues related to keyboard appearance
    private var counterOfCallsToAdjustCollectionViewContentOffsetToIgnore = 0
    private var counterOfCallsToAdjustCollectionViewContentInsetsToIgnore = 0
    
    private let animatorForHidingHeaders = UIViewPropertyAnimator(duration: 0.3, curve: .linear)
    
    private var filesViewer: FilesViewer?
    
    private var lastCollectionViewItemShouldBeVisible = true
    private let typicalDurationKbdAnimation: TimeInterval = 0.25
    private let animatorForScrollingCollectionView = UIViewPropertyAnimator(duration: typicalDurationKbdAnimation*2.3, dampingRatio: 0.65)
    
    private var hideHeaderTimer: Timer? = nil
    
    private let navigationTitleLabel = UILabel()
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))

    private var accessoryViewIsShown = false
    private var accessoryViewWasRequested = false
    
    private var showingAccessoryViewIsAppropriate: Bool {
        assert(Thread.current == Thread.main)
        // We only show the accessory view if it has been requested
        guard accessoryViewWasRequested else { return false }
        // We do not show the accessory view for locked discussions
        guard !(discussion is PersistedDiscussionGroupLocked || discussion is PersistedDiscussionOneToOneLocked) else { return false }
        // We do no not show the accessory view if we have no one to write to in a group discussion
        if let groupDiscussion = discussion as? PersistedGroupDiscussion, !groupDiscussion.hasAtLeastOneRemoteContactDevice() {
            return false
        } else {
            return true
        }
    }
    
    private var currentKbdHeight: CGFloat = 0.0
    private var observationTokens = [NSObjectProtocol]()
    private var objectIDsOfNewMessages = Set<NSManagedObjectID>() // Allows to properly update the "new message" system message
    
    private var sectionChanges = [(type: NSFetchedResultsChangeType, sectionIndex: Int)]()
    private var itemChanges = [(type: NSFetchedResultsChangeType, indexPath: IndexPath?, newIndexPath: IndexPath?)]()
    
    private static let typicalDurationKbdAnimation: TimeInterval = 0.25
    private let animatorForCollectionViewContent = UIViewPropertyAnimator(duration: typicalDurationKbdAnimation*2.3, dampingRatio: 0.65)
    
    private var urlsOfTempFilesToDeleteOnUIDocumentPickerViewControllerDismissal = [URL]()

    private let queueForReadReceiptNotifications = DispatchQueue(label: "Queue for read receipt notifications")

    private var selectedGroupMembers = Set<PersistedObvContactIdentity>()

    private var cellsShowingCallLogItemRejectedIncomingCallBecauseOfDeniedRecordPermissionNeedToBeReconfigured = false

    private func markAsNotNewTheReceivedMessage(_ messageReceived: PersistedMessageReceived) {
        guard messageReceived.status == .new else { return }
        ObvMessengerInternalNotification.messagesAreNotNewAnymore(persistedMessageObjectIDs: [messageReceived.typedObjectID.downcast])
            .postOnDispatchQueue()
    }

    private func markAsNotNewTheSystemMessage(_ messageSystem: PersistedMessageSystem) {
        guard messageSystem.status != .read else { return }
        ObvMessengerInternalNotification.messagesAreNotNewAnymore(persistedMessageObjectIDs: [messageSystem.typedObjectID.downcast])
            .postOnDispatchQueue()
    }

    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { SingleDiscussionViewController.makeError(message: message) }
    
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
    
    private let dateFormaterForHeadersCurrentMonth: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale.current
        df.doesRelativeDateFormatting = false
        df.timeStyle = .none
        df.setLocalizedDateFormatFromTemplate("EEEEd")
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
    
    let dateFormaterForMessages: DateFormatter = {
        let df = DateFormatter()
        df.doesRelativeDateFormatting = true
        df.dateStyle = .none
        df.timeStyle = .short
        df.locale = Locale.current
        return df
    }()

    
    override func didReceiveMemoryWarning() {
        os_log("didReceiveMemoryWarning (SingleDiscussionViewController)", log: log, type: .fault)
    }

    
    override var inputAccessoryView: UIView? {
        assert(Thread.current == Thread.main)
        guard showingAccessoryViewIsAppropriate else {
            accessoryViewIsShown = false
            return nil
        }
        accessoryViewIsShown = true
        return self.composeMessageView
    }
    
    
    override var canBecomeFirstResponder: Bool {
        return true
    }

    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// This should be properly dealocated each time the view will disappear.
    private var timerForRefreshingCellCountdowns: Timer?
    
    func addAttachmentFromAirDropFile(at fileURL: URL) {
        guard let composeMessageViewDocumentPickerAdapterWithDraft = self.composeMessageViewDocumentPickerDelegate as? ComposeMessageViewDocumentPickerAdapterWithDraft else { assertionFailure(); return }
        composeMessageViewDocumentPickerAdapterWithDraft.addAttachmentFromAirDropFile(at: fileURL)
    }
}


// MARK: - View controller lifecycle

extension SingleDiscussionViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()

        if restrictToLastMessages {
            self.fetchedResultsController = PersistedMessage.getFetchedResultsControllerForLastMessagesWithinDiscussion(discussionObjectID: discussion.objectID, within: ObvStack.shared.viewContext)
        } else {
            self.fetchedResultsController = PersistedMessage.getFetchedResultsControllerForAllMessagesWithinDiscussion(discussionObjectID: discussion.typedObjectID, within: ObvStack.shared.viewContext)
        }
        
        self.composeMessageView = Bundle.main.loadNibNamed(ComposeMessageView.nibName, owner: nil, options: nil)!.first as? ComposeMessageView
        self.composeMessageView.dataSource = self.composeMessageViewDataSource
        self.composeMessageView.documentPickerDelegate = self.composeMessageViewDocumentPickerDelegate
        self.composeMessageView.sendMessageDelegate = self.composeMessageViewSendMessageDelegate

        configureNavigationBarTitle()
        
        self.fetchedResultsController.delegate = self
        (self.composeMessageViewDocumentPickerDelegate as? ComposeMessageViewDocumentPickerAdapterWithDraft)?.delegate = self

        let layout = ObvCollectionViewLayout()
        
        collectionView = ObvCollectionView(frame: self.view.bounds, collectionViewLayout: layout)
        collectionView.backgroundColor = AppTheme.shared.colorScheme.discussionScreenBackground
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.indicatorStyle = .white
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.scrollsToTop = false
        collectionView.register(MessageSentCollectionViewCell.self, forCellWithReuseIdentifier: MessageSentCollectionViewCell.identifier)
        collectionView.register(MessageReceivedCollectionViewCell.self, forCellWithReuseIdentifier: MessageReceivedCollectionViewCell.identifier)
        collectionView.register(MessageSystemCollectionViewCell.self, forCellWithReuseIdentifier: MessageSystemCollectionViewCell.identifier)
        collectionView.register(DateCollectionReusableView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: DateCollectionReusableView.identifier)

        layout.delegate = self
        collectionView.dataSource = self
        
        do {
            try self.fetchedResultsController.performFetch()
        } catch let error {
            fatalError("Could not perform fetch: \(error.localizedDescription)")
        }
        
        registerKeyboardNotifications()
        configureGestureRecognizers()
        observeDeletedFyleMessageJoinNotifications()
        observeCertainMessageDeletionToUpdateNumberOfNewMessagesSystemMessage()
        observePersistedDiscussionHasNewTitleNotifications()
        observePersistedContactHasNewCustomDisplayNameNotifications()
        observePersistedContactGroupHasUpdatedContactIdentitiesNotifications()
        observeCallLogItemWasUpdatedNotifications()
        observeAppStateChanges()
        observeDiscussionLocalConfigurationHasBeenUpdatedNotifications()
        showAccessoryView()
    }

    
    private func configureNavigationBarTitle() {
        navigationTitleLabel.font = UIFont.preferredFont(forTextStyle: UIFont.TextStyle.headline)
        navigationTitleLabel.textAlignment = .center
        navigationTitleLabel.text = discussion.title
        navigationTitleLabel.isUserInteractionEnabled = true
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(titleTapped))
        navigationTitleLabel.addGestureRecognizer(tapGestureRecognizer)
        navigationItem.titleView = navigationTitleLabel
        navigationItem.largeTitleDisplayMode = .never

        if !(discussion is PersistedDiscussionGroupLocked) {
            var items: [UIBarButtonItem] = []
            items += [UIBarButtonItem(systemName: ObvSystemIcon.ellipsisCircle.systemName, style: .plain, target: self, action: #selector(settingsButtonTapped))]

            if discussion.isCallAvailable, AppStateManager.shared.appType == .mainApp {
                items += [UIBarButtonItem(systemName: ObvSystemIcon.phoneFill.systemName, style: .plain, target: self, action: #selector(callButtonTapped))]
            }
            if #available(iOS 14.0, *), let muteNotificationEndDate = discussion.localConfiguration.currentMuteNotificationsEndDate {
                let unmuteDateFormatted = PersistedDiscussionLocalConfiguration.formatDateForMutedNotification(muteNotificationEndDate)
                let unmuteButton = UIBarButtonItem(
                    systemName: ObvMessengerConstants.muteIcon.systemName,
                    style: .plain,
                    title: Strings.mutedNotificationsConfirmation(unmuteDateFormatted),
                    actions: [UIAction(title:
                                        NSLocalizedString("UNMUTE_NOTIFICATIONS", comment: "")
                    ) { _ in
                        ObvMessengerInternalNotification.userWantsToUpdateDiscussionLocalConfiguration(value: .muteNotificationsDuration(muteNotificationsDuration: nil), localConfigurationObjectID: self.discussion.localConfiguration.typedObjectID).postOnDispatchQueue()
                    }])
                items += [unmuteButton]
            }
            navigationItem.rightBarButtonItems = items
        }
    }

    
    @objc func settingsButtonTapped() {
        if #available(iOS 13, *) {
            composeMessageView.textView.resignFirstResponder()
            guard let vc = DiscussionSettingsHostingViewController(discussionSharedConfiguration: self.discussion.sharedConfiguration, discussionLocalConfiguration: self.discussion.localConfiguration) else {
                assertionFailure()
                return
            }
            present(vc, animated: true)
        } else {
            let vc = SingleDiscussionSettingsTableViewController(discussionInViewContext: self.discussion)
            self.navigationController?.pushViewController(vc, animated: true)
        }
    }

    @objc func callButtonTapped() {
        if let oneToOneDiscussion = discussion as? PersistedOneToOneDiscussion {
            guard let contactID = oneToOneDiscussion.contactIdentity?.typedObjectID else { return }

            ObvMessengerInternalNotification.userWantsToCallButWeShouldCheckSheIsAllowedTo(contactIDs: [contactID], groupId: nil)
                .postOnDispatchQueue()

        } else if let groupDiscussion = discussion as? PersistedGroupDiscussion,
                  let contactGroup = groupDiscussion.contactGroup,
                  let groupId = try? contactGroup.getGroupId() {
            let contactIdentities = contactGroup.contactIdentities

            ObvMessengerInternalNotification.userWantsToSelectAndCallContacts(contactIDs: contactIdentities.map({ $0.typedObjectID }), groupId: groupId).postOnDispatchQueue()
        }
    }

    @objc func titleTapped() {
        self.delegate?.userTappedTitleOfDiscussion(self.discussion)
    }

    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        insertSystemMessageIndicatingNewMesssages()
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300)) { [weak self] in
            self?.scrollToSystemMessageIndicatingNewMesssages()
        }

        // If there is a system message indicating the number of new messages, we need to keep track of those messages in order to make it possible to update this system message.
        if let numberOfNewMessagesSystemMessage = try? PersistedMessageSystem.getNumberOfNewMessagesSystemMessage(in: discussion) {
            do {
                objectIDsOfNewMessages.removeAll()
                if let newReceivedMessages = try? PersistedMessageReceived.getAllNew(in: discussion) {
                    objectIDsOfNewMessages.formUnion(Set(newReceivedMessages.map({ $0.objectID })))
                }
                if let newSystemMessages = try? PersistedMessageSystem.getAllNewRelevantSystemMessages(in: discussion) {
                    objectIDsOfNewMessages.formUnion(Set(newSystemMessages.map({ $0.objectID })))
                }
            }
            assert(numberOfNewMessagesSystemMessage.numberOfUnreadReceivedMessages == objectIDsOfNewMessages.count)
        }

        if timerForRefreshingCellCountdowns == nil {
            timerForRefreshingCellCountdowns = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(refreshCellCountdowns), userInfo: nil, repeats: true)
        }

    }
    
    
    private func insertSystemMessageIndicatingNewMesssages() {
        assert(Thread.isMainThread)
        assert(discussion.managedObjectContext == ObvStack.shared.viewContext)
        os_log("Inserting system message indicating new messages", log: log, type: .info)
        do {
            try PersistedMessageSystem.removeAnyNewMessagesSystemMessages(withinDiscussion: discussion)
            _ = try PersistedMessageSystem.insertNumberOfNewMessagesSystemMessage(within: discussion)
        } catch let error {
            os_log("Could not insert number of new message within the discussion: %{public}@", log: log, type: .error, error.localizedDescription)
        }
    }

    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
    }
    
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()

        /* Note that this called is required because
         * func viewSafeAreaInsetsDidChange()
         * is called before
         * func viewDidAppear(_ animated: Bool)
         * which is not the case of
         * func viewDidLayoutSubviews().
         */
        resetCollectionViewLayoutIfRequired()

        // If the accessory is not shown (e.g., for locked discussions), we adjust the insets of the collection view by hand
        if composeMessageView.window == nil {
            adjustCollectionViewContentInset(nextKbdAndComposeViewHeight: 0)
        }
        
    }
    
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        resetCollectionViewLayoutIfRequired()
        if !viewDidAppearWasCalled {
            hideTopHeaderIfRequired(animate: false)
        }

        self.composeMessageView.setWidth(to: self.view.bounds.width)

        // If the discussion is locked, or if the group is empty, the keyboard won't show.
        // In that case, we manually adjust the inset of the collection view.
        if discussion is PersistedDiscussionGroupLocked || discussion is PersistedDiscussionOneToOneLocked || discussionHasNoRemoteContactDevice {
            adjustCollectionViewContentInset(nextKbdAndComposeViewHeight: 0)
            DispatchQueue.main.async { [weak self] in
                self?.performInitialScrollToBottomIfRequired()
            }
        }

        

    }
    
    
    private func resetCollectionViewLayoutIfRequired() {
        // In case the width of the safe area of the collection view is different from the one that the layout used to size all the cells, we invalidate the layout to force re-layout.
        let layout = collectionView.collectionViewLayout as! ObvCollectionViewLayout
        if layout.knownCollectionViewSafeAreaWidth != collectionView.bounds.inset(by: collectionView.safeAreaInsets).width {
            collectionView.collectionViewLayout.invalidateLayout()
            (collectionView.collectionViewLayout as? ObvCollectionViewLayout)?.reset()
            collectionView.layoutIfNeeded()
        }
    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        performInitialScrollToBottomIfRequired() // To be called before setting viewDidAppearWasCalled to true. This call is required on iPad.
        viewDidAppearWasCalled = true
  
        scrollToSystemMessageIndicatingNewMesssages()

        insertSystemMessageIfCurrentDiscussionIsEmpty()
     
        if scrollToSystemMessageIndicatingNewMesssagesWasCalled {
            // This call is necessary when the user navigated to another discussion from this one, i.e., this discussion is part of the navigation but is not the last one, i.e., not visible on screen.
            // Then, the user comes back to this discussion. We want to mark the visible messages as "read" at that moment.
            markAllVisibleMessageReceivedAsNotNew()
            markAllVisibleMessageSystemAsNotNew()
        }

        self.becomeFirstResponder()

        showAccessoryView()
    }
    
    
    private func performInitialScrollToBottomIfRequired() {
        guard !viewDidAppearWasCalled else { return }
        let x = collectionView.contentOffset.x
        // This does not always work... there is still a glitch on iPhone 11 Pro Max in landscape.
        let y: CGFloat
        if composeMessageView.window == nil {
            // The keyboard is not on screen so we do not take its height into account
            y = collectionView.contentSize.height - collectionView.bounds.height + collectionView.safeAreaInsets.bottom
        } else {
            // The keyboard is on screen
            y = collectionView.contentSize.height - collectionView.bounds.height + composeMessageView.frame.height
        }
        guard y + collectionView.safeAreaInsets.top > 0 else { return }
        let newOffset = CGPoint(x: x, y: y)
        guard collectionView.contentOffset.distance(to: newOffset) > 0.01 else { return } // No need to scroll in that case
        UIView.performWithoutAnimation {
            collectionView.setContentOffset(newOffset, animated: false)
        }
    }
    
    
    private func insertSystemMessageIfCurrentDiscussionIsEmpty() {
        let discussionObjectID = discussion.objectID
        let log = self.log
        ObvStack.shared.performBackgroundTask { (context) in
            do {
                try PersistedDiscussion.insertSystemMessagesIfDiscussionIsEmpty(discussionObjectID: discussionObjectID, markAsRead: true, within: context)
                try context.save(logOnFailure: log)
            } catch {
                os_log("Could not insert DiscussionIsEndToEndEncryptedSystemMessage within discussion", log: log, type: .error)
            }
        }
    }
    
    
    private func scrollToSystemMessageIndicatingNewMesssages() {
        assert(Thread.isMainThread)
        guard !scrollToSystemMessageIndicatingNewMesssagesWasCalled else { return }
        scrollToSystemMessageIndicatingNewMesssagesWasCalled = true
        if let messageObjectID = try? PersistedMessageSystem.getNewMessageSystemMessageObjectID(withinDiscussion: self.discussion),
            let message = try? fetchedResultsController.managedObjectContext.existingObject(with: messageObjectID) as? PersistedMessageSystem,
            let indexPath = fetchedResultsController.indexPath(forObject: message), let collectionView = self.collectionView as? ObvCollectionView {
            // Only scroll if the cell is not already visible on screen (this techniques works better than calling indexPathsForVisibleItems)
            guard let cell = collectionView.cellForItem(at: indexPath) else {
                // The cell might be to high...
                collectionView.adjustedScrollToItem(at: indexPath, at: .top, animated: true) { [weak self] in
                    self?.markAllVisibleMessageReceivedAsNotNew()
                    self?.markAllVisibleMessageSystemAsNotNew()
                }
                return
            }
            let cellRect = cell.contentView.convert(cell.contentView.bounds, to: collectionView)
            guard !collectionView.bounds.inset(by: collectionView.safeAreaInsets).contains(cellRect) else {
                return
            }
            // The system cell is not visible --> scroll
            collectionView.adjustedScrollToItem(at: indexPath, at: .top, animated: true) { [weak self] in
                self?.markAllVisibleMessageReceivedAsNotNew()
                self?.markAllVisibleMessageSystemAsNotNew()
            }
        }
    }
    
    
    private func markAllVisibleMessageReceivedAsNotNew() {
        do {
            let visibleMessageReceivedCells = collectionView.visibleCells.compactMap { $0 as? MessageReceivedCollectionViewCell}
            for cell in visibleMessageReceivedCells {
                guard let indexPath = collectionView.indexPath(for: cell) else { continue }
                guard let messageReceived = fetchedResultsController.object(at: indexPath) as? PersistedMessageReceived else { continue }
                guard messageReceived.status == .new else { continue }
                markAsNotNewTheReceivedMessage(messageReceived)
            }
        }
    }
    
    
    private func markAllVisibleMessageSystemAsNotNew() {
        let visibleMessageReceivedCells = collectionView.visibleCells.compactMap { $0 as? MessageReceivedCollectionViewCell}
        for cell in visibleMessageReceivedCells {
            guard let indexPath = collectionView.indexPath(for: cell) else { continue }
            guard let messageSystem = fetchedResultsController.object(at: indexPath) as? PersistedMessageSystem else { continue }
            guard messageSystem.status == .new else { continue }
            markAsNotNewTheSystemMessage(messageSystem)
        }
    }
    
    private func observePersistedContactGroupHasUpdatedContactIdentitiesNotifications() {
        let token = ObvMessengerInternalNotification.observePersistedContactGroupHasUpdatedContactIdentities(queue: OperationQueue.main) { [weak self] (_, _, _) in
            self?.reloadInputViews()
        }
        observationTokens.append(token)
    }

    private func observeCallLogItemWasUpdatedNotifications() {
        let token = ObvMessengerInternalNotification.observeCallHasBeenUpdated(queue: OperationQueue.main) { [weak self] _, _ in
            self?.collectionView.reloadData()
        }
        observationTokens.append(token)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        timerForRefreshingCellCountdowns?.invalidate()
        timerForRefreshingCellCountdowns = nil
        
        if self.filesViewer == nil {
            if let discussion = self.discussion {
                try? PersistedMessageSystem.removeAnyNewMessagesSystemMessages(withinDiscussion: discussion)
            }
        }
    }

    
    private func dismissAccessoryView() {
        assert(Thread.current == Thread.main)
        accessoryViewWasRequested = false
        composeMessageView.textView.resignFirstResponder()
        self.becomeFirstResponder()
        reloadInputViews()
    }
    
    
    private func showAccessoryView() {
        assert(Thread.current == Thread.main)
        guard !accessoryViewIsShown else { return }
        accessoryViewWasRequested = true
        guard showingAccessoryViewIsAppropriate else { return }
        becomeFirstResponder()
        reloadInputViews()
    }

    @objc(refreshCellCountdowns)
    private func refreshCellCountdowns() {
        collectionView?.visibleCells.forEach {
            ($0 as? MessageCollectionViewCell)?.refreshCellCountdown()
        }
    }
    
}


// MARK: - UICollectionViewDataSource

extension SingleDiscussionViewController {
    
    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return fetchedResultsController.sections?.count ?? 0
    }

    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let sections = fetchedResultsController.sections else {
            fatalError("No sections in fetchedResultsController")
        }
        let sectionInfo = sections[section]
        return sectionInfo.numberOfObjects
    }

    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        let message = fetchedResultsController.object(at: indexPath)
        
        if let message = message as? PersistedMessageReceived {
            
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MessageReceivedCollectionViewCell.identifier, for: indexPath) as! MessageReceivedCollectionViewCell
            cell.prepare(with: message, withDateFormatter: dateFormaterForMessages)
            cell.delegate = self
            return cell
            
        } else if let message = message as? PersistedMessageSent {
            
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MessageSentCollectionViewCell.identifier, for: indexPath) as! MessageSentCollectionViewCell
            cell.prepare(with: message, withDateFormatter: dateFormaterForMessages, hideProgresses: self.hideProgresses)
            cell.delegate = self
            return cell
            
        } else if let message = message as? PersistedMessageSystem {
            
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MessageSystemCollectionViewCell.identifier, for: indexPath) as! MessageSystemCollectionViewCell
            cell.prepare(with: message)
            return cell
            
        } else {
            
            return UICollectionViewCell()
            
        }
        
    }
    
    
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader else { fatalError() }
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: DateCollectionReusableView.identifier, for: indexPath) as! DateCollectionReusableView
        let sectionTitle = getSectionTitle(at: indexPath)
        header.label.text = sectionTitle
        return header
    }
    
    
    private func getSectionTitle(at indexPath: IndexPath) -> String {
        guard let sections = fetchedResultsController.sections else {
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
}


// MARK: - ObvCollectionViewLayoutDelegate

extension SingleDiscussionViewController: ObvCollectionViewLayoutDelegate {
    
    func collectionViewDidAppear() -> Bool {
        return viewDidAppearWasCalled
    }

    
    func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {

        switch layoutAttributes.representedElementCategory {
        case .cell:
            let message = fetchedResultsController.object(at: layoutAttributes.indexPath)
            if let receivedMessage = message as? PersistedMessageReceived {
                let cell = MessageReceivedCollectionViewCell()
                cell.prepare(with: receivedMessage, withDateFormatter: dateFormaterForMessages)
                return cell.preferredLayoutAttributesFitting(layoutAttributes)
            } else if let sentMessage = message as? PersistedMessageSent {
                let cell = MessageSentCollectionViewCell()
                cell.prepare(with: sentMessage, withDateFormatter: dateFormaterForMessages, hideProgresses: self.hideProgresses)
                return cell.preferredLayoutAttributesFitting(layoutAttributes)
            } else if let systemMessage = message as? PersistedMessageSystem {
                let cell = MessageSystemCollectionViewCell()
                cell.prepare(with: systemMessage)
                return cell.preferredLayoutAttributesFitting(layoutAttributes)
            } else {
                assertionFailure()
                return layoutAttributes
            }
        case .supplementaryView:
            guard layoutAttributes.representedElementKind == UICollectionView.elementKindSectionHeader else { return layoutAttributes }
            let header = DateCollectionReusableView()
            let sectionTitle = getSectionTitle(at: layoutAttributes.indexPath)
            header.label.text = sectionTitle
            return header.preferredLayoutAttributesFitting(layoutAttributes)
        case .decorationView:
            assertionFailure()
            return layoutAttributes
        @unknown default:
            assertionFailure()
            return layoutAttributes
        }
        
    }
    
}


// MARK: - UIScrollViewDelegate

extension SingleDiscussionViewController {
    
    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        
        guard let collectionView = self.collectionView as? ObvCollectionView else {
            assertionFailure()
            return
        }
        
        let isFingerScrolling = scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
        
        if isFingerScrolling {
            let visibleHeaders = collectionView.visibleSupplementaryViews(ofKind: UICollectionView.elementKindSectionHeader)
            for header in visibleHeaders {
                (header as? DateCollectionReusableView)?.alphaIsLocked = false
            }

            lastCollectionViewItemShouldBeVisible = collectionView.lastIndexPathIsVisible
        }
        
        if scrollView.isDragging {
            showTopHeader()
        }
        
        hideTopHeaderInTheFuture()
        
    }
    
    private func showTopHeader() {
        // Show all headers when scrolling
        let headersToShow = collectionView.visibleSupplementaryViews(ofKind: UICollectionView.elementKindSectionHeader).filter { $0.isHidden == true }
        for header in headersToShow {
            header.alpha = 0.0
        }
        animatorForHidingHeaders.addAnimations {
            for header in headersToShow {
                header.isHidden = false
                header.alpha = 1.0
            }
        }
        animatorForHidingHeaders.startAnimation()
        
    }
    
    private func hideTopHeaderInTheFuture() {
        hideHeaderTimer?.invalidate()
        hideHeaderTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false, block: { [weak self] (timer) in
            guard timer.isValid else { return }
            self?.hideTopHeaderIfRequired(animate: true)
        })
    }
    
    
    private func hideTopHeaderIfRequired(animate: Bool) {
        guard collectionView.bounds.inset(by: collectionView.adjustedContentInset).height < collectionView.contentSize.height else { return }
        guard let layout = collectionView.collectionViewLayout as? ObvCollectionViewLayout else { return }
        guard let currentStickyHeader = layout.indexPathOfPinnedHeader else { return }
        guard let header = collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionHeader, at: currentStickyHeader) else { return }
        guard !header.isHidden else { return }
        if let firstCell = collectionView.cellForItem(at: IndexPath(item: 0, section: currentStickyHeader.section)) {
            guard firstCell.frame.intersects(header.frame) || firstCell.frame.maxY <= header.frame.minY else { return }
        }
        
        if animate {
            animatorForHidingHeaders.addAnimations {
                header.alpha = 0.0
            }
            animatorForHidingHeaders.addCompletion { (position) in
                switch position {
                case .end:
                    header.isHidden = header.alpha.isZero
                default:
                    header.isHidden = false
                }
            }
            animatorForHidingHeaders.startAnimation()
        } else {
            header.alpha = 0.0
            header.isHidden = true
        }
        
    }

}


// MARK: - UICollectionViewDelegate

extension SingleDiscussionViewController {
    
    override func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {

        // Check that the discussion is on screen, otherwise we do not mark the messages as "not new"
        guard isViewLoaded && view.window != nil else { return }
        
        // We also check that the app is running before setting the messages as "not new".
        // If the user enters to fast in the app (e.g., by tapping a message notification), the app state might be 'inactive' although the messages should be indicated as "not new". To solve this issue, we also observe app state changes updates.
        guard AppStateManager.shared.currentState.isInitializedAndActive else { return }

        markAsNotNewTheReceivedMessageInCell(cell)
        
    }
    
    
    /// We observe app states changes to mark as "not new" all the messages that are visible when the app enters the running state.
    private func observeAppStateChanges() {
        observationTokens.append(ObvMessengerInternalNotification.observeAppStateChanged(queue: OperationQueue.main) { [weak self] (previousState, currentState) in
            guard let _self = self else { return }
            guard currentState.isInitializedAndActive else { return }
            guard _self.isViewLoaded && _self.view.window != nil else { return }
            _self.insertSystemMessageIndicatingNewMesssages()
            _self.scrollToSystemMessageIndicatingNewMesssages()
            for cell in _self.collectionView.visibleCells {
                _self.markAsNotNewTheReceivedMessageInCell(cell)
            }
            if _self.cellsShowingCallLogItemRejectedIncomingCallBecauseOfDeniedRecordPermissionNeedToBeReconfigured {
                _self.fetchedResultsController.managedObjectContext.refreshAllObjects()
                let visibleIps = _self.collectionView.indexPathsForVisibleItems.filter { _self.collectionView.cellForItem(at: $0) is MessageSystemCollectionViewCell }
                _self.collectionView.reloadItems(at: visibleIps)
                self?.cellsShowingCallLogItemRejectedIncomingCallBecauseOfDeniedRecordPermissionNeedToBeReconfigured = false
            }
        })
    }

    
    private func markAsNotNewTheReceivedMessageInCell(_ cell: UICollectionViewCell) {
        if let msgReceivedCell = cell as? MessageReceivedCollectionViewCell,
           let messageReceived = msgReceivedCell.message as? PersistedMessageReceived {
            guard messageReceived.status == .new else { return }
            markAsNotNewTheReceivedMessage(messageReceived)
        }
        if let msgSystemCell = cell as? MessageSystemCollectionViewCell,
           let messageSystem = msgSystemCell.messageSystem {
            guard messageSystem.status == .new else { return }
            markAsNotNewTheSystemMessage(messageSystem)
        }
    }
    
    
    @available(iOS 13.0, *)
    override func collectionView(_ collectionView: UICollectionView, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {
        // This describes what should be done when the user taps *in* the cell. For now, we simply dismiss the preview.
        animator.preferredCommitStyle = .dismiss
    }
    
    @available(iOS 13.0, *)
    override func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        
        guard let cell = collectionView.cellForItem(at: indexPath) as? CellWithMessage else { return nil }
        
        guard cell.isSomeActionAvailable else { return nil }

        if currentKbdHeight > composeMessageView.frame.height {
            // When the keyboard is up, we use the usual technique in order to avoid animation glitches.
            counterOfCallsToAdjustCollectionViewContentInsetsToIgnore = 3
            counterOfCallsToAdjustCollectionViewContentOffsetToIgnore = 3
        }

        let actionProvider = makeActionProvider(for: cell)
                
        let menuConfiguration = UIContextMenuConfiguration(indexPath: indexPath,
                                                           previewProvider: nil,
                                                           actionProvider: actionProvider)
        
        return menuConfiguration
    }
    
    
    @available(iOS 13.0, *)
    override func collectionView(_ collectionView: UICollectionView, previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        return getUITargetedPreviewInCollectionView(collectionView, previewForContextMenuWithConfiguration: configuration)
    }
    

    @available(iOS 13.0, *)
    override func collectionView(_ collectionView: UICollectionView, previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        return getUITargetedPreviewInCollectionView(collectionView, previewForContextMenuWithConfiguration: configuration)
    }
    
    
    @available(iOS 13.0, *)
    private func getUITargetedPreviewInCollectionView(_ collectionView: UICollectionView, previewForContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        guard let indexPath = configuration.indexPath else { return nil }
        guard let cell = collectionView.cellForItem(at: indexPath) as? CellWithMessage else { return nil }
        var targetedPreview = UITargetedPreview(view: cell.viewForTargetedPreview)
        // A bug was introduced in iOS 13.2. It seems that the framework is not able to behave properly if the UIPreviewTarget of the `targetedPreview` is different from the cell itself. By default, using the above constructor, the target is set to be the main stack view of the cell. In the following block, we re-target the `targetedPreview` so as to make the cell the UIPreviewTarget. This requires to compute the center of the cell.roundedRectView in the coordinate system of the cell.
        do {
            let centerOfRoundedRectView = CGPoint(x: cell.viewForTargetedPreview.bounds.width / 2, y: cell.viewForTargetedPreview.bounds.height / 2)
            let centerOfRoundedRectViewInCellCoordinateSpace = cell.viewForTargetedPreview.convert(centerOfRoundedRectView, to: cell)
            let previewTarget = UIPreviewTarget(container: cell, center: centerOfRoundedRectViewInCellCoordinateSpace)
            targetedPreview = targetedPreview.retargetedPreview(with: previewTarget)
        }
        return targetedPreview
    }
    
    
    @available(iOS 13.0, *)
    private func makeActionProvider(for cell: CellWithMessage) -> (([UIMenuElement]) -> UIMenu?) {
        return { (suggestedActions) in

            var children = [UIMenuElement]()
            
            // Message infos action
            if cell.isInfoActionAvailable {
                let action = UIAction(title: "Info") { [weak self] (_) in
                    // The following lines is useful when the keyboard is up at the time the user performs a long press on a sent message, then chooses infos.
                    // In that case, the counter is equal to 2 when arriving here, which is inappropriate. So we set it back to one.
                    if let vc = cell.infoViewController {
                        self?.counterOfCallsToAdjustCollectionViewContentInsetsToIgnore = min(1, self?.counterOfCallsToAdjustCollectionViewContentInsetsToIgnore ?? 0)
                        let nav = UINavigationController(rootViewController: vc)
                        nav.presentationController?.delegate = self
                        if #available(iOS 15, *) {
                            let appearance = UINavigationBarAppearance()
                            appearance.configureWithOpaqueBackground()
                            nav.navigationBar.standardAppearance = appearance
                            nav.navigationBar.scrollEdgeAppearance = appearance
                        }
                        self?.navigationController?.present(nav, animated: true)
                    }
                }
                action.image = UIImage(systemName: "info.circle")
                children.append(action)
            }

            // Copy Text action
            if cell.isCopyActionAvailable, let bodyText = cell.textViewToCopy?.text, !bodyText.isEmpty {
                let action = UIAction(title: CommonString.Title.copyText) { (_) in
                    UIPasteboard.general.string = bodyText
                }
                action.image = UIImage(systemName: "doc.on.doc")
                children.append(action)
            }

            if cell.isSharingActionAvailable {
                // Share all photos at once
                if let imageAttachments = cell.imageAttachments, imageAttachments.count > 0 {
                    let action = UIAction(title: Strings.sharePhotos(imageAttachments.count)) { (_) in
                        let completionHandlerForRequestAllHardLinksToFyles = { [weak self] (hardlinks: [HardLinkToFyle?]) in
                            guard let _self = self else { return }
                            let activityItemProviders = hardlinks.compactMap({ $0?.activityItemProvider })
                            guard activityItemProviders.count == hardlinks.count else {
                                os_log("Could not get all activity item providers from the hard links", log: _self.log, type: .fault)
                                return
                            }
                            let uiActivityVC = UIActivityViewController(activityItems: activityItemProviders, applicationActivities: nil)
                            DispatchQueue.main.async { [weak self] in
                                uiActivityVC.popoverPresentationController?.sourceView = cell
                                self?.present(uiActivityVC, animated: true)
                            }
                        }
                        let fyleElements: [FyleElement] = imageAttachments.compactMap {
                            $0.fyleElement
                        }
                        ObvMessengerInternalNotification.requestAllHardLinksToFyles(fyleElements: fyleElements, completionHandler: completionHandlerForRequestAllHardLinksToFyles).postOnDispatchQueue()
                    }
                    action.image = UIImage(systemName: "square.and.arrow.up")
                    children.append(action)
                }

                // Share all attachments at once
                if let fyleMessagesJoinWithStatus = cell.fyleMessagesJoinWithStatus, !fyleMessagesJoinWithStatus.isEmpty, cell.imageAttachments?.count != fyleMessagesJoinWithStatus.count {
                    let action = UIAction(title: Strings.shareAttachments(fyleMessagesJoinWithStatus.count)) { (_) in
                        let completionHandlerForRequestAllHardLinksToFyles = { [weak self] (hardlinks: [HardLinkToFyle?]) in
                            guard let _self = self else { return }
                            let activityItemProviders = hardlinks.compactMap({ $0?.activityItemProvider })
                            guard activityItemProviders.count == hardlinks.count else {
                                os_log("Could not get all activity item providers from the hard links", log: _self.log, type: .fault)
                                return
                            }
                            let uiActivityVC = UIActivityViewController(activityItems: activityItemProviders, applicationActivities: nil)
                            DispatchQueue.main.async { [weak self] in
                                uiActivityVC.popoverPresentationController?.sourceView = cell
                                self?.present(uiActivityVC, animated: true)
                            }
                        }
                        let fyleElements: [FyleElement] = fyleMessagesJoinWithStatus.compactMap {
                            $0.fyleElement
                        }
                        ObvMessengerInternalNotification.requestAllHardLinksToFyles(fyleElements: fyleElements, completionHandler: completionHandlerForRequestAllHardLinksToFyles).postOnDispatchQueue()
                    }
                    action.image = UIImage(systemName: "square.and.arrow.up")
                    children.append(action)
                }
            }
            
            // Reply to message action
            if cell.isReplyToActionAvailable {
                let action = UIAction(title: CommonString.Word.Reply) { [weak self] (_) in
                    guard let discussion = self?.discussion else { return }
                    guard let log = self?.log else { return }
                    ObvStack.shared.performBackgroundTask { [weak self] (context) in
                        guard let _self = self else { return }
                        do {
                            guard let persistedMessage = cell.persistedMessage else { throw NSError() }
                            guard let writableDraft = try PersistedDraft.get(from: discussion, within: context) else { throw NSError() }
                            guard let writableMessage = try PersistedMessage.get(with: persistedMessage.objectID, within: context) else { throw _self.makeError(message: "Could not find PersistedMessage") }
                            writableDraft.replyTo = writableMessage
                            try context.save(logOnFailure: log)
                        } catch {
                            os_log("Could not attach message as a replyTo to the draft", log: log, type: .error)
                            return
                        }
                        os_log("We added a replyTo to the draft", log: log, type: .debug)
                        DispatchQueue.main.async {
                            self?.composeMessageView.loadReplyTo()
                        }
                    }
                }
                action.image = UIImage(systemName: "arrowshape.turn.up.left.2")
                children.append(action)
            }
            
            // Delete message action
            if cell.isDeleteActionAvailable {
                let action = UIAction(title: CommonString.Word.Delete) { [weak self] (_) in
                    guard let persistedMessage = cell.persistedMessage else { return }
                    self?.deletePersistedMessage(objectId: persistedMessage.objectID, confirmedDeletionType: nil, withinCell: cell)
                    self?.counterOfCallsToAdjustCollectionViewContentInsetsToIgnore = 1
                }
                action.image = UIImage(systemName: "trash")
                action.attributes = [.destructive]
                children.append(action)
            }
            
            // Edit message action
            if cell.isEditBodyActionAvailable {
                let action = UIAction(title: CommonString.Word.Edit) { [weak self] (_) in
                    guard let persistedMessage = cell.persistedMessage else { return }
                    let sentMessageObjectID = persistedMessage.objectID
                    let currentTextBody = persistedMessage.textBody
                    self?.dismissAccessoryView()
                    let vc = BodyEditViewController(currentBody: currentTextBody) { [weak self] in
                        self?.presentedViewController?.dismiss(animated: true, completion: {
                            self?.showAccessoryView()
                        })
                    } send: { [weak self] (newTextBody) in
                        self?.presentedViewController?.dismiss(animated: true, completion: {
                            self?.showAccessoryView()
                            guard newTextBody != currentTextBody else { return }
                            ObvMessengerInternalNotification.userWantsToSendEditedVersionOfSentMessage(sentMessageObjectID: sentMessageObjectID,
                                                                                                       newTextBody: newTextBody ?? "")
                                .postOnDispatchQueue()
                        })
                    }
                    self?.present(vc, animated: true)
                    return
                }
                action.image = UIImage(systemName: "pencil.circle")
                children.append(action)
            }

            if cell.isCallActionAvailable {
                let action = UIAction(title: CommonString.Word.Call) { (_) in
                    guard let persistedMessage = cell.persistedMessage as? PersistedMessageSystem else { return }
                    guard let item = persistedMessage.optionalCallLogItem else { return }
                    let groupId = try? item.getGroupId()

                    var contactsToCall = [TypeSafeManagedObjectID<PersistedObvContactIdentity>]()
                    for logContact in item.logContacts {
                        guard let contactIdentity = logContact.contactIdentity else { continue }
                        contactsToCall.append(contactIdentity.typedObjectID)
                    }

                    ObvMessengerInternalNotification.userWantsToSelectAndCallContacts(contactIDs: contactsToCall, groupId: groupId).postOnDispatchQueue()
                }
                action.image = UIImage(systemName: ObvSystemIcon.phoneFill.systemName)
                children.append(action)
            }
            
            return UIMenu(title: "", image: nil, identifier: nil, options: .displayInline, children: children)
        }
    }
}

// MARK: - NSFetchedResultsControllerDelegate

extension SingleDiscussionViewController: NSFetchedResultsControllerDelegate {
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        sectionChanges.insert((type, sectionIndex), at: 0)
    }
    
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        itemChanges.append((type, indexPath, newIndexPath))
    }
    
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        
        let visibleHeaders = collectionView.visibleSupplementaryViews(ofKind: UICollectionView.elementKindSectionHeader)
        
        for header in visibleHeaders {
            // Locking the alpha of the headers prevents animation glitches due to the layout attributes returned with a 1.0 alpha
            (header as? DateCollectionReusableView)?.alphaIsLocked = true
        }

        var anItemWasInserted = false
        // The "bug" (?) can be reproduced by sending a message in a oneToOne discussion prior channel creation.
        // Then create the channel, the message status in not updated.
        // For now, we adopt an ugly patch
        var indexPathsToReload = Set<IndexPath>()
        
        collectionView.performBatchUpdates({
            
            while let (type, sectionIndex) = sectionChanges.popLast() {
                switch type {
                case .insert:
                    collectionView.insertSections(IndexSet(integer: sectionIndex))
                case .delete:
                    collectionView.deleteSections(IndexSet(integer: sectionIndex))
                case .move, .update:
                    break
                @unknown default:
                    assertionFailure()
                }
            }
            while let (type, indexPath, newIndexPath) = itemChanges.popLast() {
                switch type {
                case .insert:
                    collectionView.insertItems(at: [newIndexPath!])
                    anItemWasInserted = true
                    if fetchedResultsController.object(at: newIndexPath!) is PersistedMessageSent {
                        lastCollectionViewItemShouldBeVisible = true
                    }
                case .delete:
                    collectionView.deleteItems(at: [indexPath!])
                    let cellsToRefresh = visibleCellsWithReplyToMessageInCell(at: indexPath!)
                    for cell in cellsToRefresh {
                        cell.refresh()
                    }
                    
                case .update:
                    if let messageCell = collectionView.cellForItem(at: indexPath!) as? MessageCollectionViewCell {
                        messageCell.refresh()
                    } else {
                        collectionView.reloadItems(at: [indexPath!])
                    }
                case .move:
                    // 2020-12-06: We add the 'if' statement. Given the new operations, the collection view has a tendency to call
                    // 'move' instead of 'update'.
                    if indexPath! == newIndexPath!, let messageCell = collectionView.cellForItem(at: indexPath!) as? MessageCollectionViewCell {
                        messageCell.refresh()
                    } else {
                        collectionView.moveItem(at: indexPath!, to: newIndexPath!)
                        indexPathsToReload.insert(newIndexPath!)
                    }
                @unknown default:
                    assertionFailure()
                }
            }
            
        }) { [weak self] (_) in
            
            guard let _self = self else { return }
            let collectionView = _self.collectionView!

            defer {
                if !indexPathsToReload.isEmpty {
                    collectionView.reloadItems(at: [IndexPath](indexPathsToReload))
                }
                if anItemWasInserted {
                    _self.showNoChannelAlertIfRequired()
                }
            }
            
            guard collectionView.bounds.inset(by: collectionView.adjustedContentInset).height < collectionView.contentSize.height && _self.lastCollectionViewItemShouldBeVisible else {
                for header in visibleHeaders {
                    (header as? DateCollectionReusableView)?.alphaIsLocked = false
                }
                return
            }
            
            _self.animatorForScrollingCollectionView.addAnimations {
                collectionView.contentOffset = CGPoint(x: 0, y: collectionView.contentSize.height - collectionView.bounds.height + collectionView.adjustedContentInset.bottom)
            }
            _self.animatorForScrollingCollectionView.addCompletion { (_) in
                for header in visibleHeaders {
                    (header as? DateCollectionReusableView)?.alphaIsLocked = false
                }
                _self.hideTopHeaderIfRequired(animate: true)
            }
            _self.animatorForScrollingCollectionView.startAnimation()
            
        }
        
    }
    
    
    private func visibleCellsWithReplyToMessageInCell(at indexPAth: IndexPath) -> [MessageCollectionViewCell] {
        guard let cell = collectionView.cellForItem(at: indexPAth) else { return [] }
        assert(Thread.current == Thread.main)
        guard let messageCell = cell as? MessageCollectionViewCell else { return [] }
        guard let message = messageCell.message else { return [] }
        let cells = collectionView.visibleCells
            .compactMap { $0 as? MessageCollectionViewCell }
            .filter { $0.message == message }
        return cells
    }
    
}


// MARK: - Handling Gestures

extension SingleDiscussionViewController {
    
    private func configureGestureRecognizers() {
        
        let hedgeGesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(screenEdgePanPerformed))
        hedgeGesture.edges = [.left]
        self.collectionView.addGestureRecognizer(hedgeGesture)

        var longPress: UILongPressGestureRecognizer?
        if #available(iOS 13, *) {
            // We do not add a long press gesture recognizer since we use UIContextMenuConfiguration for showing a context menu
        } else {
            longPress = UILongPressGestureRecognizer(target: self, action: #selector(longPressPerformed(recognizer:)))
            self.collectionView.addGestureRecognizer(longPress!)
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapPerformed))
        if let longPress = longPress {
            tap.require(toFail: longPress)
        }
        self.collectionView.addGestureRecognizer(tap)

    }
 
    
    @objc func screenEdgePanPerformed(recognizer: UIScreenEdgePanGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let percent = max(recognizer.translation(in: view).x, 0) / view.frame.width
        let velocity = recognizer.velocity(in: view).x
        if percent > 0.5 || velocity > 1000 {
            self.dismiss(animated: true)
        }
    }

    
    /// This method is only used for iOS version prior to iOS 13. It calls a method allowing to show a context menu.
    @objc func longPressPerformed(recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        let location = recognizer.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: location) else { return }
        guard let cell = collectionView.cellForItem(at: indexPath) as? CellWithMessage else { return }
        if cell.viewForTargetedPreview.bounds.contains(recognizer.location(in: cell.viewForTargetedPreview)) {
            longPressPerformedOnBodyTextView(ofCell: cell)
        }
    }
    

    @objc func tapPerformed(recognizer: UITapGestureRecognizer) {
        
        guard recognizer.state == .ended else { return }
        let location = recognizer.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: location) else { return }
        let cell = collectionView.cellForItem(at: indexPath)
        
        // Detect tap on a "reply-to" cell
        do {
            if let receivedCell = cell as? MessageCollectionViewCell {
                let replyToRoundedRectView = receivedCell.replyToRoundedRectView
                if replyToRoundedRectView.superview != nil {
                    // The replyToRoundedRectView exists in the view hierarchy, we check whether it was tapped
                    if replyToRoundedRectView.bounds.contains(recognizer.location(in: replyToRoundedRectView)) {
                        // The user tapped on the reply-to cell. Find the corresponding message
                        switch fetchedResultsController.object(at: indexPath).genericRepliesTo {
                        case .none, .notAvailableYet, .deleted:
                            return
                        case .available(let replyToMessage):
                            tapPerformedOnReplyToRoundedRectView(replyToMessage: replyToMessage)
                        }
                    }
                    
                }
            }
        }

        // Detect tap on a new received message that cannot be read (yet)
        do {
            if let receivedMessage = (cell as? MessageCollectionViewCell)?.message as? PersistedMessageReceived, receivedMessage.readingRequiresUserAction {
                ObvMessengerInternalNotification.userWantsToReadReceivedMessagesThatRequiresUserAction(persistedMessageObjectIDs: Set([receivedMessage.typedObjectID]))
                    .postOnDispatchQueue()
                return
            }
        }

        // Detect tap on a FyleMessageJoinWithStatus
        do {
            if let messageCell = cell as? MessageCollectionViewCell {
                if let index = messageCell.indexOfFyleMessageJoinWithStatus(at: recognizer.location(in: messageCell)) {
                    tapPerformedOnFyleMessageJoinWithStatus(atIndex: index, within: messageCell)
                    return // We detected an appropriate tap, we can return
                }
            }
        }

        // Detect tap on CallLog Item
        if let systemMessage = (cell as? MessageSystemCollectionViewCell)?.messageSystem,
           let callLogItem = systemMessage.optionalCallLogItem,
           let callReportKind = callLogItem.callReportKind {
            switch callReportKind {
            case .rejectedIncomingCallBecauseOfDeniedRecordPermission:
                systemCellShowingCallLogItemRejectedIncomingCallBecauseOfDeniedRecordPermissionWasTapped()
            case .missedIncomingCall,
                 .filteredIncomingCall,
                 .rejectedIncomingCall,
                 .acceptedIncomingCall,
                 .acceptedOutgoingCall,
                 .rejectedOutgoingCall,
                 .busyOutgoingCall,
                 .unansweredOutgoingCall,
                 .uncompletedOutgoingCall,
                 .newParticipantInIncomingCall,
                 .newParticipantInOutgoingCall,
                 .anyIncomingCall,
                 .anyOutgoingCall:
                break
            }
        }
    }
    
    
    /// Called when we detect that the user tapped on a view showing a "replied-to" message.
    private func tapPerformedOnReplyToRoundedRectView(replyToMessage: PersistedMessage) {
        
        guard let replyToIndexPath = fetchedResultsController.indexPath(forObject: replyToMessage) else { return }

        if let collectionView = self.collectionView as? ObvCollectionView {
            collectionView.adjustedScrollToItem(at: replyToIndexPath, at: .centeredVertically, animated: true) { [weak self] in
                self?.highlightItem(at: replyToIndexPath)
            }
        }

    }
    
    private func highlightItem(at indexPath: IndexPath) {
        guard let cell = collectionView.cellForItem(at: indexPath) as? MessageCollectionViewCell else { return }

        switch cell {
        case is MessageSentCollectionViewCell:
            cell.roundedRectView.applyRippleEffect(withColor: AppTheme.shared.colorScheme.primary300)
        case is MessageReceivedCollectionViewCell:
            let effectColor = AppTheme.shared.colorScheme.tertiarySystemBackground
            cell.roundedRectView.applyRippleEffect(withColor: effectColor)
        default:
            return
        }
        
    }


    private func tapPerformedOnFyleMessageJoinWithStatus(atIndex index: Int, within messageCell: MessageCollectionViewCell) {
                
        if let fyleMessagesJoinWithStatus = messageCell.fyleMessagesJoinWithStatus as? [ReceivedFyleMessageJoinWithStatus] {
            
            let fyleMessageJoinWithStatus = fyleMessagesJoinWithStatus[index]
            
            switch fyleMessageJoinWithStatus.status {
                
            case .downloadable:
                break
                
            case .downloading:
                break

            case .complete:
                let isSharingActionAvailable = (messageCell as? MessageReceivedCollectionViewCell)?.isSharingActionAvailable ?? false
                let renderableFyleMessagesJoinWithStatus = fyleMessagesJoinWithStatus.filter({ !$0.isWiped })
                guard let indexInListOfRenderableFyles = renderableFyleMessagesJoinWithStatus.firstIndex(where: { $0 == fyleMessageJoinWithStatus }) else { return }
                self.filesViewer = try? FilesViewer(renderableFyleMessagesJoinWithStatus, preventSharing: !isSharingActionAvailable)
                self.filesViewer?.delegate = self
                self.filesViewer?.cellIndexPath = collectionView.indexPath(for: messageCell)
                dismissAccessoryView() // Shown back in func previewControllerDidDismiss(_ controller: QLPreviewController)
                counterOfCallsToAdjustCollectionViewContentOffsetToIgnore = 2
                counterOfCallsToAdjustCollectionViewContentInsetsToIgnore = 2
                self.filesViewer?.tryToShowFile(atIndex: indexInListOfRenderableFyles, within: self)
                return
                
            case .cancelledByServer:
                break // We do nothing if the attachment cannot be downloaded because it was cancelled by the server
            }
            
        } else if let fyleMessagesJoinWithStatus = messageCell.fyleMessagesJoinWithStatus as? [SentFyleMessageJoinWithStatus] {
            
            let fyleMessageJoinWithStatus = fyleMessagesJoinWithStatus[index]
            
            switch fyleMessageJoinWithStatus.status {
            case .uploadable, .uploading, .complete:

                let isSharingActionAvailable = (messageCell as? MessageSentCollectionViewCell)?.isSharingActionAvailable ?? false
                let renderableFyleMessagesJoinWithStatus = fyleMessagesJoinWithStatus.filter({ !$0.isWiped })
                guard let indexInListOfRenderableFyles = renderableFyleMessagesJoinWithStatus.firstIndex(where: { $0 == fyleMessageJoinWithStatus }) else { return }
                self.filesViewer = try? FilesViewer(renderableFyleMessagesJoinWithStatus, preventSharing: !isSharingActionAvailable)
                self.filesViewer?.delegate = self
                self.filesViewer?.cellIndexPath = collectionView.indexPath(for: messageCell)
                dismissAccessoryView() // Shown back in func previewControllerDidDismiss(_ controller: QLPreviewController)
                counterOfCallsToAdjustCollectionViewContentOffsetToIgnore = 2
                counterOfCallsToAdjustCollectionViewContentInsetsToIgnore = 2
                self.filesViewer?.tryToShowFile(atIndex: indexInListOfRenderableFyles, within: self)

            }
            
            
        }
        
    }

    func systemCellShowingCallLogItemRejectedIncomingCallBecauseOfDeniedRecordPermissionWasTapped() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] (granted) in
                guard AppStateManager.shared.currentState.isInitializedAndActive else {
                    self?.cellsShowingCallLogItemRejectedIncomingCallBecauseOfDeniedRecordPermissionNeedToBeReconfigured = true
                    return
                }
                self?.collectionView.reloadData()
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

}


// MARK: - UIDocumentPickerDelegate

extension SingleDiscussionViewController: UIDocumentPickerDelegate {
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        deleteTempFilesToDeleteOnUIDocumentPickerViewControllerDismissal()
    }
    
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        deleteTempFilesToDeleteOnUIDocumentPickerViewControllerDismissal()
    }
    
    
    private func deleteTempFilesToDeleteOnUIDocumentPickerViewControllerDismissal() {
        while let tempURL = urlsOfTempFilesToDeleteOnUIDocumentPickerViewControllerDismissal.popLast() {
            let container = ObvMessengerConstants.containerURL.forTempFiles
            guard tempURL.absoluteString.starts(with: container.absoluteString) else {
                return
            }
            try? FileManager.default.removeItem(at: tempURL)
        }
    }
    
}


// MARK: - Handling keyboard appearance

extension SingleDiscussionViewController {
    
    func registerKeyboardNotifications() {
        do {
            let token = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: nil) { [weak self] (notification) in
                self?.keyboardWillChangeFrame(notification)
            }
            observationTokens.append(token)
        }
        do {
            let token = NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: nil) { [weak self] (notification) in
                self?.keyboardDidHideNotification(notification)
            }
            observationTokens.append(token)
        }
    }

    
    private func keyboardDidHideNotification(_ notification: Notification) {
        accessoryViewIsShown = false
    }
    
    
    private func keyboardWillChangeFrame(_ notification: Notification) {
        
        let visibleHeaders = collectionView.visibleSupplementaryViews(ofKind: UICollectionView.elementKindSectionHeader)
        
        for header in visibleHeaders {
            (header as? DateCollectionReusableView)?.alphaIsLocked = true
        }
        animatorForCollectionViewContent.addCompletion { [weak self] (_) in
            for header in visibleHeaders {
                (header as? DateCollectionReusableView)?.alphaIsLocked = false
            }
            self?.hideTopHeaderIfRequired(animate: true)
        }

        let kbdHeight = getKeyboardHeight(notification)
        guard kbdHeight != currentKbdHeight else { return }
        adjustCollectionViewContentOffset(nextKbdAndComposeViewHeight: kbdHeight)
        adjustCollectionViewContentInset(nextKbdAndComposeViewHeight: kbdHeight)
        currentKbdHeight = kbdHeight
        

    }

    
    private func getKeyboardHeight(_ notification: Notification) -> CGFloat {
        let userInfo = notification.userInfo!
        let kbSize = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as! CGRect).size
        return kbSize.height
    }

    
    private func adjustCollectionViewContentInset(nextKbdAndComposeViewHeight: CGFloat) {
        
        guard counterOfCallsToAdjustCollectionViewContentInsetsToIgnore == 0 else {
            counterOfCallsToAdjustCollectionViewContentInsetsToIgnore -= 1
            debugPrint("🥶 \(discussion.title) counterOfCallsToAdjustCollectionViewInsetsOffsetToIgnore: \(counterOfCallsToAdjustCollectionViewContentInsetsToIgnore+1) --> \(counterOfCallsToAdjustCollectionViewContentInsetsToIgnore)")
            return
        }
        
        let bottomInset = (nextKbdAndComposeViewHeight == 0) ? collectionView.safeAreaInsets.bottom : nextKbdAndComposeViewHeight
        let currentInset = collectionView.contentInset
        let newInset = UIEdgeInsets(top: collectionView.safeAreaInsets.top,
                                    left: collectionView.safeAreaInsets.left,
                                    bottom: bottomInset,
                                    right: collectionView.safeAreaInsets.right)
        if newInset != currentInset {
            debugPrint("🥶 \(discussion.title) Changing insets: \(currentInset) --> \(newInset)")
            if viewDidAppearWasCalled {
                collectionView.contentInset = newInset
            } else {
                UIView.performWithoutAnimation {
                    collectionView.contentInset = newInset
                }
            }
        }
    }
    
    
    private func adjustCollectionViewContentOffset(nextKbdAndComposeViewHeight: CGFloat) {

        guard viewDidAppearWasCalled else {
            // If viewDidAppear has not been called already, we scroll to the bottom of the collection view
            performInitialScrollToBottomIfRequired()
            return
        }
        
        // This is a hack. This is usefull when dismissing the preview of an attachment to avoid animation glitches.
        guard counterOfCallsToAdjustCollectionViewContentOffsetToIgnore == 0 else {
            counterOfCallsToAdjustCollectionViewContentOffsetToIgnore -= 1
            debugPrint("🥵 \(discussion.title) counterOfCallsToAdjustCollectionViewContentOffsetToIgnore: \(counterOfCallsToAdjustCollectionViewContentOffsetToIgnore+1) --> \(counterOfCallsToAdjustCollectionViewContentOffsetToIgnore)")
            return
        }
        
        // If the keyboard size increases, scroll
        
        guard nextKbdAndComposeViewHeight > currentKbdHeight else { return }
        
        let previousAvailableHeightForContent = collectionView.bounds.height - collectionView.safeAreaInsets.top - currentKbdHeight
        let nextAvailableHeightForContent = collectionView.bounds.height - collectionView.safeAreaInsets.top - nextKbdAndComposeViewHeight
        let currentOffset = self.collectionView.contentOffset
        
        let deltaVerticalContentOffset: CGFloat
        
        if collectionView.contentSize.height > previousAvailableHeightForContent {
            
            // Case 1 : The collection view's content size is larger than the previous available height for for content. Typical when there are a lot of messages.
            deltaVerticalContentOffset = nextKbdAndComposeViewHeight - currentKbdHeight
            
        } else if collectionView.contentSize.height > nextAvailableHeightForContent {
            
            // Case 2 : The collection view's content size is smaller than the previous available height for for content, but larger than the next available height. Typical when there are a few messages.
            deltaVerticalContentOffset = collectionView.contentSize.height - nextAvailableHeightForContent
            
        } else {
            
            // Case 3 : The collection view's content size is smaller than the next available height for for content.
            deltaVerticalContentOffset = 0
            
        }
        
        let newContentOffset = CGPoint(x: currentOffset.x, y: currentOffset.y + deltaVerticalContentOffset)
        
        debugPrint("🥵 \(discussion.title) collectionView contentOffset: \(collectionView.contentOffset) --> \(newContentOffset)")

        animatorForCollectionViewContent.addAnimations { [weak self] in
            self?.collectionView.setContentOffset(newContentOffset, animated: false)
        }

        if animatorForCollectionViewContent.state != .active {
            animatorForCollectionViewContent.startAnimation()
        }

    }
    
}


// MARK: - Handling overlay windows

extension SingleDiscussionViewController {
    
    @objc private func dismissOverlayWindow() {
        guard let uiApplication = self.uiApplication else { return }
        for window in uiApplication.windows.reversed() {
            let overlays = window.subviews.filter { $0 is OverlayWindow }
            let animator = UIViewPropertyAnimator(duration: 0.2, curve: .easeInOut)
            for overlayWindow in overlays {
                animator.addAnimations {
                    overlayWindow.backgroundColor = .clear
                    _ = overlayWindow.subviews.map { $0.isHidden = true }
                }
                animator.addCompletion({ (_) in
                    overlayWindow.removeFromSuperview()
                })
            }
            animator.startAnimation()
        }
    }

    
    /// This method is used for iOS version prior to iOS 13. It allows to show a context menu.
    private func longPressPerformedOnBodyTextView(ofCell messageCell: CellWithMessage) {
        guard let uiApplication = self.uiApplication else { return }
        guard let topWindow = uiApplication.windows.last else { return }
        guard let persistedMessage = messageCell.persistedMessage else { return }

        let onBodyRoundedRectView = messageCell.viewForTargetedPreview
        
        // Create an overlay window
        let overlayWindow = OverlayWindow(frame: UIScreen.main.bounds)
        overlayWindow.backgroundColor = .clear
        overlayWindow.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissOverlayWindow)))
        overlayWindow.isHidden = false
        if let navigationBarFrame = self.navigationController?.navigationBar.frame {
            overlayWindow.maskLayerTopMargin = navigationBarFrame.size.height + navigationBarFrame.origin.y
        }

        // Create an UIImageView containing a bitmap of the UIView, set its frame and add it to the overlay window
        do {
            let renderer = UIGraphicsImageRenderer(size: onBodyRoundedRectView.frame.size)
            let image = renderer.image { (rendererCtx) in
                onBodyRoundedRectView.layer.render(in: rendererCtx.cgContext)
            }
            let imageView = UIImageView(image: image)
            imageView.frame = onBodyRoundedRectView.convert(onBodyRoundedRectView.bounds, to: overlayWindow)
            overlayWindow.addView(imageView)
        }

        // Set the horizontalCenter property of the overlay window
        do {
            let rect = onBodyRoundedRectView.convert(onBodyRoundedRectView.bounds, to: overlayWindow)
            let horizontalCenter = rect.origin.x + onBodyRoundedRectView.bounds.size.width / 2
            overlayWindow.setHorizontalCenter(to: horizontalCenter)
        }
        
        // Add actions to the overlay
        if messageCell.isCopyActionAvailable {
            overlayWindow.addAction(title: CommonString.Title.copyText, image: UIImage(named: "menu-copy")!) { [weak self] in
                self?.dismissOverlayWindow()
                UIPasteboard.general.string = messageCell.textViewToCopy?.text
            }
        }
        if messageCell.isReplyToActionAvailable {
            overlayWindow.addAction(title: CommonString.Word.Reply, image: UIImage(named: "menu-reply")!) { [weak self] in
                self?.dismissOverlayWindow()
                guard let discussion = self?.discussion else { return }
                guard let log = self?.log else { return }
                ObvStack.shared.performBackgroundTask { [weak self] (context) in
                    do {
                        guard let writableDraft = try PersistedDraft.get(from: discussion, within: context) else { throw NSError() }
                        guard let writableMessage = try PersistedMessage.get(with: persistedMessage.objectID, within: context) else { throw NSError() }
                        writableDraft.replyTo = writableMessage
                        try context.save(logOnFailure: log)
                    } catch {
                        os_log("Could not attach message as a replyTo to the draft", log: log, type: .error)
                        return
                    }
                    os_log("We added a replyTo to the draft", log: log, type: .debug)
                    DispatchQueue.main.async {
                        self?.composeMessageView.loadReplyTo()
                    }
                }
            }
        }
        if messageCell.isDeleteActionAvailable {
            overlayWindow.addAction(title: CommonString.Word.Delete, image: UIImage(named: "menu-delete")!) { [weak self] in
                self?.dismissOverlayWindow()
                self?.deletePersistedMessage(objectId: persistedMessage.objectID, confirmedDeletionType: nil, withinCell: messageCell)
            }
        }
        
        // Animate the overlay appearance
        topWindow.addSubview(overlayWindow)
        let animator = UIViewPropertyAnimator(duration: 0.2, curve: .easeInOut) {
            overlayWindow.backgroundColor = UIColor(white: 0.0, alpha: 0.8)
        }
        animator.startAnimation()

    }


    private func deletePersistedMessage(objectId: NSManagedObjectID, confirmedDeletionType: DeletionType?, withinCell cell: CellWithMessage) {
        
        switch confirmedDeletionType {
        
        case .none:
            
            guard let persistedMessage = try? PersistedMessage.get(with: objectId, within: ObvStack.shared.viewContext) else { return }
            guard persistedMessage.discussion == self.discussion else { return }
            
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
            DispatchQueue.main.async {
                alert.popoverPresentationController?.sourceView = cell.viewForTargetedPreview
                self.present(alert, animated: true, completion: nil)
            }
            
        case .some(let deletionType):
            
            ObvMessengerInternalNotification.userRequestedDeletionOfPersistedMessage(persistedMessageObjectID: objectId, deletionType: deletionType)
                .postOnDispatchQueue()

        }
        
    }

}


// MARK: - Handling notifications

extension SingleDiscussionViewController {
    
    // Refresh the discussion title if it is updated
    private func observePersistedDiscussionHasNewTitleNotifications() {
        let token = ObvMessengerInternalNotification.observePersistedDiscussionHasNewTitle(queue: OperationQueue.main) { [weak self] (objectID, title) in
            assert(self?.discussion?.managedObjectContext == ObvStack.shared.viewContext)
            guard objectID == self?.discussion?.typedObjectID else { return }
            self?.navigationTitleLabel.text = title
        }
        observationTokens.append(token)
    }
    
    
    private func observePersistedContactHasNewCustomDisplayNameNotifications() {
        let log = self.log
        let token = ObvMessengerInternalNotification.observePersistedContactHasNewCustomDisplayName(queue: OperationQueue.main) { [weak self] (contactCryptoId) in
            guard let _self = self else { return }
            guard let groupDiscussion = _self.discussion as? PersistedGroupDiscussion else { return }
            guard let contactGroup = groupDiscussion.contactGroup else {
                os_log("Could find contact group (this is ok if it was just deleted)", log: log, type: .error)
                return
            }
            let contactsCryptoIds = contactGroup.contactIdentities.map { $0.cryptoId }
            guard contactsCryptoIds.contains(contactCryptoId) else { return }
            // If we reach this point, we simply reload all visible cells that correspond to a received message
            // We need to refresh the context since the changed object is not among the one that are fetcheded
            _self.fetchedResultsController.managedObjectContext.refreshAllObjects()
            let visibleIps = _self.collectionView.indexPathsForVisibleItems.filter { _self.collectionView.cellForItem(at: $0) is MessageReceivedCollectionViewCell }
            _self.collectionView.reloadItems(at: visibleIps)
        }
        observationTokens.append(token)
    }

    private func observeDiscussionLocalConfigurationHasBeenUpdatedNotifications() {
        let token = ObvMessengerInternalNotification.observeDiscussionLocalConfigurationHasBeenUpdated(queue: OperationQueue.main) { [weak self] value, objectId in
            guard let _self = self else { return }
            guard case .muteNotificationsDuration = value else { return }
            guard _self.discussion.localConfiguration.typedObjectID == objectId else { return }

            _self.configureNavigationBarTitle()
        }
        observationTokens.append(token)
    }
}


// MARK: - MessageReceivedCollectionViewCellDelegate

extension SingleDiscussionViewController: MessageCollectionViewCellDelegate {
    func userSelectedURL(_ url: URL) {
        delegate?.userSelectedURL(url, within: self)
    }
    
    func reloadCell(_ cell: UICollectionViewCell) {
        assert(Thread.current == Thread.main)
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        collectionView.reloadItems(at: [indexPath])
    }
}


// MARK: - Showing an alert when no channel is available

extension SingleDiscussionViewController {
    
    private func showNoChannelAlertIfRequired() {
        
        guard discussionHasNoRemoteContactDevice else { return }
        
        let alert: UIAlertController
        if discussion is PersistedOneToOneDiscussion {
            alert = UIAlertController(title: Strings.Alerts.WaitingForChannel.title,
                                      message: Strings.Alerts.WaitingForChannel.message,
                                      preferredStyle: .alert)
        } else if discussion is PersistedGroupDiscussion {
            alert = UIAlertController(title: Strings.Alerts.WaitingForFirstGroupMember.title,
                                      message: Strings.Alerts.WaitingForFirstGroupMember.message,
                                      preferredStyle: .alert)
        } else {
            return
        }
        alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .default, handler: nil))
        present(alert, animated: true)
        
    }
    
    
    private var discussionHasNoRemoteContactDevice: Bool {
        if let oneToOneDiscussion = discussion as? PersistedOneToOneDiscussion {
            return !oneToOneDiscussion.hasAtLeastOneRemoteContactDevice()
        } else if let groupDiscussion = discussion as? PersistedGroupDiscussion {
            return !groupDiscussion.hasAtLeastOneRemoteContactDevice()
        } else {
            return true
        }
    }

}


// MARK: - CustomQLPreviewControllerDelegate

extension SingleDiscussionViewController: QLPreviewControllerDelegate {
    
    func previewController(_ controller: QLPreviewController, transitionViewFor item: QLPreviewItem) -> UIView? {
        guard let filesViewer = self.filesViewer else { assertionFailure(); return nil }
        guard let indexPath = filesViewer.cellIndexPath else { assertionFailure(); return nil }
        guard let messageCell = self.collectionView.cellForItem(at: indexPath) as? MessageCollectionViewCell else { return nil }
        let attachmentIndex = controller.currentPreviewItemIndex
        guard attachmentIndex < filesViewer.shownFyleMessageJoins.count else { assertionFailure(); return nil }
        let dismissedFyleMessageJoin = filesViewer.shownFyleMessageJoins[attachmentIndex]
        let thumbnailView = messageCell.thumbnailViewOfFyleMessageJoinWithStatus(dismissedFyleMessageJoin)
        return thumbnailView
    }
    
    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        showAccessoryView()
        self.filesViewer = nil
    }
    
}


// MARK: - UIAdaptivePresentationControllerDelegate

extension SingleDiscussionViewController: UIAdaptivePresentationControllerDelegate {

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        // This method is typically called when the user dismissed the modal VC presented in order to show the infos of a particular message.
        // This method is also called when the user the user dismissed the SentMessageInfosViewController by tapping the back button, since we call this method "by hand" in that case.
        showAccessoryView()
    }
}


// MARK: Stuff

extension SingleDiscussionViewController {

    
    /// We observe notifications of deleted fyle message joins (i.e., attachments) so as to be able to dismiss the File Viewer if:
    /// - there is one presented ;-)
    /// - it is currently configured to show one of the deleted attachments
    /// This typically occurs for attachments with limited visibility. The first time we tap on such an attachment, the counter starts.  When it is over, we delete de whole message, including the attachments.
    /// In that case, we do not allow the user to continue viewing any of those attachments so we dismiss the file viewer.
    private func observeDeletedFyleMessageJoinNotifications() {
        let NotificationName = NSNotification.Name.NSManagedObjectContextDidSave
        let token = NotificationCenter.default.addObserver(forName: NotificationName, object: nil, queue: nil) { [weak self] (notification) in
            guard let filesViewer = self?.filesViewer else { return }

            var objectIDs = Set<NSManagedObjectID>()
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
            let shownObjectIDs = Set(filesViewer.shownFyleMessageJoins.map({ $0.objectID }))
            guard !objectIDs.isDisjoint(with: shownObjectIDs) else { return }
            DispatchQueue.main.async {
                (self?.presentedViewController as? QLPreviewController)?.dismiss(animated: true, completion: {
                    self?.filesViewer = nil
                })
            }
        }
        observationTokens.append(token)
    }
    
    
    /// If a received message gets deleted (e.g., after its visibility expires), we check whether it was "under" the
    /// system message indicating the number of new messages. If this is the case, we must update (potentially delete)
    /// the system message.
    private func observeCertainMessageDeletionToUpdateNumberOfNewMessagesSystemMessage() {
        observationTokens.append(ObvMessengerInternalNotification.observePersistedMessageReceivedWasDeleted(queue: OperationQueue.main) { [weak self] (objectID, _, _, sortIndex, _) in
            guard let _self = self else { return }
            guard let numberOfNewMessagesSystemMessage = try? PersistedMessageSystem.getNumberOfNewMessagesSystemMessage(in: _self.discussion) else { return }
            guard _self.objectIDsOfNewMessages.contains(objectID) else { return }
            // If we reach this point, the system message of type 'numberOfNewMessages' should be updated (potentially deleted).
            _self.objectIDsOfNewMessages.remove(objectID)
            numberOfNewMessagesSystemMessage.updateAndPotentiallyDeleteNumberOfUnreadReceivedMessagesSystemMessage(newNumberOfUnreadReceivedMessages: _self.objectIDsOfNewMessages.count)
        })
        observationTokens.append(ObvMessengerInternalNotification.observePersistedMessageSystemWasDeleted(queue: OperationQueue.main) { [weak self] (objectID, _) in
            guard let _self = self else { return }
            guard let numberOfNewMessagesSystemMessage = try? PersistedMessageSystem.getNumberOfNewMessagesSystemMessage(in: _self.discussion) else { return }
            guard _self.objectIDsOfNewMessages.contains(objectID) else { return }
            // If we reach this point, the system message of type 'numberOfNewMessages' should be updated (potentially deleted).
            _self.objectIDsOfNewMessages.remove(objectID)
            numberOfNewMessagesSystemMessage.updateAndPotentiallyDeleteNumberOfUnreadReceivedMessagesSystemMessage(newNumberOfUnreadReceivedMessages: _self.objectIDsOfNewMessages.count)
        })
    }
    
}
