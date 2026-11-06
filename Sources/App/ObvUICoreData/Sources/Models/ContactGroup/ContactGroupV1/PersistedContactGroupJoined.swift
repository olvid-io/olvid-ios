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
import CoreData
import OSLog
import ObvEngine
import ObvTypes
import OlvidUtils
import ObvSettings
import ObvAppCoreConstants


@objc(PersistedContactGroupJoined)
public final class PersistedContactGroupJoined: PersistedContactGroup {
    
    private static let entityName = "PersistedContactGroupJoined"
    
    // MARK: Attributes

    @NSManaged private(set) var customPhotoFilename: String?
    @NSManaged public private(set) var groupNameCustom: String?
    @NSManaged private var rawStatus: Int

    // MARK: Relationships

    @NSManaged private(set) public var owner: PersistedObvContactIdentity? // If nil, this entity is eventually cascade-deleted

    // MARK: Other variables

    public var status: PublishedDetailsStatusType {
        return PublishedDetailsStatusType(rawValue: self.rawStatus)!
    }
    
    public var customPhotoURL: URL? {
        guard let customPhotoFilename = customPhotoFilename else { return nil }
        return ObvUICoreDataConstants.ContainerURL.forCustomGroupProfilePictures.appendingPathComponent(customPhotoFilename)
    }

    private var changedKeys = Set<String>()

    // MARK: - Initializer

    convenience init(contactGroup: ObvContactGroup, isRestoringSyncSnapshotOrBackup: Bool, within context: NSManagedObjectContext) throws {

        guard contactGroup.groupType == .joined else {
            assertionFailure()
            throw ObvUICoreDataError.unexpectedGroupType
        }
        
        guard let ownedIdentity = try PersistedObvOwnedIdentity.get(persisted: contactGroup.ownedIdentity, within: context) else {
            assertionFailure()
            throw ObvUICoreDataError.couldNotFindOwnedIdentity
        }
        guard let owner = try PersistedObvContactIdentity.get(cryptoId: contactGroup.groupOwner.cryptoId, ownedIdentity: ownedIdentity, whereOneToOneStatusIs: .any) else {
            assertionFailure()
            throw ObvUICoreDataError.couldNotFindContactWithId(contactIdentifier: .init(contactCryptoId: contactGroup.groupOwner.cryptoId, ownedCryptoId: contactGroup.ownedIdentity.cryptoId))
        }
        
        try self.init(contactGroup: contactGroup,
                      groupName: contactGroup.trustedOrLatestCoreDetails.name,
                      category: .joined, 
                      isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup,
                      forEntityName: PersistedContactGroupJoined.entityName,
                      within: context)
        
        self.groupNameCustom = nil
        self.rawStatus = PublishedDetailsStatusType.noNewPublishedDetails.rawValue
        self.owner = owner
        self.customPhotoFilename = nil
    }


    // MARK: - Receiving discussion shared configurations

    
    /// Called when receiving a ``DiscussionSharedConfigurationJSON`` from a contact or an owned identity indicating this particular group as the target. This method makes sure the contact  or the owned identity is allowed to change the configuration, i.e., that she is the group owner.
    override func mergeReceivedDiscussionSharedConfiguration(discussionSharedConfiguration: PersistedDiscussion.SharedConfiguration, receivedFrom cryptoId: ObvCryptoId) throws -> (sharedSettingHadToBeUpdated: Bool, weShouldSendBackOurSharedSettings: Bool) {
        
        let (sharedSettingHadToBeUpdated, _) = try super.mergeReceivedDiscussionSharedConfiguration(discussionSharedConfiguration: discussionSharedConfiguration, receivedFrom: cryptoId)
        
        // Since we joined this group, we are not allowed to change its shared settings, so we never send ours back

        let weShouldSendBackOurSharedSettings = false

        return (sharedSettingHadToBeUpdated, weShouldSendBackOurSharedSettings)
        
    }
    
}


// MARK: - Other methods

extension PersistedContactGroupJoined {
    
    struct Predicate {
        enum Key: String {
            case groupNameCustom = "groupNameCustom"
        }
    }
    
    func setGroupNameCustom(to groupNameCustom: String?) throws -> Bool {
        let groupNameCustomHadToBeUpdated: Bool
        let newGroupNameCustom = groupNameCustom?.trimmingCharacters(in: .whitespacesAndNewlines).mapToNilIfZeroLength()
        if let newGroupNameCustom, !newGroupNameCustom.isEmpty {
            if self.groupNameCustom != newGroupNameCustom {
                self.groupNameCustom = newGroupNameCustom
                groupNameCustomHadToBeUpdated = true
            } else {
                groupNameCustomHadToBeUpdated = false
            }
        } else {
            if self.groupNameCustom != nil {
                self.groupNameCustom = nil
                groupNameCustomHadToBeUpdated = true
            } else {
                groupNameCustomHadToBeUpdated = false
            }
        }
        if groupNameCustomHadToBeUpdated {
            try discussion.resetTitle(to: self.displayName)
        }
        return groupNameCustomHadToBeUpdated
    }
    
    
    func setStatus(to newStatus: PublishedDetailsStatusType) {
        guard self.rawStatus != newStatus.rawValue else { return }
        self.rawStatus = newStatus.rawValue
        try? createOrUpdateTheAssociatedDisplayedContactGroup()
    }

    public func markPublishedDetailsAsSeen() {
        switch self.status {
        case .noNewPublishedDetails:
            return
        case .unseenPublishedDetails:
            self.setStatus(to: .seenPublishedDetails)
        case .seenPublishedDetails:
            return
        }
    }
    
}


// MARK: - willSave/didSave

extension PersistedContactGroupJoined {

    override public func willSave() {
        super.willSave()
        changedKeys = Set(changedValues().keys)
    }

    override public func didSave() {
        super.didSave()
        defer { changedKeys.removeAll() }
        guard !isDeleted else { return }
        if changedKeys.contains(Predicate.Key.groupNameCustom.rawValue) {
            do {
                let groupIdentifier = try self.obvGroupIdentifier
                Task { await PersistedContactGroupJoined.observersHolder.aGroupV1CustomNameChanged(groupIdentifier: groupIdentifier) }
            } catch {
                assertionFailure(error.localizedDescription) // Continue anyway
            }
        }
    }

}


// MARK: - PersistedContactGroupJoined observers

public protocol PersistedContactGroupJoinedObserver: AnyObject, Sendable {
    func aGroupV1CustomNameChanged(groupIdentifier: ObvGroupV1Identifier) async
}

public extension PersistedContactGroupJoinedObserver {
    func aGroupV1CustomNameChanged(groupIdentifier: ObvGroupV1Identifier) async {}
}

extension PersistedContactGroupJoined {

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "PersistedContactGroupJoined")

    nonisolated(unsafe) private static var observersHolder = ObserversHolder()

    public static func addObvObserver(_ newObserver: PersistedContactGroupJoinedObserver) async {
        await observersHolder.addObserver(newObserver)
    }

}

private actor ObserversHolder: PersistedContactGroupJoinedObserver {

    private var observers = [WeakObserver]()

    private final class WeakObserver {
        private(set) weak var value: PersistedContactGroupJoinedObserver?
        init(value: PersistedContactGroupJoinedObserver?) { self.value = value }
    }

    func addObserver(_ newObserver: PersistedContactGroupJoinedObserver) {
        observers.append(.init(value: newObserver))
    }

    func aGroupV1CustomNameChanged(groupIdentifier: ObvGroupV1Identifier) async {
        await withTaskGroup(of: Void.self) { taskGroup in
            for observer in observers.compactMap(\.value) {
                taskGroup.addTask { await observer.aGroupV1CustomNameChanged(groupIdentifier: groupIdentifier) }
            }
        }
    }

}
