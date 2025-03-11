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


public struct PersistedCallLogItemStructure {
    
    public let callUUID: UUID
    public let direction: Direction
    public let discussionKind: PersistedDiscussionAbstractStructure.StructureKind
    public let otherParticipants: [PersistedCallLogContactStructure]
    public let callReportKind: CallReportKind
    public let initialOtherParticipantsCount: Int

    public enum Direction {
        case incoming
        case outgoing
    }
    
    
    /// Although `PersistedCallLogItem` has many other `CallReportKinds`, we restrict to certain kinds as we do not report the other ones for now.
    public enum CallReportKind: CaseIterable {
        // Outgoing
        case rejectedOutgoingCall
        case acceptedOutgoingCall
        case uncompletedOutgoingCall
        // Incoming
        case acceptedIncomingCall
        case missedIncomingCall
        case rejectedIncomingCall
        case filteredIncomingCall
        case rejectedIncomingCallBecauseOfDeniedRecordPermission
    }
    
    
    public init(callUUID: UUID, direction: Direction, discussionKind: PersistedDiscussionAbstractStructure.StructureKind, otherParticipants: [PersistedCallLogContactStructure], callReportKind: CallReportKind, initialOtherParticipantsCount: Int) {
        self.callUUID = callUUID
        self.direction = direction
        self.discussionKind = discussionKind
        self.otherParticipants = otherParticipants
        self.callReportKind = callReportKind
        self.initialOtherParticipantsCount = initialOtherParticipantsCount
    }
    
    
    /// When a PersistedCallLogItem is inserted, a notification is sent from the DB. It is catched both by:
    /// - the notification coordinator, that will generate a local user notification (enriched with a suggested `INStartCallIntent`) if the kind is `userNotificationAndStartCallIntent`
    /// - the intent manager, that will only suggest a `INStartCallIntent` if the kind is `startCallItentOnly`
    public enum NotificationKind {
        case none
        case userNotificationAndStartCallIntent
        case startCallItentOnly
    }
    
    public var notificationKind: NotificationKind {
        switch callReportKind {
        case .rejectedOutgoingCall, .acceptedOutgoingCall, .uncompletedOutgoingCall, .acceptedIncomingCall, .rejectedIncomingCall:
            return .startCallItentOnly
        case .missedIncomingCall, .filteredIncomingCall, .rejectedIncomingCallBecauseOfDeniedRecordPermission:
            return .userNotificationAndStartCallIntent
        }
    }
    
}
