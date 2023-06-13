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
import ObvTypes
import ObvEncoder
import ObvCrypto
import ObvMetaManager
import OlvidUtils


@objc(ServerPushNotification)
final class ServerPushNotification: NSManagedObject, ObvErrorMaker {
    
    // MARK: Internal constants
    
    private static let entityName = "ServerPushNotification"
    static let errorDomain = "ServerPushNotification"

    enum ServerRegistrationStatus {
        case toRegister
        case registering(urlSessionTaskIdentifier: Int)
        case registered
        
        public enum ByteId: UInt8 {
            case toRegister = 0
            case registering = 1
            case registered = 2
        }

        var byteId: ByteId {
            switch self {
            case .toRegister: return .toRegister
            case .registering: return .registering
            case .registered: return .registered
            }
        }
        
    }
    
    // MARK: Attributes
    
    @NSManaged private var creationDate: Date
    @NSManaged private var kickOtherDevices: Bool // Part of ObvPushNotificationParameters
    @NSManaged private var pushToken: Data? // Non nil for remote push notification type, always nil for the registerDeviceUid type.
    @NSManaged private var rawCurrentDeviceUID: Data
    @NSManaged private var rawKeycloakPushTopics: String?
    @NSManaged private var rawMaskingUID: Data? // Non nil for remote push notification type, always nil for the registerDeviceUid type.
    @NSManaged private var rawOwnedCryptoId: Data
    @NSManaged private var rawPushNotificationByteId: Int // One byte, see ObvPushNotificationType
    @NSManaged private var rawServerRegistrationStatus: Int
    @NSManaged private var rawURLSessionTaskIdentifier: Int // Only makes sense when the ServerRegistrationStatus is "registering". It is set to -1 otherwise.
    @NSManaged private var useMultiDevice: Bool // Part of ObvPushNotificationParameters
    @NSManaged private var voipToken: Data? // Non nil for remote push notification type, always nil for the registerDeviceUid type.
    

    var pushNotification: ObvPushNotificationType {
        get throws {
            guard let ownedCryptoId = ObvCryptoIdentity(from: rawOwnedCryptoId) else {
                assertionFailure()
                throw Self.makeError(message: "Unexpected rawOwnedCryptoId")
            }
            guard let currentDeviceUID = UID(uid: rawCurrentDeviceUID) else {
                assertionFailure()
                throw Self.makeError(message: "Unexpected rawCurrentDeviceUID")
            }
            guard let pushNotificationByteId = ObvPushNotificationType.ByteId(rawValue: UInt8(rawPushNotificationByteId)) else {
                assertionFailure()
                throw Self.makeError(message: "Unexpected rawPushNotificationByteId")
            }
            switch pushNotificationByteId {
            case .remote:
                guard let pushToken, let rawMaskingUID, let maskingUID = UID(uid: rawMaskingUID) else {
                    assertionFailure()
                    throw Self.makeError(message: "Could not reconstruct remote push notification")
                }
                let parameters = ObvPushNotificationParameters(kickOtherDevices: kickOtherDevices, useMultiDevice: useMultiDevice, keycloakPushTopics: keycloakPushTopics)
                return .remote(ownedCryptoId: ownedCryptoId, currentDeviceUID: currentDeviceUID, pushToken: pushToken, voipToken: voipToken, maskingUID: maskingUID, parameters: parameters)
            case .registerDeviceUid:
                let parameters = ObvPushNotificationParameters(kickOtherDevices: kickOtherDevices, useMultiDevice: useMultiDevice, keycloakPushTopics: keycloakPushTopics)
                return .registerDeviceUid(ownedCryptoId: ownedCryptoId, currentDeviceUID: currentDeviceUID, parameters: parameters)
            }
        }
    }
    
    private var keycloakPushTopics: Set<String> {
        get {
            guard let rawKeycloakPushTopics else { return Set<String>() }
            return Set(rawKeycloakPushTopics.split(separator: "|").map({ String($0) }))
        }
        set {
            let newRawKeycloakPushTopics = newValue.sorted().joined(separator: "|")
            if self.rawKeycloakPushTopics != newRawKeycloakPushTopics {
                self.rawKeycloakPushTopics = newRawKeycloakPushTopics
            }
        }
    }
    
    var serverRegistrationStatus: ServerRegistrationStatus {
        get throws {
            guard let byteId = ServerRegistrationStatus.ByteId(rawValue: UInt8(rawServerRegistrationStatus)) else {
                assertionFailure()
                throw Self.makeError(message: "Unexpected raw ServerRegistrationStatus.ByteId: \(rawServerRegistrationStatus)")
            }
            switch byteId {
            case .toRegister: return .toRegister
            case .registering: return .registering(urlSessionTaskIdentifier: rawURLSessionTaskIdentifier)
            case .registered: return .registered
            }
        }
    }
    
    // MARK: - Initializer
    
    private convenience init(pushNotificationType: ObvPushNotificationType, within context: NSManagedObjectContext) {
        
        let entityDescription = NSEntityDescription.entity(forEntityName: ServerPushNotification.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        self.creationDate = Date()
        self.rawOwnedCryptoId = pushNotificationType.ownedCryptoId.getIdentity()
        self.rawPushNotificationByteId = Int(pushNotificationType.byteId.rawValue)
        self.rawServerRegistrationStatus = Int(ServerRegistrationStatus.toRegister.byteId.rawValue)
        self.rawCurrentDeviceUID = pushNotificationType.currentDeviceUID.raw
        self.rawURLSessionTaskIdentifier = -1
        
        switch pushNotificationType {
        case .remote(ownedCryptoId: _, currentDeviceUID: _, pushToken: let pushToken, voipToken: let voipToken, maskingUID: let maskingUID, parameters: let parameters):
            self.kickOtherDevices = parameters.kickOtherDevices
            self.keycloakPushTopics = parameters.keycloakPushTopics
            self.pushToken = pushToken
            self.rawMaskingUID = maskingUID.raw
            self.useMultiDevice = parameters.useMultiDevice
            self.voipToken = voipToken
        case .registerDeviceUid(ownedCryptoId: _, currentDeviceUID: _, parameters: let parameters):
            self.kickOtherDevices = parameters.kickOtherDevices
            self.keycloakPushTopics = parameters.keycloakPushTopics
            self.pushToken = nil
            self.rawMaskingUID = nil
            self.useMultiDevice = parameters.useMultiDevice
            self.voipToken = nil
        }
        
    }
    
    
    static func createOrThrowIfOneAlreadyExists(pushNotificationType: ObvPushNotificationType, within context: NSManagedObjectContext) throws -> Self {
        guard try ServerPushNotification.getServerPushNotificationOfType(pushNotificationType.byteId, ownedCryptoId: pushNotificationType.ownedCryptoId, within: context) == nil else {
            assertionFailure()
            throw Self.makeError(message: "An ServerPushNotification of type \(pushNotificationType.byteId.rawValue) already exists")
        }
        return Self.init(pushNotificationType: pushNotificationType, within: context)
    }

    
    func delete() throws {
        guard let managedObjectContext else {
            assertionFailure()
            throw Self.makeError(message: "Could not find context")
        }
        managedObjectContext.delete(self)
    }
    
    
    func switchToServerRegistrationStatus(_ newServerRegistrationStatus: ServerRegistrationStatus) throws {
        switch newServerRegistrationStatus {
        case .toRegister:
            if self.rawServerRegistrationStatus != ServerRegistrationStatus.ByteId.toRegister.rawValue {
                self.rawServerRegistrationStatus = Int(ServerRegistrationStatus.ByteId.toRegister.rawValue)
            }
            if self.rawURLSessionTaskIdentifier != -1 {
                self.rawURLSessionTaskIdentifier = -1
            }
        case .registering(urlSessionTaskIdentifier: let urlSessionTaskIdentifier):
            if self.rawServerRegistrationStatus != ServerRegistrationStatus.ByteId.registering.rawValue {
                self.rawServerRegistrationStatus = Int(ServerRegistrationStatus.ByteId.registering.rawValue)
            }
            if self.rawURLSessionTaskIdentifier != urlSessionTaskIdentifier {
                self.rawURLSessionTaskIdentifier = urlSessionTaskIdentifier
            }
        case .registered:
            if self.rawServerRegistrationStatus != ServerRegistrationStatus.ByteId.registered.rawValue {
                self.rawServerRegistrationStatus = Int(ServerRegistrationStatus.ByteId.registered.rawValue)
            }
            if self.rawURLSessionTaskIdentifier != -1 {
                self.rawURLSessionTaskIdentifier = -1
            }
        }
    }
    
    func setKickOtherDevices(to newValue: Bool) {
        if self.kickOtherDevices != newValue {
            self.kickOtherDevices = newValue
        }
    }
}


// MARK: - Convenience DB getters

extension ServerPushNotification {
    
    struct Predicate {
        enum Key: String {
            case creationDate = "creationDate"
            case kickOtherDevices = "kickOtherDevices"
            case pushToken = "pushToken"
            case rawCurrentDeviceUID = "rawCurrentDeviceUID"
            case rawKeycloakPushTopics = "rawKeycloakPushTopics"
            case rawMaskingUID = "rawMaskingUID"
            case rawOwnedCryptoId = "rawOwnedCryptoId"
            case rawPushNotificationByteId = "rawPushNotificationByteId"
            case rawServerRegistrationStatus = "rawServerRegistrationStatus"
            case rawURLSessionTaskIdentifier = "rawURLSessionTaskIdentifier"
            case useMultiDevice = "useMultiDevice"
            case voipToken = "voipToken"
        }
        static func withOwnedCryptoId(_ ownedCryptoId: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(Key.rawOwnedCryptoId, EqualToData: ownedCryptoId.getIdentity())
        }
        static func withTypeByteId(_ typeByteId: ObvPushNotificationType.ByteId) -> NSPredicate {
            NSPredicate(Key.rawPushNotificationByteId, EqualToInt: Int(typeByteId.rawValue))
        }
        static func withServerRegistrationStatus(_ serverRegistrationStatus: ServerRegistrationStatus.ByteId) -> NSPredicate {
            NSPredicate(Key.rawServerRegistrationStatus, EqualToInt: Int(serverRegistrationStatus.rawValue))
        }
        static func withServerRegistrationStatusDistinctFrom(_ serverRegistrationStatus: ServerRegistrationStatus.ByteId) -> NSPredicate {
            NSPredicate(Key.rawServerRegistrationStatus, DistinctFromInt: Int(serverRegistrationStatus.rawValue))
        }
        static func withURLSessionTaskIdentifier(urlSessionTaskIdentifier: Int) -> NSPredicate {
            NSPredicate(Key.rawURLSessionTaskIdentifier, EqualToInt: urlSessionTaskIdentifier)
        }
    }
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<ServerPushNotification> {
        return NSFetchRequest<ServerPushNotification>(entityName: ServerPushNotification.entityName)
    }
    
    
    static func getServerPushNotificationOfType(_ typeByteId: ObvPushNotificationType.ByteId, ownedCryptoId: ObvCryptoIdentity, within context: NSManagedObjectContext) throws -> ServerPushNotification? {
        let request: NSFetchRequest<ServerPushNotification> = ServerPushNotification.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedCryptoId(ownedCryptoId),
            Predicate.withTypeByteId(typeByteId),
        ])
        request.fetchLimit = 1
        let item = try context.fetch(request).first
        return item
    }
    
    
    static func getRegisteringAndCorrespondingToURLSessionTaskIdentifier(_ urlSessionTaskIdentifier: Int, within context: NSManagedObjectContext) throws -> ServerPushNotification? {
        let request: NSFetchRequest<ServerPushNotification> = ServerPushNotification.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withServerRegistrationStatus(.registering),
            Predicate.withURLSessionTaskIdentifier(urlSessionTaskIdentifier: urlSessionTaskIdentifier),
        ])
        request.fetchBatchSize = 100
        let items = try context.fetch(request)
        assert(items.count < 2, "More than one registering item found for that url session task identifier, not expected")
        return items.first
    }
    
    
    static func deleteAllServerPushNotificationForOwnedCryptoIdentity(_ ownedCryptoId: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = ServerPushNotification.fetchRequest()
        request.predicate = Predicate.withOwnedCryptoId(ownedCryptoId)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        deleteRequest.resultType = .resultTypeStatusOnly
        _ = try obvContext.execute(deleteRequest)
    }
    
    
//    static func switchServerRegistrationStatusToToRegisterForAllServerPushNotification(within context: NSManagedObjectContext) throws {
//        let request: NSFetchRequest<ServerPushNotification> = ServerPushNotification.fetchRequest()
//        request.fetchBatchSize = 100
//        let items = try context.fetch(request)
//        try items.forEach { item in
//            try item.switchToServerRegistrationStatus(.toRegister)
//        }
//    }
    
    static func getAllServerPushNotification(within context: NSManagedObjectContext) throws -> Set<ServerPushNotification> {
        let request: NSFetchRequest<ServerPushNotification> = ServerPushNotification.fetchRequest()
        request.fetchBatchSize = 100
        let items = try context.fetch(request)
        return Set(items)
    }
    
}
