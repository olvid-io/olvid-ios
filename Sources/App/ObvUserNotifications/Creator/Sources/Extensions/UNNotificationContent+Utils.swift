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

import Foundation
import UserNotifications
import ObvTypes
import ObvEncoder
import ObvAppTypes


fileprivate struct UserInfoKey {
    static let obvDialog = "obvDialog"
    static let obvProtocolMessage = "ObvProtocolMessage"
    static let obvMessageAppIdentifier = "ObvMessageAppIdentifier"
    static let obvDiscussionIdentifier = "ObvDiscussionIdentifier"
    static let obvContactIdentifier = "ObvContactIdentifier"
    static let isEphemeralMessageWithUserAction = "isEphemeralMessageWithUserAction"
    static let expectedAttachmentsCount = "expectedAttachmentsCount"
    static let showsEditIndication = "showsEditIndication"
    static let sentMessageReactedTo = "sentMessageReactedTo"
    static let reactor = "reactor"
    static let uploadTimestampFromServer = "uploadTimestampFromServer"
}


extension UNNotificationContent {
    
    public var obvDialog: ObvDialog? {
        get {
            guard let rawObvDialog = self.userInfo[UserInfoKey.obvDialog] as? Data else { assertionFailure(); return nil }
            guard let encodedObvDialog = ObvEncoded(withRawData: rawObvDialog) else { assertionFailure(); return nil }
            guard let obvDialog = ObvDialog(encodedObvDialog) else { assertionFailure(); return nil }
            return obvDialog
        }
    }
    
    public var obvProtocolMessage: ObvProtocolMessage? {
        get {
            guard let raw = self.userInfo[UserInfoKey.obvProtocolMessage] as? Data else { return nil }
            guard let encoded = ObvEncoded(withRawData: raw) else { assertionFailure(); return nil }
            guard let obvProtocolMessage = ObvProtocolMessage(encoded) else { assertionFailure(); return nil }
            return obvProtocolMessage
        }
    }
    
    public var messageAppIdentifier: ObvMessageAppIdentifier? {
        guard let description = self.userInfo[UserInfoKey.obvMessageAppIdentifier] as? String else { return nil }
        guard let messageAppIdentifier = ObvMessageAppIdentifier(description) else { assertionFailure(); return nil }
        return messageAppIdentifier
    }
    
    var isEphemeralMessageWithUserAction: Bool? {
        guard let isEphemeralMessageWithUserAction = self.userInfo[UserInfoKey.isEphemeralMessageWithUserAction] as? Bool else { return nil }
        return isEphemeralMessageWithUserAction
    }

    var expectedAttachmentsCount: Int? {
        guard let expectedAttachmentsCount = self.userInfo[UserInfoKey.expectedAttachmentsCount] as? Int else { return nil }
        return expectedAttachmentsCount
    }
    
    var showsEditIndication: Bool? {
        guard let showsEditIndication = self.userInfo[UserInfoKey.showsEditIndication] as? Bool else { return nil }
        return showsEditIndication
    }
    
    public var discussionIdentifier: ObvDiscussionIdentifier? {
        guard let description = self.userInfo[UserInfoKey.obvDiscussionIdentifier] as? String else { return nil }
        guard let discussionIdentifier = ObvDiscussionIdentifier(description) else { assertionFailure(); return nil }
        return discussionIdentifier
    }
    
    public var contactIdentifier: ObvContactIdentifier? {
        guard let description = self.userInfo[UserInfoKey.obvContactIdentifier] as? String else { return nil }
        guard let contactIdentifier = ObvContactIdentifier(description) else { assertionFailure(); return nil }
        return contactIdentifier
    }

    public var sentMessageReactedTo: ObvMessageAppIdentifier? {
        guard let description = self.userInfo[UserInfoKey.sentMessageReactedTo] as? String else { return nil }
        guard let sentMessageReactedTo = ObvMessageAppIdentifier(description) else { assertionFailure(); return nil }
        return sentMessageReactedTo
    }

    public var reactor: ObvContactIdentifier? {
        guard let description = self.userInfo[UserInfoKey.reactor] as? String else { return nil }
        guard let reactor = ObvContactIdentifier(description) else { assertionFailure(); return nil }
        return reactor
    }
    
    public var uploadTimestampFromServer: Date? {
        guard let uploadTimestampFromServer = self.userInfo[UserInfoKey.uploadTimestampFromServer] as? Date else { return nil }
        return uploadTimestampFromServer
    }

}


extension UNMutableNotificationContent {
    
    func setObvDialog(to obvDialog: ObvDialog) throws {
        self.userInfo[UserInfoKey.obvDialog] = try obvDialog.obvEncode().rawData
    }
    
    func setObvProtocolMessage(to obvProtocolMessage: ObvProtocolMessage) throws {
        self.userInfo[UserInfoKey.obvProtocolMessage] = try obvProtocolMessage.obvEncode().rawData
    }
    
    func setObvMessageAppIdentifier(to messageAppIdentifier: ObvMessageAppIdentifier) {
        self.userInfo[UserInfoKey.obvMessageAppIdentifier] = messageAppIdentifier.description
    }
    
    func setIsEphemeralMessageWithUserAction(to isEphemeralMessageWithUserAction: Bool) {
        self.userInfo[UserInfoKey.isEphemeralMessageWithUserAction] = isEphemeralMessageWithUserAction
    }

    func setExpectedAttachmentsCount(to expectedAttachmentsCount: Int) {
        self.userInfo[UserInfoKey.expectedAttachmentsCount] = expectedAttachmentsCount
    }

    func setShowsEditIndication(to showsEditIndication: Bool) {
        self.userInfo[UserInfoKey.showsEditIndication] = showsEditIndication
    }
    
    func setObvDiscussionIdentifier(to discussionIdentifier: ObvDiscussionIdentifier) {
        self.userInfo[UserInfoKey.obvDiscussionIdentifier] = discussionIdentifier.description
    }

    func setObvContactIdentifier(to contactIdentifier: ObvContactIdentifier) {
        self.userInfo[UserInfoKey.obvContactIdentifier] = contactIdentifier.description
    }
    
    func setSentMessageReactedTo(to sentMessageReactedTo: ObvMessageAppIdentifier) {
        self.userInfo[UserInfoKey.sentMessageReactedTo] = sentMessageReactedTo.description
    }

    func setReactor(to reactor: ObvContactIdentifier) {
        self.userInfo[UserInfoKey.reactor] = reactor.description
    }
    
    func setUploadTimestampFromServer(to uploadTimestampFromServer: Date) {
        self.userInfo[UserInfoKey.uploadTimestampFromServer] = uploadTimestampFromServer
    }

}
