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
        
        notificationCenterTokens.append(ObvNetworkFetchNotificationNew.observeAppStoreReceiptVerificationSucceededButSubscriptionIsExpired(within: notificationDelegate) { [weak self] (ownedIdentity, transactionIdentifier, flowId) in
            guard let _self = self else { return }
            ObvEngineNotificationNew.appStoreReceiptVerificationSucceededButSubscriptionIsExpired(ownedIdentity: ObvCryptoId(cryptoIdentity: ownedIdentity), transactionIdentifier: transactionIdentifier)
                .postOnBackgroundQueue(within: _self.appNotificationCenter)
        })

        notificationCenterTokens.append(ObvNetworkFetchNotificationNew.observeAppStoreReceiptVerificationFailed(within: notificationDelegate) { [weak self] (ownedIdentity, transactionIdentifier, flowId) in
            guard let _self = self else { return }
            ObvEngineNotificationNew.appStoreReceiptVerificationFailed(ownedIdentity: ObvCryptoId(cryptoIdentity: ownedIdentity), transactionIdentifier: transactionIdentifier)
                .postOnBackgroundQueue(within: _self.appNotificationCenter)
        })
        
        notificationCenterTokens.append(ObvNetworkFetchNotificationNew.observeFreeTrialIsStillAvailableForOwnedIdentity(within: notificationDelegate) { [weak self] (ownedIdentity, flowId) in
            self?.processFreeTrialIsStillAvailableForOwnedIdentity(ownedIdentity: ownedIdentity, flowId: flowId)
        })
        
        notificationCenterTokens.append(ObvNetworkFetchNotificationNew.observeNoMoreFreeTrialAPIKeyAvailableForOwnedIdentity(within: notificationDelegate) { [weak self] (ownedIdentity, flowId) in
            self?.processNoMoreFreeTrialAPIKeyAvailableForOwnedIdentity(ownedIdentity: ownedIdentity, flowId: flowId)
        })
                        
        notificationCenterTokens.append(ObvNetworkFetchNotificationNew.observeNewAPIKeyElementsForAPIKey(within: notificationDelegate) { [weak self] (serverURL, apiKey, apiKeyStatus, apiPermissions, apiKeyExpirationDate) in
            self?.processNewAPIKeyElementsForAPIKeyNotification(serverURL: serverURL, apiKey: apiKey, apiKeyStatus: apiKeyStatus, apiPermissions: apiPermissions, apiKeyExpirationDate: apiKeyExpirationDate)
        })

        notificationCenterTokens.append(ObvNetworkFetchNotificationNew.observeNewAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity(within: notificationDelegate) { [weak self] (ownedIdentity, apiKeyStatus, apiPermissions, apiKeyExpirationDate) in
            self?.processNewAPIKeyElementsForCurrentAPIKeyOfOwnedIdentityNotification(ownedIdentity: ownedIdentity, apiKeyStatus: apiKeyStatus, apiPermissions: apiPermissions, apiKeyExpirationDate: apiKeyExpirationDate)
        })
        
        notificationCenterTokens.append(ObvNetworkFetchNotificationNew.observeCannotReturnAnyProgressForMessageAttachments(within: notificationDelegate, block: { [weak self] (messageId, flowId) in
            self?.processCannotReturnAnyProgressForMessageAttachmentsNotification(messageId: messageId, flowId: flowId)
        }))
        notificationCenterTokens.append(ObvNetworkFetchNotificationNew.observeTurnCredentialsReceptionPermissionDenied(within: notificationDelegate) { [weak self] (ownedIdentity, callUuid, flowId) in
            self?.processTurnCredentialsReceptionPermissionDeniedNotification(ownedIdentity: ownedIdentity, callUuid: callUuid, flowId: flowId)
        })
        notificationCenterTokens.append(ObvNetworkFetchNotificationNew.observeTurnCredentialServerDoesNotSupportCalls(within: notificationDelegate) { [weak self] (ownedIdentity, callUuid, flowId) in
            self?.processTurnCredentialServerDoesNotSupportCalls(ownedIdentity: ownedIdentity, callUuid: callUuid, flowId: flowId)
        })

        notificationCenterTokens.append(ObvNetworkFetchNotificationNew.observeTurnCredentialsReceptionFailure(within: notificationDelegate) { [weak self] (ownedIdentity, callUuid, flowId) in
            self?.processTurnCredentialsReceptionFailureNotification(ownedIdentity: ownedIdentity, callUuid: callUuid, flowId: flowId)
        })
        
        notificationCenterTokens.append(ObvNetworkFetchNotificationNew.observeTurnCredentialsReceived(within: notificationDelegate, queue: nil, block: { [weak self] (ownedIdentity, callUuid, turnCredentialsWithTurnServers, flowId) in
            self?.processTurnCredentialsReceivedNotification(ownedIdentity: ownedIdentity, callUuid: callUuid, turnCredentialsWithTurnServers: turnCredentialsWithTurnServers, flowId: flowId)
        }))
        
        notificationCenterTokens.append(ObvNetworkPostNotification.observeOutboxMessageWasUploaded(within: notificationDelegate, queue: nil) { [weak self] (messageId, timestampFromServer, isAppMessageWithUserContent, isVoipMessage, flowId) in
            self?.processOutboxMessageWasUploadedNotification(messageId: messageId, timestampFromServer: timestampFromServer, isAppMessageWithUserContent: isAppMessageWithUserContent, isVoipMessage: isVoipMessage, flowId: flowId)
        })
        
        do {
            let token = ObvNetworkPostNotification.observeOutboxMessagesAndAllTheirAttachmentsWereAcknowledged(within: notificationDelegate, queue: nil) { [weak self] (messageIdsAndTimestampsFromServer, flowId) in
                self?.processOutboxMessagesAndAllTheirAttachmentsWereAcknowledgedNotifications(messageIdsAndTimestampsFromServer: messageIdsAndTimestampsFromServer, flowId: flowId)
            }
            notificationCenterTokens.append(token)
        }

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
        
        do {
            notificationCenterTokens.append(ObvNetworkFetchNotificationNew.observeApplicationMessageDecrypted(within: notificationDelegate) { [weak self] (messageId, attachmentIds, hasEncryptedExtendedMessagePayload, flowId) in
                self?.processMessageDecryptedNotification(messageId: messageId, flowId: flowId)
            })
        }
        
        do {
            let token = ObvNetworkFetchNotificationNew.observeInboxAttachmentHasNewProgress(within: notificationDelegate) { [weak self] (attachmentId, progress, flowId) in
                self?.processAttachmentDownloadNewProgressNotification(attachmentId: attachmentId, progress: progress, flowId: flowId)
            }
            notificationCenterTokens.append(token)
        }
        
        do {
            let token = ObvNetworkPostNotification.observeOutboxAttachmentHasNewProgress(within: notificationDelegate) { [weak self] (attachmentId, newProgress, flowId) in
                self?.processOutboxAttachmentHasNewProgressNotification(attachmentId: attachmentId, newProgress: newProgress, flowId: flowId)
            }
            notificationCenterTokens.append(token)
        }

        do {
            let token = ObvNetworkFetchNotificationNew.observeInboxAttachmentWasDownloaded(within: notificationDelegate) { [weak self] (attachmentId, flowId) in
                self?.processAttachmentDownloadedNotification(attachmentId: attachmentId, flowId: flowId)
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
            let token = ObvBackupNotification.observeNewBackupSeedGenerated(within: notificationDelegate) { [weak self] (backupSeedString, backupKeyInformation, flowId)  in
                guard let appNotificationCenter = self?.appNotificationCenter else { return }
                let obvBackupKeyInformation = ObvBackupKeyInformation(backupKeyInformation: backupKeyInformation)
                let notification = ObvEngineNotificationNew.newBackupKeyGenerated(backupKeyString: backupSeedString, obvBackupKeyInformation: obvBackupKeyInformation)
                notification.postOnBackgroundQueue(within: appNotificationCenter)
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
            let token = ObvNetworkFetchNotificationNew.observeServerRequiresThisDeviceToRegisterToPushNotifications(within: notificationDelegate) { [weak self] (ownedIdentity, flowId) in
                guard let appNotificationCenter = self?.appNotificationCenter else { return }
                let ownedCryptoId = ObvCryptoId(cryptoIdentity: ownedIdentity)
                let notification = ObvEngineNotificationNew.serverRequiresThisDeviceToRegisterToPushNotifications(ownedIdentity: ownedCryptoId)
                notification.postOnBackgroundQueue(within: appNotificationCenter)
            }
            notificationCenterTokens.append(token)
        }

        do {
            let token = ObvBackupNotification.observeBackupForUploadWasUploaded(within: notificationDelegate) { [weak self] (backupKeyUid, version, flowId) in
                guard let appNotificationCenter = self?.appNotificationCenter else { return }
                let notification = ObvEngineNotificationNew.backupForUploadWasUploaded(backupRequestUuid: flowId, backupKeyUid: backupKeyUid, version: version)
                notification.postOnBackgroundQueue(within: appNotificationCenter)
            }
            notificationCenterTokens.append(token)
        }

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
            ObvNetworkFetchNotificationNew.observeApiKeyStatusQueryFailed(within: notificationDelegate) { [weak self] (ownedIdentity, apiKey) in
                self?.processApiKeyStatusQueryFailed(ownedIdentity: ownedIdentity, apiKey: apiKey)
            },
            ObvProtocolNotification.observeMutualScanContactAdded(within: notificationDelegate) { [weak self] ownedIdentity, contactIdentity, signature in
                self?.processMutualScanContactAdded(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, signature: signature)
            },
            ObvNetworkFetchNotificationNew.observeDownloadingMessageExtendedPayloadWasPerformed(within: notificationDelegate) { [weak self] (messageId, extendedMessagePayload, flowId) in
                self?.processDownloadingMessageExtendedPayloadWasPerformed(messageId: messageId, extendedMessagePayload: extendedMessagePayload, flowId: flowId)
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
            ObvIdentityNotificationNew.observeOwnedIdentityCapabilitiesWereUpdated(within: notificationDelegate) { [weak self] ownedIdentity, flowId in
                self?.processOwnedIdentityCapabilitiesWereUpdated(ownedIdentity: ownedIdentity, flowId: flowId)
            },
        ])
        
        do {
            let token = ObvBackupNotification.observeBackupForExportWasExported(within: notificationDelegate) { [weak self] (backupKeyUid, version, flowId) in
                guard let appNotificationCenter = self?.appNotificationCenter else { return }
                let notification = ObvEngineNotificationNew.backupForExportWasExported(backupRequestUuid: flowId, backupKeyUid: backupKeyUid, version: version)
                notification.postOnBackgroundQueue(within: appNotificationCenter)
            }
            notificationCenterTokens.append(token)
        }

        do {
            let token = ObvNetworkFetchNotificationNew.observeWellKnownHasBeenUpdated(within: notificationDelegate) { [weak self] (serverURL, appInfo, flowId) in
                guard let appNotificationCenter = self?.appNotificationCenter else { return }
                let notification = ObvEngineNotificationNew.wellKnownUpdatedSuccess(serverURL: serverURL, appInfo: appInfo)
                notification.postOnBackgroundQueue(within: appNotificationCenter)
            }
            notificationCenterTokens.append(token)
        }

        do {
            let token = ObvNetworkFetchNotificationNew.observeWellKnownHasBeenDownloaded(within: notificationDelegate) { [weak self] (serverURL, appInfo, flowId) in
                guard let appNotificationCenter = self?.appNotificationCenter else { return }
                let notification = ObvEngineNotificationNew.wellKnownDownloadedSuccess(serverURL: serverURL, appInfo: appInfo)
                notification.postOnBackgroundQueue(within: appNotificationCenter)
            }
            notificationCenterTokens.append(token)
        }

        do {
            let token = ObvNetworkFetchNotificationNew.observeWellKnownDownloadFailure(within: notificationDelegate) { [weak self] (serverURL, flowId) in
                guard let appNotificationCenter = self?.appNotificationCenter else { return }
                let notification = ObvEngineNotificationNew.wellKnownDownloadedFailure(serverURL: serverURL)
                notification.postOnBackgroundQueue(within: appNotificationCenter)
            }
            notificationCenterTokens.append(token)
        }

        do {
            let token = ObvChannelNotification.observeDeletedConfirmedObliviousChannel(within: notificationDelegate) { [weak self] (currentDeviceUid, remoteCryptoIdentity, remoteDeviceUid) in
                self?.processDeletedConfirmedObliviousChannelNotifications(currentDeviceUid: currentDeviceUid, remoteCryptoIdentity: remoteCryptoIdentity, remoteDeviceUid: remoteDeviceUid)
            }
            notificationCenterTokens.append(token)
        }

        observeNewPublishedContactIdentityDetailsNotifications(notificationDelegate: notificationDelegate)
        observeOwnedIdentityDetailsPublicationInProgressNotifications(notificationDelegate: notificationDelegate)
        observeNewTrustedContactIdentityDetailsNotifications(notificationDelegate: notificationDelegate)
        observeAttachmentDownloadCancelledByServerNotifications(notificationDelegate: notificationDelegate)
        observeNewReturnReceiptToProcessNotifications(notificationDelegate: notificationDelegate)
        
    }
    
    
    private func processApiKeyStatusQueryFailed(ownedIdentity: ObvCryptoIdentity, apiKey: UUID) {
        // We do not send the owned identity. In certain cases, we use a dummy owned identity to query the server. We should not send this dummy identity to the application.
        ObvEngineNotificationNew.apiKeyStatusQueryFailed(serverURL: ownedIdentity.serverURL, apiKey: apiKey)
            .postOnBackgroundQueue(within: appNotificationCenter)
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

    
    private func observeNewReturnReceiptToProcessNotifications(notificationDelegate: ObvNotificationDelegate) {
        let NotificationType = ObvNetworkFetchNotification.NewReturnReceiptToProcess.self
        let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
            guard let _self = self else { return }
            guard let returnReceipt = NotificationType.parse(notification) else { return }
            let obvReturnReceipt = ObvReturnReceipt(returnReceipt: returnReceipt)
            ObvEngineNotificationNew.newObvReturnReceiptToProcess(obvReturnReceipt: obvReturnReceipt)
                .postOnBackgroundQueue(_self.queueForPostingNewObvReturnReceiptToProcessNotifications, within: _self.appNotificationCenter)
        }
        notificationCenterTokens.append(token)
    }
    
    
    private func processDownloadingMessageExtendedPayloadWasPerformed(messageId: MessageIdentifier, extendedMessagePayload: Data, flowId: FlowIdentifier) {
        
        os_log("We received a DownloadingMessageExtendedPayloadWasPerformed notification for the message %{public}@.", log: log, type: .debug, messageId.debugDescription)

        
        guard let createContextDelegate = createContextDelegate else {
            os_log("The create context delegate is not set", log: log, type: .fault)
            return
        }
        
        guard let networkFetchDelegate = networkFetchDelegate else {
            os_log("The network fetch delegate is not set", log: log, type: .fault)
            return
        }
        
        guard let identityDelegate = identityDelegate else {
            os_log("The network fetch delegate is not set", log: log, type: .fault)
            return
        }

        createContextDelegate.performBackgroundTask(flowId: flowId) { [weak self] (obvContext) in

            guard let _self = self else { return }

            let obvMessage: ObvMessage
            do {
                try obvMessage = ObvMessage(messageId: messageId, networkFetchDelegate: networkFetchDelegate, identityDelegate: identityDelegate, within: obvContext)
            } catch {
                os_log("Could not construct an ObvMessage from the network message and its attachments", log: _self.log, type: .fault, messageId.debugDescription)
                return
            }
            
            ObvEngineNotificationNew.messageExtendedPayloadAvailable(obvMessage: obvMessage, extendedMessagePayload: extendedMessagePayload)
                .postOnBackgroundQueue(_self.queueForPostingNotificationsToTheApp, within: _self.appNotificationCenter)

        }
        
    }
    

    private func observeAttachmentDownloadCancelledByServerNotifications(notificationDelegate: ObvNotificationDelegate) {
        
        let token = ObvNetworkFetchNotificationNew.observeInboxAttachmentDownloadCancelledByServer(within: notificationDelegate) { [weak self] (attachmentId, flowId) in
            guard let _self = self else { return }
            
            os_log("We received an AttachmentDownloadCancelledByServer notification for the attachment %{public}@.", log: _self.log, type: .debug, attachmentId.debugDescription)
            
            guard let createContextDelegate = _self.createContextDelegate else {
                os_log("The create context delegate is not set", log: _self.log, type: .fault)
                return
            }
            
            guard let networkFetchDelegate = _self.networkFetchDelegate else {
                os_log("The network fetch delegate is not set", log: _self.log, type: .fault)
                return
            }
            
            guard let identityDelegate = _self.identityDelegate else {
                os_log("The identity delegate is not set", log: _self.log, type: .fault)
                return
            }
            
            createContextDelegate.performBackgroundTask(flowId: flowId) { [weak self] (obvContext) in
                
                guard let _self = self else { return }
                
                let obvAttachment: ObvAttachment
                do {
                    try obvAttachment = ObvAttachment(attachmentId: attachmentId, networkFetchDelegate: networkFetchDelegate, identityDelegate: identityDelegate, within: obvContext)
                } catch {
                    os_log("Could not construct an ObvAttachment of attachment %{public}@", log: _self.log, type: .fault, attachmentId.debugDescription)
                    return
                }
                
                // We notify the app
                
                ObvEngineNotificationNew.attachmentDownloadCancelledByServer(obvAttachment: obvAttachment)
                    .postOnBackgroundQueue(within: _self.appNotificationCenter)

            }

            
        }
        notificationCenterTokens.append(token)
        
    }
    
    
    private func processDeletedConfirmedObliviousChannelNotifications(currentDeviceUid: UID, remoteCryptoIdentity: ObvCryptoIdentity, remoteDeviceUid: UID) {
        os_log("We received a DeletedConfirmedObliviousChannel notification", log: log, type: .info)
        
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
            
            // Determine the owned identity related to the current device uid
            
            guard let ownedCryptoIdentity = try? identityDelegate.getOwnedIdentityOfCurrentDeviceUid(currentDeviceUid, within: obvContext) else {
                os_log("The device uid does not correspond to any owned identity", log: _self.log, type: .fault)
                return
            }
            
            // The remote device might either be :
            // - an owned remote device
            // - a contact device
            // For each case, we have an appropriate notification to send
            
            if let remoteOwnedDevice = ObvRemoteOwnedDevice(remoteOwnedDeviceUid: remoteDeviceUid, ownedCryptoIdentity: ownedCryptoIdentity, identityDelegate: identityDelegate, within: obvContext) {
                
                os_log("The deleted channel was one with had with a remote owned device %@", log: _self.log, type: .info, remoteOwnedDevice.description)
                                    
            } else if let contactDevice = ObvContactDevice(contactDeviceUid: remoteDeviceUid, contactCryptoIdentity: remoteCryptoIdentity, ownedCryptoIdentity: ownedCryptoIdentity, identityDelegate: identityDelegate, within: obvContext) {
                
                os_log("The deleted channel was one we had with a contact device", log: _self.log, type: .info)
                
                let NotificationType = ObvEngineNotification.DeletedObliviousChannelWithContactDevice.self
                let userInfo = [NotificationType.Key.obvContactDevice: contactDevice]
                let notification = Notification(name: NotificationType.name, userInfo: userInfo)
                _self.appNotificationCenter.post(notification)
                
            } else {
                
                os_log("We could not determine any appropriate remote device. It might have been deleted already.", log: _self.log, type: .info)
                
                if let obvContactIdentity = ObvContactIdentity(contactCryptoIdentity: remoteCryptoIdentity, ownedCryptoIdentity: ownedCryptoIdentity, identityDelegate: identityDelegate, within: obvContext) {
                    
                    let contactDevice = ObvContactDevice(identifier: remoteDeviceUid.raw, contactIdentity: obvContactIdentity)
                    
                    os_log("The deleted channel was one we had with a contact device", log: _self.log, type: .info)
                    
                    let NotificationType = ObvEngineNotification.DeletedObliviousChannelWithContactDevice.self
                    let userInfo = [NotificationType.Key.obvContactDevice: contactDevice]
                    let notification = Notification(name: NotificationType.name, userInfo: userInfo)
                    _self.appNotificationCenter.post(notification)

                }
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

            ObvEngineNotificationNew.contactWasRevokedAsCompromisedWithinEngine(obvContactIdentity: obvContactIdentity)
                .postOnBackgroundQueue(within: appNotificationCenter)

        }

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

    
    private func processOutboxMessagesAndAllTheirAttachmentsWereAcknowledgedNotifications(messageIdsAndTimestampsFromServer: [(messageId: MessageIdentifier, timestampFromServer: Date)], flowId: FlowIdentifier) {
        os_log("We received an OutboxMessagesAndAllTheirAttachmentsWereAcknowledged notification within flow %{public}@", log: log, type: .debug, flowId.debugDescription)
        let info = messageIdsAndTimestampsFromServer.map() { ($0.messageId.uid.raw, ObvCryptoId(cryptoIdentity: $0.messageId.ownedCryptoIdentity), $0.timestampFromServer) }
        ObvEngineNotificationNew.outboxMessagesAndAllTheirAttachmentsWereAcknowledged(messageIdsAndTimestampsFromServer: info)
            .postOnBackgroundQueue(within: appNotificationCenter)
    }
    
    private func processTurnCredentialsReceptionPermissionDeniedNotification(ownedIdentity: ObvCryptoIdentity, callUuid: UUID, flowId: FlowIdentifier) {
        ObvEngineNotificationNew.callerTurnCredentialsReceptionPermissionDenied(ownedIdentity: ObvCryptoId(cryptoIdentity: ownedIdentity), callUuid: callUuid)
            .postOnBackgroundQueue(within: appNotificationCenter)
    }

    private func processTurnCredentialServerDoesNotSupportCalls(ownedIdentity: ObvCryptoIdentity, callUuid: UUID, flowId: FlowIdentifier) {
        ObvEngineNotificationNew.callerTurnCredentialsServerDoesNotSupportCalls(ownedIdentity: ObvCryptoId(cryptoIdentity: ownedIdentity), callUuid: callUuid)
            .postOnBackgroundQueue(within: appNotificationCenter)
    }

    private func processTurnCredentialsReceptionFailureNotification(ownedIdentity: ObvCryptoIdentity, callUuid: UUID, flowId: FlowIdentifier) {
        ObvEngineNotificationNew.callerTurnCredentialsReceptionFailure(ownedIdentity: ObvCryptoId(cryptoIdentity: ownedIdentity), callUuid: callUuid)
            .postOnBackgroundQueue(within: appNotificationCenter)
    }

    private func processTurnCredentialsReceivedNotification(ownedIdentity: ObvCryptoIdentity, callUuid: UUID, turnCredentialsWithTurnServers credentials: TurnCredentialsWithTurnServers, flowId: FlowIdentifier) {
        let obvTurnCredentials = ObvTurnCredentials(callerUsername: credentials.expiringUsername1,
                                                    callerPassword: credentials.password1,
                                                    recipientUsername: credentials.expiringUsername2,
                                                    recipientPassword: credentials.password2,
                                                    turnServersURL: credentials.turnServersURL)
        let notification = ObvEngineNotificationNew.callerTurnCredentialsReceived(ownedIdentity: ObvCryptoId(cryptoIdentity: ownedIdentity),
                                                                                  callUuid: callUuid,
                                                                                  turnCredentials: obvTurnCredentials)
        notification.postOnBackgroundQueue(within: appNotificationCenter)
    }
    
    private func processFreeTrialIsStillAvailableForOwnedIdentity(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        let identity = ObvCryptoId(cryptoIdentity: ownedIdentity)
        ObvEngineNotificationNew.freeTrialIsStillAvailableForOwnedIdentity(ownedIdentity: identity)
            .postOnBackgroundQueue(within: appNotificationCenter)
    }
    
    private func processNoMoreFreeTrialAPIKeyAvailableForOwnedIdentity(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        let identity = ObvCryptoId(cryptoIdentity: ownedIdentity)
        ObvEngineNotificationNew.noMoreFreeTrialAPIKeyAvailableForOwnedIdentity(ownedIdentity: identity)
            .postOnBackgroundQueue(within: appNotificationCenter)
    }
        
    private func processNewAPIKeyElementsForAPIKeyNotification(serverURL: URL, apiKey: UUID, apiKeyStatus: APIKeyStatus, apiPermissions: APIPermissions, apiKeyExpirationDate: Date?) {
        ObvEngineNotificationNew.newAPIKeyElementsForAPIKey(serverURL: serverURL, apiKey: apiKey, apiKeyStatus: apiKeyStatus, apiPermissions: apiPermissions, apiKeyExpirationDate: EngineOptionalWrapper(apiKeyExpirationDate))
            .postOnBackgroundQueue(within: appNotificationCenter)
    }
    
    private func processNewAPIKeyElementsForCurrentAPIKeyOfOwnedIdentityNotification(ownedIdentity: ObvCryptoIdentity, apiKeyStatus: APIKeyStatus, apiPermissions: APIPermissions, apiKeyExpirationDate: Date?) {
        let ownedIdentity = ObvCryptoId(cryptoIdentity: ownedIdentity)
        ObvEngineNotificationNew.newAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity(ownedIdentity: ownedIdentity, apiKeyStatus: apiKeyStatus, apiPermissions: apiPermissions, apiKeyExpirationDate: EngineOptionalWrapper(apiKeyExpirationDate))
            .postOnBackgroundQueue(within: appNotificationCenter)
    }
    
    private func processCannotReturnAnyProgressForMessageAttachmentsNotification(messageId: MessageIdentifier, flowId: FlowIdentifier) {
        ObvEngineNotificationNew.cannotReturnAnyProgressForMessageAttachments(messageIdentifierFromEngine: messageId.uid.raw)
            .postOnBackgroundQueue(within: appNotificationCenter)
    }

    
    private func processOutboxMessageWasUploadedNotification(messageId: MessageIdentifier, timestampFromServer: Date, isAppMessageWithUserContent: Bool, isVoipMessage: Bool, flowId: FlowIdentifier) {
        
        os_log("We received an OutboxMessageWasUploaded notification within flow %{public}@", log: log, type: .debug, flowId.debugDescription)
        
        let ownedIdentity = ObvCryptoId(cryptoIdentity: messageId.ownedCryptoIdentity)
        ObvEngineNotificationNew.messageWasAcknowledged(ownedIdentity: ownedIdentity,
                                                        messageIdentifierFromEngine: messageId.uid.raw,
                                                        timestampFromServer: timestampFromServer,
                                                        isAppMessageWithUserContent: isAppMessageWithUserContent,
                                                        isVoipMessage: isVoipMessage)
            .postOnBackgroundQueue(within: appNotificationCenter)

    }
    
    private func processAttachmentWasAcknowledgedNotification(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier) {
        
        os_log("We received an AttachmentWasAcknowledged notification within flow %{public}@", log: log, type: .debug, flowId.debugDescription)
        
        ObvEngineNotificationNew.attachmentWasAcknowledgedByServer(messageIdentifierFromEngine: attachmentId.messageId.uid.raw, attachmentNumber: attachmentId.attachmentNumber)
            .postOnBackgroundQueue(within: appNotificationCenter)

    }
    
    private func registerToContactWasDeletedNotifications(notificationDelegate: ObvNotificationDelegate) {
        let log = self.log
        let token = ObvIdentityNotificationNew.observeContactWasDeleted(within: notificationDelegate) { [weak self] (ownedCryptoIdentity, contactCryptoIdentity, contactTrustedIdentityDetails) in
            
            guard let _self = self else { return }
            
            os_log("We received an ContactWasDeleted notification for the contact %@ of the ownedIdentity %@", log: log, type: .info, contactCryptoIdentity.debugDescription, ownedCryptoIdentity.debugDescription)
                        
            ObvEngineNotificationNew.contactWasDeleted(
                ownedCryptoId: ObvCryptoId(cryptoIdentity: ownedCryptoIdentity),
                contactCryptoId: ObvCryptoId(cryptoIdentity: contactCryptoIdentity))
                .postOnBackgroundQueue(within: _self.appNotificationCenter)

        }        
        notificationCenterTokens.append(token)
    }
    
    
    private func processOutboxAttachmentHasNewProgressNotification(attachmentId: AttachmentIdentifier, newProgress: Progress, flowId: FlowIdentifier) {

        ObvEngineNotificationNew.attachmentUploadNewProgress(messageIdentifierFromEngine: attachmentId.messageId.uid.raw, attachmentNumber: attachmentId.attachmentNumber, newProgress: newProgress)
            .postOnBackgroundQueue(within: appNotificationCenter)

    }
    
    private func processAttachmentDownloadNewProgressNotification(attachmentId: AttachmentIdentifier, progress: Progress, flowId: FlowIdentifier) {

        os_log("🌊 We received an AttachmentDownloadNewProgress notification within flow %{public}@.", log: log, type: .debug, flowId.debugDescription)
        os_log("We received an AttachmentDownloadNewProgress notification for the attachment %{public}@. Progress is %{public}@.", log: log, type: .debug, attachmentId.debugDescription, progress.localizedDescription)
        
        let log = self.log
        
        guard let createContextDelegate = createContextDelegate else {
            os_log("The create context delegate is not set", log: log, type: .fault)
            return
        }
        
        guard let networkFetchDelegate = networkFetchDelegate else {
            os_log("The network fetch delegate is not set", log: log, type: .fault)
            return
        }
        
        guard let identityDelegate = identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            return
        }
        
        let appNotificationCenter = self.appNotificationCenter
        let queueForPostingNotificationsToTheApp = self.queueForPostingNotificationsToTheApp
        
        createContextDelegate.performBackgroundTask(flowId: flowId) { [weak self] (obvContext) in
            guard let _self = self else { return }
            let obvAttachment: ObvAttachment
            do {
                obvAttachment = try ObvAttachment(attachmentId: attachmentId, networkFetchDelegate: networkFetchDelegate, identityDelegate: identityDelegate, within: obvContext)
            } catch {
                os_log("Could not construct an ObvAttachment of message %{public}@ (1)", log: _self.log, type: .fault, attachmentId.messageId.debugDescription)
                return
            }
            
            // We notify the app
            
            ObvEngineNotificationNew.inboxAttachmentNewProgress(obvAttachment: obvAttachment, newProgress: progress)
                .postOnBackgroundQueue(queueForPostingNotificationsToTheApp, within: appNotificationCenter)

        }
        
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
            
            let NotificationType = ObvEngineNotification.NewContactGroup.self
            let userInfo = [NotificationType.Key.obvContactGroup: obvContactGroup]
            let notification = Notification(name: NotificationType.name, userInfo: userInfo)
            self?.appNotificationCenter.post(notification)
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
            
            let NotificationType = ObvEngineNotification.NewContactGroup.self
            let userInfo = [NotificationType.Key.obvContactGroup: obvContactGroup]
            let notification = Notification(name: NotificationType.name, userInfo: userInfo)
            self?.appNotificationCenter.post(notification)
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
            
            let NotificationType = ObvEngineNotification.ContactGroupHasUpdatedPendingMembersAndGroupMembers.self
            let userInfo = [NotificationType.Key.obvContactGroup: obvContactGroup]
            let notification = Notification(name: NotificationType.name, userInfo: userInfo)
            self?.appNotificationCenter.post(notification)
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
            
            let NotificationType = ObvEngineNotification.ContactGroupHasUpdatedPendingMembersAndGroupMembers.self
            let userInfo = [NotificationType.Key.obvContactGroup: obvContactGroup]
            let notification = Notification(name: NotificationType.name, userInfo: userInfo)
            self?.appNotificationCenter.post(notification)
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

            let NotificationType = ObvEngineNotification.ContactGroupHasUpdatedPublishedDetails.self
            let userInfo = [NotificationType.Key.obvContactGroup: obvContactGroup]
            let notification = Notification(name: NotificationType.name, userInfo: userInfo)
            self?.appNotificationCenter.post(notification)
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
            
            let NotificationType = ObvEngineNotification.ContactGroupHasUpdatedPublishedDetails.self
            let userInfo = [NotificationType.Key.obvContactGroup: obvContactGroup]
            let notification = Notification(name: NotificationType.name, userInfo: userInfo)
            self?.appNotificationCenter.post(notification)
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
        let appNotificationCenter = self.appNotificationCenter
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
            guard let obvOwnedIdentity = ObvOwnedIdentity(ownedCryptoIdentity: ownedIdentity,
                                                          identityDelegate: identityDelegate, within: obvContext) else {
                os_log("Could not create an ObvOwnedIdentity structure", log: self.log, type: .fault)
                return
            }
            ObvEngineNotificationNew.publishedPhotoOfOwnedIdentityHasBeenUpdated(ownedIdentity: obvOwnedIdentity)
                .postOnBackgroundQueue(within: appNotificationCenter)
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
            
            let NotificationType = ObvEngineNotification.ContactGroupDeleted.self
            let userInfo = [NotificationType.Key.groupUid: groupUid,
                            NotificationType.Key.groupOwner: ObvCryptoId(cryptoIdentity: groupOwner),
                            NotificationType.Key.ownedIdentity: obvOwnedIdentity] as [String: Any]
            let notification = Notification(name: NotificationType.name, userInfo: userInfo)
            self?.appNotificationCenter.post(notification)
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
            
            let NotificationType = ObvEngineNotification.ContactGroupOwnedHasUpdatedLatestDetails.self
            let userInfo = [NotificationType.Key.obvContactGroup: obvContactGroup]
            let notification = Notification(name: NotificationType.name, userInfo: userInfo)
            self?.appNotificationCenter.post(notification)
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
            
            let NotificationType = ObvEngineNotification.ContactGroupOwnedDiscardedLatestDetails.self
            let userInfo = [NotificationType.Key.obvContactGroup: obvContactGroup]
            let notification = Notification(name: NotificationType.name, userInfo: userInfo)
            self?.appNotificationCenter.post(notification)
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
            
            let NotificationType = ObvEngineNotification.ContactGroupJoinedHasUpdatedTrustedDetails.self
            let userInfo = [NotificationType.Key.obvContactGroup: obvContactGroup]
            let notification = Notification(name: NotificationType.name, userInfo: userInfo)
            self?.appNotificationCenter.post(notification)
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
            
            let NotificationType = ObvEngineNotification.NewPendingGroupMemberDeclinedStatus.self
            let userInfo = [NotificationType.Key.obvContactGroup: obvContactGroup]
            let notification = Notification(name: NotificationType.name, userInfo: userInfo)
            self?.appNotificationCenter.post(notification)
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
            
            let NotificationType = ObvEngineNotification.NewPendingGroupMemberDeclinedStatus.self
            let userInfo = [NotificationType.Key.obvContactGroup: obvContactGroup]
            let notification = Notification(name: NotificationType.name, userInfo: userInfo)
            self?.appNotificationCenter.post(notification)
        }
        
        
    }

    
    private func processMessageDecryptedNotification(messageId: MessageIdentifier, flowId: FlowIdentifier) {
        
        guard let createContextDelegate = createContextDelegate else {
            os_log("The create context delegate is not set", log: log, type: .fault)
            return
        }
        
        guard let networkFetchDelegate = networkFetchDelegate else {
            os_log("The network fetch delegate is not set", log: log, type: .fault)
            return
        }
        
        guard let identityDelegate = identityDelegate else {
            os_log("The network fetch delegate is not set", log: log, type: .fault)
            return
        }

        guard let flowDelegate = flowDelegate else {
            os_log("The flow delegate is not set", log: log, type: .fault)
            return
        }

        createContextDelegate.performBackgroundTask(flowId: flowId) { [weak self] (obvContext) in
            
            guard let _self = self else { return }
            
            let obvMessage: ObvMessage
            do {
                try obvMessage = ObvMessage(messageId: messageId, networkFetchDelegate: networkFetchDelegate, identityDelegate: identityDelegate, within: obvContext)
            } catch {
                os_log("Could not construct an ObvMessage from the network message and its attachments", log: _self.log, type: .fault, messageId.debugDescription)
                return
            }
            
            // We create a completion handler that, once called, ask to delete the message if possible.
            // It also specifies all the attachments that should be downloaded as soon as possible.
            // All the other attachments should not be downloaded now.
            
            let allAttachments = Set(obvMessage.attachments)
            let completionHandler: (Set<ObvAttachment>) -> Void = { attachmentsToDownloadNow in

                // Manage the attachments: download those tht should automatically downloaded.
                // For all the others, inform the flow delegate that the decision not to download these attachments has been taken.
                // This eventually allows to end the flow.
                
                let attachmentsToDownload = allAttachments.intersection(attachmentsToDownloadNow)
                let attachmentsNotToDownload = allAttachments.subtracting(attachmentsToDownloadNow)

                for attachment in attachmentsToDownload {
                    networkFetchDelegate.resumeDownloadOfAttachment(attachmentId: attachment.attachmentId, flowId: flowId)
                }

                for attachment in attachmentsNotToDownload {
                    flowDelegate.attachmentDownloadDecisionHasBeenTaken(attachmentId: attachment.attachmentId, flowId: flowId)
                }
                
                // Request the deletion of the message whenever possible
                
                createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
                    do {
                        networkFetchDelegate.markMessageForDeletion(messageId: obvMessage.messageId, within: obvContext)
                        try obvContext.save(logOnFailure: _self.log)
                    } catch {
                        os_log("Could not call deleteMessageWhenPossible", log: _self.log, type: .error)
                    }
                }
            }
            
            ObvEngineNotificationNew.newMessageReceived(obvMessage: obvMessage, completionHandler: completionHandler)
                .postOnBackgroundQueue(_self.queueForPostingNotificationsToTheApp, within: _self.appNotificationCenter)

        }
        
    }
    
    
    private func processAttachmentDownloadedNotification(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier) {
        
        os_log("We received an AttachmentDownloaded notification for the attachment %{public}@", log: log, type: .debug, attachmentId.debugDescription)
        
        // We first check whether all the attachments of the message have been downloaded

        guard let createContextDelegate = createContextDelegate else {
            os_log("The create context delegate is not set", log: log, type: .fault)
            return
        }

        guard let networkFetchDelegate = networkFetchDelegate else {
            os_log("The network fetch delegate is not set", log: log, type: .fault)
            return
        }
        
        guard let identityDelegate = identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            return
        }
        
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: randomFlowId) { [weak self] (obvContext) in
            
            guard let _self = self else { return }
            
            let obvAttachment: ObvAttachment
            do {
                try obvAttachment = ObvAttachment(attachmentId: attachmentId, networkFetchDelegate: networkFetchDelegate, identityDelegate: identityDelegate, within: obvContext)
            } catch {
                os_log("Could not construct an ObvAttachment of message %{public}@ (4)", log: _self.log, type: .fault, attachmentId.messageId.debugDescription)
                return
            }
            
            // We notify the app
            
            ObvEngineNotificationNew.attachmentDownloaded(obvAttachment: obvAttachment)
                .postOnBackgroundQueue(_self.queueForPostingNotificationsToTheApp, within: _self.appNotificationCenter)
        }
    }

    
    /// Thanks to a internal notification within the Oblivious Engine, this method gets called when an Oblivious channel is confirmed. Within this method, we send a similar notification through the default notification center so as to let the App be notified.
    private func processNewConfirmedObliviousChannelNotification(currentDeviceUid: UID, remoteCryptoIdentity: ObvCryptoIdentity, remoteDeviceUid: UID) {
        
        os_log("We received a NewConfirmedObliviousChannel notification", log: log, type: .info)
        
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
            
            // Determine the owned identity related to the current device uid
            
            guard let ownedCryptoIdentity = try? identityDelegate.getOwnedIdentityOfCurrentDeviceUid(currentDeviceUid, within: obvContext) else {
                os_log("The device uid does not correspond to any owned identity", log: _self.log, type: .fault)
                return
            }
            
            // The remote device might either be :
            // - an owned remote device
            // - a contact device
            // For each case, we have an appropriate notification to send
            
            if let remoteOwnedDevice = ObvRemoteOwnedDevice(remoteOwnedDeviceUid: remoteDeviceUid, ownedCryptoIdentity: ownedCryptoIdentity, identityDelegate: identityDelegate, within: obvContext) {
                
                os_log("The channel was created with a remote owned device %@", log: _self.log, type: .info, remoteOwnedDevice.description)
                
            } else if let contactDevice = ObvContactDevice(contactDeviceUid: remoteDeviceUid, contactCryptoIdentity: remoteCryptoIdentity, ownedCryptoIdentity: ownedCryptoIdentity, identityDelegate: identityDelegate, within: obvContext) {
                
                os_log("The channel was created with a contact device", log: _self.log, type: .info)
                
                ObvEngineNotificationNew.newObliviousChannelWithContactDevice(obvContactDevice: contactDevice)
                    .postOnBackgroundQueue(within: _self.appNotificationCenter)
                
            } else {
                
                assertionFailure()
                os_log("We could not determine any appropriate remote device", log: _self.log, type: .fault)
                
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
            
            DispatchQueue(label: "Queue for posting NewTrustedContactIdentity notifications").async {
                let NotificationType = ObvEngineNotification.NewTrustedContactIdentity.self
                let userInfo = [NotificationType.Key.contactIdentity: contactIdentity]
                let notification = Notification(name: NotificationType.name, userInfo: userInfo)
                _self.appNotificationCenter.post(notification)
            }
            
        }
    }
    
}
