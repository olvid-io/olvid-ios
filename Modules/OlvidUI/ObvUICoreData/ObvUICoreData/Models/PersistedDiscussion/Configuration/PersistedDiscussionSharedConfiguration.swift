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
import CoreData
import os.log
import ObvEngine
import ObvTypes
import ObvCrypto
import OlvidUtils


@objc(PersistedDiscussionSharedConfiguration)
public final class PersistedDiscussionSharedConfiguration: NSManagedObject, ObvErrorMaker {
    
    private static let entityName = "PersistedDiscussionSharedConfiguration"
    public static let errorDomain = "PersistedDiscussionSharedConfiguration"

    // Attributes
    
    @NSManaged private var rawExistenceDuration: NSNumber?
    @NSManaged private var rawVisibilityDuration: NSNumber?
    @NSManaged public fileprivate(set) var readOnce: Bool
    @NSManaged public fileprivate(set) var version: Int
    
    // Relationships
    
    // In practice, this is almost never nil. If this happens, this configuration will be cascade deleted soon.
    @NSManaged public private(set) var discussion: PersistedDiscussion?

    // Other variables
    
    public fileprivate(set) var existenceDuration: TimeInterval? {
        get {
            guard let seconds = rawExistenceDuration?.intValue else { return nil }
            return TimeInterval(seconds)
        }
        set {
            self.rawExistenceDuration = (newValue == nil ? nil : NSNumber(value: newValue!) )
        }
    }
    
    public fileprivate(set) var visibilityDuration: TimeInterval? {
        get {
            guard let seconds = rawVisibilityDuration?.intValue else { return nil }
            return TimeInterval(seconds)
        }
        set {
            self.rawVisibilityDuration = (newValue == nil ? nil : NSNumber(value: newValue!) )
        }
    }
    
}


public enum PersistedDiscussionSharedConfigurationValue {
    case readOnce(readOnce: Bool)
    case existenceDuration(existenceDuration: TimeInterval?)
    case visibilityDuration(visibilityDuration: TimeInterval?)
}


extension PersistedDiscussionSharedConfigurationValue {

    public func updatePersistedDiscussionSharedConfigurationValue(with configuration: PersistedDiscussionSharedConfiguration, initiatorAsOwnedCryptoId ownedCryptoId: ObvCryptoId) throws {
        let newExpiration: ExpirationJSON
        switch self {
        case .readOnce(readOnce: let readOnce):
            newExpiration = ExpirationJSON(
                readOnce: readOnce,
                visibilityDuration: configuration.visibilityDuration,
                existenceDuration: configuration.existenceDuration)
        case .existenceDuration(existenceDuration: let existenceDuration):
            newExpiration = ExpirationJSON(
                readOnce: configuration.readOnce,
                visibilityDuration: configuration.visibilityDuration,
                existenceDuration: existenceDuration)
        case .visibilityDuration(visibilityDuration: let visibilityDuration):
            newExpiration = ExpirationJSON(
                readOnce: configuration.readOnce,
                visibilityDuration: visibilityDuration,
                existenceDuration: configuration.existenceDuration)
        }
        try configuration.replacePersistedDiscussionSharedConfiguration(with: newExpiration, initiator: .ownedIdentity(ownedCryptoId: ownedCryptoId))
    }
    
}


// MARK: - Initializer and stuff

extension PersistedDiscussionSharedConfiguration {
    
    convenience init(discussion: PersistedDiscussion) throws {
        guard let context = discussion.managedObjectContext else {
            throw Self.makeError(message: "Could not find context")
        }
        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedDiscussionSharedConfiguration.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        // The following 3 values might be reset during the init procedure using the `setValuesUsingSettings`
        self.readOnce = false
        self.existenceDuration = nil
        self.visibilityDuration = nil
        self.version = 0
        self.discussion = discussion
    }
    
    
    func setValuesUsingSettings() {
        self.readOnce = ObvMessengerSettings.Discussions.readOnce
        self.existenceDuration = ObvMessengerSettings.Discussions.existenceDuration.timeInterval
        self.visibilityDuration = ObvMessengerSettings.Discussions.visibilityDuration.timeInterval
    }

    
    public func differs(from other: PersistedDiscussionSharedConfiguration) -> Bool {
        assert(self.managedObjectContext?.concurrencyType == .some(.mainQueueConcurrencyType))
        assert(other.managedObjectContext?.concurrencyType == .some(.mainQueueConcurrencyType))
        assert(Thread.isMainThread)
        return self.readOnce != other.readOnce ||
            self.existenceDuration != other.existenceDuration ||
            self.visibilityDuration != other.visibilityDuration
    }
    
    public enum Initiator {
        case ownedIdentity(ownedCryptoId: ObvCryptoId)
        case contact(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId, messageUploadTimestampFromServer: Date)
        case keycloak(lastModificationTimestamp: Date)
    }
    
    public func replacePersistedDiscussionSharedConfiguration(with expirationJSON: ExpirationJSON, initiator: Initiator) throws {
        
        try ensureInitiatorIsAllowedToModifyThisSharedConfiguration(initiator: initiator)

        guard self.readOnce != expirationJSON.readOnce ||
                self.existenceDuration != expirationJSON.existenceDuration ||
                self.visibilityDuration != expirationJSON.visibilityDuration else {
            return
        }
        self.readOnce = expirationJSON.readOnce
        self.existenceDuration = expirationJSON.existenceDuration
        self.visibilityDuration = expirationJSON.visibilityDuration
        self.version += 1
        
        // Insert a message into the discussion indicating that the shared settings
        
        do {
            try insertSystemMessageIndicatingThatDiscussionSharedConfigurationWasUpdated(initiator: initiator)
        } catch {
            assertionFailure(error.localizedDescription) // In producation, continue anyway
        }

    }
    
    
    public func mergePersistedDiscussionSharedConfiguration(with remoteConfig: DiscussionSharedConfigurationJSON, initiator: Initiator) throws {
        
        try ensureInitiatorIsAllowedToModifyThisSharedConfiguration(initiator: initiator)

        guard let discussion = self.discussion else {
            throw Self.makeError(message: "Cannot find discussion. It may have been deleted recently.")
        }
        
        if remoteConfig.version < self.version {
            // We ignore the received remote config
            ObvMessengerCoreDataNotification.anOldDiscussionSharedConfigurationWasReceived(persistedDiscussionObjectID: discussion.objectID)
                .postOnDispatchQueue()
            return
        } else if remoteConfig.version == self.version {
            // The version numbers are identical. If the config are identical, we do nothing.
            // Otherwise, we keep the "gcd" of the two configurations (the other party will do the same)
            // Note that we intentionally do not change the version
            guard self.readOnce != remoteConfig.expiration.readOnce ||
                    self.existenceDuration != remoteConfig.expiration.existenceDuration ||
                    self.visibilityDuration != remoteConfig.expiration.visibilityDuration else {
                return
            }
            self.readOnce = self.readOnce || remoteConfig.expiration.readOnce
            self.existenceDuration = TimeInterval.optionalMin(self.existenceDuration, remoteConfig.expiration.existenceDuration)
            self.visibilityDuration = TimeInterval.optionalMin(self.visibilityDuration, remoteConfig.expiration.visibilityDuration)
        } else {
            // The remote config is more recent that ours, so we replace ours
            self.readOnce = remoteConfig.expiration.readOnce
            self.existenceDuration = remoteConfig.expiration.existenceDuration
            self.visibilityDuration = remoteConfig.expiration.visibilityDuration
            self.version = remoteConfig.version // This necessarily updates our version number
        }
        
        // Insert a message into the discussion indicating that the shared settings
        
        do {
            try insertSystemMessageIndicatingThatDiscussionSharedConfigurationWasUpdated(initiator: initiator)
        } catch {
            assertionFailure(error.localizedDescription) // In producation, continue anyway
        }

    }
    
    
    private func insertSystemMessageIndicatingThatDiscussionSharedConfigurationWasUpdated(initiator: Initiator) throws {
     
        guard let managedObjectContext else {
            throw Self.makeError(message: "Cannot find context")
        }
        
        guard let discussion else {
            throw Self.makeError(message: "Cannot find discussion")
        }
        
        let optionalContactIdentity: PersistedObvContactIdentity?
        let markAsRead: Bool
        let messageUploadTimestampFromServer: Date?
        
        switch initiator {
        case .contact(ownedCryptoId: let ownedCryptoId, contactCryptoId: let contactCryptoId, messageUploadTimestampFromServer: let timestamp):
            optionalContactIdentity = try PersistedObvContactIdentity.get(contactCryptoId: contactCryptoId, ownedIdentityCryptoId: ownedCryptoId, whereOneToOneStatusIs: .any, within: managedObjectContext)
            markAsRead = false
            messageUploadTimestampFromServer = timestamp
        case .keycloak(lastModificationTimestamp: let timestamp):
            optionalContactIdentity = nil
            markAsRead = false
            messageUploadTimestampFromServer = timestamp
        case .ownedIdentity:
            optionalContactIdentity = nil
            markAsRead = true
            messageUploadTimestampFromServer = nil
        }
        
        try PersistedMessageSystem.insertUpdatedDiscussionSharedSettingsSystemMessage(
            within: discussion,
            optionalContactIdentity: optionalContactIdentity,
            expirationJSON: self.toExpirationJSON(),
            messageUploadTimestampFromServer: messageUploadTimestampFromServer,
            markAsRead: markAsRead)

    }
 
    
    private func ensureInitiatorIsAllowedToModifyThisSharedConfiguration(initiator: Initiator) throws {

        guard let discussion = self.discussion else { assertionFailure(); return }

        switch discussion.status {

        case .locked:
            throw Self.makeError(message: "The discussion is locked")

        case .preDiscussion:
            throw Self.makeError(message: "The discussion is a pre-discussion")

        case .active:

            switch try? discussion.kind {

            case .oneToOne(withContactIdentity: let contactIdentity):
                switch initiator {
                case .ownedIdentity(ownedCryptoId: let ownedCryptoId):
                    guard discussion.ownedIdentity?.cryptoId == ownedCryptoId else {
                        throw Self.makeError(message: "The initiator (owned identity) is not the owned identity of the one-to-one discussion")
                    }
                case .contact(ownedCryptoId: let ownedCryptoId, contactCryptoId: let contactCryptoId, messageUploadTimestampFromServer: _):
                    guard discussion.ownedIdentity?.cryptoId == ownedCryptoId && contactIdentity?.cryptoId == contactCryptoId else {
                        throw Self.makeError(message: "The initiator is neither the contact or the owned identity of the one-to-one discussion")
                    }
                case .keycloak:
                    throw Self.makeError(message: "The share configuration of a oneToOne discussion cannot be modified by keycloak")
                }

            case .groupV1(withContactGroup: let contactGroup):
                guard let contactGroup = contactGroup else {
                    throw Self.makeError(message: "Cannot find contact group")
                }
                switch initiator {
                case .ownedIdentity(ownedCryptoId: let ownedCryptoId):
                    guard contactGroup.ownerIdentity == ownedCryptoId.getIdentity() else {
                        throw Self.makeError(message: "The initiator of the change is not the group owner")
                    }
                case .contact(ownedCryptoId: let ownedCryptoId, contactCryptoId: let contactCryptoId, messageUploadTimestampFromServer: _):
                    guard contactGroup.ownerIdentity == contactCryptoId.getIdentity() && contactGroup.ownedIdentity?.cryptoId == ownedCryptoId else {
                        throw Self.makeError(message: "The initiator of the change is not the group owner")
                    }
                case .keycloak:
                    throw Self.makeError(message: "The share configuration of a groupV1 discussion cannot be modified by keycloak")
                }

            case .groupV2(withGroup: let group):
                guard let group = group else {
                    throw Self.makeError(message: "Cannot find group v2")
                }
                switch initiator {
                case .ownedIdentity(ownedCryptoId: let ownedCryptoId):
                    guard group.ownedIdentityIdentity == ownedCryptoId.getIdentity() else {
                        throw Self.makeError(message: "Unexpected owned identity")
                    }
                    guard group.ownedIdentityIsAllowedToChangeSettings else {
                        throw Self.makeError(message: "The initiator is not allowed to change settings")
                    }
                case .contact(ownedCryptoId: let ownedCryptoId, contactCryptoId: let contactCryptoId, messageUploadTimestampFromServer: _):
                    guard group.ownedIdentityIdentity == ownedCryptoId.getIdentity() else {
                        throw Self.makeError(message: "Unexpected owned identity")
                    }
                    guard let initiatorAsMember = group.otherMembers.first(where: { $0.identity == contactCryptoId.getIdentity() }) else {
                        throw Self.makeError(message: "The initiator is not part of the group")
                    }
                    guard initiatorAsMember.isAllowedToChangeSettings else {
                        throw Self.makeError(message: "The initiator is not allowed to change settings")
                    }
                case .keycloak:
                    guard group.keycloakManaged else {
                        throw Self.makeError(message: "A Keycloak server cannot change the configuration of a non-keycloak group")
                    }
                }

            case .none:
                assertionFailure()
                throw Self.makeError(message: "Unknown discussion type")
            }
        }
    }

    
    public var canBeModifiedAndSharedByOwnedIdentity: Bool {
        guard let discussion = self.discussion else { return false }
        switch discussion.status {
        case .preDiscussion, .locked:
            return false
        case .active:
            switch try? discussion.kind {
            case .oneToOne:
                return true
            case .groupV1(withContactGroup: let contactGroup):
                guard let contactGroup = contactGroup else { assertionFailure(); return false }
                return contactGroup.category == .owned
            case .groupV2(withGroup: let group):
                guard let group = group else { assertionFailure(); return false }
                return group.ownedIdentityIsAllowedToChangeSettings
            case .none:
                assertionFailure()
                return false
            }
        }
    }
 
    var isEphemeral: Bool {
        readOnce || visibilityDuration != nil || existenceDuration != nil
    }
    
}


// MARK: - Convenience DB getters

extension PersistedDiscussionSharedConfiguration {
    
    private struct Predicate {

        enum Key: String {
            case rawExistenceDuration = "rawExistenceDuration"
            case rawVisibilityDuration = "rawVisibilityDuration"
            case readOnce = "readOnce"
            case version = "version"
        }

        static func persistedDiscussionSharedConfiguration(withObjectID objectID: NSManagedObjectID) -> NSPredicate {
            NSPredicate(withObjectID: objectID)
        }
    }

    @nonobjc private static func fetchRequest() -> NSFetchRequest<PersistedDiscussionSharedConfiguration> {
        return NSFetchRequest<PersistedDiscussionSharedConfiguration>(entityName: PersistedDiscussionSharedConfiguration.entityName)
    }

    public static func get(objectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> PersistedDiscussionSharedConfiguration? {
        let request: NSFetchRequest<PersistedDiscussionSharedConfiguration> = PersistedDiscussionSharedConfiguration.fetchRequest()
        request.predicate = Predicate.persistedDiscussionSharedConfiguration(withObjectID: objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

}


// MARK: - JSON output

extension PersistedDiscussionSharedConfiguration {
    
    public func toExpirationJSON() -> ExpirationJSON {
        ExpirationJSON(readOnce: self.readOnce,
                       visibilityDuration: self.visibilityDuration,
                       existenceDuration: self.existenceDuration)
    }
    
    public func toDiscussionSharedConfigurationJSON() throws -> DiscussionSharedConfigurationJSON {
        let expiration = self.toExpirationJSON()
        switch try discussion?.kind {
        case .oneToOne, .none:
            return DiscussionSharedConfigurationJSON(version: self.version, expiration: expiration)
        case .groupV1(withContactGroup: let contactGroup):
            guard let contactGroup = contactGroup else { throw Self.makeError(message: "Could not find contact group of group discussion") }
            let groupV1Identifier = try contactGroup.getGroupId()
            return DiscussionSharedConfigurationJSON(version: self.version, expiration: expiration, groupV1Identifier: groupV1Identifier)
        case .groupV2(withGroup: let group):
            guard let group = group else { throw Self.makeError(message: "Could not find group v2 of group discussion") }
            let groupV2Identifier = group.groupIdentifier
            return DiscussionSharedConfigurationJSON(version: self.version, expiration: expiration, groupV2Identifier: groupV2Identifier)
        }
    }
    
}


// MARK: - For Backup purposes calls by PersistedDiscussionConfigurationBackupItem

extension PersistedDiscussionSharedConfiguration {

    /// This method shall **only** be used when restoring a backup.
    func setVersion(with version: Int) {
        self.version = version
    }

    /// This method shall **only** be used when restoring a backup.
    func setExistenceDuration(with existenceDuration: TimeInterval?) {
        self.existenceDuration = existenceDuration
    }

    /// This method shall **only** be used when restoring a backup.
    func setVisibilityDuration(with visibilityDuration: TimeInterval?) {
        self.visibilityDuration = visibilityDuration
    }

    /// This method shall **only** be used when restoring a backup.
    func setReadOnce(with readOnce: Bool) {
        self.readOnce = readOnce
    }

}
