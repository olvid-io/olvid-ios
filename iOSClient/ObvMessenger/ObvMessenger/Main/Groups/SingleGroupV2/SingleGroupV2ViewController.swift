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

import os.log
import CoreData
import OlvidUtils
import ObvEngine
import ObvTypes
import ObvUI
import SwiftUI
import ObvUICoreData
import ObvDesignSystem


protocol SingleGroupV2ViewControllerDelegate: AnyObject {
    func userWantsToDisplay(persistedContact: PersistedObvContactIdentity, within: UINavigationController?)
    func userWantsToDisplay(persistedDiscussion discussion: PersistedDiscussion)
    func userWantsToCloneGroup(displayedContactGroupObjectID: TypeSafeManagedObjectID<DisplayedContactGroup>)
    func userWantsToInviteContactToOneToOne(ownedCryptoId: ObvCryptoId, contactCryptoIds: Set<ObvCryptoId>) async throws
}


final class SingleGroupV2ViewController: UIHostingController<SingleGroupV2View>, SingleGroupV2ViewDelegate, ObvErrorMaker, PersonalNoteEditorViewActionsDelegate, EditNicknameAndCustomPictureViewControllerDelegate {
    
    let persistedGroupV2ObjectID: TypeSafeManagedObjectID<PersistedGroupV2>
    let currentOwnedCryptoId: ObvCryptoId
    let displayedContactGroupPermanentID: DisplayedContactGroupPermanentID
    private let obvEngine: ObvEngine
    private var scratchGroup: PersistedGroupV2
    private var referenceGroup: PersistedGroupV2 // Allows to compute a diff with the scratchGroup when publishing group members updates
    private let scratchViewContext: NSManagedObjectContext
    private let referenceViewContext: NSManagedObjectContext
    private let viewDelegate = ViewDelegate()
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: SingleGroupV2ViewController.self))
    static let errorDomain = "SingleGroupV2ViewController"
    weak var delegate: SingleGroupV2ViewControllerDelegate?
    private var tokens = [NSObjectProtocol]()

    init(group: PersistedGroupV2, obvEngine: ObvEngine, delegate: SingleGroupV2ViewControllerDelegate) throws {
        guard let ownCryptoId = group.persistedOwnedIdentity?.cryptoId else {
            throw Self.makeError(message: "Could not determine owned identity")
        }
        guard let displayedContactGroupPermanentID = group.displayedContactGroup?.objectPermanentID else {
            throw Self.makeError(message: "Could not determine displayed contact group")
        }
        self.currentOwnedCryptoId = ownCryptoId
        self.displayedContactGroupPermanentID = displayedContactGroupPermanentID
        self.persistedGroupV2ObjectID = group.typedObjectID
        self.obvEngine = obvEngine
        self.scratchViewContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        scratchViewContext.persistentStoreCoordinator = ObvStack.shared.persistentStoreCoordinator
        guard let scratchGroup = try PersistedGroupV2.get(objectID: group.typedObjectID, within: scratchViewContext) else { throw Self.makeError(message: "Could not get group") }
        
        self.referenceViewContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        referenceViewContext.persistentStoreCoordinator = ObvStack.shared.persistentStoreCoordinator
        guard let referenceGroup = try PersistedGroupV2.get(objectID: group.typedObjectID, within: referenceViewContext) else { throw Self.makeError(message: "Could not get group") }

        self.scratchGroup = scratchGroup
        self.referenceGroup = referenceGroup
        let view = SingleGroupV2View(group: self.scratchGroup, delegate: viewDelegate)
        super.init(rootView: view)
        viewDelegate.delegate = self
        self.delegate = delegate
        
        observeNotifications()
        
    }
    
    deinit {
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = scratchGroup.displayName
        
        addRightBarButtonMenu()

    }
    
    
    private func addRightBarButtonMenu() {
        
        let actionEditNote = UIAction(
            title: NSLocalizedString("EDIT_PERSONAL_NOTE", comment: ""),
            image: UIImage(systemIcon: .pencil(.none)),
            handler: userWantsToShowPersonalNoteEditor)
        
        let actionEditCustomDetails = UIAction(
            title: NSLocalizedString("EDIT_NICKNAME_AND_CUSTOM_PHOTO", comment: ""),
            image: UIImage(systemIcon: .camera(.none)),
            handler: userWantsToEditPersonalGroupDetails)
        
        let menu = UIMenu(children: [actionEditNote, actionEditCustomDetails])
        
        let barButtonItem = UIBarButtonItem(image: UIImage(systemIcon: .ellipsisCircle), menu: menu)
        
        navigationItem.rightBarButtonItems = [barButtonItem]
    }
    
    
    private func userWantsToShowPersonalNoteEditor(_ action: UIAction) {
        let personalNote = referenceGroup.personalNote
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
    
    
    private func userWantsToEditPersonalGroupDetails(_ action: UIAction) {
        assert(Thread.isMainThread)
        let groupV2Identifier = scratchGroup.groupIdentifier
        let defaultPhoto: UIImage?
        if let url = scratchGroup.trustedPhotoURL {
            defaultPhoto = UIImage(contentsOfFile: url.path)
        } else {
            defaultPhoto = nil
        }
        let currentCustomPhoto: UIImage?
        if let url = scratchGroup.customPhotoURL {
            currentCustomPhoto = UIImage(contentsOfFile: url.path)
        } else {
            currentCustomPhoto = nil
        }
        let currentNickname = scratchGroup.customName ?? ""
        let vc = EditNicknameAndCustomPictureViewController(
            model: .init(identifier: .groupV2(groupV2Identifier: groupV2Identifier),
                         currentInitials: "", // No initials needed for groups
                         defaultPhoto: defaultPhoto,
                         currentCustomPhoto: currentCustomPhoto,
                         currentNickname: currentNickname),
            delegate: self)
        present(vc, animated: true)
    }

    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        ObvMessengerInternalNotification.userHasSeenPublishedDetailsOfGroupV2(groupObjectID: persistedGroupV2ObjectID)
            .postOnDispatchQueue()
    }
    
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // In case the details were updated while this view controller was shown, we want to mark them as seen
        ObvMessengerInternalNotification.userHasSeenPublishedDetailsOfGroupV2(groupObjectID: persistedGroupV2ObjectID)
            .postOnDispatchQueue()
    }
    
    
    private func observeNotifications() {
        tokens.append(contentsOf: [
            NotificationCenter.default.addObserver(forName: Notification.Name.NSManagedObjectContextDidSave, object: nil, queue: OperationQueue.main) { [weak self] (notification) in
                withAnimation {
                    self?.scratchViewContext.mergeChanges(fromContextDidSave: notification)
                    self?.referenceViewContext.mergeChanges(fromContextDidSave: notification)
                }
            },
            ObvMessengerCoreDataNotification.observePersistedGroupV2UpdateIsFinished(queue: OperationQueue.main) { [weak self] objectID, _, _ in
                guard let _self = self else { return }
                guard objectID == _self.scratchGroup.typedObjectID else { return }
                // At the end of an update of the group in database, we rollback all changes we made.
                // At this point, if we were in edit mode, we loose our modifications. This is acceptable for now.
                withAnimation {
                    self?.hideUpdateInProgress()
                    self?.scratchViewContext.rollback()
                }
            },
            ObvMessengerCoreDataNotification.observePersistedGroupV2WasDeleted(queue: OperationQueue.main) { [weak self] objectID in
                guard let _self = self else { return }
                guard objectID == _self.persistedGroupV2ObjectID else { return }
                if _self.presentingViewController != nil {
                    _self.dismiss(animated: true)
                }
            },
        ])
    }
    

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: SingleGroupV2ViewDelegate
    
    private final class ViewDelegate: SingleGroupV2ViewDelegate {
        weak var delegate: SingleGroupV2ViewDelegate?
        func userWantsToAddGroupMembers() {
            delegate?.userWantsToAddGroupMembers()
        }
        func rollbackAllModifications() {
            delegate?.rollbackAllModifications()
        }
        func userWantsToNavigateToPersistedObvContactIdentity(_ contact: PersistedObvContactIdentity) {
            delegate?.userWantsToNavigateToPersistedObvContactIdentity(contact)
        }
        func userWantsToNavigateToDiscussion() {
            delegate?.userWantsToNavigateToDiscussion()
        }
        func userWantsToCall() async {
            await delegate?.userWantsToCall()
        }
        func userWantsToPublishAllModifications() {
            assert(Thread.isMainThread)
            delegate?.userWantsToPublishAllModifications()
        }
        func userWantsToReplaceTrustedDetailsByPublishedDetails() {
            delegate?.userWantsToReplaceTrustedDetailsByPublishedDetails()
        }
        func userWantsToPerformReDownloadOfGroupV2() {
            delegate?.userWantsToPerformReDownloadOfGroupV2()
        }
        func userWantsToLeaveGroup() {
            delegate?.userWantsToLeaveGroup()
        }
        func userWantsToPerformDisbandOfGroupV2() {
            delegate?.userWantsToPerformDisbandOfGroupV2()
        }
        func userWantsToEditDetailsOfGroupAsAdmin() {
            delegate?.userWantsToEditDetailsOfGroupAsAdmin()
        }
        func userWantsToCloneThisGroup() {
            delegate?.userWantsToCloneThisGroup()
        }
        func userWantsToInviteAllMembersWithChannelToOneToOne() async throws {
            try await delegate?.userWantsToInviteAllMembersWithChannelToOneToOne()
        }
    }
    
    
    func userWantsToAddGroupMembers() {
        do {
            let excludedMembers = Set(scratchGroup.otherMembers.compactMap({ $0.cryptoId }))
            let ownedCryptoId = try scratchGroup.ownCryptoId
            let mode = MultipleContactsMode.excluded(from: excludedMembers, oneToOneStatus: .any, requiredCapabilitites: [.groupsV2])
            let button: MultipleContactsButton = .floating(title: CommonString.Word.Ok, systemIcon: .personCropCircleFillBadgeCheckmark)
            let vc = MultipleContactsViewController(ownedCryptoId: ownedCryptoId,
                                                    mode: mode,
                                                    button: button,
                                                    disableContactsWithoutDevice: true,
                                                    allowMultipleSelection: true,
                                                    showExplanation: false,
                                                    allowEmptySetOfContacts: false,
                                                    textAboveContactList: CommonString.someOfYourContactsMayNotAppearAsGroupV2Candidates) { [weak self] selectedContacts in
                let contactObjectIDs = Set(selectedContacts.map({ $0.typedObjectID }))
                try? self?.scratchGroup.addGroupMembers(contactObjectIDs: contactObjectIDs)
                self?.presentedViewController?.dismiss(animated: true)
            } dismissAction: { [weak self] in
                self?.presentedViewController?.dismiss(animated: true)
            }
            vc.title = NSLocalizedString("ADD_GROUP_MEMBERS", comment: "")
            present(ObvNavigationController(rootViewController: vc), animated: true)
        } catch {
            os_log("Could not show MultipleContactsHostingViewController: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }
    
    
    func rollbackAllModifications() {
        let scratchGroupObjectID = scratchGroup.typedObjectID
        scratchGroup.managedObjectContext?.rollback()
        do {
            guard let scratchGroup = try PersistedGroupV2.get(objectID: scratchGroupObjectID, within: scratchViewContext) else {
                throw Self.makeError(message: "Could not get group")
            }
            self.scratchGroup = scratchGroup
        } catch {
            os_log("Could not reload scratch group: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
        }
    }
    
    
    func userWantsToNavigateToPersistedObvContactIdentity(_ contact: PersistedObvContactIdentity) {
        delegate?.userWantsToDisplay(persistedContact: contact, within: navigationController)
    }
    
    
    func userWantsToNavigateToDiscussion() {
        // The delegate expects the discussion object to be registered with the main view context
        guard let group = try? PersistedGroupV2.get(objectID: persistedGroupV2ObjectID, within: ObvStack.shared.viewContext) else {
            assertionFailure()
            return
        }
        guard let discussion = group.discussion else { assertionFailure(); return }
        delegate?.userWantsToDisplay(persistedDiscussion: discussion)
    }
    
    
    @MainActor
    func userWantsToCall() async {
        do {
            guard let group = try PersistedGroupV2.get(objectID: persistedGroupV2ObjectID, within: ObvStack.shared.viewContext) else {
                assertionFailure()
                return
            }
            guard let ownedCryptoId = try? group.ownCryptoId else { return }
            let contactCryptoIds = group.contactsAmongNonPendingOtherMembers.filter({ $0.isActive }).map({ $0.cryptoId })
            let groupV2Identifier = group.groupIdentifier
            ObvMessengerInternalNotification.userWantsToSelectAndCallContacts(ownedCryptoId: ownedCryptoId, contactCryptoIds: Set(contactCryptoIds), groupId: .groupV2(groupV2Identifier: groupV2Identifier))
                .postOnDispatchQueue()
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }
    
    
    func userWantsToInviteAllMembersWithChannelToOneToOne() async throws {
        let persistedGroupV2ObjectID = self.persistedGroupV2ObjectID
        let currentOwnedCryptoId = self.currentOwnedCryptoId
        let contactCryptoIds: [ObvCryptoId] = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ObvCryptoId], Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    guard let group = try PersistedGroupV2.get(objectID: persistedGroupV2ObjectID, within: context) else {
                        throw Self.makeError(message: "Could not find group")
                    }
                    guard try group.ownCryptoId == currentOwnedCryptoId else {
                        throw Self.makeError(message: "Unexpected owned identity")
                    }
                    let contactCryptoIds = group.otherMembers
                        .compactMap { $0.contact?.cryptoId }
                    continuation.resume(returning: contactCryptoIds)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        try await delegate?.userWantsToInviteContactToOneToOne(ownedCryptoId: currentOwnedCryptoId, contactCryptoIds: Set(contactCryptoIds))
    }
    
    
    @MainActor
    func userWantsToPublishAllModifications() {
        assert(Thread.isMainThread)
        do {
            let changeset = try scratchGroup.computeChangeset(with: referenceGroup)
            guard !changeset.isEmpty else { return }
            showUpdateInProgress()
            ObvMessengerInternalNotification.userWantsToUpdateGroupV2(groupObjectID: scratchGroup.typedObjectID, changeset: changeset)
                .postOnDispatchQueue()
        } catch {
            os_log("Failed to update group: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
        }
    }
    
    
    func userWantsToReplaceTrustedDetailsByPublishedDetails() {
        do {
            try scratchGroup.trustedDetailsShouldBeReplacedByPublishedDetails()
        } catch {
            assertionFailure()
        }
    }
    
    
    func userWantsToPerformReDownloadOfGroupV2() {
        let obvEngine = self.obvEngine
        let ownedCryptoId: ObvCryptoId
        let keycloakManaged: Bool
        do {
            ownedCryptoId = try scratchGroup.ownCryptoId
            keycloakManaged = scratchGroup.keycloakManaged
        } catch {
            os_log("Failed to perform manual resync of group: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            return
        }
        let groupIdentifier = scratchGroup.groupIdentifier
        if keycloakManaged {
            Task { try? await KeycloakManagerSingleton.shared.syncAllManagedIdentities() }
        } else {
            DispatchQueue(label: "Background queue for performing a manual resync of a group").async {
                do {
                    try obvEngine.performReDownloadOfGroupV2(ownedCryptoId: ownedCryptoId, groupIdentifier: groupIdentifier)
                } catch {
                    assertionFailure(error.localizedDescription)
                }
            }
        }
    }

    
    func userWantsToPerformDisbandOfGroupV2() {
        let obvEngine = self.obvEngine
        let ownedCryptoId: ObvCryptoId
        do {
            ownedCryptoId = try scratchGroup.ownCryptoId
        } catch {
            os_log("Failed to perform manual resync of group: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            return
        }
        let groupIdentifier = scratchGroup.groupIdentifier
        DispatchQueue(label: "Background queue for performing a manual resync of a group").async {
            do {
                try obvEngine.performDisbandOfGroupV2(ownedCryptoId: ownedCryptoId, groupIdentifier: groupIdentifier)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }
    
    
    func userWantsToEditDetailsOfGroupAsAdmin() {
        guard let ownedCryptoId = try? scratchGroup.ownCryptoId else { assertionFailure(); return }
        let ownedGroupEditionFlowVC = GroupEditionFlowViewController(
            ownedCryptoId: ownedCryptoId,
            editionType: .editGroupV2AsAdmin(groupIdentifier: scratchGroup.groupIdentifier),
            obvEngine: obvEngine)
        present(ownedGroupEditionFlowVC, animated: true)
    }
    
    
    func userWantsToCloneThisGroup() {
        guard let displayedContactGroup = scratchGroup.displayedContactGroup else { assertionFailure(); return }
        delegate?.userWantsToCloneGroup(displayedContactGroupObjectID: displayedContactGroup.typedObjectID)
    }

    
    func userWantsToLeaveGroup() {
        let obvEngine = self.obvEngine
        let ownedCryptoId: ObvCryptoId
        do {
            ownedCryptoId = try scratchGroup.ownCryptoId
        } catch {
            os_log("Failed to leave group: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            return
        }
        let groupIdentifier = scratchGroup.groupIdentifier
        DispatchQueue(label: "Background queue for performing a manual resync of a group").async {
            do {
                try obvEngine.leaveGroupV2(ownedCryptoId: ownedCryptoId, groupIdentifier: groupIdentifier)
            } catch {
                os_log("The engine call failed. We cannot leave the group: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            }
        }
    }
    
    
    private func showUpdateInProgress() {
        guard !scratchGroup.updateInProgress else { return }
        navigationItem.rightBarButtonItem?.isEnabled = false
        scratchGroup.setUpdateInProgress()
    }
    
    
    private func hideUpdateInProgress() {
        guard scratchGroup.updateInProgress else { return }
        scratchGroup.removeUpdateInProgress()
        navigationItem.rightBarButtonItem?.isEnabled = true
    }
 
    
    // MARK: - PersonalNoteEditorViewActionsDelegate
    
    func userWantsToDismissPersonalNoteEditorView() async {
        guard presentedViewController is PersonalNoteEditorHostingController else { return }
        presentedViewController?.dismiss(animated: true)
    }
    
    
    @MainActor
    func userWantsToUpdatePersonalNote(with newText: String?) async {
        ObvMessengerInternalNotification.userWantsToUpdatePersonalNoteOnGroupV2(ownedCryptoId: currentOwnedCryptoId, groupIdentifier: referenceGroup.groupIdentifier, newText: newText)
            .postOnDispatchQueue()
        presentedViewController?.dismiss(animated: true)
    }

    
    // MARK: - EditNicknameAndCustomPictureViewControllerDelegate
    
    func userWantsToSaveNicknameAndCustomPicture(controller: EditNicknameAndCustomPictureViewController, identifier: EditNicknameAndCustomPictureView.Model.IdentifierKind, nickname: String, customPhoto: UIImage?) async {
        let ownedCryptoId: ObvCryptoId
        let groupV2Identifier: GroupV2Identifier
        switch identifier {
        case .contact:
            assertionFailure("The controller is expected to be configured with an identifier corresponding to the group shown by this view controller")
            return
        case .groupV2(let _groupV2Identifier):
            guard scratchGroup.groupIdentifier == _groupV2Identifier else { assertionFailure(); return }
            guard let _ownedCryptoId = try? scratchGroup.ownCryptoId else { assertionFailure(); return }
            groupV2Identifier = _groupV2Identifier
            ownedCryptoId = _ownedCryptoId
        }
        let sanitizedNickname = nickname.trimmingWhitespacesAndNewlines()
        ObvMessengerInternalNotification.userWantsToUpdateCustomNameAndGroupV2Photo(
            ownedCryptoId: ownedCryptoId,
            groupIdentifier: groupV2Identifier,
            customName: sanitizedNickname,
            customPhoto: customPhoto)
        .postOnDispatchQueue()
        controller.dismiss(animated: true)
    }
    
    
    func userWantsToDismissEditNicknameAndCustomPictureViewController(controller: EditNicknameAndCustomPictureViewController) async {
        controller.dismiss(animated: true)
    }

}


// MARK: - SingleGroupV2ViewDelegate

protocol SingleGroupV2ViewDelegate: AnyObject, GroupMembersViewActionsProtocol {
    func userWantsToAddGroupMembers()
    func userWantsToNavigateToPersistedObvContactIdentity(_ contact: PersistedObvContactIdentity)
    func userWantsToNavigateToDiscussion()
    func userWantsToCall() async
    func userWantsToReplaceTrustedDetailsByPublishedDetails()
    func userWantsToPerformReDownloadOfGroupV2()
    func userWantsToLeaveGroup()
    func userWantsToPerformDisbandOfGroupV2()
    func userWantsToEditDetailsOfGroupAsAdmin()
    func userWantsToCloneThisGroup()
}


// MARK: - SingleGroupV2View

struct SingleGroupV2View: View {
    
    @ObservedObject var group: PersistedGroupV2
    let delegate: SingleGroupV2ViewDelegate
    
    @State private var presentedAlertType = AlertType.cannotLeaveGroupAsWeAreTheOnlyAdmin
    @State private var isAlertPresented = false

    @State private var presentedSheetType = SheetType.confirmLeaveGroup
    @State private var isSheetPresented = false

    enum AlertType {
        case cannotLeaveGroupAsWeAreTheOnlyAdmin
        case cannotLeaveGroupAsThisIsKeycloakGroup
    }
    
    enum SheetType {
        case confirmLeaveGroup
        case confirmDisbandGroup
    }
    
    private var textViewModelForHeaderOrTrustedDetails: TextView.Model {
        .init(titlePart1: group.displayName,
              titlePart2: nil,
              subtitle: group.displayedDescription,
              subsubtitle: nil)
    }
    
    private var profilePictureViewModelContentForHeaderOrTrustedDetails: ProfilePictureView.Model.Content {
        .init(text: nil,
              icon: .person3Fill,
              profilePicture: group.circledInitialsConfiguration.photo,
              showGreenShield: group.keycloakManaged,
              showRedShield: false)
    }
    
    private var circleAndTitlesViewModelContentForHeaderOrTrustedDetails: CircleAndTitlesView.Model.Content {
        .init(textViewModel: textViewModelForHeaderOrTrustedDetails,
              profilePictureViewModelContent: profilePictureViewModelContentForHeaderOrTrustedDetails)
    }
    
    private var initialCircleViewModelColorsForHeaderOrTrustedDetails: InitialCircleView.Model.Colors {
        .init(background: group.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
              foreground: group.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared))
    }
    
    private var circleAndTitlesViewModelForHeader: CircleAndTitlesView.Model {
        .init(content: circleAndTitlesViewModelContentForHeaderOrTrustedDetails,
              colors: initialCircleViewModelColorsForHeaderOrTrustedDetails,
              displayMode: .header,
              editionMode: .none)
    }
    
    private var textViewModelForPublishedDetails: TextView.Model {
        .init(titlePart1: group.displayNamePublished,
              titlePart2: nil,
              subtitle: group.displayedDescriptionPublished,
              subsubtitle: nil)
    }
    
    private var profilePictureViewModelContentForPublishedDetails: ProfilePictureView.Model.Content {
        .init(text: nil,
              icon: .person3Fill,
              profilePicture: group.circledInitialsConfigurationPublished.photo,
              showGreenShield: group.keycloakManaged,
              showRedShield: false)
    }
    
    private var circleAndTitlesViewModelContentForPublishedDetails: CircleAndTitlesView.Model.Content {
        .init(textViewModel: textViewModelForPublishedDetails,
              profilePictureViewModelContent: profilePictureViewModelContentForPublishedDetails)
    }
    
    private var initialCircleViewModelColorsForPublishedDetails: InitialCircleView.Model.Colors {
        .init(background: group.circledInitialsConfigurationPublished.backgroundColor(appTheme: AppTheme.shared),
              foreground: group.circledInitialsConfigurationPublished.foregroundColor(appTheme: AppTheme.shared))
    }
    
    private var circleAndTitlesViewModelForPublishedDetails: CircleAndTitlesView.Model {
        .init(content: circleAndTitlesViewModelContentForPublishedDetails,
              colors: initialCircleViewModelColorsForPublishedDetails,
              displayMode: .normal,
              editionMode: .none)
    }
            
    private var circleAndTitlesViewModelForTrustedDetails: CircleAndTitlesView.Model {
        .init(content: circleAndTitlesViewModelContentForHeaderOrTrustedDetails,
              colors: initialCircleViewModelColorsForHeaderOrTrustedDetails,
              displayMode: .normal,
              editionMode: .none)
    }
    
    var body: some View {
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .edgesIgnoringSafeArea(.all)
            ScrollView {
                VStack {
                    
                    
                    // Header
                    CircleAndTitlesView(model: circleAndTitlesViewModelForHeader)
                        .padding(.top, 16)

                    
                    // Chat and call buttons
                    
                    HStack {
                        OlvidButton(style: .standardWithBlueText,
                                    title: Text(CommonString.Word.Chat),
                                    systemIcon: .textBubbleFill,
                                    action: { delegate.userWantsToNavigateToDiscussion() })
                        OlvidButton(style: .standardWithBlueText,
                                    title: Text(CommonString.Word.Call),
                                    systemIcon: .phoneFill,
                                    action: { Task { await delegate.userWantsToCall() } })
                    }
                    .padding(.top, 16)
                    
                    // Personal note viewer
                    
                    if let personalNote = group.personalNote, !personalNote.isEmpty {
                        PersonalNoteView(model: group)
                            .padding(.top, 16)
                    }
                    
                    // View shown when an update is in progress
                    
                    if group.updateInProgress {
                        ObvCardView(padding: 0) {
                            HStack(alignment: .top, spacing: 8) {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("GROUP_UPDATE_IN_PROGRESS_EXPLANATION_TITLE")
                                        .font(.system(.headline, design: .rounded))
                                        .lineLimit(1)
                                    Text("GROUP_UPDATE_IN_PROGRESS_EXPLANATION_BODY")
                                        .font(.footnote)
                                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                                        .lineLimit(nil)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding()
                        }
                        .padding(.top, 16)
                    }
                    
                    // Card for published details
                    
                    if group.hasPublishedDetails {
                        ObvCardView(padding: 0) {
                            VStack(alignment: .leading, spacing: 0) {
                                TopLeftTextForCardView(text: Text("New"))
                                VStack(alignment: .leading, spacing: 0) {
                                    CircleAndTitlesView(model: circleAndTitlesViewModelForPublishedDetails)
                                    HStack { Spacer() }
                                    Text("GROUP_V2_PUBLISHED_DETAILS_EXPLANATION_\(UIDevice.current.name)")
                                        .font(.callout)
                                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                                        .padding(.top, 16)
                                    OlvidButton(olvidButtonAction: OlvidButtonAction(action: {
                                        delegate.userWantsToReplaceTrustedDetailsByPublishedDetails()
                                    }, title: Text("UPDATE_DETAILS"), systemIcon: .checkmarkCircleFill))
                                        .padding(.top, 16)
                                }
                                .padding()
                            }
                        }
                        .padding(.top, 16)
                    }
                    
                    // Card for trusted details

                    ObvCardView(padding: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            TopLeftTextForCardView(text: Text("ON_MY_DEVICE_\(UIDevice.current.name)"))
                            VStack(alignment: .leading, spacing: 0) {
                                CircleAndTitlesView(model: circleAndTitlesViewModelForTrustedDetails)
                                HStack { Spacer() }
                            }
                            .padding()
                        }
                    }
                    .padding(.top, 16)

                    // Group members
                    
                    GroupMembersView(ownedIdentityIsAdmin: group.ownedIdentityIsAdmin,
                                     otherMembers: Array(group.otherMembersSorted),
                                     delegate: delegate,
                                     updateInProgress: group.updateInProgress,
                                     actions: delegate)
                    .padding(.bottom, 16)

                    Spacer()

                    VStack(spacing: 8) {
                        
                        // Button for manual resync (always enabled)
                        
                        OlvidButton(style: .standardWithBlueText, title: Text("MANUAL_RESYNC_OF_GROUP_V2"), systemIcon: .arrowTriangle2CirclepathCircleFill) { delegate.userWantsToPerformReDownloadOfGroupV2() }
                                                
                        // Button for cloning the group
                        
                        OlvidButton(style: .standardWithBlueText, title: Text("CLONE_THIS_GROUP"), systemIcon: .docOnDoc) { delegate.userWantsToCloneThisGroup() }
                            .disabled(group.updateInProgress)
                        
                        // Button for leaving the group
                        
                        OlvidButton(style: .red, title: Text("LEAVE_GROUP"), systemIcon: .xmarkOctagon) {
                            switch group.ownedIdentityCanLeaveGroup {
                            case .canLeaveGroup:
                                presentedSheetType = .confirmLeaveGroup
                                isSheetPresented = true
                            case .cannotLeaveGroupAsWeAreTheOnlyAdmin:
                                presentedAlertType = .cannotLeaveGroupAsWeAreTheOnlyAdmin
                                isAlertPresented = true
                            case .cannotLeaveGroupAsThisIsKeycloakGroup:
                                presentedAlertType = .cannotLeaveGroupAsThisIsKeycloakGroup
                                isAlertPresented = true
                            }
                        }
                        
                        // Button for disbanding the group
                        
                        if group.ownedIdentityIsAdmin {
                            OlvidButton(style: .red, title: Text("DISBAND_GROUP"), systemIcon: .trashCircle) {
                                presentedSheetType = .confirmDisbandGroup
                                isSheetPresented = true
                            }
                        }
                        
                    }

                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .alert(isPresented: $isAlertPresented) {
            switch presentedAlertType {
            case .cannotLeaveGroupAsWeAreTheOnlyAdmin:
                return Alert(title: Text("SINGLE_GROUP_V2_VIEW_ALERT_CANNOT_LEAVE_GROUP_TITLE"),
                             message: Text("SINGLE_GROUP_V2_VIEW_ALERT_CANNOT_LEAVE_GROUP_MESSAGE"),
                             dismissButton: Alert.Button.default(Text("Ok"))
                )
            case .cannotLeaveGroupAsThisIsKeycloakGroup:
                return Alert(title: Text("SINGLE_GROUP_V2_VIEW_ALERT_CANNOT_LEAVE_GROUP_AS_KEYCLOAK_TITLE"),
                             message: Text("SINGLE_GROUP_V2_VIEW_ALERT_CANNOT_LEAVE_GROUP_AS_KEYCLOAK_MESSAGE"),
                             dismissButton: Alert.Button.default(Text("Ok"))
                )
            }
        }
        .actionSheet(isPresented: $isSheetPresented) {
            switch presentedSheetType {
            case .confirmLeaveGroup:
                return ActionSheet(title: Text("SINGLE_GROUP_V2_VIEW_SHEET_CONFIRM_LEAVE_GROUP_TITLE"),
                                   message: Text("SINGLE_GROUP_V2_VIEW_SHEET_CONFIRM_LEAVE_GROUP_MESSAGE"),
                                   buttons: [
                                    .destructive(Text("SINGLE_GROUP_V2_VIEW_SHEET_CONFIRM_LEAVE_GROUP_BUTTON_TITLE")) {
                                        delegate.userWantsToLeaveGroup()
                                    },
                                    .cancel()
                                   ])
            case .confirmDisbandGroup:
                return ActionSheet(title: Text("SINGLE_GROUP_V2_VIEW_SHEET_CONFIRM_DISBAND_GROUP_TITLE"),
                                   message: Text("SINGLE_GROUP_V2_VIEW_SHEET_CONFIRM_DISBAND_GROUP_MESSAGE"),
                                   buttons: [
                                    .destructive(Text("SINGLE_GROUP_V2_VIEW_SHEET_CONFIRM_DISBAND_GROUP_BUTTON_TITLE")) {
                                        delegate.userWantsToPerformDisbandOfGroupV2()
                                    },
                                    .cancel()
                                   ])
            }
        }
    }
    
}





// MARK: - GroupMembersView

protocol GroupMembersViewActionsProtocol {
    
    func rollbackAllModifications()
    func userWantsToPublishAllModifications()
    func userWantsToInviteAllMembersWithChannelToOneToOne() async throws
    
}


fileprivate struct GroupMembersView: View {
    
    let ownedIdentityIsAdmin: Bool
    let otherMembers: [PersistedGroupV2Member]
    let delegate: SingleGroupV2ViewDelegate?
    let updateInProgress: Bool
    let actions: GroupMembersViewActionsProtocol // Expected to be non nil
//    let rollbackAllModifications: (() -> Void)? // Expected to be non nil
//    let publishAllModifications: (() -> Void)? // Expected to be non nil

    @State private var editMode = false
    @State private var tappedContact: PersistedObvContactIdentity? = nil
    @State private var isInviteAllAlertPresented = false
    @State private var hudCategory: HUDView.Category?

    
    private func userWantsToInviteAllGroupMembersToOneToOne() {
        withAnimation {
            hudCategory = .progress
        }
        Task {
            do {
                try await actions.userWantsToInviteAllMembersWithChannelToOneToOne()
                await dismissHUD(success: true)
            } catch {
                await dismissHUD(success: false)
            }
        }
    }
    
    
    @MainActor
    private func dismissHUD(success: Bool) async {
        withAnimation { hudCategory = success ? .checkmark : .xmark }
        try? await Task.sleep(for: 2)
        withAnimation { hudCategory = nil }
    }
    
    
    var body: some View {
        
        ZStack {
            
            VStack {
                
                HStack {
                    Text("OTHER_GROUP_MEMBERS")
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.bold)
                    Spacer()
                }
                .padding(.top, 16)
                
                ObvCardView(padding: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        
                        if ownedIdentityIsAdmin {
                            
                            if !editMode {
                                
                                HStack {
                                    
                                    OlvidButton(olvidButtonAction: OlvidButtonAction(
                                        action: { withAnimation { editMode.toggle() } },
                                        title: Text("EDIT_GROUP_MEMBERS_AS_ADMINISTRATOR_BUTTON_TITLE"),
                                        systemIcon: .person2Circle))
                                    .disabled(updateInProgress)
                                    
                                    OlvidButton(olvidButtonAction: OlvidButtonAction(
                                        action: { delegate?.userWantsToEditDetailsOfGroupAsAdmin() },
                                        title: Text("EDIT_GROUP_DETAILS_AS_ADMINISTRATOR_BUTTON_TITLE"),
                                        systemIcon: .pencil(.circle)))
                                    .disabled(updateInProgress)
                                    
                                }
                                
                            } else {
                                
                                VStack {
                                    OlvidButton(olvidButtonAction: OlvidButtonAction(
                                        action: { delegate?.userWantsToAddGroupMembers() },
                                        title: Text("ADD_GROUP_MEMBERS"),
                                        systemIcon: .personCropCircleBadgePlus))
                                    HStack {
                                        OlvidButton(style: .red,
                                                    title: Text(CommonString.Word.Cancel),
                                                    systemIcon: .xmarkCircle,
                                                    action: { withAnimation { actions.rollbackAllModifications(); editMode.toggle() } })
                                        .transition(.asymmetric(insertion: .move(edge: .leading), removal: .scale))
                                        OlvidButton(style: .green,
                                                    title: Text("PUBLISH"),
                                                    systemIcon: .checkmarkCircle,
                                                    action: { withAnimation { actions.userWantsToPublishAllModifications(); editMode.toggle() } })
                                        .disabled(updateInProgress)
                                        .transition(.asymmetric(insertion: .scale, removal: .scale))
                                    }
                                }
                                
                            }
                            
                            Divider()
                                .padding(.vertical, 16)
                            
                        }
                        
                        if otherMembers.isEmpty {
                            
                            if ownedIdentityIsAdmin {
                                
                                HStack {
                                    Text("ADD_MEMBER_BY_TAPPING_EDIT_GROUP_MEMBERS_BUTTON")
                                        .font(.callout)
                                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                                    Spacer()
                                }
                                
                            } else {
                                
                                HStack {
                                    Text("NO_OTHER_MEMBER_FOR_NOW")
                                        .font(.callout)
                                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                                    Spacer()
                                }
                                
                            }
                            
                        } else {
                            
                            ForEach(otherMembers) { otherMember in
                                SingleGroupMemberView(otherMember: otherMember, editMode: editMode, selected: tappedContact != nil && tappedContact == otherMember.contact)
                                    .onTapGesture {
                                        guard !editMode else { return }
                                        guard let contact = otherMember.contact else { return }
                                        withAnimation {
                                            tappedContact = contact
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
                                            delegate?.userWantsToNavigateToPersistedObvContactIdentity(contact)
                                        }
                                    }
                                    .onAppear {
                                        withAnimation {
                                            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
                                                tappedContact = nil
                                            }
                                        }
                                    }
                                if otherMember != otherMembers.last {
                                    Divider()
                                        .padding(.vertical, 16)
                                        .padding(.leading, 76)
                                }
                            }
                            
                            if !editMode {
                                OlvidButton(style: .blue, title: Text("INVITE_ALL_GROUP_MEMBERS_BUTTON_TITLE"), systemIcon: .personCropCircleBadgePlus) {
                                    isInviteAllAlertPresented.toggle()
                                }
                                .padding(.top)
                                .confirmationDialog(
                                    "INVITE_ALL_GROUP_MEMBERS_BUTTON_TITLE",
                                    isPresented: $isInviteAllAlertPresented
                                ) {
                                    Button(action: userWantsToInviteAllGroupMembersToOneToOne ) {
                                        Label("INVITE_ALL_GROUP_MEMBERS_BUTTON_TITLE", systemIcon: .personCropCircleBadgePlus)
                                    }
                                    Button("Cancel", role: .cancel, action: {})
                                } message: {
                                    Text("INVITE_ALL_GROUP_MEMBERS_EXPLANATION")
                                }
                                
                            }
                            
                        }
                        
                    }.padding()
                }
                
            } // End of VStack
            
            if let hudCategory {
                HUDView(category: hudCategory)
            }
            
        }
        
    }
    
}


struct SingleGroupMemberView: View {
    
    @ObservedObject var otherMember: PersistedGroupV2Member
    let editMode: Bool
    let selected: Bool

    private var informativeTextAboutPendingStatusAndAdminStatus: Text? {
        switch (editMode, otherMember.isPending, otherMember.isAnAdmin) {
        case (false, false, false): return nil
        case (false, false, true): return Text("IS_ADMIN")
        case (false, true, false): return Text("IS_PENDING")
        case (false, true, true): return Text("IS_PENDING_ADMIN")
        case (true, false, false): return Text("IS_NOT_ADMIN")
        case (true, false, true): return Text("IS_ADMIN")
        case (true, true, false): return Text("IS_NOT_ADMIN")
        case (true, true, true): return Text("IS_ADMIN")
        }
    }
    
    
    private var circleAndTitlesViewModel: CircleAndTitlesView.Model {
        .init(content: otherMember.circleAndTitlesViewModelContent,
              colors: otherMember.initialCircleViewModelColors,
              displayMode: .normal,
              editionMode: .none)
    }
    
    
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            OlvidButtonSquare(style: .redOnTransparentBackground, systemIcon: .trash, action: {
                withAnimation {
                    try? otherMember.delete()
                }
            })
            .opacity(editMode ? 1.0 : 0.0)
            .frame(width: editMode ? nil : 0.0, height: editMode ? nil : 0.0)
            CircleAndTitlesView(model: circleAndTitlesViewModel)
            Spacer()
            VStack(alignment: .center, spacing: 0) {
                Toggle("", isOn: Binding<Bool>(
                    get: { otherMember.isAnAdmin },
                    set: { otherMember.setPermissionAdmin(to: $0) }
                )
                )
                .labelsHidden()
                .padding(.bottom, 4)
                .opacity(editMode ? 1.0 : 0.0)
                .frame(height: editMode ? nil : 0.0)
                informativeTextAboutPendingStatusAndAdminStatus
                    .multilineTextAlignment(.center)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
            }
            .frame(width: 60) // Heuristic, width of "Not admin"
            if let persistedContact = otherMember.contact {
                SpinnerViewForContactCell(model: persistedContact)
            }
            if !editMode {
                ObvChevron(selected: selected)
            }
        }
        .contentShape(Rectangle()) // This makes it possible to have an "on tap" gesture that also works when the Spacer is tapped
    }
    
}
