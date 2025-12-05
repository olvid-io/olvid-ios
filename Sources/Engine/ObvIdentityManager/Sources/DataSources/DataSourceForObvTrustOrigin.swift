/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvTypes
import OlvidUtils


final class DataSourceForObvTrustOrigin {
    
    let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        context.automaticallyMergesChangesFromParent = true
        self.context = context
    }

    private var trustOriginStreamManagerForStreamUUID = [UUID: ObvTrustOriginStreamManager]()
    
}


extension DataSourceForObvTrustOrigin {
    
    func getAsyncStreamOfObvTrustOrigin(contactIdentifier: ObvContactIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<[ObvTrustOrigin]>) {
        let manager = ObvTrustOriginStreamManager(contactIdentifier: contactIdentifier, context: context)
        trustOriginStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }


    public func finishAsyncStreamOfObvTrustOrigin(streamUUID: UUID) {
        guard let manager = trustOriginStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
}


extension DataSourceForObvTrustOrigin {
    
    private final class ObvTrustOriginStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<[ObvTrustOrigin], PersistedTrustOrigin>, @unchecked Sendable {
        
        private let contactIdentifier: ObvContactIdentifier
        private let context: NSManagedObjectContext
        
        init(contactIdentifier: ObvContactIdentifier, context: NSManagedObjectContext) {
            context.automaticallyMergesChangesFromParent = true
            self.context = context
            self.contactIdentifier = contactIdentifier
            let frc = PersistedTrustOrigin.getFetchedResultsController(contactIdentifier: contactIdentifier, within: context)
            super.init(frc: frc)
        }

        override func createModel(fetchedObjects: [PersistedTrustOrigin]) throws -> [ObvTrustOrigin] {
            let trustOrigins: [ObvTrustOrigin] = fetchedObjects.compactMap { trustOrigin in
                do {
                    let obvTrustOrigin = try trustOrigin.obvTrustOrigin
                    return obvTrustOrigin
                } catch {
                    assertionFailure(error.localizedDescription)
                    return nil
                }
            }
            return trustOrigins
        }
        
    }
    
}
