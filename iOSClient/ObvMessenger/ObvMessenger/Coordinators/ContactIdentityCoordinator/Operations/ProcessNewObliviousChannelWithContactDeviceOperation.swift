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


/// When a new channel is created with a contact device:
/// - we create a contact device
/// - we send the one-to-one discussion shared settings to the contact (well, we notify that it should be sent)
//final class ProcessNewObliviousChannelWithContactDeviceOperation: ContextualOperationWithSpecificReasonForCancel<ProcessNewObliviousChannelWithContactDeviceOperationReasonForCancel> {
//    
//    let obvContactDevice: ObvContactDevice
//    
//    init(obvContactDevice: ObvContactDevice) {
//        self.obvContactDevice = obvContactDevice
//        super.init()
//    }
//    
//    override func main() {
//        
//        guard let obvContext = self.obvContext else {
//            return cancel(withReason: .contextIsNil)
//        }
//
//        obvContext.performAndWait {
//            
//            do {
//                guard let contact = try PersistedObvContactIdentity.get(persisted: obvContactDevice.contactIdentifier, whereOneToOneStatusIs: .any, within: obvContext.context) else {
//                    return cancel(withReason: .couldNotFindContactIdentityInDatabase)
//                }
//                
//                try contact.insert(obvContactDevice)
//                
//            } catch {
//                
//                return cancel(withReason: .coreDataError(error: error))
//                
//            }
//            
//        }
//        
//    }
//    
//}

enum ProcessNewObliviousChannelWithContactDeviceOperationReasonForCancel: LocalizedErrorWithLogType {
    
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
