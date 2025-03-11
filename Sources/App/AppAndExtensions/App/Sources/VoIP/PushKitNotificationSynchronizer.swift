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
import os.log
import ObvTypes
import ObvCrypto
import ObvSettings
import ObvAppCoreConstants



actor PushKitNotificationSynchronizer {
    
    private static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "PushKitNotificationSynchronizer")

    private var receivedStartCallMessageForCallWithCallIdentifierForCallKit = [UUID: (callerDeviceIdentifier: ObvContactDeviceIdentifier, startCallMessage: StartCallMessageJSON, uuidForWebRTC: UUID)]()
    private var sleepTaskForCallWithCallIdentifierForCallKit = [UUID: Task<Void, Error>]()
    

    /// Called by the `CallProviderDelegate` when receiving a pushkit notification, after reporting the call to the system using a "fake" `CXCallUpdate`.
    /// As soon as a `StartCallMessageJSON` is available, this method returns it, allowing the `CallProviderDelegate` to update the
    /// call with a proper `CXCallUpdate`.
    func waitForStartCallMessage(encryptedNotification: ObvEncryptedRemoteUserNotification) async throws -> (callerDeviceIdentifier: ObvContactDeviceIdentifier, startCallMessage: StartCallMessageJSON, uuidForWebRTC: UUID) {
        
        let callIdentifierForCallKit = encryptedNotification.messageIdFromServer.deterministicUUID

        // The start call message may already be available, in which case, we return it
        
        if let receivedValues = receivedStartCallMessageForCallWithCallIdentifierForCallKit[callIdentifierForCallKit] {
            os_log("☎️ Start call message is readily available, so we return it now", log: Self.log, type: .info)
            return receivedValues
        }
        
        // Now that we notified, we wait until the start call message is available
        
        os_log("☎️ We wait until the start call message is available", log: Self.log, type: .info)

        assert(sleepTaskForCallWithCallIdentifierForCallKit[callIdentifierForCallKit] == nil)
        let sleepTask = Task { try await Task.sleep(seconds: 10) }
        sleepTaskForCallWithCallIdentifierForCallKit[callIdentifierForCallKit] = sleepTask
        // Wait until the sleep task is cancelled (upon reception of the start call message)
        // Note the try? instead of try: we don't want to throw when the task is cancelled.
        try? await sleepTask.value

        // Either the sleep task has been cancelled because the start call message is available, or it waited for too long
        
        guard let startCallMessage = receivedStartCallMessageForCallWithCallIdentifierForCallKit[callIdentifierForCallKit] else {
            os_log("☎️ Enough waiting for the start call message. We fail.", log: Self.log, type: .error)
            throw ObvError.startCallMessageNeverArrived
        }

        os_log("☎️ The start call message we were waiting for is now available, we return it", log: Self.log, type: .info)

        return startCallMessage

    }
    
    
    /// Called by the `CallProviderDelegate` when receiving a `StartCallMessageJSON` when CallKit is enabled (which never happens in a simulator).
    /// We store this message and cancel any sleeping task. This mechanism allows to make sure the PushKit notification is received before actually using this start call message to start an incoming call.
    func continuePushKitNotificationProcessing(_ startCallMessage: StartCallMessageJSON, messageIdFromServer: UID, callerDeviceIdentifier: ObvContactDeviceIdentifier, uuidForWebRTC: UUID) {
        
        assert(ObvUICoreDataConstants.useCallKit)
        
        os_log("☎️ Receiving a start call message", log: Self.log, type: .info)
        
        let callIdentifierForCallKit = messageIdFromServer.deterministicUUID

        guard receivedStartCallMessageForCallWithCallIdentifierForCallKit[callIdentifierForCallKit] == nil else {
            // We already received this start call message. This happens when:
            // - The PushKit notification was decrypted
            // - Then the same encrypted message arrived from the net work fetch manager.
            // So that this method is called twice. In that case, we discard the second call here.
            return
        }
        
        receivedStartCallMessageForCallWithCallIdentifierForCallKit[callIdentifierForCallKit] = (callerDeviceIdentifier, startCallMessage, uuidForWebRTC)
        
        if let sleepTask = sleepTaskForCallWithCallIdentifierForCallKit.removeValue(forKey: callIdentifierForCallKit) {
            // Now that the start call message is available, we can resume the waitForStartCallMessage(encryptedNotification:) method.
            os_log("☎️ We will resume the sleeping waitForStartCallMessage(encryptedNotification:) method as the expected start call message is now available", log: Self.log, type: .info)
            sleepTask.cancel()
        } else {
            // The PushKit notification will arrive soon and the waitForStartCallMessage(encryptedNotification:) method will called.
            // The start call message will be ready to be used immediately.
            os_log("☎️ The start call message has been stored, waiting for the PsuhKit notification that will arrive soon", log: Self.log, type: .info)
        }
        
    }
 
    
    enum ObvError: Error {
        case startCallMessageNeverArrived
        case obvMessageIsNotWebRTCMessage
    }

}
