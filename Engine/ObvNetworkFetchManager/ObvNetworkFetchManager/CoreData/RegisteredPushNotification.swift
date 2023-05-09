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

@objc(RegisteredPushNotification)
final class RegisteredPushNotification: NSManagedObject, ObvManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "RegisteredPushNotification"
    private static let pushNotificationTypeKey = "pushNotificationType"
    private static let cryptoIdentityKey = "cryptoIdentity"
    private static let creationDateKey = "creationDate"
    private static let pollingIdentifierKey = "pollingIdentifier"
    
    // MARK: Attributes
    
    @NSManaged private(set) var creationDate: Date
    @NSManaged private(set) var cryptoIdentity: ObvCryptoIdentity
    @NSManaged private(set) var deviceUid: UID
    @NSManaged private(set) var pollingIdentifier: UUID? // Always (re)set by the operation when processing this push notification
    
    private(set) var pushNotificationType: ObvPushNotificationType {
        get {
            let encodedAsData = kvoSafePrimitiveValue(forKey: RegisteredPushNotification.pushNotificationTypeKey) as! Data
            let encoded = ObvEncoded(withRawData: encodedAsData)!
            let pushNotificationType = ObvPushNotificationType.decode(encoded)!
            return pushNotificationType
        }
        set {
            kvoSafeSetPrimitiveValue(newValue.obvEncode().rawData, forKey: RegisteredPushNotification.pushNotificationTypeKey)
        }
    }
    
    // MARK: Other variables
    
    var obvContext: ObvContext?
    weak var delegateManager: ObvNetworkFetchDelegateManager?

    // MARK: - Initializer
    
    convenience init(identity: ObvCryptoIdentity, deviceUid: UID, pushNotificationType: ObvPushNotificationType, delegateManager: ObvNetworkFetchDelegateManager, within obvContext: ObvContext) {
        
        let entityDescription = NSEntityDescription.entity(forEntityName: RegisteredPushNotification.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        
        self.cryptoIdentity = identity
        self.deviceUid = deviceUid
        self.pushNotificationType = pushNotificationType
        switch pushNotificationType {
        case .polling:
            pollingIdentifier = UUID()
        default:
            pollingIdentifier = nil
        }
        self.delegateManager = delegateManager
        self.creationDate = Date()
        
    }

}


// MARK: - Convenience DB getters

extension RegisteredPushNotification {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<RegisteredPushNotification> {
        return NSFetchRequest<RegisteredPushNotification>(entityName: RegisteredPushNotification.entityName)
    }
    
    static func getAllSortedByCreationDate(for cryptoIdentity: ObvCryptoIdentity, delegateManager: ObvNetworkFetchDelegateManager, within obvContext: ObvContext) -> [RegisteredPushNotification]? {
        let request: NSFetchRequest<RegisteredPushNotification> = RegisteredPushNotification.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", cryptoIdentityKey, cryptoIdentity)
        request.sortDescriptors = [NSSortDescriptor(key: RegisteredPushNotification.creationDateKey, ascending: true)]
        let items = try? obvContext.fetch(request)
        return items?.map { $0.delegateManager = delegateManager; return $0 }
    }
    
    static func getAll(within obvContext: ObvContext, delegateManager: ObvNetworkFetchDelegateManager) -> [RegisteredPushNotification]? {
        let request: NSFetchRequest<RegisteredPushNotification> = RegisteredPushNotification.fetchRequest()
        let items = try? obvContext.fetch(request)
        return items?.map { $0.delegateManager = delegateManager; return $0 }
    }

    static func getPollingTimeInterval(for cryptoIdentity: ObvCryptoIdentity, pollingIdentifier: UUID, within obvContext: ObvContext) -> TimeInterval? {
        let request: NSFetchRequest<RegisteredPushNotification> = RegisteredPushNotification.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                        cryptoIdentityKey, cryptoIdentity,
                                        pollingIdentifierKey, pollingIdentifier as CVarArg)
        guard let item = (try? obvContext.fetch(request))?.first else { return nil }
        switch item.pushNotificationType {
        case .polling(pollingInterval: let timeIntervall):
            return timeIntervall
        default:
            return nil
        }
    }
    
    static func deleteAll(within obvContext: ObvContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = RegisteredPushNotification.fetchRequest()
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        deleteRequest.resultType = .resultTypeStatusOnly
        _ = try obvContext.execute(deleteRequest)
    }
    
    static func deleteAllRegisteredPushNotificationForOwnedCryptoIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = RegisteredPushNotification.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", cryptoIdentityKey, ownedCryptoIdentity)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        deleteRequest.resultType = .resultTypeStatusOnly
        _ = try obvContext.execute(deleteRequest)
    }
    
    static func countAll(within obvContext: ObvContext) throws -> Int {
        let request: NSFetchRequest<NSFetchRequestResult> = RegisteredPushNotification.fetchRequest()
        return try obvContext.count(for: request)
    }
    
}


// MARK: - Managing notifications

extension RegisteredPushNotification {
    
    override func didSave() {
        super.didSave()
        
        guard let delegateManager = delegateManager else {
            let log = OSLog.init(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: "RegisteredPushNotification")
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }

        if isInserted, let flowId = self.obvContext?.flowId {
            try? delegateManager.networkFetchFlowDelegate.newRegisteredPushNotificationToProcess(for: cryptoIdentity, withDeviceUid: deviceUid, flowId: flowId)
        }
        
    }
}
