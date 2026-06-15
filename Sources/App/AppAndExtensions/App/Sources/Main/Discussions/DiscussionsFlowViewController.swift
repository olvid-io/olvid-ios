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

import UIKit
import OSLog
import ObvTypes
import ObvEngine
import ObvUICoreData
import ObvAppCoreConstants
import OlvidUtils
import ObvUIGroupV1
import ObvUIGroupV2
import ObvDiscussionsList
import ObvDesignSystem
import ObvSettings
import ObvAppTypes
import ObvOwnedIdentityChooser
import ObvSharedDataSources
import ObvProfilePictureBarButtonItem
import ObvAppNavigation
import ObvSubscription


final class DiscussionsFlowViewController: ObvFlowController {

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "DiscussionsFlowViewController")
    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: DiscussionsFlowViewController.self))

    private var observationTokens = [NSObjectProtocol]()
    
    init(ownedCryptoId: ObvCryptoId, obvEngine: ObvEngine, dataSources: ObvDataSources) {

        super.init(ownedCryptoId: ownedCryptoId, obvEngine: obvEngine, dataSources: dataSources, doAddFloatingButton: false)

        let vc = Self.createObvDiscussionsListViewController(ownedCryptoId: ownedCryptoId, dataSources: dataSources)
        vc.internalDelegate = self

        self.setViewControllers([vc], animated: false)

    }
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    required init?(coder aDecoder: NSCoder) { fatalError("die") }

    private static func createObvDiscussionsListViewController(ownedCryptoId: ObvCryptoId, dataSources: ObvDataSources) -> ObvDiscussionsListViewController {
        let progressCellViewAppDataSource = ProgressCellViewAppDataSource()
        let configuration = ObvDiscussionsListViewConfiguration(
            showArchivedDiscussionsCell: .yes(dataSource: dataSources.archivedDiscussionsCellAppDataSource),
            showLocationsCell: .yes(dataSource: dataSources.locationsCellViewDataSource),
            showProgressCell: .yes(dataSource: progressCellViewAppDataSource),
            showTipCell: .yes(dataSource: dataSources.tipCellViewAppDataSource),
            showProfilePictureBarButtonItem: .yes(profilePictureBarButtonItemViewDataSource: dataSources.profilePictureBarButtonItemViewDataSource,
                                                  ownedIdentityChooserViewDataSource: dataSources.ownedIdentityChooserViewDataSource),
            showArchiveActionButtonInMenu: true,
            showUnarchiveActionButtonInMenu: false,
            showPlusButton: true)
        let vc = ObvDiscussionsListViewController(
            currentOwnedCryptoId: ownedCryptoId,
            discussionsListViewDataSource: dataSources.discussionsListViewDataSource,
            avatarViewDataSource: dataSources.avatarViewDataSource,
            configuration: configuration)
        vc.title = CommonString.Word.Discussions
        return vc
    }

    
    // MARK: - Switching current owned identity

    override func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) {
        
        super.switchCurrentOwnedCryptoId(to: newOwnedCryptoId)
        
        // We cannot simply switch the currentOwnedCryptoId on an ObvDiscussionsListViewController. For some reason, the currentOwnedCryptoId
        // state variable of the SwiftUI hosted by an ObvDiscussionsListViewController cannot be refreshed off-screen. Instead, we
        // replace ObvDiscussionsListViewController by new ones
        // Since we did pop to the root view controller, we can limit ourselves to the first view controller.
        // Note that when the owned identity is switched from the `ObvDiscussionsListViewController` itself, its currentOwnedCryptoId will
        // be correct, so we won't replace it by a new one. Replacing the ObvDiscussionsListViewController only occurs if the user
        // switches the current profile from another tab.
        if (viewControllers.first as? ObvDiscussionsListViewController)?.currentOwnedCryptoId != newOwnedCryptoId {
            let vc = Self.createObvDiscussionsListViewController(ownedCryptoId: newOwnedCryptoId, dataSources: dataSources)
            vc.internalDelegate = self
            self.setViewControllers([vc], animated: false)
        }
        
    }
        
}


// MARK: - Lifecycle

extension DiscussionsFlowViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = CommonString.Word.Discussions

        if #available(iOS 18, *) {
            // The tabbar is configured with iOS 18 APIs, we don't need to specify a tabBarItem
        } else {
            let image = UIImage(systemIcon: .bubbleLeftAndBubbleRight)
            tabBarItem = UITabBarItem(title: String(localized: "Discussions"), image: image, tag: 0)
        }

        if #available(iOS 26, *) {
            // We don't change the appearance under iOS 26
        } else {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            navigationBar.standardAppearance = appearance
        }
     
        //observeNotificationsImpactingTheNavigationStack()
        
        // This is required to activate the interactive pop gesture recognizer. Activating this interactive gesture also requires
        // to override gestureRecognizerShouldBegin(_:).
        // See ``https://stackoverflow.com/questions/18946302/uinavigationcontroller-interactive-pop-gesture-not-working``.
        if #available(iOS 18, *) {
            interactivePopGestureRecognizer?.delegate = self
        }
        
    }
        
}


// MARK: - UIGestureRecognizerDelegate

extension DiscussionsFlowViewController: UIGestureRecognizerDelegate {
    
    /// This is only used under iOS18+, in order to be the delegate of the `interactivePopGestureRecognizer`, allowing to activate the interactive pop gesture recognizer.
    /// See ``https://stackoverflow.com/questions/18946302/uinavigationcontroller-interactive-pop-gesture-not-working``.
    @objc func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return viewControllers.count > 1
    }
    
}


// MARK: - Helper methods

extension DiscussionsFlowViewController {
    
    func userWantsToDeleteDiscussion(_ persistedDiscussion: PersistedDiscussion, completionHandler: @escaping (Bool) -> Void) {
        
        assert(Thread.isMainThread)
        
        let ownedIdentityHasHasAnotherReachableDevice = persistedDiscussion.ownedIdentity?.hasAnotherDeviceWhichIsReachable ?? false
        let multipleContacts: Bool
        do {
            switch try persistedDiscussion.kind {
            case .oneToOne:
                multipleContacts = false
            case .groupV1:
                multipleContacts = true
            case .groupV2:
                multipleContacts = true
            }
        } catch {
            assertionFailure()
            multipleContacts = false
        }
        
        let alert = UIAlertController(title: Strings.Alert.ConfirmAllDeletionOfAllMessages.title,
                                      message: Strings.Alert.ConfirmAllDeletionOfAllMessages.message,
                                      preferredStyleForTraitCollection: self.traitCollection)
        
        for deletionType in persistedDiscussion.deletionTypesThatCanBeMadeAvailableForThisDiscussion.sorted() {
            let title = Strings.Alert.ConfirmAllDeletionOfAllMessages.actionTitle(for: deletionType, ownedIdentityHasHasAnotherReachableDevice: ownedIdentityHasHasAnotherReachableDevice, multipleContacts: multipleContacts)
            alert.addAction(UIAlertAction(title: title, style: .destructive, handler: { [weak self] (action) in
                guard let ownedCryptoId = persistedDiscussion.ownedIdentity?.cryptoId else { return }
                switch deletionType {
                case .fromThisDeviceOnly, .fromAllOwnedDevices:
                    ObvMessengerInternalNotification.userRequestedDeletionOfPersistedDiscussion(
                        ownedCryptoId: ownedCryptoId,
                        discussionObjectID: persistedDiscussion.typedObjectID,
                        deletionType: deletionType,
                        completionHandler: completionHandler)
                        .postOnDispatchQueue()
                case .fromAllOwnedDevicesAndAllContactDevices:
                    // Request a second confirmation in that case, as the discussion will also be delete from contact devices
                    self?.ensureUserWantsToGloballyDeleteDiscussion(persistedDiscussion,
                                                                    ownedIdentityHasHasAnotherReachableDevice: ownedIdentityHasHasAnotherReachableDevice,
                                                                    multipleContacts: multipleContacts,
                                                                    completionHandler: completionHandler)
                }
            }))
        }
        
        // Cancel action
        
        alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel) { (action) in
            completionHandler(false)
        })
        
        present(alert, animated: true)
        
    }
    
    
    private func ensureUserWantsToGloballyDeleteDiscussion(_ discussion: PersistedDiscussion, ownedIdentityHasHasAnotherReachableDevice: Bool, multipleContacts: Bool, completionHandler: @escaping (Bool) -> Void) {
        assert(Thread.current.isMainThread)
        let alert = UIAlertController(title: Strings.AlertConfirmAllDiscussionMessagesDeletionGlobally.title,
                                      message: Strings.AlertConfirmAllDiscussionMessagesDeletionGlobally.message,
                                      preferredStyleForTraitCollection: self.traitCollection)
        let actionTitle = Strings.Alert.ConfirmAllDeletionOfAllMessages.actionTitle(for: .fromAllOwnedDevicesAndAllContactDevices, ownedIdentityHasHasAnotherReachableDevice: ownedIdentityHasHasAnotherReachableDevice, multipleContacts: multipleContacts)
        alert.addAction(UIAlertAction(title: actionTitle, style: .destructive, handler: { (action) in
            guard let ownedCryptoId = discussion.ownedIdentity?.cryptoId else { return }
            ObvMessengerInternalNotification.userRequestedDeletionOfPersistedDiscussion(
                ownedCryptoId: ownedCryptoId,
                discussionObjectID: discussion.typedObjectID,
                deletionType: .fromAllOwnedDevicesAndAllContactDevices,
                completionHandler: completionHandler)
                .postOnDispatchQueue()
        }))
        alert.addAction(UIAlertAction.init(title: CommonString.Word.Cancel, style: .cancel) { (action) in
            completionHandler(false)
        })
        present(alert, animated: true)
    }

}



// MARK: - Implementing ObvDiscussionsListViewControllerActionsProtocol

extension DiscussionsFlowViewController: ObvDiscussionsListViewControllerActionsProtocol {
    
    func userWantsToDismissOlvidPlusSuccessfulSubscriptionView(_ vc: ObvDiscussionsListViewController) {
        guard let flowDelegate else { assertionFailure(); return }
        flowDelegate.userWantsToDismissOlvidPlusSuccessfulSubscriptionView(self)
    }
    
    /// Method called when the user taps on the "Discover Olvid+" button on one of the Olvid+ tips.
    func userWantsToDiscoverOlvidPlus(_ vc: ObvDiscussionsListViewController) {
        guard let flowDelegate else { assertionFailure(); return }
        flowDelegate.userWantsToDiscoverOlvidPlus(self)
    }
    
    func userTappedObvPlusButton(_ vc: ObvDiscussionsListViewController) {
        guard let flowDelegate else { assertionFailure(); return }
        flowDelegate.userTappedObvPlusButton(self)
    }
    
    func userWantsToNavigateToSettingsToChangeDiscussionsUnarchivingBehavior(_ vc: ObvDiscussionsList.ObvDiscussionsListViewController) async {
        let deepLink = ObvDeepLink.discussionsSettings
        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
            .postOnDispatchQueue()
    }
    
    
    func userWantsToGetNewMessages(_ vc: ObvDiscussionsListViewController) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userAskedToRefreshDiscussions()
    }

    
    func userDidLongPressOnProfilePicture(_ vc: ObvDiscussionsList.ObvDiscussionsListViewController) {
        guard let flowDelegate else { assertionFailure(); return }
        flowDelegate.showAlertForUnlockingHiddenOwnedIdentity(self)
    }

    
    func userWantsToAddNewProfile(_ vc: ObvDiscussionsList.ObvDiscussionsListViewController) async {
        ObvMessengerInternalNotification.userWantsToAddOwnedProfile
            .postOnDispatchQueue()
    }
    
    
    func userWantsToEditOwnedIdentity(_ vc: ObvDiscussionsList.ObvDiscussionsListViewController, ownedCryptoId: ObvTypes.ObvCryptoId) async {
        guard currentOwnedCryptoId == ownedCryptoId else { assertionFailure(); return }
        let deepLink = ObvDeepLink.myId(ownedCryptoId: ownedCryptoId)
        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
            .postOnDispatchQueue()
    }
    
    
    /// This method is called when the user changes the current profile from the `ObvDiscussionsListViewController` or one of its descendents. We need to propagate this in the rest of the app.
    func userDidSwitchCurrentOwnedCryptoId(_ vc: ObvDiscussionsList.ObvDiscussionsListViewController, to newOwnedCryptoId: ObvTypes.ObvCryptoId) async {
        ObvMessengerInternalNotification.userWantsToSwitchToOtherOwnedIdentity(ownedCryptoId: newOwnedCryptoId)
            .postOnDispatchQueue()
    }
    
    
    func userWantsToMuteDiscussions(_ vc: ObvDiscussionsListViewController, discussionIdentifiers: [ObvDiscussionsListViewModel.DiscussionIdentifier], duration: ObvMuteDurationOption) async throws {
        for discussionIdentifier in discussionIdentifiers {
            do {
                let discussion = try getPersistedDiscussion(discussionIdentifier: discussionIdentifier)
                ObvMessengerInternalNotification.userWantsToUpdateDiscussionLocalConfiguration(value: .muteNotificationsEndDate(duration.endDateFromNow), localConfigurationObjectID: discussion.localConfiguration.typedObjectID).postOnDispatchQueue()
            } catch {
                assertionFailure() // In production, continue with the next discussion
            }
        }
    }
    
    func userWantsToUnmuteDiscussions(_ vc: ObvDiscussionsListViewController, discussionIdentifiers: [ObvDiscussionsListViewModel.DiscussionIdentifier]) async throws {
        for discussionIdentifier in discussionIdentifiers {
            do {
                let discussion = try getPersistedDiscussion(discussionIdentifier: discussionIdentifier)
                ObvMessengerInternalNotification.userWantsToUpdateDiscussionLocalConfiguration(value: .muteNotificationsEndDate(nil), localConfigurationObjectID: discussion.localConfiguration.typedObjectID).postOnDispatchQueue()
            } catch {
                assertionFailure() // In production, continue with the next discussion
            }
        }
    }
    
    func userWantsToNavigateToSettings(_ vc: ObvDiscussionsListViewController) {
        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: .settings)
            .postOnDispatchQueue()
    }
    
    func userWantsToNavigateToStorageManagement(_ vc: ObvDiscussionsListViewController) {
        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: .storageManagementSettings)
            .postOnDispatchQueue()
    }
    
    func userWantsToDismissTip(_ vc: ObvDiscussionsList.ObvDiscussionsListViewController) {
        ObvMessengerSettings.ObvTips.setDateWhenUserDimissedTip(to: .now)
    }
    
    func userWantsToSetDoSendReadReceipt(_ vc: ObvDiscussionsList.ObvDiscussionsListViewController, doSendReadReceipt: Bool) {
        // Once doSendReadReceipt is persisted, `doSendReadReceiptIsSet` becomes true and the tip won't appear
        // again. Recording the dismissal date here additionally prevents any other tip from sliding in
        // immediately after the user makes their choice.
        ObvMessengerSettings.ObvTips.setDateWhenUserDimissedTip(to: .now)
        ObvMessengerSettings.Discussions.setDoSendReadReceipt(to: doSendReadReceipt, changeMadeFromAnotherOwnedDevice: false)
    }
    
    func userWantsToSetupNewBackups(_ vc: ObvDiscussionsList.ObvDiscussionsListViewController) {
        flowDelegate?.userWantsToSetupNewBackups(self)
    }
    
    
    func userWantsToDisplayBackupKey(_ vc: ObvDiscussionsList.ObvDiscussionsListViewController) {
        flowDelegate?.userWantsToDisplayBackupKey(self)
    }

    
    func userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice(_ vc: ObvDiscussionsList.ObvDiscussionsListViewController) async throws {
        try await flowDelegate?.userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice(self)
    }
    
    
    func userWantsToShowMapToConsultLocationSharedContinously(_ vc: ObvDiscussionsList.ObvDiscussionsListViewController, ownedCryptoId: ObvTypes.ObvCryptoId) async throws {
        try await flowDelegate?.userWantsToShowMapToConsultLocationSharedContinously(self, presentingViewController: vc, ownedCryptoId: ownedCryptoId)
    }
    
    
    func userWantsToNavigateToListOfArchivedDiscussions(_ vc: ObvDiscussionsList.ObvDiscussionsListViewController) {
        
        // This datasource restricts to archived discussions
        let discussionsListViewControllerAppDataSource = self.dataSources.discussionsArchivedListViewAppDataSource
        let tipCellViewDataSource = TipCellViewAppDataSourceForListOfArchivedDiscussions()
        
        let configuration = ObvDiscussionsListViewConfiguration(
            showArchivedDiscussionsCell: .no,
            showLocationsCell: .no,
            showProgressCell: .no,
            showTipCell: .yes(dataSource: tipCellViewDataSource),
            showProfilePictureBarButtonItem: .no,
            showArchiveActionButtonInMenu: false,
            showUnarchiveActionButtonInMenu: true,
            showPlusButton: false)
        
        let vc = ObvDiscussionsListViewController(
            currentOwnedCryptoId: currentOwnedCryptoId,
            discussionsListViewDataSource: discussionsListViewControllerAppDataSource,
            avatarViewDataSource: self.dataSources.avatarViewDataSource,
            configuration: configuration)
        
        vc.title = String(localized: "ARCHIVED_DISCUSSIONS")
        vc.internalDelegate = self

        self.pushViewController(vc, animated: true)
        
    }
    
    
    func userWantsToArchiveDiscussions(_ vc: ObvDiscussionsListViewController, discussionIdentifiers: Set<ObvDiscussionsListViewModel.DiscussionIdentifier>) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        let discussionObjectIDs: [TypeSafeManagedObjectID<PersistedDiscussion>] = try discussionIdentifiers.map { try self.getPersistedDiscussionObjectID(discussionIdentifier: $0) }
        try await flowDelegate.userWantsToArchiveDiscussions(self, discussionObjectIDs: discussionObjectIDs)
    }
    
    
    func userWantsToUnarchiveDiscussions(_ vc: ObvDiscussionsListViewController, discussionIdentifiers: Set<ObvDiscussionsListViewModel.DiscussionIdentifier>) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        let discussionObjectIDs: [TypeSafeManagedObjectID<PersistedDiscussion>] = try discussionIdentifiers.map { try self.getPersistedDiscussionObjectID(discussionIdentifier: $0) }
        try await flowDelegate.userWantsToUnarchiveDiscussions(self, discussionObjectIDs: discussionObjectIDs)
    }
    
    
    func userWantsToDeleteDiscussionButAsYetToConfirm(_ vc: ObvDiscussionsListViewController, discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) async throws {
        let persistedDiscussion: PersistedDiscussion = try getPersistedDiscussion(discussionIdentifier: discussionIdentifier)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            self.userWantsToDeleteDiscussion(persistedDiscussion) { success in
                if success {
                    return continuation.resume()
                } else {
                    return continuation.resume(throwing: ObvFlowControllerError.failedToDeleteDiscussion)
                }
            }
        }
    }
    
    
    func userWantsToDeleteDiscussionFromThisDeviceAndHasConfirmed(_ vc: ObvDiscussionsListViewController, discussionIdentifiers: Set<ObvDiscussionsListViewModel.DiscussionIdentifier>) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        let discussionObjectIDs: [TypeSafeManagedObjectID<PersistedDiscussion>] = try discussionIdentifiers.map { try self.getPersistedDiscussionObjectID(discussionIdentifier: $0) }
        try await flowDelegate.userWantsToDeleteDiscussionsAndHasConfirmed(self, discussionObjectIDs: discussionObjectIDs, deletionType: .fromThisDeviceOnly)
    }

    
    func userWantsToReorderPinnedDiscussions(_ vc: ObvDiscussionsListViewController, identifiersOfPinnedDiscussions: [ObvDiscussionsListViewModel.DiscussionIdentifier]) async throws {
        
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }

        var discussionObjectIds = [TypeSafeManagedObjectID<PersistedDiscussion>]()
        for identifier in identifiersOfPinnedDiscussions {
            switch identifier {
            case .obvDiscussionIdentifier(let obvDiscussionIdentifier):
                guard let discussion = try PersistedDiscussion.getPersistedDiscussion(discussionIdentifier: obvDiscussionIdentifier, within: ObvStack.shared.viewContext) else {
                    assertionFailure()
                    throw ObvFlowControllerError.couldNotFindDiscussion
                }
                discussionObjectIds += [discussion.typedObjectID]
            case .persistedDiscussionObjectID(let objectID):
                discussionObjectIds += [.init(objectID: objectID)]
            }
        }
        
        // Make sure the currentOwnedCryptoId is coherent with the selected discussions
        for discussionObjectId in discussionObjectIds {
            guard let discussion = try PersistedDiscussion.get(objectID: discussionObjectId.objectID, within: ObvStack.shared.viewContext) else {
                assertionFailure()
                throw ObvFlowControllerError.couldNotFindDiscussion
            }
            guard discussion.ownedIdentity?.cryptoId == self.currentOwnedCryptoId else {
                assertionFailure()
                throw ObvFlowControllerError.unexpectedOwnedCryptoId
            }
        }
        
        try await flowDelegate.userWantsToReorderPinnedDiscussions(self, ownedCryptoId: self.currentOwnedCryptoId, objectIDOfPinnedDiscussions: discussionObjectIds)
        
    }
    
    
    private func getPersistedDiscussion(discussionIdentifier: ObvDiscussionsList.ObvDiscussionsListViewModel.DiscussionIdentifier) throws -> PersistedDiscussion {
        switch discussionIdentifier {
        case .obvDiscussionIdentifier(let discussionIdentifier):
            guard let discussion = try PersistedDiscussion.getPersistedDiscussion(discussionIdentifier: discussionIdentifier, within: ObvStack.shared.viewContext) else {
                assertionFailure()
                throw ObvFlowControllerError.couldNotFindDiscussion
            }
            return discussion
        case .persistedDiscussionObjectID(let objectID):
            guard let discussion = try PersistedDiscussion.get(objectID: objectID, within: ObvStack.shared.viewContext) else {
                assertionFailure()
                throw ObvFlowControllerError.couldNotFindDiscussion
            }
            return discussion
        }
    }
    
    
    private func getPersistedDiscussionObjectID(discussionIdentifier: ObvDiscussionsList.ObvDiscussionsListViewModel.DiscussionIdentifier) throws -> TypeSafeManagedObjectID<PersistedDiscussion> {
        let discussion = try getPersistedDiscussion(discussionIdentifier: discussionIdentifier)
        return discussion.typedObjectID
    }

    
    func userWantsToNavigateToDiscussion(_ vc: ObvDiscussionsList.ObvDiscussionsListViewController, discussionIdentifier: ObvDiscussionsList.ObvDiscussionsListViewModel.DiscussionIdentifier) throws {
        let persistedDiscussion: PersistedDiscussion = try getPersistedDiscussion(discussionIdentifier: discussionIdentifier)
        userWantsToDisplay(persistedDiscussion: persistedDiscussion)
    }
    
    
    func userWantsToMarkAllMessagesAsReadInDiscussion(_ vc: ObvDiscussionsListViewController, discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        let discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>
        switch discussionIdentifier {
        case .obvDiscussionIdentifier(let obvDiscussionIdentifier):
            guard let discussion = try PersistedDiscussion.getPersistedDiscussion(discussionIdentifier: obvDiscussionIdentifier, within: ObvStack.shared.viewContext) else {
                assertionFailure()
                throw ObvFlowControllerError.couldNotFindDiscussion
            }
            discussionObjectID = discussion.typedObjectID
        case .persistedDiscussionObjectID(let objectID):
            discussionObjectID = .init(objectID: objectID)
        }
        try await flowDelegate.userWantsToMarkAllMessagesAsReadInDiscussion(self, discussionObjectID: discussionObjectID)
    }
    
    
    func userWantsToManageTheirDevices(_ vc: ObvDiscussionsListViewController, ownedCryptoId: ObvCryptoId) {
        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: .myId(ownedCryptoId: ownedCryptoId))
            .postOnDispatchQueue()
    }
    
    
    func userWantsToShowThisDeviceReactivationOptions(_ vc: ObvDiscussionsListViewController, ownedCryptoId: ObvCryptoId) {
        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: .myId(ownedCryptoId: ownedCryptoId))
            .postOnDispatchQueue()
    }
    
    
    func userWantsToRequestNotificationsAuthorization(_ vc: ObvDiscussionsList.ObvDiscussionsListViewController) {
        guard let flowDelegate else { assertionFailure(); return }
        flowDelegate.userWantsToRequestNotificationsAuthorization(self)
    }

}
