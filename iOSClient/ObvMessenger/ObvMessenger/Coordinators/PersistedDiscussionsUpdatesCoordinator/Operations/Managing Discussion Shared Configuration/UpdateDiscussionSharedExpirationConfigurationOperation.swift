/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import OlvidUtils
import ObvUICoreData

final class ReplaceDiscussionSharedExpirationConfigurationOperation: ContextualOperationWithSpecificReasonForCancel<ReplaceDiscussionSharedExpirationConfigurationOperation.ReasonForCancel> {
    
    private let ownedCryptoIdAsInitiator: ObvCryptoId
    private let discussionId: DiscussionIdentifier
    private let expirationJSON: ExpirationJSON
    

    init(ownedCryptoIdAsInitiator: ObvCryptoId, discussionId: DiscussionIdentifier, expirationJSON: ExpirationJSON) {
        self.ownedCryptoIdAsInitiator = ownedCryptoIdAsInitiator
        self.discussionId = discussionId
        self.expirationJSON = expirationJSON
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            guard let persistedOwnedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoIdAsInitiator, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindPersistedOwnedIdentity)
            }
            
            try persistedOwnedIdentity.replaceDiscussionSharedConfigurationSentByThisOwnedIdentity(
                with: expirationJSON,
                inDiscussionWithId: discussionId)
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
            
    }
    
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case coreDataError(error: Error)
        case couldNotFindPersistedOwnedIdentity
        
        var logType: OSLogType {
            switch self {
            case .coreDataError, .couldNotFindPersistedOwnedIdentity:
                return .fault
            }
        }
        
        var errorDescription: String? {
            switch self {
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .couldNotFindPersistedOwnedIdentity:
                return "Could not find owned identity"
            }
        }

    }

}
