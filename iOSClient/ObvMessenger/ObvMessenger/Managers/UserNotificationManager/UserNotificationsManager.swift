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

import UIKit
import UserNotifications
import os.log
import ObvEngine
import ObvTypes
import CoreData
import AVFAudio

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
        observeRequestIdentifiersOfSilentNotificationsAddedByExtension()
        observeTheBodyOfPersistedMessageReceivedDidChangeNotifications()
        observePersistedMessageReceivedWasDeletedNotifications()
        /* observeUserRequestedDeletionOfPersistedDiscussionNotifications() */
        observeReportCallEventNotifications()
        observePersistedMessageReactionReceivedWasDeletedNotifications()
        observePersistedMessageReactionReceivedWasInsertedOrUpdatedNotifications()
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
            let urls = Set(try FileManager.default.contentsOfDirectory(at: ObvMessengerConstants.containerURL.forNotificationAttachments, includingPropertiesForKeys: nil))
            identifiersOnDisk = Set(urls.map({ $0.lastPathComponent }))
        } catch {
            os_log("Cannot clean notification attachements: %{public}@", log: log, type: .fault, error.localizedDescription)
            return
        }

        // Delete unused attachement notifications
        let identifiersToDeleteFromDisk = identifiersOnDisk.subtracting(identifiersInNotificationCenter)
        var count = 0
        for identifier in identifiersToDeleteFromDisk {
            let url = ObvMessengerConstants.containerURL.forNotificationAttachments.appendingPathComponent(identifier)
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
                    case .groupV1(let objectID):
                        guard let contactGroup = try? PersistedContactGroup.get(objectID: objectID.objectID, within: context) else { return }
                        discussion = contactGroup.discussion
                    case .groupV2(let objectID):
                        guard let group = try? PersistedGroupV2.get(objectID: objectID, within: context) else { return }
                        discussion = group.discussion
                    case .none:
                        discussion = contactIdentity.oneToOneDiscussion
                    }
                    guard let discussion = discussion, discussion.status == .active else { return }

                    var contactIdentityDisplayName = contactIdentity.customDisplayName ?? contactIdentity.identityCoreDetails?.getDisplayNameWithStyle(.full) ?? contactIdentity.fullDisplayName
                    if let participantCount = participantCount, participantCount > 1 {
                        contactIdentityDisplayName += " + \(participantCount - 1)"
                    }

                    do {
                        let discussionKind = try discussion.toStruct()
                        let infos = UserNotificationCreator.MissedCallNotificationInfos(
                            contact: try contactIdentity.toStruct(),
                            discussionKind: discussionKind,
                            urlForStoringPNGThumbnail: nil)
                        let (notificationId, notificationContent) = UserNotificationCreator.createMissedCallNotification(callUUID: callUUID, infos: infos, badge: nil)
                        UserNotificationsScheduler.filteredScheduleNotification(
                            discussionKind: discussionKind,
                            notificationId: notificationId,
                            notificationContent: notificationContent,
                            notificationCenter: notificationCenter)
                    } catch {
                        assertionFailure()
                        return
                    }
                case .rejectedIncomingCallBecauseOfDeniedRecordPermission:
                    switch AVAudioSession.sharedInstance().recordPermission {
                    case .undetermined:
                        let notificationCenter = UNUserNotificationCenter.current()
                        let (notificationId, notificationContent) = UserNotificationCreator.createRequestRecordPermissionNotification()
                        UserNotificationsScheduler.scheduleNotification(notificationId: notificationId, notificationContent: notificationContent, notificationCenter: notificationCenter)
                    case .denied:
                        let notificationCenter = UNUserNotificationCenter.current()
                        let (notificationId, notificationContent) = UserNotificationCreator.createDeniedRecordPermissionNotification()
                        UserNotificationsScheduler.scheduleNotification(notificationId: notificationId, notificationContent: notificationContent, notificationCenter: notificationCenter)
                    case .granted:
                        break
                    @unknown default:
                        break
                    }
                case .acceptedOutgoingCall, .acceptedIncomingCall, .rejectedOutgoingCall, .rejectedIncomingCall, .busyOutgoingCall, .unansweredOutgoingCall, .uncompletedOutgoingCall, .newParticipantInIncomingCall, .newParticipantInOutgoingCall:
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
        observationTokens.append(PersistedMessageReceivedNotification.observePersistedMessageReceivedWasDeleted { (_, messageIdentifierFromEngine, _, _, _) in
            let notificationCenter = UNUserNotificationCenter.current()
            let notificationId = ObvUserNotificationIdentifier.newMessage(messageIdentifierFromEngine: messageIdentifierFromEngine)
            ObvDisplayableLogs.shared.log("📣 Removing a user notification as its corresponding PersistedMessageReceived was deleted")
            UserNotificationsScheduler.removeAllNotificationWithIdentifier(notificationId, notificationCenter: notificationCenter)
        })
    }

    private func observeTheBodyOfPersistedMessageReceivedDidChangeNotifications() {
        observationTokens.append(PersistedMessageReceivedNotification.observeTheBodyOfPersistedMessageReceivedDidChange { (persistedMessageReceivedObjectID) in
            ObvStack.shared.performBackgroundTask { (context) in
                let notificationCenter = UNUserNotificationCenter.current()
                guard let messageReceived = try? PersistedMessageReceived.get(with: persistedMessageReceivedObjectID, within: context) as? PersistedMessageReceived else { assertionFailure(); return }
                let discussion = messageReceived.discussion
                do {
                    let infos = UserNotificationCreator.NewMessageNotificationInfos(
                        messageReceived: try messageReceived.toStruct(),
                        attachmentLocation: .notificationID,
                        urlForStoringPNGThumbnail: nil)
                    let (notificationId, notificationContent) = UserNotificationCreator.createNewMessageNotification(infos: infos, badge: nil)
                    let discussionKind = try discussion.toStruct()
                    UserNotificationsScheduler.filteredScheduleNotification(discussionKind: discussionKind, notificationId: notificationId, notificationContent: notificationContent, notificationCenter: notificationCenter)
                } catch {
                    assertionFailure()
                    return
                }
            }
        })
    }
    
    
    // Eeach time the notification extension adds a notification with minimal content (e.g., when it fails to decrypt the notification), we execute the following block.
    // This block first removes all "minimal" notifications and search for unread messages which do not have a corresponding user notifications. The missing notifications are then added.
    private func observeRequestIdentifiersOfSilentNotificationsAddedByExtension() {
        guard let userDefaults = self.userDefaults else {
            os_log("The user defaults database is not set", log: log, type: .fault)
            return
        }
        let token = userDefaults.observe(\.requestIdentifiersOfSilentNotificationsAddedByExtension) { [weak self] (userDefaults, change) in
            guard let _self = self else { return }
            _self.removeAllSilentNotificationsAddedByExtension()
            _self.addMissingNewMessageNotifications()
        }
        kvoTokens.append(token)
    }
    
    
    private func removeAllSilentNotificationsAddedByExtension() {
        guard let userDefaults = self.userDefaults else {
            os_log("The user defaults database is not set", log: log, type: .fault)
            return
        }
        guard let requestIdentifiersWithDatesOfSilentNotificationsAddedByExtension = userDefaults.notificationRequestIdentifiersWithDates(forKey: ObvMessengerConstants.requestIdentifiersOfSilentNotificationsAddedByExtension) else {
            os_log("Could not get the request identifiers of minimal notifications added by the extension", log: log, type: .error)
            return
        }
        let requestIdentifiersOfSilentNotificationsAddedByExtension = requestIdentifiersWithDatesOfSilentNotificationsAddedByExtension.map { $0.requestIdentifier }
        let notificationCenter = UNUserNotificationCenter.current()
        ObvDisplayableLogs.shared.log("📣 Removing all silent notifications added by the share extension")
        notificationCenter.removeDeliveredNotifications(withIdentifiers: requestIdentifiersOfSilentNotificationsAddedByExtension)
    }
    
    
    private func addMissingNewMessageNotifications() {
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.getDeliveredNotifications { [weak self] (deliveredNotifications) in
            guard let _self = self else { return }
            let log = _self.log
            let messageIdentifiersOfDeliveredNotifications = Set(deliveredNotifications.compactMap { $0.request.content.userInfo["messageIdentifierForNotification"] as? String })
            ObvStack.shared.performBackgroundTaskAndWait { (context) in
                let newMessagesAndNotificationIdentifiers: [(message: PersistedMessageReceived, notificationIdentifier: String)]
                do {
                    let newMessages = try PersistedMessageReceived.getAllNew(with: context)
                    newMessagesAndNotificationIdentifiers = newMessages.compactMap {
                        ($0, ObvUserNotificationIdentifier.newMessage(messageIdentifierFromEngine: $0.messageIdentifierFromEngine).getIdentifier())
                    }
                } catch {
                    os_log("Could not get new messages", log: log, type: .fault)
                    return
                }
                let messageIdentifiersOfNewMessages = Set(newMessagesAndNotificationIdentifiers.map { $0.notificationIdentifier })
                guard !messageIdentifiersOfNewMessages.isEmpty else { return }
                let messageIdentifiersOfMissingNotifications = messageIdentifiersOfNewMessages.subtracting(messageIdentifiersOfDeliveredNotifications)
                guard !messageIdentifiersOfMissingNotifications.isEmpty else { return }
                for (newMessage, identifierForNotification) in newMessagesAndNotificationIdentifiers {
                    guard messageIdentifiersOfMissingNotifications.contains(identifierForNotification) else { continue }
                    guard let newMessageStruct = try? newMessage.toStruct() else { assertionFailure(); continue }
                    guard let discussionKind = try? newMessage.discussion.toStruct() else { assertionFailure(); continue }
                    let infos = UserNotificationCreator.NewMessageNotificationInfos(
                        messageReceived: newMessageStruct,
                        attachmentLocation: .notificationID,
                        urlForStoringPNGThumbnail: nil)
                    let (notificationId, notificationContent) = UserNotificationCreator.createNewMessageNotification(infos: infos, badge: nil)
                    UserNotificationsScheduler.filteredScheduleNotification(discussionKind: discussionKind, notificationId: notificationId, notificationContent: notificationContent, notificationCenter: notificationCenter)
                }
            }
        }
    }

    /// When a received reaction message is deleted (for whatever reason), we remove any existing notification related to this reaction.
    private func observePersistedMessageReactionReceivedWasDeletedNotifications() {
        observationTokens.append(ObvMessengerCoreDataNotification.observePersistedMessageReactionReceivedWasDeletedOnSentMessage { (sentMessagePermanentID, contactPermanentID) in
            let notificationCenter = UNUserNotificationCenter.current()
            let notificationId = ObvUserNotificationIdentifier.newReaction(messagePermanentID: sentMessagePermanentID, contactPermanentId: contactPermanentID)

            // Remove the notification if it was added by the app
            ObvDisplayableLogs.shared.log("📣 Removing a user notification (added by the app) as its corresponding PersistedMessageReaction was deleted")
            UserNotificationsScheduler.removeAllNotificationWithIdentifier(notificationId, notificationCenter: notificationCenter)

            // Remove the notification if it was added by the extension
            Task {
                ObvDisplayableLogs.shared.log("📣 Removing a user notification (added by the extension) as its corresponding PersistedMessageReaction was deleted")
                await UserNotificationsScheduler.removeReactionNotificationsAddedByExtension(with: notificationId, notificationCenter: notificationCenter)
            }
        })
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
                
                do {
                    let infos = UserNotificationCreator.ReactionNotificationInfos(
                        messageSent: try message.toStruct(),
                        contact: try contact.toStruct(),
                        urlForStoringPNGThumbnail: nil)
                    let (notificationId, notificationContent) = UserNotificationCreator.createReactionNotification(infos: infos, emoji: reactionReceived.emoji, reactionTimestamp: reactionReceived.timestamp)
                    
                    let notificationCenter = UNUserNotificationCenter.current()
                    let reactionsTimestamps = UserNotificationsScheduler.getAllReactionsTimestampAddedByExtension(with: notificationId, notificationCenter: notificationCenter)
                    let discussion = message.discussion

                    if reactionsTimestamps.count == 1,
                       let timestamp = reactionsTimestamps.first,
                       timestamp >= reactionReceived.timestamp {

                        // If there is only one notifications in the center that is more recent that the given one, we let it.
                        return
                    } else {
                        // We remove all the notification that comes from the extension.
                        Task {
                            ObvDisplayableLogs.shared.log("📣 Removing a user notification (added by the extension) as its corresponding PersistedMessageReaction was inserted or deleted")
                            await UserNotificationsScheduler.removeReactionNotificationsAddedByExtension(with: notificationId, notificationCenter: notificationCenter)
                        }
                        // And replace them with a notification that is not nececarry the more recent (in the case that multiple reaction update messages have been received) and replace by a single notification with notificationID as request identifier.
                        UserNotificationsScheduler.filteredScheduleNotification(
                            discussionKind: try discussion.toStruct(),
                            notificationId: notificationId,
                            notificationContent: notificationContent,
                            notificationCenter: notificationCenter)
                    }
                } catch {
                    os_log("Could not notifiy: %{public}@", log: log, type: .fault, error.localizedDescription)
                    return
                }
                
            }
        })
    }
}


// MARK: - Managing User Notifications related to invitations

extension UserNotificationsManager {
    
    private func observeNewPersistedInvitationNotifications() {
        let token = ObvMessengerCoreDataNotification.observeNewOrUpdatedPersistedInvitation { (obvDialog, persistedInvitationUUID) in
            let notificationCenter = UNUserNotificationCenter.current()
            notificationCenter.getNotificationSettings { (settings) in
                // Do not schedule notifications if not authorized.
                guard settings.authorizationStatus == .authorized && settings.alertSetting == .enabled else { return }
                guard let (notificationId, notificationContent) = UserNotificationCreator.createInvitationNotification(obvDialog: obvDialog, persistedInvitationUUID: persistedInvitationUUID) else { return }
                UserNotificationsScheduler.scheduleNotification(notificationId: notificationId, notificationContent: notificationContent, notificationCenter: notificationCenter)
            }
        }
        observationTokens.append(token)
    }
}

// This extension makes it possible to use kvo on the user defaults dictionary used by the notification extension

private extension UserDefaults {
    @objc dynamic var requestIdentifiersOfSilentNotificationsAddedByExtension: String {
        return ObvMessengerConstants.requestIdentifiersOfSilentNotificationsAddedByExtension
    }
}
