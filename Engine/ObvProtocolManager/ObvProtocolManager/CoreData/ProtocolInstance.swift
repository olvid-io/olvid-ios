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
import OlvidUtils
import ObvEncoder
import ObvTypes
import ObvCrypto

@objc(ProtocolInstance)
class ProtocolInstance: NSManagedObject, ObvManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "ProtocolInstance"
    static let uidKey = "uid"
    private static let cryptoProtocolRawIdKey = "cryptoProtocolRawId"
    static let ownedCryptoIdentityKey = "ownedCryptoIdentity"
    
    // MARK: Attributes
    
    private(set) var cryptoProtocolId: CryptoProtocolId {
        get {
            let rawValue = kvoSafePrimitiveValue(forKey: ProtocolInstance.cryptoProtocolRawIdKey) as! Int
            let cryptoProtocolId = CryptoProtocolId(rawValue: rawValue)!
            return cryptoProtocolId
        }
        set {
            kvoSafeSetPrimitiveValue(newValue.rawValue, forKey: ProtocolInstance.cryptoProtocolRawIdKey)
        }
    }
    
    @NSManaged private(set) var currentStateRawId: Int
    @NSManaged private(set) var encodedCurrentState: ObvEncoded
    @NSManaged private(set) var ownedCryptoIdentity: ObvCryptoIdentity // Part of primary key (with `uid`)
    @NSManaged private(set) var uid: UID // Part of primary key (with `ownedCryptoIdentity`)
    
    // MARK: Other variables
    
    weak var delegateManager: ObvProtocolDelegateManager?
    var obvContext: ObvContext?
    
    // MARK: - Initializer
    
    convenience init?(cryptoProtocolId: CryptoProtocolId, protocolInstanceUid: UID, ownedCryptoIdentity: ObvCryptoIdentity, initialState: ConcreteProtocolState, delegateManager: ObvProtocolDelegateManager, within obvContext: ObvContext) {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolInstance.entityName)
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            return nil
        }
        
        // Check that no entry with the same `uid` and `contactIdentity` exists
        do {
            guard try !ProtocolInstance.exists(uid: protocolInstanceUid, ownedCryptoIdentity: ownedCryptoIdentity, within: obvContext) else {
                os_log("Cannot create a protocol instance with the same uid and owned identity twice", log: log, type: .error)
                return nil
            }
        } catch let error {
            os_log("%@", log: log, type: .fault, error.localizedDescription)
            return nil
        }
        let entityDescription = NSEntityDescription.entity(forEntityName: ProtocolInstance.entityName, in: obvContext)!
        
        // We check that the identity passed is indeed "owned"
        do {
            let identityIsOwned = try identityDelegate.isOwned(ownedCryptoIdentity, within: obvContext)
            guard identityIsOwned else { return nil }
        } catch {
            return nil
        }
        
        guard let encodedCurrentState = try? initialState.obvEncode() else { assertionFailure(); return nil }
        
        self.init(entity: entityDescription, insertInto: obvContext)
        self.cryptoProtocolId = cryptoProtocolId
        self.currentStateRawId = initialState.rawId
        self.encodedCurrentState = encodedCurrentState
        self.ownedCryptoIdentity = ownedCryptoIdentity
        self.uid = protocolInstanceUid
        self.delegateManager = delegateManager
    }
    
}


// MARK: - Updating the current state

extension ProtocolInstance {
    
    func updateCurrentState(with state: ConcreteProtocolState) throws {
        self.encodedCurrentState = try state.obvEncode()
        self.currentStateRawId = state.rawId
    }
}


// MARK: - Convenience DB getters
extension ProtocolInstance {

    // MARK: Fetch request
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<ProtocolInstance> {
        return NSFetchRequest<ProtocolInstance>(entityName: ProtocolInstance.entityName)
    }

        
    static func get(cryptoProtocolId: CryptoProtocolId, uid: UID, ownedIdentity: ObvCryptoIdentity, delegateManager: ObvProtocolDelegateManager, within obvContext: ObvContext) -> ProtocolInstance? {
        let request: NSFetchRequest<ProtocolInstance> = ProtocolInstance.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %d AND %K == %@ AND %K == %@",
                                        cryptoProtocolRawIdKey, cryptoProtocolId.rawValue,
                                        uidKey, uid,
                                        ownedCryptoIdentityKey, ownedIdentity)
        let item = (try? obvContext.fetch(request))?.first
        item?.delegateManager = delegateManager
        return item
    }
    

    static func getAll(delegateManager: ObvProtocolDelegateManager, within obvContext: ObvContext) -> [ProtocolInstance]? {
        let request: NSFetchRequest<ProtocolInstance> = ProtocolInstance.fetchRequest()
        let items = try? obvContext.fetch(request)
        return items?.map { $0.delegateManager = delegateManager; return $0 }

    }
    
    static func delete(uid: UID, ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        // We do not execute a batch delete since this method does not call the willSave/didSave methods, which are required.
        let request: NSFetchRequest<ProtocolInstance> = ProtocolInstance.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                        uidKey, uid,
                                        ownedCryptoIdentityKey, ownedCryptoIdentity)
        guard let item = (try? obvContext.fetch(request))?.first else { return }
        obvContext.delete(item)
    }
    
    static func count(within obvContext: ObvContext) -> Int {
        let request = NSFetchRequest<ProtocolInstance>(entityName: ProtocolInstance.entityName)
        guard let items = try? obvContext.fetch(request) else {
            return 0
        }
        return items.count
    }
    
    static func exists(uid: UID, ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool {
        let request: NSFetchRequest<ProtocolInstance> = ProtocolInstance.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                        uidKey, uid,
                                        ownedCryptoIdentityKey, ownedCryptoIdentity)
        return try obvContext.count(for: request) != 0

    }
    
    static func exists(cryptoProtocolId: CryptoProtocolId, uid: UID, ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool {
        let request: NSFetchRequest<ProtocolInstance> = ProtocolInstance.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %d AND %K == %@ AND %K == %@",
                                        cryptoProtocolRawIdKey, cryptoProtocolId.rawValue,
                                        uidKey, uid,
                                        ownedCryptoIdentityKey, ownedIdentity)
        return try obvContext.count(for: request) != 0
    }

}
