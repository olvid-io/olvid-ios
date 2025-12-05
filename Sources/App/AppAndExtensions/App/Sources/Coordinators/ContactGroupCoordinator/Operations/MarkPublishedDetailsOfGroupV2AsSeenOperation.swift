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
import OlvidUtils
import ObvTypes
import ObvUICoreData
import CoreData
import ObvAppTypes


final class MarkPublishedDetailsOfGroupAsSeenOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private let groupIdentifier: ObvGroupIdentifier
    
    init(groupIdentifier: ObvGroupIdentifier) {
        self.groupIdentifier = groupIdentifier
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            switch groupIdentifier {
            case .groupV1(let obvGroupV1Identifier):
                let group = try PersistedContactGroup.getContactGroup(groupIdentifier: obvGroupV1Identifier, within: obvContext.context) as? PersistedContactGroupJoined
                group?.markPublishedDetailsAsSeen()
            case .groupV2(let groupIdentifier):
                let group = try PersistedGroupV2.get(groupIdentifier: groupIdentifier, within: obvContext.context)
                group?.markPublishedDetailsAsSeen()
            }
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
