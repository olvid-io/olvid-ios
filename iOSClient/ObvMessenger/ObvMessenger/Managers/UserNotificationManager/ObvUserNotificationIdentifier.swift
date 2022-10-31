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
import UserNotifications
import ObvEngine
import os.log

// Defining an enum of all the possible user notifications

enum ObvUserNotificationID: Int {
    case newMessageNotificationWithHiddenContent = 0
    case newMessage
    case newReactionNotificationWithHiddenContent
    case newReaction
    case acceptInvite
    case sasExchange
    case mutualTrustConfirmed
    case acceptMediatorInvite
    case acceptGroupInvite
    case autoconfirmedContactIntroduction
    case increaseMediatorTrustLevelRequired
    case oneToOneInvitationReceived
    case missedCall
    case shouldGrantRecordPermissionToReceiveIncomingCalls

    case staticIdentifier = 1000
}

enum ObvUserNotificationIdentifier {

    var log: OSLog { OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "ObvUserNotificationIdentifier") }
    
    private static var df: DateFormatter {
        let RFC3339DateFormatter = DateFormatter()
        RFC3339DateFormatter.locale = Locale(identifier: "en_US_POSIX")
        RFC3339DateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        RFC3339DateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        return RFC3339DateFormatter
    }
    
    // Receiving a discussion message
    case newMessageNotificationWithHiddenContent
    case newMessage(messageIdentifierFromEngine: Data)
    // Receiving a reaction message
    case newReactionNotificationWithHiddenContent
    case newReaction(messageURI: URL, contactURI: URL)
    // Receiving an invitation message
    case acceptInvite(persistedInvitationUUID: UUID)
    case sasExchange(persistedInvitationUUID: UUID)
    case mutualTrustConfirmed(persistedInvitationUUID: UUID)
    case acceptMediatorInvite(persistedInvitationUUID: UUID)
    case acceptGroupInvite(persistedInvitationUUID: UUID)
    case autoconfirmedContactIntroduction(persistedInvitationUUID: UUID)
    case increaseMediatorTrustLevelRequired(persistedInvitationUUID: UUID)
    case oneToOneInvitationReceived(persistedInvitationUUID: UUID)
    case missedCall(callUUID: UUID)
    // When a called was missed because of record permission is either denied or undetermined
    case shouldGrantRecordPermissionToReceiveIncomingCalls
    // Static identifier, when notifications should not disclose any content
    case staticIdentifier

    func getIdentifier() -> String {
        switch self {
        case .newMessageNotificationWithHiddenContent:
            return "newMessageNotificationWithHiddenContent"
        case .newMessage(messageIdentifierFromEngine: let messageIdentifierFromEngine):
            let stringIdentifier = ObvUserNotificationIdentifier.loadIdentifierForcedInNotificationExtension(messageIdentifierFromEngine: messageIdentifierFromEngine) ?? "newMessage_\(messageIdentifierFromEngine.hexString()))"
            os_log("Returning this newMessage notification identifier: %{public}@", log: log, type: .info, stringIdentifier)
            return stringIdentifier
        case .acceptInvite(persistedInvitationUUID: let uuid):
            return "acceptInvite_\(uuid.uuidString)"
        case .sasExchange(persistedInvitationUUID: let uuid):
            return "sasExchange_\(uuid.uuidString)"
        case .mutualTrustConfirmed(persistedInvitationUUID: let uuid):
            return "mutualTrustConfirmed_\(uuid.uuidString)"
        case .acceptMediatorInvite(persistedInvitationUUID: let uuid):
            return "acceptMediatorInvite_\(uuid.uuidString)"
        case .acceptGroupInvite(persistedInvitationUUID: let uuid):
            return "acceptGroupInvite_\(uuid.uuidString)"
        case .autoconfirmedContactIntroduction(persistedInvitationUUID: let uuid):
            return "autoconfirmedContactIntroduction_\(uuid.uuidString)"
        case .increaseMediatorTrustLevelRequired(persistedInvitationUUID: let uuid):
            return "increaseMediatorTrustLevelRequired_\(uuid.uuidString)"
        case .missedCall(callUUID: let uuid):
            return "missedCall_\(uuid.uuidString)"
        case .newReaction(messageURI: let messageURI, contactURI: let contactURI):
            return "reaction_\(messageURI.absoluteString)_\(contactURI.absoluteString)"
        case .newReactionNotificationWithHiddenContent:
            return "newMessageNotificationWithHiddenContent"
        case .oneToOneInvitationReceived(persistedInvitationUUID: let uuid):
            return "oneToOneInvitationReceived_\(uuid.uuidString)"
        case .shouldGrantRecordPermissionToReceiveIncomingCalls:
            return "shouldGrantRecordPermissionToReceiveIncomingCalls"
        case .staticIdentifier:
            return "staticIdentifier"
        }
    }

    var id: ObvUserNotificationID {
        switch self {
        case .newMessageNotificationWithHiddenContent: return .newMessageNotificationWithHiddenContent
        case .newMessage: return .newMessage
        case .newReactionNotificationWithHiddenContent: return .newReactionNotificationWithHiddenContent
        case .newReaction: return .newReaction
        case .acceptInvite: return .acceptInvite
        case .sasExchange: return .sasExchange
        case .mutualTrustConfirmed: return .mutualTrustConfirmed
        case .acceptMediatorInvite: return .acceptMediatorInvite
        case .acceptGroupInvite: return .acceptGroupInvite
        case .autoconfirmedContactIntroduction: return .autoconfirmedContactIntroduction
        case .increaseMediatorTrustLevelRequired: return .increaseMediatorTrustLevelRequired
        case .missedCall: return .missedCall
        case .oneToOneInvitationReceived: return .oneToOneInvitationReceived
        case .shouldGrantRecordPermissionToReceiveIncomingCalls: return .shouldGrantRecordPermissionToReceiveIncomingCalls
        case .staticIdentifier: return .staticIdentifier
        }
    }

    func getThreadIdentifier() -> String {
        switch self {
        case .newMessage, .newMessageNotificationWithHiddenContent:
            return "MessageThread"
        case .acceptInvite, .sasExchange, .mutualTrustConfirmed, .acceptMediatorInvite, .acceptGroupInvite, .autoconfirmedContactIntroduction, .increaseMediatorTrustLevelRequired, .oneToOneInvitationReceived:
            return "InvitationThread"
        case .missedCall, .shouldGrantRecordPermissionToReceiveIncomingCalls:
            return "CallThread"
        case .newReaction, .newReactionNotificationWithHiddenContent:
            return "ReactionThread"
        case .staticIdentifier:
            return "StaticThread"
        }
    }
    

    /// All the cases that return a non-nil category must be registered in this class initializer
    func getCategory() -> UserNotificationCategory? {
        switch self {
        case .acceptInvite, .acceptMediatorInvite, .acceptGroupInvite, .oneToOneInvitationReceived:
            return .acceptInviteCategory
        case .newMessage:
            return .newMessageCategory
        case .newMessageNotificationWithHiddenContent:
            return .newMessageWithLimitedVisibilityCategory
        case .missedCall, .shouldGrantRecordPermissionToReceiveIncomingCalls:
            return .missedCallCategory
        case .newReaction, .newReactionNotificationWithHiddenContent:
            return .newReactionCategory
        case .sasExchange, .mutualTrustConfirmed, .autoconfirmedContactIntroduction, .increaseMediatorTrustLevelRequired, .staticIdentifier:
            return nil
        }
    }
    
    
    /// When a user notification is dealt with by the notification extension, the notification identifier is "forced" by iOS. We cannot set it using the "usual" internal method.
    /// Lateron, this makes it difficult to find the notification related to a specific message.
    /// To solve this issue, each time a notification is received by the notification extension, we save the mapping between the "forced" notification identifier and the identifier we
    /// are eable to compute given the message. We save all the mappings in a "user defaults" database.
    static func saveIdentifierForcedInNotificationExtension(identifier: String, messageIdentifierFromEngine: Data, timestamp: Date) {
        guard let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier) else { assertionFailure(); return }
        let currentEncoded = userDefaults.array(forKey: "notificationIdentifiersForcedInNotificationExtension") as? [Data] ?? []
        var current = currentEncoded.compactMap({ try? IdentifierForcedInNotificationExtension.jsonDecode($0) })
        assert(!current.contains(where: { $0.messageIdentifierFromEngine == messageIdentifierFromEngine }))
        current.removeAll(where: { $0.messageIdentifierFromEngine == messageIdentifierFromEngine })
        current.removeAll(where: { abs($0.timestamp.timeIntervalSinceNow) > 604_800 }) // One week
        current.append(IdentifierForcedInNotificationExtension(identifierForcedByNotificationExtension: identifier, messageIdentifierFromEngine: messageIdentifierFromEngine, timestamp: timestamp))
        userDefaults.set(current.compactMap({ try? $0.jsonEncode() }), forKey: "notificationIdentifiersForcedInNotificationExtension")
    }
    
    
    static func loadIdentifierForcedInNotificationExtension(messageIdentifierFromEngine: Data) -> String? {
        guard let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier) else { assertionFailure(); return nil }
        let currentEncoded = userDefaults.array(forKey: "notificationIdentifiersForcedInNotificationExtension") as? [Data] ?? []
        let current = currentEncoded.compactMap({ try? IdentifierForcedInNotificationExtension.jsonDecode($0) })
        return current.first(where: { $0.messageIdentifierFromEngine == messageIdentifierFromEngine })?.identifierForcedByNotificationExtension
    }
    
    static func identifierIsStaticIdentifier(identifier: String) -> Bool {
        identifier == ObvUserNotificationIdentifier.staticIdentifier.getIdentifier()
    }

}


fileprivate struct IdentifierForcedInNotificationExtension: Codable {
    
    let identifierForcedByNotificationExtension: String
    let messageIdentifierFromEngine: Data
    let timestamp: Date
    
    func jsonEncode() throws -> Data {
        try JSONEncoder().encode(self)
    }
    
    static func jsonDecode(_ data: Data) throws -> IdentifierForcedInNotificationExtension {
        let decoder = JSONDecoder()
        return try decoder.decode(IdentifierForcedInNotificationExtension.self, from: data)
    }

}
