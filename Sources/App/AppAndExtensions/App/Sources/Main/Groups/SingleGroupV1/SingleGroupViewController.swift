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
@preconcurrency import ObvEngine
@preconcurrency import ObvTypes
import SwiftUI
import ObvUI
import ObvUICoreData
import ObvDesignSystem
import ObvSettings
import ObvAppCoreConstants


class SingleGroupViewController: UIViewController, PersonalNoteEditorViewActionsDelegate {

    // Views
    
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var mainStackView: UIStackView!
    
    @IBOutlet weak var topStackView: UIStackView!
    @IBOutlet weak var circlePlaceholder: UIView!
    @IBOutlet weak var titleLabel: UILabel!
    
    @IBOutlet weak var cloneButtonContainerView: UIView!
    private let cloneBackgroundView = UIView()
    private let cloneExplanationLabel = UILabel()
    private let cloneButton = ObvImageButton()
    
    @IBOutlet weak var personalNoteContainerView: UIView!
    private let personalNoteBackgroundView = UIView()
    private let personalNoteTitle = UILabel()
    private let personalNoteBody = UILabel()
    
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
    @IBOutlet weak var smallCloneGroupView: UIView!
    @IBOutlet weak var smallCloneGroupButton: UIButton!
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
    @IBOutlet weak var removeMembersButton: ObvButtonLegacy!
    
    private static let errorDomain = "SingleGroupViewController"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    // Delegate
    
    weak var delegate: SingleGroupViewControllerDelegate?
    
    // Model

    let persistedContactGroup: PersistedContactGroup
    let obvEngine: ObvEngine
    private(set) var obvContactGroup: ObvContactGroup!
    let currentOwnedCryptoId: ObvCryptoId
    let displayedContactGroupPermanentID: DisplayedContactGroupPermanentID
    
    // Subviews set in viewDidLoad
    
    var circledInitials: CircledInitials!
    
    // Other constants
    
    private var notificationTokens = [NSObjectProtocol]()
    private var keyValueObservations = [NSKeyValueObservation]()
    
    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: SingleGroupViewController.self))
    private let customSpacingBetweenSections: CGFloat = 24.0
    private let customSpacingAfterTopStackView: CGFloat = 32.0
    private let sectionLabelsLeadingPaddingConstraint: CGFloat = 20.0
    private let olvidCardsSideConstants: CGFloat = 16.0
    
    // Initializer
    
    init(persistedContactGroupOwned: PersistedContactGroupOwned, obvEngine: ObvEngine) throws {
        guard let ownCryptoId = persistedContactGroupOwned.ownedIdentity?.cryptoId else {
            throw Self.makeError(message: "Could not determine owned identity")
        }
        guard let displayedContactGroupPermanentID = try persistedContactGroupOwned.displayedContactGroup?.objectPermanentID else {
            throw Self.makeError(message: "Could not determine displayed contact group")
        }
        self.currentOwnedCryptoId = ownCryptoId
        self.displayedContactGroupPermanentID = displayedContactGroupPermanentID
        self.persistedContactGroup = persistedContactGroupOwned
        self.obvEngine = obvEngine
        super.init(nibName: nil, bundle: nil)
        guard let ownedIdentity = persistedContactGroupOwned.ownedIdentity else {
            throw SingleGroupViewController.makeError(message: "Could not find owned identity. This is ok if it was just deleted")
        }
        try self.obvContactGroup = obvEngine.getContactGroupOwned(groupUid: persistedContactGroupOwned.groupUid, ownedCryptoId: ownedIdentity.cryptoId)
    }

    init(persistedContactGroupJoined: PersistedContactGroupJoined, obvEngine: ObvEngine) throws {
        guard let ownCryptoId = persistedContactGroupJoined.ownedIdentity?.cryptoId else {
            throw Self.makeError(message: "Could not determine owned identity")
        }
        guard let displayedContactGroupPermanentID = try persistedContactGroupJoined.displayedContactGroup?.objectPermanentID else {
            throw Self.makeError(message: "Could not determine displayed contact group")
        }
        self.currentOwnedCryptoId = ownCryptoId
        self.displayedContactGroupPermanentID = displayedContactGroupPermanentID
        self.persistedContactGroup = persistedContactGroupJoined
        self.obvEngine = obvEngine
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

    convenience init(persistedContactGroup: PersistedContactGroup, obvEngine: ObvEngine) throws {
        if let groupJoined = persistedContactGroup as? PersistedContactGroupJoined {
            try self.init(persistedContactGroupJoined: groupJoined, obvEngine: obvEngine)
        } else if let groupOwned = persistedContactGroup as? PersistedContactGroupOwned {
            try self.init(persistedContactGroupOwned: groupOwned, obvEngine: obvEngine)
        } else {
            throw Self.makeError(message: "Unexpected group type")
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        keyValueObservations.forEach { $0.invalidate() }
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
        let titleLabelStyle = UIFont.TextStyle.title1
        let titleLabelFontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: titleLabelStyle).withDesign(.rounded)?.withSymbolicTraits(.traitBold) ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: titleLabelStyle)
        titleLabel.font = UIFont(descriptor: titleLabelFontDescriptor, size: 0)

        circledInitials = (Bundle.main.loadNibNamed(CircledInitials.nibName, owner: nil, options: nil)!.first as! CircledInitials)
        circledInitials.withShadow = false
        circlePlaceholder.addSubview(circledInitials)
        circlePlaceholder.pinAllSidesToSides(of: circledInitials)
        
        cloneButtonContainerView.addSubview(cloneBackgroundView)
        cloneBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        cloneBackgroundView.backgroundColor = AppTheme.shared.colorScheme.secondarySystemBackground
        cloneBackgroundView.layer.cornerCurve = .continuous
        cloneBackgroundView.layer.cornerRadius = 16.0
        
        cloneBackgroundView.addSubview(cloneExplanationLabel)
        cloneExplanationLabel.translatesAutoresizingMaskIntoConstraints = false
        cloneExplanationLabel.text = CommonString.explanationForCloneGroupV1ToGroupV2
        cloneExplanationLabel.textColor = AppTheme.shared.colorScheme.secondaryLabel
        cloneExplanationLabel.font = UIFont.preferredFont(forTextStyle: .body)
        cloneExplanationLabel.numberOfLines = 0
        
        cloneBackgroundView.addSubview(cloneButton)
        cloneButton.translatesAutoresizingMaskIntoConstraints = false
        cloneButton.setTitle(NSLocalizedString("CLONE_THIS_GROUP_V1_TO_GROUP_V2", comment: ""), for: .normal)
        cloneButton.setImage(.docOnDoc, for: .normal)

        personalNoteContainerView.addSubview(personalNoteBackgroundView)
        personalNoteBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        personalNoteBackgroundView.backgroundColor = AppTheme.shared.colorScheme.secondarySystemBackground
        personalNoteBackgroundView.layer.cornerCurve = .continuous
        personalNoteBackgroundView.layer.cornerRadius = 16.0

        personalNoteBackgroundView.addSubview(personalNoteTitle)
        personalNoteTitle.translatesAutoresizingMaskIntoConstraints = false
        personalNoteTitle.textColor = AppTheme.shared.colorScheme.label
        personalNoteTitle.font = UIFont.preferredFont(forTextStyle: .headline)
        personalNoteTitle.text = NSLocalizedString("PERSONAL_NOTE", comment: "")
        personalNoteTitle.numberOfLines = 1
        
        personalNoteBackgroundView.addSubview(personalNoteBody)
        personalNoteBody.translatesAutoresizingMaskIntoConstraints = false
        personalNoteBody.textColor = AppTheme.shared.colorScheme.secondaryLabel
        personalNoteBody.font = UIFont.preferredFont(forTextStyle: .body)
        personalNoteBody.text = "-"
        personalNoteBody.numberOfLines = 0

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
        updateOlvidCardButton = ObvButtonLegacy()
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
        
        smallCloneGroupView.backgroundColor = AppTheme.shared.colorScheme.tertiarySystemBackground
        smallCloneGroupButton.setTitle(NSLocalizedString("CLONE_THIS_GROUP_V1_TO_GROUP_V2", comment: ""), for: .normal)
        smallCloneGroupButton.addTarget(self, action: #selector(smallCloneGroupButtonTapped), for: .touchUpInside)

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
        
        setupContraints()
        
        observePersistedContactGroupChanges()
        observeEngineNotifications()
        observeIdentityColorStyleDidChangeNotifications()
        
        keyValueObservations.append(persistedContactGroup.observe(\.note, options: [.new]) { object, change in
            guard let newPersonalNote = change.newValue else { assertionFailure(); return }
            if let newPersonalNote, !newPersonalNote.isEmpty {
                self.personalNoteBody.text = newPersonalNote
            } else {
                self.personalNoteBody.text = "-"
            }
        })
        
        // We refresh the group each time we load this view controller
        if obvContactGroup.groupType == .joined {
            refreshGroup()
        }
        
        cloneButton.addTarget(self, action: #selector(cloneGroupButtonTapped), for: .touchUpInside)

    }
    
    
    @objc private func cloneGroupButtonTapped() {
        Task {
            try await delegate?.userWantsToCloneGroup(self, persistedContactGroup: persistedContactGroup)
        }
    }
    
    
    private func setupContraints() {
        let showCloneButton = (persistedContactGroup.category == .owned)
        if showCloneButton {
            cloneBackgroundView.isHidden = false
            NSLayoutConstraint.activate([
                cloneBackgroundView.leadingAnchor.constraint(equalTo: cloneButtonContainerView.leadingAnchor, constant: 16),
                cloneBackgroundView.trailingAnchor.constraint(equalTo: cloneButtonContainerView.trailingAnchor, constant: -16),
                cloneBackgroundView.topAnchor.constraint(equalTo: cloneButtonContainerView.topAnchor, constant: 28),
                cloneBackgroundView.bottomAnchor.constraint(equalTo: cloneButtonContainerView.bottomAnchor, constant: -16),

                cloneExplanationLabel.topAnchor.constraint(equalTo: cloneBackgroundView.topAnchor, constant: 16),
                cloneExplanationLabel.trailingAnchor.constraint(equalTo: cloneBackgroundView.trailingAnchor, constant: -16),
                cloneExplanationLabel.bottomAnchor.constraint(equalTo: cloneButton.topAnchor, constant: -16),
                cloneExplanationLabel.leadingAnchor.constraint(equalTo: cloneBackgroundView.leadingAnchor, constant: 16),

                cloneButton.trailingAnchor.constraint(equalTo: cloneBackgroundView.trailingAnchor, constant: -16),
                cloneButton.leadingAnchor.constraint(equalTo: cloneBackgroundView.leadingAnchor, constant: 16),
                cloneButton.bottomAnchor.constraint(equalTo: cloneBackgroundView.bottomAnchor, constant: -16),
            ])
        } else {
            cloneBackgroundView.isHidden = true
            NSLayoutConstraint.activate([
                cloneButtonContainerView.heightAnchor.constraint(equalToConstant: 0),
                cloneBackgroundView.heightAnchor.constraint(equalToConstant: 0),
            ])
        }
        
        NSLayoutConstraint.activate([
            personalNoteBackgroundView.leadingAnchor.constraint(equalTo: personalNoteContainerView.leadingAnchor, constant: 16),
            personalNoteBackgroundView.trailingAnchor.constraint(equalTo: personalNoteContainerView.trailingAnchor, constant: -16),
            personalNoteBackgroundView.topAnchor.constraint(equalTo: personalNoteContainerView.topAnchor, constant: 0),
            personalNoteBackgroundView.bottomAnchor.constraint(equalTo: personalNoteContainerView.bottomAnchor, constant: -16),
            
            personalNoteTitle.topAnchor.constraint(equalTo: personalNoteBackgroundView.topAnchor, constant: 16),
            personalNoteTitle.trailingAnchor.constraint(equalTo: personalNoteBackgroundView.trailingAnchor, constant: -16),
            personalNoteTitle.bottomAnchor.constraint(equalTo: personalNoteBody.topAnchor, constant: -4),
            personalNoteTitle.leadingAnchor.constraint(equalTo: personalNoteBackgroundView.leadingAnchor, constant: 16),
            
            personalNoteBody.trailingAnchor.constraint(equalTo: personalNoteBackgroundView.trailingAnchor, constant: -16),
            personalNoteBody.leadingAnchor.constraint(equalTo: personalNoteBackgroundView.leadingAnchor, constant: 16),
            personalNoteBody.bottomAnchor.constraint(equalTo: personalNoteBackgroundView.bottomAnchor, constant: -16),
        ])
        
    }

    
    private func configureNavigationBarTitle() {
        addRightBarButtonMenu()
    }
    
    
    @available(iOS 15.0, *)
    private func addRightBarButtonMenu() {
        
        let actionEditNote = UIAction(
            title: NSLocalizedString("EDIT_PERSONAL_NOTE", comment: ""),
            image: UIImage(systemIcon: .pencil(.circle)),
            handler: userWantsToShowPersonalNoteEditor)
        
        let actionEditGroup = UIAction(
            title: NSLocalizedString("EDIT_GROUP", comment: ""),
            image: UIImage(systemIcon: .pencil(.circle)),
            handler: userWantsToEditGroupNickname)
        
        let actionCall: UIAction?
        if !persistedContactGroup.contactIdentities.isEmpty {
            actionCall = UIAction(
                title: NSLocalizedString("CALL", comment: ""),
                image: UIImage(systemIcon: .phoneFill),
                handler: { [weak self] _ in
                    guard let self else { return }
                    guard let context = persistedContactGroup.managedObjectContext else { return }
                    context.perform { [weak self] in
                        guard let self else { return }
                        guard let ownedCryptoId = persistedContactGroup.ownedIdentity?.cryptoId else { return }
                        let contactCryptoIds = persistedContactGroup.contactIdentities.map { $0.cryptoId }
                        guard let groupV1Identifier = try? persistedContactGroup.getGroupV1Identifier() else { assertionFailure(); return }
                        ObvMessengerInternalNotification.userWantsToSelectAndCallContacts(ownedCryptoId: ownedCryptoId, contactCryptoIds: Set(contactCryptoIds), groupId: .groupV1(groupV1Identifier: groupV1Identifier))
                            .postOnDispatchQueue()
                    }
                })
        } else {
            actionCall = nil
        }
            
        let menu = UIMenu(children: [actionEditNote, actionEditGroup, actionCall].compactMap{ $0 })
        
        let barButtonItem = UIBarButtonItem(image: UIImage(systemIcon: .ellipsisCircle), menu: menu)
        
        navigationItem.rightBarButtonItems = [barButtonItem]
    }
    
    
    @available(iOS 15.0, *)
    private func userWantsToShowPersonalNoteEditor(_ action: UIAction) {
        let personalNote = persistedContactGroup.note
        let viewControllerToPresent = PersonalNoteEditorHostingController(model: .init(initialText: personalNote), actions: self)
        if let sheet = viewControllerToPresent.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
            sheet.preferredCornerRadius = 16.0
        }
        present(viewControllerToPresent, animated: true, completion: nil)
    }

    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if obvContactGroup.groupType == .joined,
            let joinedGroup = persistedContactGroup as? PersistedContactGroupJoined,
           joinedGroup.status == .unseenPublishedDetails,
           let obvGroupIdentifier = try? joinedGroup.obvGroupIdentifier
        {
            
            ObvMessengerInternalNotification.userHasSeenPublishedDetailsOfContactGroupJoined(obvGroupIdentifier: obvGroupIdentifier)
                .postOnDispatchQueue()
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
        circledInitials.identityColors = AppTheme.shared.groupColors(forGroupUid: persistedContactGroup.groupUid, using: ObvMessengerSettings.Interface.identityColorStyle)
        titleLabel.text = self.persistedContactGroup.displayName
        if let newPersonalNote = self.persistedContactGroup.note, !newPersonalNote.isEmpty {
            self.personalNoteBody.text = newPersonalNote
        } else {
            self.personalNoteBody.text = "-"
        }
    }
    
    private func configureAndAddMembersTVC() throws {
        
        let predicate = PersistedObvContactIdentity.getPredicateForContactGroup(self.persistedContactGroup)
        let contactsTVC = ContactsTableViewController(disableContactsWithoutDevice: false, oneToOneStatus: .any, allowDeletion: false)
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
        let token = ObvMessengerSettingsNotifications.observeIdentityColorStyleDidChange {
            DispatchQueue.main.async { [weak self] in
                self?.configureViewsBasedOnPersistedContactGroup()
                self?.configureTheOlvidCards(animated: false)
            }
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
        notificationTokens.append(contentsOf: [
            ObvEngineNotificationNew.observePublishedPhotoOfContactGroupJoinedHasBeenUpdated(within: NotificationCenter.default) { [weak self] obvContactGroup in
                DispatchQueue.main.async {
                    guard let _self = self else { return }
                    guard _self.obvContactGroup.ownedIdentity == obvContactGroup.ownedIdentity else { return }
                    guard _self.obvContactGroup.groupUid == obvContactGroup.groupUid else { return }
                    self?.obvContactGroup = obvContactGroup
                    self?.configureTheOlvidCards(animated: true)
                }
            },
            ObvEngineNotificationNew.observeContactGroupOwnedDiscardedLatestDetails(within: NotificationCenter.default) { [weak self] obvContactGroup in
                DispatchQueue.main.async {
                    guard let _self = self else { return }
                    guard _self.obvContactGroup.ownedIdentity == obvContactGroup.ownedIdentity else { return }
                    guard _self.obvContactGroup.groupUid == obvContactGroup.groupUid else { return }
                    self?.obvContactGroup = obvContactGroup
                    self?.configureTheOlvidCards(animated: true)
                }
            },
            ObvEngineNotificationNew.observeContactGroupOwnedHasUpdatedLatestDetails(within: NotificationCenter.default) { [weak self] obvContactGroup in
                DispatchQueue.main.async {
                    guard let _self = self else { return }
                    guard _self.obvContactGroup.ownedIdentity == obvContactGroup.ownedIdentity else { return }
                    guard _self.obvContactGroup.groupUid == obvContactGroup.groupUid else { return }
                    self?.obvContactGroup = obvContactGroup
                    self?.configureTheOlvidCards(animated: true)
                }
            },
            ObvEngineNotificationNew.observeContactGroupHasUpdatedPublishedDetails(within: NotificationCenter.default) { [weak self] obvContactGroup in
                DispatchQueue.main.async {
                    guard let _self = self else { return }
                    guard _self.obvContactGroup.ownedIdentity == obvContactGroup.ownedIdentity else { return }
                    guard _self.obvContactGroup.groupUid == obvContactGroup.groupUid else { return }
                    self?.obvContactGroup = obvContactGroup
                    self?.configureTheOlvidCards(animated: true)
                }
            },
            ObvEngineNotificationNew.observeContactGroupJoinedHasUpdatedTrustedDetails(within: NotificationCenter.default) { [weak self] obvContactGroup in
                DispatchQueue.main.async {
                    guard let _self = self else { return }
                    guard _self.obvContactGroup.ownedIdentity == obvContactGroup.ownedIdentity else { return }
                    guard _self.obvContactGroup.groupUid == obvContactGroup.groupUid else { return }
                    self?.obvContactGroup = obvContactGroup
                    self?.configureTheOlvidCards(animated: true)
                }
            },
            ObvEngineNotificationNew.observeContactGroupHasUpdatedPendingMembersAndGroupMembers(within: NotificationCenter.default) { [weak self] obvContactGroup in
                DispatchQueue.main.async {
                    guard let _self = self else { return }
                    guard _self.obvContactGroup.ownedIdentity == obvContactGroup.ownedIdentity else { return }
                    guard _self.obvContactGroup.groupUid == obvContactGroup.groupUid else { return }
                    self?.obvContactGroup = obvContactGroup
                }
            },
            ObvEngineNotificationNew.observeContactGroupDeleted(within: NotificationCenter.default) { [weak self] obvOwnedIdentity, groupOwner, groupUid in
                DispatchQueue.main.async {
                    guard let _self = self else { return }
                    guard _self.obvContactGroup.ownedIdentity == obvOwnedIdentity else { return }
                    guard _self.obvContactGroup.groupUid == groupUid else { return }
                    if _self.navigationController?.presentingViewController != nil {
                        _self.navigationController?.dismiss(animated: true, completion: nil)
                    } else {
                        _self.navigationController?.popViewController(animated: true)
                    }
                }
            },
        ])
    }

}

// MARK: - Editing the group

extension SingleGroupViewController {
    
    private func userWantsToEditGroupNickname(_ action: UIAction) {
        editGroupButtonTapped()
    }
    
    @objc func editGroupButtonTapped() {
        
        guard let ownedCryptoId = self.persistedContactGroup.ownedIdentity?.cryptoId,
              let groupId = try? self.persistedContactGroup.getGroupId() else {
            assertionFailure()
            return
        }
        
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
            let removeNickname = UIAlertAction(title: CommonString.removeNickname, style: .destructive) { _ in
                ObvMessengerInternalNotification.userWantsToSetCustomNameOfJoinedGroupV1(ownedCryptoId: ownedCryptoId, groupId: groupId, groupNameCustom: nil)
                    .postOnDispatchQueue()
            }
            let cancelAction = UIAlertAction(title: CommonString.Word.Cancel, style: UIAlertAction.Style.cancel)
            let okAction = UIAlertAction(title: CommonString.Word.Ok, style: UIAlertAction.Style.default) { _ in
                if let newGroupName = textField.text, !newGroupName.isEmpty {
                    ObvMessengerInternalNotification.userWantsToSetCustomNameOfJoinedGroupV1(ownedCryptoId: ownedCryptoId, groupId: groupId, groupNameCustom: newGroupName)
                        .postOnDispatchQueue()
                }
            }
            alert.addAction(removeNickname)
            alert.addAction(okAction)
            alert.addAction(cancelAction)
            self.present(alert, animated: true)
            
        case .owned:
            let ownedGroupEditionFlowVC = GroupEditionFlowViewController(
                ownedCryptoId: obvContactGroup.ownedIdentity.cryptoId,
                editionType: .editGroupV1Details(obvContactGroup: obvContactGroup), obvEngine: obvEngine)
            DispatchQueue.main.async { [weak self] in
                self?.present(ownedGroupEditionFlowVC, animated: true)
            }
        }

    }

}


// MARK: - ContactsTableViewControllerDelegate

extension SingleGroupViewController: ContactsTableViewControllerDelegate {
    
    func userWantsToDeleteContact(with: ObvCryptoId, forOwnedCryptoId: ObvCryptoId, completionHandler: @escaping (Bool) -> Void) {
        assertionFailure("Should never be called")
    }

    func userDidSelect(_ obvContactIdentity: PersistedObvContactIdentity) {
        delegate?.userWantsToDisplay(self, persistedContact: obvContactIdentity, within: navigationController)
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

    
    @MainActor
    private func sendAnotherInvitation(to persistedPendingGroupMember: PersistedPendingGroupMember, confirmed: Bool, completionHandler: (() -> Void)?) {
        let currentPendingMembers = obvContactGroup.pendingGroupMembers.map { $0.cryptoId }
        guard currentPendingMembers.contains(persistedPendingGroupMember.cryptoId) else { return }
        
        if confirmed {
            
            guard let obvContactGroup = self.obvContactGroup else { return }
            let groupUid = obvContactGroup.groupUid
            let ownedCryptoId = obvContactGroup.ownedIdentity.cryptoId
            let pendingGroupMember = persistedPendingGroupMember.cryptoId
            let obvEngine = self.obvEngine
            
            DispatchQueue(label: "Queue for calling reInviteContactToGroupOwned").async {
                try? obvEngine.reInviteContactToGroupOwned(groupUid: groupUid,
                                                           ownedCryptoId: ownedCryptoId,
                                                           pendingGroupMember: pendingGroupMember)
            }
            
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
        delegate?.userWantsToDisplay(self, persistedDiscussion: discussion)
    }
 
    @objc func deleteGroupButtonTapped() {
        guard obvContactGroup.groupType == .owned else { return }
        ObvMessengerInternalNotification.userWantsToDeleteOwnedContactGroup(ownedCryptoId: obvContactGroup.ownedIdentity.cryptoId, groupUid: obvContactGroup.groupUid)
            .postOnDispatchQueue()
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
    
    @objc func smallCloneGroupButtonTapped() {
        Task {
            try await delegate?.userWantsToCloneGroup(self, persistedContactGroup: persistedContactGroup)
        }
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
        guard let obvContactGroup else { return }
        guard obvContactGroup.groupType == .joined else { return }
        let obvEngine = self.obvEngine
        let log = self.log
        Task.detached {
            do {
                try await obvEngine.trustPublishedDetailsOfJoinedContactGroup(
                    ownedCryptoId: obvContactGroup.ownedIdentity.cryptoId,
                    groupUid: obvContactGroup.groupUid,
                    groupOwner: obvContactGroup.groupOwner.cryptoId)
            } catch {
                os_log("Could not accept published details of contact group joined: %{public}@", log: log, type: .error, error.localizedDescription)
            }
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
        let ownedGroupEditionFlowVC = GroupEditionFlowViewController(ownedCryptoId: obvContactGroup.ownedIdentity.cryptoId,
                                                                     editionType: .addGroupV1Members(groupUid: obvContactGroup.groupUid, currentGroupMembers: groupMembersAndPendingMembers),
                                                                     obvEngine: obvEngine)
        DispatchQueue.main.async { [weak self] in
            self?.present(ownedGroupEditionFlowVC, animated: true)
        }
    }
    
    
    @objc func removeMembersButtonTapped() {
        guard obvContactGroup.groupType == .owned else { return }
        let currentGroupMembers = Set(obvContactGroup.groupMembers.map { $0.cryptoId })
        let currentPendingMembers = obvContactGroup.pendingGroupMembers.map { $0.cryptoId }
        let groupMembersAndPendingMembers = currentGroupMembers.union(currentPendingMembers)
        let ownedGroupEditionFlowVC = GroupEditionFlowViewController(ownedCryptoId: obvContactGroup.ownedIdentity.cryptoId,
                                                                     editionType: .removeGroupV1Members(groupUid: obvContactGroup.groupUid, currentGroupMembers: groupMembersAndPendingMembers),
                                                                     obvEngine: obvEngine)
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
                        _self.latestOlvidCardPublishButton = ObvButtonLegacy()
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
    
    
    // MARK: - PersonalNoteEditorViewActionsDelegate
    
    func userWantsToDismissPersonalNoteEditorView() async {
        guard presentedViewController is PersonalNoteEditorHostingController else { return }
        presentedViewController?.dismiss(animated: true)
    }
    
    
    @MainActor
    func userWantsToUpdatePersonalNote(with newText: String?) async {
        guard let ownedCryptoId = persistedContactGroup.ownedIdentity?.cryptoId else { return }
        guard let groupId = try? persistedContactGroup.getGroupId() else { return }
        ObvMessengerInternalNotification.userWantsToUpdatePersonalNoteOnGroupV1(ownedCryptoId: ownedCryptoId, groupId: groupId, newText: newText)
            .postOnDispatchQueue()
        presentedViewController?.dismiss(animated: true)
    }

}
