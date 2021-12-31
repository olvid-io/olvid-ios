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
import os.log
import ObvEngine
import ObvTypes

@objc(PersistedCallLogItem)
final class PersistedCallLogItem: NSManagedObject {

    // MARK: Internal constants

    private static let entityName = "PersistedCallLogItem"
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: PersistedCallLogItem.self))

    // MARK: - Attributes

    @NSManaged private var callUUID: UUID
    @NSManaged var endDate: Date?
    @NSManaged private var groupOwnerIdentity: Data?
    @NSManaged private var groupUidRaw: Data?
    @NSManaged private var rawInitialParticipantCount: NSNumber? // Should only be accessed through initialParticipantCount
    @NSManaged private(set) var isIncoming: Bool
    @NSManaged private var rawOwnedCryptoId: Data
    @NSManaged private var rawReportKind: NSNumber?
    @NSManaged var startDate: Date?
    @NSManaged private(set) var unknownContactsCount: Int

    var initialParticipantCount: Int? {
        get {
            guard let raw = self.rawInitialParticipantCount else { return nil }
            return Int(truncating: raw)
        }
        set {
            if let intValue = newValue {
                self.rawInitialParticipantCount = intValue as NSNumber
            } else {
                self.rawInitialParticipantCount = nil
            }
        }
    }
    
    // MARK: - Relationships

    @NSManaged var logContacts: Set<PersistedCallLogContact>

    // MARK: - Inits

    convenience init(callUUID: UUID, ownedCryptoId: ObvCryptoId, isIncoming: Bool, unknownContactsCount: Int, groupId: (groupUid: UID, groupOwner: ObvCryptoId)?, within context: NSManagedObjectContext) {

        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedCallLogItem.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.callUUID = callUUID
        self.endDate = nil
        self.groupOwnerIdentity = groupId?.groupOwner.getIdentity()
        self.groupUidRaw = groupId?.groupUid.raw
        self.initialParticipantCount = nil // Set latter
        self.rawOwnedCryptoId = ownedCryptoId.getIdentity()
        self.isIncoming = isIncoming
        self.unknownContactsCount = unknownContactsCount

        self.logContacts = Set()
    }

    // MARK: - Variables

    var ownedCryptoId: ObvCryptoId {
        return try! ObvCryptoId(identity: rawOwnedCryptoId)
    }

    /// We need to store callReportKind to be able to build predicate isMissedCall
    var callReportKind: CallReportKind? {
        get {
            guard let rawReportKind = rawReportKind else { return nil }
            return CallReportKind(rawValue: rawReportKind.intValue)!
        }
        set {
            if let newValue = newValue {
                self.rawReportKind = NSNumber(value: newValue.rawValue)
            } else {
                self.rawReportKind = nil
            }
        }
    }

    var caller: PersistedObvContactIdentity? {
        guard isIncoming else { return nil }
        let caller = logContacts.first(where: { $0.isCaller })
        return caller?.contactIdentity
    }

    func updateCallReportKind() {
        self.callReportKind = computedCallReportKind
    }

    // Duration in seconds
    var duration: Int? {
        guard let startDate = startDate else { return nil }
        guard let endDate = endDate else { return nil }
        return Int(endDate.timeIntervalSince(startDate))
    }

    var groupUid: UID? {
        guard let groupUidRaw = groupUidRaw else { return nil }
        return UID(uid: groupUidRaw)
    }

    func getGroupId() throws -> (groupUid: UID, groupOwner: ObvCryptoId)? {
        guard let groupUid = groupUid else { return nil }
        guard let groupOwnerIdentity = groupOwnerIdentity else { return nil }
        let groupOwner = try ObvCryptoId(identity: groupOwnerIdentity)
        return (groupUid, groupOwner)
    }

    private var computedCallReportKind: CallReportKind {
        if isIncoming {
            if logContacts.count == 1, let contact = logContacts.first {
                if contact.callReportKind == .missedIncomingCall {
                    return .missedIncomingCall
                } else if contact.callReportKind == .filteredIncomingCall {
                        return .filteredIncomingCall
                } else if contact.callReportKind == .rejectedIncomingCall {
                    return .rejectedIncomingCall
                } else if contact.callReportKind == .rejectedIncomingCallBecauseOfDeniedRecordPermission {
                    return .rejectedIncomingCallBecauseOfDeniedRecordPermission
                }
            }
            if logContacts.contains(where: { $0.callReportKind == .acceptedIncomingCall }) {
                return .acceptedIncomingCall
            }
        } else {
            if logContacts.contains(where: { $0.callReportKind == .acceptedOutgoingCall }) {
                return .acceptedOutgoingCall
            }
            if logContacts.allSatisfy({ $0.callReportKind == .rejectedOutgoingCall }) {
                return .rejectedOutgoingCall
            }
            if logContacts.allSatisfy({ $0.callReportKind == .busyOutgoingCall }) {
                return .busyOutgoingCall
            }
            if logContacts.allSatisfy({ $0.callReportKind == .unansweredOutgoingCall }) {
                return .unansweredOutgoingCall
            }
            if logContacts.allSatisfy({ $0.callReportKind == .uncompletedOutgoingCall }) {
                return .uncompletedOutgoingCall
            }
        }
        os_log("☎️📖 Please report: unable to compute CallLogStatus from the following CallLogContact: %{public}@", log: log, type: .fault, logContacts.map({ $0.callLogItem?.callReportKind?.debugDescription ?? "nil"}).joined(separator: ", "))
        assertionFailure()
        /// To be complete: it's a bug to not be able to compute the good CallReportKind from logContacts, but we choose to show something in this case.
        return isIncoming ? .anyIncomingCall : .anyOutgoingCall
    }
    
    func incrementUnknownContactsCount() {
        self.unknownContactsCount += 1
    }

}
// MARK: - Convenience DB getters

extension PersistedCallLogItem {

    private struct Predicate {
        private enum Key: String {
            case callUUID = "callUUID"
        }
        static func withCallUUID(equalTo callUUID: UUID) -> NSPredicate {
            NSPredicate(Key.callUUID, EqualToUuid: callUUID)
        }
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<PersistedCallLogItem> {
        return NSFetchRequest<PersistedCallLogItem>(entityName: self.entityName)
    }

    static func get(callUUID: UUID, within context: NSManagedObjectContext) throws -> PersistedCallLogItem? {
        let request: NSFetchRequest<PersistedCallLogItem> = PersistedCallLogItem.fetchRequest()
        request.predicate = Predicate.withCallUUID(equalTo: callUUID)
        return try context.fetch(request).first
    }

    static func get(objectID: TypeSafeManagedObjectID<PersistedCallLogItem>, within context: NSManagedObjectContext) throws -> PersistedCallLogItem? {
        return try context.existingObject(with: objectID.objectID) as? PersistedCallLogItem
    }

}
