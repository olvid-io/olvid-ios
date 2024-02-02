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
import CoreData
import os.log
import ObvEngine
import ObvTypes
import ObvCrypto
import OlvidUtils
import ObvSettings


@objc(PersistedCallLogItem)
public final class PersistedCallLogItem: NSManagedObject, ObvErrorMaker {

    // MARK: Internal constants

    private static let entityName = "PersistedCallLogItem"
    public static var errorDomain = "PersistedCallLogItem"
    private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: String(describing: PersistedCallLogItem.self))
    
    // MARK: - Attributes

    @NSManaged private var callUUID: UUID
    @NSManaged public var endDate: Date?
    @NSManaged private var groupOwnerIdentity: Data? // For group V1 identifier
    @NSManaged private var groupUidRaw: Data?  // For group V1 identifier
    @NSManaged private var groupV2Identifier: Data? // For group V2 identifier
    @NSManaged public private(set) var isIncoming: Bool
    @NSManaged private var rawInitialParticipantCount: NSNumber? // Should only be accessed through initialParticipantCount
    @NSManaged private var rawOwnedCryptoId: Data
    @NSManaged private var rawReportKind: NSNumber?
    @NSManaged public var startDate: Date?
    @NSManaged public private(set) var unknownContactsCount: Int
    
    // MARK: - Relationships

    @NSManaged public private(set) var logContacts: Set<PersistedCallLogContact>
    
    // MARK: Computed variables
    
    public var initialParticipantCount: Int? {
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

    // MARK: - Inits

    public convenience init(callUUID: UUID, ownedCryptoId: ObvCryptoId, isIncoming: Bool, unknownContactsCount: Int, groupIdentifier: GroupIdentifier?, within context: NSManagedObjectContext) throws {

        // Make sure no other PersistedCallLogItem exist with the same UUID
        
        guard try Self.get(callUUID: callUUID, within: context) == nil else {
            throw Self.makeError(message: "A PersistedCallLogItem already exist with the same UUID. We cannot create a new one.")
        }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedCallLogItem.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.callUUID = callUUID
        self.endDate = nil
        switch groupIdentifier {
        case .groupV1(let groupV1Identifier):
            if let group = try? PersistedContactGroup.getContactGroup(groupIdentifier: groupV1Identifier, ownedCryptoId: ownedCryptoId, within: context) {
                self.groupOwnerIdentity = group.ownerIdentity
                self.groupUidRaw = group.groupUid.raw
            }
        case .groupV2(let groupV2Identifier):
            if let group = try? PersistedGroupV2.get(ownIdentity: ownedCryptoId, appGroupIdentifier: groupV2Identifier, within: context) {
                self.groupV2Identifier = group.groupIdentifier
            }
        case nil:
            break
        }
        
        self.initialParticipantCount = nil // Set later
        self.rawOwnedCryptoId = ownedCryptoId.getIdentity()
        self.isIncoming = isIncoming
        self.unknownContactsCount = unknownContactsCount

        self.logContacts = Set()
    }

    // MARK: - Variables

    public var ownedCryptoId: ObvCryptoId? {
        return try? ObvCryptoId(identity: rawOwnedCryptoId)
    }

    /// We need to store callReportKind to be able to build predicate isMissedCall
    public var callReportKind: CallReportKind? {
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

    private var groupUid: UID? {
        guard let groupUidRaw = groupUidRaw else { return nil }
        return UID(uid: groupUidRaw)
    }

    public func getGroupIdentifier() throws -> GroupIdentifierBasedOnObjectID? {
        guard let context = self.managedObjectContext else { assertionFailure(); throw Self.makeError(message: "Could not find context") }
        guard let ownedCryptoId else {
            throw ObvError.couldNotDetermineOwnedCryptoId
        }
        if let groupUid = groupUid, let groupOwnerIdentity = groupOwnerIdentity {
            let groupOwner = try ObvCryptoId(identity: groupOwnerIdentity)
            let groupIdentifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
            guard let persistedContactGroup = try? PersistedContactGroup.getContactGroup(groupIdentifier: groupIdentifier, ownedCryptoId: ownedCryptoId, within: context) else { return nil }
            return .groupV1(persistedContactGroup.typedObjectID)
        } else if let groupV2Identifier = groupV2Identifier {
            guard let group = try? PersistedGroupV2.get(ownIdentity: ownedCryptoId, appGroupIdentifier: groupV2Identifier, within: context) else {
                return nil
            }
            return .groupV2(group.typedObjectID)
        } else {
            return nil
        }
    }
    
    public var groupIdentifier: GroupIdentifier? {
        if let groupUid = groupUid, let groupOwnerIdentity = groupOwnerIdentity, let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) {
            let groupIdentifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
            return .groupV1(groupV1Identifier: groupIdentifier)
        } else if let groupV2Identifier = groupV2Identifier {
            return .groupV2(groupV2Identifier: groupV2Identifier)
        } else {
            return nil
        }
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
                } else if contact.callReportKind == .answeredOnOtherDevice {
                    return .answeredOnOtherDevice
                } else  if contact.callReportKind == .rejectedOnOtherDevice {
                    return .rejectedOnOtherDevice
                } else if contact.callReportKind == .rejectedIncomingCallAsTheReceiveCallsOnThisDeviceSettingIsFalse {
                    return .rejectedIncomingCallAsTheReceiveCallsOnThisDeviceSettingIsFalse
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
    
    public func incrementUnknownContactsCount() {
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

    public static func get(callUUID: UUID, within context: NSManagedObjectContext) throws -> PersistedCallLogItem? {
        let request: NSFetchRequest<PersistedCallLogItem> = PersistedCallLogItem.fetchRequest()
        request.predicate = Predicate.withCallUUID(equalTo: callUUID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    public static func get(objectID: TypeSafeManagedObjectID<PersistedCallLogItem>, within context: NSManagedObjectContext) throws -> PersistedCallLogItem? {
        return try context.existingObject(with: objectID.objectID) as? PersistedCallLogItem
    }

}


// MARK: - Errors

extension PersistedCallLogItem {
    
    enum ObvError: Error {
        case couldNotDetermineOwnedCryptoId
    }
    
}
