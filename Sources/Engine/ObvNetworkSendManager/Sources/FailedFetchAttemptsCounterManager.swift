/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvTypes
import ObvCrypto
import ObvMetaManager


struct FailedFetchAttemptsCounterManager {
    
    private let queue = DispatchQueue(label: "FailedFetchAttemptsCounterManagerQueue")
    
    enum Counter {
        case uploadMessage(messageId: ObvMessageIdentifier)
        case batchUploadMessages(serverURL: URL)
        case uploadAttachment(attachmentId: ObvAttachmentIdentifier)
    }

    private var _uploadMessage = [ObvMessageIdentifier: Int]()
    private var _batchUploadMessages = [URL: Int]()
    private var _uploadAttachment = [ObvAttachmentIdentifier: Int]()

    mutating func incrementAndGetDelay(_ counter: Counter, increment: Int = 1) -> Int {
        var localCounter = 0
        queue.sync {
            switch counter {
                
            case .uploadMessage(messageId: let messageId):
                _uploadMessage[messageId] = (_uploadMessage[messageId] ?? 0) + increment
                localCounter = _uploadMessage[messageId] ?? 0

            case .uploadAttachment(attachmentId: let attachmentId):
                _uploadAttachment[attachmentId] = (_uploadAttachment[attachmentId] ?? 0) + increment
                localCounter = _uploadAttachment[attachmentId] ?? 0
                
            case .batchUploadMessages(serverURL: let serverURL):
                _batchUploadMessages[serverURL] = (_batchUploadMessages[serverURL] ?? 0) + increment
                localCounter = _batchUploadMessages[serverURL] ?? 0
                
            }
            
        }
        return min(ObvConstants.standardDelay<<min(localCounter, 20), ObvConstants.maximumDelay)
    }
    
    mutating func reset(counter: Counter) {
        queue.sync {

            switch counter {

            case .uploadMessage(messageId: let messageId):
                _uploadMessage.removeValue(forKey: messageId)
                
            case .uploadAttachment(attachmentId: let attachmentId):
                _uploadAttachment.removeValue(forKey: attachmentId)
                
            case .batchUploadMessages(serverURL: let serverURL):
                _batchUploadMessages.removeValue(forKey: serverURL)

            }
        }
    }
 
    
    mutating func resetAll() {
        queue.sync {
            _uploadMessage.removeAll()
            _uploadAttachment.removeAll()
            _batchUploadMessages.removeAll()
        }
    }

}
