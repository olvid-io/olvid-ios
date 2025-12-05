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

import SwiftUI
import CoreData
import ObvTypes
import ObvAppTypes
import ObvDesignSystem
import ObvCells


@MainActor
final class MinimalDataSourceAndActionsForPreviews {
    
    fileprivate var continuationInvitationContactsListViewModelForLocalContacts: AsyncStream<InvitationContactsListViewModel>.Continuation?
    fileprivate var continuationInvitationContactsListViewModelForKeycloakUsers: AsyncStream<InvitationKeycloakContactsListViewModel>.Continuation?
    fileprivate var continuationInvitationFlowGroupListViewModel: AsyncStream<InvitationFlowGroupListViewModel>.Continuation?
    
}

// MARK: - Minimal implementation of InvitationContactsListCellViewDataSource

extension MinimalDataSourceAndActionsForPreviews: InvitationContactsListCellViewDataSource {
    
    func getInitialObvContactCellViewModel(contactIdentifier: InvitationContactsListViewModel.ContactIdentifier) -> InvitationContactsListCellView.Model? {
        return nil
    }
    
    func getAsyncStreamOfObvContactCellViewModel(_ view: InvitationContactsListCellView, contactIdentifier: InvitationContactsListViewModel.ContactIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<InvitationContactsListCellView.Model>) {
        let stream = AsyncStream(InvitationContactsListCellView.Model.self) { (continuation: AsyncStream<InvitationContactsListCellView.Model>.Continuation) in
            let model = InvitationContactsListCellView.Model.sampleData(contactIdentifier)
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfObvContactCellViewModel(_ view: InvitationContactsListCellView, streamUUID: UUID) {
        // Nothing to finish in previews
    }
    
    func getInvitationContactsListCellViewModelForKeycloakUser(_ view: InvitationContactsListCellView, ownedCryptoId: ObvCryptoId, keycloakUserDetails: ObvKeycloakUserDetails) async -> InvitationContactsListCellView.Model? {
        return nil
    }
    
}

// MARK: - Minimal implementation of ObvInvitationContactsListViewDataSource

extension MinimalDataSourceAndActionsForPreviews: ListOfContactsAndGroupsViewDataSource {
    
    func getAsyncStreamOfInvitationContactsListViewModel(_ view: ListOfContactsAndGroupsView.ListOfLocalContactsView, ownedCryptoId: ObvTypes.ObvCryptoId, initialSearchStatus: InvitationContactsListViewModel.SearchStatus) throws -> (streamUUID: UUID, stream: AsyncStream<InvitationContactsListViewModel>) {
        let streamUUID = UUID()
        let stream = AsyncStream(InvitationContactsListViewModel.self) { (continuation: AsyncStream<InvitationContactsListViewModel>.Continuation) in
            let viewModel = InvitationContactsListViewModel.sampleDatasForLocalContacts.filterSampleDatas(searchStatus: initialSearchStatus)
            self.continuationInvitationContactsListViewModelForLocalContacts = continuation
            continuation.yield(viewModel)
        }
        return (streamUUID, stream)
    }
    
    func filterAsyncSequenceOfInvitationContactsListViewModel(_ view: ListOfContactsAndGroupsView.ListOfLocalContactsView, streamUUID: UUID, searchStatus: InvitationContactsListViewModel.SearchStatus) {
        guard let continuation = continuationInvitationContactsListViewModelForLocalContacts else { return }
        let filteredViewModel = InvitationContactsListViewModel.sampleDatasForLocalContacts.filterSampleDatas(searchStatus: searchStatus)
        continuation.yield(filteredViewModel)
    }
    
    func finishAsyncStreamOfInvitationContactsListViewModel(_ view: ListOfContactsAndGroupsView.ListOfLocalContactsView, streamUUID: UUID) {
        // Nothing to finish in previews
    }

    func getAsyncStreamOfInvitationKeycloakContactsListViewModel(_ view: ListOfContactsAndGroupsView.ListOfDirectoryContactsView, ownedCryptoId: ObvTypes.ObvCryptoId, initialSearchStatus: InvitationContactsListViewModel.SearchStatus) throws -> (streamUUID: UUID, stream: AsyncStream<InvitationKeycloakContactsListViewModel>) {
        let streamUUID = UUID()
        let stream = AsyncStream(InvitationKeycloakContactsListViewModel.self) { (continuation: AsyncStream<InvitationKeycloakContactsListViewModel>.Continuation) in
            let viewModel = InvitationContactsListViewModel.sampleDatasForKeycloakUsers.filterSampleDatas(searchStatus: initialSearchStatus)
            self.continuationInvitationContactsListViewModelForKeycloakUsers = continuation
            continuation.yield(.success(viewModel))
            //continuation.yield(.error(.permissionDenied))
        }
        return (streamUUID, stream)
    }
    
    func filterAsyncStreamOfInvitationKeycloakContactsListViewModel(_ view: ListOfContactsAndGroupsView.ListOfDirectoryContactsView, streamUUID: UUID, searchStatus: InvitationContactsListViewModel.SearchStatus) {
        guard let continuation = continuationInvitationContactsListViewModelForKeycloakUsers else { return }
        let filteredViewModel = InvitationContactsListViewModel.sampleDatasForKeycloakUsers.filterSampleDatas(searchStatus: searchStatus)
        print("filteredViewModel.contactIdentifiers.count: \(filteredViewModel.contactIdentifiers.count)")
        continuation.yield(.success(filteredViewModel))
        //continuation.yield(.error(.permissionDenied))
    }
    
    func finishAsyncStreamOfInvitationKeycloakContactsListViewModel(_ view: ListOfContactsAndGroupsView.ListOfDirectoryContactsView, streamUUID: UUID) {
        // Nothing to finish in previews
    }

    func getAsyncStreamOfInvitationFlowGroupListViewModel(_ view: ListOfContactsAndGroupsView.ListOfGroupsView, ownedCryptoId: ObvTypes.ObvCryptoId, initialSearchStatus: InvitationFlowGroupListViewModel.SearchStatus) throws -> (streamUUID: UUID, stream: AsyncStream<InvitationFlowGroupListViewModel>) {
        let stream = AsyncStream<InvitationFlowGroupListViewModel> { (continuation: AsyncStream<InvitationFlowGroupListViewModel>.Continuation) in
            let viewModel = InvitationFlowGroupListViewModel.sampleData.filterSampleDatas(searchStatus: initialSearchStatus)
            self.continuationInvitationFlowGroupListViewModel = continuation
            continuation.yield(viewModel)
        }
        return (UUID(), stream)
    }
    
    func filterAsyncStreamOfInvitationFlowGroupListViewModel(_ view: ListOfContactsAndGroupsView.ListOfGroupsView, streamUUID: UUID, searchStatus: InvitationFlowGroupListViewModel.SearchStatus) {
        print("filterAsyncStreamOfInvitationFlowGroupListViewModel")
        guard let continuation = continuationInvitationFlowGroupListViewModel else { return }
        let filteredViewModel = InvitationFlowGroupListViewModel.sampleData.filterSampleDatas(searchStatus: searchStatus)
        print("filteredViewModel.groupIdentifiers.count: \(filteredViewModel.groupIdentifiers.count)")
        continuation.yield(filteredViewModel)
    }
    
    func finishAsyncStreamOfInvitationFlowGroupListViewModel(_ view: ListOfContactsAndGroupsView.ListOfGroupsView, streamUUID: UUID) {
        // Nothing to finish in previews
    }

}

// MARK: - Minimal implementation of ObvExternalInvitationHandlerViewDataSource

extension MinimalDataSourceAndActionsForPreviews: ObvExternalInvitationHandlerViewDataSource {
    
    func getAsyncStreamOfObvExternalInvitationHandlerViewModel(_ view: ExternalInvitationHandlerView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvExternalInvitationHandlerViewModel>) {
        let stream = AsyncStream<ObvExternalInvitationHandlerViewModel> { (continuation: AsyncStream<ObvExternalInvitationHandlerViewModel>.Continuation) in
            // We do nothing in previews
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfObvExternalInvitationHandlerViewModel(_ view: ExternalInvitationHandlerView, streamUUID: UUID) {
        // Nothing to finish in previews
    }
    
}

// MARK: - Minimal implementation of ObvSharingProfileViewDataSource

extension MinimalDataSourceAndActionsForPreviews: ObvSharingProfileViewDataSource {
    
    func getAsyncStreamOfInvitationFlowViewModel(_ view: SharingProfileView, currentOwnedCryptoId: ObvTypes.ObvCryptoId) throws -> (streamUUID: UUID, stream: AsyncStream<SharingProfileViewModel>) {
        let stream = AsyncStream(SharingProfileViewModel.self) { (continuation: AsyncStream<SharingProfileViewModel>.Continuation) in
            continuation.yield(SharingProfileViewModel.sampleDatas[0])
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfInvitationFlowViewModel(_ view: SharingProfileView, streamUUID: UUID) {
        // Nothing to finish in previews
    }

}


// MARK: - Minimal implementation of ObvCopyPasteMenuActions

extension MinimalDataSourceAndActionsForPreviews: ObvCopyPasteMenuActions {
    
    func userWantsToCopyOwnedIdentityToClipboard(_ view: CopyPasteMenu, ownedCryptoId: ObvCryptoId) throws {
        print("User wants to copy their own crypto ID to the clipboard")
    }

    func userWantsToPasteOlvidURLFromClipboard(_ view: CopyPasteMenu, ownedCryptoId: ObvCryptoId) throws -> OlvidURL {
        print("User wants to paste OlvidURL from clipboard")
        return OlvidURL(url: URL(string: "https://olvid.io")!, category: .invitation(urlIdentity: ObvURLIdentity.sampleDataRemoteIdentity))
    }
        
}

// MARK: Minimal implementation of ObvContactInvitationViewAction

extension MinimalDataSourceAndActionsForPreviews: ObvContactInvitationViewAction {

    func userWantsToInviteContactsToOneToOne(_ view: ContactInvitationView, ownedCryptoId: ObvTypes.ObvCryptoId, users: [(cryptoId: ObvTypes.ObvCryptoId, keycloakDetails: ObvTypes.ObvKeycloakUserDetails?)]) async throws {
        print("User wants to invite contacts to one-to-one")
    }

    func userWantsToRemoveOneToOneInvitationSent(_ view: ContactInvitationView, contactIdentifier: ObvContactIdentifier) async throws {
        print("User wants to remove one-to-one invitation sent")
    }
    
    func userWantsToDiscussWith(_ view: ContactInvitationView, obvContactIdentifier: ObvTypes.ObvContactIdentifier) {
        print("User wants to discuss with: \(obvContactIdentifier)")
    }
    
}

// MARK: Minimal implementation of ObvScanValidationViewActions

extension MinimalDataSourceAndActionsForPreviews: ObvScanValidationViewActions {
    
    func userWantsToNavigateToOneToOneDiscussion(_ view: ScanValidationView, obvContactIdentifier: ObvContactIdentifier) {
        print("User wants to discuss with: \(obvContactIdentifier)")
    }
    
}

// MARK: - Minimal implementation of ObvContactInvitationViewDataSource

extension MinimalDataSourceAndActionsForPreviews: ObvContactInvitationViewDataSource {
    
    func getAsyncStreamOfContactInvitationViewModel(_ view: ContactInvitationView, contactIdentifier: ContactInvitationViewModel.ContactIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ContactInvitationViewModel>) {
        let stream = AsyncStream(ContactInvitationViewModel.self) { (continuation: AsyncStream<ContactInvitationViewModel>.Continuation) in
            let model = ContactInvitationViewModel.sampleData(contactIdentifier)
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfContactInvitationViewModel(_ view: ContactInvitationView, streamUUID: UUID) {
        // Nothing to finish in previews
    }
    
}

// MARK: - Minimal implementation of InvitationContactsListViewActions

extension MinimalDataSourceAndActionsForPreviews: ListOfContactsAndGroupsViewActions {
    
    func userWantsToDismissInvitationFlow(_ view: ListOfContactsAndGroupsView) {
        print("User wants to dismiss invitation flow")
    }
    
    func userWantsToPerformKeycloakAuthentication(_ view: ListOfContactsAndGroupsView.ListOfDirectoryContactsView, ownedCryptoId: ObvCryptoId) async {
        print("User wants to perform keycloak authentication")
    }
    
    func userWantsToCreateGroup(_ view: ListOfContactsAndGroupsView.InvitationsContactsListContentView, ownedCryptoId: ObvCryptoId) {
        print("User wants to create a group")
    }

    func persistedObvContactIdentityTapped(_ view: ListOfContactsAndGroupsView.ListOfContactsCellForKeyView, currentCryptoId: ObvCryptoId, with objectID: NSManagedObjectID) async -> InvitationContactsListNavigationType {
        return .none
    }

    func keycloakContactIdentifierTapped(_ view: ListOfContactsAndGroupsView.ListOfContactsCellForKeyView, currentCryptoId: ObvCryptoId, with keycloakUserDetails: ObvKeycloakUserDetails) async -> InvitationContactsListNavigationType {
        return .none
    }
        
    
    func userPastedAnOlvidURL(_ view: ListOfContactsAndGroupsView, scannedOlvidURL: OlvidURL) -> (remoteURLIdentity: ObvURLIdentity, mutualScanURLToShow: ObvMutualScanUrl)? {
        print("User pasted an OlvidURL")
        return nil
    }
    
}

// MARK: - Minimal implementation of ObvAvatarViewDataSource

extension MinimalDataSourceAndActionsForPreviews: ObvAvatarViewDataSource {
    
    
    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return nil
    }
    
    func fetchAvatarFromCache(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }
    
}


// MARK: - Minimal implementation of ObvExternalInvitationHandlerViewActions

extension MinimalDataSourceAndActionsForPreviews: ObvExternalInvitationHandlerViewActions {
    
    func userWantsToStartTrustEstablishmentProtocolOfRemoteIdentity(_ view: ExternalInvitationHandlerView, ownedCryptoId: ObvCryptoId, remoteURLIdentity: ObvURLIdentity) {
        print("User wants to start trust establishment protocol of remote identity")
    }
    
}


// MARK: - Minimal implementation of ObvScanValidationViewDataSource

extension MinimalDataSourceAndActionsForPreviews: ObvScanValidationViewDataSource {
    
    /// Called to update the `ScanValidationView` (shown when confirming a successful double-scan invitation).
    ///
    /// Initially, the view shows minimal contact information (e.g., full display name).
    /// Once the contact is added to the database (when network conditions permit),
    /// the data source streams updated models—enabling features like avatar display and conversation availability.
    ///
    /// - Note:
    ///   This preview implementation simulates the contact addition process.
    func getAsyncStreamOfScanValidationViewModel(_ view: ScanValidationView, contactIdentifier: ObvTypes.ObvContactIdentifier, contactFullDisplayName: String) throws -> (streamUUID: UUID, stream: AsyncStream<ScanValidationViewModel>) {
        let streamUUID = UUID()
        let stream = AsyncStream(ScanValidationViewModel.self) { (continuation: AsyncStream<ScanValidationViewModel>.Continuation) in
            Task {
                try? await Task.sleep(seconds: 6) // Twice the time before the view updates itself to indicate that the contact will be added when network is back
                continuation.yield(ScanValidationViewModel.sampleDatas[1])
            }
        }
        return (streamUUID, stream)
    }
    
    func finishAsyncStreamOfScanValidationViewModel(_ view: ScanValidationView, streamUUID: UUID) {
        // Nothing to finish in previews
    }

}


// MARK: - Minimal implementation of ObvGroupCellViewDataSource

extension MinimalDataSourceAndActionsForPreviews: ObvGroupCellViewDataSource {
    
    func getAsyncStreamOfObvGroupCellViewModel(_ view: ObvCells.ObvGroupCellView, groupIdentifier: ObvCells.ObvGroupCellViewModel.GroupIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvCells.ObvGroupCellViewModel>) {
        let stream = AsyncStream<ObvCells.ObvGroupCellViewModel> { (continuation: AsyncStream<ObvGroupCellViewModel>.Continuation) in
            let viewModel: ObvGroupCellViewModel = ObvGroupCellViewModel.sampleData(groupIdentifier: groupIdentifier)
            continuation.yield(viewModel)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfObvGroupCellViewModel(_ view: ObvCells.ObvGroupCellView, streamUUID: UUID) {
        // Nothing to finish in previews
    }
    
}


// MARK: - Minimal implementation of ScannerViewActions

extension MinimalDataSourceAndActionsForPreviews: ObvScannerViewActions {
 
    func userScannedOrPastedAnOlvidURL(_ view: NewScannerView, scannedOlvidURL: OlvidURL) -> (remoteURLIdentity: ObvURLIdentity, mutualScanURLToShow: ObvMutualScanUrl)? {
        let remoteURLIdentity = ObvURLIdentity.sampleDataRemoteIdentity
        let mutualScanURLToShow = ObvMutualScanUrl.sampleData
        return (remoteURLIdentity, mutualScanURLToShow)
    }

    
    func userWantsToStartTrustEstablishmentProtocolOfRemoteIdentity(_ view: NewScannerView, ownedCryptoId: ObvCryptoId, remoteURLIdentity: ObvURLIdentity) {
        print("User wants to start trust establishment protocol")
    }
    
}


// MARK: - Minimal implementation of ObvQRCodeViewDataSource

extension MinimalDataSourceAndActionsForPreviews: ObvQRCodeViewDataSource {
    
    func getAsyncStreamOfObvQRCodeViewViewModel(_ view: QRCodeView, ownedCryptoId: ObvTypes.ObvCryptoId) throws -> (streamUUID: UUID, stream: AsyncStream<ObvQRCodeViewViewModel>) {
        let stream = AsyncStream<ObvQRCodeViewViewModel> { (continuation: AsyncStream<ObvQRCodeViewViewModel>.Continuation) in
            let viewModel: ObvQRCodeViewViewModel = .init(ownedIdentityAvatarViewModel: ObvAvatarViewModel.sampleData)
            continuation.yield(viewModel)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfObvQRCodeViewViewModel(_ view: QRCodeView, streamUUID: UUID) {
        // Nothing to finish in previews
    }
    
}


// MARK: - Minimal implementation of ObvNewScannerViewDataSource
extension MinimalDataSourceAndActionsForPreviews: ObvNewScannerViewDataSource {
    
    func getAsyncStreamOfObvNewScannerViewModel(_ view: NewScannerView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvNewScannerViewModel>) {
        let stream = AsyncStream<ObvNewScannerViewModel> { (continuation: AsyncStream<ObvNewScannerViewModel>.Continuation) in
            // We do nothing in previews
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfObvNewScannerViewModel(_ view: NewScannerView, streamUUID: UUID) {
        // Nothing to finish in previews
    }
    
}


extension MinimalDataSourceAndActionsForPreviews: InvitationFlowRouterNavigation {
    func userDidPressOnObvGroupCellView(_ view: ObvCells.ObvGroupCellView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, expectedNavigation: ObvCells.ObvGroupCellView.ExpectedNavigation) throws {
        print("User did press on ObvGroupCellView")
    }
    
}
