/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import CoreData
import ObvEngine

enum CallReportKind: Int, CustomDebugStringConvertible, CaseIterable {
    case missedIncomingCall = 0
    case rejectedIncomingCall = 1
    case acceptedIncomingCall = 2
    case acceptedOutgoingCall = 3
    case rejectedOutgoingCall = 4
    case busyOutgoingCall = 5
    case unansweredOutgoingCall = 6
    case uncompletedOutgoingCall = 7
    case newParticipantInIncomingCall = 8
    case newParticipantInOutgoingCall = 9
    case rejectedIncomingCallBecauseOfDeniedRecordPermission = 10
    case anyIncomingCall = 11 /// incoming call without informations
    case anyOutgoingCall = 12 /// outgoing call without informations
    case filteredIncomingCall = 13

    var debugDescription: String {
        switch self {
        case .missedIncomingCall: return "missedIncomingCall"
        case .rejectedIncomingCall: return "rejectedIncomingCall"
        case .acceptedIncomingCall: return "acceptedIncomingCall"
        case .acceptedOutgoingCall: return "acceptedOutgoingCall"
        case .rejectedOutgoingCall: return "rejectedOutgoingCall"
        case .busyOutgoingCall: return "busyOutgoingCall"
        case .unansweredOutgoingCall: return "unansweredOutgoingCall"
        case .uncompletedOutgoingCall: return "uncompletedOutgoingCall"
        case .newParticipantInIncomingCall: return "newParticipantInIncomingCall"
        case .newParticipantInOutgoingCall: return "newParticipantInOutgoingCall"
        case .rejectedIncomingCallBecauseOfDeniedRecordPermission: return "rejectedIncomingCallBecauseOfDeniedRecordPermission"
        case .anyIncomingCall: return "anyIncomingCall"
        case .anyOutgoingCall: return "anyOutgoingCall"
        case .filteredIncomingCall: return "filteredIncomingCall"
        }
    }

    var isRelevantForCountingUnread: Bool {
        switch self {
        case .missedIncomingCall: return true
        case .rejectedIncomingCall: return false
        case .acceptedIncomingCall: return false
        case .acceptedOutgoingCall: return false
        case .rejectedOutgoingCall: return false
        case .busyOutgoingCall: return false
        case .unansweredOutgoingCall: return false
        case .uncompletedOutgoingCall: return false
        case .newParticipantInIncomingCall: return false
        case .newParticipantInOutgoingCall: return false
        case .rejectedIncomingCallBecauseOfDeniedRecordPermission: return true
        case .anyIncomingCall: return false
        case .anyOutgoingCall: return false
        case .filteredIncomingCall: return true
        }
    }
}


@objc(PersistedCallLogContact)
final class PersistedCallLogContact: NSManagedObject {

    // MARK: Internal constants

    private static let entityName = "PersistedCallLogContact"
    static let rawReportKindKey = "rawReportKind"

    // MARK: - Attributes

    @NSManaged private(set) var isCaller: Bool
    @NSManaged private var rawReportKind: Int

    // MARK: - Relationships

    @NSManaged private(set) var callLogItem: PersistedCallLogItem?
    @NSManaged private(set) var contactIdentity: PersistedObvContactIdentity?

    // MARK: - Variables

    var callReportKind: CallReportKind {
        get {
            CallReportKind(rawValue: rawReportKind)!
        }
        set {
            self.rawReportKind = newValue.rawValue
        }
    }

    // MARK: - Inits

    convenience init(callLogItem: PersistedCallLogItem, callReportKind: CallReportKind, contactIdentity: PersistedObvContactIdentity, isCaller: Bool, within context: NSManagedObjectContext) {

        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedCallLogContact.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.isCaller = isCaller
        self.rawReportKind = callReportKind.rawValue
        self.callLogItem = callLogItem
        self.contactIdentity = contactIdentity

        callLogItem.updateCallReportKind()
    }

}

// MARK: - Convenience DB getters

extension PersistedCallLogContact {

    private struct Predicate {
        private enum Key: String {
            case contactIdentity = "contactIdentity"
        }
        static func nilContact() -> NSPredicate {
            NSPredicate(withNilValueForKey: Key.contactIdentity)
        }
    }


    @nonobjc class func fetchRequest() -> NSFetchRequest<PersistedCallLogContact> {
        return NSFetchRequest<PersistedCallLogContact>(entityName: self.entityName)
    }

    static func getCallLogsWithoutContacts(within context: NSManagedObjectContext) throws -> [PersistedCallLogContact] {
        let request: NSFetchRequest<PersistedCallLogContact> = PersistedCallLogContact.fetchRequest()
        request.predicate = Predicate.nilContact()
        return try context.fetch(request)
    }

}
