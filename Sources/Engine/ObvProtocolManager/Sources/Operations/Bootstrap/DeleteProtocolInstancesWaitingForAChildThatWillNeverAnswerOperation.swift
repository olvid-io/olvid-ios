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
import OSLog
import OlvidUtils
import CoreData


/// Operation executed during bootstrap. It deletes the `ContactDeviceDiscoveryProtocol` and `KeycloakContactAdditionProtocol` instances
/// waiting for a child protocol that will never answer them. Such a parent is stuck for good: its state accepts nothing but the child's
/// result, and no timeout ever removes it.
///
/// This is the second of the two passes of that sweep. The `candidates` were found by
/// ``ProtocolInstance/getContactDeviceDiscoveryAndKeycloakContactAdditionInstancesWaitingForAChildThatWillNeverAnswer(within:)`` on some
/// background context, where protocol steps commit between its fetches, so that first answer is a list of suspects rather than a verdict.
/// This operation therefore asks the same question again, through
/// ``ProtocolInstance/deleteContactDeviceDiscoveryAndKeycloakContactAdditionInstancesWaitingForAChildThatWillNeverAnswer(among:within:)``,
/// and deletes only those that still match.
///
/// **It must be queued on the queue running the protocol steps**, which is what makes that second answer trustworthy: no step can run
/// while it does, so the instances cannot move under it. Queued anywhere else, it would delete a parent whose result was arriving in that
/// instant, losing the devices of a contact or a contact a keycloak addition was about to create.
final class DeleteProtocolInstancesWaitingForAChildThatWillNeverAnswerOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private let candidates: [NSManagedObjectID]
    private let logger: Logger
    
    init(candidates: [NSManagedObjectID], logger: Logger) {
        self.candidates = candidates
        self.logger = logger
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            let numberOfDeletedInstancesPerProtocol = try ProtocolInstance.deleteContactDeviceDiscoveryAndKeycloakContactAdditionInstancesWaitingForAChildThatWillNeverAnswer(
                among: candidates,
                within: obvContext.context)
            
            // Reported at the notice level, which is kept in the system log, where debug and info are not: on a device holding
            // hundreds of these instances, these two figures are the whole evidence that the sweep ran and what it removed.
            // The two differ whenever a candidate found by the first pass turned out, on this queue, to be waiting for something
            // after all, which is what the second pass exists to notice
            
            let numberOfDeletedInstances = numberOfDeletedInstancesPerProtocol.values.reduce(0, +)
            
            logger.notice("Deleted \(numberOfDeletedInstances) of the \(self.candidates.count) protocol instance(s) that were waiting for a child protocol that will never answer")
            
            for (cryptoProtocolId, numberOfDeletedInstances) in numberOfDeletedInstancesPerProtocol.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                logger.notice("Deleted \(numberOfDeletedInstances) instance(s) of the protocol \(cryptoProtocolId.debugDescription, privacy: .public)")
            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
