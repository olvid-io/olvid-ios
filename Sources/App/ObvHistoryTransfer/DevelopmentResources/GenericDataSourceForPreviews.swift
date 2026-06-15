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

import Foundation
import ObvTypes
import ObvOwnedIdentityChooser
import ObvDesignSystem
import ObvAppTypes


@MainActor
final class GenericDataSourceForPreviews {}

extension GenericDataSourceForPreviews {
    
    enum ObvError: Error {
        case error
    }
    
}


// MARK: - Implementing OwnedIdentityChooserViewDataSource

extension GenericDataSourceForPreviews: OwnedIdentityChooserViewDataSource {
    
    func getAsyncStreamOfOwnedIdentityChooserViewModel(_ view: OwnedIdentityChooserInnerView, currentOwnedCryptoId: ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<OwnedIdentityChooserViewModel>) {
        let stream = AsyncStream<ObvOwnedIdentityChooser.OwnedIdentityChooserViewModel> { (continuation: AsyncStream<OwnedIdentityChooserViewModel>.Continuation) in
            let model: OwnedIdentityChooserViewModel = .init(ownedIdentities: OwnedIdentityChooserViewModel.OwnedIdentity.sampleDatasForOwnedCryptoId)
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfOwnedIdentityChooserViewModel(_ view: OwnedIdentityChooserInnerView, streamUUID: UUID) {}
    
}


// MARK: - Implementing ObvAvatarViewDataSource

extension GenericDataSourceForPreviews: ObvAvatarViewDataSource {
    
    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return nil
    }
    
    func fetchAvatarFromCache(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }
    
}


// MARK: - Implementing ZipExportViewDataSource

extension GenericDataSourceForPreviews: ZipExportViewDataSource {
    
    func evaluateZipFileContentToExpect(_ view: ComputingExportZipFileSizeView, ownedCryptoId: ObvTypes.ObvCryptoId, scope: TransferScope) async throws -> ComputingExportZipFileSizeView.ZipFileContentToExpect {
        try await Task.sleep(seconds: 2)
        return .init(numberOfMessages: 256, numberOfDiscussions: 10, numberOfFiles: 42, fileSizeInBytes: 20_000)
    }
    
}


// MAKR: - Implementing ListOfOtherOwnedDevicesViewDataSource

extension GenericDataSourceForPreviews: ListOfOtherOwnedDevicesViewDataSource {
    
    func getAsyncStreamOfListOfOtherOwnedDevicesViewModels(_ view: ListOfOtherOwnedDevicesView, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<ListOfOtherOwnedDevicesView.Model>) {
        let stream = AsyncStream<ListOfOtherOwnedDevicesView.Model> { (continuation: AsyncStream<ListOfOtherOwnedDevicesView.Model>.Continuation) in
            let model: ListOfOtherOwnedDevicesView.Model = .init(
                isCurrentDeviceActive: true,
                otherOwnedDevices: [
                    .init(ownedDeviceIdentifier: ObvOwnedDeviceIdentifier.sampleDatas[0], deviceName: "My first other device", platform: .iPhone),
                    .init(ownedDeviceIdentifier: ObvOwnedDeviceIdentifier.sampleDatas[1], deviceName: "My second other device", platform: .mac),
                ]
            )
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfListOfOtherOwnedDevicesViewModels(_ view: ListOfOtherOwnedDevicesView, streamUUID: UUID) {}
    
}


// MARK: - Implementing ListOfOtherOwnedDevicesViewActions

extension GenericDataSourceForPreviews: ListOfOtherOwnedDevicesViewActions {
    
    func userDidChooseOtherOwnedDevice(_ view: ListOfOtherOwnedDevicesInnerView, otherOwnedDeviceIdentifier: ObvOwnedDeviceIdentifier, nameOfRemoteDevice: String?) {
        print("User did choose other owned device")
    }
    
    func userTappedBackButton(_ view: ListOfOtherOwnedDevicesView) {
        print("User tapped back button")
    }
    
}

// MARK: - Implementing ZipTransferTransportDelegateDataSource

extension GenericDataSourceForPreviews: ZipTransferTransportDelegateDataSource {
    
    func getDisplayNameOfContacts(ownedCryptoId: ObvTypes.ObvCryptoId, contactCryptoIds: Set<ObvTypes.ObvCryptoId>) async throws -> [ObvTypes.ObvCryptoId : String] {
        var result = [ObvTypes.ObvCryptoId : String]()
        for contactCryptoId in contactCryptoIds {
            result[contactCryptoId] = "Fake displayname"
        }
        return result
    }

}


// MARK: - Implementing HistoryTransferNavigationStackActions

extension GenericDataSourceForPreviews: HistoryTransferNavigationStackActions {
    
    
    
    func userRequiresMessageHistoryTransferService(_ view: ZipExportView) async throws -> any TransferServiceForZipExportView {
        print("User requires message history transfer service")
        return TransferService(temporaryDirectory: FileManager.default.temporaryDirectory, delegate: self, dataSources: .init(sourceTransferStepsDataSource: self, destinationTransferStepsDataSource: self, zipTransferTransportDelegateDataSource: self), actionsOnDestination: self)
    }
    
    func userRequiresMessageHistoryTransferService(_ view: LocalNetworkExportView) async throws -> any TransferServiceForLocalNetworkExportView {
        print("User requires message history transfer service")
        return TransferService(
            temporaryDirectory: FileManager.default.temporaryDirectory,
            delegate: self,
            dataSources: .init(sourceTransferStepsDataSource: self, destinationTransferStepsDataSource: self, zipTransferTransportDelegateDataSource: self),
            actionsOnDestination: self)
    }
    
    func historySourceDeviceWantsToSendTransferConfirmationRequestToDestinationOwnedDevice(_ view: LocalNetworkExportView, transferId: String, otherOwnedDeviceIdentifier: ObvTypes.ObvOwnedDeviceIdentifier) async throws -> DestinationOwnedDeviceDecision {
        print("History source device wants to connect to destination owned device")
        try await Task.sleep(seconds: 1) // Simulates the time required to send a message to the other owned device (destination) showing the confirmation screen to the user, the choice made by the user, then message sent back to us with the decision
        return .startTransfer
    }

    func userRequiresMessageHistoryTransferService(_ view: LocalNetworkImportView) async throws -> any TransferServiceForLocalNetworkImportView {
        return TransferService(
            temporaryDirectory: FileManager.default.temporaryDirectory,
            delegate: self,
            dataSources: .init(sourceTransferStepsDataSource: self, destinationTransferStepsDataSource: self, zipTransferTransportDelegateDataSource: self),
            actionsOnDestination: self)
    }
    
    func userWantsToDismissView(_ view: LocalNetworkImportView) {
        print("User wants to dismiss view")
    }

    func userWantsToDismissView(_ view: LocalNetworkExportView) {
        print("User wants to dismiss view")
    }
    
    func userWantsToDismissHistoryTransferNavigationStack(_ view: HistoryTransferNavigationStack) {
        print("User wants to dismiss view")
    }
    
//    func userRequiresMessageHistoryTransferService(_ view: WifiAwareExportView) async throws -> any TransferServiceForWifiAwareExportView {
//        return TransferService(
//            temporaryDirectory: FileManager.default.temporaryDirectory,
//            delegate: self,
//            dataSources: .init(sourceTransferStepsDataSource: self, destinationTransferStepsDataSource: self, zipTransferTransportDelegateDataSource: self),
//            actionsOnDestination: self)
//    }
    
//    func userRequiresMessageHistoryTransferService(_ view: WifiAwareImportView) async throws -> any TransferServiceForWifiAwareImportView {
//        if #available(iOS 26.0, *) {
//            return TransferService(
//                temporaryDirectory: FileManager.default.temporaryDirectory,
//                delegate: self,
//                dataSources: .init(sourceTransferStepsDataSource: self, destinationTransferStepsDataSource: self, zipTransferTransportDelegateDataSource: self),
//                actionsOnDestination: self)
//        } else {
//            assertionFailure()
//            throw ObvError.error
//        }
//    }
}


// MARK: - Implementing ZipImportViewActions

extension GenericDataSourceForPreviews: ZipImportViewActions {
    
    func userRequiresMessageHistoryTransferService(_ view: ZipImportView) async throws -> any TransferServiceForZipImportView {
        print("User requires message history transfer service")
        return TransferService(temporaryDirectory: FileManager.default.temporaryDirectory, delegate: self, dataSources: .init(sourceTransferStepsDataSource: self, destinationTransferStepsDataSource: self, zipTransferTransportDelegateDataSource: self), actionsOnDestination: self)
    }
    
    func userWantsToDismissView(_ view: ZipImportView) {
        print("User wants to dismiss view")
    }
    
}


// MARK: - Implementing HistoryTransferNavigationStackActions

extension GenericDataSourceForPreviews: TransferServiceDelegate {
    
    func getWellKnownTurnCredentials(_ actor: TransferService, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> ObvTypes.ObvWellKnownTurnCredentials? {
        return nil
    }
    
    func sendSignalingMessage(_ actor: TransferService, signalingMessage: WebrtcHistoryTransferMessage, toOtherOwnedDevice otherOwnedDevice: ObvTypes.ObvOwnedDeviceIdentifier) async throws {
        try? await Task.sleep(seconds: 1)
    }
    
    func sendInterruptMessage(_ actor: TransferService, transferId: String, toOtherOwnedDevice otherOwnedDevice: ObvOwnedDeviceIdentifier) async throws {
        try? await Task.sleep(seconds: 1)
    }
    
    func userWantsToAcceptHistoryTransfer(_ actor: TransferService, sourceDeviceIdentifier: ObvOwnedDeviceIdentifier, transferIdFromSource: String) async throws {
        print("User wants to accept history transfer")
    }
    
    func userWantsToCancelHistoryTransfer(_ actor: TransferService, sourceDeviceIdentifier: ObvOwnedDeviceIdentifier, transferIdFromSource: String) async throws {
        print("User wants to cancel history transfer")
    }
    
}


// MARK: - Implementing SourceTransferStepsDataSource

extension GenericDataSourceForPreviews: SourceTransferStepsDataSource {
        
    func historyTransferRequiresAllDiscussionIdentifiers(_ actor: SourceTransferSteps, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> [ObvAppTypes.ObvDiscussionIdentifier] {
        return []
    }
    
    func historyTransferRequiresAllHashAndSizesOfFyles(_ actor: SourceTransferSteps, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> [Data : UInt64] {
        return [:]
    }
    
    func historyTransferRequiresTitleAndAllMessageIdentifiersOfDiscussion(_ actor: SourceTransferSteps, discussionIdentifier: ObvDiscussionIdentifier) async throws -> (discussionTitle: String, messageIdentifiers: [ObvMessageAppIdentifier]) {
        return ("The sample discussion title", [])
    }

    func historyTransferRequiresMessages(_ actor: SourceTransferSteps, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, messageIdentifiers: [ObvAppTypes.ObvMessageAppIdentifier]) async throws -> SourceTransferSteps.MessagesToSend {
        return .discussionNotFound
    }

    func historyTransferRequiresSafeAttachmentURL(_ actor: SourceTransferSteps, sha256: Data) async throws -> URL {
        let url = URL(string: "https://olvid.io")! // In practice, the URL would be the URL of a file (attachment) on disk
        return url
    }

    func historyTransferNoLongerRequiresSafeAttachmentURL(_ actor: SourceTransferSteps, sha256: Data, url: URL) async throws {
        // Nothing to do in previews
    }
    
}


// MARK: - Implementing DestinationTransferStepsDataSource

extension GenericDataSourceForPreviews: DestinationTransferStepsDataSource {
    
    func filterKnownAndCompleteFyles(_ actor: DestinationTransferSteps, sha256s: [Data]) async throws -> [Data] {
        return []
    }
    
    func filterKnownMessages(_ actor: DestinationTransferSteps, discussionIdentifier: ObvDiscussionIdentifier, messagesAvailableOnSource: [ObvMessageAppIdentifier]) async throws -> [ObvMessageAppIdentifier] {
        return []
    }

}


// MARK: - Implementing DestinationTransferStepsActions

extension GenericDataSourceForPreviews: DestinationTransferStepsActions {
    func historyTransferRequiresToStoreSourcesMessagesOnThisDestination(_ actor: DestinationTransferSteps, messagesToStore: [ObvAppTypes.ObvHistoryReceivedMessage]) async throws -> (sha256ToRequestToSource: [Data : UInt64], sha256NotToBeRequestedToSource: Set<Data>) {
        print("History transfer requires to store sources messages on this destination")
        return ([:], [])
    }
    
    func historyTransferRequiresToStoreAttachmentOnThisDestination(_ actor: DestinationTransferSteps, sha256: Data, temporaryURLOfAttachment: URL) async throws {
        print("History transfer requires to store attachment on this destination")
    }

}
