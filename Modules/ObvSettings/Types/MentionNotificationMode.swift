/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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

/// Possible notification modes for a discussion that is muted when receiving a message that mentions us.
///
/// - `globalDefault`: Nothing specified, uses the default setting
/// - `alwaysNotifyWhenMentionned`: Always be notified when mentioned
/// - `neverNotifyWhenDiscussionIsMuted`: Never be notified when mentioned
public enum DiscussionMentionNotificationMode: CaseIterable, Hashable {
    /// Nothing specified, uses the default setting
    case globalDefault
    /// Never be notified when mentioned
    case neverNotifyWhenDiscussionIsMuted
    /// Always be notified when mentioned (even if the discussion is muted)
    case alwaysNotifyWhenMentionned
}

extension DiscussionMentionNotificationMode {

    /// The human-visible display title for a given notification mode
    public func displayTitle(globalOptions: ObvMessengerSettings.Discussions.NotificationOptions) -> String {
        switch self {
        case .globalDefault:
            let value: String

            if globalOptions.contains(.alwaysNotifyWhenMentionnedEvenInMutedDiscussion) {
                value = DiscussionMentionNotificationMode.alwaysNotifyWhenMentionned.displayTitle(globalOptions: globalOptions)
            } else {
                value = DiscussionMentionNotificationMode.neverNotifyWhenDiscussionIsMuted.displayTitle(globalOptions: globalOptions)
            }

            return String.localizedStringWithFormat(NSLocalizedString("discussion-mention-notification-mode.display-title.default",
                                                                      comment: "Display title for the `default` value for mention notification mode. Takes one argument, the global discussion notification mode"),
                                                    value as NSString)

        case .alwaysNotifyWhenMentionned:
            return NSLocalizedString("discussion-mention-notification-mode.display-title.always", comment: "Display title for the `always` value for mention notification mode")

        case .neverNotifyWhenDiscussionIsMuted:
            return NSLocalizedString("discussion-mention-notification-mode.display-title.never", comment: "Display title for the `never` value for mention notification mode")
        }
    }
}

extension DiscussionMentionNotificationMode: Codable {
    /// Inner storage, that actuall conforms to `Int`
    private enum _Storage: Int, Codable {
        case globalDefault = -1
        case neverNotifyWhenDiscussionIsMuted = 0
        case alwaysNotifyWhenMentionned = 1
    }

    private init(_ storage: _Storage) {
        switch storage {
        case .globalDefault:
            self = .globalDefault

        case .neverNotifyWhenDiscussionIsMuted:
            self = .neverNotifyWhenDiscussionIsMuted

        case .alwaysNotifyWhenMentionned:
            self = .alwaysNotifyWhenMentionned
        }
    }

    private var _storageValue: _Storage {
        switch self {
        case .globalDefault:
            return .globalDefault

        case .neverNotifyWhenDiscussionIsMuted:
            return .neverNotifyWhenDiscussionIsMuted

        case .alwaysNotifyWhenMentionned:
            return .alwaysNotifyWhenMentionned
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .globalDefault
        } else {
            self = .init(try container.decode(_Storage.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        guard self != .globalDefault else { // `nil` is implicit for the default value
            var container = encoder.singleValueContainer()

            try container.encodeNil()

            return
        }

        try _storageValue.encode(to: encoder)
    }
}

extension DiscussionMentionNotificationMode: Identifiable {
    public var id: Self {
        return self
    }
}
