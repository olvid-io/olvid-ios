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
import os.log
import CoreData
import ObvEngine
import CoreDataStack
import ObvCrypto
import OlvidUtils
import ObvTypes

final class PersistedDiscussionsUpdatesCoordinator {
    
    private let obvEngine: ObvEngine
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: PersistedDiscussionsUpdatesCoordinator.self))
    private var observationTokens = [NSObjectProtocol]()
    private var kvoTokens = [NSKeyValueObservation]()
    private let internalQueue: OperationQueue
    private let queueForLongRunningConcurrentOperations: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        queue.name = "PersistedDiscussionsUpdatesCoordinator queue for long running tasks"
        return queue
    }()

    private let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier)

    init(obvEngine: ObvEngine, operationQueue: OperationQueue) {
        self.obvEngine = obvEngine
        self.internalQueue = operationQueue
        listenToNotifications()
    }
    
    private static let errorDomain = "PersistedDiscussionsUpdatesCoordinator"
    private static func makeError(message: String) -> Error { NSError(domain: PersistedDiscussionsUpdatesCoordinator.errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { PersistedDiscussionsUpdatesCoordinator.makeError(message: message) }
    
    /// This array stores a completion handler associated to a sent message.
    /// This completion handler is called when the engine reports that the message has been sent (i.e., received by the server).
    /// This is essentially used for WebRTC messages.
    @Atomic() private var completionWhenMessageIsSent = [Data: () -> Void]()
    

    private func listenToNotifications() {
        
        defer {
            os_log("☎️ PersistedDiscussionsUpdatesCoordinator is listening to notifications", log: log, type: .info)
        }
        
        // Internal notifications
        
        observationTokens.append(contentsOf: [
            ObvMessengerCoreDataNotification.observeNewDraftToSend() { [weak self] (persistedDraftObjectID) in
                self?.processNewDraftToSendNotification(persistedDraftObjectID: persistedDraftObjectID)
            },
            ObvMessengerCoreDataNotification.observeNewPersistedObvContactDevice() { [weak self] (contactDeviceObjectID, _) in
                self?.processNewPersistedObvContactDeviceNotifications(persistedObvContactDeviceObjectID: contactDeviceObjectID)
            },
            ObvMessengerCoreDataNotification.observePersistedContactGroupHasUpdatedContactIdentities() { [weak self] (persistedContactGroupObjectID, insertedContacts, removedContacts) in
                self?.processPersistedContactGroupHasUpdatedContactIdentitiesNotification(persistedContactGroupObjectID: persistedContactGroupObjectID, insertedContacts: insertedContacts, removedContacts: removedContacts)
            },
            ObvMessengerInternalNotification.observePersistedMessageReceivedWasDeleted() { [weak self] (_, messageIdentifierFromEngine, ownedCryptoId, _, _) in
                self?.processPersistedMessageReceivedWasDeletedNotification(messageIdentifierFromEngine: messageIdentifierFromEngine, ownedCryptoId: ownedCryptoId)
            },
            ObvMessengerInternalNotification.observeUserRequestedDeletionOfPersistedMessage() { [weak self] (persistedMessageObjectID, deletionType) in
                self?.processUserRequestedDeletionOfPersistedMessageNotification(persistedMessageObjectID: persistedMessageObjectID, deletionType: deletionType)
            },
            ObvMessengerInternalNotification.observeUserRequestedDeletionOfPersistedDiscussion() { [weak self] (persistedDiscussionObjectID, deletionType, completionHandler) in
                self?.deletePersistedDiscussion(withObjectID: persistedDiscussionObjectID, deletionType: deletionType, requestedBy: nil, completionHandler: completionHandler)
            },
            ObvMessengerInternalNotification.observeMessagesAreNotNewAnymore() { [weak self] persistedMessageObjectIDs in
                self?.processMessagesAreNotNewAnymore(persistedMessageObjectIDs: persistedMessageObjectIDs)
            },
            ObvMessengerInternalNotification.observeAViewRequiresFyleMessageJoinWithStatusProgresses() { [weak self] (objectIDs) in
                self?.processAViewRequiresFyleMessageJoinWithStatusProgressesNotification(objectIDs: objectIDs)
            },
            ObvMessengerInternalNotification.observeNewObvMessageWasReceivedViaPushKitNotification { [weak self] (obvMessage) in
                self?.processNewObvMessageWasReceivedViaPushKitNotification(obvMessage: obvMessage)
            },
            ObvMessengerInternalNotification.observeNewWebRTCMessageToSend() { [weak self] (webrtcMessage, contactID, forStartingCall) in
                self?.processNewWebRTCMessageToSendNotification(webrtcMessage: webrtcMessage, contactID: contactID, forStartingCall: forStartingCall)
            },
            ObvMessengerInternalNotification.observeNewCallLogItem() { [weak self] objectID in
                self?.processNewCallLogItemNotification(objectID: objectID)
            },
            ObvMessengerInternalNotification.observeWipeAllMessagesThatExpiredEarlierThanNow { [weak self] (launchedByBackgroundTask, completionHandler) in
                self?.processWipeAllMessagesThatExpiredEarlierThanNow(launchedByBackgroundTask: launchedByBackgroundTask, completionHandler: completionHandler)
            },
            ObvMessengerInternalNotification.observeCurrentUserActivityDidChange() { [weak self] (previousUserActivity, currentUserActivity) in
                if let previousDiscussionObjectID = previousUserActivity.persistedDiscussionObjectID, previousDiscussionObjectID != currentUserActivity.persistedDiscussionObjectID {
                    self?.userLeftDiscussion(discussionObjectID: previousDiscussionObjectID)
                }
                if let currentDiscussionObjectID = currentUserActivity.persistedDiscussionObjectID, currentDiscussionObjectID != previousUserActivity.persistedDiscussionObjectID {
                    self?.userEnteredDiscussion(discussionObjectID: currentDiscussionObjectID)
                }
            },
            ObvMessengerInternalNotification.observeUserWantsToReadReceivedMessagesThatRequiresUserAction { [weak self] (persistedMessageObjectIDs) in
                self?.processUserWantsToReadReceivedMessagesThatRequiresUserActionNotification(persistedMessageObjectIDs: persistedMessageObjectIDs)
            },
            ObvMessengerInternalNotification.observePersistedMessageReceivedWasRead { [weak self] (persistedMessageReceivedObjectID) in
                self?.processPersistedMessageReceivedWasReadNotification(persistedMessageReceivedObjectID: persistedMessageReceivedObjectID)
            },
            ObvMessengerCoreDataNotification.observeAReadOncePersistedMessageSentWasSent { [weak self] (persistedMessageSentObjectID, persistedDiscussionObjectID) in
                self?.processAReadOncePersistedMessageSentWasSentNotification(persistedMessageSentObjectID: persistedMessageSentObjectID, persistedDiscussionObjectID: persistedDiscussionObjectID)
            },
            ObvMessengerInternalNotification.observeUserWantsToSetAndShareNewDiscussionSharedExpirationConfiguration { [weak self] (persistedDiscussionObjectID, expirationJSON, ownedCryptoId) in
                self?.processUserWantsToSetAndShareNewDiscussionSharedExpirationConfiguration(persistedDiscussionObjectID: persistedDiscussionObjectID, expirationJSON: expirationJSON, ownedCryptoId: ownedCryptoId)
            },
            ObvMessengerInternalNotification.observePersistedDiscussionSharedConfigurationShouldBeSent { [weak self] (persistedDiscussionObjectID) in
                self?.processPersistedDiscussionSharedConfigurationShouldBeSentNotification(persistedDiscussionObjectID: persistedDiscussionObjectID)
            },
            ObvMessengerInternalNotification.observeApplyAllRetentionPoliciesNow { [weak self] (launchedByBackgroundTask, completionHandler) in
                self?.processApplyAllRetentionPoliciesNowNotification(launchedByBackgroundTask: launchedByBackgroundTask, completionHandler: completionHandler)
            },
            ObvMessengerCoreDataNotification.observeAnOldDiscussionSharedConfigurationWasReceived { [weak self] (persistedDiscussionObjectID) in
                self?.processAnOldDiscussionSharedConfigurationWasReceivedNotification(persistedDiscussionObjectID: persistedDiscussionObjectID)
            },
            ObvMessengerInternalNotification.observeUserWantsToSendEditedVersionOfSentMessage { [weak self] (sentMessageObjectID, newTextBody) in
                self?.processUserWantsToSendEditedVersionOfSentMessage(sentMessageObjectID: sentMessageObjectID, newTextBody: newTextBody)
            },
            ObvMessengerInternalNotification.observeUserWantsToMarkAllMessagesAsNotNewWithinDiscussion { [weak self] (persistedDiscussionObjectID, completionHandler) in
                self?.processUserWantsToMarkAllMessagesAsNotNewWithinDiscussionNotification(persistedDiscussionObjectID: persistedDiscussionObjectID, completionHandler: completionHandler)
            },
            ObvMessengerInternalNotification.observeUserWantsToRemoveDraftFyleJoin { [weak self] (draftFyleJoinObjectID) in
                self?.processUserWantsToRemoveDraftFyleJoinNotification(draftFyleJoinObjectID: draftFyleJoinObjectID)
            },
            ObvMessengerCoreDataNotification.observeUserWantsToUpdateDiscussionLocalConfiguration { [weak self] (value, localConfigurationObjectID) in
                self?.processUserWantsToUpdateDiscussionLocalConfigurationNotification(with: value, localConfigurationObjectID: localConfigurationObjectID)
            },
            ObvMessengerInternalNotification.observeUserWantsToUpdateLocalConfigurationOfDiscussion { [weak self] (value, persistedDiscussionObjectID) in
                self?.processUserWantsToUpdateLocalConfigurationOfDiscussionNotification(with: value, persistedDiscussionObjectID: persistedDiscussionObjectID)
            },
            ObvMessengerCoreDataNotification.observePersistedContactWasDeleted { [weak self ] _, _ in
                self?.processPersistedContactWasDeletedNotification()
            },
            NewSingleDiscussionNotification.observeInsertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty { [weak self] (discussionObjectID, markAsRead) in
                self?.processInsertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty(discussionObjectID: discussionObjectID, markAsRead: markAsRead)
            },
            ObvMessengerInternalNotification.observeUserWantsToUpdateReaction { [weak self] messageObjectID, emoji in
                self?.processUserWantsToUpdateReaction(messageObjectID: messageObjectID, emoji: emoji)
            },
            ObvMessengerInternalNotification.observeInsertDebugMessagesInAllExistingDiscussions { [weak self] in
                self?.processInsertDebugMessagesInAllExistingDiscussions()
            },
            ObvMessengerInternalNotification.observeCleanExpiredMuteNotficationsThatExpiredEarlierThanNow { [weak self] in
                self?.cleanExpiredMuteNotificationsSetting()
            },
            ObvMessengerCoreDataNotification.observeAOneToOneDiscussionTitleNeedsToBeReset { [weak self] ownedIdentityObjectID in
                self?.processAOneToOneDiscussionTitleNeedsToBeReset(ownedIdentityObjectID: ownedIdentityObjectID)
            },
        ])
        
        // Internal VoIP notifications
        
        observationTokens.append(contentsOf: [
            VoIPNotification.observeReportCallEvent { [weak self] (callUUID, callReport, groupId, ownedCryptoId) in
                self?.processReportCallEvent(callUUID: callUUID, callReport: callReport, groupId: groupId, ownedCryptoId: ownedCryptoId)
            },
            VoIPNotification.observeCallHasBeenUpdated { [weak self] call, updateKind in
                self?.processCallHasBeenUpdated(call: call, updateKind: updateKind)
            },
        ])
        
        // Draft specific notifications
        
        observationTokens.append(contentsOf: [
            NewSingleDiscussionNotification.observeUserWantsToReplyToMessage { [weak self] messageObjectID, draftObjectID in
                self?.processUserWantsToReplyToMessage(messageObjectID: messageObjectID, draftObjectID: draftObjectID)
            },
            NewSingleDiscussionNotification.observeUserWantsToRemoveReplyToMessage { [weak self] draftObjectID in
                self?.processUserWantsToRemoveReplyToMessage(draftObjectID: draftObjectID)
            },
            NewSingleDiscussionNotification.observeUserWantsToAddAttachmentsToDraft { [weak self] draftObjectID, itemProviders, completionHandler in
                self?.processUserWantsToAddAttachmentsToDraft(draftObjectID: draftObjectID, itemProviders: itemProviders, completionHandler: completionHandler)
            },
            NewSingleDiscussionNotification.observeUserWantsToAddAttachmentsToDraftFromURLs { [weak self] draftObjectID, urls, completionHandler in
                self?.processUserWantsToAddAttachmentsToDraft(draftObjectID: draftObjectID, urls: urls, completionHandler: completionHandler)
            },
            NewSingleDiscussionNotification.observeUserWantsToDeleteAllAttachmentsToDraft { [weak self] draftObjectID in
                self?.processUserWantsToDeleteAllAttachmentsToDraft(draftObjectID: draftObjectID)
            },
            NewSingleDiscussionNotification.observeUserWantsToSendDraft { [weak self] draftObjectID, textBody in
                self?.processUserWantsToSendDraft(draftObjectID: draftObjectID, textBody: textBody)
            },
            NewSingleDiscussionNotification.observeUserWantsToSendDraftWithOneAttachement { [weak self] draftObjectID, attachementsURL in
                self?.processUserWantsToSendDraftWithAttachements(draftObjectID: draftObjectID, attachementsURL: attachementsURL)
            },
            NewSingleDiscussionNotification.observeUserWantsToUpdateDraftExpiration { [weak self] draftObjectID, value in
                self?.processUserWantsToUpdateDraftExpiration(draftObjectID: draftObjectID, value: value)
            },
            NewSingleDiscussionNotification.observeUserWantsToUpdateDraftBody { [weak self] draftObjectID, value in
                self?.processUserWantsToUpdateDraftBody(draftObjectID: draftObjectID, value: value)
            },
        ])
        
        // ObvEngine Notifications
        
        observationTokens.append(contentsOf: [
            ObvEngineNotificationNew.observeNewMessageReceived(within: NotificationCenter.default) { [weak self] (obvMessage, completionHandler) in
                self?.processNewMessageReceivedNotification(obvMessage: obvMessage, completionHandler: completionHandler)
            },
            ObvEngineNotificationNew.observeMessageWasAcknowledged(within: NotificationCenter.default) { [weak self] (ownedIdentity, messageIdentifierFromEngine, timestampFromServer, isAppMessageWithUserContent, isVoipMessage) in
                self?.processMessageWasAcknowledgedNotification(ownedIdentity: ownedIdentity, messageIdentifierFromEngine: messageIdentifierFromEngine, timestampFromServer: timestampFromServer, isAppMessageWithUserContent: isAppMessageWithUserContent, isVoipMessage: isVoipMessage)
            },
            ObvEngineNotificationNew.observeAttachmentWasAcknowledgedByServer(within: NotificationCenter.default) { [weak self] (messageIdentifierFromEngine, attachmentNumber) in
                self?.processAttachmentWasAcknowledgedByServerNotification(messageIdentifierFromEngine: messageIdentifierFromEngine, attachmentNumber: attachmentNumber)
            },
            ObvEngineNotificationNew.observeAttachmentUploadNewProgress(within: NotificationCenter.default) { [weak self] (messageIdentifierFromEngine, attachmentNumber, newProgress) in
                self?.processAttachmentUploadNewProgressNotification(messageIdentifierFromEngine: messageIdentifierFromEngine, attachmentNumber: attachmentNumber, newProgress: newProgress)
            },
            ObvEngineNotificationNew.observeInboxAttachmentNewProgress(within: NotificationCenter.default) { [weak self] (obvAttachment, newProgress) in
                self?.processInboxAttachmentNewProgressNotification(obvAttachment: obvAttachment, newProgress: newProgress)
            },
            ObvEngineNotificationNew.observeAttachmentDownloadCancelledByServer(within: NotificationCenter.default) { [weak self] (obvAttachment) in
                self?.processAttachmentDownloadCancelledByServerNotification(obvAttachment: obvAttachment)
            },
            ObvEngineNotificationNew.observeCannotReturnAnyProgressForMessageAttachments(within: NotificationCenter.default) { [weak self] (messageIdentifierFromEngine) in
                self?.processCannotReturnAnyProgressForMessageAttachmentsNotification(messageIdentifierFromEngine: messageIdentifierFromEngine)
            },
            ObvEngineNotificationNew.observeAttachmentDownloaded(within: NotificationCenter.default) { [weak self] (obvAttachment) in
                self?.processAttachmentDownloadedNotification(obvAttachment: obvAttachment)
            },
            ObvEngineNotificationNew.observeNewObvReturnReceiptToProcess(within: NotificationCenter.default) { [weak self] (obvReturnReceipt) in
                self?.processNewObvReturnReceiptToProcessNotification(obvReturnReceipt: obvReturnReceipt)
            },
            ObvEngineNotificationNew.observeOutboxMessagesAndAllTheirAttachmentsWereAcknowledged(within: NotificationCenter.default) { [weak self] (messageIdsAndTimestampsFromServer) in
                self?.processOutboxMessagesAndAllTheirAttachmentsWereAcknowledgedNotification(messageIdsAndTimestampsFromServer: messageIdsAndTimestampsFromServer)
            },
            ObvEngineNotificationNew.observeContactWasDeleted(within: NotificationCenter.default) { [weak self] (ownedCryptoId, contactCryptoId) in
                self?.processContactWasDeletedNotification(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
            },
            ObvEngineNotificationNew.observeMessageExtendedPayloadAvailable(within: NotificationCenter.default) { [weak self] (obvMessage, extendedMessagePayload) in
                self?.processMessageExtendedPayloadAvailable(obvMessage: obvMessage, extendedMessagePayload: extendedMessagePayload)
            },
            ObvEngineNotificationNew.observeContactWasRevokedAsCompromisedWithinEngine(within: NotificationCenter.default) { [weak self] obvContactIdentity in
                self?.processContactWasRevokedAsCompromisedWithinEngine(obvContactIdentity: obvContactIdentity)
            },
            ObvEngineNotificationNew.observeNewUserDialogToPresent(within: NotificationCenter.default) { [weak self] obvDialog in
                self?.processNewUserDialogToPresent(obvDialog: obvDialog)
            },
            ObvEngineNotificationNew.observeAPersistedDialogWasDeleted(within: NotificationCenter.default) { [weak self] uuid in
                self?.processAPersistedDialogWasDeleted(uuid: uuid)
            },
        ])

        // Bootstrapping
        
        observeAppStateChangedNotifications()

        // Share extension
        observeNewSentMessagesAddedByExtension()
    }
 
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

}


// MARK: - Bootstrapping

extension PersistedDiscussionsUpdatesCoordinator {
    
    private func observeAppStateChangedNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeAppStateChanged() { [weak self] (previousState, currentState) in
            
            if !previousState.isInitializedAndActive && currentState.isInitializedAndActive {
                self?.bootstrapMessagesDecryptedWithinNotificationExtension()
                self?.bootstrapProcessUnprocessedPersistedMessageSent()
                self?.deleteEmptyLockedDiscussion()
                self?.trashOrphanedFilesFoundInTheFylesDirectory()
                self?.deleteRecipientInfosThatHaveNoMsgIdentifierFromEngineAndAssociatedToDeletedContact()
                // No need to delete orphaned one to one discussions (i.e., without contact), they are cascade deleted
                // No need to delete orphaned group discussions (i.e., without contact group), they are cascade deleted
                // No need to delete orphaned PersistedMessageTimestampedMetadata, i.e., without message), they are cascade deleted
                self?.bootstrapMessagesToBeWiped(preserveReceivedMessages: true)
                self?.bootstrapWipeAllMessagesThatExpiredEarlierThanNow()
                self?.deleteOrphanedExpirations()
                self?.deleteOldOrOrphanedRemoteDeleteAndEditRequests()
                self?.deleteOldOrOrphanedPendingReactions()
                self?.cleanExpiredMuteNotificationsSetting()
                self?.cleanOrphanedPersistedMessageTimestampedMetadata()
                self?.synchronizeAllOneToOneDiscussionTitlesWithContactNameOperation()
            }
            
            if currentState.iOSAppState == .mayResignActive {
                self?.cleanJsonMessagesSavedByNotificationExtension()
                self?.bootstrapMessagesToBeWiped(preserveReceivedMessages: false)
            }
            
            if (previousState.isInitializedAndActive, currentState.isInitializedAndActive) == (false, true), let currentPersistedDiscussionObjectID = ObvUserActivitySingleton.shared.currentPersistedDiscussionObjectID {
                self?.userEnteredDiscussion(discussionObjectID: currentPersistedDiscussionObjectID)
            }
            
        })
    }

    private func observeNewSentMessagesAddedByExtension() {
        guard let userDefaults = self.userDefaults else {
            os_log("The user defaults database is not set", log: log, type: .fault)
            return
        }
        let token = userDefaults.observe(\.objectsModifiedByShareExtension) { (userDefaults, change) in
            DispatchQueue.init(label: "Queue for observing objectsModifiedByShareExtension").async {
                guard !userDefaults.objectsModifiedByShareExtensionURLAndEntityName.isEmpty else { return }
                os_log("📤 Observe %{public}@ object(s) modified by share extension to refresh into the view context.", log: self.log, type: .info, String(userDefaults.objectsModifiedByShareExtensionURLAndEntityName.count))
                for (url, entityName) in userDefaults.objectsModifiedByShareExtensionURLAndEntityName {
                    let op = RefreshUpdatedObjectsModifiedByShareExtensionOperation(objectURL: url, entityName: entityName)
                    self.internalQueue.addOperations([op], waitUntilFinished: true)
                    op.logReasonIfCancelled(log: self.log)
                }
                userDefaults.resetObjectsModifiedByShareExtension()
            }
        }
        kvoTokens.append(token)

    }
    
    
    private func deleteOldOrOrphanedRemoteDeleteAndEditRequests() {
        let op1 = DeleteOldOrOrphanedRemoteDeleteAndEditRequestsOperation()
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
    }


    private func deleteOldOrOrphanedPendingReactions() {
        let op = DeleteOldOrOrphanedPendingReactionsOperation()
        let composedOp = CompositionOfOneContextualOperation(op1: op, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
    }


    private func deleteOrphanedExpirations() {
        let op = DeleteOrphanedExpirationsOperation()
        internalQueue.addOperations([op], waitUntilFinished: true)
        op.logReasonIfCancelled(log: log)
    }
    
    
    private func cleanJsonMessagesSavedByNotificationExtension() {
        let op = DeleteAllJsonMessagesSavedByNotificationExtension()
        internalQueue.addOperations([op], waitUntilFinished: true)
        op.logReasonIfCancelled(log: log)
    }
    
    
    /// When the notification extension successfully decrypts a notification, it recovers an ObvMessage. This message is
    /// then serialized as a json and saved in an appropriate directory before showing the actual user notifications.
    /// Within this method, we loop through all these json files in order to immediately populate the local database of messages.
    /// Once we are done, we delete all the json files that we have processed.
    /// Note that if a message with the same uid from server already exists, we do *not* modify it using the content of the json.
    private func bootstrapMessagesDecryptedWithinNotificationExtension() {
        
        assert(OperationQueue.current != internalQueue)
        
        guard let urls = try? FileManager.default.contentsOfDirectory(at: ObvMessengerConstants.containerURL.forMessagesDecryptedWithinNotificationExtension, includingPropertiesForKeys: nil) else {
            os_log("📮 We could not list the serialized json files saved by the notification extension", log: log, type: .error)
            return
        }

        os_log("📮 Find %{public}@ message%{public}@ saved by the notification extension.", log: log, type: .info, String(urls.count), urls.count == 1 ? "" : "s")

        let obvMessages: [ObvMessage] = urls.compactMap { url in
            guard let serializedObvMessage = try? Data(contentsOf: url) else {
                os_log("📮 Could not read the content of %{public}@. This file will be deleted.", log: log, type: .error)
                return nil
            }
            guard let obvMessage = try? ObvMessage.decodeFromJson(data: serializedObvMessage) else {
                os_log("📮 Could not decode the content of %{public}@. This file will be deleted.", log: log, type: .error)
                return nil
            }
            return obvMessage
        }
        
        for url in urls {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                os_log("📮 Failed to delete a notification content: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
        }

        for obvMessage in obvMessages {
            processReceivedObvMessage(obvMessage, overridePreviousPersistedMessage: false, completionHandler: nil)
        }
        
    }
    

    /// This method process all the messages that are still unprocessed
    private func bootstrapProcessUnprocessedPersistedMessageSent() {
        assert(OperationQueue.current != internalQueue)
        let log = self.log
        ObvStack.shared.performBackgroundTask { [weak self] (context) in

            let infosOfUnprocessedSentMessages: [PersistedMessageSentRecipientInfos]
            do {
                infosOfUnprocessedSentMessages = try PersistedMessageSentRecipientInfos.getAllUnprocessed(within: context)
            } catch let error {
                os_log("Could not get all unprocessed message sent recipients infos: %{public}@", log: log, type: .fault, error.localizedDescription)
                assert(false)
                return
            }

            let discussionsWithUnprocessedMessages = Set(infosOfUnprocessedSentMessages.map { $0.messageSent.discussion })

            guard !discussionsWithUnprocessedMessages.isEmpty else { return }

            for discussion in discussionsWithUnprocessedMessages {
                self?.sendUnprocessedMessages(within: discussion)
            }

        }
    }
    
    
    private func bootstrapMessagesToBeWiped(preserveReceivedMessages: Bool) {
        do {
            let op1 = WipeOrDeleteReadOnceMessagesOperation(preserveReceivedMessages: preserveReceivedMessages, restrictToDiscussionWithObjectID: nil)
            let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
            internalQueue.addOperations([composedOp], waitUntilFinished: true)
            composedOp.logReasonIfCancelled(log: log)
        }
        do {
            let op1 = DeleteAllOrphanedFyleMessageJoinWithStatusOperation()
            let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
            internalQueue.addOperations([composedOp], waitUntilFinished: true)
            composedOp.logReasonIfCancelled(log: log)
        }
        do {
            let op1 = DeleteAllOrphanedFylesAndMoveAssociatedFilesToTrashOperation()
            let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
            internalQueue.addOperations([composedOp], waitUntilFinished: true)
            composedOp.logReasonIfCancelled(log: log)
        }
        ObvMessengerInternalNotification.trashShouldBeEmptied
            .postOnDispatchQueue()
    }

    
    private func bootstrapWipeAllMessagesThatExpiredEarlierThanNow() {
        let op1 = WipeExpiredMessagesOperation(launchedByBackgroundTask: false)
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
    }

    private func cleanExpiredMuteNotificationsSetting() {
        let op1 = CleanExpiredMuteNotficationEndDatesOperation()
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
    }
    
    
    private func processAOneToOneDiscussionTitleNeedsToBeReset(ownedIdentityObjectID: TypeSafeManagedObjectID<PersistedObvOwnedIdentity>) {
        let op1 = SynchronizeOneToOneDiscussionTitlesWithContactNameOperation(ownedIdentityObjectID: ownedIdentityObjectID)
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
    }
    
        
    private func cleanOrphanedPersistedMessageTimestampedMetadata() {
        let op1 = CleanOrphanedPersistedMessageTimestampedMetadataOperation()
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
    }
    
    
    private func synchronizeAllOneToOneDiscussionTitlesWithContactNameOperation() {
        let log = self.log
        ObvStack.shared.performBackgroundTask { [weak self] context in
            let ownedIdentities: [PersistedObvOwnedIdentity]
            do {
                ownedIdentities = try PersistedObvOwnedIdentity.getAll(within: context)
            } catch {
                os_log("Could not get all owned identities: %{public}@", log: log, type: .fault, error.localizedDescription)
                return
            }
            let flowId = FlowIdentifier()
            let ops = ownedIdentities.map({ SynchronizeOneToOneDiscussionTitlesWithContactNameOperation(ownedIdentityObjectID: $0.typedObjectID) })
            let composedOps = ops.map({ CompositionOfOneContextualOperation(op1: $0, contextCreator: ObvStack.shared, log: log, flowId: flowId) })
            self?.internalQueue.addOperations(composedOps, waitUntilFinished: true)
            composedOps.forEach { composedOp in
                composedOp.logReasonIfCancelled(log: log)
            }
        }
    }
    
    private func deleteEmptyLockedDiscussion() {
        assert(OperationQueue.current != internalQueue)
        let op1 = DeleteAllEmptyLockedDiscussionsOperation()
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
    }
    
    
    /// This method aynchronously lists all the files of the Fyles directory and compare this list to the list of entries of the `Fyles` database.
    /// Each file that cannot be found is a candidate for being trashed. We do not trash the file right away though, since we are doing this work
    /// asynchronously : some other operation may have created a `Fyle` while we were doing the comparison. Instead, we pass
    /// the list of candidates to an appropriate operations that will perform checks and trash the files if appropriate, in a synchronous way.
    private func trashOrphanedFilesFoundInTheFylesDirectory() {

        let log = self.log

        ObvStack.shared.performBackgroundTask { [weak self] (context) in
            
            let namesOfFilesOnDisk: Set<String>
            do {
                let allFilesInFyle = try Set(FileManager.default.contentsOfDirectory(at: ObvMessengerConstants.containerURL.forFyles, includingPropertiesForKeys: nil))
                namesOfFilesOnDisk = Set(allFilesInFyle.map({ $0.lastPathComponent }))
            } catch {
                os_log("Could not list the files of the Fyles directory: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
                                    
            let namesOfFilesToKeep: Set<String>
            do {
                namesOfFilesToKeep = Set(try Fyle.getAllFilenames(within: context))
            } catch {
                os_log("Could not get all Fyle's filenames: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }

            let namesOfFilesCandidatesForTrash = namesOfFilesOnDisk.subtracting(namesOfFilesToKeep)
            let urlsOfFilesCandidatesForTrash = Set(namesOfFilesCandidatesForTrash.map({ Fyle.getFileURL(lastPathComponent: $0) }))
            
            guard !urlsOfFilesCandidatesForTrash.isEmpty else {
                return
            }

            let op = TrashFilesThatHaveNoAssociatedFyleOperation(urlsCandidatesForTrash: urlsOfFilesCandidatesForTrash)
            self?.internalQueue.addOperations([op], waitUntilFinished: true)
            op.logReasonIfCancelled(log: log)

            ObvMessengerInternalNotification.trashShouldBeEmptied
                .postOnDispatchQueue()

        }
        
    }

}
        
        
        
// MARK: - Observing Internal notifications

extension PersistedDiscussionsUpdatesCoordinator {
    
    private func deleteRecipientInfosThatHaveNoMsgIdentifierFromEngineAndAssociatedToDeletedContact() {
        let op = DeletePersistedMessageSentRecipientInfosWithoutMessageIdentifierFromEngineAndAssociatedToDeletedContactIdentityOperation()
        internalQueue.addOperations([op], waitUntilFinished: true)
        op.logReasonIfCancelled(log: log)
    }
}


// MARK: - Processing Internal notifications

extension PersistedDiscussionsUpdatesCoordinator {
    
    /// When receiving a `NewDraftToSend` notification, we turn the draft into a `PersistedMessageSent`, reset the draft, and save the context.
    /// If this succeeds, we send the new (unprocessed)  `PersistedMessageSent`.
    private func processNewDraftToSendNotification(persistedDraftObjectID: TypeSafeManagedObjectID<PersistedDraft>) {
        assert(OperationQueue.current != internalQueue)
        let op1 = CreateUnprocessedPersistedMessageSentFromPersistedDraftOperation(persistedDraftObjectID: persistedDraftObjectID)
        let op2 = ComputeExtendedPayloadOperation(provider: op1)
        let op3 = SendUnprocessedPersistedMessageSentOperation(unprocessedPersistedMessageSentProvider: op1, extendedPayloadProvider: op2, obvEngine: obvEngine)
        let op4 = MarkAllMessagesAsNotNewWithinDiscussionOperation(persistedDraftObjectID: persistedDraftObjectID )
        let composedOp = CompositionOfFourContextualOperations(op1: op1, op2: op2, op3: op3, op4: op4, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
        guard !composedOp.isCancelled else {
            NewSingleDiscussionNotification.draftCouldNotBeSent(persistedDraftObjectID: persistedDraftObjectID)
                .postOnDispatchQueue()
            assertionFailure()
            return
        }
    }

    
    private func processInsertDebugMessagesInAllExistingDiscussions() {
        #if DEBUG
        assert(OperationQueue.current != internalQueue)
        var objectIDs = [(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>)]()
        ObvStack.shared.performBackgroundTaskAndWait { context in
            guard let discussions = try? PersistedDiscussion.getAllSortedByTimestampOfLastMessage(within: context) else { assertionFailure(); return }
            objectIDs = discussions.map({ ($0.typedObjectID, $0.draft.typedObjectID) })
        }
        let numberOfMessagesToInsert = 100
        for objectID in objectIDs {
            for messageNumber in 0..<numberOfMessagesToInsert {
                debugPrint("Message \(messageNumber) out of \(numberOfMessagesToInsert)")
                if Bool.random() {
                    let op1 = CreateRandomDraftDebugOperation(discussionObjectID: objectID.discussionObjectID)
                    let op2 = CreateUnprocessedPersistedMessageSentFromPersistedDraftOperation(persistedDraftObjectID: objectID.draftObjectID)
                    let op3 = MarkSentMessageAsDeliveredDebugOperation()
                    op3.addDependency(op2)
                    let composedOp = CompositionOfThreeContextualOperations(op1: op1, op2: op2, op3: op3, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
                    internalQueue.addOperations([composedOp], waitUntilFinished: true)
                    composedOp.logReasonIfCancelled(log: log)
                    guard !composedOp.isCancelled else { assertionFailure(); return }
                } else {
                    let op1 = CreateRandomMessageReceivedDebugOperation(discussionObjectID: objectID.discussionObjectID)
                    let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
                    internalQueue.addOperations([composedOp], waitUntilFinished: true)
                    composedOp.logReasonIfCancelled(log: log)
                    guard !composedOp.isCancelled else { assertionFailure(); return }
                }
            }
        }
        #endif
    }

    /// When receiving a NewPersistedObvContactDevice, we check whether there exists "related" unsent message in the .unprocessed status. If this is the case, we can now post them.
    private func processNewPersistedObvContactDeviceNotifications(persistedObvContactDeviceObjectID: NSManagedObjectID) {
        
        let log = self.log
        
        ObvStack.shared.performBackgroundTask { [weak self] (context) in
            
            guard let contactDevice = try? context.existingObject(with: persistedObvContactDeviceObjectID) as? PersistedObvContactDevice else {
                return
            }
            
            guard let contactIdentity = contactDevice.identity else {
                os_log("Could not find contact identity. This is ok if it was just deleted.", log: log, type: .error)
                return
            }
            
            // Send all the unprocessed messages waiting in the one2one discussion with the contact.
            // The discussion does not exist if the contact is not oneToOne
            if let oneToOneDiscussion = try? contactIdentity.oneToOneDiscussion {
                self?.sendUnprocessedMessages(within: oneToOneDiscussion)
            }
            
            // Send all the unprocessed messages waiting in all the contact group discussions we have with this contact
            for contactGroup in contactIdentity.contactGroups {
                self?.sendUnprocessedMessages(within: contactGroup.discussion)
            }
            
        }

    }

    
    /// When receiving a `PersistedContactGroupHasUpdatedContactIdentities` notification, we check whether there exists unprocessed (unsent) messages within the corresponding group discussion. If this is the case, we can now post them.
    /// We also insert the all the system messages of category `.contactJoinedGroup` and `.contactLeftGroup` as appropriate.
    private func processPersistedContactGroupHasUpdatedContactIdentitiesNotification(persistedContactGroupObjectID: NSManagedObjectID, insertedContacts: Set<PersistedObvContactIdentity>, removedContacts: Set<PersistedObvContactIdentity>) {
        // Task 1: Send unprocessed messages within this group and recover the persistedDiscussionObjectID
        var persistedDiscussionObjectID: NSManagedObjectID?
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            guard let contactGroup = try? context.existingObject(with: persistedContactGroupObjectID) as? PersistedContactGroup else {
                persistedDiscussionObjectID = nil
                return
            }
            let groupDiscussion = contactGroup.discussion
            persistedDiscussionObjectID = groupDiscussion.objectID
            guard groupDiscussion.hasAtLeastOneRemoteContactDevice() else {
                return
            }
            sendUnprocessedMessages(within: groupDiscussion)
        }
        guard let discussionObjectID = persistedDiscussionObjectID else { return }
        // Task 2: Insert a system message of category "contactJoinedGroup"
        do {
            let ops = insertedContacts.map({ InsertPersistedMessageSystemIntoDiscussionOperation(
                                            persistedMessageSystemCategory: .contactJoinedGroup,
                                            persistedDiscussionObjectID: discussionObjectID,
                                            optionalContactIdentityObjectID: $0.objectID,
                                            optionalCallLogItemObjectID: nil) })
            internalQueue.addOperations(ops, waitUntilFinished: true)
            for op in ops { op.logReasonIfCancelled(log: log) }
        }
        // Task 3: Insert a system message of category "contactLeftGroup"
        do {
            let ops = removedContacts.map({ InsertPersistedMessageSystemIntoDiscussionOperation(
                                            persistedMessageSystemCategory: .contactLeftGroup,
                                            persistedDiscussionObjectID: discussionObjectID,
                                            optionalContactIdentityObjectID: $0.objectID,
                                            optionalCallLogItemObjectID: nil) })
            internalQueue.addOperations(ops, waitUntilFinished: true)
            for op in ops { op.logReasonIfCancelled(log: log) }
        }
        // Task 4: In case the group is owned, send the shared configuration of the group discussion to all group members
        do {
            ObvStack.shared.performBackgroundTaskAndWait { (context) in
                do {
                    guard try PersistedContactGroupOwned.get(objectID: persistedContactGroupObjectID, within: context) as? PersistedContactGroupOwned != nil else { return }
                } catch {
                    os_log("Could not get PersistedContactGroupOwned: %{public}@", log: log, type: .fault, error.localizedDescription)
                    return
                }
                let op = SendPersistedDiscussionSharedConfigurationOperation(persistedDiscussionObjectID: discussionObjectID, obvEngine: obvEngine)
                internalQueue.addOperations([op], waitUntilFinished: true)
                op.logReasonIfCancelled(log: log)
            }
        }
    }

    
    /// When notified that a `PersistedMessageReceived` has been deleted, we cancel any potential download within the engine
    private func processPersistedMessageReceivedWasDeletedNotification(messageIdentifierFromEngine: Data, ownedCryptoId: ObvCryptoId) {
        do {
            try obvEngine.cancelDownloadOfMessage(withIdentifier: messageIdentifierFromEngine, ownedCryptoId: ownedCryptoId)
        } catch {
            os_log("Could not cancel the download of a message that we just deleted from the app", log: log, type: .fault)
            assertionFailure()
            return
        }
    }

    
    private func processUserRequestedDeletionOfPersistedMessageNotification(persistedMessageObjectID: NSManagedObjectID, deletionType: DeletionType) {
        
        switch deletionType {
        case .local:
            break // We will do the work below
        case .global:
            let op = SendGlobalDeleteMessagesJSONOperation(persistedMessageObjectIDs: [persistedMessageObjectID], obvEngine: obvEngine)
            internalQueue.addOperations([op], waitUntilFinished: true)
            op.logReasonIfCancelled(log: log)
        }
        
        do {
            let op = CancelUploadOrDownloadOfPersistedMessageOperation(persistedMessageObjectID: persistedMessageObjectID, obvEngine: obvEngine)
            internalQueue.addOperations([op], waitUntilFinished: true)
            op.logReasonIfCancelled(log: log)
        }
        do {
            let op1 = DeletePersistedMessageOperation(persistedMessageObjectID: persistedMessageObjectID)
            let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
            internalQueue.addOperations([composedOp], waitUntilFinished: true)
            composedOp.logReasonIfCancelled(log: log)
        }
        do {
            let op1 = DeleteAllOrphanedFyleMessageJoinWithStatusOperation()
            let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
            internalQueue.addOperations([composedOp], waitUntilFinished: true)
            composedOp.logReasonIfCancelled(log: log)
        }
        do {
            let op1 = DeleteAllOrphanedFylesAndMoveAssociatedFilesToTrashOperation()
            let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
            internalQueue.addOperations([composedOp], waitUntilFinished: true)
            composedOp.logReasonIfCancelled(log: log)
        }
        ObvMessengerInternalNotification.trashShouldBeEmptied
            .postOnDispatchQueue()
    }

    
    /// This methods properly deletes a discussion. It is typically called when the user requests the deletion of all messages within a discussion. But it is also called when a contact performs a global delete of a discussion, in which case `requestedBy` is non `nil`.
    private func deletePersistedDiscussion(withObjectID persistedDiscussionObjectID: NSManagedObjectID, deletionType: DeletionType, requestedBy: (obvContactId: ObvContactIdentity, messageUploadTimestampFromServer: Date)?, completionHandler: @escaping (Bool) -> Void) {
        
        assert(OperationQueue.current != internalQueue)
        
        guard requestedBy == nil || deletionType == .local else {
            // When performing a deletion requested by a contact, we make sure not to perfom "another" global deletion, only a local one
            assertionFailure()
            return
        }

        /*
         * If Alice sends us a message, then deletes the discussion, the following occurs:
         * 1. A user notification is received (and displayed), and a serialized version is saved, ready to be processed next time Olvid is launched
         * 2. We receive the delete request in the background and we arrive here.
         * 3. If we do not delete the serialized notifications, all the discussions messages included in these serialized notifications would appear.
         * So we need to delete these serialized notifications when a discussion is globally deleted. We actually do it even if the deletion is only local,
         * since there is no reason to have a serialized notification present after the app is launched.
         */
        cleanJsonMessagesSavedByNotificationExtension()
        
        switch deletionType {
        case .local:
            break // We will do the work below
        case .global:
            let op = SendGlobalDeleteDiscussionJSONOperation(persistedDiscussionObjectID: persistedDiscussionObjectID, obvEngine: obvEngine)
            internalQueue.addOperations([op], waitUntilFinished: true)
            op.logReasonIfCancelled(log: log)
        }
        
        // We first cancel the upload of all unprocessed messages
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            do {
                let allProcessingMessageSent = try PersistedMessageSent.getAllProcessingWithinDiscussion(persistedDiscussionObjectID: persistedDiscussionObjectID, within: context)
                let ops = allProcessingMessageSent.map({ CancelUploadOrDownloadOfPersistedMessageOperation(persistedMessageObjectID: $0.objectID, obvEngine: obvEngine) })
                internalQueue.addOperations(ops, waitUntilFinished: true)
                logReasonOfCancelledOperations(ops)
            } catch {
                os_log("Could not cancel current uploads/downloads during the deletion of the persisted discussion: %{public}@", log: log, type: .error, error.localizedDescription)
            }
        }
        
        let newDiscussionObjectID: NSManagedObjectID?
        let atLeastOneMessageWasDeleted: Bool
        do {
            let op1 = DeleteAllPersistedMessagesWithinDiscussionOperation(persistedDiscussionObjectID: persistedDiscussionObjectID)
            let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
            internalQueue.addOperations([composedOp], waitUntilFinished: true)
            composedOp.logReasonIfCancelled(log: log)
            DispatchQueue.main.async {
                completionHandler(!composedOp.isCancelled)
            }
            newDiscussionObjectID = op1.newDiscussionObjectID
            atLeastOneMessageWasDeleted = op1.atLeastOneMessageWasDeleted
        }
        do {
            let op1 = DeleteAllOrphanedFyleMessageJoinWithStatusOperation()
            let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
            internalQueue.addOperations([composedOp], waitUntilFinished: true)
            composedOp.logReasonIfCancelled(log: log)
        }
        do {
            let op1 = DeleteAllOrphanedFylesAndMoveAssociatedFilesToTrashOperation()
            let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
            internalQueue.addOperations([composedOp], waitUntilFinished: true)
            composedOp.logReasonIfCancelled(log: log)
        }
        ObvMessengerInternalNotification.trashShouldBeEmptied
            .postOnDispatchQueue()

        if let (obvContactId, messageUploadTimestampFromServer) = requestedBy {
            // This happens when this discussion was globally deleted by a contact.
            // In that case, we expect the newDiscussionObjectID to be non nil
            assert(newDiscussionObjectID != nil)
            if let objectID = newDiscussionObjectID, atLeastOneMessageWasDeleted {
                var contactIdentityObjectID: NSManagedObjectID? = nil
                ObvStack.shared.performBackgroundTaskAndWait { (context) in
                    if let contact = try? PersistedObvContactIdentity.get(persisted: obvContactId, whereOneToOneStatusIs: .any, within: context) {
                        contactIdentityObjectID = contact.objectID
                    }
                }
                assert(contactIdentityObjectID != nil)
                let op = InsertPersistedMessageSystemIntoDiscussionOperation(
                    persistedMessageSystemCategory: .discussionWasRemotelyWiped,
                    persistedDiscussionObjectID: objectID,
                    optionalContactIdentityObjectID: contactIdentityObjectID, optionalCallLogItemObjectID: nil,
                    messageUploadTimestampFromServer: messageUploadTimestampFromServer)
                internalQueue.addOperations([op], waitUntilFinished: true)
                op.logReasonIfCancelled(log: log)
            }
        }
    }
    
    private func processMessagesAreNotNewAnymore(persistedMessageObjectIDs: Set<TypeSafeManagedObjectID<PersistedMessage>>) {
        assert(OperationQueue.current != internalQueue)
        let op = ProcessPersistedMessagesAsTheyTurnsNotNewOperation(persistedMessageObjectIDs: persistedMessageObjectIDs)
        let composedOp = CompositionOfOneContextualOperation(op1: op, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
    }

    
    private func processAViewRequiresFyleMessageJoinWithStatusProgressesNotification(objectIDs: [NSManagedObjectID]) {
        
        var outboxMessageIdentifiers = Set<MessageIdentifierFromEngineAndOwnedCryptoId>()
        var inboxMessageIdentifiers = Set<MessageIdentifierFromEngineAndOwnedCryptoId>()

        ObvStack.shared.performBackgroundTaskAndWait { (context) in

            let sentFyleMessageJoinWithStatuses = objectIDs.compactMap({ context.object(with: $0) as? SentFyleMessageJoinWithStatus })
            outboxMessageIdentifiers = Set(sentFyleMessageJoinWithStatuses.compactMap({
                guard let messageIdentifierFromEngine = $0.message?.messageIdentifiersFromEngine.first else { return nil }
                guard let ownedCryptId = $0.message?.discussion.ownedIdentity?.cryptoId else { return nil }
                return MessageIdentifierFromEngineAndOwnedCryptoId(messageIdentifierFromEngine: messageIdentifierFromEngine, ownedCryptoId: ownedCryptId)
            }))
                            
            let receivedFyleMessageJoinWithStatuses = objectIDs.compactMap({ context.object(with: $0) as? ReceivedFyleMessageJoinWithStatus })
            inboxMessageIdentifiers = Set(receivedFyleMessageJoinWithStatuses.compactMap({
                guard let messageIdentifierFromEngine = $0.message?.messageIdentifiersFromEngine.first else { return nil }
                guard let ownedCryptId = $0.message?.discussion.ownedIdentity?.cryptoId else { return nil }
                return MessageIdentifierFromEngineAndOwnedCryptoId(messageIdentifierFromEngine: messageIdentifierFromEngine, ownedCryptoId: ownedCryptId)
            }))
            
        }
        
        for msgId in outboxMessageIdentifiers {
            do {
                try obvEngine.requestProgressesOfAllOutboxAttachmentsOfMessage(withIdentifier: msgId.messageIdentifierFromEngine, ownedCryptoId: msgId.ownedCryptoId)
            } catch {
                assertionFailure()
            }
        }

        for msgId in inboxMessageIdentifiers {
            do {
                try obvEngine.requestProgressesOfAllInboxAttachmentsOfMessage(withIdentifier: msgId.messageIdentifierFromEngine, ownedCryptoId: msgId.ownedCryptoId)
            } catch {
                assertionFailure()
            }
        }

    }

    
    private func processNewObvMessageWasReceivedViaPushKitNotification(obvMessage: ObvMessage) {
        processReceivedObvMessage(obvMessage, overridePreviousPersistedMessage: false, completionHandler: nil)
    }

    
    private func processNewWebRTCMessageToSendNotification(webrtcMessage: WebRTCMessageJSON, contactID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, forStartingCall: Bool) {
        os_log("☎️ We received an observeNewWebRTCMessageToSend notification", log: log, type: .info)
        do {
            let messageToSend = PersistedItemJSON(webrtcMessage: webrtcMessage)
            let messagePayload = try messageToSend.encode()
            try ObvStack.shared.performBackgroundTaskAndWaitOrThrow { [weak self] (context) in
                guard let _self = self else { return }
                guard let contact = try PersistedObvContactIdentity.get(objectID: contactID, within: context) else { throw _self.makeError(message: "Could not find PersistedObvContactIdentity") }
                let contactCryptoId = contact.cryptoId
                guard let ownedCryptoId = contact.ownedIdentity?.cryptoId else { return }
                let messageIdentifierForContactToWhichTheMessageWasSent =
                    try _self.obvEngine.post(messagePayload: messagePayload,
                                             extendedPayload: nil,
                                             withUserContent: false,
                                             isVoipMessageForStartingCall: forStartingCall, // True only for starting a call
                        attachmentsToSend: [],
                        toContactIdentitiesWithCryptoId: [contactCryptoId],
                        ofOwnedIdentityWithCryptoId: ownedCryptoId,
                        completionHandler: nil)
                if messageIdentifierForContactToWhichTheMessageWasSent[contactCryptoId] != nil {
                    os_log("☎️ We posted a new %{public}s WebRTCMessage for call %{public}s", log: log, type: .info, String(describing: webrtcMessage.messageType), String(webrtcMessage.callIdentifier))
                } else {
                    os_log("☎️ We failed to post a %{public}s WebRTCMessage", log: log, type: .fault, String(describing: webrtcMessage.messageType))
                    assertionFailure()
                }
            }
        } catch {
            os_log("☎️ Could not post %{public}s webRTCMessageJSON", log: log, type: .fault, String(describing: webrtcMessage.messageType))
            assertionFailure()
            return
        }
    }

    private func processNewCallLogItemNotification(objectID: TypeSafeManagedObjectID<PersistedCallLogItem>) {
        os_log("☎️ We received an NewReportCallItem notification", log: log, type: .info)
        do {
            try ObvStack.shared.performBackgroundTaskAndWaitOrThrow { [weak self] (context) in
                guard let _self = self else { return }

                guard let item = try PersistedCallLogItem.get(objectID: objectID, within: context) else {
                    throw _self.makeError(message: "Could not find PersistedCallLogItem")
                }

                guard let ownedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: item.ownedCryptoId, within: context) else {
                    throw _self.makeError(message: "Could not find PersistedObvOwnedIdentity")
                }

                let discussion: PersistedDiscussion
                if let groupId = try item.getGroupId() {
                    guard let contactGroup = try PersistedContactGroup.getContactGroup(groupId: groupId, ownedIdentity: ownedIdentity) else {
                        throw _self.makeError(message: "Could not find PersistedObvOwnedIdentity")
                    }
                    discussion = contactGroup.discussion
                } else {
                    if item.isIncoming {
                        guard let caller = item.logContacts.first(where: {$0.isCaller}),
                              let callerIdentity = caller.contactIdentity else {
                            throw _self.makeError(message: "Could not find caller for incoming call")
                        }
                        if let oneToOneDiscussion = try callerIdentity.oneToOneDiscussion {
                            discussion = oneToOneDiscussion
                        } else {
                            // Do not report this call.
                            return
                        }
                    } else if item.logContacts.count == 1,
                              let contact = item.logContacts.first,
                              let contactIdentity = contact.contactIdentity,
                              let oneToOneDiscussion = try contactIdentity.oneToOneDiscussion {
                        discussion = oneToOneDiscussion
                    } else {
                        // Do not report this call.
                        return
                    }
                }

                let op = InsertPersistedMessageSystemIntoDiscussionOperation(persistedMessageSystemCategory: .callLogItem, persistedDiscussionObjectID: discussion.objectID, optionalContactIdentityObjectID: nil, optionalCallLogItemObjectID: objectID)
                internalQueue.addOperations([op], waitUntilFinished: true)
                op.logReasonIfCancelled(log: log)
            }
        } catch(let error) {
            os_log("☎️ Failed NewReportCall notification: %@", log: log, type: .error, error.localizedDescription)
            assertionFailure()
            return
        }
    }

    private func processPersistedContactWasDeletedNotification() {
        os_log("☎️ We received an PersistedContactWasDeleted notification", log: log, type: .info)

        let op = CleanCallLogContactsOperation()
        internalQueue.addOperations([op], waitUntilFinished: true)
        op.logReasonIfCancelled(log: log)
    }


    private func processWipeAllMessagesThatExpiredEarlierThanNow(launchedByBackgroundTask: Bool, completionHandler: (Bool) -> Void) {
        let op1 = WipeExpiredMessagesOperation(launchedByBackgroundTask: launchedByBackgroundTask)
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
        let success = !composedOp.isCancelled
        completionHandler(success)
    }
    
    
    private func userLeftDiscussion(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) {
        do {
            let op1 = WipeOrDeleteReadOnceMessagesOperation(preserveReceivedMessages: false, restrictToDiscussionWithObjectID: discussionObjectID)
            let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
            internalQueue.addOperations([composedOp], waitUntilFinished: true)
            composedOp.logReasonIfCancelled(log: log)
        }
        do {
            let op = DeleteMessagesWithExpiredTimeBasedRetentionOperation(restrictToDiscussionWithObjectID: discussionObjectID.objectID)
            internalQueue.addOperations([op], waitUntilFinished: true)
            op.logReasonIfCancelled(log: log)
        }
        do {
            let op = DeleteMessagesWithExpiredCountBasedRetentionOperation(restrictToDiscussionWithObjectID: discussionObjectID.objectID)
            internalQueue.addOperations([op], waitUntilFinished: true)
            op.logReasonIfCancelled(log: log)
        }
        do {
            let op1 = DeleteAllOrphanedFyleMessageJoinWithStatusOperation()
            let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
            internalQueue.addOperations([composedOp], waitUntilFinished: true)
            composedOp.logReasonIfCancelled(log: log)
        }
        do {
            let op1 = DeleteAllOrphanedFylesAndMoveAssociatedFilesToTrashOperation()
            let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
            internalQueue.addOperations([composedOp], waitUntilFinished: true)
            composedOp.logReasonIfCancelled(log: log)
        }
        ObvMessengerInternalNotification.trashShouldBeEmptied
            .postOnDispatchQueue()
    }
    
    
    private func userEnteredDiscussion(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) {
        let op = AllowReadingOfAllMessagesReceivedThatRequireUserActionOperation(persistedDiscussionObjectID: discussionObjectID)
        internalQueue.addOperations([op], waitUntilFinished: true)
        op.logReasonIfCancelled(log: log)
    }

    
    private func processUserWantsToReadReceivedMessagesThatRequiresUserActionNotification(persistedMessageObjectIDs: Set<TypeSafeManagedObjectID<PersistedMessageReceived>>) {
        let op = AllowReadingOfMessagesReceivedThatRequireUserActionOperation(persistedMessageReceivedObjectIDs: persistedMessageObjectIDs)
        internalQueue.addOperations([op], waitUntilFinished: true)
        op.logReasonIfCancelled(log: log)
    }

    private func processPersistedMessageReceivedWasReadNotification(persistedMessageReceivedObjectID: NSManagedObjectID) {
        let log = self.log
        // We do not need to sync the sending of a read receipt on the operation queue
        ObvStack.shared.performBackgroundTask { [weak self] (context) in
            guard let messageReceived = try? PersistedMessageReceived.get(with: persistedMessageReceivedObjectID, within: context) as? PersistedMessageReceived else {
                assertionFailure()
                return
            }
            do {
                try self?.postReadReceiptIfRequired(messageReceived: messageReceived)
            } catch {
                os_log("The Return Receipt could not be posted", log: log, type: .fault)
                assertionFailure()
            }
        }
    }
    
    
    private func processAReadOncePersistedMessageSentWasSentNotification(persistedMessageSentObjectID: NSManagedObjectID, persistedDiscussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) {
        // When a readOnce sent message status becomes "sent", we check whether the user is still within the discussion corresponding to this message.
        // If this is the case, we do nothing. Otherwise, we should delete or wipe the message as it is readOnce, has already been seen, and was properly sent.
        guard ObvUserActivitySingleton.shared.currentPersistedDiscussionObjectID != persistedDiscussionObjectID else {
            os_log("A readOnce outbound message was sent but the user is still within the discussion, so we do *not* delete the message immediately", log: log, type: .info)
            return
        }
        os_log("A readOnce outbound message was sent after the user left the discussion. We delete/wipe the message now", log: log, type: .info)
        do {
            let op1 = WipeOrDeleteReadOnceMessagesOperation(preserveReceivedMessages: false, restrictToDiscussionWithObjectID: persistedDiscussionObjectID)
            let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
            internalQueue.addOperations([composedOp], waitUntilFinished: true)
            composedOp.logReasonIfCancelled(log: log)
        }
        do {
            let op1 = DeleteAllOrphanedFyleMessageJoinWithStatusOperation()
            let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
            internalQueue.addOperations([composedOp], waitUntilFinished: true)
            composedOp.logReasonIfCancelled(log: log)
        }
        do {
            let op1 = DeleteAllOrphanedFylesAndMoveAssociatedFilesToTrashOperation()
            let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
            internalQueue.addOperations([composedOp], waitUntilFinished: true)
            composedOp.logReasonIfCancelled(log: log)
        }
        ObvMessengerInternalNotification.trashShouldBeEmptied
            .postOnDispatchQueue()
    }
    
    
    private func processUserWantsToSetAndShareNewDiscussionSharedExpirationConfiguration(persistedDiscussionObjectID: NSManagedObjectID, expirationJSON: ExpirationJSON, ownedCryptoId: ObvCryptoId) {
        do {
            let op = ReplaceDiscussionSharedExpirationConfigurationOperation(persistedDiscussionObjectID: persistedDiscussionObjectID, expirationJSON: expirationJSON, initiator: ownedCryptoId)
            internalQueue.addOperations([op], waitUntilFinished: true)
            op.logReasonIfCancelled(log: log)
            guard !op.isCancelled else { return }
        }
        do {
            let op = InsertCurrentDiscussionSharedConfigurationSystemMessageOperation(persistedDiscussionObjectID: persistedDiscussionObjectID, messageUploadTimestampFromServer: nil, fromContactIdentity: nil)
            internalQueue.addOperations([op], waitUntilFinished: true)
            op.logReasonIfCancelled(log: log)
        }
        do {
            let op = SendPersistedDiscussionSharedConfigurationOperation(persistedDiscussionObjectID: persistedDiscussionObjectID, obvEngine: obvEngine)
            internalQueue.addOperations([op], waitUntilFinished: true)
            op.logReasonIfCancelled(log: log)
        }
    }
    
    
    private func processPersistedDiscussionSharedConfigurationShouldBeSentNotification(persistedDiscussionObjectID: NSManagedObjectID) {
        let op = SendPersistedDiscussionSharedConfigurationOperation(persistedDiscussionObjectID: persistedDiscussionObjectID, obvEngine: obvEngine)
        internalQueue.addOperations([op], waitUntilFinished: true)
        op.logReasonIfCancelled(log: log)
    }

    
    private func processApplyAllRetentionPoliciesNowNotification(launchedByBackgroundTask: Bool, completionHandler: (Bool) -> Void) {
        var success = true
        do {
            let op = DeleteMessagesWithExpiredTimeBasedRetentionOperation(restrictToDiscussionWithObjectID: nil)
            internalQueue.addOperations([op], waitUntilFinished: true)
            op.logReasonIfCancelled(log: log)
            if launchedByBackgroundTask {
                ObvDisplayableLogs.shared.log("DeleteMessagesWithExpiredTimeBasedRetentionOperation deleted \(op.numberOfDeletedMessages) messages")
            }
            success = success && !op.isCancelled
        }
        do {
            let op = DeleteMessagesWithExpiredCountBasedRetentionOperation(restrictToDiscussionWithObjectID: nil)
            internalQueue.addOperations([op], waitUntilFinished: true)
            op.logReasonIfCancelled(log: log)
            success = success && !op.isCancelled
        }
        do {
            let op1 = DeleteAllOrphanedFyleMessageJoinWithStatusOperation()
            let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
            internalQueue.addOperations([composedOp], waitUntilFinished: true)
            composedOp.logReasonIfCancelled(log: log)
        }
        do {
            let op1 = DeleteAllOrphanedFylesAndMoveAssociatedFilesToTrashOperation()
            let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
            internalQueue.addOperations([composedOp], waitUntilFinished: true)
            composedOp.logReasonIfCancelled(log: log)
        }
        ObvMessengerInternalNotification.trashShouldBeEmptied
            .postOnDispatchQueue()
        completionHandler(success)
    }

    
    private func processAnOldDiscussionSharedConfigurationWasReceivedNotification(persistedDiscussionObjectID: NSManagedObjectID) {
        let op = SendPersistedDiscussionSharedConfigurationOperation(persistedDiscussionObjectID: persistedDiscussionObjectID, obvEngine: obvEngine)
        internalQueue.addOperations([op], waitUntilFinished: true)
        op.logReasonIfCancelled(log: log)
    }

    
    private func processUserWantsToSendEditedVersionOfSentMessage(sentMessageObjectID: NSManagedObjectID, newTextBody: String) {
        let textBody = newTextBody.isEmpty ? nil : newTextBody
        let op1 = EditTextBodyOfSentMessageOperation(persistedSentMessageObjectID: sentMessageObjectID, newTextBody: textBody)
        let op2 = SendUpdateMessageJSONOperation(persistedSentMessageObjectID: sentMessageObjectID, obvEngine: obvEngine)
        let composedOp = CompositionOfTwoContextualOperations(op1: op1, op2: op2, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
        guard !composedOp.isCancelled else { assertionFailure(); return }
    }

    private func processUserWantsToUpdateReaction(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, emoji: String?) {
        let op1 = UpdateReactionsOfMessageOperation(emoji: emoji, messageObjectID: messageObjectID)
        let op2 = SendReactionJSONOperation(messageObjectID: messageObjectID, obvEngine: obvEngine, emoji: emoji)
        let composedOp = CompositionOfTwoContextualOperations(op1: op1, op2: op2, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
        guard !composedOp.isCancelled else { assertionFailure(); return }
    }
    
    private func processUserWantsToMarkAllMessagesAsNotNewWithinDiscussionNotification(persistedDiscussionObjectID: NSManagedObjectID, completionHandler: @escaping (Bool) -> Void) {
        os_log("Call to processUserWantsToMarkAllMessagesAsNotNewWithinDiscussionNotification for discussion %{public}@", log: log, type: .debug, persistedDiscussionObjectID.debugDescription)
        os_log("Creating a MarkAllMessagesAsNotNewWithinDiscussionOperation for discussion %{public}@", log: log, type: .debug, persistedDiscussionObjectID.debugDescription)
        let op1 = MarkAllMessagesAsNotNewWithinDiscussionOperation(persistedDiscussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>(objectID: persistedDiscussionObjectID) )
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
        guard !composedOp.isCancelled else { assertionFailure(); completionHandler(false); return }
        DispatchQueue.main.async { completionHandler(true) }
    }

    
    private func processUserWantsToRemoveDraftFyleJoinNotification(draftFyleJoinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>) {
        do {
            let op = DeleteDraftFyleJoinOperation(draftFyleJoinObjectID: draftFyleJoinObjectID)
            internalQueue.addOperations([op], waitUntilFinished: true)
            op.logReasonIfCancelled(log: log)
        }
        do {
            let op1 = DeleteAllOrphanedFylesAndMoveAssociatedFilesToTrashOperation()
            let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
            internalQueue.addOperations([composedOp], waitUntilFinished: true)
            composedOp.logReasonIfCancelled(log: log)
        }
        ObvMessengerInternalNotification.trashShouldBeEmptied
            .postOnDispatchQueue()
    }

    
}


// MARK: - Draft specific notifications

extension PersistedDiscussionsUpdatesCoordinator {
    
    private func processUserWantsToReplyToMessage(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) {
        let op = AddReplyToOnDraftOperation(messageObjectID: messageObjectID, draftObjectID: draftObjectID)
        let composedOp = CompositionOfOneContextualOperation(op1: op, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
    }

    private func processUserWantsToRemoveReplyToMessage(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) {
        let op = RemoveReplyToOnDraftOperation(draftObjectID: draftObjectID)
        let composedOp = CompositionOfOneContextualOperation(op1: op, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
    }
    
    private func processUserWantsToAddAttachmentsToDraft(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, itemProviders: [NSItemProvider], completionHandler: @escaping (Bool) -> Void) {
        assert(OperationQueue.current != internalQueue)
        
        let loadItemProviderOperations = itemProviders.map {
            LoadItemProviderOperation(itemProvider: $0, progressAvailable: { [weak self] progress in
                // Called only if a progress is made available during the operation execution
                self?.newProgressToAddForTrackingFreeze(draftObjectID: draftObjectID, progress: progress)
            })
        }
        queueForLongRunningConcurrentOperations.addOperations(loadItemProviderOperations, waitUntilFinished: true)
        logReasonOfCancelledOperations(loadItemProviderOperations)

        let loadedItemProviders = loadItemProviderOperations.compactMap({ $0.loadedItemProvider })

        let op1 = NewCreateDraftFyleJoinsFromLoadedFileRepresentationsOperation(draftObjectID: draftObjectID, loadedItemProviders: loadedItemProviders, completionHandler: completionHandler, log: log)
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        op1.logReasonIfCancelled(log: log)
        
    }
    
    
    private func newProgressToAddForTrackingFreeze(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, progress: Progress) {
        if #available(iOS 15, *) {
            CompositionViewFreezeManager.shared.newProgressToAddForTrackingFreeze(draftObjectID: draftObjectID, progress: progress)
        }
    }
    

    private func processUserWantsToAddAttachmentsToDraft(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, urls: [URL], completionHandler: @escaping (Bool) -> Void) {
        assert(OperationQueue.current != internalQueue)
        
        let loadItemProviderOperations = urls.map {
            LoadItemProviderOperation(itemURL: $0, progressAvailable: { [weak self] progress in
                // Called only if a progress is made available during the operation execution
                self?.newProgressToAddForTrackingFreeze(draftObjectID: draftObjectID, progress: progress)
            })
        }
        queueForLongRunningConcurrentOperations.addOperations(loadItemProviderOperations, waitUntilFinished: true)
        logReasonOfCancelledOperations(loadItemProviderOperations)

        let loadedItemProviders = loadItemProviderOperations.compactMap({ $0.loadedItemProvider })

        let op1 = NewCreateDraftFyleJoinsFromLoadedFileRepresentationsOperation(draftObjectID: draftObjectID, loadedItemProviders: loadedItemProviders, completionHandler: completionHandler, log: log)
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        op1.logReasonIfCancelled(log: log)
        
    }

    private func processUserWantsToDeleteAllAttachmentsToDraft(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) {
        
        do {
            let op = DeleteAllDraftFyleJoinOfDraftOperation(draftObjectID: draftObjectID)
            let composedOp = CompositionOfOneContextualOperation(op1: op, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
            internalQueue.addOperations([composedOp], waitUntilFinished: true)
            composedOp.logReasonIfCancelled(log: log)
        }
        
        do {
            let op = DeleteAllOrphanedFylesAndMoveAssociatedFilesToTrashOperation()
            let composedOp = CompositionOfOneContextualOperation(op1: op, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
            internalQueue.addOperations([composedOp], waitUntilFinished: true)
            composedOp.logReasonIfCancelled(log: log)
        }
        ObvMessengerInternalNotification.trashShouldBeEmptied
            .postOnDispatchQueue()

    }
    
    
    private func processUserWantsToSendDraft(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, textBody: String) {
        let op1 = SaveBodyTextOfPersistedDraftOperation(draftObjectID: draftObjectID, bodyText: textBody)
        let op2 = RequestedSendingOfDraftOperation(draftObjectID: draftObjectID)
        let composedOp = CompositionOfTwoContextualOperations(op1: op1, op2: op2, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
        guard !composedOp.isCancelled else {
            NewSingleDiscussionNotification.draftCouldNotBeSent(persistedDraftObjectID: draftObjectID)
                .postOnDispatchQueue()
            return
        }
    }

    private func processUserWantsToSendDraftWithAttachements(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, attachementsURL: [URL]) {
        
        let loadItemProviderOperations = attachementsURL.map {
            LoadItemProviderOperation(itemURL: $0, progressAvailable: { [weak self] progress in
                // Called only if a progress is made available during the operation execution
                self?.newProgressToAddForTrackingFreeze(draftObjectID: draftObjectID, progress: progress)
            })
        }
        queueForLongRunningConcurrentOperations.addOperations(loadItemProviderOperations, waitUntilFinished: true)
        logReasonOfCancelledOperations(loadItemProviderOperations)

        let loadedItemProviders = loadItemProviderOperations.compactMap({ $0.loadedItemProvider })

        let op1 = NewCreateDraftFyleJoinsFromLoadedFileRepresentationsOperation(draftObjectID: draftObjectID, loadedItemProviders: loadedItemProviders, completionHandler: nil, log: log)
        let op2 = RequestedSendingOfDraftOperation(draftObjectID: draftObjectID)
        let composedOp = CompositionOfTwoContextualOperations(op1: op1, op2: op2, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
        guard !composedOp.isCancelled else {
            NewSingleDiscussionNotification.draftCouldNotBeSent(persistedDraftObjectID: draftObjectID)
                .postOnDispatchQueue()
            return
        }

    }

    private func processUserWantsToUpdateDraftExpiration(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, value: PersistedDiscussionSharedConfigurationValue?) {
        let op1 = UpdateDraftConfigurationOperation(value: value, draftObjectID: draftObjectID)
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
    }

    private func processUserWantsToUpdateDraftBody(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, value: String) {
        let op = UpdateDraftBodyOperation(value: value, draftObjectID: draftObjectID)
        let composedOp = CompositionOfOneContextualOperation(op1: op, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
    }

    private func processUserWantsToUpdateDiscussionLocalConfigurationNotification(with value: PersistedDiscussionLocalConfigurationValue, localConfigurationObjectID: TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>) {
        let op = UpdateDiscussionLocalConfigurationOperation(value: value, localConfigurationObjectID: localConfigurationObjectID)
        let composedOp = CompositionOfOneContextualOperation(op1: op, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
    }

    private func processUserWantsToUpdateLocalConfigurationOfDiscussionNotification(with value: PersistedDiscussionLocalConfigurationValue, persistedDiscussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) {
        let op = UpdateDiscussionLocalConfigurationOperation(value: value, persistedDiscussionObjectID: persistedDiscussionObjectID)
        let composedOp = CompositionOfOneContextualOperation(op1: op, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
    }

}


// MARK: - Processing ObvEngine Notifications

extension PersistedDiscussionsUpdatesCoordinator {
    
    private func processNewMessageReceivedNotification(obvMessage: ObvMessage, completionHandler: @escaping (Set<ObvAttachment>) -> Void) {
        os_log("We received a NewMessageReceived notification", log: log, type: .debug)

        let attachmentsToDownloadAsap = Set(obvMessage.attachments.filter({ $0.totalUnitCount < ObvMessengerSettings.Downloads.maxAttachmentSizeForAutomaticDownload }))
        let localCompletionHandler = {
            completionHandler(attachmentsToDownloadAsap)
        }

        processReceivedObvMessage(obvMessage, overridePreviousPersistedMessage: true, completionHandler: localCompletionHandler)
        
    }

    
    private func processMessageWasAcknowledgedNotification(ownedIdentity: ObvCryptoId, messageIdentifierFromEngine: Data, timestampFromServer: Date, isAppMessageWithUserContent: Bool, isVoipMessage: Bool) {
        defer {
            let completion = completionWhenMessageIsSent.removeValue(forKey: messageIdentifierFromEngine)
            completion?()
        }

        if isAppMessageWithUserContent {

            let op = SetTimestampMessageSentOfPersistedMessageSentRecipientInfosOperation(messageIdentifierFromEngine: messageIdentifierFromEngine, timestampFromServer: timestampFromServer)
            internalQueue.addOperations([op], waitUntilFinished: true)
            op.logReasonIfCancelled(log: log)
            
            obvEngine.deleteHistoryConcerningTheAcknowledgementOfOutboxMessages([(messageIdentifierFromEngine, ownedIdentity)])

        }
    }

    
    private func processAttachmentWasAcknowledgedByServerNotification(messageIdentifierFromEngine: Data, attachmentNumber: Int) {
        let op1 = MarkSentFyleMessageJoinWithStatusAsCompleteOperation(messageIdentifierFromEngine: messageIdentifierFromEngine, attachmentNumber: attachmentNumber)
        let op2 = SetTimestampAllAttachmentsSentIfPossibleOfPersistedMessageSentRecipientInfosOperation(messageIdentifierFromEngine: messageIdentifierFromEngine)
        op2.addDependency(op1)
        let ops: [OperationThatCanLogReasonForCancel] = [op1]
        internalQueue.addOperations(ops, waitUntilFinished: true)
        logReasonOfCancelledOperations(ops)
    }

    
    private func processAttachmentUploadNewProgressNotification(messageIdentifierFromEngine: Data, attachmentNumber: Int, newProgress: Progress) {
        
        let log = self.log
        
        ObvStack.shared.performBackgroundTask { (context) in

            let persistedMessageSent: PersistedMessageSent
            do {
                os_log("🆗 Looking for PersistedMessageSentRecipientInfos having messageIdentifierFromEngine %{public}@", log: log, type: .info, messageIdentifierFromEngine.hexString())
                let infos = try PersistedMessageSentRecipientInfos.getAllPersistedMessageSentRecipientInfos(messageIdentifierFromEngine: messageIdentifierFromEngine, within: context)
                guard let _persistedMessageSent = infos.first?.messageSent else {
                    os_log("🆗 Could not find PersistedMessageSent from db (3)", log: log, type: .error)
                    return
                }
                persistedMessageSent = _persistedMessageSent
            } catch {
                os_log("PersistedMessageSent fetch failed", log: log, type: .fault)
                return
            }

            guard attachmentNumber < persistedMessageSent.fyleMessageJoinWithStatuses.count else {
                os_log("There is no SentFyleMessageJoinWithStatus corresponding to the received engine attachment number", log: log, type: .error)
                return
            }

            let fyleMessageJoinWithStatus = persistedMessageSent.fyleMessageJoinWithStatuses[attachmentNumber]
            
            ObvMessengerInternalNotification.fyleMessageJoinWithStatusHasNewProgress(objectID: fyleMessageJoinWithStatus.objectID, progress: newProgress)
                .postOnDispatchQueue()
            
            // Under iOS14+, when using the new discussion screen, we store the progress right within the fyle message join,
            // Making it possible for the single discussion view to update its cells with this new progress.

            if #available(iOS 14.0, *) {
                let joinObjectID = fyleMessageJoinWithStatus.objectID
                if let messageObjectID = fyleMessageJoinWithStatus.message?.objectID {
                    DispatchQueue.main.async {
                        guard let join = FyleMessageJoinWithStatus.get(objectID: joinObjectID, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
                        join.progress = newProgress
                        if let message = ObvStack.shared.viewContext.registeredObject(for: messageObjectID) {
                            ObvStack.shared.viewContext.refresh(message, mergeChanges: true)
                        }
                    }
                }
            }
            
        }

    }

    
    private func processInboxAttachmentNewProgressNotification(obvAttachment: ObvAttachment, newProgress: Progress) {
        
        os_log("We received an AttachmentDownloadNewProgress notification", log: log, type: .debug)

        let op = ProcessFyleWithinDownloadingAttachmentOperation(obvAttachment: obvAttachment, newProgress: newProgress, obvEngine: obvEngine)
        let composedOp = CompositionOfOneContextualOperation(op1: op, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
        
    }

    
    private func processAttachmentDownloadCancelledByServerNotification(obvAttachment: ObvAttachment) {
        
        os_log("We received an AttachmentDownloadCancelledByServer notification", log: log, type: .debug)
        
        let op = ProcessFyleWithinDownloadingAttachmentOperation(obvAttachment: obvAttachment, newProgress: nil, obvEngine: obvEngine)
        let composedOp = CompositionOfOneContextualOperation(op1: op, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
        
        guard !composedOp.isCancelled else { return }
        
        // If we reach this point, we have successfully processed the fyle within the attachment. We can ask the engine to delete the attachment
        
        do {
            try obvEngine.deleteObvAttachment(attachmentNumber: obvAttachment.number,
                                              ofMessageWithIdentifier: obvAttachment.messageIdentifier,
                                              ownedCryptoId: obvAttachment.ownedCryptoId)
        } catch {
            os_log("The engine failed to delete the attachment", log: log, type: .fault)
        }
        
    }

    
    /// This notification is typically sent when we request progress for attachments that cannot be found anymore within the engine's inbox.
    /// Typical if the message/attachments were deleted by the sender before they were completely sent.
    private func processCannotReturnAnyProgressForMessageAttachmentsNotification(messageIdentifierFromEngine: Data) {
        let op = MarkAllIncompleteReceivedFyleMessageJoinWithStatusAsCancelledByServer(messageIdentifierFromEngine: messageIdentifierFromEngine)
        internalQueue.addOperations([op], waitUntilFinished: true)
        op.logReasonIfCancelled(log: log)
    }

    
    private func processAttachmentDownloadedNotification(obvAttachment: ObvAttachment) {
        
        let op = ProcessFyleWithinDownloadingAttachmentOperation(obvAttachment: obvAttachment, newProgress: nil, obvEngine: obvEngine)
        let composedOp = CompositionOfOneContextualOperation(op1: op, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
        
        guard !composedOp.isCancelled else { return }
        
        // If we reach this point, we have successfully processed the fyle within the attachment. We can ask the engine to delete the attachment
        
        do {
            try obvEngine.deleteObvAttachment(attachmentNumber: obvAttachment.number,
                                              ofMessageWithIdentifier: obvAttachment.messageIdentifier,
                                              ownedCryptoId: obvAttachment.ownedCryptoId)
        } catch {
            os_log("The engine failed to delete the attachment we just persisted", log: log, type: .fault)
            assertionFailure()
        }

    }

    
    private func processNewObvReturnReceiptToProcessNotification(obvReturnReceipt: ObvReturnReceipt) {
        
        let op = ProcessObvReturnReceiptOperation(obvReturnReceipt: obvReturnReceipt, obvEngine: obvEngine)
        let composedOp = CompositionOfOneContextualOperation(op1: op, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)

        if let reasonForCancel = op.reasonForCancel {
            switch reasonForCancel {
            case .contextIsNil:
                os_log("Could not process return receipt: %{public}@", log: log, type: .fault, reasonForCancel.localizedDescription)
            case .coreDataError(error: let error):
                os_log("Could not process return receipt: %{public}@", log: log, type: .fault, error.localizedDescription)
            case .couldNotFindAnyPersistedMessageSentRecipientInfosInDatabase:
                os_log("Could not find message corresponding to the return receipt. We delete the receipt.", log: log, type: .error)
                obvEngine.deleteObvReturnReceipt(obvReturnReceipt)
            }
        } else {
            // If we reach this point, the receipt has been successfully processed. We can delete it from the engine.
            obvEngine.deleteObvReturnReceipt(obvReturnReceipt)
        }
    }

    
    /// The OutboxMessagesAndAllTheirAttachmentsWereAcknowledged notification is typically sent when the messages/attachments were deleted from their outbox, meaning that they all have been fully sent to the server
    /// (unless they were cancelled by the user by deleting the message). This is also sent during the boostraping of the engine, when replaying the transaction history, so as to make sure the app didn't miss any important notification.
    /// This means that most of the time, we already know about the information provided within the notification.
    private func processOutboxMessagesAndAllTheirAttachmentsWereAcknowledgedNotification(messageIdsAndTimestampsFromServer: [(messageIdentifierFromEngine: Data, ownedCryptoId: ObvCryptoId, timestampFromServer: Date)]) {

        var operationsToQueue = [OperationThatCanLogReasonForCancel]()

        // Task #1: Set the sent timestamp of the PersistedMessageSentRecipientInfos
        
        for (messageIdentifierFromEngine, _, timestampFromServer) in messageIdsAndTimestampsFromServer {
            let op = SetTimestampMessageSentOfPersistedMessageSentRecipientInfosOperation(messageIdentifierFromEngine: messageIdentifierFromEngine, timestampFromServer: timestampFromServer)
            operationsToQueue.append(op)
        }
        
        // Task #2: Acknowledge all sent attachments
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            for (messageIdentifierFromEngine, ownedCryptoId, _) in messageIdsAndTimestampsFromServer {
                let infos: [PersistedMessageSentRecipientInfos]
                do {
                    infos = try PersistedMessageSentRecipientInfos.getAllPersistedMessageSentRecipientInfos(messageIdentifierFromEngine: messageIdentifierFromEngine,
                                                                                                            ownedCryptoId: ownedCryptoId,
                                                                                                            within: context)
                    guard let persistedMessageSent = infos.first?.messageSent else { continue }
                    guard !persistedMessageSent.fyleMessageJoinWithStatuses.isEmpty else { continue }
                    for attachmentNumber in 0..<persistedMessageSent.fyleMessageJoinWithStatuses.count {
                        let op1 = MarkSentFyleMessageJoinWithStatusAsCompleteOperation(messageIdentifierFromEngine: messageIdentifierFromEngine, attachmentNumber: attachmentNumber)
                        let op2 = SetTimestampAllAttachmentsSentIfPossibleOfPersistedMessageSentRecipientInfosOperation(messageIdentifierFromEngine: messageIdentifierFromEngine)
                        op2.addDependency(op1)
                        operationsToQueue.append(contentsOf: [op1, op2])
                    }
                } catch {
                    os_log("PersistedMessageSent fetch failed: %{public}@", log: log, type: .fault)
                    continue
                }
            }
        }
        
        // Now we can execute all the operations
        
        guard !operationsToQueue.isEmpty else { return }
        internalQueue.addOperations(operationsToQueue, waitUntilFinished: true)
        logReasonOfCancelledOperations(operationsToQueue)
        
        // We ask the engine to delete the history (we probably should filter those ids depending on the success of the operations...)
        
        let messageIds = messageIdsAndTimestampsFromServer.map { ($0.messageIdentifierFromEngine, $0.ownedCryptoId) }
        obvEngine.deleteHistoryConcerningTheAcknowledgementOfOutboxMessages(messageIds)
        
    }

    
    /// When a contact is deleted, we look for all associated `PersistedMessageSentRecipientInfos` instance with no message identifier from engine and delete these instances.
    /// For each of these instances, we also recompute the status of the associated `PersistedMessageSent` (since the absence of a particular `PersistedMessageSentRecipientInfos`
    /// may have an influence on the result of the computation).
    ///
    /// Those `PersistedMessageSentRecipientInfos` instances are created when sending a message to this contact. In the case we have no channel
    /// with this contact at that point in time, the message won't be accepted by the engine
    /// and will prevent the message to be marked as sent. In practice, the user sees a "rabbit" that cannot go away. Deleting these instances and recomputing the `PersistedMessageSent`
    /// statues allow to prevent this bad user experience. Moreover, the message would never be sent anyway.
    private func processContactWasDeletedNotification(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId) {
        let op = DeletePersistedMessageSentRecipientInfosWithoutMessageIdentifierFromEngineAndAssociatedToContactIdentityOperation(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
        internalQueue.addOperations([op], waitUntilFinished: true)
        op.logReasonIfCancelled(log: log)
    }

    
    /// Called when the engine received successfully downloaded and decrypted an extended payload for an application message.
    private func processMessageExtendedPayloadAvailable(obvMessage: ObvMessage, extendedMessagePayload: Data) {
        let op = ProcessReceivedExtendedPayloadOperation(obvMessage: obvMessage, extendedMessagePayload: extendedMessagePayload)
        let composedOp = CompositionOfOneContextualOperation(op1: op, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
    }
    
    
    private func processContactWasRevokedAsCompromisedWithinEngine(obvContactIdentity: ObvContactIdentity) {
        // When the engine informs us that a contact has been revoked as compromised, we insert
        let log = self.log
        ObvStack.shared.performBackgroundTask { [weak self] context in
            let contact: PersistedObvContactIdentity
            do {
                guard let _contact = try PersistedObvContactIdentity.get(persisted: obvContactIdentity, whereOneToOneStatusIs: .any, within: context) else { assertionFailure(); return }
                contact = _contact
            } catch {
                os_log("Could not get contact: %{public}", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
            if let oneToOneDiscussionObjectID = try? contact.oneToOneDiscussion?.objectID {
                let op = InsertPersistedMessageSystemIntoDiscussionOperation(
                    persistedMessageSystemCategory: .contactRevokedByIdentityProvider,
                    persistedDiscussionObjectID: oneToOneDiscussionObjectID,
                    optionalContactIdentityObjectID: contact.objectID,
                    optionalCallLogItemObjectID: nil,
                    messageUploadTimestampFromServer: nil)
                self?.internalQueue.addOperations([op], waitUntilFinished: true)
                op.logReasonIfCancelled(log: log)
            }
        }
    }

    
    private func processNewUserDialogToPresent(obvDialog: ObvDialog) {
        assert(OperationQueue.current != internalQueue)
        let op1 = ProcessObvDialogOperation(obvDialog: obvDialog, obvEngine: obvEngine)
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
    }

    
    private func processAPersistedDialogWasDeleted(uuid: UUID) {
        assert(OperationQueue.current != internalQueue)
        let log = self.log
        internalQueue.addOperation {
            ObvStack.shared.performBackgroundTaskAndWait { (context) in
                do {
                    guard let persistedInvitation = try PersistedInvitation.get(uuid: uuid, within: context) else { return }
                    try persistedInvitation.delete()
                    try context.save(logOnFailure: log)
                } catch let error {
                    os_log("Could not delete PersistedInvitation: %@", log: log, type: .error, error.localizedDescription)
                    assertionFailure()
                }
            }
        }
    }

}


// MARK: - Helpers

extension PersistedDiscussionsUpdatesCoordinator {
    
    
    private func postReadReceiptIfRequired(messageReceived: PersistedMessageReceived) throws {
        guard messageReceived.discussion.localConfiguration.doSendReadReceipt ?? ObvMessengerSettings.Discussions.doSendReadReceipt else { return }
        guard let returnReceiptJSON = messageReceived.returnReceipt else { return }
        guard let contactCryptoId = messageReceived.contactIdentity?.cryptoId else { return }
        guard let ownedCryptoId = messageReceived.contactIdentity?.ownedIdentity?.cryptoId else { return }
        try obvEngine.postReturnReceiptWithElements(returnReceiptJSON.elements, andStatus: ReturnReceiptJSON.Status.read.rawValue, forContactCryptoId: contactCryptoId, ofOwnedIdentityCryptoId: ownedCryptoId)
    }
    
    
    private func processReceivedObvMessage(_ obvMessage: ObvMessage, overridePreviousPersistedMessage: Bool, completionHandler: (() -> Void)?) {

        assert(OperationQueue.current != internalQueue)

        os_log("Call to processReceivedObvMessage", log: log, type: .debug)
        
        let persistedItemJSON: PersistedItemJSON
        do {
            persistedItemJSON = try PersistedItemJSON.decode(obvMessage.messagePayload)
        } catch {
            os_log("Could not decode the message payload", log: log, type: .error)
            completionHandler?()
            assertionFailure()
            return
        }

        // Case #1: The ObvMessage contains a WebRTC signaling message
        
        if let webrtcMessage = persistedItemJSON.webrtcMessage {
            
            os_log("☎️ The message is a WebRTC signaling message", log: log, type: .debug)
            
            var contactId: OlvidUserId?
            ObvStack.shared.performBackgroundTaskAndWait { (context) in
                guard let persistedContactIdentity = try? PersistedObvContactIdentity.get(persisted: obvMessage.fromContactIdentity, whereOneToOneStatusIs: .any, within: context) else {
                    os_log("☎️ Could not find persisted contact associated with received webrtc message", log: log, type: .fault)
                    assertionFailure()
                    return
                }
                contactId = .known(contactObjectID: persistedContactIdentity.typedObjectID,
                                   ownCryptoId: obvMessage.fromContactIdentity.ownedIdentity.cryptoId,
                                   remoteCryptoId: obvMessage.fromContactIdentity.cryptoId,
                                   displayName: persistedContactIdentity.fullDisplayName)
            }
            if let contactId = contactId {
                ObvMessengerInternalNotification.newWebRTCMessageWasReceived(webrtcMessage: webrtcMessage,
                                                                             contactId: contactId,
                                                                             messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer,
                                                                             messageIdentifierFromEngine: obvMessage.messageIdentifierFromEngine)
                    .postOnDispatchQueue()
            } else {
                completionHandler?()
                return
            }
        }
        
        // Case #2: The ObvMessage contains a message
        
        if let messageJSON = persistedItemJSON.message {
            
            os_log("The message is an ObvMessage", log: log, type: .debug)

            let returnReceiptJSON = persistedItemJSON.returnReceipt

            do {
                try createPersistedMessageReceivedFromReceivedObvMessage(obvMessage, messageJSON: messageJSON, overridePreviousPersistedMessage: overridePreviousPersistedMessage, returnReceiptJSON: returnReceiptJSON)
            } catch let error {
                os_log("Could not create persisted message received from received message: %{public}@", log: log, type: .fault, error.localizedDescription)
                return
            }
            
        }
        
        // Case #3: The ObvMessage contains a shared configuration for a discussion
        
        if let discussionSharedConfiguration = persistedItemJSON.discussionSharedConfiguration {
            
            os_log("The message is shared discussion configuration", log: log, type: .debug)

            updateSharedConfigurationOfPersistedDiscussion(using: discussionSharedConfiguration,
                                                           fromContactIdentity: obvMessage.fromContactIdentity,
                                                           messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer)
            
        }

        // Case #4: The ObvMessage contains a JSON message indicating that some messages should be globally deleted in a discussion
        
        if let deleteMessagesJSON = persistedItemJSON.deleteMessagesJSON {
            os_log("The message is a delete message JSON", log: log, type: .debug)
            let op = WipeMessagesOperation(messagesToDelete: deleteMessagesJSON.messagesToDelete,
                                           groupId: deleteMessagesJSON.groupId,
                                           requester: obvMessage.fromContactIdentity,
                                           messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer,
                                           saveRequestIfMessageCannotBeFound: true)
            let composedOp = CompositionOfOneContextualOperation(op1: op, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
            internalQueue.addOperations([composedOp], waitUntilFinished: true)
            composedOp.logReasonIfCancelled(log: log)
        }
        
        // Case #5: The ObvMessage contains a JSON message indicating that a discussion should be globally deleted
        
        if let deleteDiscussionJSON = persistedItemJSON.deleteDiscussionJSON {
            os_log("The message is a delete discussion JSON", log: log, type: .debug)
            let op = GetAppropriateDiscussionOperation(contact: obvMessage.fromContactIdentity, groupId: deleteDiscussionJSON.groupId)
            internalQueue.addOperations([op], waitUntilFinished: true)
            op.logReasonIfCancelled(log: log)
            assert(op.discussionObjectID != nil || op.isCancelled)
            if let discussionObjectID = op.discussionObjectID {
                // An appropriate discussion to delete was found, we can delete it
                deletePersistedDiscussion(withObjectID: discussionObjectID, deletionType: .local, requestedBy: (obvMessage.fromContactIdentity, obvMessage.downloadTimestampFromServer), completionHandler: { _ in })
            }
        }
        
        // Case #6: The ObvMessage contains a JSON message indicating that a received message has been edited by the original sender

        if let updateMessageJSON = persistedItemJSON.updateMessageJSON {
            os_log("The message is an update message JSON", log: log, type: .debug)
            let op = EditTextBodyOfReceivedMessageOperation(newTextBody: updateMessageJSON.newTextBody,
                                                            requester: obvMessage.fromContactIdentity,
                                                            groupId: updateMessageJSON.groupId,
                                                            receivedMessageToEdit: updateMessageJSON.messageToEdit,
                                                            messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer,
                                                            saveRequestIfMessageCannotBeFound: true)
            let composedOp = CompositionOfOneContextualOperation(op1: op, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
            internalQueue.addOperations([composedOp], waitUntilFinished: true)
            composedOp.logReasonIfCancelled(log: log)
        }

        // Case #7: The ObvMessage contains a JSON message indicating that a reaction has been add by a contact

        if let reactionJSON = persistedItemJSON.reactionJSON {
                let op = UpdateReactionsOfMessageOperation(contactIdentity: obvMessage.fromContactIdentity,
                                                           reactionJSON: reactionJSON,
                                                           reactionTimestamp: obvMessage.messageUploadTimestampFromServer,
                                                           addPendingReactionIfMessageCannotBeFound: true)
                let composedOp = CompositionOfOneContextualOperation(op1: op, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
                internalQueue.addOperations([composedOp], waitUntilFinished: true)
                composedOp.logReasonIfCancelled(log: log)
        }
        
        // The inbox message has been processed, we can call the completion handler.
        // This completion handler is typically used to mark the message from deletion within the FetchManager in the engine.
        
        os_log("Calling the completion handler", log: log, type: .debug)
        completionHandler?()

    }
    
    
    /// This method is called when receiving a message from the engine that contains a shared configuration for a persisted discussion (typically, either one2one, or a group discussion owned by the send of this message).
    /// We use this new configuration to update ours.
    private func updateSharedConfigurationOfPersistedDiscussion(using discussionSharedConfiguration: DiscussionSharedConfigurationJSON, fromContactIdentity: ObvContactIdentity, messageUploadTimestampFromServer: Date) {
        let updatedDiscussionObjectID: NSManagedObjectID?
        do {
            let op = MergeDiscussionSharedExpirationConfigurationOperation(discussionSharedConfiguration: discussionSharedConfiguration, fromContactIdentity: fromContactIdentity)
            internalQueue.addOperations([op], waitUntilFinished: true)
            op.logReasonIfCancelled(log: log)
            updatedDiscussionObjectID = op.updatedDiscussionObjectID
        }
        guard let persistedDiscussionObjectID = updatedDiscussionObjectID else { return }
        do {
            let op = InsertCurrentDiscussionSharedConfigurationSystemMessageOperation(
                persistedDiscussionObjectID: persistedDiscussionObjectID,
                messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                fromContactIdentity: fromContactIdentity)
            internalQueue.addOperations([op], waitUntilFinished: true)
            op.logReasonIfCancelled(log: log)
        }
    }

    private func processReportCallEvent(callUUID: UUID, callReport: CallReport, groupId: (groupUid: UID, groupOwner: ObvCryptoId)?, ownedCryptoId: ObvCryptoId) {
        let op = ReportCallEventOperation(callUUID: callUUID, callReport: callReport, groupId: groupId, ownedCryptoId: ownedCryptoId)
        self.internalQueue.addOperations([op], waitUntilFinished: true)
        op.logReasonIfCancelled(log: self.log)
    }

    private func processCallHasBeenUpdated(call: CallEssentials, updateKind: CallUpdateKind) {
        guard case .state(let newState) = updateKind else { return }
        guard newState.isFinalState else { return }
        let op = ReportEndCallOperation(callUUID: call.uuid)
        self.internalQueue.addOperations([op], waitUntilFinished: true)
        op.logReasonIfCancelled(log: self.log)
    }
    
    
    private func processInsertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, markAsRead: Bool) {
        assert(OperationQueue.current != internalQueue)
        let op = InsertEndToEndEncryptedSystemMessageIfCurrentDiscussionIsEmptyOperation(discussionObjectID: discussionObjectID, markAsRead: markAsRead)
        let composedOp = CompositionOfOneContextualOperation(op1: op, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
    }

    
    /// This method *must* be called from `processReceivedObvMessage(...)`.
    /// This method is called when a new (received) ObvMessage is available. This message can come from one of the two followings places:
    /// - Either it was serialized within the notification extension, and deserialized here,
    /// - Either it was received by the main app.
    /// In the first case, this method is called using `overridePreviousPersistedMessage` set to `false`: we check whether the message already exists in database (using the message uid from server) and, if this is the
    /// case, we do nothing. If the message does not exist, we create it. In the second case, `overridePreviousPersistedMessage` set to `true` and we override any existing persisted message. In other words, messages
    /// comming from the engine always superseed messages comming from  the notification extension.
    private func createPersistedMessageReceivedFromReceivedObvMessage(_ obvMessage: ObvMessage, messageJSON: MessageJSON, overridePreviousPersistedMessage: Bool, returnReceiptJSON: ReturnReceiptJSON?) throws {

        assert(OperationQueue.current != internalQueue)

        os_log("Call to createPersistedMessageReceivedFromReceivedObvMessage for obvMessage %{public}@", log: log, type: .debug, obvMessage.messageIdentifierFromEngine.debugDescription)

        // Create a persisted message received
        let op1 = CreatePersistedMessageReceivedFromReceivedObvMessageOperation(obvMessage: obvMessage,
                                                                                messageJSON: messageJSON,
                                                                                overridePreviousPersistedMessage: overridePreviousPersistedMessage,
                                                                                returnReceiptJSON: returnReceiptJSON,
                                                                                obvEngine: obvEngine)
        // Check for a previously received delete or edit request and apply it
        let op2 = ApplyExistingRemoteDeleteAndEditRequestOperation(obvMessage: obvMessage, messageJSON: messageJSON)
        // Look for a previously received reaction for that message. If found, apply it.
        let op3 = ApplyPendingReactionsOperation(obvMessage: obvMessage, messageJSON: messageJSON)

        let composedOp = CompositionOfThreeContextualOperations(op1: op1, op2: op2, op3: op3, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())

        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)

        // If the composed operation did not cancel, we know the message has been persisted. We can send a return receipt.
        
        if !composedOp.isCancelled {
            
            // If there is a return receipt within the json item we received, we use it to send a return receipt for the received obvMessage
            
            if let returnReceiptJSON = returnReceiptJSON {
                do {
                    try obvEngine.postReturnReceiptWithElements(returnReceiptJSON.elements, andStatus: ReturnReceiptJSON.Status.delivered.rawValue, forContactCryptoId: obvMessage.fromContactIdentity.cryptoId, ofOwnedIdentityCryptoId: obvMessage.fromContactIdentity.ownedIdentity.cryptoId)
                } catch {
                    os_log("The Return Receipt could not be posted", log: log, type: .fault)
                }
            }

        }
        
    }

    
    private func logReasonOfCancelledOperations(_ operations: [OperationThatCanLogReasonForCancel]) {
        let cancelledOps = operations.filter({ $0.isCancelled })
        for op in cancelledOps {
            op.logReasonIfCancelled(log: log)
        }
    }
    
    /// This method allows to post messages that were still `unprocessed` within a discussion. This typically happens when the user post a message within a discussion
    /// before the channel with the contact is established (i.e., before a contact device is added), or when the user post a message in an empty group and adds a member
    /// afterwards.
    private func sendUnprocessedMessages(within discussion: PersistedDiscussion) {
        assert(OperationQueue.current != internalQueue)
        let sentMessages = discussion.messages.compactMap { $0 as? PersistedMessageSent }
        let objectIDOfUnprocessedMessages = sentMessages.filter({ $0.status == .unprocessed || $0.status == .processing }).map({ $0.typedObjectID })
        let ops: [(ComputeExtendedPayloadOperation, SendUnprocessedPersistedMessageSentOperation)] = objectIDOfUnprocessedMessages.map({
                let op1 = ComputeExtendedPayloadOperation(persistedMessageSentObjectID: $0)
                let op2 = SendUnprocessedPersistedMessageSentOperation(persistedMessageSentObjectID: $0, extendedPayloadProvider: op1, obvEngine: obvEngine)
                return (op1, op2)
            })
        let composedOps = ops.map({ CompositionOfTwoContextualOperations(op1: $0.0, op2: $0.1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier()) })
        internalQueue.addOperations(composedOps, waitUntilFinished: true)
    }
    
}


fileprivate struct MessageIdentifierFromEngineAndOwnedCryptoId: Hashable {
    
    let messageIdentifierFromEngine: Data
    let ownedCryptoId: ObvCryptoId
    
}

// This extension makes it possible to use kvo on the user defaults dictionary used by the share extension

private extension UserDefaults {
    @objc dynamic var objectsModifiedByShareExtension: String {
        return ObvMessengerConstants.objectsModifiedByShareExtension
    }
}
