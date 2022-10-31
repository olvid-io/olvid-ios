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
  

import SwiftUI
import os.log
import ObvTypes
import CoreData
import OlvidUtils
import ObvEngine


protocol SingleGroupV2ViewControllerDelegate: AnyObject {
    func userWantsToDisplay(persistedContact: PersistedObvContactIdentity, within: UINavigationController?)
    func userWantsToSelectAndCallContactsOfPersistedGroupV2(objectID: TypeSafeManagedObjectID<PersistedGroupV2>)
    func userWantsToDisplay(persistedDiscussion discussion: PersistedDiscussion)
    func userWantsToCloneGroup(displayedContactGroupObjectID: TypeSafeManagedObjectID<DisplayedContactGroup>)
}


final class SingleGroupV2ViewController: UIHostingController<SingleGroupV2View>, SingleGroupV2ViewDelegate, ObvErrorMaker {
    
    let persistedGroupV2ObjectID: TypeSafeManagedObjectID<PersistedGroupV2>
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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = scratchGroup.displayName
        
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18.0, weight: .bold)
        let image = UIImage(systemIcon: .squareAndPencil, withConfiguration: symbolConfiguration)
        let buttonItem = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(editGroupCustomNameAndCustomPhotoButtonItemTapped))
        buttonItem.tintColor = AppTheme.shared.colorScheme.olvidLight
        
        navigationItem.rightBarButtonItem = buttonItem

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
            ObvMessengerCoreDataNotification.observePersistedGroupV2UpdateIsFinished(queue: OperationQueue.main) { [weak self] objectID in
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
    

    @objc func editGroupCustomNameAndCustomPhotoButtonItemTapped() {
        guard let ownedCryptoId = try? scratchGroup.ownCryptoId else { assertionFailure(); return }
        let ownedGroupEditionFlowVC = GroupEditionFlowViewController(
            ownedCryptoId: ownedCryptoId,
            editionType: .editGroupV2CustomNameAndCustomPhoto(groupIdentifier: scratchGroup.groupIdentifier),
            obvEngine: obvEngine)
        present(ownedGroupEditionFlowVC, animated: true)
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
        func userWantsToCall() {
            delegate?.userWantsToCall()
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
                                                    allowEmptySetOfContacts: false) { [weak self] selectedContacts in
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
    
    
    func userWantsToCall() {
        delegate?.userWantsToSelectAndCallContactsOfPersistedGroupV2(objectID: scratchGroup.typedObjectID)
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
            let ownCryptoId = try scratchGroup.ownCryptoId
            ObvMessengerGroupV2Notifications.groupV2TrustedDetailsShouldBeReplacedByPublishedDetails(ownCryptoId: ownCryptoId, groupIdentifier: scratchGroup.groupIdentifier)
                .postOnDispatchQueue()
        } catch {
            assertionFailure()
        }
    }
    
    
    func userWantsToPerformReDownloadOfGroupV2() {
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
                try obvEngine.performReDownloadOfGroupV2(ownedCryptoId: ownedCryptoId, groupIdentifier: groupIdentifier)
            } catch {
                assertionFailure(error.localizedDescription)
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
    
}


// MARK: - SingleGroupV2ViewDelegate

protocol SingleGroupV2ViewDelegate: AnyObject {
    func userWantsToAddGroupMembers()
    func rollbackAllModifications()
    func userWantsToNavigateToPersistedObvContactIdentity(_ contact: PersistedObvContactIdentity)
    func userWantsToNavigateToDiscussion()
    func userWantsToCall()
    func userWantsToPublishAllModifications()
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
    let delegate: SingleGroupV2ViewDelegate?
    
    @State private var presentedAlertType = AlertType.cannotLeaveGroup
    @State private var isAlertPresented = false

    @State private var presentedSheetType = SheetType.confirmLeaveGroup
    @State private var isSheetPresented = false

    enum AlertType {
        case cannotLeaveGroup
    }
    
    enum SheetType {
        case confirmLeaveGroup
        case confirmDisbandGroup
    }
    
    var body: some View {
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .edgesIgnoringSafeArea(.all)
            ScrollView {
                VStack {
                    
                    
                    // Header
                    
                    CircleAndTitlesView(titlePart1: group.displayName,
                                        titlePart2: nil,
                                        subtitle: nil,
                                        subsubtitle: nil,
                                        circleBackgroundColor: group.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
                                        circleTextColor: group.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared),
                                        circledTextView: nil,
                                        systemImage: .person3Fill,
                                        profilePicture: group.circledInitialsConfiguration.photo,
                                        alignment: .top,
                                        showGreenShield: false,
                                        showRedShield: false,
                                        editionMode: .none,
                                        displayMode: .header)
                    .padding(.top, 16)

                    
                    // Chat and call buttons
                    
                    HStack {
                        OlvidButton(style: .standardWithBlueText,
                                    title: Text(CommonString.Word.Chat),
                                    systemIcon: .textBubbleFill,
                                    action: { delegate?.userWantsToNavigateToDiscussion() })
                        OlvidButton(style: .standardWithBlueText,
                                    title: Text(CommonString.Word.Call),
                                    systemIcon: .phoneFill,
                                    action: { delegate?.userWantsToCall() })
                    }
                    .padding(.top, 16)
                    
                    // View shown when an update is in progress
                    
                    if group.updateInProgress {
                        ObvCardView(padding: 0) {
                            HStack(alignment: .top, spacing: 8) {
                                if #available(iOS 14, *) {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                }
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
                                    CircleAndTitlesView(titlePart1: group.displayNamePublished,
                                                        titlePart2: nil,
                                                        subtitle: group.displayedDescriptionPublished,
                                                        subsubtitle: nil,
                                                        circleBackgroundColor: group.circledInitialsConfigurationPublished.backgroundColor(appTheme: AppTheme.shared),
                                                        circleTextColor: group.circledInitialsConfigurationPublished.foregroundColor(appTheme: AppTheme.shared),
                                                        circledTextView: nil,
                                                        systemImage: .person3Fill,
                                                        profilePicture: group.circledInitialsConfigurationPublished.photo,
                                                        showGreenShield: false,
                                                        showRedShield: false,
                                                        editionMode: .none,
                                                        displayMode: .normal)
                                    HStack { Spacer() }
                                    Text("GROUP_V2_PUBLISHED_DETAILS_EXPLANATION_\(UIDevice.current.name)")
                                        .font(.callout)
                                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                                        .padding(.top, 16)
                                    OlvidButton(olvidButtonAction: OlvidButtonAction(action: {
                                        delegate?.userWantsToReplaceTrustedDetailsByPublishedDetails()
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
                                CircleAndTitlesView(titlePart1: group.displayName,
                                                    titlePart2: nil,
                                                    subtitle: group.displayedDescription,
                                                    subsubtitle: nil,
                                                    circleBackgroundColor: group.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
                                                    circleTextColor: group.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared),
                                                    circledTextView: nil,
                                                    systemImage: .person3Fill,
                                                    profilePicture: group.circledInitialsConfiguration.photo,
                                                    showGreenShield: false,
                                                    showRedShield: false,
                                                    editionMode: .none,
                                                    displayMode: .normal)
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
                                     rollbackAllModifications: delegate?.rollbackAllModifications,
                                     publishAllModifications: delegate?.userWantsToPublishAllModifications)
                    .padding(.bottom, 16)

                    Spacer()

                    VStack(spacing: 8) {
                        
                        // Button for manual resync (always enabled)
                        
                        OlvidButton(style: .standard, title: Text("MANUAL_RESYNC_OF_GROUP_V2"), systemIcon: .arrowTriangle2CirclepathCircleFill) { delegate?.userWantsToPerformReDownloadOfGroupV2() }
                        
                        // Button for cloning the group
                        
                        OlvidButton(style: .standard, title: Text("CLONE_THIS_GROUP"), systemIcon: .docOnDoc) { delegate?.userWantsToCloneThisGroup() }
                            .disabled(group.updateInProgress)
                        
                        // Button for leaving the group
                        
                        OlvidButton(style: .red, title: Text("LEAVE_GROUP"), systemIcon: .xmarkOctagon) {
                            if group.ownedIdentityCanLeaveGroup {
                                presentedSheetType = .confirmLeaveGroup
                                isSheetPresented = true
                            } else {
                                presentedAlertType = .cannotLeaveGroup
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
            case .cannotLeaveGroup:
                return Alert(title: Text("SINGLE_GROUP_V2_VIEW_ALERT_CANNOT_LEAVE_GROUP_TITLE"),
                             message: Text("SINGLE_GROUP_V2_VIEW_ALERT_CANNOT_LEAVE_GROUP_MESSAGE"),
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
                                        delegate?.userWantsToLeaveGroup()
                                    },
                                    .cancel()
                                   ])
            case .confirmDisbandGroup:
                return ActionSheet(title: Text("SINGLE_GROUP_V2_VIEW_SHEET_CONFIRM_DISBAND_GROUP_TITLE"),
                                   message: Text("SINGLE_GROUP_V2_VIEW_SHEET_CONFIRM_DISBAND_GROUP_MESSAGE"),
                                   buttons: [
                                    .destructive(Text("SINGLE_GROUP_V2_VIEW_SHEET_CONFIRM_DISBAND_GROUP_BUTTON_TITLE")) {
                                        delegate?.userWantsToPerformDisbandOfGroupV2()
                                    },
                                    .cancel()
                                   ])
            }
        }
    }
    
}


fileprivate struct GroupMembersView: View {
    
    let ownedIdentityIsAdmin: Bool
    let otherMembers: [PersistedGroupV2Member]
    let delegate: SingleGroupV2ViewDelegate?
    let updateInProgress: Bool
    let rollbackAllModifications: (() -> Void)? // Expected to be non nil
    let publishAllModifications: (() -> Void)? // Expected to be non nil

    @State private var editMode = false
    @State private var tappedContact: PersistedObvContactIdentity? = nil

    var body: some View {
        
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
                                            action: { withAnimation { rollbackAllModifications?(); editMode.toggle() } })
                                .transition(.asymmetric(insertion: .move(edge: .leading), removal: .scale))
                                OlvidButton(style: .green,
                                            title: Text("PUBLISH"),
                                            systemIcon: .checkmarkCircle,
                                            action: { withAnimation { publishAllModifications?(); editMode.toggle() } })
                                .disabled(updateInProgress)
                                .transition(.asymmetric(insertion: .scale, removal: .scale))
                            }
                        }
                        
                    }
                    
                    Divider()
                        .padding(.vertical, 16)
                    
                }
                
                if otherMembers.isEmpty && ownedIdentityIsAdmin {
                    
                    Text("ADD_MEMBER_BY_TAPPING_EDIT_GROUP_MEMBERS_BUTTON")
                        .font(.callout)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))

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

                }

            }.padding()
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
    
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            OlvidButtonSquare(style: .redOnTransparentBackground, systemIcon: .trash, action: {
                withAnimation {
                    try? otherMember.delete()
                }
            })
            .opacity(editMode ? 1.0 : 0.0)
            .frame(width: editMode ? nil : 0.0, height: editMode ? nil : 0.0)
            CircleAndTitlesView(titlePart1: otherMember.displayedFirstName,
                                titlePart2: otherMember.displayedCustomDisplayNameOrLastName,
                                subtitle: otherMember.displayedPosition,
                                subsubtitle: otherMember.displayedCompany,
                                circleBackgroundColor: otherMember.contact?.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
                                circleTextColor: otherMember.contact?.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared),
                                circledTextView: nil,
                                systemImage: .person,
                                profilePicture: otherMember.displayedProfilePicture,
                                showGreenShield: false,
                                showRedShield: false,
                                editionMode: .none,
                                displayMode: .normal)
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
            if !editMode {
                ObvChevron(selected: selected)
            }
        }
        .contentShape(Rectangle()) // This makes it possible to have an "on tap" gesture that also works when the Spacer is tapped
    }
    
}




struct SingleGroupV2InnerView_Previews: PreviewProvider {

    fileprivate static let group: PersistedGroupV2 = {
        let groupIdentifier = Data(repeating: 0, count: 16)
        let ownedIdentity = Data(repeating: 1, count: 16)
        return PersistedGroupV2.mocObject(
            customName: "Group name3",
            groupIdentifier: groupIdentifier,
            keycloakManaged: false,
            ownPermissionAdmin: true,
            rawOwnedIdentityIdentity: Data(repeating: 1, count: 16),
            updateInProgress: false,
            otherMembers: Set<PersistedGroupV2Member>([
                PersistedGroupV2Member.mocObject(
                    company: "Apple",
                    firstName: "Alice",
                    groupIdentifier: groupIdentifier,
                    identity: Data(repeating: 2, count: 16),
                    isPending: false,
                    lastName: "Work",
                    permissionAdmin: false,
                    position: "Manager",
                    rawOwnedIdentityIdentity: ownedIdentity),
                PersistedGroupV2Member.mocObject(
                    company: "Olvid",
                    firstName: "Bob",
                    groupIdentifier: groupIdentifier,
                    identity: Data(repeating: 2, count: 16),
                    isPending: false,
                    lastName: "Home",
                    permissionAdmin: false,
                    position: "Happiness Officer",
                    rawOwnedIdentityIdentity: ownedIdentity),
                PersistedGroupV2Member.mocObject(
                    company: "Some company",
                    firstName: "Charlize",
                    groupIdentifier: groupIdentifier,
                    identity: Data(repeating: 2, count: 16),
                    isPending: false,
                    lastName: "Laptop",
                    permissionAdmin: true,
                    position: "CEO",
                    rawOwnedIdentityIdentity: ownedIdentity),
            ])
        )
    }()
    
    static var previews: some View {
        SingleGroupV2View(group: Self.group, delegate: nil)
    }

}
