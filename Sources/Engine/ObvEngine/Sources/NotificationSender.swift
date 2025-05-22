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

import Foundation
import CoreData
import os.log
import UserNotifications
import ObvMetaManager
import ObvCrypto
import ObvEncoder
import ObvTypes
import OlvidUtils


extension ObvEngine {
    
    func registerToInternalNotifications() throws {
        
        guard let notificationDelegate = notificationDelegate else { throw Self.makeError(message: "The notification delegate is not set") }
                
        notificationCenterTokens.append(contentsOf: [
            ObvNetworkPostNotification.observeOutboxMessageWasUploaded(within: notificationDelegate, queue: nil) { [weak self] (messageId, timestampFromServer, isAppMessageWithUserContent, isVoipMessage, flowId) in
                self?.processOutboxMessageWasUploadedNotification(messageId: messageId, timestampFromServer: timestampFromServer, isAppMessageWithUserContent: isAppMessageWithUserContent, isVoipMessage: isVoipMessage, flowId: flowId)
            },
            ObvNetworkPostNotification.observeOutboxMessagesAndAllTheirAttachmentsWereAcknowledged(within: notificationDelegate) { [weak self] (messageIdsAndTimestampsFromServer, flowId) in
                self?.processOutboxMessagesAndAllTheirAttachmentsWereAcknowledgedNotifications(messageIdsAndTimestampsFromServer: messageIdsAndTimestampsFromServer, flowId: flowId)
            },
            ObvNetworkPostNotification.observeOutboxMessageCouldNotBeSentToServer(within: notificationDelegate) { [weak self] (messageId, flowId) in
                self?.processOutboxMessageCouldNotBeSentToServer(messageId: messageId, flowId: flowId)
            },
        ])
                
        do {
            let token = ObvNetworkPostNotification.observeOutboxAttachmentWasAcknowledged(within: notificationDelegate, queue: nil) { [weak self] (attachmentId, flowId) in
                self?.processAttachmentWasAcknowledgedNotification(attachmentId: attachmentId, flowId: flowId)
            }
            notificationCenterTokens.append(token)
        }

        do {
            let token = ObvIdentityNotificationNew.observeContactIdentityIsNowTrusted(within: notificationDelegate) { [weak self] (contactIdentity, ownedIdentity, flowId) in
                self?.processContactIdentityIsNowTrustedNotification(ownedCryptoIdentity: ownedIdentity, contactCryptoIdentity: contactIdentity, flowId: flowId)
            }
            notificationCenterTokens.append(token)
        }
        
        do {
            let token = ObvChannelNotification.observeNewConfirmedObliviousChannel(within: notificationDelegate) { [weak self] (currentDeviceUid, remoteCryptoIdentity, remoteDeviceUid) in
                self?.processNewConfirmedObliviousChannelNotification(currentDeviceUid: currentDeviceUid, remoteCryptoIdentity: remoteCryptoIdentity, remoteDeviceUid: remoteDeviceUid)
            }
            notificationCenterTokens.append(token)
        }
                
        registerToContactWasDeletedNotifications(notificationDelegate: notificationDelegate)

        do {
            let NotificationType = ObvIdentityNotification.NewContactGroupJoined.self
            let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
                guard let (groupUid, groupOwner, ownedIdentity) = NotificationType.parse(notification) else { return }
                self?.processNewContactGroupJoinedNotification(groupUid: groupUid, groupOwner: groupOwner, ownedIdentity: ownedIdentity)
            }
            notificationCenterTokens.append(token)
        }

        do {
            let NotificationType = ObvIdentityNotification.NewContactGroupOwned.self
            let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
                guard let (groupUid, ownedIdentity) = NotificationType.parse(notification) else { return }
                self?.processNewContactGroupOwnedNotification(groupUid: groupUid, ownedIdentity: ownedIdentity)
            }
            notificationCenterTokens.append(token)
        }

        do {
            let NotificationType = ObvIdentityNotification.ContactGroupOwnedHasUpdatedPendingMembersAndGroupMembers.self
            let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
                guard let (groupUid, ownedIdentity) = NotificationType.parse(notification) else {
                    return
                }
                self?.processContactGroupOwnedHasUpdatedPendingMembersAndGroupMembersNotification(groupUid: groupUid, ownedIdentity: ownedIdentity)
            }
            notificationCenterTokens.append(token)
        }

        do {
            let NotificationType = ObvIdentityNotification.ContactGroupJoinedHasUpdatedPendingMembersAndGroupMembers.self
            let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
                guard let (groupUid, groupOwner, ownedIdentity) = NotificationType.parse(notification) else {
                    return
                }
                self?.processContactGroupJoinedHasUpdatedPendingMembersAndGroupMembersNotification(groupUid: groupUid, groupOwner: groupOwner, ownedIdentity: ownedIdentity)
            }
            notificationCenterTokens.append(token)
        }

        do {
            let NotificationType = ObvIdentityNotification.ContactGroupOwnedHasUpdatedPublishedDetails.self
            let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
                guard let (groupUid, ownedIdentity) = NotificationType.parse(notification) else { return }
                self?.processContactGroupOwnedHasUpdatedPublishedDetailsNotification(groupUid: groupUid, ownedIdentity: ownedIdentity)
            }
            notificationCenterTokens.append(token)
        }
        
        do {
            let NotificationType = ObvIdentityNotification.ContactGroupJoinedHasUpdatedPublishedDetails.self
            let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
                guard let (groupUid, groupOwner, ownedIdentity) = NotificationType.parse(notification) else { return }
                self?.processContactGroupJoinedHasUpdatedPublishedDetailsNotification(groupUid: groupUid, groupOwner: groupOwner, ownedIdentity: ownedIdentity)
            }
            notificationCenterTokens.append(token)
        }

        do {
            let NotificationType = ObvIdentityNotification.ContactGroupDeleted.self
            let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
                guard let (groupUid, groupOwner, ownedIdentity) = NotificationType.parse(notification) else { return }
                self?.processContactGroupDeletedNotification(groupUid: groupUid, groupOwner: groupOwner, ownedIdentity: ownedIdentity)
            }
            notificationCenterTokens.append(token)
        }

        do {
            let NotificationType = ObvIdentityNotification.ContactGroupOwnedHasUpdatedLatestDetails.self
            let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
                guard let (groupUid, ownedIdentity) = NotificationType.parse(notification) else { return }
                self?.processContactGroupOwnedHasUpdatedLatestDetailsNotification(groupUid: groupUid, ownedIdentity: ownedIdentity)
            }
            notificationCenterTokens.append(token)
        }

        do {
            let NotificationType = ObvIdentityNotification.ContactGroupOwnedDiscardedLatestDetails.self
            let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
                guard let (groupUid, ownedIdentity) = NotificationType.parse(notification) else { return }
                self?.processContactGroupOwnedDiscardedLatestDetailsNotification(groupUid: groupUid, ownedIdentity: ownedIdentity)
            }
            notificationCenterTokens.append(token)
        }

        do {
            let NotificationType = ObvIdentityNotification.ContactGroupJoinedHasUpdatedTrustedDetails.self
            let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
                guard let (groupUid, groupOwner, ownedIdentity) = NotificationType.parse(notification) else {
                    return
                }
                self?.processContactGroupJoinedHasUpdatedTrustedDetailsNotification(groupUid: groupUid, groupOwner: groupOwner, ownedIdentity: ownedIdentity)
            }
            notificationCenterTokens.append(token)
        }

        do {
            let NotificationType = ObvIdentityNotification.PendingGroupMemberDeclinedInvitationToOwnedGroup.self
            let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
                guard let (groupUid, ownedIdentity, contactIdentity) = NotificationType.parse(notification) else {
                    return
                }
                self?.processPendingGroupMemberDeclinedInvitationToOwnedGroupNotification(groupUid: groupUid, ownedIdentity: ownedIdentity, contactIdentity: contactIdentity)
            }
            notificationCenterTokens.append(token)
        }

        do {
            let NotificationType = ObvIdentityNotification.DeclinedPendingGroupMemberWasUndeclinedForOwnedGroup.self
            let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
                guard let (groupUid, ownedIdentity, contactIdentity) = NotificationType.parse(notification) else {
                    return
                }
                self?.processDeclinedPendingGroupMemberWasUndeclinedForOwnedGroupNotification(groupUid: groupUid, ownedIdentity: ownedIdentity, contactIdentity: contactIdentity)
            }
            notificationCenterTokens.append(token)
        }
        
        do {
            let token = ObvIdentityNotificationNew.observeOwnedIdentityWasDeactivated(within: notificationDelegate) { [weak self] (ownedIdentity, flowId) in
                guard let appNotificationCenter = self?.appNotificationCenter else { return }
                let ownedCryptoId = ObvCryptoId(cryptoIdentity: ownedIdentity)
                let notification = ObvEngineNotificationNew.ownedIdentityWasDeactivated(ownedIdentity: ownedCryptoId)
                notification.postOnBackgroundQueue(within: appNotificationCenter)
            }
            notificationCenterTokens.append(token)
        }

        do {
            let token = ObvIdentityNotificationNew.observeOwnedIdentityWasReactivated(within: notificationDelegate) { [weak self] (ownedIdentity, flowId) in
                guard let appNotificationCenter = self?.appNotificationCenter else { return }
                let ownedCryptoId = ObvCryptoId(cryptoIdentity: ownedIdentity)
                let notification = ObvEngineNotificationNew.ownedIdentityWasReactivated(ownedIdentity: ownedCryptoId)
                notification.postOnBackgroundQueue(within: appNotificationCenter)
            }
            notificationCenterTokens.append(token)
        }

        do {
            let token = ObvNetworkFetchNotificationNew.observeFetchNetworkOperationFailedSinceOwnedIdentityIsNotActive(within: notificationDelegate) { [weak self] (ownedIdentity, flowId) in
                guard let appNotificationCenter = self?.appNotificationCenter else { return }
                let ownedCryptoId = ObvCryptoId(cryptoIdentity: ownedIdentity)
                let notification = ObvEngineNotificationNew.networkOperationFailedSinceOwnedIdentityIsNotActive(ownedIdentity: ownedCryptoId)
                notification.postOnBackgroundQueue(within: appNotificationCenter)
            }
            notificationCenterTokens.append(token)
        }

        do {
            let token = ObvNetworkPostNotification.observePostNetworkOperationFailedSinceOwnedIdentityIsNotActive(within: notificationDelegate) { [weak self] (ownedIdentity, flowId) in
                guard let appNotificationCenter = self?.appNotificationCenter else { return }
                let ownedCryptoId = ObvCryptoId(cryptoIdentity: ownedIdentity)
                let notification = ObvEngineNotificationNew.networkOperationFailedSinceOwnedIdentityIsNotActive(ownedIdentity: ownedCryptoId)
                notification.postOnBackgroundQueue(within: appNotificationCenter)
            }
            notificationCenterTokens.append(token)
        }

        do {
            let token = ObvNetworkFetchNotificationNew.observeServerRequiresThisDeviceToRegisterToPushNotifications(within: notificationDelegate) { [weak self] (_, flowId) in
                guard let appNotificationCenter = self?.appNotificationCenter else { assertionFailure(); return }
                ObvEngineNotificationNew.serverRequiresAllActiveOwnedIdentitiesToRegisterToPushNotifications
                    .postOnBackgroundQueue(within: appNotificationCenter)
            }
            notificationCenterTokens.append(token)
        }
        
        // ObvProtocolNotification

        notificationCenterTokens.append(contentsOf: [
            ObvProtocolNotification.observeMutualScanContactAdded(within: notificationDelegate) { [weak self] ownedIdentity, contactIdentity, signature in
                self?.processMutualScanContactAdded(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, signature: signature)
            },
            ObvProtocolNotification.observeKeycloakSynchronizationRequired(within: notificationDelegate) { [weak self] ownedIdentity in
                self?.processKeycloakSynchronizationRequired(ownedIdentity: ownedIdentity)
            },
            ObvProtocolNotification.observeGroupV2UpdateDidFail(within: notificationDelegate) { [weak self] ownedIdentity, appGroupIdentifier, flowId in
                self?.processGroupV2UpdateDidFail(ownedIdentity: ownedIdentity, appGroupIdentifier: appGroupIdentifier, flowId: flowId)
            },
            ObvProtocolNotification.observeContactIntroductionInvitationSent(within: notificationDelegate) { [weak self] ownedIdentity, contactIdentityA, contactIdentityB in
                self?.processContactIntroductionInvitationSent(ownedIdentity: ownedIdentity, contactIdentityA: contactIdentityA, contactIdentityB: contactIdentityB)
            },
            ObvProtocolNotification.observeTheCurrentDeviceWasNotPartOfTheLastOwnedDeviceDiscoveryResults(within: notificationDelegate) { [weak self] ownedCryptoIdentity in
                self?.processTheCurrentDeviceWasNotPartOfTheLastOwnedDeviceDiscoveryResults(ownedCryptoIdentity: ownedCryptoIdentity)
            },
            ObvProtocolNotification.observeAnOwnedIdentityTransferProtocolFailed(within: notificationDelegate) { [weak self] ownedCryptoIdentity, protocolInstanceUID, error in
                self?.processAnOwnedIdentityTransferProtocolFailed(ownedCryptoIdentity: ownedCryptoIdentity, protocolInstanceUID: protocolInstanceUID, error: error)
            },
        ])
        
        // ObvIdentityNotificationNew notifications
        
        notificationCenterTokens.append(contentsOf: [
            ObvIdentityNotificationNew.observeTrustedPhotoOfContactIdentityHasBeenUpdated(within: notificationDelegate) { [weak self] (ownedIdentity, contactIdentity) in
                self?.processTrustedPhotoOfContactIdentityHasBeenUpdated(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity)
            },
            ObvIdentityNotificationNew.observePublishedPhotoOfContactIdentityHasBeenUpdated(within: notificationDelegate) { [weak self] (ownedIdentity, contactIdentity) in
                self?.processPublishedPhotoOfContactIdentityHasBeenUpdated(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity)
            },
            ObvIdentityNotificationNew.observePublishedPhotoOfOwnedIdentityHasBeenUpdated(within: notificationDelegate) { [weak self] ownedIdentity in
                self?.processPublishedPhotoOfOwnedIdentityHasBeenUpdated(ownedIdentity: ownedIdentity)
            },
            ObvIdentityNotificationNew.observeTrustedPhotoOfContactGroupJoinedHasBeenUpdated(within: notificationDelegate) { [weak self] (groupUid, ownedIdentity, groupOwner) in
                self?.processTrustedPhotoOfContactGroupJoinedHasBeenUpdated(groupUid: groupUid, ownedIdentity: ownedIdentity, groupOwner: groupOwner)
            },
            ObvIdentityNotificationNew.observePublishedPhotoOfContactGroupJoinedHasBeenUpdated(within: notificationDelegate) { [weak self] (groupUid, ownedIdentity, groupOwner) in
                self?.processPublishedPhotoOfContactGroupJoinedHasBeenUpdated(groupUid: groupUid, ownedIdentity: ownedIdentity, groupOwner: groupOwner)
            },
            ObvIdentityNotificationNew.observePublishedPhotoOfContactGroupOwnedHasBeenUpdated(within: notificationDelegate) { [weak self] (groupUid, ownedIdentity) in
                self?.processPublishedPhotoOfContactGroupOwnedHasBeenUpdated(groupUid: groupUid, ownedIdentity: ownedIdentity)
            },
            ObvIdentityNotificationNew.observeLatestPhotoOfContactGroupOwnedHasBeenUpdated(within: notificationDelegate) { [weak self] (groupUid, ownedIdentity) in
                self?.processLatestPhotoOfContactGroupOwnedHasBeenUpdated(groupUid: groupUid, ownedIdentity: ownedIdentity)
            },
            ObvIdentityNotificationNew.observeOwnedIdentityKeycloakServerChanged(within: notificationDelegate) { [weak self] ownedCryptoIdentity, flowId in
                self?.processOwnedIdentityKeycloakServerChanged(ownedCryptoIdentity: ownedCryptoIdentity, flowId: flowId)
            },
            ObvIdentityNotificationNew.observeContactWasUpdatedWithinTheIdentityManager(within: notificationDelegate) { [weak self] (ownedIdentity, contactIdentity, flowId) in
                self?.processContactWasUpdatedWithinTheIdentityManager(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, flowId: flowId)
            },
            ObvIdentityNotificationNew.observeContactIsActiveChanged(within: notificationDelegate) { [weak self] (ownedIdentity, contactIdentity, isActive, flowId) in
                self?.processContactIsActiveChanged(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, isActive: isActive, flowId: flowId)
            },
            ObvIdentityNotificationNew.observeContactWasRevokedAsCompromised(within: notificationDelegate) { [weak self] ownedIdentity, contactIdentity, flowId in
                self?.processContactWasRevokedAsCompromised(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, flowId: flowId)
            },
            ObvIdentityNotificationNew.observeContactObvCapabilitiesWereUpdated(within: notificationDelegate) { [weak self] ownedIdentity, contactIdentity, flowId in
                self?.processContactObvCapabilitiesWereUpdated(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, flowId: flowId)
            },
            ObvIdentityNotificationNew.observeUpdatedContactDevice(within: notificationDelegate) { [weak self] deviceIdentifier, flowId in
                self?.processUpdatedContactDevice(deviceIdentifier: deviceIdentifier, flowId: flowId)
            },
            ObvIdentityNotificationNew.observeOwnedIdentityCapabilitiesWereUpdated(within: notificationDelegate) { [weak self] ownedIdentity, flowId in
                self?.processOwnedIdentityCapabilitiesWereUpdated(ownedIdentity: ownedIdentity, flowId: flowId)
            },
            ObvIdentityNotificationNew.observeGroupV2WasCreated(within: notificationDelegate) { [weak self] (obvGroupV2, initiator) in
                self?.processGroupV2WasCreated(obvGroupV2: obvGroupV2, initiator: initiator)
            },
            ObvIdentityNotificationNew.observeGroupV2WasUpdated(within: notificationDelegate) { [weak self] (obvGroupV2, initiator) in
                self?.processGroupV2WasUpdated(obvGroupV2: obvGroupV2, initiator: initiator)
            },
            ObvIdentityNotificationNew.observeGroupV2WasDeleted(within: notificationDelegate) { [weak self] (ownedIdentity, appGroupIdentifier) in
                self?.processGroupV2WasDeleted(ownedIdentity: ownedIdentity, appGroupIdentifier: appGroupIdentifier)
            },
            ObvIdentityNotificationNew.observeNewRemoteOwnedDevice(within: notificationDelegate) { [weak self] ownedCryptoId, remoteDeviceUid, _ in
                self?.processNewRemoteOwnedDevice(ownedCryptoId: ownedCryptoId, remoteDeviceUid: remoteDeviceUid)
            },
            ObvIdentityNotificationNew.observeAnOwnedDeviceWasUpdated(within: notificationDelegate) { [weak self] ownedCryptoId in
                self?.processAnOwnedDeviceWasUpdated(ownedCryptoId: ownedCryptoId)
            },
            ObvIdentityNotificationNew.observeAnOwnedDeviceWasDeleted(within: notificationDelegate) { [weak self] ownedCryptoId in
                self?.processAnOwnedDeviceWasDeleted(ownedCryptoId: ownedCryptoId)
            },
            ObvIdentityNotificationNew.observeNewContactDevice(within: notificationDelegate) { [weak self] ownedIdentity, contactIdentity, _, _, _ in
                self?.processNewContactDevice(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity)
            },
            ObvIdentityNotificationNew.observePushTopicOfKeycloakGroupWasUpdated(within: notificationDelegate) { [weak self] ownedIdentity in
                self?.processPushTopicOfKeycloakGroupWasUpdated(ownedIdentity: ownedIdentity)
            },
        ])

        do {
            let token = ObvChannelNotification.observeDeletedConfirmedObliviousChannel(within: notificationDelegate) { [weak self] (currentDeviceUid, remoteCryptoIdentity, remoteDeviceUid) in
                self?.processDeletedConfirmedObliviousChannelNotifications(currentDeviceUid: currentDeviceUid, remoteCryptoIdentity: remoteCryptoIdentity, remoteDeviceUid: remoteDeviceUid)
            }
            notificationCenterTokens.append(token)
        }

        observeNewPublishedContactIdentityDetailsNotifications(notificationDelegate: notificationDelegate)
        observeOwnedIdentityDetailsPublicationInProgressNotifications(notificationDelegate: notificationDelegate)
        observeNewTrustedContactIdentityDetailsNotifications(notificationDelegate: notificationDelegate)
        
        // Notification received from the network fetch manager
        
        notificationCenterTokens.append(contentsOf: [
            ObvNetworkFetchNotificationNew.observeNewAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity(within: notificationDelegate) { [weak self] (ownedIdentity, apiKeyStatus, apiPermissions, apiKeyExpirationDate) in
                self?.processNewAPIKeyElementsForCurrentAPIKeyOfOwnedIdentityNotification(ownedIdentity: ownedIdentity, apiKeyStatus: apiKeyStatus, apiPermissions: apiPermissions, apiKeyExpirationDate: apiKeyExpirationDate)
            },
            ObvNetworkFetchNotificationNew.observeDownloadingMessageExtendedPayloadWasPerformed(within: notificationDelegate) { [weak self] (message, flowId) in
                self?.processDownloadingMessageExtendedPayloadWasPerformed(message: message, flowId: flowId)
            },
            ObvNetworkFetchNotificationNew.observeWellKnownHasBeenUpdated(within: notificationDelegate) { [weak self] (serverURL, appInfo, flowId) in
                guard let appNotificationCenter = self?.appNotificationCenter else { return }
                let notification = ObvEngineNotificationNew.wellKnownUpdatedSuccess(serverURL: serverURL, appInfo: appInfo)
                notification.postOnBackgroundQueue(within: appNotificationCenter)
            },
            ObvNetworkFetchNotificationNew.observeWellKnownHasBeenDownloaded(within: notificationDelegate) { [weak self] (serverURL, appInfo, flowId) in
                guard let appNotificationCenter = self?.appNotificationCenter else { return }
                let notification = ObvEngineNotificationNew.wellKnownDownloadedSuccess(serverURL: serverURL, appInfo: appInfo)
                notification.postOnBackgroundQueue(within: appNotificationCenter)
            },
            ObvNetworkFetchNotificationNew.observeWellKnownDownloadFailure(within: notificationDelegate) { [weak self] (serverURL, flowId) in
                guard let appNotificationCenter = self?.appNotificationCenter else { return }
                let notification = ObvEngineNotificationNew.wellKnownDownloadedFailure(serverURL: serverURL)
                notification.postOnBackgroundQueue(within: appNotificationCenter)
            },
            ObvNetworkFetchNotificationNew.observeCannotReturnAnyProgressForMessageAttachments(within: notificationDelegate) { [weak self] (messageId, flowId) in
                self?.processCannotReturnAnyProgressForMessageAttachmentsNotification(messageId: messageId, flowId: flowId)
            },
            ObvNetworkFetchNotificationNew.observeInboxAttachmentDownloadCancelledByServer(within: notificationDelegate) { [weak self] (attachmentId, flowId) in
                self?.processInboxAttachmentDownloadCancelledByServer(attachmentId: attachmentId, flowId: flowId)
            },
            ObvNetworkFetchNotificationNew.observeApplicationMessagesDecrypted(within: notificationDelegate) { [weak self] (obvMessageOrObvOwnedMessages, flowId) in
                self?.processMessageDecryptedNotification(obvMessageOrObvOwnedMessages: obvMessageOrObvOwnedMessages, flowId: flowId)
            },
            ObvNetworkFetchNotificationNew.observeInboxAttachmentWasDownloaded(within: notificationDelegate) { [weak self] (attachmentId, flowId) in
                self?.processAttachmentDownloadedNotification(attachmentId: attachmentId, flowId: flowId)
            },
            ObvNetworkFetchNotificationNew.observeInboxAttachmentDownloadWasResumed(within: notificationDelegate) { [weak self] (attachmentId, flowId) in
                self?.processInboxAttachmentDownloadWasResumed(attachmentId: attachmentId, flowId: flowId)
            },
            ObvNetworkFetchNotificationNew.observeInboxAttachmentDownloadWasPaused(within: notificationDelegate) { [weak self] (attachmentId, flowId) in
                self?.processInboxAttachmentDownloadWasPaused(attachmentId: attachmentId, flowId: flowId)
            },
            ObvNetworkFetchNotificationNew.observePushTopicReceivedViaWebsocket(within: notificationDelegate) { [weak self] pushTopic in
                self?.processPushTopicReceivedViaWebsocket(pushTopic: pushTopic)
            },
            ObvNetworkFetchNotificationNew.observeKeycloakTargetedPushNotificationReceivedViaWebsocket(within: notificationDelegate) { [weak self] ownedIdentity in
                self?.processKeycloakTargetedPushNotificationReceivedViaWebsocket(ownedIdentity: ownedIdentity)
            },
            ObvNetworkFetchNotificationNew.observeOwnedDevicesMessageReceivedViaWebsocket(within: notificationDelegate) { [weak self] ownedCryptoIdentity in
                guard let appNotificationCenter = self?.appNotificationCenter else { return }
                ObvEngineNotificationNew.serverRequiresAllActiveOwnedIdentitiesToRegisterToPushNotifications
                    .postOnBackgroundQueue(within: appNotificationCenter)
            },
            ObvNetworkFetchNotificationNew.observeNewReturnReceiptToProcess(within: notificationDelegate) { [weak self] encryptedReceivedReturnReceipt in
                self?.processNewReturnReceiptToProcessNotification(encryptedReceivedReturnReceipt: encryptedReceivedReturnReceipt)
            },
        ])
    }
    
    
    private func processMutualScanContactAdded(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, signature: Data) {
        
        guard let createContextDelegate = createContextDelegate else {
            os_log("The create context delegate is not set", log: log, type: .fault)
            return
        }
        
        guard let identityDelegate = identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            return
        }

        let log = self.log
        let appNotificationCenter = appNotificationCenter
        
        createContextDelegate.performBackgroundTask(flowId: FlowIdentifier()) { obvContext in
            guard let obvContact = ObvContactIdentity(contactCryptoIdentity: contactIdentity, ownedCryptoIdentity: ownedIdentity, identityDelegate: identityDelegate, within: obvContext) else {
                os_log("Could not get ObvContact", log: log, type: .fault)
                assertionFailure()
                return
            }
            ObvEngineNotificationNew.mutualScanContactAdded(obvContactIdentity: obvContact, signature: signature)
                .postOnBackgroundQueue(within: appNotificationCenter)
        }
        
    }

    
    private func processNewReturnReceiptToProcessNotification(encryptedReceivedReturnReceipt: ObvEncryptedReceivedReturnReceipt) {
        ObvEngineNotificationNew.newObvEncryptedReceivedReturnReceipt(encryptedReceivedReturnReceipt: encryptedReceivedReturnReceipt)
            .postOnBackgroundQueue(queueForPostingNewObvReturnReceiptToProcessNotifications, within: appNotificationCenter)
    }
    

    /// If the protocol performing an owned device discovery reports that the current device is not part of the results returned by the server, we force a registration to push notifications.
    /// If the current device was not part of the discovery because another owned device deactivated it, we will be notified by the server as a result of this re-register to push notifications.
    /// In that case, the registration method will return a ``ObvNetworkFetchError.RegisterPushNotificationError.anotherDeviceIsAlreadyRegistered`` error, and this device will be deactivated.
    private func processTheCurrentDeviceWasNotPartOfTheLastOwnedDeviceDiscoveryResults(ownedCryptoIdentity: ObvCryptoIdentity) {
        let ownedCryptoId = ObvCryptoId(cryptoIdentity: ownedCryptoIdentity)
        ObvEngineNotificationNew.engineRequiresOwnedIdentityToRegisterToPushNotifications(ownedCryptoId: ownedCryptoId, performOwnedDeviceDiscoveryOnFinish: true)
            .postOnBackgroundQueue(queueForPostingNotificationsToTheApp, within: appNotificationCenter)
    }

    
    
    /// This is called when the protocol manager notifies that an ongoing owned identity transfer protocol did fail. In that case, it has been terminated.
    /// Note that, on a target device, the owned identity indicated here is an ephemeral identity.
    private func processAnOwnedIdentityTransferProtocolFailed(ownedCryptoIdentity: ObvCryptoIdentity, protocolInstanceUID: UID, error: Error) {
        let ownedCryptoId = ObvCryptoId(cryptoIdentity: ownedCryptoIdentity)
        ObvEngineNotificationNew.anOwnedIdentityTransferProtocolFailed(ownedCryptoId: ownedCryptoId, protocolInstanceUID: protocolInstanceUID, error: error)
            .postOnBackgroundQueue(queueForPostingNotificationsToTheApp, within: appNotificationCenter)
    }


    private func processDownloadingMessageExtendedPayloadWasPerformed(message: ObvMessageOrObvOwnedMessage, flowId: FlowIdentifier) {
        
        logger.debug("We received a DownloadingMessageExtendedPayloadWasPerformed notification for the message \(message.messageId.debugDescription).")

        ObvEngineNotificationNew.messageExtendedPayloadAvailable(message: message)
            .postOnBackgroundQueue(queueForPostingNotificationsToTheApp, within: appNotificationCenter)

    }
    

    private func processInboxAttachmentDownloadCancelledByServer(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) {
        
        os_log("We received an AttachmentDownloadCancelledByServer notification for the attachment %{public}@.", log: log, type: .debug, attachmentId.debugDescription)
        
        guard let createContextDelegate = createContextDelegate else {
            os_log("The create context delegate is not set", log: log, type: .fault)
            return
        }
        
        guard let networkFetchDelegate = networkFetchDelegate else {
            os_log("The network fetch delegate is not set", log: log, type: .fault)
            return
        }
        
        createContextDelegate.performBackgroundTask(flowId: flowId) { [weak self] (obvContext) in
            
            guard let _self = self else { return }
            
            guard let networkReceivedAttachment = networkFetchDelegate.getAttachment(withId: attachmentId, within: obvContext) else {
                os_log("Could not get a network received attachment of message %{public}@ (4)", log: _self.log, type: .fault, attachmentId.messageId.debugDescription)
                return
            }

            if networkReceivedAttachment.fromCryptoIdentity == networkReceivedAttachment.attachmentId.messageId.ownedCryptoIdentity {
                
                let obvOwnedAttachment: ObvOwnedAttachment
                do {
                    obvOwnedAttachment = try ObvOwnedAttachment(attachmentId: attachmentId, networkFetchDelegate: networkFetchDelegate, within: obvContext)
                } catch {
                    os_log("Could not construct an ObvOwnedAttachment of message %{public}@ (1)", log: _self.log, type: .fault, attachmentId.messageId.debugDescription)
                    return
                }

                // We notify the app
                
                ObvEngineNotificationNew.ownedAttachmentDownloadCancelledByServer(obvOwnedAttachment: obvOwnedAttachment)
                    .postOnBackgroundQueue(within: _self.appNotificationCenter)
                
            } else {
                
                let contactIdentifier = ObvContactIdentifier(contactCryptoIdentity: networkReceivedAttachment.fromCryptoIdentity,
                                                             ownedCryptoIdentity: networkReceivedAttachment.attachmentId.messageId.ownedCryptoIdentity)
                
                let obvAttachment: ObvAttachment
                do {
                    try obvAttachment = ObvAttachment(attachmentId: attachmentId, fromContactIdentity: contactIdentifier, networkFetchDelegate: networkFetchDelegate, within: obvContext)
                } catch {
                    os_log("Could not construct an ObvAttachment of message %{public}@ (4)", log: _self.log, type: .fault, attachmentId.messageId.debugDescription)
                    return
                }
                
                // We notify the app
                
                ObvEngineNotificationNew.attachmentDownloadCancelledByServer(obvAttachment: obvAttachment)
                    .postOnBackgroundQueue(within: _self.appNotificationCenter)

                
            }

        }

    }
    
    
    private func processDeletedConfirmedObliviousChannelNotifications(currentDeviceUid: UID, remoteCryptoIdentity: ObvCryptoIdentity, remoteDeviceUid: UID) {
        os_log("We received a DeletedConfirmedObliviousChannel notification", log: log, type: .info)
        
        guard let createContextDelegate else {
            os_log("The create context delegate is not set", log: log, type: .fault)
            return
        }
        guard let identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            return
        }
        
        let appNotificationCenter = self.appNotificationCenter
        let queueForPostingNotificationsToTheApp = self.queueForPostingNotificationsToTheApp
        
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: randomFlowId) { [weak self] (obvContext) in
            
            guard let _self = self else { return }
            
            // Determine the owned identity related to the current device uid
            
            guard let ownedCryptoIdentity = try? identityDelegate.getOwnedIdentityOfCurrentDeviceUid(currentDeviceUid, within: obvContext) else {
                os_log("The device uid does not correspond to any owned identity. This is ok during a profile deletion.", log: _self.log, type: .error)
                return
            }
                        
            // The remote device might either be :
            // - an owned remote device
            // - a contact device
            // For each case, we have an appropriate notification to send
            
            if ownedCryptoIdentity == remoteCryptoIdentity {
                
                os_log("The deleted channel was one with had with a remote owned device %@", log: _self.log, type: .info, remoteDeviceUid.description)
                
                ObvEngineNotificationNew.deletedObliviousChannelWithRemoteOwnedDevice
                    .postOnBackgroundQueue(queueForPostingNotificationsToTheApp, within: appNotificationCenter)
                
            } else {
                
                os_log("The deleted channel was one we had with a contact device %@", log: _self.log, type: .info, remoteDeviceUid.description)
                
                let contactIdentifier = ObvContactIdentifier(contactCryptoIdentity: remoteCryptoIdentity, ownedCryptoIdentity: ownedCryptoIdentity)
                
                ObvEngineNotificationNew.deletedObliviousChannelWithContactDevice(obvContactIdentifier: contactIdentifier)
                    .postOnBackgroundQueue(queueForPostingNotificationsToTheApp, within: appNotificationCenter)
                
            }

            
        }

        
    }
    

    private func observeNewTrustedContactIdentityDetailsNotifications(notificationDelegate: ObvNotificationDelegate) {
        
        let NotificationType = ObvIdentityNotification.NewTrustedContactIdentityDetails.self
        let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
            guard let _self = self else { return }
            guard let (contactCryptoIdentity, ownedCryptoIdentity, _) = NotificationType.parse(notification) else { return }
            
            guard let createContextDelegate = _self.createContextDelegate else { return }
            guard let identityDelegate = _self.identityDelegate else { return }

            var obvContactIdentity: ObvContactIdentity?
            let randomFlowId = FlowIdentifier()
            createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
                obvContactIdentity = ObvContactIdentity(contactCryptoIdentity: contactCryptoIdentity,
                                                        ownedCryptoIdentity: ownedCryptoIdentity,
                                                        identityDelegate: identityDelegate,
                                                        within: obvContext)
            }
            guard let obvContactIdentity = obvContactIdentity else {
                os_log("Could not get contact identity", log: _self.log, type: .fault)
                return
            }
            
            ObvEngineNotificationNew.updatedContactIdentity(obvContactIdentity: obvContactIdentity, trustedIdentityDetailsWereUpdated: true, publishedIdentityDetailsWereUpdated: false)
                .postOnBackgroundQueue(within: _self.appNotificationCenter)
        }
        notificationCenterTokens.append(token)
    }

    
    private func observeNewPublishedContactIdentityDetailsNotifications(notificationDelegate: ObvNotificationDelegate) {
        
        let NotificationType = ObvIdentityNotification.NewPublishedContactIdentityDetails.self
        let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
            guard let _self = self else { return }
            guard let (contactCryptoIdentity, ownedCryptoIdentity, _) = NotificationType.parse(notification) else { return }
            
            guard let createContextDelegate = _self.createContextDelegate else { return }
            guard let identityDelegate = _self.identityDelegate else { return }
            
            var obvContactIdentity: ObvContactIdentity?
            let randomFlowId = FlowIdentifier()
            createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
                obvContactIdentity = ObvContactIdentity(contactCryptoIdentity: contactCryptoIdentity,
                                                             ownedCryptoIdentity: ownedCryptoIdentity,
                                                             identityDelegate: identityDelegate,
                                                             within: obvContext)
            }
            guard let obvContactIdentity = obvContactIdentity else {
                os_log("Could not get contact identity", log: _self.log, type: .fault)
                return
            }
            ObvEngineNotificationNew.updatedContactIdentity(obvContactIdentity: obvContactIdentity, trustedIdentityDetailsWereUpdated: false, publishedIdentityDetailsWereUpdated: true)
                .postOnBackgroundQueue(within: _self.appNotificationCenter)
        }
        notificationCenterTokens.append(token)
    }

    
    private func processOwnedIdentityKeycloakServerChanged(ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {

        guard let identityDelegate = self.identityDelegate else { assertionFailure(); return }
        guard let createContextDelegate = self.createContextDelegate else { assertionFailure(); return }
        let appNotificationCenter = self.appNotificationCenter
        
        createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
            
            guard let obvOwnedIdentity = ObvOwnedIdentity(ownedCryptoIdentity: ownedCryptoIdentity, identityDelegate: identityDelegate, within: obvContext) else {
                assertionFailure()
                return
            }

            ObvEngineNotificationNew.updatedOwnedIdentity(obvOwnedIdentity: obvOwnedIdentity)
                .postOnBackgroundQueue(within: appNotificationCenter)

        }
        
    }
    
    
    private func processContactIsActiveChanged(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, isActive: Bool, flowId: FlowIdentifier) {
        
        guard let identityDelegate = self.identityDelegate else { assertionFailure(); return }
        guard let createContextDelegate = self.createContextDelegate else { assertionFailure(); return }
        let appNotificationCenter = self.appNotificationCenter
        
        createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
            
            guard let obvContactIdentity = ObvContactIdentity(contactCryptoIdentity: contactIdentity,
                                                              ownedCryptoIdentity: ownedIdentity,
                                                              identityDelegate: identityDelegate, within: obvContext) else {
                os_log("Could not create an ObvContactIdentity structure", log: self.log, type: .fault)
                assertionFailure()
                return
            }

            ObvEngineNotificationNew.contactIsActiveChangedWithinEngine(obvContactIdentity: obvContactIdentity)
                .postOnBackgroundQueue(within: appNotificationCenter)

        }

    }
    
    
    private func processContactWasRevokedAsCompromised(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
     
        let appNotificationCenter = self.appNotificationCenter
        
        let obvContactIdentifier = ObvContactIdentifier(contactCryptoIdentity: contactIdentity, ownedCryptoIdentity: ownedIdentity)
        
        ObvEngineNotificationNew.contactWasRevokedAsCompromisedWithinEngine(obvContactIdentifier: obvContactIdentifier)
            .postOnBackgroundQueue(within: appNotificationCenter)

    }
    
    
    private func processOwnedIdentityCapabilitiesWereUpdated(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        
        guard let identityDelegate = self.identityDelegate else { assertionFailure(); return }
        guard let createContextDelegate = self.createContextDelegate else { assertionFailure(); return }
        let appNotificationCenter = self.appNotificationCenter

        createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
            
            guard let obvOwnedIdentity = ObvOwnedIdentity(ownedCryptoIdentity: ownedIdentity, identityDelegate: identityDelegate, within: obvContext) else {
                os_log("Could not create an ObvOwnedIdentity structure", log: self.log, type: .fault)
                assertionFailure()
                return
            }
            
            ObvEngineNotificationNew.OwnedIdentityCapabilitiesWereUpdated(ownedIdentity: obvOwnedIdentity)
                .postOnBackgroundQueue(within: appNotificationCenter)

        }

    }
    
    
    private func processGroupV2WasCreated(obvGroupV2: ObvGroupV2, initiator: ObvGroupV2.CreationOrUpdateInitiator) {
        ObvEngineNotificationNew.groupV2WasCreatedOrUpdated(obvGroupV2: obvGroupV2, initiator: initiator)
            .postOnBackgroundQueue(queueForPostingNotificationsToTheApp, within: appNotificationCenter)
    }

    
    private func processGroupV2WasUpdated(obvGroupV2: ObvGroupV2, initiator: ObvGroupV2.CreationOrUpdateInitiator) {
        ObvEngineNotificationNew.groupV2WasCreatedOrUpdated(obvGroupV2: obvGroupV2, initiator: initiator)
            .postOnBackgroundQueue(queueForPostingNotificationsToTheApp, within: appNotificationCenter)
    }
    
    
    private func processGroupV2WasDeleted(ownedIdentity: ObvCryptoIdentity, appGroupIdentifier: Data) {
        ObvEngineNotificationNew.groupV2WasDeleted(ownedIdentity: ObvCryptoId(cryptoIdentity: ownedIdentity), appGroupIdentifier: appGroupIdentifier)
            .postOnBackgroundQueue(queueForPostingNotificationsToTheApp, within: appNotificationCenter)
    }

    
    private func processGroupV2UpdateDidFail(ownedIdentity: ObvCryptoIdentity, appGroupIdentifier: Data, flowId: FlowIdentifier) {
        ObvEngineNotificationNew.groupV2UpdateDidFail(ownedIdentity: ObvCryptoId(cryptoIdentity: ownedIdentity), appGroupIdentifier: appGroupIdentifier)
            .postOnBackgroundQueue(queueForPostingNotificationsToTheApp, within: appNotificationCenter)
    }
    
    
    private func processContactIntroductionInvitationSent(ownedIdentity: ObvCryptoIdentity, contactIdentityA: ObvCryptoIdentity, contactIdentityB: ObvCryptoIdentity) {
        ObvEngineNotificationNew.contactIntroductionInvitationSent(
            ownedIdentity: ObvCryptoId(cryptoIdentity: ownedIdentity),
            contactIdentityA: ObvCryptoId(cryptoIdentity: contactIdentityA),
            contactIdentityB: ObvCryptoId(cryptoIdentity: contactIdentityB))
        .postOnBackgroundQueue(queueForPostingNotificationsToTheApp, within: appNotificationCenter)
    }

    
    func notifyAppThatOwnedIdentityWasDeleted() {
        ObvEngineNotificationNew.ownedIdentityWasDeleted
            .postOnBackgroundQueue(queueForPostingNotificationsToTheApp, within: appNotificationCenter)
    }

    
    /// When a new owned remote device is inserted in database, we notify the app, to make it possible to immediately see this device in the list of owned devices.
    /// See also ``EngineCoordinator.processNewRemoteOwnedDevice(ownedCryptoId:remoteDeviceUid:)`` where we launch a channel creation.
    private func processNewRemoteOwnedDevice(ownedCryptoId: ObvCryptoIdentity, remoteDeviceUid: UID) {
        ObvEngineNotificationNew.newRemoteOwnedDevice
            .postOnBackgroundQueue(queueForPostingNotificationsToTheApp, within: appNotificationCenter)
    }
    
    
    private func processAnOwnedDeviceWasUpdated(ownedCryptoId: ObvCryptoIdentity) {
        ObvEngineNotificationNew.anOwnedDeviceWasUpdated(ownedCryptoId: ObvCryptoId(cryptoIdentity: ownedCryptoId))
            .postOnBackgroundQueue(queueForPostingNotificationsToTheApp, within: appNotificationCenter)
    }

    
    private func processAnOwnedDeviceWasDeleted(ownedCryptoId: ObvCryptoIdentity) {
        ObvEngineNotificationNew.anOwnedDeviceWasDeleted(ownedCryptoId: ObvCryptoId(cryptoIdentity: ownedCryptoId))
            .postOnBackgroundQueue(queueForPostingNotificationsToTheApp, within: appNotificationCenter)
    }
    
    
    private func processNewContactDevice(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity) {
        let obvContactIdentifier = ObvContactIdentifier(contactCryptoIdentity: contactIdentity, ownedCryptoIdentity: ownedIdentity)
        ObvEngineNotificationNew.newContactDevice(obvContactIdentifier: obvContactIdentifier)
            .postOnBackgroundQueue(queueForPostingNotificationsToTheApp, within: appNotificationCenter)
    }
    
    
    /// When a the push topic of a keycloak group is created/updated, we want to re-register to push notification to make sure we inform the server we are interested by this new push topic.
    private func processPushTopicOfKeycloakGroupWasUpdated(ownedIdentity: ObvCryptoIdentity) {
        let ownedCryptoId = ObvCryptoId(cryptoIdentity: ownedIdentity)
        ObvEngineNotificationNew.engineRequiresOwnedIdentityToRegisterToPushNotifications(ownedCryptoId: ownedCryptoId, performOwnedDeviceDiscoveryOnFinish: false)
            .postOnBackgroundQueue(queueForPostingNotificationsToTheApp, within: appNotificationCenter)
    }

    
    private func processKeycloakSynchronizationRequired(ownedIdentity: ObvCryptoIdentity) {
        ObvEngineNotificationNew.keycloakSynchronizationRequired(ownCryptoId: ObvCryptoId(cryptoIdentity: ownedIdentity))
            .postOnBackgroundQueue(queueForPostingNotificationsToTheApp, within: appNotificationCenter)
    }

    
    private func processContactObvCapabilitiesWereUpdated(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        
        guard let identityDelegate = self.identityDelegate else { assertionFailure(); return }
        guard let createContextDelegate = self.createContextDelegate else { assertionFailure(); return }
        let appNotificationCenter = self.appNotificationCenter

        createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
            
            guard let obvContactIdentity = ObvContactIdentity(contactCryptoIdentity: contactIdentity,
                                                              ownedCryptoIdentity: ownedIdentity,
                                                              identityDelegate: identityDelegate, within: obvContext) else {
                os_log("Could not create an ObvContactIdentity structure", log: self.log, type: .fault)
                assertionFailure()
                return
            }

            ObvEngineNotificationNew.ContactObvCapabilitiesWereUpdated(contact: obvContactIdentity)
                .postOnBackgroundQueue(within: appNotificationCenter)

        }

        
    }
    
    
    private func processUpdatedContactDevice(deviceIdentifier: ObvContactDeviceIdentifier, flowId: FlowIdentifier) {
        ObvEngineNotificationNew.updatedContactDevice(deviceIdentifier: deviceIdentifier)
            .postOnBackgroundQueue(within: appNotificationCenter)
    }

    
    private func processContactWasUpdatedWithinTheIdentityManager(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        
        guard let identityDelegate = self.identityDelegate else { assertionFailure(); return }
        guard let createContextDelegate = self.createContextDelegate else { assertionFailure(); return }
        let appNotificationCenter = self.appNotificationCenter
        
        createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
            
            guard let obvContactIdentity = ObvContactIdentity(contactCryptoIdentity: contactIdentity,
                                                              ownedCryptoIdentity: ownedIdentity,
                                                              identityDelegate: identityDelegate, within: obvContext) else {
                os_log("Could not create an ObvContactIdentity structure", log: self.log, type: .fault)
                assertionFailure()
                return
            }

            ObvEngineNotificationNew.updatedContactIdentity(obvContactIdentity: obvContactIdentity, trustedIdentityDetailsWereUpdated: false, publishedIdentityDetailsWereUpdated: false)
                .postOnBackgroundQueue(within: appNotificationCenter)

        }

    }


    private func observeOwnedIdentityDetailsPublicationInProgressNotifications(notificationDelegate: ObvNotificationDelegate) {
        let NotificationType = ObvIdentityNotification.OwnedIdentityDetailsPublicationInProgress.self
        let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
            guard let _self = self else { return }
            guard let ownedCryptoIdentity = NotificationType.parse(notification) else { return }
            
            guard let createContextDelegate = _self.createContextDelegate else { return }
            guard let identityDelegate = _self.identityDelegate else { return }
            
            var obvOwnedIdentity: ObvOwnedIdentity?
            let randomFlowId = FlowIdentifier()
            createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
                obvOwnedIdentity = ObvOwnedIdentity(ownedCryptoIdentity: ownedCryptoIdentity,
                                                    identityDelegate: identityDelegate, within: obvContext)
            }
            guard let obvOwnedIdentity = obvOwnedIdentity else {
                os_log("Could not get owned identity", log: _self.log, type: .fault)
                return
            }

            ObvEngineNotificationNew.updatedOwnedIdentity(obvOwnedIdentity: obvOwnedIdentity)
                .postOnBackgroundQueue(within: _self.appNotificationCenter)

        }
        notificationCenterTokens.append(token)
        
    }

    
    private func processOutboxMessagesAndAllTheirAttachmentsWereAcknowledgedNotifications(messageIdsAndTimestampsFromServer: [(messageId: ObvMessageIdentifier, timestampFromServer: Date)], flowId: FlowIdentifier) {
        os_log("We received an OutboxMessagesAndAllTheirAttachmentsWereAcknowledged notification within flow %{public}@", log: log, type: .debug, flowId.debugDescription)
        let info = messageIdsAndTimestampsFromServer.map() { ($0.messageId.uid.raw, ObvCryptoId(cryptoIdentity: $0.messageId.ownedCryptoIdentity), $0.timestampFromServer) }
        ObvEngineNotificationNew.outboxMessagesAndAllTheirAttachmentsWereAcknowledged(messageIdsAndTimestampsFromServer: info)
            .postOnBackgroundQueue(within: appNotificationCenter)
    }
    
    private func processOutboxMessageCouldNotBeSentToServer(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) {
        let messageIdentifierFromEngine = messageId.uid.raw
        let ownedIdentity = ObvCryptoId(cryptoIdentity: messageId.ownedCryptoIdentity)
        ObvEngineNotificationNew.outboxMessageCouldNotBeSentToServer(messageIdentifierFromEngine: messageIdentifierFromEngine, ownedIdentity: ownedIdentity)
            .postOnBackgroundQueue(within: appNotificationCenter)
    }
    
    private func processNewAPIKeyElementsForCurrentAPIKeyOfOwnedIdentityNotification(ownedIdentity: ObvCryptoIdentity, apiKeyStatus: APIKeyStatus, apiPermissions: APIPermissions, apiKeyExpirationDate: Date?) {
        let ownedIdentity = ObvCryptoId(cryptoIdentity: ownedIdentity)
        ObvEngineNotificationNew.newAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity(ownedIdentity: ownedIdentity, apiKeyStatus: apiKeyStatus, apiPermissions: apiPermissions, apiKeyExpirationDate: apiKeyExpirationDate)
            .postOnBackgroundQueue(within: appNotificationCenter)
    }
    
    private func processCannotReturnAnyProgressForMessageAttachmentsNotification(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) {
        let ownedCryptoId = ObvCryptoId(cryptoIdentity: messageId.ownedCryptoIdentity)
        ObvEngineNotificationNew.cannotReturnAnyProgressForMessageAttachments(ownedCryptoId: ownedCryptoId, messageIdentifierFromEngine: messageId.uid.raw)
            .postOnBackgroundQueue(within: appNotificationCenter)
    }

    
    private func processOutboxMessageWasUploadedNotification(messageId: ObvMessageIdentifier, timestampFromServer: Date, isAppMessageWithUserContent: Bool, isVoipMessage: Bool, flowId: FlowIdentifier) {
        
        os_log("We received an OutboxMessageWasUploaded notification within flow %{public}@", log: log, type: .debug, flowId.debugDescription)
        
        let ownedIdentity = ObvCryptoId(cryptoIdentity: messageId.ownedCryptoIdentity)
        ObvEngineNotificationNew.messageWasAcknowledged(ownedIdentity: ownedIdentity,
                                                        messageIdentifierFromEngine: messageId.uid.raw,
                                                        timestampFromServer: timestampFromServer,
                                                        isAppMessageWithUserContent: isAppMessageWithUserContent,
                                                        isVoipMessage: isVoipMessage)
            .postOnBackgroundQueue(within: appNotificationCenter)

    }
    
    private func processAttachmentWasAcknowledgedNotification(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) {
        
        os_log("We received an AttachmentWasAcknowledged notification within flow %{public}@", log: log, type: .debug, flowId.debugDescription)
        
        ObvEngineNotificationNew.attachmentWasAcknowledgedByServer(ownedCryptoId: ObvCryptoId(cryptoIdentity: attachmentId.messageId.ownedCryptoIdentity), messageIdentifierFromEngine: attachmentId.messageId.uid.raw, attachmentNumber: attachmentId.attachmentNumber)
            .postOnBackgroundQueue(within: appNotificationCenter)

    }
    
    private func registerToContactWasDeletedNotifications(notificationDelegate: ObvNotificationDelegate) {
        let log = self.log
        let token = ObvIdentityNotificationNew.observeContactWasDeleted(within: notificationDelegate) { [weak self] (ownedCryptoIdentity, contactCryptoIdentity) in
            
            guard let _self = self else { return }
            
            os_log("We received an ContactWasDeleted notification for the contact %@ of the ownedIdentity %@", log: log, type: .info, contactCryptoIdentity.debugDescription, ownedCryptoIdentity.debugDescription)
                        
            ObvEngineNotificationNew.contactWasDeleted(
                ownedCryptoId: ObvCryptoId(cryptoIdentity: ownedCryptoIdentity),
                contactCryptoId: ObvCryptoId(cryptoIdentity: contactCryptoIdentity))
                .postOnBackgroundQueue(within: _self.appNotificationCenter)

        }        
        notificationCenterTokens.append(token)
    }
    
    
    private func processNewContactGroupJoinedNotification(groupUid: UID, groupOwner: ObvCryptoIdentity, ownedIdentity: ObvCryptoIdentity) {

        guard let createContextDelegate = createContextDelegate else {
            os_log("The create context delegate is not set", log: log, type: .fault)
            return
        }
        
        guard let identityDelegate = identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            return
        }

        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: randomFlowId) { [weak self] (obvContext) in
            guard let _self = self else { return }
            
            guard let groupStructure = try? identityDelegate.getGroupJoinedStructure(ownedIdentity: ownedIdentity, groupUid: groupUid, groupOwner: groupOwner, within: obvContext) else {
                os_log("Could not get group structure", log: _self.log, type: .fault)
                return
            }
            
            guard let obvContactGroup = ObvContactGroup(groupStructure: groupStructure, identityDelegate: identityDelegate, within: obvContext) else {
                os_log("Could not create an ObvContactGroup structure", log: _self.log, type: .fault)
                return
            }
            
            ObvEngineNotificationNew.newContactGroup(obvContactGroup: obvContactGroup)
                .postOnBackgroundQueue(_self.queueForPostingNotificationsToTheApp, within: _self.appNotificationCenter)
            
        }
        
    }

    
    private func processNewContactGroupOwnedNotification(groupUid: UID, ownedIdentity: ObvCryptoIdentity) {
        
        guard let createContextDelegate = createContextDelegate else {
            os_log("The create context delegate is not set", log: log, type: .fault)
            return
        }
        
        guard let identityDelegate = identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            return
        }
        
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: randomFlowId) { [weak self] (obvContext) in
            guard let _self = self else { return }
            
            guard let groupStructure = try? identityDelegate.getGroupOwnedStructure(ownedIdentity: ownedIdentity, groupUid: groupUid, within: obvContext) else {
                os_log("Could not get group structure", log: _self.log, type: .fault)
                return
            }
            
            guard let obvContactGroup = ObvContactGroup(groupStructure: groupStructure, identityDelegate: identityDelegate, within: obvContext) else {
                os_log("Could not create an ObvContactGroup structure", log: _self.log, type: .fault)
                return
            }
            
            ObvEngineNotificationNew.newContactGroup(obvContactGroup: obvContactGroup)
                .postOnBackgroundQueue(_self.queueForPostingNotificationsToTheApp, within: _self.appNotificationCenter)

        }
        
    }

    
    private func processContactGroupOwnedHasUpdatedPendingMembersAndGroupMembersNotification(groupUid: UID, ownedIdentity: ObvCryptoIdentity) {
        
        guard let createContextDelegate = createContextDelegate else {
            os_log("The create context delegate is not set", log: log, type: .fault)
            return
        }
        
        guard let identityDelegate = identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            return
        }

        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: randomFlowId) { [weak self] (obvContext) in
            guard let _self = self else { return }
            
            guard let groupStructure = try? identityDelegate.getGroupOwnedStructure(ownedIdentity: ownedIdentity, groupUid: groupUid, within: obvContext) else {
                os_log("Could not get group structure", log: _self.log, type: .fault)
                return
            }
            
            guard let obvContactGroup = ObvContactGroup(groupStructure: groupStructure, identityDelegate: identityDelegate, within: obvContext) else {
                os_log("Could not create an ObvContactGroup structure", log: _self.log, type: .fault)
                return
            }
            
            ObvEngineNotificationNew.contactGroupHasUpdatedPendingMembersAndGroupMembers(obvContactGroup: obvContactGroup)
                .postOnBackgroundQueue(_self.queueForPostingNotificationsToTheApp, within: _self.appNotificationCenter)

        }
        
    }
    
    
    private func processContactGroupJoinedHasUpdatedPendingMembersAndGroupMembersNotification(groupUid: UID, groupOwner: ObvCryptoIdentity, ownedIdentity: ObvCryptoIdentity) {
        
        guard let createContextDelegate = createContextDelegate else {
            os_log("The create context delegate is not set", log: log, type: .fault)
            return
        }
        
        guard let identityDelegate = identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            return
        }
        
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: randomFlowId) { [weak self] (obvContext) in
            guard let _self = self else { return }
            
            guard let groupStructure = try? identityDelegate.getGroupJoinedStructure(ownedIdentity: ownedIdentity, groupUid: groupUid, groupOwner: groupOwner, within: obvContext) else {
                os_log("Could not get group structure", log: _self.log, type: .fault)
                return
            }
            
            guard let obvContactGroup = ObvContactGroup(groupStructure: groupStructure, identityDelegate: identityDelegate, within: obvContext) else {
                os_log("Could not create an ObvContactGroup structure", log: _self.log, type: .fault)
                return
            }
            
            ObvEngineNotificationNew.contactGroupHasUpdatedPendingMembersAndGroupMembers(obvContactGroup: obvContactGroup)
                .postOnBackgroundQueue(_self.queueForPostingNotificationsToTheApp, within: _self.appNotificationCenter)

        }
        
    }

    
    private func processContactGroupOwnedHasUpdatedPublishedDetailsNotification(groupUid: UID, ownedIdentity: ObvCryptoIdentity) {
        
        guard let createContextDelegate = createContextDelegate else {
            os_log("The create context delegate is not set", log: log, type: .fault)
            return
        }
        
        guard let identityDelegate = identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            return
        }
        
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: randomFlowId) { [weak self] (obvContext) in
            guard let _self = self else { return }

            guard let groupStructure = try? identityDelegate.getGroupOwnedStructure(ownedIdentity: ownedIdentity, groupUid: groupUid, within: obvContext) else {
                os_log("Could not get group structure", log: _self.log, type: .fault)
                return
            }
            
            guard let obvContactGroup = ObvContactGroup(groupStructure: groupStructure, identityDelegate: identityDelegate, within: obvContext) else {
                os_log("Could not create an ObvContactGroup structure", log: _self.log, type: .fault)
                return
            }

            ObvEngineNotificationNew.contactGroupHasUpdatedPublishedDetails(obvContactGroup: obvContactGroup)
                .postOnBackgroundQueue(_self.queueForPostingNotificationsToTheApp, within: _self.appNotificationCenter)

        }
    }
    
    
    private func processContactGroupJoinedHasUpdatedPublishedDetailsNotification(groupUid: UID, groupOwner: ObvCryptoIdentity, ownedIdentity: ObvCryptoIdentity) {
        
        guard let createContextDelegate = createContextDelegate else {
            os_log("The create context delegate is not set", log: log, type: .fault)
            return
        }
        
        guard let identityDelegate = identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            return
        }
        
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: randomFlowId) { [weak self] (obvContext) in
            guard let _self = self else { return }
            
            guard let groupStructure = try? identityDelegate.getGroupJoinedStructure(ownedIdentity: ownedIdentity, groupUid: groupUid, groupOwner: groupOwner, within: obvContext) else {
                os_log("Could not get group structure", log: _self.log, type: .fault)
                return
            }
            
            guard let obvContactGroup = ObvContactGroup(groupStructure: groupStructure, identityDelegate: identityDelegate, within: obvContext) else {
                os_log("Could not create an ObvContactGroup structure", log: _self.log, type: .fault)
                return
            }
            
            ObvEngineNotificationNew.contactGroupHasUpdatedPublishedDetails(obvContactGroup: obvContactGroup)
                .postOnBackgroundQueue(_self.queueForPostingNotificationsToTheApp, within: _self.appNotificationCenter)
        }
    }


    private func processTrustedPhotoOfContactIdentityHasBeenUpdated(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity) {
        guard let createContextDelegate = self.createContextDelegate else { assertionFailure(); return }
        guard let identityDelegate = self.identityDelegate else { assertionFailure(); return }
        let appNotificationCenter = self.appNotificationCenter
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: randomFlowId) { (obvContext) in
            guard let obvContactIdentity = ObvContactIdentity(contactCryptoIdentity: contactIdentity,
                                                              ownedCryptoIdentity: ownedIdentity,
                                                              identityDelegate: identityDelegate, within: obvContext) else {
                os_log("Could not create an ObvContactIdentity structure", log: self.log, type: .fault)
                assertionFailure()
                return
            }
            ObvEngineNotificationNew.trustedPhotoOfContactIdentityHasBeenUpdated(contactIdentity: obvContactIdentity)
                .postOnBackgroundQueue(within: appNotificationCenter)
        }
    }

    
    private func processPublishedPhotoOfContactIdentityHasBeenUpdated(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity) {
        guard let createContextDelegate = self.createContextDelegate else { assertionFailure(); return }
        guard let identityDelegate = self.identityDelegate else { assertionFailure(); return }
        let appNotificationCenter = self.appNotificationCenter
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: randomFlowId) { (obvContext) in
            guard let obvContactIdentity = ObvContactIdentity(contactCryptoIdentity: contactIdentity,
                                                              ownedCryptoIdentity: ownedIdentity,
                                                              identityDelegate: identityDelegate, within: obvContext) else {
                os_log("Could not create an ObvContactIdentity structure", log: self.log, type: .fault)
                assertionFailure()
                return
            }
            ObvEngineNotificationNew.publishedPhotoOfContactIdentityHasBeenUpdated(contactIdentity: obvContactIdentity)
                .postOnBackgroundQueue(within: appNotificationCenter)
        }
    }

    
    private func processPublishedPhotoOfOwnedIdentityHasBeenUpdated(ownedIdentity: ObvCryptoIdentity) {
        guard let createContextDelegate = self.createContextDelegate else { assertionFailure(); return }
        guard let identityDelegate = self.identityDelegate else { assertionFailure(); return }
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { [weak self] (obvContext) in
            guard let _self = self else { return }
            guard let obvOwnedIdentity = ObvOwnedIdentity(ownedCryptoIdentity: ownedIdentity,
                                                          identityDelegate: identityDelegate, within: obvContext) else {
                os_log("Could not create an ObvOwnedIdentity structure", log: _self.log, type: .fault)
                return
            }
            ObvEngineNotificationNew.publishedPhotoOfOwnedIdentityHasBeenUpdated(ownedIdentity: obvOwnedIdentity)
                .postOnBackgroundQueue(_self.queueForPostingNotificationsToTheApp, within: _self.appNotificationCenter)
        }
    }

    
    private func processTrustedPhotoOfContactGroupJoinedHasBeenUpdated(groupUid: UID, ownedIdentity: ObvCryptoIdentity, groupOwner: ObvCryptoIdentity) {
        guard let createContextDelegate = self.createContextDelegate else { assertionFailure(); return }
        guard let identityDelegate = self.identityDelegate else { assertionFailure(); return }
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: randomFlowId) { [weak self] (obvContext) in
            guard let _self = self else { return }
            guard let groupStructure = try? identityDelegate.getGroupJoinedStructure(ownedIdentity: ownedIdentity, groupUid: groupUid, groupOwner: groupOwner, within: obvContext) else {
                os_log("Could not get group structure", log: _self.log, type: .fault)
                return
            }
            guard let obvContactGroup = ObvContactGroup(groupStructure: groupStructure, identityDelegate: identityDelegate, within: obvContext) else {
                os_log("Could not create an ObvContactGroup structure", log: _self.log, type: .fault)
                return
            }
            ObvEngineNotificationNew.trustedPhotoOfContactGroupJoinedHasBeenUpdated(group: obvContactGroup)
                .postOnBackgroundQueue(within: _self.appNotificationCenter)
        }
    }

    
    private func processPublishedPhotoOfContactGroupJoinedHasBeenUpdated(groupUid: UID, ownedIdentity: ObvCryptoIdentity, groupOwner: ObvCryptoIdentity) {
        guard let createContextDelegate = self.createContextDelegate else { assertionFailure(); return }
        guard let identityDelegate = self.identityDelegate else { assertionFailure(); return }
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: randomFlowId) { [weak self] (obvContext) in
            guard let _self = self else { return }
            guard let groupStructure = try? identityDelegate.getGroupJoinedStructure(ownedIdentity: ownedIdentity, groupUid: groupUid, groupOwner: groupOwner, within: obvContext) else {
                os_log("Could not get group structure", log: _self.log, type: .fault)
                return
            }
            guard let obvContactGroup = ObvContactGroup(groupStructure: groupStructure, identityDelegate: identityDelegate, within: obvContext) else {
                os_log("Could not create an ObvContactGroup structure", log: _self.log, type: .fault)
                return
            }
            ObvEngineNotificationNew.publishedPhotoOfContactGroupJoinedHasBeenUpdated(group: obvContactGroup)
                .postOnBackgroundQueue(within: _self.appNotificationCenter)
        }
    }

    
    private func processPublishedPhotoOfContactGroupOwnedHasBeenUpdated(groupUid: UID, ownedIdentity: ObvCryptoIdentity) {
        guard let createContextDelegate = self.createContextDelegate else { assertionFailure(); return }
        guard let identityDelegate = self.identityDelegate else { assertionFailure(); return }
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: randomFlowId) { [weak self] (obvContext) in
            guard let _self = self else { return }
            guard let groupStructure = try? identityDelegate.getGroupOwnedStructure(ownedIdentity: ownedIdentity, groupUid: groupUid, within: obvContext) else {
                os_log("Could not get group structure", log: _self.log, type: .fault)
                return
            }
            guard let obvContactGroup = ObvContactGroup(groupStructure: groupStructure, identityDelegate: identityDelegate, within: obvContext) else {
                os_log("Could not create an ObvContactGroup structure", log: _self.log, type: .fault)
                return
            }
            ObvEngineNotificationNew.publishedPhotoOfContactGroupOwnedHasBeenUpdated(group: obvContactGroup)
                .postOnBackgroundQueue(within: _self.appNotificationCenter)
        }
    }

    
    private func processLatestPhotoOfContactGroupOwnedHasBeenUpdated(groupUid: UID, ownedIdentity: ObvCryptoIdentity) {
        guard let createContextDelegate = self.createContextDelegate else { assertionFailure(); return }
        guard let identityDelegate = self.identityDelegate else { assertionFailure(); return }
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: randomFlowId) { [weak self] (obvContext) in
            guard let _self = self else { return }
            guard let groupStructure = try? identityDelegate.getGroupOwnedStructure(ownedIdentity: ownedIdentity, groupUid: groupUid, within: obvContext) else {
                os_log("Could not get group structure", log: _self.log, type: .fault)
                return
            }
            guard let obvContactGroup = ObvContactGroup(groupStructure: groupStructure, identityDelegate: identityDelegate, within: obvContext) else {
                os_log("Could not create an ObvContactGroup structure", log: _self.log, type: .fault)
                return
            }
            ObvEngineNotificationNew.latestPhotoOfContactGroupOwnedHasBeenUpdated(group: obvContactGroup)
                .postOnBackgroundQueue(within: _self.appNotificationCenter)
        }
    }
    
    
    private func processContactGroupDeletedNotification(groupUid: UID, groupOwner: ObvCryptoIdentity, ownedIdentity: ObvCryptoIdentity) {
        
        guard let createContextDelegate = createContextDelegate else {
            os_log("The create context delegate is not set", log: log, type: .fault)
            return
        }
        
        guard let identityDelegate = identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            return
        }
        
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: randomFlowId) { [weak self] (obvContext) in
            guard let _self = self else { return }

            guard let obvOwnedIdentity = ObvOwnedIdentity(ownedCryptoIdentity: ownedIdentity, identityDelegate: identityDelegate, within: obvContext) else {
                os_log("Could not find owned identity", log: _self.log, type: .error)
                return
            }
            
            ObvEngineNotificationNew.contactGroupDeleted(ownedIdentity: obvOwnedIdentity, groupOwner: ObvCryptoId(cryptoIdentity: groupOwner), groupUid: groupUid)
                .postOnBackgroundQueue(_self.queueForPostingNotificationsToTheApp, within: _self.appNotificationCenter)

        }
        
    }
    
    private func processContactGroupOwnedHasUpdatedLatestDetailsNotification(groupUid: UID, ownedIdentity: ObvCryptoIdentity) {
        
        guard let createContextDelegate = createContextDelegate else {
            os_log("The create context delegate is not set", log: log, type: .fault)
            return
        }
        
        guard let identityDelegate = identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            return
        }
        
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: randomFlowId) { [weak self] (obvContext) in
            guard let _self = self else { return }
            
            guard let groupStructure = try? identityDelegate.getGroupOwnedStructure(ownedIdentity: ownedIdentity, groupUid: groupUid, within: obvContext) else {
                os_log("Could not get group structure", log: _self.log, type: .fault)
                return
            }
            
            guard let obvContactGroup = ObvContactGroup(groupStructure: groupStructure, identityDelegate: identityDelegate, within: obvContext) else {
                os_log("Could not create an ObvContactGroup structure", log: _self.log, type: .fault)
                return
            }
            
            ObvEngineNotificationNew.contactGroupOwnedHasUpdatedLatestDetails(obvContactGroup: obvContactGroup)
                .postOnBackgroundQueue(_self.queueForPostingNotificationsToTheApp, within: _self.appNotificationCenter)

        }

    }

    
    private func processContactGroupOwnedDiscardedLatestDetailsNotification(groupUid: UID, ownedIdentity: ObvCryptoIdentity) {
        
        guard let createContextDelegate = createContextDelegate else {
            os_log("The create context delegate is not set", log: log, type: .fault)
            return
        }
        
        guard let identityDelegate = identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            return
        }
        
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: randomFlowId) { [weak self] (obvContext) in
            guard let _self = self else { return }
            
            guard let groupStructure = try? identityDelegate.getGroupOwnedStructure(ownedIdentity: ownedIdentity, groupUid: groupUid, within: obvContext) else {
                os_log("Could not get group structure", log: _self.log, type: .fault)
                return
            }
            
            guard let obvContactGroup = ObvContactGroup(groupStructure: groupStructure, identityDelegate: identityDelegate, within: obvContext) else {
                os_log("Could not create an ObvContactGroup structure", log: _self.log, type: .fault)
                return
            }
            
            ObvEngineNotificationNew.contactGroupOwnedDiscardedLatestDetails(obvContactGroup: obvContactGroup)
                .postOnBackgroundQueue(_self.queueForPostingNotificationsToTheApp, within: _self.appNotificationCenter)

        }
        
    }
    
    
    private func processContactGroupJoinedHasUpdatedTrustedDetailsNotification(groupUid: UID, groupOwner: ObvCryptoIdentity, ownedIdentity: ObvCryptoIdentity) {
        
        guard let createContextDelegate = createContextDelegate else {
            os_log("The create context delegate is not set", log: log, type: .fault)
            return
        }
        
        guard let identityDelegate = identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            return
        }
        
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: randomFlowId) { [weak self] (obvContext) in
            guard let _self = self else { return }
            
            guard let groupStructure = try? identityDelegate.getGroupJoinedStructure(ownedIdentity: ownedIdentity, groupUid: groupUid, groupOwner: groupOwner, within: obvContext) else {
                os_log("Could not get group structure", log: _self.log, type: .fault)
                return
            }
            
            guard let obvContactGroup = ObvContactGroup(groupStructure: groupStructure, identityDelegate: identityDelegate, within: obvContext) else {
                os_log("Could not create an ObvContactGroup structure", log: _self.log, type: .fault)
                return
            }
            
            ObvEngineNotificationNew.contactGroupJoinedHasUpdatedTrustedDetails(obvContactGroup: obvContactGroup)
                .postOnBackgroundQueue(_self.queueForPostingNotificationsToTheApp, within: _self.appNotificationCenter)

        }
        
    }
    
    
    private func processPendingGroupMemberDeclinedInvitationToOwnedGroupNotification(groupUid: UID, ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity) {
        
        guard let createContextDelegate = createContextDelegate else {
            os_log("The create context delegate is not set", log: log, type: .fault)
            return
        }
        
        guard let identityDelegate = identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            return
        }
        
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: randomFlowId) { [weak self] (obvContext) in
            guard let _self = self else { return }
            
            guard let groupStructure = try? identityDelegate.getGroupOwnedStructure(ownedIdentity: ownedIdentity, groupUid: groupUid, within: obvContext) else {
                os_log("Could not get group structure", log: _self.log, type: .fault)
                return
            }
            
            guard let obvContactGroup = ObvContactGroup(groupStructure: groupStructure, identityDelegate: identityDelegate, within: obvContext) else {
                os_log("Could not create an ObvContactGroup structure", log: _self.log, type: .fault)
                return
            }
            
            ObvEngineNotificationNew.newPendingGroupMemberDeclinedStatus(obvContactGroup: obvContactGroup)
                .postOnBackgroundQueue(_self.queueForPostingNotificationsToTheApp, within: _self.appNotificationCenter)

        }

        
    }
    
    
    private func processDeclinedPendingGroupMemberWasUndeclinedForOwnedGroupNotification(groupUid: UID, ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity) {
        
        guard let createContextDelegate = createContextDelegate else {
            os_log("The create context delegate is not set", log: log, type: .fault)
            return
        }
        
        guard let identityDelegate = identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            return
        }
        
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: randomFlowId) { [weak self] (obvContext) in
            guard let _self = self else { return }
            
            guard let groupStructure = try? identityDelegate.getGroupOwnedStructure(ownedIdentity: ownedIdentity, groupUid: groupUid, within: obvContext) else {
                os_log("Could not get group structure", log: _self.log, type: .fault)
                return
            }
            
            guard let obvContactGroup = ObvContactGroup(groupStructure: groupStructure, identityDelegate: identityDelegate, within: obvContext) else {
                os_log("Could not create an ObvContactGroup structure", log: _self.log, type: .fault)
                return
            }
            
            ObvEngineNotificationNew.newPendingGroupMemberDeclinedStatus(obvContactGroup: obvContactGroup)
                .postOnBackgroundQueue(_self.queueForPostingNotificationsToTheApp, within: _self.appNotificationCenter)

        }
        
        
    }

    
    private func processMessageDecryptedNotification(obvMessageOrObvOwnedMessages: [ObvMessageOrObvOwnedMessage], flowId: FlowIdentifier) {
        
        //let logger = self.logger
        
//        guard let flowDelegate = flowDelegate else {
//            logger.fault("The flow delegate is not set")
//            assertionFailure()
//            return
//        }
        
        let appNotificationCenter = self.appNotificationCenter
        let queueForPostingNotificationsToTheApp = self.queueForPostingNotificationsToTheApp
        
        // Before notifying the app about this new message, we start a flow allowing to wait until the return receipt is sent.
        // In practice, the app will save the new message is database, create the return receipt, pass it to the engine that will send it.
        // Once this is done, the engine will stop the flow.
//        do {
//            _ = try flowDelegate.startBackgroundActivityForPostingReturnReceipt(messageId: obvMessageOrObvOwnedMessage.messageId, attachmentNumber: nil)
//        } catch {
//            logger.fault("🧾 Failed to start a flow allowing to wait for the message return receipt to be sent")
//            assertionFailure()
//            // In production, continue anyway
//        }
        
        ObvDisplayableLogs.shared.log("[🚩][\(flowId.shortDebugDescription)] Notifying the app about \(obvMessageOrObvOwnedMessages.count) messages")
        ObvEngineNotificationNew.newMessagesReceived(messages: obvMessageOrObvOwnedMessages)
            .postOnBackgroundQueue(queueForPostingNotificationsToTheApp, within: appNotificationCenter)

        
    }
    
    
    private func processAttachmentDownloadedNotification(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) {
        
        let log = self.log
        
        os_log("We received an AttachmentDownloaded notification for the attachment %{public}@", log: log, type: .debug, attachmentId.debugDescription)
        
        guard let createContextDelegate = createContextDelegate else {
            os_log("The create context delegate is not set", log: log, type: .fault)
            return
        }

        guard let networkFetchDelegate = networkFetchDelegate else {
            os_log("The network fetch delegate is not set", log: log, type: .fault)
            return
        }
        
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: randomFlowId) { [weak self] (obvContext) in
            
            guard let _self = self else { return }
            
            guard let networkReceivedAttachment = networkFetchDelegate.getAttachment(withId: attachmentId, within: obvContext) else {
                os_log("Could not get a network received attachment of message %{public}@ (4)", log: _self.log, type: .fault, attachmentId.messageId.debugDescription)
                return
            }

            if networkReceivedAttachment.fromCryptoIdentity == networkReceivedAttachment.attachmentId.messageId.ownedCryptoIdentity {
                
                let obvOwnedAttachment: ObvOwnedAttachment
                do {
                    obvOwnedAttachment = try ObvOwnedAttachment(attachmentId: attachmentId, networkFetchDelegate: networkFetchDelegate, within: obvContext)
                } catch {
                    os_log("Could not construct an ObvOwnedAttachment of message %{public}@ (4)", log: _self.log, type: .fault, attachmentId.messageId.debugDescription)
                    return
                }
                
                // Before notifying the app about this downloaded attachment, we start a flow allowing to wait until the return receipt for this attachment is sent.
                // In practice, the app will marks this attachment as "complete" in database, create the return receipt, pass it to the engine that will send it.
                // Once this is done, the engine will stop the flow.
//                do {
//                    _ = try flowDelegate.startBackgroundActivityForPostingReturnReceipt(messageId: attachmentId.messageId, attachmentNumber: attachmentId.attachmentNumber)
//                } catch {
//                    assertionFailure()
//                    os_log("🧾 Failed to start a flow allowing to wait for the message return receipt to be sent", log: log, type: .fault)
//                    // In production, continue anyway
//                }

                // We notify the app
                
                ObvEngineNotificationNew.ownedAttachmentDownloaded(obvOwnedAttachment: obvOwnedAttachment)
                    .postOnBackgroundQueue(_self.queueForPostingNotificationsToTheApp, within: _self.appNotificationCenter)
                
            } else {
                
                let contactIdentifier = ObvContactIdentifier(contactCryptoIdentity: networkReceivedAttachment.fromCryptoIdentity,
                                                             ownedCryptoIdentity: networkReceivedAttachment.attachmentId.messageId.ownedCryptoIdentity)
                
                let obvAttachment: ObvAttachment
                do {
                    try obvAttachment = ObvAttachment(attachmentId: attachmentId, fromContactIdentity: contactIdentifier, networkFetchDelegate: networkFetchDelegate, within: obvContext)
                } catch {
                    os_log("Could not construct an ObvAttachment of message %{public}@ (4)", log: _self.log, type: .fault, attachmentId.messageId.debugDescription)
                    return
                }
                
                // Before notifying the app about this downloaded attachment, we start a flow allowing to wait until the return receipt for this attachment is sent.
                // In practice, the app will marks this attachment as "complete" in database, create the return receipt, pass it to the engine that will send it.
                // Once this is done, the engine will stop the flow.
//                do {
//                    _ = try flowDelegate.startBackgroundActivityForPostingReturnReceipt(messageId: attachmentId.messageId, attachmentNumber: attachmentId.attachmentNumber)
//                } catch {
//                    assertionFailure()
//                    os_log("🧾 Failed to start a flow allowing to wait for the message return receipt to be sent", log: log, type: .fault)
//                    // In production, continue anyway
//                }
                
                // We notify the app
                
                ObvEngineNotificationNew.attachmentDownloaded(obvAttachment: obvAttachment)
                    .postOnBackgroundQueue(_self.queueForPostingNotificationsToTheApp, within: _self.appNotificationCenter)

                
            }

        }
    }
    
    
    private func processInboxAttachmentDownloadWasResumed(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) {
        os_log("We received an InboxAttachmentDownloadWasResumed notification from the network fetch manager for the attachment %{public}@", log: log, type: .debug, attachmentId.debugDescription)
        
        guard let createContextDelegate else { assertionFailure(); return }
        guard let networkFetchDelegate = networkFetchDelegate else { assertionFailure(); return }
        
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: randomFlowId) { [weak self] (obvContext) in
            
            guard let _self = self else { return }
            
            guard let networkReceivedAttachment = networkFetchDelegate.getAttachment(withId: attachmentId, within: obvContext) else {
                os_log("Could not get a network received attachment of message %{public}@ (4)", log: _self.log, type: .fault, attachmentId.messageId.debugDescription)
                return
            }
            
            let ownCryptoId = ObvCryptoId(cryptoIdentity: attachmentId.messageId.ownedCryptoIdentity)

            if networkReceivedAttachment.fromCryptoIdentity == networkReceivedAttachment.attachmentId.messageId.ownedCryptoIdentity {
                
                ObvEngineNotificationNew.ownedAttachmentDownloadWasResumed(ownCryptoId: ownCryptoId, messageIdentifierFromEngine: attachmentId.messageId.uid.raw, attachmentNumber: attachmentId.attachmentNumber)
                    .postOnBackgroundQueue(_self.queueForPostingNotificationsToTheApp, within: _self.appNotificationCenter)

            } else {
                
                ObvEngineNotificationNew.attachmentDownloadWasResumed(ownCryptoId: ownCryptoId, messageIdentifierFromEngine: attachmentId.messageId.uid.raw, attachmentNumber: attachmentId.attachmentNumber)
                    .postOnBackgroundQueue(_self.queueForPostingNotificationsToTheApp, within: _self.appNotificationCenter)

            }
            
        }
    }

    
    private func processInboxAttachmentDownloadWasPaused(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) {
        os_log("We received an InboxAttachmentDownloadWasPaused notification from the network fetch manager for the attachment %{public}@", log: log, type: .debug, attachmentId.debugDescription)
        
        guard let createContextDelegate else { assertionFailure(); return }
        guard let networkFetchDelegate = networkFetchDelegate else { assertionFailure(); return }
        
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: randomFlowId) { [weak self] (obvContext) in
            
            guard let _self = self else { return }
            
            guard let networkReceivedAttachment = networkFetchDelegate.getAttachment(withId: attachmentId, within: obvContext) else {
                os_log("Could not get a network received attachment of message %{public}@ (4)", log: _self.log, type: .fault, attachmentId.messageId.debugDescription)
                return
            }
            
            let ownCryptoId = ObvCryptoId(cryptoIdentity: attachmentId.messageId.ownedCryptoIdentity)
            
            if networkReceivedAttachment.fromCryptoIdentity == networkReceivedAttachment.attachmentId.messageId.ownedCryptoIdentity {
                
                ObvEngineNotificationNew.ownedAttachmentDownloadWasPaused(ownCryptoId: ownCryptoId, messageIdentifierFromEngine: attachmentId.messageId.uid.raw, attachmentNumber: attachmentId.attachmentNumber)
                    .postOnBackgroundQueue(_self.queueForPostingNotificationsToTheApp, within: _self.appNotificationCenter)

                
            } else {
                
                ObvEngineNotificationNew.attachmentDownloadWasPaused(ownCryptoId: ownCryptoId, messageIdentifierFromEngine: attachmentId.messageId.uid.raw, attachmentNumber: attachmentId.attachmentNumber)
                    .postOnBackgroundQueue(_self.queueForPostingNotificationsToTheApp, within: _self.appNotificationCenter)
                
            }
            
        }
    }

    
    private func processPushTopicReceivedViaWebsocket(pushTopic: String) {
        os_log("We received a PushTopicReceivedViaWebsocket notification from the network fetch manager. Push topic is %{public}@", log: log, type: .debug, pushTopic)
        ObvEngineNotificationNew.aPushTopicWasReceivedViaWebsocket(pushTopic: pushTopic)
            .postOnBackgroundQueue(queueForPostingNotificationsToTheApp, within: appNotificationCenter)
    }

    
    private func processKeycloakTargetedPushNotificationReceivedViaWebsocket(ownedIdentity: ObvCryptoIdentity) {
        os_log("We received a KeycloakTargetedPushNotificationReceivedViaWebsocket notification from the network fetch manager. Owned identity is %{public}@", log: log, type: .debug, ownedIdentity.debugDescription)
        let ownCryptoId = ObvCryptoId(cryptoIdentity: ownedIdentity)
        ObvEngineNotificationNew.aKeycloakTargetedPushNotificationReceivedViaWebsocket(ownedIdentity: ownCryptoId)
            .postOnBackgroundQueue(queueForPostingNotificationsToTheApp, within: appNotificationCenter)
    }


    /// Thanks to a internal notification within the Oblivious Engine, this method gets called when an Oblivious channel is confirmed. Within this method, we send a similar notification through the default notification center so as to let the App be notified.
    private func processNewConfirmedObliviousChannelNotification(currentDeviceUid: UID, remoteCryptoIdentity: ObvCryptoIdentity, remoteDeviceUid: UID) {
        
        os_log("We received a NewConfirmedObliviousChannel notification", log: log, type: .info)
        
        guard let createContextDelegate else {
            os_log("The create context delegate is not set", log: log, type: .fault)
            return
        }
        guard let identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            return
        }
        
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: randomFlowId) { [weak self] (obvContext) in
            
            guard let _self = self else { return }
            
            // Determine the owned identity related to the current device uid
            
            guard let ownedCryptoIdentity = try? identityDelegate.getOwnedIdentityOfCurrentDeviceUid(currentDeviceUid, within: obvContext) else {
                os_log("The device uid does not correspond to any owned identity (6)", log: _self.log, type: .fault)
                return
            }
            
            // The remote device might either be :
            // - an owned remote device
            // - a contact device
            // For each case, we have an appropriate notification to send
            
            if ownedCryptoIdentity == remoteCryptoIdentity {
                
                os_log("The channel was created with a remote owned device %@", log: _self.log, type: .info, remoteDeviceUid.description)

                ObvEngineNotificationNew.newConfirmedObliviousChannelWithRemoteOwnedDevice
                    .postOnBackgroundQueue(within: _self.appNotificationCenter)

            } else {
                
                os_log("The channel was created with a contact device %@", log: _self.log, type: .info, remoteDeviceUid.description)

                let obvContactIdentifier = ObvContactIdentifier(contactCryptoIdentity: remoteCryptoIdentity, ownedCryptoIdentity: ownedCryptoIdentity)
                
                ObvEngineNotificationNew.newObliviousChannelWithContactDevice(obvContactIdentifier: obvContactIdentifier)
                    .postOnBackgroundQueue(within: _self.appNotificationCenter)

            }

        }
    }
    
    
    /// Thanks to a internal notification within the Oblivious Engine, this method gets called when a conctact identity becomes trusted. Within this method, we send a similar notification through the default notification center so as to let the App be notified.
    func processContactIdentityIsNowTrustedNotification(ownedCryptoIdentity: ObvCryptoIdentity, contactCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        
        guard let createContextDelegate = createContextDelegate else { return }
        guard let identityDelegate = identityDelegate else { return }
        
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: randomFlowId) { [weak self] (obvContext) in
            
            guard let _self = self else { return }
            
            guard let contactIdentity = ObvContactIdentity(contactCryptoIdentity: contactCryptoIdentity, ownedCryptoIdentity: ownedCryptoIdentity, identityDelegate: identityDelegate, within: obvContext) else {
                os_log("Could not create an ObvContactIdentity", log: _self.log, type: .fault)
                return
            }
            
            ObvEngineNotificationNew.newTrustedContactIdentity(obvContactIdentity: contactIdentity)
                .postOnBackgroundQueue(_self.queueForPostingNotificationsToTheApp, within: _self.appNotificationCenter)
            
        }
    }
    
}
