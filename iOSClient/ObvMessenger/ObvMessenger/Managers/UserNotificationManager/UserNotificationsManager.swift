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
import UserNotifications
import os.log
import ObvEngine
import ObvTypes
import CoreData
import AVFAudio
import ObvUICoreData
import ObvSettings
import OlvidUtils


final class UserNotificationsManager: NSObject {
    
    private var observationTokens = [NSObjectProtocol]()
    private var kvoTokens = [NSKeyValueObservation]()

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: UserNotificationsManager.self))

    private let userNotificationCenterDelegate: UserNotificationCenterDelegate
    
    private let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier)
    
    // MARK: - Initializer
    
    override init() {

        self.userNotificationCenterDelegate = UserNotificationCenterDelegate()
        super.init()
        
        // Register as the UNUserNotificationCenter's delegate
        // This must be set before the app finished launching.
        // See https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate
        
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.delegate = userNotificationCenterDelegate

        // Register the custom actions/categories
        
        let categories = Set(UserNotificationCategory.allCases.map { $0.getCategory() })
        notificationCenter.setNotificationCategories(categories)

        // Bootstrap
        Task {
            await deleteObsoleteNotificationAttachments()
        }

        // Observe notifications
        
        observeNewPersistedInvitationNotifications()
        observeTheBodyOfPersistedMessageReceivedDidChangeNotifications()
        observePersistedMessageReceivedWasDeletedNotifications()
        /* observeUserRequestedDeletionOfPersistedDiscussionNotifications() */
        observeReportCallEventNotifications()
        observePersistedMessageReactionReceivedWasDeletedNotifications()
        observePersistedMessageReactionReceivedWasInsertedOrUpdatedNotifications()
        removeAllNotificationsWhenHidingProfile()
    }
    
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
}

// MARK: - Bootstrap

extension UserNotificationsManager {

    /// Deletes the attachments deletes the notification attachments that are not used by any existing notification in the notification center.
    /// These attachments were certainly created for notifications that do not exist anymore.
    private func deleteObsoleteNotificationAttachments() async {
        let notificationCenter = UNUserNotificationCenter.current()

        // Compute the set of existing notifications
        var identifiersInNotificationCenter = Set<String>()
        for identifier in await notificationCenter.pendingNotificationRequests().map({ $0.identifier }) {
            identifiersInNotificationCenter.insert(identifier)
        }
        for identifier in await notificationCenter.deliveredNotifications().map({ $0.request.identifier }) {
            identifiersInNotificationCenter.insert(identifier)
        }

        // Compute the set of attachments within the notifications
        let identifiersOnDisk: Set<String>
        do {
            let urls = Set(try FileManager.default.contentsOfDirectory(at: ObvUICoreDataConstants.ContainerURL.forNotificationAttachments.url, includingPropertiesForKeys: nil))
            identifiersOnDisk = Set(urls.map({ $0.lastPathComponent }))
        } catch {
            os_log("Cannot clean notification attachements: %{public}@", log: log, type: .fault, error.localizedDescription)
            return
        }

        // Delete unused attachement notifications
        let identifiersToDeleteFromDisk = identifiersOnDisk.subtracting(identifiersInNotificationCenter)
        var count = 0
        for identifier in identifiersToDeleteFromDisk {
            let url = ObvUICoreDataConstants.ContainerURL.forNotificationAttachments.appendingPathComponent(identifier)
            do {
                try FileManager.default.removeItem(at: url)
                count += 1
            } catch {
                os_log("Cannot delete unused notification attachement: %{public}@", log: self.log, type: .fault, error.localizedDescription)
                assertionFailure()
                continue
            }
        }
        os_log("Cleaned %{public}d notification attachement(s).", log: log, type: .info, count)
    }

}

// MARK: - Managing User Notifications related to received messages

extension UserNotificationsManager {

    private func observeReportCallEventNotifications() {
        observationTokens.append(VoIPNotification.observeReportCallEvent { (callUUID, callReport, groupId, ownedCryptoId) in
            ObvStack.shared.performBackgroundTask { (context) in

                switch callReport {
                case .missedIncomingCall(caller: let caller, participantCount: let participantCount),
                     .filteredIncomingCall(caller: let caller, participantCount: let participantCount):
                    guard let contactObjectID = caller?.contactObjectID else { return }
                    let notificationCenter = UNUserNotificationCenter.current()

                    guard let contactIdentity = try? PersistedObvContactIdentity.get(objectID: contactObjectID, within: context) else { assertionFailure(); return }

                    let discussion: PersistedDiscussion?
                    switch groupId {
                    case .groupV1(groupV1Identifier: let groupV1Identifier):
                        guard let contactGroup = try? PersistedContactGroup.getContactGroup(groupIdentifier: groupV1Identifier, ownedCryptoId: ownedCryptoId, within: context) else { return }
                        discussion = contactGroup.discussion
                    case .groupV2(groupV2Identifier:let groupV2Identifier):
                        guard let group = try? PersistedGroupV2.get(ownIdentity: ownedCryptoId, appGroupIdentifier: groupV2Identifier, within: context) else { return }
                        discussion = group.discussion
                    case nil:
                        discussion = contactIdentity.oneToOneDiscussion
                    }
                    guard let discussion = discussion, discussion.status == .active else { return }

                    var contactIdentityDisplayName = contactIdentity.customDisplayName ?? contactIdentity.identityCoreDetails?.getDisplayNameWithStyle(.full) ?? contactIdentity.fullDisplayName
                    if let participantCount = participantCount, participantCount > 1 {
                        contactIdentityDisplayName += " + \(participantCount - 1)"
                    }

                    do {
                        let discussionKind = try discussion.toStructKind()
                        let infos = UserNotificationCreator.MissedCallNotificationInfos(
                            contact: try contactIdentity.toStruct(),
                            discussionKind: discussionKind)
                        let (notificationId, notificationContent) = UserNotificationCreator.createMissedCallNotification(callUUID: callUUID, infos: infos, badge: nil)
                        UserNotificationsScheduler.filteredScheduleNotification(
                            discussionKind: discussionKind,
                            notificationId: notificationId,
                            notificationContent: notificationContent,
                            notificationCenter: notificationCenter,
                            mentions: [], //we don't have any mentions here since it's a call
                            messageRepliedToStructure: nil,
                            immediately: false)
                    } catch {
                        assertionFailure()
                        return
                    }
                case .rejectedIncomingCallBecauseOfDeniedRecordPermission:
                    switch AVAudioSession.sharedInstance().recordPermission {
                    case .undetermined:
                        let notificationCenter = UNUserNotificationCenter.current()
                        let (notificationId, notificationContent) = UserNotificationCreator.createRequestRecordPermissionNotification()
                        UserNotificationsScheduler.scheduleNotification(notificationId: notificationId, notificationContent: notificationContent, notificationCenter: notificationCenter, immediately: false)
                    case .denied:
                        let notificationCenter = UNUserNotificationCenter.current()
                        let (notificationId, notificationContent) = UserNotificationCreator.createDeniedRecordPermissionNotification()
                        UserNotificationsScheduler.scheduleNotification(notificationId: notificationId, notificationContent: notificationContent, notificationCenter: notificationCenter, immediately: false)
                    case .granted:
                        break
                    @unknown default:
                        break
                    }
                case .acceptedOutgoingCall, .acceptedIncomingCall, .rejectedOutgoingCall, .rejectedIncomingCall, .busyOutgoingCall, .unansweredOutgoingCall, .uncompletedOutgoingCall, .newParticipantInIncomingCall, .newParticipantInOutgoingCall, .answeredOrRejectedOnOtherDevice, .rejectedIncomingCallAsTheReceiveCallsOnThisDeviceSettingIsFalse:
                    // Do nothing
                    break
                }
            }
        })
    }
    
    /// When the user decides to delete a discussion, it would too expensive to check whethere there exists a notification for one of the messages within the discussion.
    /// But we do want to delete such a notification if one exist. For now, we simply delete all notifications.
    /// 2022-10-31 : We comment this method since it is probably not pertinent: when deleting a discussion, we receive a `PersistedMessageReceivedWasDeleted` for each deleted message, and delete the associated user notification already. No need to do it twice.
    /**
    private func observeUserRequestedDeletionOfPersistedDiscussionNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeUserRequestedDeletionOfPersistedDiscussion() { (_, _, _) in
            let notificationCenter = UNUserNotificationCenter.current()
            ObvDisplayableLogs.shared.log("📣 Removing all delivered and pending notifications as the user requested the deletion of a persisted discussion")
            notificationCenter.removeAllDeliveredNotifications()
            notificationCenter.removeAllPendingNotificationRequests()
        })
    }
     */


    /// When a received message is deleted (for whatever reason), we want to remove any existing notification related
    /// to this message
    private func observePersistedMessageReceivedWasDeletedNotifications() {
        observationTokens.append(ObvMessengerCoreDataNotification.observePersistedMessageReceivedWasDeleted { (_, messageIdentifierFromEngine, _, _, _) in
            let notificationCenter = UNUserNotificationCenter.current()
            let notificationId = ObvUserNotificationIdentifier.newMessage(messageIdentifierFromEngine: messageIdentifierFromEngine)
            //ObvDisplayableLogs.shared.log("📣 Removing a user notification as its corresponding PersistedMessageReceived was deleted")
            UserNotificationsScheduler.removeAllNotificationWithIdentifier(notificationId, notificationCenter: notificationCenter)
        })
    }

    private func observeTheBodyOfPersistedMessageReceivedDidChangeNotifications() {
        observationTokens.append(ObvMessengerCoreDataNotification.observeTheBodyOfPersistedMessageReceivedDidChange { (persistedMessageReceivedObjectID) in
            ObvStack.shared.performBackgroundTask { (context) in
                let notificationCenter = UNUserNotificationCenter.current()
                guard let messageReceived = try? PersistedMessageReceived.get(with: persistedMessageReceivedObjectID, within: context) as? PersistedMessageReceived else { assertionFailure(); return }
                guard let discussion = messageReceived.discussion else { assertionFailure(); return }
                do {
                    let notificationId = ObvUserNotificationIdentifier.newMessage(messageIdentifierFromEngine: messageReceived.messageIdentifierFromEngine)

                    if messageReceived.textBody == nil {
                        assert(messageReceived.isWiped)
                        // The message should be wiped, we remove associated notifications to not expose previous body.
                        //ObvDisplayableLogs.shared.log("📣 Removing a user notification as its corresponding PersistedMessageReceived was wiped")
                        UserNotificationsScheduler.removeAllNotificationWithIdentifier(notificationId, notificationCenter: notificationCenter)
                    } else {
                        let messageReceivedStruct = try messageReceived.toStruct()
                        let messageRepliedToStructure = try messageReceived.messageRepliedTo?.toAbstractStructure()
                        let infos = UserNotificationCreator.NewMessageNotificationInfos(
                            messageReceived: messageReceivedStruct,
                            attachmentLocation: .notificationID)
                        let (notificationId, notificationContent) = UserNotificationCreator.createNewMessageNotification(infos: infos, badge: nil, addNotificationSilently: true)
                        let discussionKind = try discussion.toStructKind()
                        UserNotificationsScheduler.filteredScheduleNotification(discussionKind: discussionKind,
                                                                                notificationId: notificationId,
                                                                                notificationContent: notificationContent,
                                                                                notificationCenter: notificationCenter,
                                                                                mentions: messageReceivedStruct.mentions,
                                                                                messageRepliedToStructure: messageRepliedToStructure,
                                                                                immediately: true) // we can't edit the contents of a previously delivered notification; the system will automagically remove the previously delivered notification and push a new one

                    }
                } catch {
                    assertionFailure()
                    return
                }
            }
        })
    }
    

    /// When a received reaction message is deleted (for whatever reason), we remove any existing notification related to this reaction.
    private func observePersistedMessageReactionReceivedWasDeletedNotifications() {
        observationTokens.append(ObvMessengerCoreDataNotification.observePersistedMessageReactionReceivedWasDeletedOnSentMessage { [weak self] (sentMessagePermanentID, contactPermanentID) in
            self?.deleteNotificationsReaction(sentMessagePermanentID: sentMessagePermanentID,
                                              contactPermanentID: contactPermanentID)
        })
    }

    private func deleteNotificationsReaction(sentMessagePermanentID: MessageSentPermanentID, contactPermanentID: ObvManagedObjectPermanentID<PersistedObvContactIdentity>) {
        let notificationCenter = UNUserNotificationCenter.current()
        let notificationId = ObvUserNotificationIdentifier.newReaction(messagePermanentID: sentMessagePermanentID, contactPermanentId: contactPermanentID)

        // Remove the notification if it was added by the app
        //ObvDisplayableLogs.shared.log("📣 Removing a user notification (added by the app) as its corresponding PersistedMessageReaction was deleted")
        UserNotificationsScheduler.removeAllNotificationWithIdentifier(notificationId, notificationCenter: notificationCenter)

        // Remove the notification if it was added by the extension
        Task {
            //ObvDisplayableLogs.shared.log("📣 Removing a user notification (added by the extension) as its corresponding PersistedMessageReaction was deleted")
            await UserNotificationsScheduler.removeReactionNotificationsAddedByExtension(with: notificationId, notificationCenter: notificationCenter)
        }

    }

    
    /// If there is only a single notification that comes from the extension and if it corresponds to the given reaction, we let it (even if the request identifier is an UUID) if it is more recent than the given one.
    /// If there are several notifications that comes from the extension, we only know that the given reaction corresponds to one of them, we start by removing all notifications that come from the extension
    /// and schedule a notification with a nice notification id. The next reaction will replace this new notification if it is more recent. The only deficit of this, is when the extension will decryp n reactions
    /// and shows n notification : launching the app will remove these n notifications and replace them by a single one, that can be updated (n - 1) times in the worst case if the reaction are processed in the
    /// wrong order. But it is a corner case to have a user that will react n times to the same message...
    private func observePersistedMessageReactionReceivedWasInsertedOrUpdatedNotifications() {
        observationTokens.append(ObvMessengerCoreDataNotification.observePersistedMessageReactionReceivedWasInsertedOrUpdated { [weak self] objectID in
            guard let _self = self else { return }
            let log = _self.log
            ObvStack.shared.performBackgroundTask { context in
                guard let reactionReceived = try? PersistedMessageReaction.get(with: objectID.downcast, within: context) as? PersistedMessageReactionReceived else { return }
                guard let message = reactionReceived.message as? PersistedMessageSent else { return }
                guard let contact = reactionReceived.contact else { return }
                
                if let emoji = reactionReceived.emoji {
                    do {
                        let messageStruct = try message.toStruct()
                        let messageRepliedToStructure = try message.messageRepliedTo?.toAbstractStructure()
                        let infos = UserNotificationCreator.ReactionNotificationInfos(
                            messageSent: messageStruct,
                            contact: try contact.toStruct())
                        let (notificationId, notificationContent) = UserNotificationCreator.createReactionNotification(infos: infos, emoji: emoji, reactionTimestamp: reactionReceived.timestamp)

                        let notificationCenter = UNUserNotificationCenter.current()
                        let reactionsTimestamps = UserNotificationsScheduler.getAllReactionsTimestampAddedByExtension(with: notificationId, notificationCenter: notificationCenter)
                        let discussionKind = messageStruct.discussionKind

                        if reactionsTimestamps.count == 1,
                           let timestamp = reactionsTimestamps.first,
                           timestamp >= reactionReceived.timestamp {
                            // There is only one notification in the notification center and it is more recent than the received one. We leave the existing notification as is.
                            return
                        } else {
                            // We remove all the notifications that come from the extension.
                            Task {
                                //ObvDisplayableLogs.shared.log("📣 Removing a user notification (added by the extension) as its corresponding PersistedMessageReaction was inserted or deleted")
                                await UserNotificationsScheduler.removeReactionNotificationsAddedByExtension(with: notificationId, notificationCenter: notificationCenter)
                            }
                            // And replace them with a notification that is not necessary the most recent (in the case where multiple reaction update messages have been received) and replace by a single notification with notificationID as request identifier.
                            UserNotificationsScheduler.filteredScheduleNotification(
                                discussionKind: discussionKind,
                                notificationId: notificationId,
                                notificationContent: notificationContent,
                                notificationCenter: notificationCenter,
                                mentions: messageStruct.mentions,
                                messageRepliedToStructure: messageRepliedToStructure,
                                immediately: false)
                        }
                    } catch {
                        os_log("Could not notifiy: %{public}@", log: log, type: .fault, error.localizedDescription)
                        return
                    }
                } else {
                    _self.deleteNotificationsReaction(sentMessagePermanentID: message.objectPermanentID,
                                                      contactPermanentID: contact.objectPermanentID)
                }
            }
        })
    }
    
    
    /// When a profile (owned identity) is hidden, we remove all notifications to make sure no notification concerning this hidden profile is shown.
    private func removeAllNotificationsWhenHidingProfile() {
        observationTokens.append(ObvMessengerCoreDataNotification.observeOwnedIdentityHiddenStatusChanged { _, isHidden in
            guard isHidden else { return }
            let notificationCenter = UNUserNotificationCenter.current()
            notificationCenter.removeAllDeliveredNotifications()
            notificationCenter.removeAllPendingNotificationRequests()
        })
    }
    
}


// MARK: - Managing User Notifications related to invitations

extension UserNotificationsManager {
    
    private func observeNewPersistedInvitationNotifications() {
        let token = ObvMessengerCoreDataNotification.observeNewOrUpdatedPersistedInvitation { (concernedOwnedIdentityIsHidden, obvDialog, persistedInvitationUUID) in
            guard !concernedOwnedIdentityIsHidden else { return }
            let notificationCenter = UNUserNotificationCenter.current()
            notificationCenter.getNotificationSettings { (settings) in
                // Do not schedule notifications if not authorized.
                guard settings.authorizationStatus == .authorized && settings.alertSetting == .enabled else { return }
                guard let (notificationId, notificationContent) = UserNotificationCreator.createInvitationNotification(obvDialog: obvDialog, persistedInvitationUUID: persistedInvitationUUID) else { return }
                UserNotificationsScheduler.scheduleNotification(notificationId: notificationId, notificationContent: notificationContent, notificationCenter: notificationCenter, immediately: false)
            }
        }
        observationTokens.append(token)
    }
}
