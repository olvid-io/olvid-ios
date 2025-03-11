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
import CoreData
import ObvSettings
import os.log
import OlvidUtils
import ObvTypes
import ObvAppTypes
import UIKit
import CryptoKit

@objc(PersistedLocation)
public class PersistedLocation: NSManagedObject {
    
    private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "PersistedLocation")
    
    // MARK: Attributes

    @NSManaged private var rawContinuousOrOneShot: Int16
    @NSManaged private var rawSentOrReceived: Int16
    @NSManaged public private(set) var address: String?
    @NSManaged private var rawAltitude: NSNumber?
    @NSManaged private var rawPrecision: NSNumber?
    @NSManaged private var rawLongitude: NSNumber?
    @NSManaged private var rawLatitude: NSNumber?
    @NSManaged private var quality: Int
    @NSManaged public private(set) var count: Int
    @NSManaged public private(set) var sharingExpiration: Date? // non-nil if message can expire
    @NSManaged private var timestamp: Date?
    
    
    // MARK: - Computed variables
    
    public var continuousOrOneShot: ContinuousOrOneShot {
        get throws {
            guard let value = ContinuousOrOneShot(rawValue: rawContinuousOrOneShot) else { assertionFailure(); throw ObvUICoreDataError.unexpectedNilValue(valueName: "continuousOrOneShot") }
            return value
        }
    }
    
    var sentOrReceived: SentOrReceived {
        get throws {
            guard let value = SentOrReceived(rawValue: rawSentOrReceived) else { assertionFailure(); throw ObvUICoreDataError.unexpectedNilValue(valueName: "sentOrReceived") }
            return value
        }
    }
    
    private var altitude: Double? {
        get {
            return rawAltitude?.doubleValue
        }
        set {
            self.rawAltitude = (newValue == nil ? nil : NSNumber(value: newValue!))
        }
    }
    
    public private(set) var latitude: Double {
        get {
            return rawLatitude?.doubleValue ?? 0.0
        }
        set {
            self.rawLatitude = NSNumber(value: newValue)
        }
    }
    
    public private(set) var longitude: Double {
        get {
            return rawLongitude?.doubleValue ?? 0.0
        }
        set {
            self.rawLongitude = NSNumber(value: newValue)
        }
    }
    
    private var precision: Double? {
        get {
            return rawPrecision?.doubleValue
        }
        set {
            self.rawPrecision = (newValue == nil ? nil : NSNumber(value: newValue!))
        }
    }
    
    public var snapshotFilename: String? {
        let filename: String
        if let address = address {
            filename = address
        } else {
            filename = "\(latitude)-\(longitude)"
        }
        
        let filenameForArchiving = "map_snapshot_\(filename)"
        
        guard let filenameData = filenameForArchiving.data(using: .utf8) else { return nil }
        
        let digest = SHA256.hash(data: filenameData)
        let digestString = digest.map { String(format: "%02hhx", $0) }.joined()
        return [digestString, "png"].joined(separator: ".")
    }
    
    struct PredicateForPersistedLocation {
        enum Key: String {
            // Attributes
            case timestamp = "timestamp"
        }
    }
    
}


// MARK: - Initializers

extension PersistedLocation {
    
    private convenience init(continuousOrOneShot: ContinuousOrOneShot,
                             sentOrReceived: SentOrReceived,
                             address: String?,
                             altitude: Double?,
                             latitude: Double,
                             longitude: Double,
                             quality: Int,
                             precision: Double?,
                             count: Int?,
                             sharingExpiration: Date?,
                             timestamp: Date,
                             forEntityName entityName: String,
                             within context: NSManagedObjectContext) throws {

        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        self.rawContinuousOrOneShot = continuousOrOneShot.rawValue
        self.rawSentOrReceived = sentOrReceived.rawValue
        self.address = address
        self.altitude = altitude
        self.latitude = latitude
        self.longitude = longitude
        self.quality = quality
        self.precision = precision
        self.count = count ?? 0
        self.sharingExpiration = sharingExpiration
        self.timestamp = timestamp
        
    }
    
    
    fileprivate convenience init(continuousOrOneShot: ContinuousOrOneShot,
                                 sentOrReceived: SentOrReceived,
                                 locationData: ObvLocationData,
                                 count: Int?,
                                 sharingExpiration: Date?,
                                 forEntityName entityName: String,
                                 within context: NSManagedObjectContext) throws {
        
        try self.init(continuousOrOneShot: continuousOrOneShot,
                      sentOrReceived: sentOrReceived,
                      address: locationData.address,
                      altitude: locationData.altitude,
                      latitude: locationData.latitude,
                      longitude: locationData.longitude,
                      quality: 0,
                      precision: locationData.precision,
                      count: count,
                      sharingExpiration: sharingExpiration,
                      timestamp: locationData.timestamp ?? .now,
                      forEntityName: entityName,
                      within: context)

        
    }
    
    
    func toLocationJSON() throws -> LocationJSON {

        let sharingType: LocationJSON.LocationSharingType
        switch try continuousOrOneShot {
        case .continuous:
            sharingType = .SHARING
        case .oneShot:
            sharingType = .SEND
        }
        
        let locationJSON = LocationJSON(type: sharingType,
                                        timestamp: self.timestamp,
                                        count: self.count,
                                        quality: self.quality,
                                        sharingExpiration: self.sharingExpiration?.timeIntervalSince1970,
                                        latitude: self.latitude,
                                        longitude: self.longitude,
                                        altitude: self.altitude,
                                        precision: self.precision,
                                        address: self.address)
        
        return locationJSON
    }
    
    public var serialized: Data? {
        try? toLocationJSON().jsonEncode()
    }
}

extension PersistedLocation {
    
    func updateContentForContinuousLocation(with locationData: ObvLocationData, count: Int) throws {
        guard self.count < count else {
            return
        }
        try self.updateContent(locationData: locationData, count: count)
    }
    
    func updateContentForOneShotLocation(with locationData: ObvLocationData) throws {
        try self.updateContent(locationData: locationData, count: nil)
    }
    
    
    private func updateContent(locationData: ObvLocationData, count: Int?) throws {
        
        if self.address != locationData.address {
            self.address = locationData.address
        }
        if self.altitude != locationData.altitude {
            self.altitude = locationData.altitude
        }
        if self.latitude != locationData.latitude {
            self.latitude = locationData.latitude
        }
        if self.longitude != locationData.longitude {
            self.longitude = locationData.longitude
        }
        if self.precision != locationData.precision {
            self.precision = locationData.precision
        }
        if self.count != count ?? 0 {
            self.count = count ?? 0
        }
        if self.timestamp != locationData.timestamp {
            self.timestamp = locationData.timestamp
        }
        
        if self.hasChanges {
            deleteSnapshot() // We want to delete current snapshot if location has been updated
        }
        
    }
    
}

extension PersistedLocation {
    
    private func deleteSnapshot() {
    
        guard let filename = self.snapshotFilename else { return }
        
        let snapshotURL = ObvUICoreDataConstants.ContainerURL.forMapSnapshots.appendingPathComponent(filename)
        
        if FileManager.default.fileExists(atPath: snapshotURL.path) {
            try? FileManager.default.removeItem(at: snapshotURL)
        }
        
    }
    
}

extension PersistedLocation {

    /// Body of a location message in order to be displayed for legacy versions of the app that do NOT feature location sharing
    var legacyLocationMessageBody: String {
        var body = ""
        
        body += "https://www.google.com/maps/search/?api=1&query="
        body += String(self.latitude)
        body += "%2C"
        body += String(self.longitude)
        
        return body
    }

}

// MARK: - Convenience DB getters
extension PersistedLocation {
    
    struct Predicate {
        enum Key: String {
            // Attributes
            case rawType = "rawType"
            case address = "address"
            case altiude = "altitude"
            case latitude = "latitude"
            case longitude = "longitude"
            case quality = "quality"
            case precision = "precision"
            case count = "count"
            case sharingExpiration = "sharingExpiration"
            case timestamp = "timestamp"
        }
    }
    
    /// Shall **only** be called from the sublcasses, after the necessary checks have been performed.
    /// In particular, we don't want to delete a continuous location shown in two distinct messages when one of the messages
    /// is deleted.
    func deletePersistedLocation() throws {
        guard let context = self.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        context.delete(self)
    }
    
}

extension PersistedLocation {
    
    public enum ContinuousOrOneShot: Int16 {
        case continuous = 0
        case oneShot = 1
    }

    enum SentOrReceived: Int16 {
        case sent = 0
        case received = 1
    }
        
}


// MARK: - PersistedLocationContinuous

@objc(PersistedLocationContinuous)
public class PersistedLocationContinuous: PersistedLocation {
    
    private static let entityName = "PersistedLocationContinuous"
    
    fileprivate convenience init(sentOrReceived: SentOrReceived, locationData: ObvLocationData, count: Int, sharingExpiration: Date?, forEntityName: String, within context: NSManagedObjectContext) throws {
        
        try self.init(continuousOrOneShot: .continuous,
                      sentOrReceived: sentOrReceived,
                      locationData: locationData,
                      count: count,
                      sharingExpiration: sharingExpiration,
                      forEntityName: forEntityName,
                      within: context)
        
    }
    
    
    public var isSharingLocationExpired: Bool {
        guard let expirationDate = sharingExpiration else { return false }
        
        return expirationDate < Date()
    }
    
}

extension PersistedLocationContinuous {

    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedLocationContinuous> {
        return NSFetchRequest<PersistedLocationContinuous>(entityName: PersistedLocationContinuous.entityName)
    }

    struct Predicate {
        
        static var isContinuousSent: NSPredicate {
            return NSPredicate(withEntity: PersistedLocationContinuousSent.entity())
        }
        
        static var isContinuousReceived: NSPredicate {
                return NSPredicate(withEntity: PersistedLocationContinuousReceived.entity())
        }
        
        static func withinDiscussion(_ discussion: PersistedDiscussion) -> NSPredicate {
            return NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    Predicate.isContinuousReceived,
                    PersistedLocationContinuousReceived.Predicate.withinDiscussion(discussion)
                ]),
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    Predicate.isContinuousSent,
                    PersistedLocationContinuousSent.Predicate.withinDiscussion(discussion)
                ]),
            ])
        }
    }
    
    public static func getFetchRequestForLocations(in discussion: PersistedDiscussion) -> NSFetchRequest<PersistedLocationContinuous> {
        
        let request: NSFetchRequest<PersistedLocationContinuous> = PersistedLocationContinuous.fetchRequest()

        request.predicate = Predicate.withinDiscussion(discussion)
        
        request.includesSubentities = true
        
        request.sortDescriptors = [NSSortDescriptor(key: PersistedLocation.Predicate.Key.timestamp.rawValue, ascending: true)]
        
        return request
    }
}


// MARK: - PersistedLocationContinuousReceived

@objc(PersistedLocationContinuousReceived)
public final class PersistedLocationContinuousReceived: PersistedLocationContinuous {
    
    private static let entityName = "PersistedLocationContinuousReceived"
    
    // MARK: Relationships

    @NSManaged private var contactDevice: PersistedObvContactDevice? // non-nil for contact sharing location
    @NSManaged public private(set) var receivedMessages: Set<PersistedMessageReceived> // Can be in multiple messages (one per discussion at most)

    // MARK: Initializer
    
    convenience init(locationData: ObvLocationData, count: Int, sharingExpiration: Date?, contactDevice: PersistedObvContactDevice) throws {
        
        guard let context = contactDevice.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        
        try self.init(sentOrReceived: .received,
                      locationData: locationData,
                      count: count,
                      sharingExpiration: sharingExpiration,
                      forEntityName: Self.entityName,
                      within: context)
        
        self.contactDevice = contactDevice
        self.receivedMessages = Set() // Set later
        
    }
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedLocationContinuousReceived> {
        return NSFetchRequest<PersistedLocationContinuousReceived>(entityName: PersistedLocationContinuousReceived.entityName)
    }

    struct Predicate {
        
        enum Key: String {
            // Attributes
            case receivedMessages = "receivedMessages"
        }
        
        static func withinDiscussion(_ discussion: PersistedDiscussion) -> NSPredicate {
            let messagesReceived = Key.receivedMessages.rawValue
            let discussionKey = PersistedMessage.Predicate.Key.discussion.rawValue
            
            return NSPredicate(format: "SUBQUERY(\(messagesReceived), $message, $message.\(discussionKey) == %@).@count > 0", discussion)
        }
    }
    

    // MARK: Deleting a PersistedLocationContinuousReceived
    
    func receivedLocationNoLongerNeeded(by receivedMessage: PersistedMessageReceived) throws {
        self.receivedMessages.remove(receivedMessage)
        try deleteIfReceivedMessagesIsEmpty()
    }
    
    func deleteIfReceivedMessagesIsEmpty() throws {
        if self.receivedMessages.isEmpty {
            try self.deletePersistedLocation()
        }
    }

    // MARK: Making sure the location is not used by more than one message per discussion
    
    public override func willSave() {
        super.willSave()
        
        // We aim to ensure that a given device's continuous location is not displayed more than once within a discussion.
        // To achieve this, we construct a dictionary where the keys are discussions containing at least one message with PersistedLocationContinuousReceived data.
        // The corresponding values for these keys will be all messages from their respective discussions which display this location.
        // Each value should contain no more than one message; therefore, only the most recent message is retained.
        
        let receivedMessagesInDiscussion: [TypeSafeManagedObjectID<PersistedDiscussion>?: [PersistedMessageReceived]] = Dictionary(grouping: self.receivedMessages, by: { message in
            message.discussion?.typedObjectID
        })
        for (_, messages) in receivedMessagesInDiscussion {
            guard messages.count > 1 else { continue }
            let messagesToRemove = messages.sorted(by: \.timestamp).dropLast()
            messagesToRemove.forEach { messageToRemove in
                self.receivedMessages.remove(messageToRemove)
            }
        }
        
        if self.receivedMessages.isEmpty, !self.isDeleted {
            try? self.deletePersistedLocation()
        }

    }
    
}


// MARK: - PersistedLocationContinuousSent

@objc(PersistedLocationContinuousSent)
public final class PersistedLocationContinuousSent: PersistedLocationContinuous {
    
    private static let entityName = "PersistedLocationContinuousSent"

    // MARK: Relationships
    
    @NSManaged public private(set) var ownedDevice: PersistedObvOwnedDevice? // non-nil for own sharing location
    @NSManaged public private(set) var sentMessages: Set<PersistedMessageSent> // Can be in multiple messages (one per discussion at most)

    // MARK: Initializer
    
    convenience init(locationData: ObvLocationData, sharingExpiration: Date?, ownedDevice: PersistedObvOwnedDevice) throws {
        
        guard let context = ownedDevice.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        
        try self.init(sentOrReceived: .sent,
                      locationData: locationData,
                      count: 0,
                      sharingExpiration: sharingExpiration,
                      forEntityName: Self.entityName,
                      within: context)
        
        self.ownedDevice = ownedDevice
        self.sentMessages = Set() // Set later
        
    }
    

    @nonobjc public static func fetchRequest() -> NSFetchRequest<PersistedLocationContinuousSent> {
        return NSFetchRequest<PersistedLocationContinuousSent>(entityName: PersistedLocationContinuousSent.entityName)
    }


    struct Predicate {
        enum Key: String {
            // Attributes
            case sentMessages = "sentMessages"
            // Relationships
            case ownedDevice = "ownedDevice"
        }
        
        static func withinDiscussion(_ discussion: PersistedDiscussion) -> NSPredicate {
            let messagesSent = Key.sentMessages.rawValue
            let discussionKey = PersistedMessage.Predicate.Key.discussion.rawValue
            
            return NSPredicate(format: "SUBQUERY(\(messagesSent), $message, $message.\(discussionKey) == %@).@count > 0", discussion)
        }
        
        static var nonNilOwnedDevice: NSPredicate {
            NSPredicate(withNonNilValueForKey: Key.ownedDevice)
        }

        private static var ownedDeviceIsCurrentDevice: NSPredicate {
            let ownedDeviceRawSecureChannelStatus = [Self.Key.ownedDevice.rawValue, PersistedObvOwnedDevice.Predicate.Key.rawSecureChannelStatus.rawValue].joined(separator: ".")
            return NSPredicate(ownedDeviceRawSecureChannelStatus, EqualToInt: PersistedObvOwnedDevice.SecureChannelStatusRaw.currentDevice.rawValue)
        }
        
        private static func forOwnedCryptoId(ownedCryptoId: ObvCryptoId) -> NSPredicate {
            let ownedDeviceRawOwnedIdentityIdentity = [Self.Key.ownedDevice.rawValue, PersistedObvOwnedDevice.Predicate.Key.rawOwnedIdentityIdentity.rawValue].joined(separator: ".")
            return NSPredicate(ownedDeviceRawOwnedIdentityIdentity, EqualToData: ownedCryptoId.getIdentity())
        }
        
        static func forCurrentOwnedDeviceOfOwnedIdentity(ownedCryptoId: ObvCryptoId) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.nonNilOwnedDevice,
                Self.ownedDeviceIsCurrentDevice,
                Self.forOwnedCryptoId(ownedCryptoId: ownedCryptoId),
            ])
        }

        static func withObjectID(_ objectID: NSManagedObjectID) -> NSPredicate {
            NSPredicate(withObjectID: objectID)
        }
    }
    
    
    public static func getFetchRequestForPersistedLocationContinuousSentFromCurrentOwnedDevice(ownedCryptoId: ObvCryptoId) -> FetchRequestControllerModel<PersistedLocationContinuousSent> {
        let fetchRequest: NSFetchRequest<PersistedLocationContinuousSent> = PersistedLocationContinuousSent.fetchRequest()
        fetchRequest.predicate = Predicate.forCurrentOwnedDeviceOfOwnedIdentity(ownedCryptoId: ownedCryptoId)
        fetchRequest.propertiesToFetch = []
        fetchRequest.relationshipKeyPathsForPrefetching = []
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(key: PredicateForPersistedLocation.Key.timestamp.rawValue, ascending: false),
        ]
        fetchRequest.fetchLimit = 1
        return FetchRequestControllerModel(fetchRequest: fetchRequest, sectionNameKeyPath: nil)
    }


    public static func getPersistedLocationContinuousSent(objectID: TypeSafeManagedObjectID<PersistedLocationContinuousSent>, within context: NSManagedObjectContext) throws -> PersistedLocationContinuousSent? {
        let request: NSFetchRequest<PersistedLocationContinuousSent> = PersistedLocationContinuousSent.fetchRequest()
        request.predicate = PersistedLocationContinuousSent.Predicate.withObjectID(objectID.objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }


    func updatePersistedLocationContinuousSent(with locationData: ObvLocationData) throws -> (unprocessedMessagesToSend: [MessageSentPermanentID], updatedSentMessages: Set<PersistedMessageSent>) {
        
        let newCount = self.count + 1
        try super.updateContentForContinuousLocation(with: locationData, count: newCount)
        
        self.sentMessages.forEach { try? $0.setBodyWithLocation() }
        
        let unprocessedMessagesToSend: [MessageSentPermanentID] = try self.sentMessages.filter({ $0.status == .unprocessed }).map({ try $0.objectPermanentID })
        let processedMessagesToEdit: [PersistedMessageSent] = self.sentMessages.filter({ $0.status != .unprocessed })
        
        return (unprocessedMessagesToSend, Set(processedMessagesToEdit))
        
    }
    
    // MARK: Deleting a PersistedLocationContinuousSent
    
    func sentLocationNoLongerNeeded(by sentMessage: PersistedMessageSent) throws {
        self.sentMessages.remove(sentMessage)
        // This location is deleted, if necessary, in the willSave method. We do not delete it here, as we might be adding
        // a new sent message to this location.
    }
    
    
    func sentLocationNoLongerNeeded(by discussion: PersistedDiscussion) throws -> Set<PersistedMessageSent> {
        let messages = self.sentMessages.filter({ $0.discussion == discussion })
        for message in messages {
            try sentLocationNoLongerNeeded(by: message)
        }
        return messages
    }
    
    
    func sentLocationNoLongerNeededByAnyDiscussion() throws -> Set<PersistedMessageSent> {
        let sentMessagesToReturn = self.sentMessages
        for sentMessage in sentMessages {
            try sentLocationNoLongerNeeded(by: sentMessage)
        }
        // The location is deleted in the will save method
        return sentMessagesToReturn
    }
    
    
    public override func willSave() {
        super.willSave()
        
        // If this location is no longer needed, we delete it
        if self.sentMessages.isEmpty, !self.isDeleted {
            try? self.deletePersistedLocation()
        }
        
    }
    
}


// MARK: - PersistedLocationOneShot

@objc(PersistedLocationOneShot)
public class PersistedLocationOneShot: PersistedLocation {
    
    fileprivate convenience init(sentOrReceived: SentOrReceived, locationData: ObvLocationData, forEntityName: String, within context: NSManagedObjectContext) throws {
        
        try self.init(continuousOrOneShot: .oneShot,
                      sentOrReceived: sentOrReceived,
                      locationData: locationData,
                      count: nil,
                      sharingExpiration: nil,
                      forEntityName: forEntityName,
                      within: context)
        
    }

}


// MARK: - PersistedLocationOneShotReceived

@objc(PersistedLocationOneShotReceived)
public final class PersistedLocationOneShotReceived: PersistedLocationOneShot {
    
    private static let entityName = "PersistedLocationOneShotReceived"

    // MARK: Relationships
    
    @NSManaged private var receivedMessage: PersistedMessageReceived? // Expected to be non-nil

    // MARK: Initializer
    
    convenience init(locationData: ObvLocationData, within context: NSManagedObjectContext) throws {
        
        try self.init(sentOrReceived: .received,
                      locationData: locationData,
                      forEntityName: Self.entityName,
                      within: context)
        
        self.receivedMessage = nil // Set later
        
    }
    
    
    func deleteIfAssociatedReceivedMessageIsNil() throws {
        if receivedMessage == nil {
            try self.deletePersistedLocation()
        }
    }

}


// MARK: - PersistedLocationOneShotSent

@objc(PersistedLocationOneShotSent)
public final class PersistedLocationOneShotSent: PersistedLocationOneShot {
    
    private static let entityName = "PersistedLocationOneShotSent"

    // MARK: Relationships
    
    @NSManaged private var sentMessage: PersistedMessageSent? // Expected to be non-nil
    
    // MARK: Initializer
    
    convenience init(locationData: ObvLocationData, within context: NSManagedObjectContext) throws {

        try self.init(sentOrReceived: .sent,
                      locationData: locationData,
                      forEntityName: Self.entityName,
                      within: context)
        
        self.sentMessage = nil // Set later
        
    }

    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedLocationOneShotSent> {
        return NSFetchRequest<PersistedLocationOneShotSent>(entityName: PersistedLocationOneShotSent.entityName)
    }

    struct Predicate {
        static func withObjectID(_ objectID: NSManagedObjectID) -> NSPredicate {
            NSPredicate(withObjectID: objectID)
        }
    }
    
    static func getPersistedLocationOneShotSent(objectID: TypeSafeManagedObjectID<PersistedLocationOneShotSent>, within context: NSManagedObjectContext) throws -> PersistedLocationOneShotSent? {
        let request: NSFetchRequest<PersistedLocationOneShotSent> = PersistedLocationOneShotSent.fetchRequest()
        request.predicate = PersistedLocationOneShotSent.Predicate.withObjectID(objectID.objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

}



// MARK: - Helpers

public enum ReceivedLocation {
    case oneShot(location: PersistedLocationOneShotReceived)
    case continuous(location: PersistedLocationContinuousReceived, toStop: Bool)
}


public enum SentLocation {
    case oneShot(location: TypeSafeManagedObjectID<PersistedLocationOneShotSent>)
    case continuous(location: TypeSafeManagedObjectID<PersistedLocationContinuousSent>, toStop: ObvLocation.EndSharingDestination?)
}
