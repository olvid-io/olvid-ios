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
        case downloadAttachment(attachmentId: AttachmentIdentifier)
        case processPendingDeleteFromServer(messageId: MessageIdentifier)
        case serverQuery(objectID: NSManagedObjectID)
        case serverUserData(input: ServerUserDataInput)
        case queryServerWellKnown(serverURL: URL)
    }
    
    private var _downloadMessagesAndListAttachments = [ObvCryptoIdentity: Int]()
    private var _sessionCreation = [ObvCryptoIdentity: Int]()
    private var _registerPushNotification = [ObvCryptoIdentity: Int]()
    private var _downloadAttachment = [AttachmentIdentifier: Int]()
    private var _processPendingDeleteFromServer = [MessageIdentifier: Int]()
    private var _serverQuery = [NSManagedObjectID: Int]()
    private var _serverUserData = [ServerUserDataInput: Int]()
    private var _queryServerWellKnown = [URL: Int]()

    private var count: Int = 0
    
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
                
            case .registerPushNotification(ownedIdentity: let identity):
                _registerPushNotification[identity] = (_registerPushNotification[identity] ?? 0) + increment
                localCounter = _registerPushNotification[identity] ?? 0

            case .downloadAttachment(attachmentId: let attachmentId):
                localCounter = (_downloadAttachment[attachmentId] ?? 0) + increment
                _downloadAttachment[attachmentId] = localCounter
                
            case .processPendingDeleteFromServer(messageId: let messageId):
                localCounter = (_processPendingDeleteFromServer[messageId] ?? 0) + increment
                _processPendingDeleteFromServer[messageId] = localCounter

            case .serverQuery(objectID: let objectID):
                _serverQuery[objectID] = (_serverQuery[objectID] ?? 0) + increment
                localCounter = _serverQuery[objectID] ?? 0

            case .serverUserData(input: let input):
                _serverUserData[input] = (_serverUserData[input] ?? 0) + increment
                localCounter = _serverUserData[input] ?? 0
                
            case .queryServerWellKnown(serverURL: let serverURL):
                _queryServerWellKnown[serverURL] = (_queryServerWellKnown[serverURL] ?? 0) + increment
                localCounter = _queryServerWellKnown[serverURL] ?? 0

            }

        }
        return min(ObvConstants.standardDelay<<localCounter, ObvConstants.maximumDelay)
    }
    
    mutating func reset(counter: Counter) {
        queue.sync {
            switch counter {
            case .downloadMessagesAndListAttachments(ownedIdentity: let identity):
                _downloadMessagesAndListAttachments.removeValue(forKey: identity)

            case .sessionCreation(ownedIdentity: let identity):
                _sessionCreation.removeValue(forKey: identity)

            case .registerPushNotification(ownedIdentity: let identity):
                _registerPushNotification.removeValue(forKey: identity)
                
            case .downloadAttachment(attachmentId: let attachmentId):
                _downloadAttachment.removeValue(forKey: attachmentId)
                
            case .processPendingDeleteFromServer(messageId: let messageId):
                _processPendingDeleteFromServer.removeValue(forKey: messageId)

            case .serverQuery(objectID: let objectID):
                _serverQuery.removeValue(forKey: objectID)

            case .serverUserData(input: let input):
                _serverUserData.removeValue(forKey: input)
                
            case .queryServerWellKnown(serverURL: let serverURL):
                _queryServerWellKnown.removeValue(forKey: serverURL)
            }
        }
    }
    
    
    mutating func resetAll() {
        queue.sync {
            _downloadMessagesAndListAttachments.removeAll()
            _sessionCreation.removeAll()
            _registerPushNotification.removeAll()
            _downloadAttachment.removeAll()
            _processPendingDeleteFromServer.removeAll()
            _serverQuery.removeAll()
            _serverUserData.removeAll()
            _queryServerWellKnown.removeAll()
        }
    }

}
