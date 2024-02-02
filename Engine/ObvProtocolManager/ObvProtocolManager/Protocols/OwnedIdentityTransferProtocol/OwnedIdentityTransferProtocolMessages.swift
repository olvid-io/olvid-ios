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
import ObvEncoder
import ObvMetaManager
import ObvCrypto
import ObvTypes


// MARK: - Protocol Messages

extension OwnedIdentityTransferProtocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {
        
        case initiateTransferOnSourceDevice = 0
        case initiateTransferOnTargetDevice = 1
        case sourceGetSessionNumber = 2
        case sourceWaitForTargetConnection = 4
//        case targetGetSessionNumber = 5
        case targetSendEphemeralIdentity = 6
        case sourceSendCommitment = 7
        case targetSeed = 8
        case sourceSASInput = 9
        case sourceDecommitment = 10
        case targetWaitForSnapshot = 11
        case sourceSnapshot = 12
        case closeWebsocketConnection = 99
        case abortProtocol = 100

        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .initiateTransferOnSourceDevice:
                return InitiateTransferOnSourceDeviceMessage.self
            case .initiateTransferOnTargetDevice:
                return InitiateTransferOnTargetDeviceMessage.self
            case .sourceGetSessionNumber:
                return SourceGetSessionNumberMessage.self
            case .targetSendEphemeralIdentity:
                return TargetSendEphemeralIdentityMessage.self
            case .targetSeed:
                return TargetSeedMessage.self
            case .targetWaitForSnapshot:
                return TargetWaitForSnapshotMessage.self
            case .closeWebsocketConnection:
                return CloseWebsocketConnectionMessage.self
            case .abortProtocol:
                return AbortProtocolMessage.self
            case .sourceWaitForTargetConnection:
                return SourceWaitForTargetConnectionMessage.self
            case .sourceSendCommitment:
                return SourceSendCommitmentMessage.self
            case .sourceDecommitment:
                return SourceDecommitmentMessage.self
            case .sourceSASInput:
                return SourceSASInputMessage.self
            case .sourceSnapshot:
                return SourceSnapshotMessage.self
            }
        }
        
    }
    
    
    // MARK: - InitiateTransferOnSourceDeviceMessage
    
    struct InitiateTransferOnSourceDeviceMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.initiateTransferOnSourceDevice
        let coreProtocolMessage: CoreProtocolMessage

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
        }

        var encodedInputs: [ObvEncoded] { [] }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
        }

    }

    
    // MARK: - InitiateTransferOnTargetDeviceMessage
    
    struct InitiateTransferOnTargetDeviceMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.initiateTransferOnTargetDevice
        let coreProtocolMessage: CoreProtocolMessage

        let currentDeviceName: String
        let transferSessionNumber: ObvOwnedIdentityTransferSessionNumber
        let encryptionPrivateKey: PrivateKeyForPublicKeyEncryption
        let macKey: MACKey
        
        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, currentDeviceName: String, transferSessionNumber: ObvOwnedIdentityTransferSessionNumber, encryptionPrivateKey: PrivateKeyForPublicKeyEncryption, macKey: MACKey) {
            self.coreProtocolMessage = coreProtocolMessage
            self.currentDeviceName = currentDeviceName
            self.transferSessionNumber = transferSessionNumber
            self.encryptionPrivateKey = encryptionPrivateKey
            self.macKey = macKey
        }

        var encodedInputs: [ObvEncoded] {
            [
                currentDeviceName.obvEncode(),
                transferSessionNumber.obvEncode(),
                encryptionPrivateKey.obvEncode(),
                macKey.obvEncode()
            ]
        }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 4 else { assertionFailure(); throw ObvError.unexpectedNumberOfEncodedElements }
            self.currentDeviceName = try message.encodedInputs[0].obvDecode()
            self.transferSessionNumber = try message.encodedInputs[1].obvDecode()
            self.encryptionPrivateKey = try PrivateKeyForPublicKeyEncryptionDecoder.obvDecodeOrThrow(message.encodedInputs[2])
            self.macKey = try MACKeyDecoder.obvDecodeOrThrow(message.encodedInputs[3])
        }

        enum ObvError: Error {
            case unexpectedNumberOfEncodedElements
        }

    }

    
    // MARK: - SourceSASInputMessage
    
    struct SourceSASInputMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.sourceSASInput
        let coreProtocolMessage: CoreProtocolMessage

        let enteredSAS: ObvOwnedIdentityTransferSas
        let deviceUIDToKeepActive: UID?
                
        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, enteredSAS: ObvOwnedIdentityTransferSas, deviceUIDToKeepActive: UID?) {
            self.coreProtocolMessage = coreProtocolMessage
            self.enteredSAS = enteredSAS
            self.deviceUIDToKeepActive = deviceUIDToKeepActive
        }

        var encodedInputs: [ObvEncoded] {
            var encoded = [enteredSAS.obvEncode()]
            if let deviceUIDToKeepActive {
                encoded += [deviceUIDToKeepActive.obvEncode()]
            }
            return encoded
        }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            if message.encodedInputs.count == 1 {
                self.enteredSAS = try message.encodedInputs[0].obvDecode()
                self.deviceUIDToKeepActive = nil
            } else if message.encodedInputs.count == 2 {
                self.enteredSAS = try message.encodedInputs[0].obvDecode()
                self.deviceUIDToKeepActive = try message.encodedInputs[1].obvDecode()
            } else {
                throw ObvError.unexpectedNumberOfEncodedElements
            }
        }

        enum ObvError: Error {
            case unexpectedNumberOfEncodedElements
        }

    }

    
    // MARK: - SourceGetSessionNumberMessage
    
    struct SourceGetSessionNumberMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.sourceGetSessionNumber
        let coreProtocolMessage: CoreProtocolMessage

        // Not used when posting this message from the protocol manager
        let result: SourceGetSessionNumberResult

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
            self.result = .requestFailed // Not used anyway
        }

        var encodedInputs: [ObvEncoded] { [] }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { assertionFailure(); throw ObvError.unexpectedNumberOfEncodedElements }
            self.result = try message.encodedInputs[0].obvDecode()
        }

        enum ObvError: Error {
            case unexpectedNumberOfEncodedElements
        }
        
    }

    
    // MARK: - SourceGetSessionNumberMessage
    
    struct SourceWaitForTargetConnectionMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.sourceWaitForTargetConnection
        let coreProtocolMessage: CoreProtocolMessage

        // Not used when posting this message from the protocol manager
        let result: SourceWaitForTargetConnectionResult

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
            self.result = .requestFailed // Not used anyway
        }

        var encodedInputs: [ObvEncoded] { [] }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { assertionFailure(); throw ObvError.unexpectedNumberOfEncodedElements }
            self.result = try message.encodedInputs[0].obvDecode()
        }

        enum ObvError: Error {
            case unexpectedNumberOfEncodedElements
        }
        
    }

    
    // MARK: - SourceSendCommitmentMessage
    
    struct SourceSendCommitmentMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.sourceSendCommitment
        let coreProtocolMessage: CoreProtocolMessage

        // Not used when posting this message from the protocol manager
        let result: OwnedIdentityTransferRelayMessageResult

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
            self.result = .requestFailed // Not used anyway
        }

        var encodedInputs: [ObvEncoded] { [] }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { assertionFailure(); throw ObvError.unexpectedNumberOfEncodedElements }
            self.result = try message.encodedInputs[0].obvDecode()
        }

        enum ObvError: Error {
            case unexpectedNumberOfEncodedElements
        }
        
    }

    
    // MARK: - SourceDecommitmentMessage
    
    struct SourceDecommitmentMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.sourceDecommitment
        let coreProtocolMessage: CoreProtocolMessage

        // Not used when posting this message from the protocol manager
        let result: OwnedIdentityTransferRelayMessageResult

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
            self.result = .requestFailed // Not used anyway
        }

        var encodedInputs: [ObvEncoded] { [] }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { assertionFailure(); throw ObvError.unexpectedNumberOfEncodedElements }
            self.result = try message.encodedInputs[0].obvDecode()
        }

        enum ObvError: Error {
            case unexpectedNumberOfEncodedElements
        }
        
    }

    
    // MARK: - TargetSendEphemeralIdentityMessage
    
    struct TargetSendEphemeralIdentityMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.targetSendEphemeralIdentity
        let coreProtocolMessage: CoreProtocolMessage

        // Not used when posting this message from the protocol manager
        let result: TargetSendEphemeralIdentityResult

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
            self.result = .requestDidFail // Not used anyway
        }

        var encodedInputs: [ObvEncoded] { [] }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { assertionFailure(); throw ObvError.unexpectedNumberOfEncodedElements }
            self.result = try message.encodedInputs[0].obvDecode()
        }

        enum ObvError: Error {
            case unexpectedNumberOfEncodedElements
        }
        
    }

    
    // MARK: - TargetSeedMessage
    
    struct TargetSeedMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.targetSeed
        let coreProtocolMessage: CoreProtocolMessage

        // Not used when posting this message from the protocol manager
        let result: OwnedIdentityTransferRelayMessageResult

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
            self.result = .requestFailed // Not used anyway
        }

        var encodedInputs: [ObvEncoded] { [] }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { assertionFailure(); throw ObvError.unexpectedNumberOfEncodedElements }
            self.result = try message.encodedInputs[0].obvDecode()
        }

        enum ObvError: Error {
            case unexpectedNumberOfEncodedElements
        }
        
    }

    
    // MARK: - TargetWaitForSnapshotMessage
    
    struct TargetWaitForSnapshotMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.targetWaitForSnapshot
        let coreProtocolMessage: CoreProtocolMessage

        // Not used when posting this message from the protocol manager
        let result: OwnedIdentityTransferWaitResult

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
            self.result = .requestFailed // Not used anyway
        }

        var encodedInputs: [ObvEncoded] { [] }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { assertionFailure(); throw ObvError.unexpectedNumberOfEncodedElements }
            self.result = try message.encodedInputs[0].obvDecode()
        }

        enum ObvError: Error {
            case unexpectedNumberOfEncodedElements
        }
        
    }

    
    // MARK: - AbortProtocolMessage
    
    struct AbortProtocolMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.abortProtocol
        let coreProtocolMessage: CoreProtocolMessage

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
        }

        var encodedInputs: [ObvEncoded] { [] }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
        }

    }

    
    // MARK: - CloseWebsocketConnectionMessage
    
    struct CloseWebsocketConnectionMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.closeWebsocketConnection
        let coreProtocolMessage: CoreProtocolMessage

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
        }

        var encodedInputs: [ObvEncoded] { [] }
        
        // Init when receiving this message (never called as we don't expect an answer to this server query)

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
        }

    }

    
    // MARK: - SourceSnapshotMessage
    
    struct SourceSnapshotMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.sourceSnapshot
        let coreProtocolMessage: CoreProtocolMessage

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
        }

        var encodedInputs: [ObvEncoded] { [] }
        
        // Init when receiving this message (never called as we don't expect an answer to this server query)

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
        }

    }

}
