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

import UserNotifications
import ObvEngine
import os.log
import OlvidUtils
import ObvTypes
import ObvCrypto
import ObvUICoreData
import ObvSettings


final class NotificationService: UNNotificationServiceExtension {

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: NotificationService.self))
    
    var contentHandler: ((UNNotificationContent) -> Void)?
    var silentAttemptContent: UNNotificationContent?
    var fullAttemptContent: UNNotificationContent?
    var requestIdentifier: String?
    static let runningLog = RunningLogError()
    
    private let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier)
    private let internalQueue = DispatchQueue(label: "NotificationService internal queue")
    
    private static var obvEngine: ObvEngine?
    
    private static func makeError(message: String) -> Error {
        NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message])
    }

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        
        os_log("Entering didReceive method", log: log, type: .debug)
        
        // Store the request and content handler, and create a minimal notification to instantiate the full attempt content.
        // This minimal attempt content allows to make sure we display a notification in all situations (even in bad cases where
        // The engine fails to load, e.g., because a database migration is required and the app has not been started yet since
        // The last app upgrade).
        self.contentHandler = contentHandler
        self.fullAttemptContent = UserNotificationCreator.createMinimalNotification(badge: nil).notificationContent
        self.silentAttemptContent = UNNotificationContent()  // "empty" content object to suppress the notification
        self.requestIdentifier = request.identifier

        // Initialize the engine
        if NotificationService.obvEngine == nil {
            let mainEngineContainer = ObvUICoreDataConstants.ContainerURL.mainEngineContainer.url
            ObvEngine.mainContainerURL = mainEngineContainer
            do {
                NotificationService.obvEngine = try ObvEngine.startLimitedToDecrypting(sharedContainerIdentifier: ObvMessengerConstants.appGroupIdentifier, logPrefix: "DecryptingLimitedEngine", appType: .notificationExtension, runningLog: NotificationService.runningLog)
            } catch {
                os_log("Could not start the obvEngine (happens when a migration is needed)", log: log, type: .fault)
                cleanUserDefaults()
                addNotification()
                return
            }
        }
        
        // Initialize the CoreData Stack
        
        do {
            try ObvStack.initSharedInstance(transactionAuthor: ObvUICoreDataConstants.AppType.notificationExtension.transactionAuthor, runningLog: NotificationService.runningLog, enableMigrations: false)
        } catch let error {
            os_log("Could initialize the ObvStack within the notification service extension: %{public}@", log: log, type: .fault, error.localizedDescription)
            cleanUserDefaults()
            addNotification()
            return
        }

        // Extract the information from the received notification
        
        guard let encryptedNotification = ObvEncryptedPushNotification(content: request.content) else {
            os_log("Could not extract information from the received notification", log: log, type: .error)
            cleanUserDefaults()
            addNotification()
            return
        }
        
        Task {
            
            // First try: Decrypt the notification in order to create an appropriate user notification
            
            if await tryToCreateNewMessageNotificationByDecrypting(encryptedPushNotification: encryptedNotification, request: request) {
                os_log("The encrypted push notification was successfully decrypted and the notification was set", log: log, type: .info)
                cleanUserDefaults()
                addNotification()
                return
            }
            
            // Second try: If we reach this point, it might be the case that we could not decrypt the notification because the decryption key was not available.
            // This happens in particular when the message was already fetched and decrypted by the app. In that case, the decrypted might already be in database.
            // So we try to fetch it from there.
            
            if await tryToCreateNewMessageNotificationByFetchingReceivedMessageFromDatabase(encryptedPushNotification: encryptedNotification, request: request) {
                os_log("The message was found in database. We used it to populate the notification.", log: log, type: .info)
                cleanUserDefaults()
                addNotification()
                return
            }
            
            // If we reach this point, we could not decrypt, we could not get the message from the app. We do not display a user notification.
            // It might be the case that the app is in foreground and that we are receiving a message from a non-OneToOne contact or within an unknown group discussion.
            // In those cases, we do not want to display a user notification, we set the fullAttemptContent to nil.
            
            self.fullAttemptContent = nil
            
            cleanUserDefaults()
            addNotification()
            
        }

    }

    // Update the app badge value within user defaults. The actual app badge is updated using the User Notification badge content.
    // If the notification was creating by fetching a received message from the database, we do not increment the badge count as the app already did.
    // Otherwise, we do increment the badge.
    private func getBadge(afterIncrementingIt: Bool) -> NSNumber {
        let currentBadgeValue = self.userDefaults?.integer(forKey: UserDefaultsKeyForBadge.keyForAppBadgeCount) ?? 0
        let newBadgeValue = afterIncrementingIt ? currentBadgeValue + 1 : currentBadgeValue
        self.userDefaults?.set(newBadgeValue, forKey: UserDefaultsKeyForBadge.keyForAppBadgeCount)
        return newBadgeValue as NSNumber
    }

    
    private func tryToCreateNewMessageNotificationByFetchingReceivedMessageFromDatabase(encryptedPushNotification: ObvEncryptedPushNotification, request: UNNotificationRequest) async -> Bool {

        var messageReceivedStructure: PersistedMessageReceived.Structure?
        var messageRepliedToStructure: PersistedMessage.AbstractStructure?
        ObvStack.shared.performBackgroundTaskAndWait { context in
            let messageReceived: PersistedMessageReceived
            do {
                guard let _message = try PersistedMessageReceived.getAll(messageIdentifierFromEngine: encryptedPushNotification.messageIdentifierFromEngine, within: context)
                        .sorted(by: { $0.timestamp < $1.timestamp }).last else {
                    os_log("Could not get find any PersistedMessageReceived for the given message identifier from engine", log: log, type: .error)
                    return
                }
                messageReceived = _message
            } catch {
                os_log("Could not get any PersistedMessageReceived from engine: %{public}@", log: log, type: .fault, error.localizedDescription)
                return
            }
            guard messageReceived.contactIdentity?.ownedIdentity?.isHidden == false else {
                // We never show notifications concerning hidden owned identities
                return
            }
            do {
                messageReceivedStructure = try messageReceived.toStruct()
            } catch {
                assertionFailure()
                os_log("Could create PersistedMessageReceived.Structure: %{public}@", log: log, type: .fault, error.localizedDescription)
                return
            }
            do {
                messageRepliedToStructure = try messageReceived.messageRepliedTo?.toAbstractStructure()
            } catch {
                assertionFailure()
                os_log("Could create PersistedMessage.Structure for message replied to: %{public}@", log: log, type: .fault, error.localizedDescription)
                return
            }
        }

        guard let messageReceivedStructure else {
            return false
        }
        
        // If we reach this point, we were eable to create the thread safe structure from the PersistedMessageReceived in database
        
        // Save the notification identifier (forced by iOS) and associate it with the message
        
        ObvUserNotificationIdentifier.saveIdentifierForcedInNotificationExtension(
            identifier: request.identifier,
            messageIdentifierFromEngine: messageReceivedStructure.messageIdentifierFromEngine,
            timestamp: messageReceivedStructure.timestamp)

        // We do not need to save a serialized version of the message for the app (since the app is obviously aware of the message).
        // Similarly, we do not need to create a return receipt. The app took care of that.
                    
        // Construct the notification content
        
        let discussion = messageReceivedStructure.discussionKind
        if discussion.ownedIdentity.isHidden || discussion.localConfiguration.shouldMuteNotification(with: messageReceivedStructure.mentions,
                                                                                                     messageRepliedToStructure: messageRepliedToStructure,
                                                                                                     globalDiscussionNotificationOptions: ObvMessengerSettings.Discussions.notificationOptions) {
            self.fullAttemptContent = nil
        } else {
            let badge = getBadge(afterIncrementingIt: false)
            let infos = UserNotificationCreator.NewMessageNotificationInfos(messageReceived: messageReceivedStructure, attachmentLocation: .custom(request.identifier))
            let (_, notificationContent) = UserNotificationCreator.createNewMessageNotification(infos: infos, badge: badge, addNotificationSilently: false)
            self.fullAttemptContent = notificationContent
        }

        return true
    }
    
    
    /// Returns true if the encrypted pushed notification was processed, either because a user notification was created, or because we detected that no notification should be shown.
    private func tryToCreateNewMessageNotificationByDecrypting(encryptedPushNotification: ObvEncryptedPushNotification, request: UNNotificationRequest) async -> Bool {

        let log = self.log
        
        guard let obvEngine = NotificationService.obvEngine else {
            os_log("Could not get the obvEngine", log: log, type: .error)
            return false
        }
        
        // Decrypt the information
        
        let obvMessage: ObvMessage
        do {
            obvMessage = try await obvEngine.decrypt(encryptedPushNotification: encryptedPushNotification)
        } catch {
            os_log("Could not decrypt information", log: log, type: .info)
            return false
        }

        // Create the persistent message received using the message payload

        let messagePayload = obvMessage.messagePayload
        let persistedItemJSON: PersistedItemJSON
        do {
            persistedItemJSON = try PersistedItemJSON.jsonDecode(messagePayload)
        } catch {
            os_log("Could not decode the message payload", log: log, type: .error)
            return false
        }

        guard persistedItemJSON.message != nil || persistedItemJSON.reactionJSON != nil else {
            os_log("We received a notification for an item that does not contain a valid message nor a valid reaction message, which is unexpected", log: log, type: .fault)
            return false
        }

        // Grab the persisted contact and the appropriate discussion

        var contactStructure: PersistedObvContactIdentity.Structure?
        var discussionKind: PersistedDiscussion.StructureKind?
        var messageRepliedToStructure: PersistedMessage.AbstractStructure?
        var shouldShowMinimalNotification = false
        
        ObvStack.shared.performBackgroundTaskAndWait { context in
            
            // Try to determine the contactStructure
            
            guard let persistedContactIdentity = try? PersistedObvContactIdentity.get(persisted: obvMessage.fromContactIdentity, whereOneToOneStatusIs: .any, within: context) else {
                os_log("Could not recover the persisted contact identity", log: log, type: .fault)
                return
            }

            do {
                contactStructure = try persistedContactIdentity.toStruct()
            } catch {
                assertionFailure()
                os_log("Could create PersistedObvContactIdentity.Structure: %{public}@", log: log, type: .fault, error.localizedDescription)
                return
            }

            let groupV1Identifier: GroupV1Identifier?
            let groupV2Identifier: GroupV2Identifier?
            if let messageJSON = persistedItemJSON.message {
                groupV1Identifier = messageJSON.groupV1Identifier
                groupV2Identifier = messageJSON.groupV2Identifier
            } else if let reactionJSON = persistedItemJSON.reactionJSON {
                groupV1Identifier = reactionJSON.groupV1Identifier
                groupV2Identifier = reactionJSON.groupV2Identifier
            } else {
                os_log("The received item should be a message or a reaction", log: log, type: .fault)
                assertionFailure()
                return
            }
            
            // Try to determine the discussionKind

            let discussion: PersistedDiscussion
            do {
                if let groupV1Identifier = groupV1Identifier {
                    guard let ownedIdentity = persistedContactIdentity.ownedIdentity else {
                        os_log("Could not find owned identity. This is ok if it was just deleted.", log: log, type: .error)
                        return
                    }
                    guard let contactGroup = try PersistedContactGroup.getContactGroup(groupIdentifier: groupV1Identifier, ownedIdentity: ownedIdentity) else {
                        throw Self.makeError(message: "Could not find contact group")
                    }
                    discussion = contactGroup.discussion
                } else if let groupV2Identifier = groupV2Identifier {
                    guard let ownedIdentity = persistedContactIdentity.ownedIdentity else {
                        os_log("Could not find owned identity. This is ok if it was just deleted.", log: log, type: .error)
                        return
                    }
                    guard let group = try PersistedGroupV2.get(ownIdentity: ownedIdentity.cryptoId, appGroupIdentifier: groupV2Identifier, within: context) else {
                        // We are receiving a message from a known contact, within a group we don't know. It is likely that we accepted this group invitation from another
                        // owned device (otherwise, we would be a pending member and the contact would not have sent this message). Yet, we don't display the message,
                        // and only show a minimal notification. The may incite the local user to launch the app, which will create the group and receive the message.
                        shouldShowMinimalNotification = true
                        return
                    }
                    guard let _discussion = group.discussion else {
                        throw Self.makeError(message: "Could not find discussion of group v2")
                    }
                    discussion = _discussion
                } else if let oneToOneDiscussion = persistedContactIdentity.oneToOneDiscussion {
                    discussion = oneToOneDiscussion
                } else {
                    os_log("Could not find an appropriate discussion where the received message could go.", log: log, type: .error)
                    // We are in a situation where we can decide that no user notification should be shown
                    return
                }
            } catch {
                assertionFailure()
                os_log("Core data error: %{public}@", log: log, type: .fault, error.localizedDescription)
                return
            }
                        
            // If we reach this point, we found an appropriate discussion where the message can go
            
            do {
                discussionKind = try discussion.toStructKind()
            } catch {
                assertionFailure()
                os_log("Could create PersistedDiscussion.StructureKind: %{public}@", log: log, type: .fault, error.localizedDescription)
                return
            }

            // Try to determine if the repliedToMessage
            
            do {
                if let replyTo = persistedItemJSON.message?.replyTo,
                    let messageRepliedTo = try PersistedMessage.findMessageFrom(reference: replyTo, within: discussion) {
                    messageRepliedToStructure = try messageRepliedTo.toAbstractStructure()
                    // Note that we *know* the discussion corresponding to this messageRepliedToStructure corresponds to the discussionKind above
                } else {
                    messageRepliedToStructure = nil
                }
            } catch {
                assertionFailure()
                os_log("Core data error or to struct error: %{public}@", log: log, type: .fault, error.localizedDescription)
                return
            }

        }
        
        guard !shouldShowMinimalNotification else {
            self.fullAttemptContent = UserNotificationCreator.createMinimalNotification(badge: nil).notificationContent
            return true
        }
        
        guard let contactStructure, let discussionKind else {
            assertionFailure()
            os_log("Could create PersistedDiscussion.StructureKind or PersistedObvContactIdentity.Structure although the encrypted was decrypted. We do not show any notification.", log: log, type: .error)
            self.fullAttemptContent = nil
            return true
        }
        
        // If we reach this point, we found an appropriate discussion where the message can go

        // Save the notification identifier (forced by iOS) and associate it with the message
        
        ObvUserNotificationIdentifier.saveIdentifierForcedInNotificationExtension(
            identifier: request.identifier,
            messageIdentifierFromEngine: obvMessage.messageIdentifierFromEngine,
            timestamp: obvMessage.messageUploadTimestampFromServer)
        
        // Save a serialized version of the `ObvMessage` in an appropriate location so that the app can fetch it immediately at next launch
        
        do {
            let jsonDecryptedMessage = try obvMessage.encodeToJson()
            let directory = ObvUICoreDataConstants.ContainerURL.forMessagesDecryptedWithinNotificationExtension.url
            let filename = [encryptedPushNotification.messageIdFromServerAsString, "json"].joined(separator: ".")
            let filepath = directory.appendingPathComponent(filename)
            try jsonDecryptedMessage.write(to: filepath)
            os_log("📮 Notification extension has saved a serialized version of the message.", log: log, type: .info)
        } catch let error {
            os_log("📮 Could not save a serialized version of the message: %{public}@", log: log, type: .fault, error.localizedDescription)
            // Continue anyway
        }

        // Since we saved a serialized version of the message, we can send a return receipt
        
        if let returnReceiptJSON = persistedItemJSON.returnReceipt {
            do {
                try NotificationService.obvEngine!.postReturnReceiptWithElements(
                    returnReceiptJSON.elements,
                    andStatus: ReturnReceiptJSON.Status.delivered.rawValue,
                    forContactCryptoId: obvMessage.fromContactIdentity.contactCryptoId,
                    ofOwnedIdentityCryptoId: obvMessage.fromContactIdentity.ownedCryptoId,
                    messageIdentifierFromEngine: obvMessage.messageIdentifierFromEngine,
                    attachmentNumber: nil)
            } catch {
                os_log("The Return Receipt could not be posted", log: log, type: .fault)
                // Continue anyway
            }
        }

        // Depending on whether the discussion is muted or not, or if the owned identity is hidden, we construct the notification content

        if contactStructure.ownedIdentity.isHidden || discussionKind.localConfiguration.shouldMuteNotification(with: persistedItemJSON.message,
                                                                                                               messageRepliedToStructure: messageRepliedToStructure,
                                                                                                               globalDiscussionNotificationOptions: ObvMessengerSettings.Discussions.notificationOptions) {

            // Do not show a user notification in that case
            
            self.fullAttemptContent = nil
            
        } else {

            // Construct the notification content

            if let messageJSON = persistedItemJSON.message {
                
                var isEphemeralMessageWithUserAction = false
                if let expiration = messageJSON.expiration, expiration.visibilityDuration != nil || expiration.readOnce {
                    isEphemeralMessageWithUserAction = true
                }
                
                let textBody: String?
                if isEphemeralMessageWithUserAction {
                    textBody = NSLocalizedString("EPHEMERAL_MESSAGE", comment: "")
                } else {
                    textBody = messageJSON.body
                }
                
                let attachementImages: [NotificationAttachmentImage]?
                if isEphemeralMessageWithUserAction {
                    attachementImages = nil
                } else {
                    // Extract Extended Payload
                    // In practice, this is disappointing as the server seems to often send a nil extended payload as soon as there are more than one image (i.e., one attachment) to show.
                    let op = ExtractReceivedExtendedPayloadOperation(input: .messageSentByContact(obvMessage: obvMessage))
                    op.start()
                    assert(op.isFinished)
                    attachementImages = op.attachementImages
                }

                let badge = getBadge(afterIncrementingIt: true)

                let infos = await UserNotificationCreator.NewMessageNotificationInfos(
                    body: textBody ?? UserNotificationCreator.Strings.NewPersistedMessageReceivedMinimal.body,
                    messageIdentifierFromEngine: encryptedPushNotification.messageIdentifierFromEngine,
                    contact: contactStructure,
                    discussionKind: discussionKind,
                    isEphemeralMessageWithUserAction: isEphemeralMessageWithUserAction,
                    attachmentsCount: obvMessage.expectedAttachmentsCount,
                    attachementImages: attachementImages,
                    attachmentLocation: .custom(request.identifier))
                let (_, notificationContent) = UserNotificationCreator.createNewMessageNotification(infos: infos, badge: badge, addNotificationSilently: false)
                self.fullAttemptContent = notificationContent
                
            } else if let reactionJSON = persistedItemJSON.reactionJSON {
                
                self.fullAttemptContent = nil // Do not want any minimal notification on failure for reaction.
                
                var messageSentStructure: PersistedMessageSent.Structure?
                
                ObvStack.shared.performBackgroundTaskAndWait { context in
                    guard let persistedDiscussion = try? PersistedDiscussion.getManagedObject(withPermanentID: discussionKind.discussionPermanentID, within: context) else { return }
                    guard let message = try? PersistedMessage.findMessageFrom(reference: reactionJSON.messageReference, within: persistedDiscussion) else { return }
                    guard let messageSent = message as? PersistedMessageSent, !messageSent.isWiped else { return }
                    messageSentStructure = try? messageSent.toStruct()
                }
                
                guard let messageSentStructure = messageSentStructure else { return true }
                
                if let emoji = reactionJSON.emoji {
                    let infos = UserNotificationCreator.ReactionNotificationInfos(messageSent: messageSentStructure, contact: contactStructure)
                    let (_, notificationContent) = UserNotificationCreator.createReactionNotification(
                        infos: infos,
                        emoji: emoji,
                        reactionTimestamp: obvMessage.messageUploadTimestampFromServer)
                    self.fullAttemptContent = notificationContent
                } else {
                    // Nothing can be done: we are not able to remove the notification from the extension and we cannot wake up the app.
                }
                
            }

        }
        
        return true

    }

    
    private func addNotification() {
        if addFullNotification() { return }
        if addSilentNotification() { return }
        os_log("Could not add notification at all", log: log, type: .fault)
    }

    
    private func addFullNotification() -> Bool {
        guard let contentHandler = self.contentHandler else {
            os_log("The content handler is not set", log: log, type: .fault)
            return false
        }
        guard let fullAttemptContent = self.fullAttemptContent else {
            os_log("The full attemps content is not set", log: log, type: .error)
            return false
        }
        contentHandler(fullAttemptContent)
        notifyAppOfNewFullNotification()
        return true
    }

    private func addSilentNotification() -> Bool {
        guard let contentHandler = self.contentHandler else {
            os_log("The content handler is not set", log: log, type: .fault)
            return false
        }
        guard let silentAttemptContent = self.silentAttemptContent else {
            os_log("The silent attemps content is not set", log: log, type: .fault)
            return false
        }
        contentHandler(silentAttemptContent)
        return true
    }
    
    private func notifyAppOfNotification(with key: String) {
        guard let userDefaults = self.userDefaults else {
            os_log("Could not access user defaults", log: log, type: .fault)
            return
        }
        guard let requestIdentifier = self.requestIdentifier else {
            os_log("The request identifier is not set", log: log, type: .fault)
            return
        }
        internalQueue.sync {
            var notificationRequestIdentifiersWithDates = userDefaults.notificationRequestIdentifiersWithDates(forKey: key) ?? []
            let newIdentifierWithDate = UNNotificationRequestIdentifierWithDate(requestIdentifier: requestIdentifier, date: Date())
            notificationRequestIdentifiersWithDates.append(newIdentifierWithDate)
            userDefaults.set(notificationRequestIdentifiersWithDates, forKey: key)
        }
    }

    private func notifyAppOfNewFullNotification() {
        notifyAppOfNotification(with: ObvMessengerConstants.requestIdentifiersOfFullNotificationsAddedByExtension)
    }

    private func cleanNotifications(for key: String) {
        guard let userDefaults = self.userDefaults else {
            os_log("Could not access user defaults", log: log, type: .fault)
            return
        }
        internalQueue.sync {
            let notificationRequestIdentifiersWithDates = userDefaults.notificationRequestIdentifiersWithDates(forKey: key) ?? []
            let yesterday = Date().addingTimeInterval(TimeInterval.init(60*60*24)) // One day
            let notificationRequestIdentifiersWithDatesToKeep = notificationRequestIdentifiersWithDates.filter { $0.date > yesterday }
            os_log("We cleaned %d old entries in the user defaults db for notifications", log: log, type: .info, notificationRequestIdentifiersWithDates.count - notificationRequestIdentifiersWithDatesToKeep.count)
            userDefaults.set(notificationRequestIdentifiersWithDatesToKeep, forKey: key)
        }
    }

    private func cleanUserDefaults() {
        cleanNotifications(for: ObvMessengerConstants.requestIdentifiersOfFullNotificationsAddedByExtension)
    }

    
    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        addNotification()
    }
    
}


fileprivate extension ObvEncryptedPushNotification {
    
    init?(content: UNNotificationContent) {
        
        let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "ObvEncryptedPushNotification")

        let wrappedKeyString = content.userInfo["encryptedHeader"] as? String ?? content.title
        let encryptedContentString = content.userInfo["encryptedMessage"] as? String ?? content.body
        
        guard let wrappedKey = Data(base64Encoded: wrappedKeyString) else {
            os_log("Could not decode de base64encoded wrapped key string found in the encrypted header of the user info", log: log, type: .error)
            return nil
        }
        
        guard let encryptedContent = Data(base64Encoded: encryptedContentString) else {
            os_log("Could not decode de base64encoded encrypted content found in the encrypted message field of the user info", log: log, type: .error)
            return nil
        }
        
        guard let maskingUID = content.userInfo["maskinguid"] as? String else {
            os_log("Could not find the masking uid (as a String) in the user info dictionary", log: log, type: .error)
            return nil
        }
        
        guard let messageUploadTimestampFromServerAsDouble = content.userInfo["timestamp"] as? Double else {
            os_log("Could not find the message upload timestamp from server (as a Double) in the user info dictionary", log: log, type: .error)
            return nil
        }

        guard let messageIdFromServer = content.userInfo["messageuid"] as? String else {
            os_log("Could not find the messageId from server (as a String) in the user info dictionary", log: log, type: .error)
            return nil
        }

        var encryptedExtendedContent: Data?
        if let encryptedExtendedContentString = content.userInfo["extendedContent"] as? String {
            encryptedExtendedContent = Data(base64Encoded: encryptedExtendedContentString)
        }

        let messageUploadTimestampFromServer = Date(timeIntervalSince1970: messageUploadTimestampFromServerAsDouble / 1000.0)

        self.init(messageIdFromServer: messageIdFromServer,
                  wrappedKey: wrappedKey,
                  encryptedContent: encryptedContent,
                  encryptedExtendedContent: encryptedExtendedContent,
                  maskingUID: maskingUID,
                  messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                  localDownloadTimestamp: Date())
        
    }
    
}
