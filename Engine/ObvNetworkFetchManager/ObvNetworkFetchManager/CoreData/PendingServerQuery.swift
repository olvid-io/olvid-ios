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
import os.log
import CoreData
import ObvMetaManager
import ObvEncoder
import ObvCrypto
import ObvTypes
import OlvidUtils

@objc(PendingServerQuery)
class PendingServerQuery: NSManagedObject, ObvManagedObject {

    // MARK: Internal constants

    private static let entityName = "PendingServerQuery"
    private static let encodedElementsKey = "encodedElements"
    private static let encodedQueryTypeKey = "encodedQueryType"
    private static let encodedResponseTypeKey = "encodedResponseType"
    private static let ownedIdentityKey = "ownedIdentity"

    // MARK: Attributes

    private(set) var encodedElements: ObvEncoded {
        get {
            let rawData = kvoSafePrimitiveValue(forKey: PendingServerQuery.encodedElementsKey) as! Data
            return ObvEncoded(withRawData: rawData)!
        }
        set {
            kvoSafeSetPrimitiveValue(newValue.rawData, forKey: PendingServerQuery.encodedElementsKey)
        }
    }
    private(set) var queryType: ServerQuery.QueryType {
        get {
            let rawData = kvoSafePrimitiveValue(forKey: PendingServerQuery.encodedQueryTypeKey) as! Data
            let encodedQueryType = ObvEncoded(withRawData: rawData)!
            return ServerQuery.QueryType(encodedQueryType)!
        }
        set {
            kvoSafeSetPrimitiveValue(newValue.encode().rawData, forKey: PendingServerQuery.encodedQueryTypeKey)
        }
    }
    var responseType: ServerResponse.ResponseType? {
        get {
            let rawData = kvoSafePrimitiveValue(forKey: PendingServerQuery.encodedResponseTypeKey) as! Data?
            if let rawData = rawData {
                let encodedResponseType = ObvEncoded(withRawData: rawData)!
                return ServerResponse.ResponseType(encodedResponseType)
            } else {
                return nil
            }
        }
        set {
            if let newValue = newValue {
                kvoSafeSetPrimitiveValue(newValue.encode().rawData, forKey: PendingServerQuery.encodedResponseTypeKey)
            }
        }
    }
    @NSManaged private(set) var ownedIdentity: ObvCryptoIdentity

    // MARK: Other variables

    weak var delegateManager: ObvNetworkFetchDelegateManager?
    var obvContext: ObvContext?

    // MARK: - Initializer

    convenience init(serverQuery: ServerQuery, delegateManager: ObvNetworkFetchDelegateManager, within obvContext: ObvContext) {

        let entityDescription = NSEntityDescription.entity(forEntityName: PendingServerQuery.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)

        self.encodedElements = serverQuery.encodedElements
        self.queryType = serverQuery.queryType
        self.ownedIdentity = serverQuery.ownedIdentity
        self.delegateManager = delegateManager

    }

}


// MARK: - Other functions

extension PendingServerQuery {

    func delete(flowId: FlowIdentifier) {
        guard let obvContext = self.obvContext else {
            assertionFailure("ObvContext is nil in PendingServerQuery")
            return
        }
        obvContext.delete(self)
    }

}

// MARK: - Convenience DB getters

extension PendingServerQuery {

    @nonobjc class func fetchRequest() -> NSFetchRequest<PendingServerQuery> {
        return NSFetchRequest<PendingServerQuery>(entityName: PendingServerQuery.entityName)
    }

    static func get(objectId: NSManagedObjectID, delegateManager: ObvNetworkFetchDelegateManager, within obvContext: ObvContext) throws -> PendingServerQuery {
        guard let serverQuery = try obvContext.existingObject(with: objectId) as? PendingServerQuery else { throw NSError() }
        serverQuery.delegateManager = delegateManager
        return serverQuery
    }

    static func getAllServerQuery(for identity: ObvCryptoIdentity, delegateManager: ObvNetworkFetchDelegateManager, within obvContext: ObvContext) throws -> [PendingServerQuery] {
        let request: NSFetchRequest<PendingServerQuery> = PendingServerQuery.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", PendingServerQuery.ownedIdentityKey,
                    identity)
        return try obvContext.fetch(request)
    }

}

// MARK: - Managing Change Events

extension PendingServerQuery {

    override func didSave() {
        super.didSave()

        guard let delegateManager = delegateManager else {
            let log = OSLog.init(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: PendingServerQuery.entityName)
            os_log("The delegate manager is not set", log: log, type: .fault)
            return
        }

        if isInserted, let flowId = self.obvContext?.flowId {
            delegateManager.networkFetchFlowDelegate.newPendingServerQueryToProcessWithObjectId(self.objectID, flowId: flowId)
        } else if isDeleted, let flowId = self.obvContext?.flowId {
            delegateManager.networkFetchFlowDelegate.pendingServerQueryWasDeletedFromDatabase(objectId: self.objectID, flowId: flowId)
        }
    }

}
