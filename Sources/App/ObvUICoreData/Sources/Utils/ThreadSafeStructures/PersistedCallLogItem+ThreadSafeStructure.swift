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
import ObvUICoreDataStructs


extension PersistedCallLogItem {
    
    public func toStructure() throws -> PersistedCallLogItemStructure {
        guard let context = self.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        let direction: PersistedCallLogItemStructure.Direction = self.isIncoming ? .incoming : .outgoing
        guard let ownedCryptoId else { assertionFailure(); throw ObvUICoreDataError.ownedIdentityIsNil }
        guard let discussionId = obvDiscussionIdentifier?.toDiscussionIdentifier() else { assertionFailure(); throw ObvUICoreDataError.discussionIsNil }
        guard let persistedDiscussion = try PersistedDiscussion.getPersistedDiscussion(ownedCryptoId: ownedCryptoId, discussionId: discussionId, within: context) else {
            assertionFailure()
            throw ObvUICoreDataError.discussionIsNil
        }
        let otherParticipants = try self.logContacts.map({ try $0.toStructure() })
        guard let callReportKind = self.callReportKind?.toPersistedCallLogItemStructureCallReportKind() else {
            assertionFailure()
            throw ObvUICoreDataError.unhandledCallReportKind
        }
        return .init(callUUID: self.callUUID,
                     direction: direction,
                     discussionKind: try persistedDiscussion.toStructureKind(),
                     otherParticipants: otherParticipants,
                     callReportKind: callReportKind,
                     initialOtherParticipantsCount: self.initialParticipantCount ?? 1)
    }
    
}


extension CallReportKind {
    
    func toPersistedCallLogItemStructureCallReportKind() -> PersistedCallLogItemStructure.CallReportKind? {
        for kind in PersistedCallLogItemStructure.CallReportKind.allCases {
            switch kind {
            case .rejectedOutgoingCall:
                if self == .rejectedOutgoingCall { return kind }
            case .acceptedOutgoingCall:
                if self == .acceptedOutgoingCall { return kind }
            case .uncompletedOutgoingCall:
                if self == .uncompletedOutgoingCall { return kind }
            case .acceptedIncomingCall:
                if self == .acceptedIncomingCall { return kind }
            case .missedIncomingCall:
                if self == .missedIncomingCall { return kind }
            case .rejectedIncomingCall:
                if self == .rejectedIncomingCall { return kind }
            case .filteredIncomingCall:
                if self == .filteredIncomingCall { return kind }
            case .rejectedIncomingCallBecauseOfDeniedRecordPermission:
                if self == .rejectedIncomingCallBecauseOfDeniedRecordPermission { return kind }
            }
        }
        // Unhandled case
        return nil
    }
    
}
