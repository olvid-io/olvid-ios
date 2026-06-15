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
import ObvCrypto
import OlvidUtils
import ObvSettings
import ObvAppTypes


@objc(PersistedDiscussionSharedConfiguration)
public final class PersistedDiscussionSharedConfiguration: NSManagedObject {
    
    private static let entityName = "PersistedDiscussionSharedConfiguration"

    // Attributes
    
    @NSManaged private var rawExistenceDuration: NSNumber?
    @NSManaged private var rawVisibilityDuration: NSNumber?
    @NSManaged public fileprivate(set) var readOnce: Bool
    @NSManaged public fileprivate(set) var version: Int
    
    // Relationships
    
    // In practice, this is almost never nil. If this happens, this configuration will be cascade deleted soon.
    @NSManaged public private(set) var discussion: PersistedDiscussion?

    // Other variables
    
    private var changedKeys = Set<String>()

    public fileprivate(set) var existenceDuration: TimeInterval? {
        get {
            guard let seconds = rawExistenceDuration?.intValue else { return nil }
            return TimeInterval(seconds)
        }
        set {
            // We ensure that a value is always strictly positive. Otherwise,
            // we consider there is no existence duration.
            if let newValue, newValue > 0 {
                self.rawExistenceDuration = NSNumber(value: newValue)
            } else {
                self.rawExistenceDuration = nil
            }
        }
    }
    
    public fileprivate(set) var visibilityDuration: TimeInterval? {
        get {
            guard let seconds = rawVisibilityDuration?.intValue else { return nil }
            return TimeInterval(seconds)
        }
        set {
            // We ensure that a value is always strictly positive. Otherwise,
            // we consider there is no visibility duration.
            if let newValue, newValue > 0 {
                self.rawVisibilityDuration = NSNumber(value: newValue)
            } else {
                self.rawVisibilityDuration = nil
            }
        }
    }
    
    
    // MARK: - Observers
    
    nonisolated(unsafe) private static var observersHolder = ObserversHolder()
    
    public static func addObvObserver(_ newObserver: PersistedDiscussionSharedConfigurationObserver) async {
        await observersHolder.addObserver(newObserver)
    }

}


public enum PersistedDiscussionSharedConfigurationValue {
    case readOnce(readOnce: Bool)
    case existenceDuration(existenceDuration: TimeInterval?)
    case visibilityDuration(visibilityDuration: TimeInterval?)
    
    public func toExpirationJSON(overriding config: PersistedDiscussionSharedConfiguration) -> ExpirationJSON {
        switch self {
        case .readOnce(let readOnce):
            return ExpirationJSON(readOnce: readOnce,
                           visibilityDuration: config.visibilityDuration,
                           existenceDuration: config.existenceDuration)
        case .existenceDuration(let existenceDuration):
            return ExpirationJSON(readOnce: config.readOnce,
                           visibilityDuration: config.visibilityDuration,
                           existenceDuration: existenceDuration)
        case .visibilityDuration(let visibilityDuration):
            return ExpirationJSON(readOnce: config.readOnce,
                           visibilityDuration: visibilityDuration,
                           existenceDuration: config.existenceDuration)
        }
    }

}


// MARK: - Initializer and stuff

extension PersistedDiscussionSharedConfiguration {
    
    convenience init(discussion: PersistedDiscussion) throws {
        guard let context = discussion.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
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
        self.existenceDuration = ObvMessengerSettings.Discussions.existenceDuration
        self.visibilityDuration = ObvMessengerSettings.Discussions.visibilityDuration
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
    

    func replacePersistedDiscussionSharedConfiguration(with expirationJSON: ExpirationJSON) throws -> Bool {
        
        guard self.readOnce != expirationJSON.readOnce ||
                self.existenceDuration != expirationJSON.existenceDuration ||
                self.visibilityDuration != expirationJSON.visibilityDuration else {
            let sharedSettingHadToBeUpdated = false
            return sharedSettingHadToBeUpdated
        }
        self.readOnce = expirationJSON.readOnce
        self.existenceDuration = expirationJSON.existenceDuration
        self.visibilityDuration = expirationJSON.visibilityDuration
        self.version += 1
        
        let sharedSettingHadToBeUpdated = true
        return sharedSettingHadToBeUpdated

    }


    /// Exclusively called from ``PersistedDiscussion.mergeReceivedDiscussionSharedConfiguration(_:)``. Shall not be called from elsewhere.
    func mergePersistedDiscussionSharedConfiguration(with remoteConfig: PersistedDiscussion.SharedConfiguration) -> (sharedSettingHadToBeUpdated: Bool, weShouldSendBackOurSharedSettings: Bool) {
                
        let weShouldSendBackOurSharedSettingsIfAllowedTo: Bool
        let sharedSettingHadToBeUpdated: Bool

        if remoteConfig.version < self.version {
            
            // We ignore the received remote config
            sharedSettingHadToBeUpdated = false
            weShouldSendBackOurSharedSettingsIfAllowedTo = true
            
        } else if remoteConfig.version == self.version {
            
            // The version numbers are identical.
            // We compute the pgcd of the two configs and replace our shared settings we this pgcd.
            // Then, if our resulting shared settings are different from those we received, we send them back.
            
            let pgcdReadOnce = self.readOnce || remoteConfig.expiration.readOnce
            let pgcdExistenceDuration = TimeInterval.optionalMin(self.existenceDuration, remoteConfig.expiration.existenceDuration)
            let pgcdVisibilityDuration = TimeInterval.optionalMin(self.visibilityDuration, remoteConfig.expiration.visibilityDuration)
            
            if self.readOnce != pgcdReadOnce || self.existenceDuration != pgcdExistenceDuration || self.visibilityDuration != pgcdVisibilityDuration {
                self.readOnce = pgcdReadOnce
                self.existenceDuration = pgcdExistenceDuration
                self.visibilityDuration = pgcdVisibilityDuration
                sharedSettingHadToBeUpdated = true
            } else {
                sharedSettingHadToBeUpdated = false
            }
            
            if self.readOnce != remoteConfig.expiration.readOnce ||
                self.existenceDuration != remoteConfig.expiration.existenceDuration ||
                self.visibilityDuration != remoteConfig.expiration.visibilityDuration {
                weShouldSendBackOurSharedSettingsIfAllowedTo = true
            } else {
                weShouldSendBackOurSharedSettingsIfAllowedTo = false
            }
            
        } else {
            
            // The remote config is more recent that ours, so we replace ours
            self.readOnce = remoteConfig.expiration.readOnce
            self.existenceDuration = remoteConfig.expiration.existenceDuration
            self.visibilityDuration = remoteConfig.expiration.visibilityDuration
            self.version = remoteConfig.version // This necessarily updates our version number
            sharedSettingHadToBeUpdated = true
            weShouldSendBackOurSharedSettingsIfAllowedTo = false
            
        }
        
        return (sharedSettingHadToBeUpdated, weShouldSendBackOurSharedSettingsIfAllowedTo)
        
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
        fileprivate static var withExistenceLessOrEqualToZero: NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(withNonNilValueForKey: Key.rawExistenceDuration),
                NSPredicate(Key.rawExistenceDuration, LessOrEqualThanInt: 0),
            ])
        }
        fileprivate static var withVisiblityLessOrEqualToZero: NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(withNonNilValueForKey: Key.rawVisibilityDuration),
                NSPredicate(Key.rawVisibilityDuration, LessOrEqualThanInt: 0),
            ])
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

    
    public static func resetInconsistentDiscussionExistenceAndVisibilityDurations(within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<PersistedDiscussionSharedConfiguration> = PersistedDiscussionSharedConfiguration.fetchRequest()
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            Predicate.withVisiblityLessOrEqualToZero,
            Predicate.withExistenceLessOrEqualToZero,
        ])
        request.fetchBatchSize = 500
        let configurations = try context.fetch(request)
        configurations.forEach { configuration in
            if let existenceDuration = configuration.existenceDuration, existenceDuration <= 0 {
                configuration.existenceDuration = nil
            }
            if let visibilityDuration = configuration.visibilityDuration, visibilityDuration <= 0 {
                configuration.visibilityDuration = nil
            }
        }
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
        guard let discussionIdentifier = try self.discussion?.discussionIdentifier else {
            assertionFailure()
            throw ObvUICoreDataError.couldNotDetermineDiscussionIdentifier
        }
        let expiration = self.toExpirationJSON()
        return .init(discussionIdentifier: discussionIdentifier, version: self.version, expiration: expiration)
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


// MARK: On save

extension PersistedDiscussionSharedConfiguration {
        
    public override func willSave() {
        super.willSave()
        if isUpdated {
            changedKeys = Set<String>(self.changedValues().keys)
        }
    }
    
    public override func didSave() {
        super.didSave()
        
        defer {
            changedKeys.removeAll()
        }
        
        // Potentially notify that the previous backed up profile snapshot is obsolete.
        // We only notify in case of a change. Insertion/Deletion are notified by
        // the engine.
        // See `PersistedObvOwnedIdentity` for a list of entities that might post a similar notification.
        
        if !isDeleted && !isInserted && !changedKeys.isEmpty {
            if changedKeys.contains(Predicate.Key.version.rawValue) ||
                changedKeys.contains(Predicate.Key.rawExistenceDuration.rawValue) ||
                changedKeys.contains(Predicate.Key.rawVisibilityDuration.rawValue) ||
                changedKeys.contains(Predicate.Key.readOnce.rawValue) {
                if let ownedCryptoId = self.discussion?.ownedIdentity?.cryptoId {
                    Task {
                        await PersistedDiscussionSharedConfiguration.observersHolder.previousBackedUpProfileSnapShotIsObsoleteAsPersistedDiscussionSharedConfigurationChanged(ownedCryptoId: ownedCryptoId)
                    }
                } else {
                    assertionFailure()
                }
            }
        }
        
    }
    
}


// MARK: - For snapshot purposes

extension PersistedDiscussionSharedConfiguration {
    
    var syncSnapshotNode: PersistedDiscussionSharedConfigurationSyncSnapshotItem {
        .init(version: version,
              existenceDuration: existenceDuration,
              visibilityDuration: visibilityDuration,
              readOnce: readOnce)
    }
    
}


struct PersistedDiscussionSharedConfigurationSyncSnapshotItem: Codable, Hashable {

    private let version: Int
    private let existenceDuration: TimeInterval?
    private let visibilityDuration: TimeInterval?
    private let readOnce: Bool

    enum CodingKeys: String, CodingKey, CaseIterable, Codable {
        case version = "version"
        case existenceDuration = "existence_duration"
        case visibilityDuration = "visibility_duration"
        case readOnce = "read_once"
    }

    
    
    init(version: Int, existenceDuration: TimeInterval?, visibilityDuration: TimeInterval?, readOnce: Bool) {
        self.version = version
        self.existenceDuration = existenceDuration
        self.visibilityDuration = visibilityDuration
        self.readOnce = readOnce
    }

    
    // Synthesized implementation of encode(to encoder: Encoder)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 0
        self.existenceDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .existenceDuration)
        self.visibilityDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .visibilityDuration)
        self.readOnce = try container.decodeIfPresent(Bool.self, forKey: .readOnce) ?? false
    }
    
 
    func useToUpdate(_ configuration: PersistedDiscussionSharedConfiguration) {
        configuration.setVersion(with: version)
        configuration.setExistenceDuration(with: existenceDuration)
        configuration.setVisibilityDuration(with: visibilityDuration)
        configuration.setReadOnce(with: readOnce)
    }
    
}


// MARK: - PersistedDiscussionSharedConfiguration observers

public protocol PersistedDiscussionSharedConfigurationObserver: AnyObject, Sendable {
    func previousBackedUpProfileSnapShotIsObsoleteAsPersistedDiscussionSharedConfigurationChanged(ownedCryptoId: ObvCryptoId) async
}


private actor ObserversHolder: PersistedDiscussionSharedConfigurationObserver {
    
    private var observers = [WeakObserver]()
    
    private final class WeakObserver {
        private(set) weak var value: PersistedDiscussionSharedConfigurationObserver?
        init(value: PersistedDiscussionSharedConfigurationObserver?) {
            self.value = value
        }
    }

    func addObserver(_ newObserver: PersistedDiscussionSharedConfigurationObserver) {
        self.observers.append(.init(value: newObserver))
    }

    // Implementing OwnedIdentityObserver

    func previousBackedUpProfileSnapShotIsObsoleteAsPersistedDiscussionSharedConfigurationChanged(ownedCryptoId: ObvCryptoId) async {
        await withTaskGroup(of: Void.self) { taskGroup in
            for observer in observers.compactMap(\.value) {
                taskGroup.addTask { await observer.previousBackedUpProfileSnapShotIsObsoleteAsPersistedDiscussionSharedConfigurationChanged(ownedCryptoId: ownedCryptoId) }
            }
        }
    }
    
}
