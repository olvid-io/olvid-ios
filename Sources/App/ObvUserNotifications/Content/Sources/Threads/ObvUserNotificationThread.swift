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
import UserNotifications
import ObvAppTypes


/// This enum is used to define specific user notification threads. Typically, we want to group all received message notifications depending by discussion.
/// Certain notifications, such as "missed call" notifications are too important, and don't happen very often, so we don't define a thread for them.
///
/// The ``threadIdentifier`` string produced here is set as `UNNotificationContent.threadIdentifier` (iOS's
/// notification-grouping key). iOS also surfaces that same string back to us as the `conversationIdentifiers`
/// of an `INSearchForMessagesIntent`, so this type lives in the lightweight `ObvUserNotificationsContent`
/// module — shared by the notification *creator* (which writes it) and the Intents extension (which parses
/// it via ``init(threadIdentifier:)``), keeping the format a single source of truth.
public enum ObvUserNotificationThread {

    case minimal
    case discussion(ObvDiscussionIdentifier)

    /// Namespace shared by every thread identifier. The last dot-separated segment is the discriminator:
    /// the literal `minimal`, or a discussion's `ObvDiscussionIdentifier.description` (hex, never contains
    /// a `.`), which keeps the prefix/suffix split unambiguous.
    private static let namespace = ["ObvUserNotificationThread", "threadIdentifier"].joined(separator: ".")
    private static let minimalThreadIdentifier = [namespace, "minimal"].joined(separator: ".")
    private static let discussionThreadIdentifierPrefix = namespace + "."

    public var threadIdentifier: String {
        switch self {
        case .minimal:
            return Self.minimalThreadIdentifier
        case .discussion(let discussionIdentifier):
            return Self.discussionThreadIdentifierPrefix + discussionIdentifier.description
        }
    }

    /// Inverse of ``threadIdentifier``: reconstructs the thread from a string previously produced by this
    /// type (e.g. a `UNNotificationContent.threadIdentifier`, or the `conversationIdentifiers` value iOS
    /// hands back on an `INSearchForMessagesIntent`). Returns `nil` for strings outside our namespace, or
    /// whose discussion suffix doesn't decode.
    public init?(threadIdentifier: String) {
        if threadIdentifier == Self.minimalThreadIdentifier {
            self = .minimal
        } else if threadIdentifier.hasPrefix(Self.discussionThreadIdentifierPrefix),
                  let discussionIdentifier = ObvDiscussionIdentifier(String(threadIdentifier.dropFirst(Self.discussionThreadIdentifierPrefix.count))) {
            self = .discussion(discussionIdentifier)
        } else {
            return nil
        }
    }

    /// The discussion this thread groups, or `nil` for ``minimal``.
    public var discussionIdentifier: ObvDiscussionIdentifier? {
        switch self {
        case .minimal: return nil
        case .discussion(let discussionIdentifier): return discussionIdentifier
        }
    }

}
