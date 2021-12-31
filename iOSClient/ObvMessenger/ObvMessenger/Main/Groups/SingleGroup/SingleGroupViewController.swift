/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import ObvEngine
import ObvTypes
import SwiftUI
import ObvMetaManager

class SingleGroupViewController: UIViewController {

    // Views
    
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var mainStackView: UIStackView!
    
    @IBOutlet weak var topStackView: UIStackView!
    @IBOutlet weak var circlePlaceholder: UIView!
    @IBOutlet weak var titleLabel: UILabel!
    
    @IBOutlet weak var membersStackView: UIStackView!
    @IBOutlet weak var membersLabel: UILabel!
    @IBOutlet weak var membersLeadingPaddingConstraint: NSLayoutConstraint!
    @IBOutlet weak var noMemberView: UIView!
    @IBOutlet weak var noMemberLabel: UILabel!
    @IBOutlet weak var memberLabelLeadingPaddingConstraint: NSLayoutConstraint!
    
    @IBOutlet weak var pendingMembersStackView: UIStackView!
    @IBOutlet weak var pendingMembersLabel: UILabel!
    @IBOutlet weak var pendingMembersLeadingPaddingConstraint: NSLayoutConstraint!
    @IBOutlet weak var noPendingMemberLabel: UILabel!
    @IBOutlet weak var noPendingMemberView: UIView!
    @IBOutlet weak var noPendingMemberLeadingPaddingConstraint: NSLayoutConstraint!
    
    @IBOutlet weak var actionsStackView: UIStackView!
    @IBOutlet weak var actionsLabel: UILabel!
    @IBOutlet weak var refreshGroupView: UIView!
    @IBOutlet weak var refreshGroupButton: UIButton!
    @IBOutlet weak var deleteOrLeaveGroupView: UIView!
    @IBOutlet weak var deleteOrLeaveGroupButton: UIButton!
    
    @IBOutlet weak var startDiscussionButton: UIButton!
    
    @IBOutlet weak var olvidCardVersionChooserPlaceholder: UIView!
    private var olvidCardChooserView: ExplanationCardView!
    private var updateOlvidCardButton: UIButton!
    
    @IBOutlet weak var redOlvidCardPlaceholder: UIView!
    private var redOlvidCardView: OlvidCardView!

    @IBOutlet weak var greenOlvidCardPlaceholder: UIView!
    private var greenOlvidCardView: OlvidCardView!

    private var latestOlvidCardDiscardButton: UIButton!
    private var latestOlvidCardPublishButton: UIButton!
    
    @IBOutlet weak var membersManagementStackView: UIStackView!
    @IBOutlet weak var addMembersButton: UIButton!
    @IBOutlet weak var removeMembersButton: ObvButton!
    
    private static let errorDomain = "SingleGroupViewController"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    // Delegate
    
    weak var delegate: SingleGroupViewControllerDelegate?
    
    // Model

    let persistedContactGroup: PersistedContactGroup
    private(set) var obvContactGroup: ObvContactGroup!
    
    
    // Subviews set in viewDidLoad
    
    var circledInitials: CircledInitials!
    
    // Other constants
    
    private var notificationTokens = [NSObjectProtocol]()
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))
    private let customSpacingBetweenSections: CGFloat = 24.0
    private let customSpacingAfterTopStackView: CGFloat = 32.0
    private let sectionLabelsLeadingPaddingConstraint: CGFloat = 20.0
    private let olvidCardsSideConstants: CGFloat = 16.0
    
    // Initializer
    
    init(persistedContactGroupOwned: PersistedContactGroupOwned) throws {
        self.persistedContactGroup = persistedContactGroupOwned
        super.init(nibName: nil, bundle: nil)
        guard let ownedIdentity = persistedContactGroupOwned.ownedIdentity else {
            throw SingleGroupViewController.makeError(message: "Could not find owned identity. This is ok if it was just deleted")
        }
        try self.obvContactGroup = obvEngine.getContactGroupOwned(groupUid: persistedContactGroupOwned.groupUid, ownedCryptoId: ownedIdentity.cryptoId)
    }

    init(persistedContactGroupJoined: PersistedContactGroupJoined) throws {
        self.persistedContactGroup = persistedContactGroupJoined
        super.init(nibName: nil, bundle: nil)
        guard let ownedIdentity = persistedContactGroupJoined.ownedIdentity else {
            throw SingleGroupViewController.makeError(message: "Could not find owned identity. This is ok if it was just deleted")
        }
        guard let owner = persistedContactGroupJoined.owner else {
            os_log("Could not find owner. This is ok if it was just deleted.", log: log, type: .error)
            throw SingleGroupViewController.makeError(message: "Could not find owner. This is ok if it was just deleted.")
        }
        try self.obvContactGroup = obvEngine.getContactGroupJoined(groupUid: persistedContactGroupJoined.groupUid, groupOwner: owner.cryptoId, ownedCryptoId: ownedIdentity.cryptoId)
    }

    convenience init(persistedContactGroup: PersistedContactGroup) throws {
        if let groupJoined = persistedContactGroup as? PersistedContactGroupJoined {
            try self.init(persistedContactGroupJoined: groupJoined)
        } else if let groupOwned = persistedContactGroup as? PersistedContactGroupOwned {
            try self.init(persistedContactGroupOwned: groupOwned)
        } else {
            throw NSError()
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

}


// MARK: - UIViewController lifecycle

extension SingleGroupViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        extendedLayoutIncludesOpaqueBars = true
        self.navigationItem.largeTitleDisplayMode = .never

        view.backgroundColor = AppTheme.shared.colorScheme.systemBackground
        scrollView.alwaysBounceVertical = true
        mainStackView.setCustomSpacing(customSpacingAfterTopStackView, after: topStackView)
        extendedLayoutIncludesOpaqueBars = true
        
        circlePlaceholder.backgroundColor = .clear
        titleLabel.textColor = AppTheme.shared.colorScheme.label

        circledInitials = (Bundle.main.loadNibNamed(CircledInitials.nibName, owner: nil, options: nil)!.first as! CircledInitials)
        circledInitials.withShadow = true
        circlePlaceholder.addSubview(circledInitials)
        circlePlaceholder.pinAllSidesToSides(of: circledInitials)

        membersLabel.textColor = AppTheme.shared.colorScheme.label
        membersLabel.text = Strings.members
        membersLeadingPaddingConstraint.constant = sectionLabelsLeadingPaddingConstraint
        noMemberView.backgroundColor = AppTheme.shared.colorScheme.tertiarySystemBackground
        noMemberLabel.accessibilityIdentifier = "noMemberLabel"
        noMemberLabel.text = CommonString.Word.None
        noMemberLabel.textColor = AppTheme.shared.colorScheme.secondaryLabel
        memberLabelLeadingPaddingConstraint.constant = sectionLabelsLeadingPaddingConstraint
        mainStackView.setCustomSpacing(customSpacingBetweenSections, after: membersStackView)
        
        pendingMembersLabel.textColor = AppTheme.shared.colorScheme.label
        pendingMembersLabel.text = Strings.pendingMembers
        pendingMembersLeadingPaddingConstraint.constant = sectionLabelsLeadingPaddingConstraint
        noPendingMemberView.backgroundColor = AppTheme.shared.colorScheme.tertiarySystemBackground
        noPendingMemberLabel.text = CommonString.Word.None
        noPendingMemberLabel.textColor = AppTheme.shared.colorScheme.secondaryLabel
        noPendingMemberLeadingPaddingConstraint.constant = sectionLabelsLeadingPaddingConstraint
        
        olvidCardVersionChooserPlaceholder.backgroundColor = .clear
        olvidCardChooserView = (Bundle.main.loadNibNamed(ExplanationCardView.nibName, owner: nil, options: nil)!.first as! ExplanationCardView)
        olvidCardChooserView.titleLabel.text = Strings.OlvidCardChooser.title
        olvidCardChooserView.bodyLabel.text = Strings.OlvidCardChooser.body
        olvidCardChooserView.iconImageView.image = UIImage(named: "account_card_no_borders")
        olvidCardChooserView.iconImageView.tintColor = AppTheme.shared.colorScheme.secondaryLabel
        updateOlvidCardButton = ObvButton()
        updateOlvidCardButton.setTitle(CommonString.Word.Update, for: .normal)
        updateOlvidCardButton.addTarget(self, action: #selector(acceptPublishedCardButtonTapped), for: .touchUpInside)
        olvidCardChooserView.addButton(updateOlvidCardButton)
        olvidCardVersionChooserPlaceholder.addSubview(olvidCardChooserView)
        olvidCardVersionChooserPlaceholder.pinAllSidesToSides(of: olvidCardChooserView, sideConstants: olvidCardsSideConstants)

        redOlvidCardPlaceholder.backgroundColor = .clear
        redOlvidCardView = (Bundle.main.loadNibNamed(OlvidCardView.nibName, owner: nil, options: nil)!.first as! OlvidCardView)
        redOlvidCardPlaceholder.addSubview(redOlvidCardView)
        redOlvidCardPlaceholder.pinAllSidesToSides(of: redOlvidCardView, sideConstants: olvidCardsSideConstants)
        
        greenOlvidCardPlaceholder.backgroundColor = .clear
        greenOlvidCardView = (Bundle.main.loadNibNamed(OlvidCardView.nibName, owner: nil, options: nil)!.first as! OlvidCardView)
        greenOlvidCardPlaceholder.addSubview(greenOlvidCardView)
        greenOlvidCardPlaceholder.pinAllSidesToSides(of: greenOlvidCardView, sideConstants: olvidCardsSideConstants)

        actionsLabel.textColor = AppTheme.shared.colorScheme.label
        actionsLabel.text = CommonString.Word.Actions
        actionsLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        
        switch obvContactGroup.groupType {
        case .owned:
            refreshGroupView.isHidden = true
        case .joined:
            refreshGroupView.backgroundColor = AppTheme.shared.colorScheme.tertiarySystemBackground
            refreshGroupButton.setTitle(Strings.refreshGroupButton.title, for: .normal)
            refreshGroupButton.addTarget(self, action: #selector(refreshGroupButtonTapped), for: .touchUpInside)
        }
        
        deleteOrLeaveGroupView.backgroundColor = AppTheme.shared.colorScheme.tertiarySystemBackground
        deleteOrLeaveGroupButton.setTitleColor(.red, for: .normal)
        switch obvContactGroup.groupType {
        case .owned:
            deleteOrLeaveGroupButton.setTitle(CommonString.Title.deleteGroup, for: .normal)
            deleteOrLeaveGroupButton.addTarget(self, action: #selector(deleteGroupButtonTapped), for: .touchUpInside)
        case .joined:
            deleteOrLeaveGroupButton.setTitle(CommonString.Title.leaveGroup, for: .normal)
            deleteOrLeaveGroupButton.addTarget(self, action: #selector(leaveGroupButtonTapped), for: .touchUpInside)
        }

        configureNavigationBarTitle()
        configureViewsBasedOnPersistedContactGroup()
        configureTheOlvidCards(animated: false)
        
        do {
            try configureAndAddMembersTVC()
            try configureAndAddPendingMembersTVC()
        } catch {
            os_log("Could not configure a TVC", log: log, type: .fault)
        }
     
        switch obvContactGroup.groupType {
        case .joined:
            membersManagementStackView.isHidden = true
        case .owned:
            membersManagementStackView.isHidden = false
            addMembersButton.setTitle(Strings.addMembers, for: .normal)
            addMembersButton.titleLabel?.lineBreakMode = .byWordWrapping
            addMembersButton.titleLabel?.textAlignment = .center
            addMembersButton.addTarget(self, action: #selector(addMembersButtonTapped), for: .touchUpInside)
            removeMembersButton.setTitle(Strings.removeMembers, for: .normal)
            removeMembersButton.titleLabel?.lineBreakMode = .byWordWrapping
            removeMembersButton.titleLabel?.textAlignment = .center
            removeMembersButton.addTarget(self, action: #selector(removeMembersButtonTapped), for: .touchUpInside)
        }
        
        observePersistedContactGroupChanges()
        observeEngineNotifications()
        observeIdentityColorStyleDidChangeNotifications()
        
        // We refresh the group each time we load this view controller
        if obvContactGroup.groupType == .joined {
            refreshGroup()
        }
    }

    private func configureNavigationBarTitle() {
        var items: [UIBarButtonItem] = []

        items += [UIBarButtonItem(barButtonSystemItem: UIBarButtonItem.SystemItem.compose, target: self, action: #selector(editGroupButtonTapped))]

        if !persistedContactGroup.contactIdentities.isEmpty {
            items += [UIBarButtonItem(systemName: ObvSystemIcon.phoneFill.systemName, style: .plain, target: self, action: #selector(callButtonTapped))]
        }

        self.navigationItem.rightBarButtonItems = items
    }
    
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        guard obvContactGroup.groupType == .joined else { return }
        
        ObvStack.shared.performBackgroundTask { [weak self] (context) in
            guard let _self = self else { return }
            do {
                guard let writablePersistedContactGroupJoined = try? PersistedContactGroupJoined.get(objectID: _self.persistedContactGroup.objectID, within: context) as? PersistedContactGroupJoined else { return }
                if writablePersistedContactGroupJoined.status == .unseenPublishedDetails {
                    writablePersistedContactGroupJoined.setStatus(to: .seenPublishedDetails)
                }
                try context.save(logOnFailure: _self.log)
            } catch {
                os_log("Could not update the status of a joined contact group", log: _self.log, type: .error)
            }
        }

    }
    
}


// MARK: - Helpers

extension SingleGroupViewController {
    
    
    private func configureViewsBasedOnPersistedContactGroup() {
        self.title = self.persistedContactGroup.displayName
        if let photoURL = self.persistedContactGroup.displayPhotoURL {
            circledInitials.showPhoto(fromUrl: photoURL)
        } else {
            circledInitials.showImage(fromImage: AppTheme.shared.images.groupImage)
        }
        circledInitials.identityColors = AppTheme.shared.groupColors(forGroupUid: persistedContactGroup.groupUid)
        titleLabel.text = self.persistedContactGroup.displayName
    }
    
    private func configureAndAddMembersTVC() throws {
        
        let predicate = PersistedObvContactIdentity.getPredicateForContactGroup(self.persistedContactGroup)
        let contactsTVC = ContactsTableViewController(showOwnedIdentityWithCryptoId: nil, disableContactsWithoutDevice: false, allowDeletion: false)
        contactsTVC.cellBackgroundColor = AppTheme.shared.colorScheme.tertiarySystemBackground
        contactsTVC.predicate = predicate
        contactsTVC.delegate = self
        if obvContactGroup.groupType == .joined {
            let ownerCryptoId = obvContactGroup.groupOwner.cryptoId
            contactsTVC.titleChipTextForIdentity = [ownerCryptoId: CommonString.Word.Admin]
        }
        
        let blockOnNewHeight = { [weak self] (height: CGFloat) in
            _ = self?.noMemberView.isHidden = !(height == 0)
        }
        contactsTVC.constraintHeightToContentHeight(blockOnNewHeight: blockOnNewHeight)
        contactsTVC.view.translatesAutoresizingMaskIntoConstraints = false

        contactsTVC.willMove(toParent: self)
        self.addChild(contactsTVC)
        contactsTVC.didMove(toParent: self)
        
        self.membersStackView.insertArrangedSubview(contactsTVC.view, at: 1)
        
    }
    
    
    private func configureAndAddPendingMembersTVC() throws {
        
        let frc = try PersistedPendingGroupMember.getFetchedResultsControllerForContactGroup(self.persistedContactGroup)
        let cellSelectionStyle = obvContactGroup.groupType == .joined ? UITableViewCell.SelectionStyle.none : UITableViewCell.SelectionStyle.default
        let pendingMembersTVC = PendingGroupMembersTableViewController(fetchedResultsController: frc, cellSelectionStyle: cellSelectionStyle)
        pendingMembersTVC.cellBackgroundColor = AppTheme.shared.colorScheme.tertiarySystemBackground
        pendingMembersTVC.delegate = self
        
        let blockOnNewHeight = { [weak self] (height: CGFloat) in
            _ = self?.noPendingMemberView.isHidden = !(height == 0)
        }
        pendingMembersTVC.constraintHeightToContentHeight(blockOnNewHeight: blockOnNewHeight)
        pendingMembersTVC.view.translatesAutoresizingMaskIntoConstraints = false
        
        pendingMembersTVC.willMove(toParent: self)
        self.addChild(pendingMembersTVC)
        pendingMembersTVC.didMove(toParent: self)

        self.pendingMembersStackView.addArrangedSubview(pendingMembersTVC.view)
        
    }
    
}


// MARK: - Reacting to notifications

extension SingleGroupViewController {
    
    private func observeIdentityColorStyleDidChangeNotifications() {
        let token = ObvMessengerInternalNotification.observeIdentityColorStyleDidChange(queue: OperationQueue.main) { [weak self] in
            self?.configureViewsBasedOnPersistedContactGroup()
            self?.configureTheOlvidCards(animated: false)
        }
        self.notificationTokens.append(token)
    }

    private func observePersistedContactGroupChanges() {
        let NotificationName = Notification.Name.NSManagedObjectContextDidSave
        let token = NotificationCenter.default.addObserver(forName: NotificationName, object: nil, queue: nil) { [weak self] (notification) in
            guard let _self = self else { return }
            guard let context = notification.object as? NSManagedObjectContext else { return }
            guard context.concurrencyType != .mainQueueConcurrencyType else { return }
            context.performAndWait {
                guard let userInfo = notification.userInfo else { return }
                guard let updatedObjects = userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject> else { return }
                guard !updatedObjects.isEmpty else { return }
                let updatedContactGroups = updatedObjects.filter { $0 is PersistedContactGroup } as! Set<PersistedContactGroup>
                guard !updatedContactGroups.isEmpty else { return }
                let objectIDs = updatedContactGroups.map { $0.objectID }
                guard objectIDs.contains(_self.persistedContactGroup.objectID) else { return }
                DispatchQueue.main.async {
                    _self.persistedContactGroup.managedObjectContext?.mergeChanges(fromContextDidSave: notification)
                    _self.configureViewsBasedOnPersistedContactGroup()
                    _self.configureNavigationBarTitle()
                }
            }
            
        }
        notificationTokens.append(token)
    }

    
    private func observeEngineNotifications() {
        notificationTokens.append(ObvEngineNotificationNew.observePublishedPhotoOfContactGroupJoinedHasBeenUpdated(within: NotificationCenter.default, queue: OperationQueue.main) { [weak self] obvContactGroup in
            guard let _self = self else { return }
            guard _self.obvContactGroup.ownedIdentity == obvContactGroup.ownedIdentity else { return }
            guard _self.obvContactGroup.groupUid == obvContactGroup.groupUid else { return }
            self?.obvContactGroup = obvContactGroup
            self?.configureTheOlvidCards(animated: true)
        })
        do {
            let NotificationType = ObvEngineNotification.ContactGroupOwnedDiscardedLatestDetails.self
            let token = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: nil) { [weak self] (notification) in
                guard let _self = self else { return }
                guard let obvContactGroup = NotificationType.parse(notification) else { return }
                DispatchQueue.main.async {
                    guard _self.obvContactGroup.ownedIdentity == obvContactGroup.ownedIdentity else { return }
                    guard _self.obvContactGroup.groupUid == obvContactGroup.groupUid else { return }
                    self?.obvContactGroup = obvContactGroup
                    self?.configureTheOlvidCards(animated: true)
                }
            }
            notificationTokens.append(token)
        }
        do {
            let NotificationType = ObvEngineNotification.ContactGroupOwnedHasUpdatedLatestDetails.self
            let token = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: nil) { [weak self] (notification) in
                guard let _self = self else { return }
                guard let obvContactGroup = NotificationType.parse(notification) else { return }
                DispatchQueue.main.async {
                    guard _self.obvContactGroup.ownedIdentity == obvContactGroup.ownedIdentity else { return }
                    guard _self.obvContactGroup.groupUid == obvContactGroup.groupUid else { return }
                    self?.obvContactGroup = obvContactGroup
                    self?.configureTheOlvidCards(animated: true)
                }
            }
            notificationTokens.append(token)
        }
        do {
            let NotificationType = ObvEngineNotification.ContactGroupHasUpdatedPublishedDetails.self
            let token = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: nil) { [weak self] (notification) in
                guard let _self = self else { return }
                guard let obvContactGroup = NotificationType.parse(notification) else { return }
                DispatchQueue.main.async {
                    guard _self.obvContactGroup.ownedIdentity == obvContactGroup.ownedIdentity else { return }
                    guard _self.obvContactGroup.groupUid == obvContactGroup.groupUid else { return }
                    self?.obvContactGroup = obvContactGroup
                    self?.configureTheOlvidCards(animated: true)
                }
            }
            notificationTokens.append(token)
        }
        do {
            let NotificationType = ObvEngineNotification.ContactGroupJoinedHasUpdatedTrustedDetails.self
            let token = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: nil) { [weak self] (notification) in
                guard let _self = self else { return }
                guard let obvContactGroup = NotificationType.parse(notification) else { return }
                DispatchQueue.main.async {
                    guard _self.obvContactGroup.ownedIdentity == obvContactGroup.ownedIdentity else { return }
                    guard _self.obvContactGroup.groupUid == obvContactGroup.groupUid else { return }
                    self?.obvContactGroup = obvContactGroup
                    self?.configureTheOlvidCards(animated: true)
                }
            }
            notificationTokens.append(token)
        }
        do {
            let NotificationType = ObvEngineNotification.ContactGroupHasUpdatedPendingMembersAndGroupMembers.self
            let token = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: nil) { [weak self] (notification) in
                guard let _self = self else { return }
                guard let obvContactGroup = NotificationType.parse(notification) else { return }
                DispatchQueue.main.async {
                    guard _self.obvContactGroup.ownedIdentity == obvContactGroup.ownedIdentity else { return }
                    guard _self.obvContactGroup.groupUid == obvContactGroup.groupUid else { return }
                    self?.obvContactGroup = obvContactGroup
                }
            }
            notificationTokens.append(token)
        }
        do {
            let NotificationType = ObvEngineNotification.ContactGroupDeleted.self
            let token = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: nil) { [weak self] (notification) in
                guard let _self = self else { return }
                guard let (obvOwnedIdentity, _, groupUid) = NotificationType.parse(notification) else { return }
                DispatchQueue.main.async {
                    guard _self.obvContactGroup.ownedIdentity == obvOwnedIdentity else { return }
                    guard _self.obvContactGroup.groupUid == groupUid else { return }
                    if _self.navigationController?.presentingViewController != nil {
                        _self.navigationController?.dismiss(animated: true, completion: nil)
                    } else {
                        _self.navigationController?.popViewController(animated: true)
                    }
                }
            }
            notificationTokens.append(token)
        }

    }

}

// MARK: - Editing the group

extension SingleGroupViewController {
    
    @objc func editGroupButtonTapped() {
        
        switch obvContactGroup.groupType {
        case .joined:
            
            let alert = UIAlertController(title: Strings.GroupName.title, message: nil, preferredStyle: .alert)
            alert.addTextField { [weak self] (textField) in
                guard let _self = self else { return }
                textField.font = UIFont.preferredFont(forTextStyle: UIFont.TextStyle.headline)
                textField.autocapitalizationType = .words
                textField.text = _self.persistedContactGroup.displayName
            }
            guard let textField = alert.textFields?.first else { return }
            let removeNickname = UIAlertAction(title: CommonString.removeNickname, style: .destructive) { [weak self] (_) in
                self?.removeGroupNameCustom()
            }
            let cancelAction = UIAlertAction(title: CommonString.Word.Cancel, style: UIAlertAction.Style.cancel)
            let okAction = UIAlertAction(title: CommonString.Word.Ok, style: UIAlertAction.Style.default) { [weak self] (action) in
                if let newGroupName = textField.text, !newGroupName.isEmpty {
                    self?.setGroupNameCustom(to: newGroupName)
                }
            }
            alert.addAction(removeNickname)
            alert.addAction(okAction)
            alert.addAction(cancelAction)
            self.present(alert, animated: true)
            
        case .owned:
            let ownedGroupEditionFlowVC = OwnedGroupEditionFlowViewController(
                ownedCryptoId: obvContactGroup.ownedIdentity.cryptoId,
                editionType: .editGroupDetails(obvContactGroup: obvContactGroup))
            DispatchQueue.main.async { [weak self] in
                self?.present(ownedGroupEditionFlowVC, animated: true)
            }
        }

    }

    @objc func callButtonTapped() {
        if let groupId = try? persistedContactGroup.getGroupId() {
            let contactIdentities = persistedContactGroup.contactIdentities

            ObvMessengerInternalNotification.userWantsToSelectAndCallContacts(contactIDs: contactIdentities.map({ $0.typedObjectID }), groupId: groupId).postOnDispatchQueue()
        }
    }

    private func setGroupNameCustom(to groupNameCustom: String) {
        guard obvContactGroup.groupType == .joined else { return }
        ObvStack.shared.performBackgroundTask { [weak self] (context) in
            guard let _self = self else { return }
            do {
                guard let writablePersistedContactGroupJoined = try PersistedContactGroupJoined.get(objectID: _self.persistedContactGroup.objectID, within: context) as? PersistedContactGroupJoined else { return }
                try writablePersistedContactGroupJoined.setGroupNameCustom(to: groupNameCustom)
                try context.save(logOnFailure: _self.log)
            } catch {
                os_log("Could not change group name", log: _self.log, type: .error)
            }
        }
    }
    
    private func removeGroupNameCustom() {
        guard obvContactGroup.groupType == .joined else { return }
        ObvStack.shared.performBackgroundTask { [weak self] (context) in
            guard let _self = self else { return }
            do {
                guard let writablePersistedContactGroupJoined = try PersistedContactGroupJoined.get(objectID: _self.persistedContactGroup.objectID, within: context) as? PersistedContactGroupJoined else { return }
                try writablePersistedContactGroupJoined.removeGroupNameCustom()
                try context.save(logOnFailure: _self.log)
            } catch {
                os_log("Could not change group name", log: _self.log, type: .error)
            }
        }
    }
}


// MARK: - ContactsTableViewControllerDelegate

extension SingleGroupViewController: ContactsTableViewControllerDelegate {

    func userDidSelectOwnedIdentity() {
        // Never called
    }
    
    func userWantsToDeleteContact(with: ObvCryptoId, forOwnedCryptoId: ObvCryptoId, completionHandler: @escaping (Bool) -> Void) {
        assertionFailure("Should never be called")
    }

    func userDidSelect(_ obvContactIdentity: PersistedObvContactIdentity) {
        delegate?.userWantsToDisplay(persistedContact: obvContactIdentity, within: navigationController)
    }
    
    func userDidDeselect(_: PersistedObvContactIdentity) {}
    
    func userAskedToDelete(_: PersistedObvContactIdentity, completionHandler: @escaping (Bool) -> Void) {}
    
    
}


// MARK: - PendingGroupMembersTableViewControllerDelegate

extension SingleGroupViewController: PendingGroupMembersTableViewControllerDelegate {
    
    func userDidSelect(_ persistedPendingGroupMember: PersistedPendingGroupMember, completionHandler: (() -> Void)?) {
        guard obvContactGroup.groupType == .owned else { return }
        sendAnotherInvitation(to: persistedPendingGroupMember, confirmed: false, completionHandler: completionHandler)

    }

    
    private func sendAnotherInvitation(to persistedPendingGroupMember: PersistedPendingGroupMember, confirmed: Bool, completionHandler: (() -> Void)?) {
        let currentPendingMembers = obvContactGroup.pendingGroupMembers.map { $0.cryptoId }
        guard currentPendingMembers.contains(persistedPendingGroupMember.cryptoId) else { return }
        
        if confirmed {
            
            try? obvEngine.reInviteContactToGroupOwned(groupUid: obvContactGroup.groupUid,
                                                       ownedCryptoId: obvContactGroup.ownedIdentity.cryptoId,
                                                       pendingGroupMember: persistedPendingGroupMember.cryptoId)
        } else {
            
            let alert = UIAlertController(title: Strings.reinviteContact.title,
                                          message: Strings.reinviteContact.message,
                                          preferredStyleForTraitCollection: self.traitCollection)
            
            alert.addAction(UIAlertAction(title: CommonString.Word.Send, style: .default, handler: { [weak self] (action) in
                self?.sendAnotherInvitation(to: persistedPendingGroupMember, confirmed: true, completionHandler: nil)
                completionHandler?()
            }))
            
            alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel, handler: { (_) in
                completionHandler?()
            }))
            DispatchQueue.main.async { [weak self] in
                self?.present(alert, animated: true, completion: nil)
            }

        }
        
    }
}

// MARK: - User actions

extension SingleGroupViewController {
    
    @IBAction func startDiscussionButtonTapped(_ sender: Any) {
        let discussion = self.persistedContactGroup.discussion
        assert(discussion.managedObjectContext == ObvStack.shared.viewContext)
        delegate?.userWantsToDisplay(persistedDiscussion: discussion)
    }
 
    @objc func deleteGroupButtonTapped() {
        guard obvContactGroup.groupType == .owned else { return }
        let NotificationType = MessengerInternalNotification.UserWantsToDeleteOwnedContactGroup.self
        let userInfo = [NotificationType.Key.ownedCryptoId: obvContactGroup.ownedIdentity.cryptoId,
                        NotificationType.Key.groupUid: obvContactGroup.groupUid] as [String: Any]
        NotificationCenter.default.post(name: NotificationType.name, object: nil, userInfo: userInfo)
    }
    
    @objc func leaveGroupButtonTapped() {
        guard obvContactGroup.groupType == .joined else { return }
        guard let deleteOrLeaveGroupButton = self.deleteOrLeaveGroupButton else { return }
        let NotificationType = MessengerInternalNotification.UserWantsToLeaveJoinedContactGroup.self
        let userInfo: [String: Any] = [
            NotificationType.Key.ownedCryptoId: obvContactGroup.ownedIdentity.cryptoId,
            NotificationType.Key.groupOwner: obvContactGroup.groupOwner.cryptoId,
            NotificationType.Key.groupUid: obvContactGroup.groupUid,
            NotificationType.Key.sourceView: deleteOrLeaveGroupButton,
        ]
        NotificationCenter.default.post(name: NotificationType.name, object: nil, userInfo: userInfo)
    }

    @objc func refreshGroupButtonTapped() {
        refreshGroup()
    }
    
    /// This method is called from viewDidLoad and each time the user taps the refresh button
    private func refreshGroup() {
        guard obvContactGroup.groupType == .joined else { return }
        let notification = ObvMessengerInternalNotification.userWantsToRefreshContactGroupJoined(obvContactGroup: self.obvContactGroup)
        notification.postOnDispatchQueue()
    }
}


// MARK: - Reacting to button taps

extension SingleGroupViewController {
    
    @objc func acceptPublishedCardButtonTapped() {
        guard obvContactGroup.groupType == .joined else { return }
        do {
           try obvEngine.trustPublishedDetailsOfJoinedContactGroup(ownedCryptoId: obvContactGroup.ownedIdentity.cryptoId,
                                                                   groupUid: obvContactGroup.groupUid,
                                                                   groupOwner: obvContactGroup.groupOwner.cryptoId)
        } catch {
            os_log("Could not accept published details of contact group joined", log: log, type: .error)
        }
    }
    
    
    @objc func discardLatestDetails() {
        guard obvContactGroup.groupType == .owned else { return }
        do {
            try obvEngine.discardLatestDetailsOfOwnedContactGroup(ownedCryptoId: obvContactGroup.ownedIdentity.cryptoId,
                                                                  groupUid: obvContactGroup.groupUid)
        } catch {
            os_log("Could not discard latest contact group details", log: log, type: .fault)
            return
        }
    }
    
    
    @objc func publishLatestDetails() {
        guard obvContactGroup.groupType == .owned else { return }
        do {
            try obvEngine.publishLatestDetailsOfOwnedContactGroup(ownedCryptoId: obvContactGroup.ownedIdentity.cryptoId,
                                                                  groupUid: obvContactGroup.groupUid)
        } catch {
            os_log("Could not publish latest details of owned contact group", log: log, type: .error)
        }
    }
    
    
    @objc func addMembersButtonTapped() {
        guard obvContactGroup.groupType == .owned else { return }
        let currentGroupMembers = Set(obvContactGroup.groupMembers.map { $0.cryptoId })
        let currentPendingMembers = obvContactGroup.pendingGroupMembers.map { $0.cryptoId }
        let groupMembersAndPendingMembers = currentGroupMembers.union(currentPendingMembers)
        let ownedGroupEditionFlowVC = OwnedGroupEditionFlowViewController(ownedCryptoId: obvContactGroup.ownedIdentity.cryptoId, editionType: .addGroupMembers(groupUid: obvContactGroup.groupUid, currentGroupMembers: groupMembersAndPendingMembers))
        DispatchQueue.main.async { [weak self] in
            self?.present(ownedGroupEditionFlowVC, animated: true)
        }
    }
    
    
    @objc func removeMembersButtonTapped() {
        guard obvContactGroup.groupType == .owned else { return }
        let currentGroupMembers = Set(obvContactGroup.groupMembers.map { $0.cryptoId })
        let currentPendingMembers = obvContactGroup.pendingGroupMembers.map { $0.cryptoId }
        let groupMembersAndPendingMembers = currentGroupMembers.union(currentPendingMembers)
        let ownedGroupEditionFlowVC = OwnedGroupEditionFlowViewController(ownedCryptoId: obvContactGroup.ownedIdentity.cryptoId, editionType: .removeGroupMembers(groupUid: obvContactGroup.groupUid, currentGroupMembers: groupMembersAndPendingMembers))
        DispatchQueue.main.async { [weak self] in
            self?.present(ownedGroupEditionFlowVC, animated: true)
        }
    }

}


// MARK: - Configuring the OlvidCards

extension SingleGroupViewController {
    
    func configureTheOlvidCards(animated: Bool) {
        guard self.olvidCardChooserView != nil else { return }
        guard self.greenOlvidCardView != nil else { return }
        guard self.redOlvidCardView != nil else { return }
        
        let animator1 = UIViewPropertyAnimator(duration: 0.4, curve: .easeInOut)
        let animator2 = UIViewPropertyAnimator(duration: 0.4, curve: .easeInOut)

        let animation1: () -> Void
        let animation2: () -> Void

        switch obvContactGroup.groupType {
        case .joined:
            
            if obvContactGroup.publishedDetailsAndTrustedOrLatestDetailsAreEquivalentForTheUser() {
                // If the published details are identical to the trusted details, the first card displays these details. The second is hidden
                
                animation1 = { [weak self] in
                    guard let _self = self else { return }
                    _self.redOlvidCardPlaceholder.alpha = 0
                    _self.greenOlvidCardPlaceholder.alpha = 1
                    _self.olvidCardVersionChooserPlaceholder.alpha = 0
                    let cardTypeText = Strings.groupCard.uppercased()
                    _self.greenOlvidCardView.configure(with: _self.obvContactGroup.publishedObvGroupDetails,
                                                       groupUid: _self.persistedContactGroup.groupUid,
                                                       cardTypeText: cardTypeText,
                                                       cardTypeStyle: .green)
                }
                
                animation2 = { [weak self] in
                    guard let _self = self else { return }
                    _self.redOlvidCardPlaceholder.isHidden = true
                    _self.greenOlvidCardPlaceholder.isHidden = false
                    _self.olvidCardVersionChooserPlaceholder.isHidden = true
                }
                
            } else {
                // If the published details differ from the trusted details, the first card displays the published details, the second displays the trusted details
                
                animation2 = { [weak self] in
                    guard let _self = self else { return }
                    _self.redOlvidCardPlaceholder.alpha = 1
                    _self.greenOlvidCardPlaceholder.alpha = 1
                    _self.olvidCardVersionChooserPlaceholder.alpha = 1
                    _self.redOlvidCardView.configure(with: _self.obvContactGroup.publishedObvGroupDetails,
                                                     groupUid: _self.persistedContactGroup.groupUid,
                                                     cardTypeText: Strings.groupCardNew.uppercased(),
                                                     cardTypeStyle: .red)
                    _self.greenOlvidCardView.configure(with: _self.obvContactGroup.trustedOrLatestGroupDetails,
                                                       groupUid: _self.persistedContactGroup.groupUid,
                                                       cardTypeText: Strings.groupCardOnPhone.uppercased(),
                                                       cardTypeStyle: .green)
                    
                }
                animation1 = { [weak self] in
                    guard let _self = self else { return }
                    _self.redOlvidCardPlaceholder.isHidden = false
                    _self.greenOlvidCardPlaceholder.isHidden = false
                    _self.olvidCardVersionChooserPlaceholder.isHidden = false
                }
                
            }
            
        case .owned:
            
            if obvContactGroup.publishedDetailsAndTrustedOrLatestDetailsAreEquivalentForTheUser() {
                // The published details are identical to the latest details.
                // The first card is the only one shown and shows these details
                
                animation1 = { [weak self] in
                    guard let _self = self else { return }
                    _self.redOlvidCardPlaceholder.alpha = 0
                    _self.greenOlvidCardPlaceholder.alpha = 1
                    _self.olvidCardVersionChooserPlaceholder.alpha = 1
                    let cardTypeText = Strings.groupCard.uppercased()
                    _self.greenOlvidCardView.configure(with: _self.obvContactGroup.publishedObvGroupDetails,
                                                       groupUid: _self.persistedContactGroup.groupUid,
                                                       cardTypeText: cardTypeText,
                                                       cardTypeStyle: .green)
                }
                
                animation2 = { [weak self] in
                    guard let _self = self else { return }
                    _self.redOlvidCardPlaceholder.isHidden = true
                    _self.greenOlvidCardPlaceholder.isHidden = false
                    _self.olvidCardVersionChooserPlaceholder.isHidden = true
                }
                
            } else {
                // There are (unpublished) latest details.
                // The first card displays the latest details while the second card displays the published details
                
                animation2 = { [weak self] in
                    guard let _self = self else { return }
                    _self.redOlvidCardPlaceholder.alpha = 1
                    _self.greenOlvidCardPlaceholder.alpha = 1
                    _self.olvidCardVersionChooserPlaceholder.alpha = 0
                    if _self.latestOlvidCardDiscardButton == nil {
                        _self.latestOlvidCardDiscardButton = ObvButtonBorderless()
                        _self.latestOlvidCardDiscardButton.setTitle(CommonString.Word.Discard, for: .normal)
                        _self.latestOlvidCardDiscardButton.addTarget(self, action: #selector(_self.discardLatestDetails), for: .touchUpInside)
                        _self.redOlvidCardView.addButton(_self.latestOlvidCardDiscardButton)
                    }
                    if _self.latestOlvidCardPublishButton == nil {
                        _self.latestOlvidCardPublishButton = ObvButton()
                        _self.latestOlvidCardPublishButton.setTitle(CommonString.Word.Publish, for: .normal)
                        _self.latestOlvidCardPublishButton.addTarget(self, action: #selector(_self.publishLatestDetails), for: .touchUpInside)
                        _self.redOlvidCardView.addButton(_self.latestOlvidCardPublishButton)
                    }
                    _self.redOlvidCardView.configure(with: _self.obvContactGroup.trustedOrLatestGroupDetails,
                                                     groupUid: _self.persistedContactGroup.groupUid,
                                                     cardTypeText: Strings.groupCardUnpublished.uppercased(),
                                                     cardTypeStyle: .red)
                    _self.greenOlvidCardView.configure(with: _self.obvContactGroup.publishedObvGroupDetails,
                                                       groupUid: _self.persistedContactGroup.groupUid,
                                                       cardTypeText: Strings.groupCardPublished.uppercased(),
                                                       cardTypeStyle: .green)
                }
                
                animation1 = { [weak self] in
                    guard let _self = self else { return }
                    _self.redOlvidCardPlaceholder.isHidden = false
                    _self.greenOlvidCardPlaceholder.isHidden = false
                    _self.olvidCardVersionChooserPlaceholder.isHidden = true
                }
            }
            
        }
        
        if animated {
            animator1.addAnimations(animation1)
            animator2.addAnimations(animation2)
            animator1.addCompletion { (_) in
                animator2.startAnimation()
            }
            animator1.startAnimation()
        } else {
            animation1()
            animation2()
        }
        
    }
    
}
