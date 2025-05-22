/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvEngine
import ObvTypes
import os.log
import CoreData
import ObvCrypto
import OlvidUtils
import ObvUICoreData
import ObvSettings
import ObvAppCoreConstants
import ObvAppTypes
import ObvDesignSystem
import ObvUIGroupV2
import UniformTypeIdentifiers
import ObvKeycloakManager


@MainActor
protocol ObvFlowController: UINavigationController, SingleDiscussionViewControllerDelegate, SingleGroupViewControllerDelegate, SingleContactIdentityViewHostingControllerDelegate, ObvErrorMaker, ObvUIGroupV2RouterDelegateForCreation, ObvUIGroupV2RouterDelegateForEdition, EditNicknameAndCustomPictureViewControllerDelegate {

    var flowDelegate: ObvFlowControllerDelegate? { get }
    var log: OSLog { get }
    var obvEngine: ObvEngine { get }
    var observationTokens: [NSObjectProtocol] { get set }
    var floatingButton: UIButton? { get set } // Used on iOS 18+ only
    var delegatesStack: ObvFlowControllerDelegatesStack { get }
    
    var routerForGroupCreation: ObvUIGroupV2Router { get }
    var routerForGroupEdition: ObvUIGroupV2Router { get }
    var appDataSourceForObvUIGroupV2Router: AppDataSourceForObvUIGroupV2Router { get }

    @MainActor
    func userWantsToDisplay(persistedDiscussion discussion: PersistedDiscussion)
    
    @MainActor
    func userWantsToDisplay(persistedMessage message: PersistedMessage)
    
    // Switching the current owned identity
    
    var currentOwnedCryptoId: ObvCryptoId { get }
    func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) async

}


// MARK: - Floating Plus button under iOS18

extension ObvFlowController {
    
    @available(iOS 18, *)
    @MainActor private func createConfiguredFloatingButton() -> UIButton {
        
        var config = UIButton.Configuration.filled()
        config.buttonSize = .large
        
        //config.image = UIImage(systemIcon: .plus)?.applyingSymbolConfiguration(.init(weight: .heavy))
        config.image = UIImage(systemIcon: .personBadgePlus)
        config.baseBackgroundColor = UIColor(named: "Blue01")
        config.title = NSLocalizedString("FLOATING_BUTTON_TITLE_ADD_CONTACT", comment: "Floating button title")
        config.imagePadding = 12.0
        
        config.cornerStyle = .capsule
        
        let action = UIAction(handler: { [weak self] _ in
            guard let self else { return }
            flowDelegate?.floatingButtonTapped(flow: self)
        })
        
        let button = UIButton(configuration: config, primaryAction: action)
        
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.2
        button.layer.shadowRadius = 8.0

        return button
        
    }
    
    
    /// All custom `UINavigationController` that implement `ObvFlowController` leverage this method to add the "Add a contact" floating button under iOS18+.
    @available(iOS 18, *)
    @MainActor func addFloatingButtonIfRequired() {
        
        guard floatingButton == nil else { return }
        
        guard let rootViewController = self.viewControllers.first else {
            assertionFailure()
            return
        }
        
        let button = createConfiguredFloatingButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        
        rootViewController.view.addSubview(button)
        
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: rootViewController.view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            button.bottomAnchor.constraint(equalTo: rootViewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            button.widthAnchor.constraint(lessThanOrEqualTo: rootViewController.view.safeAreaLayoutGuide.widthAnchor, multiplier: 1.0),
        ])
        
        floatingButton = button
        
    }

}


// MARK: - Showing/Hiding SnackBar

extension ObvFlowController {
    
    func showSnackBar(with category: OlvidSnackBarCategory, currentOwnedCryptoId: ObvCryptoId, completion: @escaping () -> Void) {
    
        removeSnackBar { [weak self] in
            guard let _self = self else { completion(); return }
            guard let firstVC = _self.children.first else { completion(); return }
            let snackBar = OlvidSnackBarView()
            snackBar.alpha = 0.0
            snackBar.configure(with: category, ownedCryptoId: currentOwnedCryptoId)
            firstVC.view.addSubview(snackBar)
            snackBar.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                snackBar.trailingAnchor.constraint(equalTo: firstVC.view.trailingAnchor),
                snackBar.bottomAnchor.constraint(equalTo: firstVC.view.safeAreaLayoutGuide.bottomAnchor),
                snackBar.leadingAnchor.constraint(equalTo: firstVC.view.leadingAnchor),
            ])
            UIView.animate(withDuration: 0.3) {
                snackBar.alpha = 1.0
            } completion: { _ in
                completion()
            }

        }
        
    }
    
    
    func removeSnackBar(completion: @escaping () -> Void) {
        guard let firstVC = children.first else { completion(); return }
        guard let snackBar = firstVC.view.subviews.compactMap({ $0 as? OlvidSnackBarView }).first else {
            completion()
            return
        }
        UIView.animate(withDuration: 0.3) {
            snackBar.alpha = 0.0
        } completion: { _ in
            snackBar.removeFromSuperview()
            completion()
        }

    }
    
}


// MARK: Centralised stack management

extension ObvFlowController {
    
    /// This method should be called from the `viewDidLoad` method of all view controllers (conforming to this protocol)
    func observeNotificationsImpactingTheNavigationStack() {
        observationTokens.append(contentsOf: [
            ObvMessengerCoreDataNotification.observePersistedGroupV2WasDeleted { [weak self] groupIdentifier in
                Task { [weak self] in await self?.removeGroupViewController(groupIdentifier: groupIdentifier) }
            },
            ObvEngineNotificationNew.observeContactGroupDeleted(within: NotificationCenter.default) { _, _, groupUid in
                Task { [weak self] in await self?.removeGroupViewController(groupUid: groupUid) }
            },
        ])
    }

}


// MARK: - Implementations of protocol methods

extension ObvFlowController {
    
    func userWantsToDisplay(persistedDiscussion discussion: PersistedDiscussion) {
        userWantsToDisplayImpl(persistedDiscussion: discussion, messageToShow: nil)
    }

    func userWantsToDisplay(persistedMessage message: PersistedMessage) {
        guard let discussion = message.discussion else { assertionFailure(); return }
        userWantsToDisplayImpl(persistedDiscussion: discussion, messageToShow: message)
    }

    private func userWantsToDisplayImpl(persistedDiscussion discussion: PersistedDiscussion, messageToShow: PersistedMessage?) {
                
        assert(Thread.isMainThread)
        os_log("User wants to display persisted discussion", log: log, type: .info)

        let discussionToDisplay: PersistedDiscussion
        if discussion.managedObjectContext == ObvStack.shared.viewContext {
            discussionToDisplay = discussion
        } else {
            guard let _discussion = try? PersistedDiscussion.get(objectID: discussion.typedObjectID, within: ObvStack.shared.viewContext) else {
                assertionFailure()
                return
            }
            discussionToDisplay = _discussion
        }
        
        let messageToDisplay: PersistedMessage?
        if let messageToShow = messageToShow {
            if messageToShow.managedObjectContext == ObvStack.shared.viewContext {
                messageToDisplay = messageToShow
            } else {
                if let _message = try? PersistedMessage.get(with: messageToShow.typedObjectID, within: ObvStack.shared.viewContext) {
                    messageToDisplay = _message
                } else {
                    assertionFailure()
                    messageToDisplay = nil
                }
            }
        } else {
            messageToDisplay = nil
        }
        
        // Dismiss any presented view controller
        if let presentedViewController = presentedViewController {
            presentedViewController.dismiss(animated: true, completion: { [weak self] in
                self?.popOrPushDiscussionViewController(for: discussionToDisplay, messageToShow: messageToDisplay)
            })
        } else {
            popOrPushDiscussionViewController(for: discussionToDisplay, messageToShow: messageToDisplay)
        }
    }

    
    private func popOrPushDiscussionViewController(for discussion: PersistedDiscussion, messageToShow: PersistedMessage?) {
        
        assert(Thread.isMainThread)
        assert(discussion.managedObjectContext == ObvStack.shared.viewContext)

        // Look for an existing SingleDiscussionViewController and pop to it if found
        for vc in children {
            guard let discussionVC = vc as? SomeSingleDiscussionViewController else { continue }
            guard discussionVC.discussionObjectID == discussion.typedObjectID else { continue }
            // If we reach this point, there exists an appropriate SingleDiscussionViewController within the navigation stack, so we pop to this VC and return
            popToViewController(discussionVC, animated: true)
            if let messageToShow = messageToShow {
                discussionVC.scrollTo(message: messageToShow)
            }
            return
        }
        
        os_log("Will instantiate a singleDiscussionVC", log: log, type: .info)
        
        // If we reach this point, we need to push a new SingleDiscussionViewController.

        let discussionVC: SomeSingleDiscussionViewController
        do {
            discussionVC = try buildSingleDiscussionVC(discussion: discussion, messageToShow: messageToShow)
        } catch {
            assertionFailure(error.localizedDescription)
            return
        }
        showDetailViewController(discussionVC, sender: self)

        // There might be some AirDrop'ed files, add them to the discussion draft
        if let airDroppedFileURLs = flowDelegate?.getAndRemoveAirDroppedFileURLs() {
            for url in airDroppedFileURLs {
                discussionVC.addAttachmentFromAirDropFile(at: url)
            }
        }

    }


    @MainActor
    func removeGroupViewController(groupUid: UID) async {
        assert(Thread.isMainThread)
        var newViewController = [UIViewController]()
        for vc in viewControllers {
            guard let groupVC = vc as? SingleGroupViewController, groupVC.obvContactGroup.groupUid == groupUid else {
                newViewController += [vc]
                continue
            }
            // Skip the view controller
        }
        setViewControllers(newViewController, animated: true)
    }


    /// If a a PersistedGroupV2 gets deleted (e.g., because we were kicked from the group), we want to dismiss any pushed `SingleGroupV2ViewController`.
    @MainActor
    private func removeGroupViewController(groupIdentifier: ObvGroupV2Identifier) async {
        routerForGroupEdition.removeFromNavigationAllViewControllersRelatingToGroup(navigationController: self, groupIdentifier: groupIdentifier)
    }

}


// MARK: - Helping the MainFlowViewController when a discussion gets deleted

extension ObvFlowController {
    
    @MainActor
    func removeAllSomeSingleDiscussionViewControllerForDiscussionWithPermanentID(_ discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>) async {
        let newStack = self.viewControllers.compactMap { viewController in
            guard let someSingleDiscussionVC = viewController as? SomeSingleDiscussionViewController else { return viewController }
            return (someSingleDiscussionVC.discussionPermanentID == discussionPermanentID) ? nil : someSingleDiscussionVC
        }
        self.setViewControllers(newStack, animated: true)
    }
    

    @MainActor
    func refreshAllSingleDiscussionViewControllerForDiscussion(_ discussion: PersistedDiscussion) async throws {
        let newStack = try self.viewControllers.compactMap { viewController in
            guard let someSingleDiscussionVC = viewController as? SomeSingleDiscussionViewController else { return viewController }
            if someSingleDiscussionVC.discussionPermanentID != discussion.discussionPermanentID {
                return someSingleDiscussionVC
            } else {
                return try getNewSingleDiscussionViewController(for:discussion, initialScroll: .newMessageSystemOrLastMessage)
            }
        }
        self.setViewControllers(newStack, animated: false)
    }
    
    
    func buildSingleDiscussionVC(discussion: PersistedDiscussion, messageToShow: PersistedMessage?) throws -> SomeSingleDiscussionViewController {
        let initialScroll: NewSingleDiscussionViewController.InitialScroll
        if let messageToShow = messageToShow {
            initialScroll = .specificMessage(messageToShow)
        } else {
            initialScroll = .newMessageSystemOrLastMessage
        }
        let singleDiscussionVC = try getNewSingleDiscussionViewController(for: discussion, initialScroll: initialScroll)
        return singleDiscussionVC
    }

    
    func getNewSingleDiscussionViewController(for discussion: PersistedDiscussion, initialScroll: NewSingleDiscussionViewController.InitialScroll) throws -> NewSingleDiscussionViewController {
        assert(Thread.isMainThread)
        let singleDiscussionVC = try NewSingleDiscussionViewController(discussion: discussion, delegate: self, initialScroll: initialScroll)
        singleDiscussionVC.hidesBottomBarWhenPushed = true
        return singleDiscussionVC
    }
    
}

// MARK: - Implementing SingleDiscussionViewControllerDelegate

extension ObvFlowController {
    
    /// Called when the user taps on a message representing `PersistedLocationContinuous`.
    func userWantsToShowMapToConsultLocationSharedContinously(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>) async throws {
        guard let flowDelegate else { assertionFailure(); throw Self.makeError(message: "Flow delegate is nil") }
        try await flowDelegate.userWantsToShowMapToConsultLocationSharedContinously(self, presentingViewController: singleDiscussionViewController, messageObjectID: messageObjectID)
    }
    
    func userWantsToShowMapToSendOrShareLocationContinuously(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, discussionIdentifier: ObvDiscussionIdentifier) async throws {
        guard let flowDelegate else { assertionFailure(); throw Self.makeError(message: "Flow delegate is nil") }
        try await flowDelegate.userWantsToShowMapToSendOrShareLocationContinuously(self, presentingViewController: singleDiscussionViewController, discussionIdentifier: discussionIdentifier)
    }
    
    
    func userWantsToStopSharingLocationInDiscussion(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, discussionIdentifier: ObvDiscussionIdentifier) async throws {
        guard let flowDelegate else { assertionFailure(); throw Self.makeError(message: "Flow delegate is nil") }
        try await flowDelegate.userWantsToStopSharingLocationInDiscussion(self, discussionIdentifier: discussionIdentifier)
    }
    
    
    func userWantsToUpdateReaction(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, ownedCryptoId: ObvCryptoId, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, newEmoji: String?) async throws {
        guard let flowDelegate else { assertionFailure(); throw Self.makeError(message: "Flow delegate is nil") }
        try await flowDelegate.userWantsToUpdateReaction(self, ownedCryptoId: ownedCryptoId, messageObjectID: messageObjectID, newEmoji: newEmoji)
    }
    
    
    func messagesAreNotNewAnymore(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageIds: [MessageIdentifier]) async throws {
        guard let flowDelegate else { assertionFailure(); throw Self.makeError(message: "Flow delegate is nil") }
        try await flowDelegate.messagesAreNotNewAnymore(self, ownedCryptoId: ownedCryptoId, discussionId: discussionId, messageIds: messageIds)
    }
    
    
    func updatedSetOfCurrentlyDisplayedMessagesWithLimitedVisibility(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentIDs: Set<ObvManagedObjectPermanentID<PersistedMessage>>) async throws {
        guard let flowDelegate else { assertionFailure(); throw Self.makeError(message: "Flow delegate is nil") }
        try await flowDelegate.updatedSetOfCurrentlyDisplayedMessagesWithLimitedVisibility(self, discussionPermanentID: discussionPermanentID, messagePermanentIDs: messagePermanentIDs)
    }
    
    
    func userWantsToReadReceivedMessageThatRequiresUserAction(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageId: ReceivedMessageIdentifier) async throws {
        guard let flowDelegate else { assertionFailure(); throw Self.makeError(message: "Flow delegate is nil") }
        try await flowDelegate.userWantsToReadReceivedMessageThatRequiresUserAction(self, ownedCryptoId: ownedCryptoId, discussionId: discussionId, messageId: messageId)
    }
    
    
    func userWantsToUpdateDraftExpiration(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, value: PersistedDiscussionSharedConfigurationValue?) async throws {
        guard let flowDelegate else { assertionFailure(); throw Self.makeError(message: "Flow delegate is nil") }
        try await flowDelegate.userWantsToUpdateDraftExpiration(self, draftObjectID: draftObjectID, value: value)
    }
    
    
    func insertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, markAsRead: Bool) async throws {
        guard let flowDelegate else { assertionFailure(); throw Self.makeError(message: "Flow delegate is nil") }
        try await flowDelegate.insertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty(self, discussionObjectID: discussionObjectID, markAsRead: markAsRead)
    }
    
    
    func userWantsToRemoveReplyToMessage(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws {
        guard let flowDelegate else { assertionFailure(); throw Self.makeError(message: "Flow delegate is nil") }
        try await flowDelegate.userWantsToRemoveReplyToMessage(self, draftObjectID: draftObjectID)
    }
    
    
    func userWantsToPauseSentFyleMessageJoinWithStatusFromOtherOwnedDevice(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>) async throws {
        guard let flowDelegate else { assertionFailure(); throw Self.makeError(message: "Flow delegate is nil") }
        try await flowDelegate.userWantsToPauseSentFyleMessageJoinWithStatusFromOtherOwnedDevice(self, sentJoinObjectID: sentJoinObjectID)
    }
    
    
    func userWantsToDownloadSentFyleMessageJoinWithStatusFromOtherOwnedDevice(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>) async throws {
        guard let flowDelegate else { assertionFailure(); throw Self.makeError(message: "Flow delegate is nil") }
        try await flowDelegate.userWantsToDownloadSentFyleMessageJoinWithStatusFromOtherOwnedDevice(self, sentJoinObjectID: sentJoinObjectID)
    }
    
    
    func userWantsToPauseDownloadReceivedFyleMessageJoinWithStatus(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) async throws {
        guard let flowDelegate else { assertionFailure(); throw Self.makeError(message: "Flow delegate is nil") }
        try await flowDelegate.userWantsToPauseDownloadReceivedFyleMessageJoinWithStatus(self, receivedJoinObjectID: receivedJoinObjectID)
    }
    
    
    func userWantsToDownloadReceivedFyleMessageJoinWithStatus(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) async throws {
        guard let flowDelegate else { assertionFailure(); throw Self.makeError(message: "Flow delegate is nil") }
        try await flowDelegate.userWantsToDownloadReceivedFyleMessageJoinWithStatus(self, receivedJoinObjectID: receivedJoinObjectID)
    }
    
    func userWantsToReplyToMessage(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws {
        guard let flowDelegate else { assertionFailure(); throw Self.makeError(message: "Flow delegate is nil") }
        try await flowDelegate.userWantsToReplyToMessage(self, messageObjectID: messageObjectID, draftObjectID: draftObjectID)
    }
    
    
    func userWantsToDeleteAttachmentsFromDraft(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, draftTypeToDelete: DeleteAllDraftFyleJoinOfDraftOperation.DraftType) async {
        guard let flowDelegate else { assertionFailure(); return }
        await flowDelegate.userWantsToDeleteAttachmentsFromDraft(self, draftObjectID: draftObjectID, draftTypeToDelete: draftTypeToDelete)
    }
    
    
    func userWantsToUpdateDraftBodyAndMentions(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, body: String, mentions: Set<MessageJSON.UserMention>) async throws {
        guard let flowDelegate else { assertionFailure(); throw Self.makeError(message: "Flow delegate is nil") }
        try await flowDelegate.userWantsToUpdateDraftBodyAndMentions(self, draftObjectID: draftObjectID, body: body, mentions: mentions)
    }
    
    func userWantsToAddAttachmentsToDraftFromURLs(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, urls: [URL]) async throws {
        guard let flowDelegate else { assertionFailure(); throw Self.makeError(message: "Flow delegate is nil") }
        try await flowDelegate.userWantsToAddAttachmentsToDraftFromURLs(self, draftPermanentID: draftPermanentID, urls: urls)
    }

    
    func userWantsToAddAttachmentsToDraft(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, itemProviders: [NSItemProvider]) async throws {
        guard let flowDelegate else { assertionFailure(); throw Self.makeError(message: "Flow delegate is nil") }
        try await flowDelegate.userWantsToAddAttachmentsToDraft(self, draftPermanentID: draftPermanentID, itemProviders: itemProviders)
    }
    
    
    func userWantsToSendDraft(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, textBody: String, mentions: Set<MessageJSON.UserMention>) async throws {
        guard let flowDelegate else { assertionFailure(); throw Self.makeError(message: "Flow delegate is nil") }
        try await flowDelegate.userWantsToSendDraft(self, draftPermanentID: draftPermanentID, textBody: textBody, mentions: mentions)
    }

    
    func userTappedTitleOfDiscussion(_ discussion: PersistedDiscussion) {
        
        let vcToPresent: UIViewController
        
        switch try? discussion.kind {
            
        case .oneToOne(withContactIdentity: let contactIdentity):
            
            // In case the title tapped is the one of a one2one discussion, we display the contact sheet of the contact
            guard let contactIdentity = contactIdentity else {
                os_log("Could not find contact identity. This is ok if it has just been deleted.", log: log, type: .error)
                return
            }
            do {
                vcToPresent = try SingleContactIdentityViewHostingController(contact: contactIdentity, obvEngine: obvEngine)
            } catch {
                assertionFailure(error.localizedDescription)
                return
            }
            (vcToPresent as? SingleContactIdentityViewHostingController)?.delegate = self
            
        case .groupV1(withContactGroup: let contactGroup):
            
            guard let contactGroup = contactGroup else {
                os_log("Could find contact group (this is ok if it was just deleted)", log: log, type: .error)
                return
            }
            guard let singleGroupVC = try? SingleGroupViewController(persistedContactGroup: contactGroup, obvEngine: obvEngine) else { return }
            singleGroupVC.delegate = self
            vcToPresent = singleGroupVC
            
        case .groupV2(withGroup: let group):
            
            guard let obvGroupIdentifier = try? group?.obvGroupIdentifier else {
                os_log("Could find group V2 (this is ok if it was just deleted)", log: log, type: .error)
                return
            }
            
            guard let singleGroupV2VC = routerForGroupEdition.getInitialViewControllerToPresentForGroupEdition(groupIdentifier: obvGroupIdentifier) else {
                assertionFailure()
                return
            }

            vcToPresent = singleGroupV2VC

        case .none:
            
            assertionFailure()
            return
            
        }
        
        let closeButton = BlockBarButtonItem.forClosing { [weak self] in self?.presentedViewController?.dismiss(animated: true) }
        vcToPresent.navigationItem.setLeftBarButton(closeButton, animated: false)
        present(UINavigationController(rootViewController: vcToPresent), animated: true)
        
    }
    
    
    @MainActor
    func userDidTapOnContactImage(contactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>) {
        
        assert(Thread.isMainThread)
        
        guard let contactIdentity = try? PersistedObvContactIdentity.get(objectID: contactObjectID, within: ObvStack.shared.viewContext) else {
            os_log("Could not find contact identity. This is ok if it has just been deleted.", log: log, type: .error)
            return
        }
        
        guard let contactIdentifier = try? contactIdentity.contactIdentifier else { assertionFailure(); return }
        
        userWantsToPresentSingleContactIdentityView(contactIdentifier: contactIdentifier)

    }
    
    
    @MainActor
    func userWantsToPresentSingleContactIdentityView(contactIdentifier: ObvContactIdentifier) {
        
        guard let contactIdentity = try? PersistedObvContactIdentity.get(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: ObvStack.shared.viewContext) else {
            os_log("Could not find contact identity. This is ok if it has just been deleted.", log: log, type: .error)
            return
        }

        let vcToPresent: SingleContactIdentityViewHostingController
        do {
            vcToPresent = try SingleContactIdentityViewHostingController(contact: contactIdentity, obvEngine: obvEngine)
        } catch {
            assertionFailure(error.localizedDescription)
            return
        }
        vcToPresent.delegate = self

        let closeButton = BlockBarButtonItem.forClosing { [weak self] in self?.presentedViewController?.dismiss(animated: true) }
        vcToPresent.navigationItem.setLeftBarButton(closeButton, animated: false)
        present(UINavigationController(rootViewController: vcToPresent), animated: true)

        
    }
    
    
    private func userWantsToPresentMyId(ownedCryptoId: ObvCryptoId) {
        
        guard let ownedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: ObvStack.shared.viewContext) else {
            os_log("Could not find owned identity. This is ok if it has just been deleted.", log: log, type: .error)
            assertionFailure()
            return
        }

        let vcToPresent = SingleOwnedIdentityFlowViewController(ownedIdentity: ownedIdentity, obvEngine: obvEngine, delegate: flowDelegate)

        let closeButton = BlockBarButtonItem.forClosing { [weak self] in self?.presentedViewController?.dismiss(animated: true) }
        vcToPresent.navigationItem.setLeftBarButton(closeButton, animated: false)
        if let presentedViewController {
            presentedViewController.dismiss(animated: true) { [weak self] in
                self?.present(UINavigationController(rootViewController: vcToPresent), animated: true)
            }
        } else {
            present(UINavigationController(rootViewController: vcToPresent), animated: true)
        }

    }
    
    
    /// Called when the user taps on a mention in a single discussion view controller. In that case, we present the appropriate detail view controller, depending on the ``mentionableIdentity`` that was tapped.
    @MainActor
    func singleDiscussionViewController(_ viewController: any SomeSingleDiscussionViewController, userDidTapOn mentionableIdentity: ObvMentionableIdentityAttribute.Value) async {

        switch mentionableIdentity {
            
        case .ownedIdentity(ownedCryptoId: let ownedCryptoId):
            
            userWantsToPresentMyId(ownedCryptoId: ownedCryptoId)
            
        case .contact(let contactIdentifier):
            
            userWantsToPresentSingleContactIdentityView(contactIdentifier: contactIdentifier)
            
        case .groupV2Member(groupIdentifier: let groupIdentifier, memberId: _):
            
            guard let persistedGroupV2 = try? PersistedGroupV2.get(ownIdentity: groupIdentifier.ownedCryptoId,
                                                                   appGroupIdentifier: groupIdentifier.identifier.appGroupIdentifier,
                                                                   within: ObvStack.shared.viewContext)
            else {
                return
            }
            userWantsToPresentSingleGroupView(persistedGroupV2: persistedGroupV2)
            
        }
    }
    
}

// MARK: - SingleContactViewControllerDelegate

extension ObvFlowController {

    func userWantsToNavigateToListOfContactDevicesView(_ contact: PersistedObvContactIdentity, within nav: UINavigationController?) {
        let appropriateNav = nav ?? self
        let vc = ListOfContactDevicesViewController(persistedContact: contact, obvEngine: obvEngine)
        appropriateNav.pushViewController(vc, animated: true)
    }
    
    
    func userWantsToNavigateToListOfTrustOriginsView(_ trustOrigins: [ObvTrustOrigin], within nav: UINavigationController?) {
        let appropriateNav = nav ?? self
        let vc = ListOfTrustOriginsViewController(trustOrigins: trustOrigins)
        appropriateNav.pushViewController(vc, animated: true)
    }
    
    
    func userWantsToNavigateToSingleGroupView(_ group: DisplayedContactGroup, within nav: UINavigationController?) {
        
        assert(group.groupV1 == nil || group.groupV2 == nil)
        
        let appropriateNav = nav ?? self

        if let groupV1 = group.groupV1 {
            userWantsToNavigateToSingleGroupView(persistedContactGroup: groupV1, within: appropriateNav)
        } else if let groupV2 = group.groupV2 {
            do {
                let groupIdentifier = try groupV2.obvGroupIdentifier
                userWantsToNavigateToSingleGroupView(groupIdentifier: groupIdentifier, within: appropriateNav)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        } else {
            assertionFailure()
        }
        
    }

    
    private func userWantsToNavigateToSingleGroupView(persistedContactGroup: PersistedContactGroup, within nav: UINavigationController) {
                
        for vc in nav.children {
            guard let singleGroupViewController = vc as? SingleGroupViewController else { continue }
            guard singleGroupViewController.persistedContactGroup.objectID == persistedContactGroup.objectID else { continue }
            // If we reach this point, there exists an appropriate SingleGroupViewController within the navigation stack, so we pop to this VC and return
            nav.popToViewController(singleGroupViewController, animated: true)
            return
        }
        // If we reach this point, we could not find an appropriate VC within the navigation stack, so we push a new one
        guard let singleGroupViewController = try? SingleGroupViewController(persistedContactGroup: persistedContactGroup, obvEngine: obvEngine) else { return }
        singleGroupViewController.delegate = self
        nav.pushViewController(singleGroupViewController, animated: true)

    }

    
    @MainActor
    public func userWantsToPresentSingleGroupView(_ group: DisplayedContactGroup) {

        assert(group.groupV1 == nil || group.groupV2 == nil)
        
        if let groupV1 = group.groupV1 {
            userWantsToPresentSingleGroupView(persistedContactGroup: groupV1)
        } else if let groupV2 = group.groupV2 {
            userWantsToPresentSingleGroupView(persistedGroupV2: groupV2)
        } else {
            assertionFailure()
        }
        
    }
    
    
    @MainActor
    private func userWantsToPresentSingleGroupView(persistedContactGroup: PersistedContactGroup) {
        
        guard let singleGroupViewController = try? SingleGroupViewController(persistedContactGroup: persistedContactGroup, obvEngine: obvEngine) else { return }
        singleGroupViewController.delegate = self
        if let presentedViewController {
            presentedViewController.dismiss(animated: true) { [weak self] in
                self?.present(singleGroupViewController, animated: true)
            }
        } else {
            present(singleGroupViewController, animated: true)
        }
        
    }

    
    @MainActor
    private func userWantsToPresentSingleGroupView(persistedGroupV2: PersistedGroupV2) {
        guard let groupIdentifier: ObvGroupV2Identifier = try? persistedGroupV2.obvGroupIdentifier else {
            assertionFailure()
            return
        }
        guard let vcToPresent = routerForGroupEdition.getInitialViewControllerToPresentForGroupEdition(groupIdentifier: groupIdentifier) else {
            assertionFailure()
            return
        }
        self.presentOnTop(vcToPresent, animated: true)
    }
    
    
    func userWantsToUpdateTrustedIdentityDetailsOfContactIdentity(with contactCryptoId: ObvCryptoId, using newContactIdentityDetails: ObvIdentityDetails) {
        flowDelegate?.userWantsToUpdateTrustedIdentityDetailsOfContactIdentity(with: contactCryptoId, using: newContactIdentityDetails)
    }
    

    func userWantsToInviteContactToOneToOne(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId) {
        Task { [weak self] in
            guard let self else { return }
            do {
                assert(flowDelegate != nil)
                try await flowDelegate?.userWantsToInviteContactsToOneToOne(ownedCryptoId: ownedCryptoId, users: [(contactCryptoId, nil)])
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }
    
    
    func userWantsToCancelSentInviteContactToOneToOne(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId) {
        Task {
            try await cancelSentInviteContactToOneToOne(ownedCryptoId: ownedCryptoId, contactCryptoId: contactCryptoId)
        }
    }
    
    
    private func cancelSentInviteContactToOneToOne(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId) async throws {
        let log = self.log
        let obvEngine = self.obvEngine
        let dialog = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ObvDialog?, any Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    guard let oneToOneInvitationSent = try PersistedInvitationOneToOneInvitationSent.get(fromOwnedIdentity: ownedCryptoId,
                                                                                                         toContact: contactCryptoId,
                                                                                                         within: context) else {
                        assertionFailure()
                        return continuation.resume(returning: nil)
                    }
                    let dialog = oneToOneInvitationSent.obvDialog
                    return continuation.resume(returning: dialog)
                } catch {
                    os_log("Could not cancel OneToOne invitation: %{public}@", log: log, type: .fault, error.localizedDescription)
                    return continuation.resume(throwing: error)
                }
            }
        }
        guard var dialog else { return }
        try dialog.cancelOneToOneInvitationSent()
        let dialogForEngine = dialog
        try await obvEngine.respondTo(dialogForEngine)
    }
    
    
    func userWantsToSyncOneToOneStatusOfContact(persistedContactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>) {
        let log = self.log
        ObvStack.shared.performBackgroundTask { [weak self] (context) in
            do {
                guard let _self = self else { return }
                guard let contact = try PersistedObvContactIdentity.get(objectID: persistedContactObjectID, within: context) else { assertionFailure(); return }
                guard let ownedIdentity = contact.ownedIdentity else { assertionFailure(); return }
                let ownedCryptoId = ownedIdentity.cryptoId
                let contactToSync = contact.cryptoId
                Task {
                    do {
                        try await _self.obvEngine.requestOneStatusSyncRequest(ownedIdentity: ownedCryptoId, contactsToSync: Set([contactToSync]))
                    } catch {
                        os_log("Could not sync contact OneToOne status: %{public}@", log: log, type: .fault, error.localizedDescription)
                        assertionFailure()
                    }
                }
            } catch {
                os_log("Could not sync contact OneToOne status: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
        }
    }
    
}


// MARK: - SingleGroupViewControllerDelegate

extension ObvFlowController {
    
    func userWantsToDisplay(_ vc: SingleGroupViewController, persistedDiscussion discussion: PersistedDiscussion) {
        userWantsToDisplay(persistedDiscussion: discussion)
    }
    

    func userWantsToDisplay(_ vc: SingleGroupViewController, persistedContact: PersistedObvContactIdentity, within nav: UINavigationController?) {
        userWantsToDisplay(persistedContact: persistedContact, within: nav)
    }
    
    
    func userWantsToDisplay(persistedContact: PersistedObvContactIdentity, within nav: UINavigationController?) {
        let appropriateNav = nav ?? self

        for vc in appropriateNav.children {
            guard let singleContactIdentityViewHostingController = vc as? SingleContactIdentityViewHostingController else { continue }
            guard singleContactIdentityViewHostingController.contactCryptoId == persistedContact.cryptoId else { continue }
            // If we reach this point, there exists an appropriate SingleContactViewController within the navigation stack, so we pop to this VC and return
            appropriateNav.popToViewController(singleContactIdentityViewHostingController, animated: true)
            return
        }
        // If we reach this point, we could not find an appropriate VC within the navigation stack, so we push a new one
        let vcToPush: SingleContactIdentityViewHostingController
        do {
            vcToPush = try SingleContactIdentityViewHostingController(contact: persistedContact, obvEngine: obvEngine)
        } catch {
            assertionFailure(error.localizedDescription)
            return
        }
        vcToPush.delegate = self
        appropriateNav.pushViewController(vcToPush, animated: true)
    }

    
    func userWantsToCloneGroup(_ vc: SingleGroupViewController, persistedContactGroup: PersistedContactGroup) async throws {

        assert(Thread.isMainThread)
        
        let valuesOfGroupToClone = try await appDataSourceForObvUIGroupV2Router.getValuesOfGroupToClone(persistedContactGroup: persistedContactGroup)
        
        routerForGroupCreation.presentInitialViewControllerForGroupCreation(ownedCryptoId: currentOwnedCryptoId,
                                                                            presentingViewController: self,
                                                                            creationMode: .cloneExistingGroup(valuesOfGroupToClone: valuesOfGroupToClone))

    }
    
    
    private func displayAlertWhenTryingToCloneGroupV1WithMembersNotSupportingGroupsV2(contactsNotSupportingGroupV2: Set<PersistedObvContactIdentity>) {
        
        
        let arrrayOfMemberNames = contactsNotSupportingGroupV2.map({ $0.displayedCustomDisplayNameOrFirstNameOrLastName ?? $0.customOrNormalDisplayName })
        let allMemberNames = ListFormatter.localizedString(byJoining: arrrayOfMemberNames)
        let title = NSLocalizedString("SOME_GROUP_MEMBERS_MUST_UPGRADE", comment: "")
        let message = String.localizedStringWithFormat(NSLocalizedString("FOLLOWING_MEMBERS_MUST_UPGRADE_BEFORE_CREATING_GROUP_V2_%@", comment: ""), allMemberNames)
        
        let alert = UIAlertController.init(title: title,
                                           message: message,
                                           preferredStyle: .alert)
        
        alert.addAction(.init(title: CommonString.Word.Ok, style: .cancel))
        
        present(alert, animated: true)
        
    }

}


// MARK: - Implementing EditNicknameAndCustomPictureViewControllerDelegate

extension ObvFlowController {
    
    func userWantsToSaveNicknameAndCustomPicture(controller: EditNicknameAndCustomPictureViewController, identifier: EditNicknameAndCustomPictureView.Model.IdentifierKind, nickname: String, customPhoto: UIImage?) async {
        let ownedCryptoId: ObvCryptoId = self.currentOwnedCryptoId
        let groupV2Identifier: GroupV2Identifier
        switch identifier {
        case .contact:
            assertionFailure("The controller is expected to be configured with an identifier corresponding to the group shown by this view controller")
            return
        case .groupV2(let _groupV2Identifier):
            guard let group = try? PersistedGroupV2.getWithPrimaryKey(ownCryptoId: ownedCryptoId, groupIdentifier: _groupV2Identifier, within: ObvStack.shared.viewContext) else {
                assertionFailure()
                return
            }
            guard group.groupIdentifier == _groupV2Identifier else { assertionFailure(); return }
            groupV2Identifier = _groupV2Identifier
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


// MARK: - Implementing ObvUIGroupV2RouterDelegateForCreation

extension ObvFlowController {
 
    /// Called when the user hits the cancel button on the view allowing to choose the group members during a group creation. Also called after a group was created.
    func presentedGroupCreationFlowShouldBeDismissed(_ router: ObvUIGroupV2Router) {
        self.presentedViewController?.dismiss(animated: true)
    }

    
    func userWantsObtainAvatarDuringGroupCreation(_ router: ObvUIGroupV2Router, avatarSource: ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return try await userWantsObtainAvatar(avatarSource: avatarSource, avatarSize: avatarSize)
    }
    
    
    func userWantsToSaveImageToTempFileDuringGroupCreation(_ router: ObvUIGroupV2Router, image: UIImage) async throws -> URL {
        try await userWantsToSaveImageToTempFile(image: image)
    }
    
    
    func userWantsToPublishCreatedGroupV2(_ router: ObvUIGroupV2Router, ownedCryptoId: ObvCryptoId, groupDetails: ObvTypes.ObvGroupDetails, groupType: ObvGroupType, otherGroupMembers: Set<ObvGroupV2.IdentityAndPermissions>) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        
        let groupCoreDetails = GroupV2CoreDetails(groupName: groupDetails.coreDetails.name,
                                                  groupDescription: groupDetails.coreDetails.description)
        
        let ownPermissions: Set<ObvGroupV2.Permission> = ObvGroupType.exactPermissions(of: .admin, forGroupType: groupType)
        
        try await flowDelegate.userWantsToPublishGroupV2Creation(groupCoreDetails: groupCoreDetails,
                                                                 ownPermissions: ownPermissions,
                                                                 otherGroupMembers: otherGroupMembers,
                                                                 ownedCryptoId: ownedCryptoId,
                                                                 photoURL: groupDetails.photoURL,
                                                                 groupType: groupType)
        

    }
    
}


// MARK: - Implementing ObvUIGroupV2RouterDelegateForEdition

extension ObvFlowController {
    
    /// This method is not part of `ObvUIGroupV2RouterDelegateForEdition`, but allows to easily navigate
    @MainActor
    func userWantsToNavigateToSingleGroupView(groupIdentifier: ObvGroupV2Identifier, within navigationController: UINavigationController?) {
        routerForGroupEdition.pushOrPopInitialViewControllerForGroupEdition(navigationController: navigationController ?? self, groupIdentifier: groupIdentifier)
    }
    
    
    func userWantsToReplaceTrustedDetailsByPublishedDetails(_ router: ObvUIGroupV2Router, publishedDetails: PublishedDetailsValidationViewModel) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        let groupIdentifier = publishedDetails.groupIdentifier
        try await flowDelegate.userWantsToReplaceTrustedDetailsByPublishedDetails(self, groupIdentifier: groupIdentifier)
    }
    
    
    func userWantsToLeaveGroup(_ router: ObvUIGroupV2Router, groupIdentifier: ObvGroupV2Identifier) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userWantsToLeaveGroup(self, groupIdentifier: groupIdentifier)
    }
    
    
    func userWantsToDisbandGroup(_ router: ObvUIGroupV2Router, groupIdentifier: ObvGroupV2Identifier) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userWantsToDisbandGroup(self, groupIdentifier: groupIdentifier)
    }
    
    
    func userWantsToChat(_ router: ObvUIGroupV2Router, groupIdentifier: ObvGroupV2Identifier) async {
        guard let persistedGroup = try? PersistedGroupV2.get(ownIdentity: groupIdentifier.ownedCryptoId, appGroupIdentifier: groupIdentifier.identifier.appGroupIdentifier, within: ObvStack.shared.viewContext) else {
            assertionFailure()
            return
        }
        guard let persistedDiscussion = persistedGroup.discussion else {
            assertionFailure()
            return
        }
        self.userWantsToDisplayImpl(persistedDiscussion: persistedDiscussion, messageToShow: nil)
    }
    
    
    func userWantsToCall(_ router: ObvUIGroupV2Router, groupIdentifier: ObvGroupV2Identifier) async {
        guard let flowDelegate else { assertionFailure(); return }
        guard let persistedGroup = try? PersistedGroupV2.get(ownIdentity: groupIdentifier.ownedCryptoId, appGroupIdentifier: groupIdentifier.identifier.appGroupIdentifier, within: ObvStack.shared.viewContext) else {
            assertionFailure()
            return
        }
        let contactCryptoIds = Set(persistedGroup.otherMembers
            .filter({ !$0.isPending })
            .compactMap(\.cryptoId))
        await flowDelegate.userWantsToSelectAndCallContacts(flowController: self,
                                                            ownedCryptoId: groupIdentifier.ownedCryptoId,
                                                            contactCryptoIds: contactCryptoIds,
                                                            groupId: .groupV2(groupV2Identifier: groupIdentifier.identifier.appGroupIdentifier))
    }
    
    
    func userWantsToRemoveOtherUserFromGroup(_ router: ObvUIGroupV2Router, groupIdentifier: ObvGroupV2Identifier, contactIdentifier: ObvContactIdentifier) async throws {
        
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        
        guard groupIdentifier.ownedCryptoId == contactIdentifier.ownedCryptoId else {
            assertionFailure()
            throw ObvFlowControllerError.unexpectedOwnedCryptoId
        }
        guard let persistedGroup = try PersistedGroupV2.get(ownIdentity: groupIdentifier.ownedCryptoId, appGroupIdentifier: groupIdentifier.identifier.appGroupIdentifier, within: ObvStack.shared.viewContext) else {
            assertionFailure()
            throw ObvFlowControllerError.couldNotFindGRoup
        }
        
        let groupObjectID: TypeSafeManagedObjectID<PersistedGroupV2> = .init(objectID: persistedGroup.objectID)
        let changeset: ObvGroupV2.Changeset = try .init(changes: [.memberRemoved(contactCryptoId: contactIdentifier.contactCryptoId)])
        
        try await flowDelegate.userWantsToPublishGroupV2Modification(self, groupObjectID: groupObjectID, changeset: changeset)
        
    }
    
    
    func userWantsToRemoveMembersFromGroup(_ router: ObvUIGroupV2Router, groupIdentifier: ObvTypes.ObvGroupV2Identifier, membersToRemove: Set<SingleGroupMemberViewModelIdentifier>) async throws {
        
        guard !membersToRemove.isEmpty else { return }
        
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        
        for memberToRemove in membersToRemove {
            guard memberToRemove.groupIdentifier == groupIdentifier else {
                assertionFailure()
                throw ObvFlowControllerError.unexpectedGroupIdentifier
            }
        }
        
        guard let persistedGroup = try PersistedGroupV2.get(ownIdentity: groupIdentifier.ownedCryptoId, appGroupIdentifier: groupIdentifier.identifier.appGroupIdentifier, within: ObvStack.shared.viewContext) else {
            assertionFailure()
            throw ObvFlowControllerError.couldNotFindGRoup
        }
        
        let groupObjectID: TypeSafeManagedObjectID<PersistedGroupV2> = .init(objectID: persistedGroup.objectID)
        let changes: Set<ObvGroupV2.Change> = Set(try membersToRemove.map { memberIdentifier in
            switch memberIdentifier {
            case .contactIdentifierForExistingGroup(groupIdentifier: let groupIdentifier, contactIdentifier: let contactIdentifier):
                guard groupIdentifier.ownedCryptoId == contactIdentifier.ownedCryptoId else {
                    assertionFailure()
                    throw ObvFlowControllerError.unexpectedOwnedCryptoId
                }
                let contactCryptoId = contactIdentifier.contactCryptoId
                return .memberRemoved(contactCryptoId: contactCryptoId)
            case .objectIDOfPersistedGroupV2Member(groupIdentifier: _, objectID: let objectID):
                guard let groupMemberToRemove = persistedGroup.otherMembers.first(where: { $0.objectID == objectID }) else {
                    assertionFailure()
                    throw ObvFlowControllerError.groupMemberNotFound
                }
                let cryptoId = groupMemberToRemove.cryptoId
                return .memberRemoved(contactCryptoId: cryptoId)
            case .contactIdentifierForCreatingGroup:
                assertionFailure("This identifier shall only be used when creating a new group, not for an existing one.")
                throw ObvFlowControllerError.unexpectedIdentifier
            case .objectIDOfPersistedContact(objectID: _):
                assertionFailure("This identifier shall only be used when creating a new group, not for an existing one.")
                throw ObvFlowControllerError.unexpectedIdentifier
            }
        })
        let changeset: ObvGroupV2.Changeset = try .init(changes: changes)
        
        try await flowDelegate.userWantsToPublishGroupV2Modification(self, groupObjectID: groupObjectID, changeset: changeset)
        
    }
    
    
    func userWantsToUpdateGroupV2(_ router: ObvUIGroupV2Router, groupIdentifier: ObvGroupV2Identifier, changeset: ObvGroupV2.Changeset) async throws {
        
        guard !changeset.isEmpty else { return }
        
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        
        guard let persistedGroup = try PersistedGroupV2.get(ownIdentity: groupIdentifier.ownedCryptoId, appGroupIdentifier: groupIdentifier.identifier.appGroupIdentifier, within: ObvStack.shared.viewContext) else {
            assertionFailure()
            throw ObvFlowControllerError.couldNotFindGRoup
        }
        
        let groupObjectID: TypeSafeManagedObjectID<PersistedGroupV2> = .init(objectID: persistedGroup.objectID)
        
        try await flowDelegate.userWantsToPublishGroupV2Modification(self, groupObjectID: groupObjectID, changeset: changeset)
        
    }
    
    
    func userWantsObtainAvatarDuringGroupEdition(_ router: ObvUIGroupV2Router, avatarSource: ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return try await userWantsObtainAvatar(avatarSource: avatarSource, avatarSize: avatarSize)
    }
    
    
    private func userWantsObtainAvatar(avatarSource: ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        return try await flowDelegate.userWantsObtainAvatar(self, avatarSource: avatarSource, avatarSize: avatarSize)
    }
    
    
    func userWantsToSaveImageToTempFileDuringGroupEdition(_ router: ObvUIGroupV2Router, image: UIImage) async throws -> URL {
        try await userWantsToSaveImageToTempFile(image: image)
    }

    
    private func userWantsToSaveImageToTempFile(image: UIImage) async throws -> URL {
        guard let jpegData = image.jpegData(compressionQuality: 1.0) else { assertionFailure(); throw ObvFlowControllerError.couldNotGenerateJPEGData }
        let filename = [UUID().uuidString, UTType.jpeg.preferredFilenameExtension ?? "jpeg"].joined(separator: ".")
        let directoryForTempFiles = ObvUICoreDataConstants.ContainerURL.forTempFiles.url
        let filepath = directoryForTempFiles.appendingPathComponent(filename)
        try jpegData.write(to: filepath)
        return filepath
    }
    
    
    func userWantsToInviteOtherUserToOneToOne(_ router: ObvUIGroupV2Router, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        let users: [(cryptoId: ObvCryptoId, keycloakDetails: ObvKeycloakUserDetails?)] = [(contactIdentifier.contactCryptoId, nil)]
        try await flowDelegate.userWantsToInviteContactsToOneToOne(ownedCryptoId: contactIdentifier.ownedCryptoId, users: users)
    }
    
    
    func userWantsToInviteOtherUserToOneToOne(_ router: ObvUIGroupV2Router, contactIdentifiers: [ObvContactIdentifier]) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        let ownedCryptoIds = Set(contactIdentifiers.map { $0.ownedCryptoId })
        guard ownedCryptoIds.count == 1, let ownedCryptoId = ownedCryptoIds.first else { assertionFailure(); return }
        let users: [(cryptoId: ObvCryptoId, keycloakDetails: ObvKeycloakUserDetails?)] = contactIdentifiers.map { contactIdentifier in
            return (contactIdentifier.contactCryptoId, nil)
        }
        try await flowDelegate.userWantsToInviteContactsToOneToOne(ownedCryptoId: ownedCryptoId, users: users)
    }
    
    
    func userWantsToCancelOneToOneInvitationSent(_ router: ObvUIGroupV2Router, contactIdentifier: ObvContactIdentifier) async throws {
        try await cancelSentInviteContactToOneToOne(ownedCryptoId: contactIdentifier.ownedCryptoId,
                                                    contactCryptoId: contactIdentifier.contactCryptoId)
    }
    
    func userWantsToShowOtherUserProfile(_ router: ObvUIGroupV2Router, navigationController: UINavigationController, contactIdentifier: ObvTypes.ObvContactIdentifier) async {
        do {
            guard let persistedContact = try PersistedObvContactIdentity.get(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: ObvStack.shared.viewContext) else {
                assertionFailure("Could not find contact in database. Is the user a pending member of the group, not a contact yet?")
                return
            }
            userWantsToDisplay(persistedContact: persistedContact, within: navigationController)
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }
 
    
    func userWantsToUpdatePersonalNote(_ router: ObvUIGroupV2Router, groupIdentifier: ObvGroupV2Identifier, with newText: String?) async {
        let ownedCryptoId = groupIdentifier.ownedCryptoId
        let appGroupIdentifier: Data = groupIdentifier.identifier.appGroupIdentifier
        ObvMessengerInternalNotification.userWantsToUpdatePersonalNoteOnGroupV2(ownedCryptoId: ownedCryptoId, groupIdentifier: appGroupIdentifier, newText: newText)
            .postOnDispatchQueue()
    }
    
    
    func userWantsToEditGroupNicknameAndCustomPicture(_ router: ObvUIGroupV2Router, groupIdentifier: ObvGroupV2Identifier) {
        guard let group = try? PersistedGroupV2.getWithPrimaryKey(ownCryptoId: groupIdentifier.ownedCryptoId, groupIdentifier: groupIdentifier.identifier.appGroupIdentifier, within: ObvStack.shared.viewContext) else {
            assertionFailure()
            return
        }
        let groupV2Identifier = group.groupIdentifier
        let defaultPhoto: UIImage?
        if let url = group.trustedPhotoURL {
            defaultPhoto = UIImage(contentsOfFile: url.path)
        } else {
            defaultPhoto = nil
        }
        let currentCustomPhoto: UIImage?
        if let url = group.customPhotoURL {
            currentCustomPhoto = UIImage(contentsOfFile: url.path)
        } else {
            currentCustomPhoto = nil
        }
        let currentNickname = group.customNameSanitized ?? ""
        let vc = EditNicknameAndCustomPictureViewController(
            model: .init(identifier: .groupV2(groupV2Identifier: groupV2Identifier),
                         currentInitials: "", // No initials needed for groups
                         defaultPhoto: defaultPhoto,
                         currentCustomPhoto: currentCustomPhoto,
                         currentNickname: currentNickname),
            delegate: self)
        presentOnTop(vc, animated: true)
    }
    
    
    func userWantsToCloneGroup(_ router: ObvUIGroupV2Router, valuesOfGroupToClone: ObvUIGroupV2Router.ValuesOfClonedGroup) {
        routerForGroupCreation.presentInitialViewControllerForGroupCreation(ownedCryptoId: currentOwnedCryptoId,
                                                                            presentingViewController: self,
                                                                            creationMode: .cloneExistingGroup(valuesOfGroupToClone: valuesOfGroupToClone))
    }

    
    func userTappedOnManualResyncOfGroupV2Button(_ router: ObvUIGroupV2Router, groupIdentifier: ObvGroupV2Identifier) async throws {
        guard let persistedGroup = try PersistedGroupV2.get(groupIdentifier: groupIdentifier, within: ObvStack.shared.viewContext) else {
            assertionFailure()
            throw ObvFlowControllerError.couldNotFindGRoup
        }
        if persistedGroup.keycloakManaged {
            try await KeycloakManagerSingleton.shared.syncAllManagedIdentities()
        } else {
            try await obvEngine.performReDownloadOfGroupV2(ownedCryptoId: groupIdentifier.ownedCryptoId, groupIdentifier: groupIdentifier.identifier.appGroupIdentifier)
        }
    }

}


// MARK: - Errors

enum ObvFlowControllerError: Error {
    case couldNotFindOwnedIdentity
    case delegateIsNil
    case couldNotFindGRoup
    case unexpectedOwnedCryptoId
    case unexpectedGroupIdentifier
    case groupMemberNotFound
    case couldNotGenerateJPEGData
    case unexpectedIdentifier
}
    

// MARK: - ObvFlowControllerDelegate

protocol ObvFlowControllerDelegate: AnyObject, SingleOwnedIdentityFlowViewControllerDelegate {

    func getAndRemoveAirDroppedFileURLs() -> [URL]
    func performTrustEstablishmentProtocolOfRemoteIdentity(remoteCryptoId: ObvCryptoId, remoteFullDisplayName: String)
    func rePerformTrustEstablishmentProtocolOfContactIdentity(contactCryptoId: ObvCryptoId, contactFullDisplayName: String)
    func userWantsToUpdateTrustedIdentityDetailsOfContactIdentity(with: ObvCryptoId, using: ObvIdentityDetails)
    func userAskedToRefreshDiscussions() async throws
    func userWantsToInviteContactsToOneToOne(ownedCryptoId: ObvCryptoId, users: [(cryptoId: ObvCryptoId, keycloakDetails: ObvKeycloakUserDetails?)]) async throws
    func userWantsToPublishGroupV2Creation(groupCoreDetails: GroupV2CoreDetails, ownPermissions: Set<ObvGroupV2.Permission>, otherGroupMembers: Set<ObvGroupV2.IdentityAndPermissions>, ownedCryptoId: ObvCryptoId, photoURL: URL?, groupType: ObvAppTypes.ObvGroupType) async throws
    func userWantsToPublishGroupV2Modification(_ flowController: any ObvFlowController, groupObjectID: TypeSafeManagedObjectID<PersistedGroupV2>, changeset: ObvGroupV2.Changeset) async throws
    func userWantsToSendDraft(_ flowController: any ObvFlowController, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, textBody: String, mentions: Set<MessageJSON.UserMention>) async throws
    func userWantsToAddAttachmentsToDraft(_ flowController: any ObvFlowController, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, itemProviders: [NSItemProvider]) async throws
    func userWantsToAddAttachmentsToDraftFromURLs(_ flowController: any ObvFlowController, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, urls: [URL]) async throws
    func userWantsToUpdateDraftBodyAndMentions(_ flowController: any ObvFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, body: String, mentions: Set<MessageJSON.UserMention>) async throws
    func userWantsToDeleteAttachmentsFromDraft(_ flowController: any ObvFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, draftTypeToDelete: DeleteAllDraftFyleJoinOfDraftOperation.DraftType) async
    func userWantsToReplyToMessage(_ flowController: any ObvFlowController, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws
    func userWantsToDownloadReceivedFyleMessageJoinWithStatus(_ flowController: any ObvFlowController, receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) async throws
    func userWantsToPauseDownloadReceivedFyleMessageJoinWithStatus(_ flowController: any ObvFlowController, receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) async throws
    func userWantsToPauseSentFyleMessageJoinWithStatusFromOtherOwnedDevice(_ flowController: any ObvFlowController, sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>) async throws
    func userWantsToDownloadSentFyleMessageJoinWithStatusFromOtherOwnedDevice(_ flowController: any ObvFlowController, sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>) async throws
    func userWantsToRemoveReplyToMessage(_ flowController: any ObvFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws
    func insertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty(_ flowController: any ObvFlowController, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, markAsRead: Bool) async throws
    func userWantsToUpdateDraftExpiration(_ flowController: any ObvFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, value: PersistedDiscussionSharedConfigurationValue?) async throws
    func userWantsToReadReceivedMessageThatRequiresUserAction(_ flowController: any ObvFlowController, ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageId: ReceivedMessageIdentifier) async throws
    func updatedSetOfCurrentlyDisplayedMessagesWithLimitedVisibility(_ flowController: any ObvFlowController, discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentIDs: Set<ObvManagedObjectPermanentID<PersistedMessage>>) async throws
    func messagesAreNotNewAnymore(_ flowController: any ObvFlowController, ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageIds: [MessageIdentifier]) async throws
    func userWantsToUpdateReaction(_ flowController: any ObvFlowController, ownedCryptoId: ObvCryptoId, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, newEmoji: String?) async throws
    func userWantsToStopSharingLocationInDiscussion(_ flowController: any ObvFlowController, discussionIdentifier: ObvDiscussionIdentifier) async throws
    func userWantsToSetupNewBackups(_ flowController: any ObvFlowController)
    func userWantsToDisplayBackupKey(_ flowController: any ObvFlowController)
    func userWantsToReplaceTrustedDetailsByPublishedDetails(_ flowController: any ObvFlowController, groupIdentifier: ObvGroupV2Identifier) async throws
    func userWantsToLeaveGroup(_ flowController: any ObvFlowController, groupIdentifier: ObvGroupV2Identifier) async throws
    func userWantsToDisbandGroup(_ flowController: any ObvFlowController, groupIdentifier: ObvGroupV2Identifier) async throws
    func userWantsToSelectAndCallContacts(flowController: any ObvFlowController, ownedCryptoId: ObvCryptoId, contactCryptoIds: Set<ObvCryptoId>, groupId: GroupIdentifier?) async
    func userWantsObtainAvatar(_ flowController: any ObvFlowController, avatarSource: ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage?

    func userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice(_ flowController: any ObvFlowController) async throws
    func userWantsToShowMapToConsultLocationSharedContinously(_ flowController: any ObvFlowController, presentingViewController: UIViewController, ownedCryptoId: ObvTypes.ObvCryptoId) async throws
    func userWantsToShowMapToSendOrShareLocationContinuously(_ flowController: any ObvFlowController, presentingViewController: UIViewController, discussionIdentifier: ObvDiscussionIdentifier) async throws
    func userWantsToShowMapToConsultLocationSharedContinously(_ flowController: any ObvFlowController, presentingViewController: UIViewController, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>) async throws

    @available(iOS 18, *)
    @MainActor func floatingButtonTapped(flow: ObvFlowController)
    
}
