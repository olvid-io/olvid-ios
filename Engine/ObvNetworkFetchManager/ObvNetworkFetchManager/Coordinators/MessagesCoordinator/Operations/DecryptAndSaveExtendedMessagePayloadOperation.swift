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
import os.log
import CoreData
import OlvidUtils
import ObvCrypto
import ObvTypes


final class DecryptAndSaveExtendedMessagePayloadOperation: ContextualOperationWithSpecificReasonForCancel<DecryptAndSaveExtendedMessagePayloadOperation.ReasonForCancel> {
    
    private let messageId: ObvMessageIdentifier
    private let encryptedExtendedMessagePayload: EncryptedData
    
    init(messageId: ObvMessageIdentifier, encryptedExtendedMessagePayload: EncryptedData) {
        self.messageId = messageId
        self.encryptedExtendedMessagePayload = encryptedExtendedMessagePayload
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            guard let message = try InboxMessage.get(messageId: messageId, within: obvContext) else { return }
            
            guard let extendedMessagePayloadKey = message.extendedMessagePayloadKey else {
                return cancel(withReason: .extendedMessagePayloadKeyIsNil)
            }
            
            let authEnc = extendedMessagePayloadKey.algorithmImplementationByteId.algorithmImplementation
            let extendedMessagePayload = try authEnc.decrypt(encryptedExtendedMessagePayload, with: extendedMessagePayloadKey)

            message.setExtendedMessagePayload(to: extendedMessagePayload)
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
    
    public enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case coreDataError(error: Error)
        case extendedMessagePayloadKeyIsNil

        public var logType: OSLogType {
            return .fault
        }

        public var errorDescription: String? {
            switch self {
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .extendedMessagePayloadKeyIsNil:
                return "Extended Message Payload Key is nil"
            }
        }

    }

}
