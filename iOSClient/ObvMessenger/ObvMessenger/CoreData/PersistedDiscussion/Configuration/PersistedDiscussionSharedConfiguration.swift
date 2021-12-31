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


@objc(PersistedDiscussionSharedConfiguration)
final class PersistedDiscussionSharedConfiguration: NSManagedObject {
    
    private static let entityName = "PersistedDiscussionSharedConfiguration"
    private static let readOnceKey = "readOnce"
    private static let rawExistenceDurationKey = "rawExistenceDuration"
    private static let rawVisibilityDurationKey = "rawVisibilityDuration"
    private static let versionKey = "version"

    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { Self.makeError(message: message) }

    @NSManaged fileprivate(set) var readOnce: Bool
    @NSManaged private var rawExistenceDuration: NSNumber?
    @NSManaged private var rawVisibilityDuration: NSNumber?
    @NSManaged fileprivate(set) var version: Int
    
    fileprivate(set) var existenceDuration: TimeInterval? {
        get {
            guard let seconds = rawExistenceDuration?.intValue else { return nil }
            return TimeInterval(seconds)
        }
        set {
            self.rawExistenceDuration = (newValue == nil ? nil : NSNumber(value: newValue!) )
        }
    }
    
    fileprivate(set) var visibilityDuration: TimeInterval? {
        get {
            guard let seconds = rawVisibilityDuration?.intValue else { return nil }
            return TimeInterval(seconds)
        }
        set {
            self.rawVisibilityDuration = (newValue == nil ? nil : NSNumber(value: newValue!) )
        }
    }
    
    /// In practice, this is almost never nil. If this happens, this configuration will be cascade deleted soon.
    @NSManaged private(set) var discussion: PersistedDiscussion?

    private var changedKeys = Set<String>()

}

enum PersistedDiscussionSharedConfigurationValue {
    case readOnce(readOnce: Bool)
    case existenceDuration(existenceDuration: TimeInterval?)
    case visibilityDuration(visibilityDuration: TimeInterval?)
}

extension PersistedDiscussionSharedConfigurationValue {
    func update(for configuration: PersistedDiscussionSharedConfiguration, initiator: ObvCryptoId) throws -> Bool {
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
        return try configuration.replace(with: newExpiration, initiator: initiator)
    }
}

// MARK: - Initializer and stuff

extension PersistedDiscussionSharedConfiguration {
    
    convenience init?(discussion: PersistedDiscussion) {
        guard let context = discussion.managedObjectContext else { return nil }
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
    
    func differs(from other: PersistedDiscussionSharedConfiguration) -> Bool {
        assert(self.managedObjectContext?.concurrencyType == .some(.mainQueueConcurrencyType))
        assert(other.managedObjectContext?.concurrencyType == .some(.mainQueueConcurrencyType))
        assert(Thread.isMainThread)
        return self.readOnce != other.readOnce ||
            self.existenceDuration != other.existenceDuration ||
            self.visibilityDuration != other.visibilityDuration
    }
    
    
    func replace(with expirationJSON: ExpirationJSON, initiator: ObvCryptoId) throws -> Bool {
        
        try ensureInitiatorIsAllowedToModifyThisSharedConfiguration(initiator: initiator)
        
        guard self.readOnce != expirationJSON.readOnce ||
                self.existenceDuration != expirationJSON.existenceDuration ||
                self.visibilityDuration != expirationJSON.visibilityDuration else {
            return false
        }
        self.readOnce = expirationJSON.readOnce
        self.existenceDuration = expirationJSON.existenceDuration
        self.visibilityDuration = expirationJSON.visibilityDuration
        self.version += 1
        return true
        
    }
    
    
    func merge(with remoteConfig: DiscussionSharedConfigurationJSON, initiator: ObvCryptoId) throws -> Bool {
        
        try ensureInitiatorIsAllowedToModifyThisSharedConfiguration(initiator: initiator)

        guard let discussion = self.discussion else {
            throw makeError(message: "Cannot find discussion. It may have been deleted recently.")
        }
        
        if remoteConfig.version < self.version {
            // We ignore the received remote config
            ObvMessengerInternalNotification.anOldDiscussionSharedConfigurationWasReceived(persistedDiscussionObjectID: discussion.objectID)
                .postOnDispatchQueue()
            return false
        } else if remoteConfig.version == self.version {
            // The version numbers are identical. If the config are identical, we do nothing.
            // Otherwise, we keep the "gcd" of the two configurations (the other party will do the same)
            // Note that we intentionally do not change the version
            guard self.readOnce != remoteConfig.expiration.readOnce ||
                    self.existenceDuration != remoteConfig.expiration.existenceDuration ||
                    self.visibilityDuration != remoteConfig.expiration.visibilityDuration else {
                return false
            }
            self.readOnce = self.readOnce || remoteConfig.expiration.readOnce
            self.existenceDuration = TimeInterval.optionalMin(self.existenceDuration, remoteConfig.expiration.existenceDuration)
            self.visibilityDuration = TimeInterval.optionalMin(self.visibilityDuration, remoteConfig.expiration.visibilityDuration)
            return true
        } else {
            // The remote config is more recent that ours, so we replace ours
            self.readOnce = remoteConfig.expiration.readOnce
            self.existenceDuration = remoteConfig.expiration.existenceDuration
            self.visibilityDuration = remoteConfig.expiration.visibilityDuration
            self.version = remoteConfig.version // This necessarily updates our version number
            return true
        }
    }
 
    
    private func ensureInitiatorIsAllowedToModifyThisSharedConfiguration(initiator: ObvCryptoId) throws {
        if let oneToOneDiscussion = discussion as? PersistedOneToOneDiscussion {
            guard [oneToOneDiscussion.contactIdentity?.cryptoId, oneToOneDiscussion.ownedIdentity?.cryptoId].contains(initiator) else {
                throw makeError(message: "The initiator is neither the contact or the owned identity of the one-to-one discussion")
            }
        } else if let groupDiscussion = discussion as? PersistedGroupDiscussion {
            guard let contactGroup = groupDiscussion.contactGroup else {
                throw makeError(message: "Cannot find contact group")
            }
            guard contactGroup.ownerIdentity == initiator.getIdentity() else {
                throw makeError(message: "The initiator of the change is not the group owner")
            }
        }
    }

    
    var canBeModifiedAndSharedByOwnedIdentity: Bool {
        if discussion is PersistedOneToOneDiscussion {
            return true
        } else if let groupDiscussion = discussion as? PersistedGroupDiscussion {
            guard let contactGroup = groupDiscussion.contactGroup else { assertionFailure(); return false }
            return contactGroup.category == .owned
        } else {
            assertionFailure()
            return false
        }
    }
 
    var isEphemeral: Bool {
        readOnce || visibilityDuration != nil || existenceDuration != nil
    }
    
}


// MARK: - Convenience DB getters

extension PersistedDiscussionSharedConfiguration {
    
    private struct Predicate {
        static func persistedDiscussionSharedConfiguration(withObjectID objectID: NSManagedObjectID) -> NSPredicate {
            NSPredicate(format: "SELF == %@", objectID)
        }
    }

    @nonobjc private static func fetchRequest() -> NSFetchRequest<PersistedDiscussionSharedConfiguration> {
        return NSFetchRequest<PersistedDiscussionSharedConfiguration>(entityName: PersistedDiscussionSharedConfiguration.entityName)
    }

    static func get(objectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> PersistedDiscussionSharedConfiguration? {
        let request: NSFetchRequest<PersistedDiscussionSharedConfiguration> = PersistedDiscussionSharedConfiguration.fetchRequest()
        request.predicate = Predicate.persistedDiscussionSharedConfiguration(withObjectID: objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

}


// MARK: - JSON output

extension PersistedDiscussionSharedConfiguration {
    
    func toExpirationJSON() -> ExpirationJSON {
        ExpirationJSON(readOnce: self.readOnce,
                       visibilityDuration: self.visibilityDuration,
                       existenceDuration: self.existenceDuration)
    }
    
    func toJSON() throws -> DiscussionSharedConfigurationJSON {
        let expiration = self.toExpirationJSON()
        let groupId: (groupUid: UID, groupOwner: ObvCryptoId)?
        if let groupDiscussion = discussion as? PersistedGroupDiscussion {
            guard let contactGroup = groupDiscussion.contactGroup else { throw makeError(message: "Could not find contact group of group discussion") }
            groupId = try contactGroup.getGroupId()
        } else {
            groupId = nil
        }
        return DiscussionSharedConfigurationJSON(version: self.version,
                                                 expiration: expiration,
                                                 groupId: groupId)
    }
    
}


// MARK: - For Backup purposes

extension PersistedDiscussionConfigurationBackupItem {
    
    func updateExistingInstance(_ configuration: PersistedDiscussionSharedConfiguration) {
        
        if let sharedSettingsVersion = self.sharedSettingsVersion {
            configuration.version = sharedSettingsVersion
        }
        configuration.existenceDuration = self.existenceDuration
        configuration.visibilityDuration = self.visibilityDuration
        if let readOnce = self.readOnce {
            configuration.readOnce = readOnce
        }

    }
    
}
