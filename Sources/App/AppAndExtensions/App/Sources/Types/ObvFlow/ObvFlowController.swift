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


protocol ObvFlowController: UINavigationController, SingleDiscussionViewControllerDelegate, SingleGroupViewControllerDelegate, SingleGroupV2ViewControllerDelegate, SingleContactIdentityViewHostingControllerDelegate, ObvErrorMaker, NewGroupEditionFlowViewControllerGroupCreationDelegate {

    var flowDelegate: ObvFlowControllerDelegate? { get }
    var log: OSLog { get }
    var obvEngine: ObvEngine { get }
    var observationTokens: [NSObjectProtocol] { get set }
    var floatingButton: UIButton? { get set } // Used on iOS 18+ only
    var delegatesStack: ObvFlowControllerDelegatesStack { get }

    func userWantsToDisplay(persistedDiscussion discussion: PersistedDiscussion)
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
            ObvMessengerCoreDataNotification.observePersistedGroupV2WasDeleted { [weak self] persistedGroupV2ObjectID in
                Task { [weak self] in await self?.removeGroupViewController(persistedGroupV2ObjectId: persistedGroupV2ObjectID) }
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
    private func removeGroupViewController(persistedGroupV2ObjectId: TypeSafeManagedObjectID<PersistedGroupV2>) async {
        var newViewController = [UIViewController]()
        for vc in viewControllers {
            guard let groupVC = vc as? SingleGroupV2ViewController, groupVC.persistedGroupV2ObjectID == persistedGroupV2ObjectId else {
                newViewController += [vc]
                continue
            }
            // Skip the view controller
        }
        setViewControllers(newViewController, animated: true)
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
    
    func userWantsToShowMapToSendOrShareLocationContinuously(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, discussionIdentifier: ObvDiscussionIdentifier) async throws {
        guard let flowDelegate else { assertionFailure(); throw Self.makeError(message: "Flow delegate is nil") }
        try await flowDelegate.userWantsToShowMapToSendOrShareLocationContinuously(self, presentingViewController: singleDiscussionViewController, discussionIdentifier: discussionIdentifier)
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
            
            guard let group = group else {
                os_log("Could find group V2 (this is ok if it was just deleted)", log: log, type: .error)
                return
            }
            
            guard let singleGroupV2VC = try? SingleGroupV2ViewController(group: group, obvEngine: obvEngine, delegate: self) else { return }
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
            userWantsToNavigateToSingleGroupView(persistedGroupV2: groupV2, within: appropriateNav)
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

    
    private func userWantsToNavigateToSingleGroupView(persistedGroupV2: PersistedGroupV2, within nav: UINavigationController) {
        
        for vc in nav.children {
            guard let singleGroupViewController = vc as? SingleGroupV2ViewController else { continue }
            guard singleGroupViewController.persistedGroupV2ObjectID == persistedGroupV2.typedObjectID else { continue }
            // If we reach this point, there exists an appropriate SingleGroupV2ViewController within the navigation stack, so we pop to this VC and return
            nav.popToViewController(singleGroupViewController, animated: true)
            return
        }
        // If we reach this point, we could not find an appropriate VC within the navigation stack, so we push a new one
        guard let singleGroupViewController = try? SingleGroupV2ViewController(group: persistedGroupV2, obvEngine: obvEngine, delegate: self) else { return }
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
        
        guard let singleGroupViewController = try? SingleGroupV2ViewController(group: persistedGroupV2, obvEngine: obvEngine, delegate: self) else { return }
        if let presentedViewController {
            presentedViewController.dismiss(animated: true) { [weak self] in
                self?.present(singleGroupViewController, animated: true)
            }
        } else {
            present(singleGroupViewController, animated: true)
        }
        
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
    
    
    /// Method part of the `SingleGroupV2ViewControllerDelegate`, called when the user wants to add all the group members as one2one contacts at once.
    func userWantsToInviteContactToOneToOne(ownedCryptoId: ObvCryptoId, contactCryptoIds: Set<ObvCryptoId>) async throws {
        assert(flowDelegate != nil)
        let users: [(cryptoId: ObvCryptoId, keycloakDetails: ObvKeycloakUserDetails?)] = contactCryptoIds.map { ($0, nil) }
        try await flowDelegate?.userWantsToInviteContactsToOneToOne(ownedCryptoId: ownedCryptoId, users: users)
    }

    
    func userWantsToCancelSentInviteContactToOneToOne(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId) {
        let log = self.log
        let obvEngine = self.obvEngine
        ObvStack.shared.performBackgroundTask { (context) in
            do {
                guard let oneToOneInvitationSent = try PersistedInvitationOneToOneInvitationSent.get(fromOwnedIdentity: ownedCryptoId,
                                                                                                     toContact: contactCryptoId,
                                                                                                     within: context) else {
                    assertionFailure(); return
                }
                guard var dialog = oneToOneInvitationSent.obvDialog else { assertionFailure(); return }
                try dialog.cancelOneToOneInvitationSent()
                let dialogForEngine = dialog
                Task {
                    try? await obvEngine.respondTo(dialogForEngine)
                }
            } catch {
                os_log("Could not invite contact to OneToOne: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
        }
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


// MARK: - SingleGroupViewControllerDelegate, SingleGroupV2ViewControllerDelegate

extension ObvFlowController {
    
    func userWantsToPublishGroupV2Modification(groupObjectID: TypeSafeManagedObjectID<PersistedGroupV2>, changeset: ObvGroupV2.Changeset) async {
        await flowDelegate?.userWantsToPublishGroupV2Modification(groupObjectID: groupObjectID, changeset: changeset)
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

    
    @MainActor
    func userWantsToCloneGroup(displayedContactGroupObjectID: TypeSafeManagedObjectID<DisplayedContactGroup>) {

        assert(Thread.isMainThread)

        guard let displayedContactGroup = try? DisplayedContactGroup.get(objectID: displayedContactGroupObjectID.objectID, within: ObvStack.shared.viewContext) else { return }
        
        let ownedCryptoId: ObvCryptoId
        let initialGroupMembers: Set<NewGroupEditionFlowViewController.EditionType.InitialGroupMember>
        let originalGroupName: String?
        let initialGroupDescription: String?
        let originalPhotoURL: URL?
        let initialGroupType: PersistedGroupV2.GroupType?
        
        switch displayedContactGroup.group {
        case .none:
            return
            
        case .groupV2(group: let group):
            
            guard let _ownedCryptoId = try? group.ownCryptoId else { assertionFailure(); return }
            ownedCryptoId = _ownedCryptoId
            initialGroupMembers = Set(group.contactsAmongOtherPendingAndNonPendingMembers.map { persistedContact in
                let cryptoId = persistedContact.cryptoId
                let isAdmin = group.otherMembers.first(where: { $0.cryptoId == cryptoId })?.isAnAdmin ?? false
                return NewGroupEditionFlowViewController.EditionType.InitialGroupMember(cryptoId: cryptoId, isAdmin: isAdmin)
            })
            originalGroupName = group.trustedName
            initialGroupDescription = group.trustedDescription?.mapToNilIfZeroLength()
            initialGroupType = group.getAdequateGroupType()
            if let url = group.trustedPhotoURL, FileManager.default.fileExists(atPath: url.path) {
                originalPhotoURL = url
            } else {
                originalPhotoURL = nil
            }
            
        case .groupV1(group: let group):
            
            guard let ownedIdentity = group.ownedIdentity else { assertionFailure(); return }
            ownedCryptoId = ownedIdentity.cryptoId
            // Get a list of contacts that need to be included in the cloned group
            let candidates: Set<PersistedObvContactIdentity>
            do {
                let contactsAmongPendingMembers = Set(group.pendingMembers
                    .map({ $0.cryptoId })
                    .compactMap({ try? PersistedObvContactIdentity.get(cryptoId: $0, ownedIdentity: ownedIdentity, whereOneToOneStatusIs: .any) }))
                candidates = group.contactIdentities.union(contactsAmongPendingMembers)
            }
            // Check that all the candidates have the appropriate capability
            let candidatesNotSupportingGroupV2 = candidates.filter({ !$0.supportsCapability(.groupsV2) })
            guard candidatesNotSupportingGroupV2.isEmpty else {
                displayAlertWhenTryingToCloneGroupV1WithMembersNotSupportingGroupsV2(contactsNotSupportingGroupV2: candidatesNotSupportingGroupV2)
                return
            }
            initialGroupMembers = Set(candidates.map({ NewGroupEditionFlowViewController.EditionType.InitialGroupMember(cryptoId: $0.cryptoId, isAdmin: false) }))
            originalGroupName = group.groupName.mapToNilIfZeroLength()
            initialGroupDescription = nil // The description of a group v1 is only available at the engine level, we don't fetch it here
            if let url = group.displayPhotoURL, FileManager.default.fileExists(atPath: url.path) {
                originalPhotoURL = url
            } else {
                originalPhotoURL = nil
            }
            
            initialGroupType = nil
        }

        let initialGroupName: String?
        if let originalGroupName = originalGroupName, !originalGroupName.isEmpty {
            initialGroupName = CommonString.clonedGroupNameFromOriginalName(originalGroupName)
        } else {
            initialGroupName = nil
        }
                
        let initialPhotoURL: URL?
        if let originalPhotoURL = originalPhotoURL {
            let randomFilename = UUID().uuidString
            let randomFileURL = ObvUICoreDataConstants.ContainerURL.forProfilePicturesCache.appendingPathComponent(randomFilename, isDirectory: false)
            do {
                try FileManager.default.copyItem(at: originalPhotoURL, to: randomFileURL)
                initialPhotoURL = randomFileURL
            } catch {
                assertionFailure()
                initialPhotoURL = nil
            }
        } else {
            initialPhotoURL = nil
        }
        
        let groupCreationFlowVC = NewGroupEditionFlowViewController(ownedCryptoId: ownedCryptoId,
                                                                    editionType: .cloneGroup(delegate: self,
                                                                                             initialGroupMembers: initialGroupMembers,
                                                                                             initialGroupName: initialGroupName,
                                                                                             initialGroupDescription: initialGroupDescription,
                                                                                             initialPhotoURL: initialPhotoURL,
                                                                                             initialGroupType: initialGroupType),
                                                                    logSubsystem: ObvAppCoreConstants.logSubsystem,
                                                                    directoryForTempFiles: ObvUICoreDataConstants.ContainerURL.forTempFiles.url)

        if let presentedViewController = presentedViewController {
            presentedViewController.dismiss(animated: true) { [weak self] in
                self?.present(groupCreationFlowVC, animated: true)
            }
        } else {
            present(groupCreationFlowVC, animated: true)
        }

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


// MARK: - NewGroupEditionFlowViewControllerGroupCreationDelegate

extension ObvFlowController {
    
    func userWantsToPublishGroupV2Creation(controller: NewGroupEditionFlowViewController, groupCoreDetails: GroupV2CoreDetails, ownPermissions: Set<ObvGroupV2.Permission>, otherGroupMembers: Set<ObvGroupV2.IdentityAndPermissions>, ownedCryptoId: ObvCryptoId, photoURL: URL?, groupType: PersistedGroupV2.GroupType) async {
        await flowDelegate?.userWantsToPublishGroupV2Creation(groupCoreDetails: groupCoreDetails,
                                                              ownPermissions: ownPermissions,
                                                              otherGroupMembers: otherGroupMembers,
                                                              ownedCryptoId: ownedCryptoId,
                                                              photoURL: photoURL,
                                                              groupType: groupType)
    }

}


// MARK: - Errors

enum ObvFlowControllerError: Error {
    case couldNotFindOwnedIdentity
}
    

// MARK: - ObvFlowControllerDelegate

protocol ObvFlowControllerDelegate: AnyObject, SingleOwnedIdentityFlowViewControllerDelegate {

    func getAndRemoveAirDroppedFileURLs() -> [URL]
    func performTrustEstablishmentProtocolOfRemoteIdentity(remoteCryptoId: ObvCryptoId, remoteFullDisplayName: String)
    func rePerformTrustEstablishmentProtocolOfContactIdentity(contactCryptoId: ObvCryptoId, contactFullDisplayName: String)
    func userWantsToUpdateTrustedIdentityDetailsOfContactIdentity(with: ObvCryptoId, using: ObvIdentityDetails)
    func userAskedToRefreshDiscussions() async throws
    func userWantsToInviteContactsToOneToOne(ownedCryptoId: ObvCryptoId, users: [(cryptoId: ObvCryptoId, keycloakDetails: ObvKeycloakUserDetails?)]) async throws
    func userWantsToPublishGroupV2Creation(groupCoreDetails: GroupV2CoreDetails, ownPermissions: Set<ObvGroupV2.Permission>, otherGroupMembers: Set<ObvGroupV2.IdentityAndPermissions>, ownedCryptoId: ObvCryptoId, photoURL: URL?, groupType: PersistedGroupV2.GroupType) async
    func userWantsToPublishGroupV2Modification(groupObjectID: TypeSafeManagedObjectID<PersistedGroupV2>, changeset: ObvGroupV2.Changeset) async
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
    func userWantsToStopSharingLocation() async throws
    func userWantsToShowMapToSendOrShareLocationContinuously(_ flowController: any ObvFlowController, presentingViewController: UIViewController, discussionIdentifier: ObvDiscussionIdentifier) async throws

    @available(iOS 18, *)
    @MainActor func floatingButtonTapped(flow: ObvFlowController)
    
}
