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
import OlvidUtils
import ObvEngine
import os.log
import ObvUICoreData
import CoreData

final class UpdatePersistedContactIdentityStatusWithInfoFromEngineOperation: ContextualOperationWithSpecificReasonForCancel<UpdatePersistedContactIdentityStatusWithInfoFromEngineOperationReasonForCancel> {
    
    let obvContactIdentity: ObvContactIdentity
    let trustedIdentityDetailsWereUpdated: Bool
    let publishedIdentityDetailsWereUpdated: Bool
    
    init(obvContactIdentity: ObvContactIdentity, trustedIdentityDetailsWereUpdated: Bool, publishedIdentityDetailsWereUpdated: Bool) {
        self.obvContactIdentity = obvContactIdentity
        self.trustedIdentityDetailsWereUpdated = trustedIdentityDetailsWereUpdated
        self.publishedIdentityDetailsWereUpdated = publishedIdentityDetailsWereUpdated
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            guard let persistedContactIdentity = try PersistedObvContactIdentity.get(persisted: obvContactIdentity.contactIdentifier, whereOneToOneStatusIs: .any, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindContactIdentityInDatabase)
            }
            
            if trustedIdentityDetailsWereUpdated {
                persistedContactIdentity.setContactStatus(to: .noNewPublishedDetails)
            }
            
            if publishedIdentityDetailsWereUpdated {
                assert(obvContactIdentity.publishedIdentityDetails != nil)
                if let receivedPublishedDetails = obvContactIdentity.publishedIdentityDetails {
                    let identicalPhotos: Bool
                    if obvContactIdentity.trustedIdentityDetails.photoURL == receivedPublishedDetails.photoURL {
                        identicalPhotos = true
                    } else if let trustedPhotoURL = obvContactIdentity.trustedIdentityDetails.photoURL, let newPhotoURL = receivedPublishedDetails.photoURL {
                        identicalPhotos = FileManager.default.contentsEqual(atPath: trustedPhotoURL.path, andPath: newPhotoURL.path)
                    } else {
                        identicalPhotos = false
                    }
                    if obvContactIdentity.trustedIdentityDetails.coreDetails == receivedPublishedDetails.coreDetails && identicalPhotos {
                        persistedContactIdentity.setContactStatus(to: .noNewPublishedDetails)
                    } else {
                        persistedContactIdentity.setContactStatus(to: .unseenPublishedDetails)
                    }
                }
            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
}


enum UpdatePersistedContactIdentityStatusWithInfoFromEngineOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case contextIsNil
    case couldNotFindContactIdentityInDatabase

    var logType: OSLogType {
        switch self {
        case .coreDataError,
             .contextIsNil:
            return .fault
        case .couldNotFindContactIdentityInDatabase:
            return .error
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .contextIsNil:
            return "Context is nil"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotFindContactIdentityInDatabase:
            return "Could not find contact identity in database"
        }
    }

}
