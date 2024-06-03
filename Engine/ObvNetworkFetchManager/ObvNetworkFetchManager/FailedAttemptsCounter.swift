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
import CoreData
import ObvTypes
import ObvCrypto
import ObvMetaManager


struct FailedAttemptsCounterManager {
    
    private let queue = DispatchQueue(label: "FailedAttemptsCounterManager")
    
    enum Counter {
        case sessionCreation(ownedIdentity: ObvCryptoIdentity)
        case registerPushNotification(ownedIdentity: ObvCryptoIdentity)
        case downloadMessagesAndListAttachments(ownedIdentity: ObvCryptoIdentity)
        case downloadAttachment(attachmentId: ObvAttachmentIdentifier)
        case serverQuery(objectID: NSManagedObjectID)
        case serverUserData(input: ServerUserDataInput)
        case queryServerWellKnown(serverURL: URL)
        case freeTrialQuery(ownedIdentity: ObvCryptoIdentity)
        case downloadOfExtendedMessagePayload(messageId: ObvMessageIdentifier)
        case sendingWebSocketRegisterMessage
        case webSocketTask(webSocketServerURL: URL?)
        case batchDeleteAndMarkAsListed(ownedCryptoIdentity: ObvCryptoIdentity)
    }
    
    private var _downloadMessagesAndListAttachments = [ObvCryptoIdentity: Int]()
    private var _sessionCreation = [ObvCryptoIdentity: Int]()
    private var _registerPushNotification = [ObvCryptoIdentity: Int]()
    private var _downloadAttachment = [ObvAttachmentIdentifier: Int]()
    private var _serverQuery = [NSManagedObjectID: Int]()
    private var _serverUserData = [ServerUserDataInput: Int]()
    private var _queryServerWellKnown = [URL: Int]()
    private var _freeTrialQuery = [ObvCryptoIdentity: Int]()
    private var _downloadOfExtendedMessagePayload = [ObvMessageIdentifier: Int]()
    private var _sendingWebSocketRegisterMessage: Int?
    private var _webSocketTask = [URL?: Int]()
    private var _batchDeleteAndMarkAsListed = [ObvCryptoIdentity: Int]()

    private var count: Int = 0
    
    mutating func getCurrentDelay(_ counter: Counter) -> Int {
        return incrementAndGetDelay(counter, increment: 0)
    }
    
    mutating func incrementAndGetDelay(_ counter: Counter, increment: Int = 1) -> Int {
        var localCounter = 0
        queue.sync {
            switch counter {
                
            case .downloadMessagesAndListAttachments(ownedIdentity: let identity):
                _downloadMessagesAndListAttachments[identity] = (_downloadMessagesAndListAttachments[identity] ?? 0) + increment
                localCounter = _downloadMessagesAndListAttachments[identity] ?? 0
                
            case .sessionCreation(ownedIdentity: let identity):
                _sessionCreation[identity] = (_sessionCreation[identity] ?? 0) + increment
                localCounter = _sessionCreation[identity] ?? 0

            case .freeTrialQuery(ownedIdentity: let identity):
                _freeTrialQuery[identity] = (_freeTrialQuery[identity] ?? 0) + increment
                localCounter = _freeTrialQuery[identity] ?? 0

            case .registerPushNotification(ownedIdentity: let identity):
                _registerPushNotification[identity] = (_registerPushNotification[identity] ?? 0) + increment
                localCounter = _registerPushNotification[identity] ?? 0

            case .downloadAttachment(attachmentId: let attachmentId):
                localCounter = (_downloadAttachment[attachmentId] ?? 0) + increment
                _downloadAttachment[attachmentId] = localCounter
                
            case .serverQuery(objectID: let objectID):
                _serverQuery[objectID] = (_serverQuery[objectID] ?? 0) + increment
                localCounter = _serverQuery[objectID] ?? 0

            case .serverUserData(input: let input):
                _serverUserData[input] = (_serverUserData[input] ?? 0) + increment
                localCounter = _serverUserData[input] ?? 0
                
            case .queryServerWellKnown(serverURL: let serverURL):
                _queryServerWellKnown[serverURL] = (_queryServerWellKnown[serverURL] ?? 0) + increment
                localCounter = _queryServerWellKnown[serverURL] ?? 0
                
            case .downloadOfExtendedMessagePayload(messageId: let messageId):
                _downloadOfExtendedMessagePayload[messageId] = (_downloadOfExtendedMessagePayload[messageId] ?? 0) + increment
                localCounter = _downloadOfExtendedMessagePayload[messageId] ?? 0
                
            case .sendingWebSocketRegisterMessage:
                _sendingWebSocketRegisterMessage = (_sendingWebSocketRegisterMessage ?? 0) + increment
                localCounter = _sendingWebSocketRegisterMessage ?? 0
                
            case .webSocketTask(webSocketServerURL: let webSocketServerURL):
                _webSocketTask[webSocketServerURL] = (_webSocketTask[webSocketServerURL] ?? 0) + increment
                localCounter = _webSocketTask[webSocketServerURL] ?? 0
                
            case .batchDeleteAndMarkAsListed(ownedCryptoIdentity: let ownedCryptoIdentity):
                _batchDeleteAndMarkAsListed[ownedCryptoIdentity] = _batchDeleteAndMarkAsListed[ownedCryptoIdentity, default: 0] + increment
                localCounter = _batchDeleteAndMarkAsListed[ownedCryptoIdentity] ?? 0

            }

        }
        return min(ObvConstants.standardDelay<<min(localCounter, 20), ObvConstants.maximumDelay)
    }
    
    mutating func reset(counter: Counter) {
        queue.sync {
            switch counter {
            case .downloadMessagesAndListAttachments(ownedIdentity: let identity):
                _downloadMessagesAndListAttachments.removeValue(forKey: identity)

            case .sessionCreation(ownedIdentity: let identity):
                _sessionCreation.removeValue(forKey: identity)

            case .freeTrialQuery(ownedIdentity: let identity):
                _freeTrialQuery.removeValue(forKey: identity)

            case .registerPushNotification(ownedIdentity: let identity):
                _registerPushNotification.removeValue(forKey: identity)
                
            case .downloadAttachment(attachmentId: let attachmentId):
                _downloadAttachment.removeValue(forKey: attachmentId)
                
            case .serverQuery(objectID: let objectID):
                _serverQuery.removeValue(forKey: objectID)

            case .serverUserData(input: let input):
                _serverUserData.removeValue(forKey: input)
                
            case .queryServerWellKnown(serverURL: let serverURL):
                _queryServerWellKnown.removeValue(forKey: serverURL)
                
            case .downloadOfExtendedMessagePayload(messageId: let messageId):
                _downloadOfExtendedMessagePayload.removeValue(forKey: messageId)
                
            case .sendingWebSocketRegisterMessage:
                _sendingWebSocketRegisterMessage = nil
                
            case .webSocketTask(webSocketServerURL: let webSocketServerURL):
                _webSocketTask.removeValue(forKey: webSocketServerURL)
                
            case .batchDeleteAndMarkAsListed(ownedCryptoIdentity: let ownedCryptoIdentity):
                _batchDeleteAndMarkAsListed.removeValue(forKey: ownedCryptoIdentity)
                
            }
        }
    }
    
    
    mutating func resetAll() {
        queue.sync {
            _freeTrialQuery.removeAll()
            _downloadMessagesAndListAttachments.removeAll()
            _sessionCreation.removeAll()
            _registerPushNotification.removeAll()
            _downloadAttachment.removeAll()
            _serverQuery.removeAll()
            _serverUserData.removeAll()
            _queryServerWellKnown.removeAll()
            _downloadOfExtendedMessagePayload.removeAll()
            _sendingWebSocketRegisterMessage = nil
            _webSocketTask.removeAll()
            _batchDeleteAndMarkAsListed.removeAll()
        }
    }

}
