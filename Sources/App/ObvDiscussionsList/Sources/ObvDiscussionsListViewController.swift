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
import SwiftUI
import ObvDesignSystem
import ObvTypes
import ObvAppTypes
import ObvProfilePictureBarButtonItem


@MainActor
public protocol ObvDiscussionsListViewControllerActionsProtocol: AnyObject {
    func userWantsToNavigateToDiscussion(_ vc: ObvDiscussionsListViewController, discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) throws
    func userWantsToMarkAllMessagesAsReadInDiscussion(_ vc: ObvDiscussionsListViewController, discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) async throws
    func userWantsToReorderPinnedDiscussions(_ vc: ObvDiscussionsListViewController, identifiersOfPinnedDiscussions: [ObvDiscussionsListViewModel.DiscussionIdentifier]) async throws
    func userWantsToDeleteDiscussionButAsYetToConfirm(_ vc: ObvDiscussionsListViewController, discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) async throws
    func userWantsToArchiveDiscussions(_ vc: ObvDiscussionsListViewController, discussionIdentifiers: Set<ObvDiscussionsListViewModel.DiscussionIdentifier>) async throws
    func userWantsToUnarchiveDiscussions(_ vc: ObvDiscussionsListViewController, discussionIdentifiers: Set<ObvDiscussionsListViewModel.DiscussionIdentifier>) async throws
    func userWantsToDeleteDiscussionFromThisDeviceAndHasConfirmed(_ vc: ObvDiscussionsListViewController, discussionIdentifiers: Set<ObvDiscussionsListViewModel.DiscussionIdentifier>) async throws
    func userWantsToNavigateToListOfArchivedDiscussions(_ vc: ObvDiscussionsListViewController)
    func userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice(_ vc: ObvDiscussionsListViewController) async throws
    func userWantsToShowMapToConsultLocationSharedContinously(_ vc: ObvDiscussionsListViewController, ownedCryptoId: ObvTypes.ObvCryptoId) async throws
    func userWantsToSetupNewBackups(_ vc: ObvDiscussionsListViewController)
    func userWantsToDisplayBackupKey(_ vc: ObvDiscussionsListViewController)
    func userWantsToSetDoSendReadReceipt(_ vc: ObvDiscussionsListViewController, doSendReadReceipt: Bool)
    func userWantsToDismissTip(_ vc: ObvDiscussionsListViewController)
    func userWantsToNavigateToSettings(_ vc: ObvDiscussionsListViewController)
    func userWantsToNavigateToStorageManagement(_ vc: ObvDiscussionsListViewController)
    func userWantsToMuteDiscussions(_ vc: ObvDiscussionsListViewController, discussionIdentifiers: [ObvDiscussionsListViewModel.DiscussionIdentifier], duration: ObvMuteDurationOption) async throws
    func userWantsToUnmuteDiscussions(_ vc: ObvDiscussionsListViewController, discussionIdentifiers: [ObvDiscussionsListViewModel.DiscussionIdentifier]) async throws
    
    func userDidLongPressOnProfilePicture(_ vc: ObvDiscussionsListViewController)
    func userWantsToAddNewProfile(_ vc: ObvDiscussionsListViewController) async
    func userWantsToEditOwnedIdentity(_ vc: ObvDiscussionsListViewController, ownedCryptoId: ObvTypes.ObvCryptoId) async

    /// Allows the rest of the app to be notified when the user switches to another profile in this view or from one of its decendents.
    func userDidSwitchCurrentOwnedCryptoId(_ vc: ObvDiscussionsListViewController, to newOwnedCryptoId: ObvCryptoId) async
 
    func userWantsToGetNewMessages(_ vc: ObvDiscussionsListViewController) async throws
    
    func userWantsToNavigateToSettingsToChangeDiscussionsUnarchivingBehavior(_ vc: ObvDiscussionsListViewController) async

    func userTappedObvPlusButton(_ vc: ObvDiscussionsListViewController)
    
    func userWantsToDiscoverOlvidPlus(_ vc: ObvDiscussionsListViewController)
    func userWantsToDismissOlvidPlusSuccessfulSubscriptionView(_ vc: ObvDiscussionsListViewController)

}


public final class ObvDiscussionsListViewController: UIHostingController<ObvDiscussionsListView> {
    
    private let viewsActions = ViewsActions()
    private let titleLabel = UILabel()
    public private(set) var currentOwnedCryptoId: ObvCryptoId

    public weak var internalDelegate: ObvDiscussionsListViewControllerActionsProtocol?
    private let configuration: ObvDiscussionsListViewConfiguration

    public init(currentOwnedCryptoId: ObvCryptoId, discussionsListViewDataSource: ObvDiscussionsListViewDataSource, avatarViewDataSource: ObvAvatarViewDataSource, configuration: ObvDiscussionsListViewConfiguration) {
        self.currentOwnedCryptoId = currentOwnedCryptoId
        self.configuration = configuration
        let rootView = ObvDiscussionsListView(
            currentOwnedCryptoId: currentOwnedCryptoId,
            dataSource: discussionsListViewDataSource,
            avatarViewDataSource: avatarViewDataSource,
            actions: viewsActions,
            configuration: configuration)
        super.init(rootView: rootView)
        self.viewsActions.delegate = self
    }
        
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(ofSize: 20.0, weight: .heavy)
        titleLabel.text = self.navigationItem.title
        self.navigationItem.titleView = titleLabel

        if #available(iOS 26, *) {
            // We don't customise the appearance of the navigation bar
        } else {
            if let appearance = self.navigationController?.navigationBar.standardAppearance.copy() {
                appearance.configureWithTransparentBackground()
                appearance.shadowColor = .clear
                appearance.backgroundEffect = UIBlurEffect(style: .regular)
                navigationItem.standardAppearance = appearance
            }
        }
        
    }
    
    enum ObvError: Error {
        case dataSourceNotSet
        case internalDelegateNotSet
    }
    
}


// MARK: - Implementing ObvDiscussionsListViewActionsProtocol

extension ObvDiscussionsListViewController: ObvDiscussionsListViewActionsProtocol {
    
    func userDidSwitchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) async {
        guard let internalDelegate else { assertionFailure(); return }
        self.currentOwnedCryptoId = newOwnedCryptoId
        await internalDelegate.userDidSwitchCurrentOwnedCryptoId(self, to: newOwnedCryptoId)
    }
    
    public func userWantsToEditOwnedIdentity(_ view: ObvProfilePictureBarButtonItem.ObvProfilePictureBarButtonItemView, ownedCryptoId: ObvTypes.ObvCryptoId) async {
        guard let internalDelegate else { assertionFailure(); return }
        await internalDelegate.userWantsToEditOwnedIdentity(self, ownedCryptoId: ownedCryptoId)
    }
    
    func userWantsToNavigateToDiscussion(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) throws {
        guard let internalDelegate else { assertionFailure(); return }
        try internalDelegate.userWantsToNavigateToDiscussion(self, discussionIdentifier: discussionIdentifier)
    }
    
    func userWantsToMarkAllMessagesAsReadInDiscussion(withIdentifier discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.internalDelegateNotSet }
        try await internalDelegate.userWantsToMarkAllMessagesAsReadInDiscussion(self, discussionIdentifier: discussionIdentifier)
    }
    
    func userWantsToReorderPinnedDiscussions(identifiersOfPinnedDiscussions: [ObvDiscussionsListViewModel.DiscussionIdentifier]) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.internalDelegateNotSet }
        try await internalDelegate.userWantsToReorderPinnedDiscussions(self, identifiersOfPinnedDiscussions: identifiersOfPinnedDiscussions)
    }
    
    func userWantsToDeleteDiscussionButAsYetToConfirm(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.internalDelegateNotSet }
        try await internalDelegate.userWantsToDeleteDiscussionButAsYetToConfirm(self, discussionIdentifier: discussionIdentifier)
    }
    
    func userWantsToArchiveDiscussion(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.internalDelegateNotSet }
        try await internalDelegate.userWantsToArchiveDiscussions(self, discussionIdentifiers: [discussionIdentifier])
    }
    
    func userWantsToUnarchiveDiscussion(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.internalDelegateNotSet }
        try await internalDelegate.userWantsToUnarchiveDiscussions(self, discussionIdentifiers: [discussionIdentifier])
    }
    
    func userWantsToArchiveDiscussions(discussionIdentifiers: Set<ObvDiscussionsListViewModel.DiscussionIdentifier>) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.internalDelegateNotSet }
        try await internalDelegate.userWantsToArchiveDiscussions(self, discussionIdentifiers: discussionIdentifiers)
    }
    
    func userWantsToUnarchiveDiscussions(discussionIdentifiers: Set<ObvDiscussionsListViewModel.DiscussionIdentifier>) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.internalDelegateNotSet }
        try await internalDelegate.userWantsToUnarchiveDiscussions(self, discussionIdentifiers: discussionIdentifiers)
    }
    
    func userWantsToDeleteDiscussionFromThisDeviceAndHasConfirmed(discussionIdentifiers: Set<ObvDiscussionsListViewModel.DiscussionIdentifier>) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.internalDelegateNotSet }
        try await internalDelegate.userWantsToDeleteDiscussionFromThisDeviceAndHasConfirmed(self, discussionIdentifiers: discussionIdentifiers)
    }
    
    func userWantsToNavigateToListOfArchivedDiscussions() {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userWantsToNavigateToListOfArchivedDiscussions(self)
    }
    
    func userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice() async throws {
        guard let internalDelegate else { assertionFailure(); return }
        try await internalDelegate.userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice(self)
    }
    
    func userWantsToShowMapToConsultLocationSharedContinously(ownedCryptoId: ObvTypes.ObvCryptoId) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.internalDelegateNotSet }
        try await internalDelegate.userWantsToShowMapToConsultLocationSharedContinously(self, ownedCryptoId: ownedCryptoId)
    }
    
    func userWantsToSetupNewBackups() {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userWantsToSetupNewBackups(self)
    }
    
    func userWantsToDisplayBackupKey() {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userWantsToDisplayBackupKey(self)
    }

    func userWantsToSetDoSendReadReceipt(doSendReadReceipt: Bool) {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userWantsToSetDoSendReadReceipt(self, doSendReadReceipt: doSendReadReceipt)
    }
    
    func userWantsToDismissTip() {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userWantsToDismissTip(self)
    }

    func userWantsToNavigateToSettings() {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userWantsToNavigateToSettings(self)
    }
    
    func userWantsToNavigateToStorageManagement() {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userWantsToNavigateToStorageManagement(self)
    }
    
    func userWantsToMuteDiscussion(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier, duration: ObvMuteDurationOption) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.internalDelegateNotSet }
        try await internalDelegate.userWantsToMuteDiscussions(self, discussionIdentifiers: [discussionIdentifier], duration: duration)
    }
    
    func userWantsToUnmuteDiscussion(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.internalDelegateNotSet }
        try await internalDelegate.userWantsToUnmuteDiscussions(self, discussionIdentifiers: [discussionIdentifier])
    }
    
    public func userDidLongPressOnProfilePicture(_ view: ObvProfilePictureBarButtonItemView) {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userDidLongPressOnProfilePicture(self)
    }
    
    public func userWantsToAddNewProfile(_ view: ObvProfilePictureBarButtonItemView) async {
        guard let internalDelegate else { assertionFailure(); return }
        await internalDelegate.userWantsToAddNewProfile(self)
    }

    func userWantsToGetNewMessages() async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.internalDelegateNotSet }
        try await internalDelegate.userWantsToGetNewMessages(self)
    }

    func userWantsToNavigateToSettingsToChangeDiscussionsUnarchivingBehavior(_ view: ArchivedDiscussionsHelpMessageView) async {
        guard let internalDelegate else { assertionFailure(); return }
        await internalDelegate.userWantsToNavigateToSettingsToChangeDiscussionsUnarchivingBehavior(self)
    }
    
    public func userTappedObvPlusButton() {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userTappedObvPlusButton(self)
    }
    
    func userWantsToDiscoverOlvidPlus(_ view: OlvidPlusTipView) {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userWantsToDiscoverOlvidPlus(self)
    }
    
    func userWantsToDismissOlvidPlusSuccessfulSubscriptionView(_ view: OlvidPlusSuccessfulSubscriptionView) {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userWantsToDismissOlvidPlusSuccessfulSubscriptionView(self)
    }
    
}


// MARK: - View's actions

private final class ViewsActions: ObvDiscussionsListViewActionsProtocol {
                        
    weak var delegate: ObvDiscussionsListViewActionsProtocol?
    
    func userDidSwitchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) async {
        guard let delegate else { assertionFailure(); return }
        await delegate.userDidSwitchCurrentOwnedCryptoId(to: newOwnedCryptoId)
    }
    
    func userWantsToEditOwnedIdentity(_ view: ObvProfilePictureBarButtonItem.ObvProfilePictureBarButtonItemView, ownedCryptoId: ObvTypes.ObvCryptoId) async {
        guard let delegate else { assertionFailure(); return }
        await delegate.userWantsToEditOwnedIdentity(view, ownedCryptoId: ownedCryptoId)
    }

    func userWantsToNavigateToDiscussion(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) throws {
        guard let delegate else { assertionFailure(); return }
        try delegate.userWantsToNavigateToDiscussion(discussionIdentifier: discussionIdentifier)
    }
    
    func userWantsToMarkAllMessagesAsReadInDiscussion(withIdentifier discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateNotSet }
        try await delegate.userWantsToMarkAllMessagesAsReadInDiscussion(withIdentifier: discussionIdentifier)
    }
    
    func userWantsToReorderPinnedDiscussions(identifiersOfPinnedDiscussions: [ObvDiscussionsListViewModel.DiscussionIdentifier]) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateNotSet }
        try await delegate.userWantsToReorderPinnedDiscussions(identifiersOfPinnedDiscussions: identifiersOfPinnedDiscussions)
    }
    
    func userWantsToDeleteDiscussionButAsYetToConfirm(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateNotSet }
        try await delegate.userWantsToDeleteDiscussionButAsYetToConfirm(discussionIdentifier: discussionIdentifier)
    }
    
    func userWantsToArchiveDiscussion(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateNotSet }
        try await delegate.userWantsToArchiveDiscussion(discussionIdentifier: discussionIdentifier)
    }
    
    func userWantsToUnarchiveDiscussion(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateNotSet }
        try await delegate.userWantsToUnarchiveDiscussion(discussionIdentifier: discussionIdentifier)
    }
    
    func userWantsToArchiveDiscussions(discussionIdentifiers: Set<ObvDiscussionsListViewModel.DiscussionIdentifier>) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateNotSet }
        try await delegate.userWantsToArchiveDiscussions(discussionIdentifiers: discussionIdentifiers)
    }

    func userWantsToUnarchiveDiscussions(discussionIdentifiers: Set<ObvDiscussionsListViewModel.DiscussionIdentifier>) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateNotSet }
        try await delegate.userWantsToUnarchiveDiscussions(discussionIdentifiers: discussionIdentifiers)
    }
    
    func userWantsToDeleteDiscussionFromThisDeviceAndHasConfirmed(discussionIdentifiers: Set<ObvDiscussionsListViewModel.DiscussionIdentifier>) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateNotSet }
        try await delegate.userWantsToDeleteDiscussionFromThisDeviceAndHasConfirmed(discussionIdentifiers: discussionIdentifiers)
    }
    
    func userWantsToNavigateToListOfArchivedDiscussions() {
        guard let delegate else { assertionFailure(); return }
        delegate.userWantsToNavigateToListOfArchivedDiscussions()
    }
    
    func userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice() async throws {
        guard let delegate else { assertionFailure(); return }
        try await delegate.userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice()
    }
    
    func userWantsToShowMapToConsultLocationSharedContinously(ownedCryptoId: ObvTypes.ObvCryptoId) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateNotSet }
        try await delegate.userWantsToShowMapToConsultLocationSharedContinously(ownedCryptoId: ownedCryptoId)
    }

    func userWantsToSetupNewBackups() {
        guard let delegate else { assertionFailure(); return }
        delegate.userWantsToSetupNewBackups()
    }
    
    func userWantsToDisplayBackupKey() {
        guard let delegate else { assertionFailure(); return }
        delegate.userWantsToDisplayBackupKey()
    }

    func userWantsToSetDoSendReadReceipt(doSendReadReceipt: Bool) {
        guard let delegate else { assertionFailure(); return }
        delegate.userWantsToSetDoSendReadReceipt(doSendReadReceipt: doSendReadReceipt)
    }
    
    func userWantsToDismissTip() {
        guard let delegate else { assertionFailure(); return }
        delegate.userWantsToDismissTip()
    }
    
    func userWantsToNavigateToSettings() {
        guard let delegate else { assertionFailure(); return }
        delegate.userWantsToNavigateToSettings()
    }
    
    func userWantsToNavigateToStorageManagement() {
        guard let delegate else { assertionFailure(); return }
        delegate.userWantsToNavigateToStorageManagement()
    }
    
    func userWantsToMuteDiscussion(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier, duration: ObvMuteDurationOption) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateNotSet }
        try await delegate.userWantsToMuteDiscussion(discussionIdentifier: discussionIdentifier, duration: duration)
    }
    
    func userWantsToUnmuteDiscussion(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateNotSet }
        try await delegate.userWantsToUnmuteDiscussion(discussionIdentifier: discussionIdentifier)
    }
    
    func userDidLongPressOnProfilePicture(_ view: ObvProfilePictureBarButtonItemView) {
        guard let delegate else { assertionFailure(); return }
        delegate.userDidLongPressOnProfilePicture(view)
    }
    
    func userWantsToAddNewProfile(_ view: ObvProfilePictureBarButtonItemView) async {
        guard let delegate else { assertionFailure(); return }
        await delegate.userWantsToAddNewProfile(view)
    }

    func userWantsToGetNewMessages() async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateNotSet }
        try await delegate.userWantsToGetNewMessages()
    }
    
    func userWantsToNavigateToSettingsToChangeDiscussionsUnarchivingBehavior(_ view: ArchivedDiscussionsHelpMessageView) async {
        guard let delegate else { assertionFailure(); return }
        await delegate.userWantsToNavigateToSettingsToChangeDiscussionsUnarchivingBehavior(view)
    }

    func userTappedObvPlusButton() {
        guard let delegate else { assertionFailure(); return }
        delegate.userTappedObvPlusButton()
    }
    
    func userWantsToDiscoverOlvidPlus(_ view: OlvidPlusTipView) {
        guard let delegate else { assertionFailure(); return }
        delegate.userWantsToDiscoverOlvidPlus(view)
    }
    
    func userWantsToDismissOlvidPlusSuccessfulSubscriptionView(_ view: OlvidPlusSuccessfulSubscriptionView) {
        guard let delegate else { assertionFailure(); return }
        delegate.userWantsToDismissOlvidPlusSuccessfulSubscriptionView(view)
    }
    
    enum ObvError: Error {
        case delegateNotSet
    }
    
}
