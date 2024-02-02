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
import ObvCrypto
import ObvMetaManager
import ObvTypes

// MARK: - Protocol Messages

extension SynchronizationProtocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {
        
        // For Atoms
        case initiateSyncAtom = 0
        case syncAtom = 1
        case syncAtomDialog = 100
        // For Snapshots
//        case initiateSyncSnapshot = 2
//        case triggerSyncSnapshot = 3
//        case transferSyncSnapshot = 4
//        case atomProcessed = 5
        
        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {

            case .initiateSyncAtom : return InitiateSyncAtomMessage.self
            case .syncAtom: return SyncAtomMessage.self
            case .syncAtomDialog: return SyncAtomDialogMessage.self

//            case .initiateSyncSnapshot: return InitiateSyncSnapshotMessage.self
//            case .triggerSyncSnapshot: return TriggerSyncSnapshotMessage.self
//            case .transferSyncSnapshot: return TransferSyncSnapshotMessage.self
//            case .atomProcessed: return AtomProcessedMessage.self
                
            }
        }

    }
    
    
    // MARK: - InitiateSyncAtomMessage
    
    struct InitiateSyncAtomMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.initiateSyncAtom
        let coreProtocolMessage: CoreProtocolMessage
        
        let syncAtom: ObvSyncAtom
        
        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, syncAtom: ObvSyncAtom) {
            self.coreProtocolMessage = coreProtocolMessage
            self.syncAtom = syncAtom
        }

        var encodedInputs: [ObvEncoded] {
            return [syncAtom.obvEncode()]
        }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            syncAtom = try message.encodedInputs.obvDecode()
        }

    }
    
    
    // MARK: - SyncAtomMessage

    struct SyncAtomMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.syncAtom
        let coreProtocolMessage: CoreProtocolMessage
        
        let syncAtom: ObvSyncAtom
        
        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, syncAtom: ObvSyncAtom) {
            self.coreProtocolMessage = coreProtocolMessage
            self.syncAtom = syncAtom
        }

        var encodedInputs: [ObvEncoded] {
            return [syncAtom.obvEncode()]
        }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            syncAtom = try message.encodedInputs.obvDecode()
        }

    }
    
    
    // MARK: - InitiateSyncSnapshotMessage
    
//    struct InitiateSyncSnapshotMessage: ConcreteProtocolMessage {
//
//        let id: ConcreteProtocolMessageId = MessageId.initiateSyncSnapshot
//        let coreProtocolMessage: CoreProtocolMessage
//
//        let otherOwnedDeviceUID: UID
//
//        // Init when sending this message
//
//        init(coreProtocolMessage: CoreProtocolMessage, otherOwnedDeviceUID: UID) {
//            self.coreProtocolMessage = coreProtocolMessage
//            self.otherOwnedDeviceUID = otherOwnedDeviceUID
//        }
//
//        var encodedInputs: [ObvEncoded] {
//            return [otherOwnedDeviceUID.obvEncode()]
//        }
//
//        // Init when receiving this message
//
//        init(with message: ReceivedMessage) throws {
//            self.coreProtocolMessage = CoreProtocolMessage(with: message)
//            otherOwnedDeviceUID = try message.encodedInputs.obvDecode()
//        }
//
//    }

    
    // MARK: - TriggerSyncSnapshotMessage
    
//    struct TriggerSyncSnapshotMessage: ConcreteProtocolMessage {
//
//        let id: ConcreteProtocolMessageId = MessageId.triggerSyncSnapshot
//        let coreProtocolMessage: CoreProtocolMessage
//
//        let forceSendSnapshot: Bool
//
//        // Init when sending this message
//
//        init(coreProtocolMessage: CoreProtocolMessage, forceSendSnapshot: Bool) {
//            self.coreProtocolMessage = coreProtocolMessage
//            self.forceSendSnapshot = forceSendSnapshot
//        }
//
//        var encodedInputs: [ObvEncoded] {
//            return [forceSendSnapshot.obvEncode()]
//        }
//
//        // Init when receiving this message
//
//        init(with message: ReceivedMessage) throws {
//            self.coreProtocolMessage = CoreProtocolMessage(with: message)
//            forceSendSnapshot = try message.encodedInputs.obvDecode()
//        }
//
//    }

    
    // MARK: - TransferSyncSnapshotMessage
    
//    struct TransferSyncSnapshotMessage: ConcreteProtocolMessage {
//
//        let id: ConcreteProtocolMessageId = MessageId.transferSyncSnapshot
//        let coreProtocolMessage: CoreProtocolMessage
//
//        // Naming reflecting the understanding of the receiver of this message
//        let remoteSyncSnapshotAndVersion: ObvSyncSnapshotAndVersion
//        let localVersionKnownBySender: Int?
//
//        // Init when sending this message
//
//        init(coreProtocolMessage: CoreProtocolMessage, remoteSyncSnapshotAndVersion: ObvSyncSnapshotAndVersion, localVersionKnownBySender: Int?) {
//            self.coreProtocolMessage = coreProtocolMessage
//            self.remoteSyncSnapshotAndVersion = remoteSyncSnapshotAndVersion
//            self.localVersionKnownBySender = localVersionKnownBySender
//        }
//
//        var encodedInputs: [ObvEncoded] {
//            get throws {
//                return [remoteSyncSnapshotAndVersion.version.obvEncode(), (localVersionKnownBySender ?? -1).obvEncode(), try remoteSyncSnapshotAndVersion.syncSnapshot.obvEncode()]
//            }
//        }
//
//        // Init when receiving this message
//
//        init(with message: ReceivedMessage) throws {
//            self.coreProtocolMessage = CoreProtocolMessage(with: message)
//            let (removeVersion, localVersion, remoteSnapshot): (Int, Int, ObvSyncSnapshot) = try message.encodedInputs.obvDecode()
//            self.remoteSyncSnapshotAndVersion = ObvSyncSnapshotAndVersion(version: removeVersion, syncSnapshot: remoteSnapshot)
//            self.localVersionKnownBySender = (localVersion == -1) ? nil : localVersion
//        }
//
//    }

    
    // MARK: - AtomProcessedMessage
    
//    struct AtomProcessedMessage: ConcreteProtocolMessage {
//        
//        let id: ConcreteProtocolMessageId = MessageId.atomProcessed
//        let coreProtocolMessage: CoreProtocolMessage
//        
//        // Init when sending this message
//
//        init(coreProtocolMessage: CoreProtocolMessage) {
//            self.coreProtocolMessage = coreProtocolMessage
//        }
//
//        var encodedInputs: [ObvEncoded] { [] }
//        
//        // Init when receiving this message
//
//        init(with message: ReceivedMessage) throws {
//            self.coreProtocolMessage = CoreProtocolMessage(with: message)
//        }
//
//    }

    
    // MARK: - SyncAtomDialogMessage

    struct SyncAtomDialogMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.syncAtomDialog
        let coreProtocolMessage: CoreProtocolMessage
        
        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
        }

        var encodedInputs: [ObvEncoded] { [] }

        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            throw Self.makeError(message: "This message is only expected to be sent from the protocol manager to the engine, and never received by the protocol manager")
        }

    }

}
