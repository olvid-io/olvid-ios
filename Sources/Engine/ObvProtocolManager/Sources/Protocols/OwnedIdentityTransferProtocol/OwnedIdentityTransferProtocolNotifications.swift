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
import ObvMetaManager
import ObvCrypto
import ObvTypes


struct OwnedIdentityTransferProtocolNotification {
    
    struct NotificationDescriptor<Payload> {
        let name: Notification.Name
        let convert: (Notification) -> Payload
    }
    
    enum KindForObserving {
        case sourceDisplaySessionNumber(payload: (SourceDisplaySessionNumber.Payload) -> Void)
        case ownedIdentityTransferProtocolFailed(payload: (OwnedIdentityTransferProtocolFailed.Payload) -> Void)
        case userEnteredIncorrectTransferSessionNumber(payload: (UserEnteredIncorrectTransferSessionNumber.Payload) -> Void)
        case sasIsAvailable(payload: (SasIsAvailable.Payload) -> Void)
        case processingReceivedSnapshotOntargetDevice(payload: (ProcessingReceivedSnapshotOntargetDevice.Payload) -> Void)
        case successfulTransferOnTargetDevice(payload: (SuccessfulTransferOnTargetDevice.Payload) -> Void)
        case waitingForSASOnSourceDevice(payload: (WaitingForSASOnSourceDevice.Payload) -> Void)
        case protocolFinishedSuccessfullyOnSourceDeviceAsSnapshotSentWasSent(payload: (ProtocolFinishedSuccessfullyOnSourceDeviceAsSnapshotSentWasSent.Payload) -> Void)
        case keycloakAuthenticationRequiredAsProfileIsTransferRestricted(payload: (KeycloakAuthenticationRequiredAsProfileIsTransferRestricted.Payload) -> Void)
    }
    
    enum KindForPosting {
        case sourceDisplaySessionNumber(payload: SourceDisplaySessionNumber.Payload)
        case ownedIdentityTransferProtocolFailed(payload: OwnedIdentityTransferProtocolFailed.Payload)
        case userEnteredIncorrectTransferSessionNumber(payload: UserEnteredIncorrectTransferSessionNumber.Payload)
        case sasIsAvailable(payload: SasIsAvailable.Payload)
        case processingReceivedSnapshotOntargetDevice(payload: ProcessingReceivedSnapshotOntargetDevice.Payload)
        case successfulTransferOnTargetDevice(payload: SuccessfulTransferOnTargetDevice.Payload)
        case waitingForSASOnSourceDevice(payload: WaitingForSASOnSourceDevice.Payload)
        case protocolFinishedSuccessfullyOnSourceDeviceAsSnapshotSentWasSent(payload: ProtocolFinishedSuccessfullyOnSourceDeviceAsSnapshotSentWasSent.Payload)
        case keycloakAuthenticationRequiredAsProfileIsTransferRestricted(payload: KeycloakAuthenticationRequiredAsProfileIsTransferRestricted.Payload)
    }

        
    struct SourceDisplaySessionNumber {
        
        fileprivate static let name: Notification.Name = .init("io.olvid.protocolmanager.OwnedIdentityTransferProtocolNotification.SourceDisplaySessionNumber")
        
        struct Payload {
            let protocolInstanceUID: UID
            let sessionNumber: ObvOwnedIdentityTransferSessionNumber
            enum Key: String {
                case protocolInstanceUID = "protocolInstanceUID"
                case sessionNumber = "sessionNumber"
            }
        }
        
        let payload: Payload

    }
    
    
    struct OwnedIdentityTransferProtocolFailed {
        
        fileprivate static let name: Notification.Name = .init("io.olvid.protocolmanager.OwnedIdentityTransferProtocolNotification.OwnedIdentityTransferProtocolFailed")
        
        struct Payload {
            let ownedCryptoIdentity: ObvCryptoIdentity
            let protocolInstanceUID: UID
            let error: Error
            enum Key: String {
                case ownedCryptoIdentity = "ownedCryptoIdentity"
                case protocolInstanceUID = "protocolInstanceUID"
                case error = "Error"
            }
        }
        
        let payload: Payload

    }
 
    
    struct UserEnteredIncorrectTransferSessionNumber {
        
        fileprivate static let name: Notification.Name = .init("io.olvid.protocolmanager.OwnedIdentityTransferProtocolNotification.UserEnteredIncorrectTransferSessionNumber")
        
        struct Payload {
            let protocolInstanceUID: UID
            enum Key: String {
                case protocolInstanceUID = "protocolInstanceUID"
            }
        }
        
        let payload: Payload

    }
    
    
    struct SasIsAvailable {
        
        fileprivate static let name: Notification.Name = .init("io.olvid.protocolmanager.OwnedIdentityTransferProtocolNotification.SasIsAvailable")
        
        struct Payload {
            let protocolInstanceUID: UID
            let sas: ObvOwnedIdentityTransferSas
            enum Key: String {
                case protocolInstanceUID = "protocolInstanceUID"
                case sas = "sas"
            }
        }
        
        let payload: Payload

    }

    
    struct ProcessingReceivedSnapshotOntargetDevice {
        
        fileprivate static let name: Notification.Name = .init("io.olvid.protocolmanager.OwnedIdentityTransferProtocolNotification.ProcessingReceivedSnapshotOntargetDevice")
        
        struct Payload {
            let protocolInstanceUID: UID
            enum Key: String {
                case protocolInstanceUID = "protocolInstanceUID"
            }
        }
        
        let payload: Payload

    }
    
    
    struct SuccessfulTransferOnTargetDevice {
        
        fileprivate static let name: Notification.Name = .init("io.olvid.protocolmanager.OwnedIdentityTransferProtocolNotification.SuccessfulTransferOnTargetDevice")
        
        struct Payload {
            let protocolInstanceUID: UID
            let transferredOwnedCryptoId: ObvCryptoId
            let postTransferError: Error?
            enum Key: String {
                case protocolInstanceUID = "protocolInstanceUID"
                case transferredOwnedCryptoId = "transferredOwnedCryptoId"
                case postTransferError = "postTransferError"
            }
        }
        
        let payload: Payload

    }

    
    struct WaitingForSASOnSourceDevice {
        
        fileprivate static let name: Notification.Name = .init("io.olvid.protocolmanager.OwnedIdentityTransferProtocolNotification.WaitingForSASOnSourceDevice")
        
        struct Payload {
            let protocolInstanceUID: UID
            let sasExpectedOnInput: ObvOwnedIdentityTransferSas
            let targetDeviceName: String
            enum Key: String {
                case protocolInstanceUID = "protocolInstanceUID"
                case sasExpectedOnInput = "sasExpectedOnInput"
                case targetDeviceName = "targetDeviceName"
            }
        }
        
        let payload: Payload

    }

    
    struct ProtocolFinishedSuccessfullyOnSourceDeviceAsSnapshotSentWasSent {
        
        fileprivate static let name: Notification.Name = .init("io.olvid.protocolmanager.OwnedIdentityTransferProtocolNotification.ProtocolFinishedSuccessfullyOnSourceDeviceAsSnapshotSentWasSent")
        
        struct Payload {
            let protocolInstanceUID: UID
            enum Key: String {
                case protocolInstanceUID = "protocolInstanceUID"
            }
        }
        
        let payload: Payload

    }
    
    
    struct KeycloakAuthenticationRequiredAsProfileIsTransferRestricted {
        
        fileprivate static let name: Notification.Name = .init("io.olvid.protocolmanager.OwnedIdentityTransferProtocolNotification.KeycloakAuthenticationRequiredAsProfileIsTransferRestricted")

        struct Payload {
            let protocolInstanceUID: UID
            let keycloakConfiguration: ObvKeycloakConfiguration
            let keycloakTransferProofElements: ObvKeycloakTransferProofElements
            let ownedCryptoIdentity: ObvCryptoIdentity
            enum Key: String {
                case protocolInstanceUID = "protocolInstanceUID"
                case keycloakConfiguration = "keycloakConfiguration"
                case ownedCryptoIdentity = "ownedCryptoIdentity"
                case keycloakTransferProofElements = "keycloakTransferProofElements"
            }
        }
        
        let payload: Payload

    }
    
}


fileprivate extension OwnedIdentityTransferProtocolNotification.SourceDisplaySessionNumber.Payload {
    
    init(notification: Notification) {
        let Key = OwnedIdentityTransferProtocolNotification.SourceDisplaySessionNumber.Payload.Key.self
        self.protocolInstanceUID = notification.userInfo![Key.protocolInstanceUID.rawValue] as! UID
        self.sessionNumber = notification.userInfo![Key.sessionNumber.rawValue] as! ObvOwnedIdentityTransferSessionNumber
    }
    
}


fileprivate extension OwnedIdentityTransferProtocolNotification.OwnedIdentityTransferProtocolFailed.Payload {
    
    init(notification: Notification) {
        let Key = OwnedIdentityTransferProtocolNotification.OwnedIdentityTransferProtocolFailed.Payload.Key.self
        self.ownedCryptoIdentity = notification.userInfo![Key.ownedCryptoIdentity.rawValue] as! ObvCryptoIdentity
        self.protocolInstanceUID = notification.userInfo![Key.protocolInstanceUID.rawValue] as! UID
        self.error = notification.userInfo![Key.error.rawValue] as! Error
    }
    
}


fileprivate extension OwnedIdentityTransferProtocolNotification.UserEnteredIncorrectTransferSessionNumber.Payload {
    
    init(notification: Notification) {
        let Key = OwnedIdentityTransferProtocolNotification.UserEnteredIncorrectTransferSessionNumber.Payload.Key.self
        self.protocolInstanceUID = notification.userInfo![Key.protocolInstanceUID.rawValue] as! UID
    }
    
}


fileprivate extension OwnedIdentityTransferProtocolNotification.SasIsAvailable.Payload {
    
    init(notification: Notification) {
        let Key = OwnedIdentityTransferProtocolNotification.SasIsAvailable.Payload.Key.self
        self.protocolInstanceUID = notification.userInfo![Key.protocolInstanceUID.rawValue] as! UID
        self.sas = notification.userInfo![Key.sas.rawValue] as! ObvOwnedIdentityTransferSas
    }
    
}


fileprivate extension OwnedIdentityTransferProtocolNotification.ProcessingReceivedSnapshotOntargetDevice.Payload {
    
    init(notification: Notification) {
        let Key = OwnedIdentityTransferProtocolNotification.SasIsAvailable.Payload.Key.self
        self.protocolInstanceUID = notification.userInfo![Key.protocolInstanceUID.rawValue] as! UID
    }
    
}


fileprivate extension OwnedIdentityTransferProtocolNotification.SuccessfulTransferOnTargetDevice.Payload {
    
    init(notification: Notification) {
        let Key = OwnedIdentityTransferProtocolNotification.SuccessfulTransferOnTargetDevice.Payload.Key.self
        self.protocolInstanceUID = notification.userInfo![Key.protocolInstanceUID.rawValue] as! UID
        self.transferredOwnedCryptoId = notification.userInfo![Key.transferredOwnedCryptoId.rawValue] as! ObvCryptoId
        self.postTransferError = notification.userInfo![Key.postTransferError.rawValue] as? Error
    }
    
}


fileprivate extension OwnedIdentityTransferProtocolNotification.WaitingForSASOnSourceDevice.Payload {
    
    init(notification: Notification) {
        let Key = OwnedIdentityTransferProtocolNotification.WaitingForSASOnSourceDevice.Payload.Key.self
        self.protocolInstanceUID = notification.userInfo![Key.protocolInstanceUID.rawValue] as! UID
        self.sasExpectedOnInput = notification.userInfo![Key.sasExpectedOnInput.rawValue] as! ObvOwnedIdentityTransferSas
        self.targetDeviceName = notification.userInfo![Key.targetDeviceName.rawValue] as! String
    }
    
}


fileprivate extension OwnedIdentityTransferProtocolNotification.ProtocolFinishedSuccessfullyOnSourceDeviceAsSnapshotSentWasSent.Payload {
    
    init(notification: Notification) {
        let Key = OwnedIdentityTransferProtocolNotification.ProtocolFinishedSuccessfullyOnSourceDeviceAsSnapshotSentWasSent.Payload.Key.self
        self.protocolInstanceUID = notification.userInfo![Key.protocolInstanceUID.rawValue] as! UID
    }
    
}


fileprivate extension OwnedIdentityTransferProtocolNotification.KeycloakAuthenticationRequiredAsProfileIsTransferRestricted.Payload {
    
    init(notification: Notification) {
        let Key = OwnedIdentityTransferProtocolNotification.KeycloakAuthenticationRequiredAsProfileIsTransferRestricted.Payload.Key.self
        self.protocolInstanceUID = notification.userInfo![Key.protocolInstanceUID.rawValue] as! UID
        self.keycloakConfiguration = notification.userInfo![Key.keycloakConfiguration.rawValue] as! ObvKeycloakConfiguration
        self.ownedCryptoIdentity = notification.userInfo![Key.ownedCryptoIdentity.rawValue] as! ObvCryptoIdentity
        self.keycloakTransferProofElements = notification.userInfo![Key.keycloakTransferProofElements.rawValue] as! ObvKeycloakTransferProofElements
    }

}


fileprivate extension Notification {
    
    init(payload: OwnedIdentityTransferProtocolNotification.SourceDisplaySessionNumber.Payload) {
        let Type = OwnedIdentityTransferProtocolNotification.SourceDisplaySessionNumber.self
        let userInfo: [String : Any] = [
            Type.Payload.Key.protocolInstanceUID.rawValue: payload.protocolInstanceUID,
            Type.Payload.Key.sessionNumber.rawValue: payload.sessionNumber,
        ]
        self.init(name: Type.name, object: nil, userInfo: userInfo)
    }

    
    init(payload: OwnedIdentityTransferProtocolNotification.OwnedIdentityTransferProtocolFailed.Payload) {
        let Type = OwnedIdentityTransferProtocolNotification.OwnedIdentityTransferProtocolFailed.self
        let userInfo: [String : Any] = [
            Type.Payload.Key.ownedCryptoIdentity.rawValue: payload.ownedCryptoIdentity,
            Type.Payload.Key.protocolInstanceUID.rawValue: payload.protocolInstanceUID,
            Type.Payload.Key.error.rawValue: payload.error,
        ]
        self.init(name: Type.name, object: nil, userInfo: userInfo)
    }

    
    init(payload: OwnedIdentityTransferProtocolNotification.UserEnteredIncorrectTransferSessionNumber.Payload) {
        let Type = OwnedIdentityTransferProtocolNotification.UserEnteredIncorrectTransferSessionNumber.self
        let userInfo: [String : Any] = [
            Type.Payload.Key.protocolInstanceUID.rawValue: payload.protocolInstanceUID,
        ]
        self.init(name: Type.name, object: nil, userInfo: userInfo)
    }

    
    init(payload: OwnedIdentityTransferProtocolNotification.SasIsAvailable.Payload) {
        let Type = OwnedIdentityTransferProtocolNotification.SasIsAvailable.self
        let userInfo: [String : Any] = [
            Type.Payload.Key.protocolInstanceUID.rawValue: payload.protocolInstanceUID,
            Type.Payload.Key.sas.rawValue: payload.sas,
        ]
        self.init(name: Type.name, object: nil, userInfo: userInfo)
    }

    
    init(payload: OwnedIdentityTransferProtocolNotification.ProcessingReceivedSnapshotOntargetDevice.Payload) {
        let Type = OwnedIdentityTransferProtocolNotification.ProcessingReceivedSnapshotOntargetDevice.self
        let userInfo: [String : Any] = [
            Type.Payload.Key.protocolInstanceUID.rawValue: payload.protocolInstanceUID,
        ]
        self.init(name: Type.name, object: nil, userInfo: userInfo)
    }

    
    init(payload: OwnedIdentityTransferProtocolNotification.SuccessfulTransferOnTargetDevice.Payload) {
        let Type = OwnedIdentityTransferProtocolNotification.SuccessfulTransferOnTargetDevice.self
        let userInfo: [String : Any] = [
            Type.Payload.Key.protocolInstanceUID.rawValue: payload.protocolInstanceUID,
            Type.Payload.Key.transferredOwnedCryptoId.rawValue: payload.transferredOwnedCryptoId,
            Type.Payload.Key.postTransferError.rawValue: payload.postTransferError as Any,
        ]
        self.init(name: Type.name, object: nil, userInfo: userInfo)
    }

    
    init(payload: OwnedIdentityTransferProtocolNotification.WaitingForSASOnSourceDevice.Payload) {
        let Type = OwnedIdentityTransferProtocolNotification.WaitingForSASOnSourceDevice.self
        let userInfo: [String : Any] = [
            Type.Payload.Key.protocolInstanceUID.rawValue: payload.protocolInstanceUID,
            Type.Payload.Key.sasExpectedOnInput.rawValue: payload.sasExpectedOnInput,
            Type.Payload.Key.targetDeviceName.rawValue: payload.targetDeviceName,
        ]
        self.init(name: Type.name, object: nil, userInfo: userInfo)
    }

    
    init(payload: OwnedIdentityTransferProtocolNotification.ProtocolFinishedSuccessfullyOnSourceDeviceAsSnapshotSentWasSent.Payload) {
        let Type = OwnedIdentityTransferProtocolNotification.ProtocolFinishedSuccessfullyOnSourceDeviceAsSnapshotSentWasSent.self
        let userInfo: [String : Any] = [
            Type.Payload.Key.protocolInstanceUID.rawValue: payload.protocolInstanceUID,
        ]
        self.init(name: Type.name, object: nil, userInfo: userInfo)
    }

    init(payload: OwnedIdentityTransferProtocolNotification.KeycloakAuthenticationRequiredAsProfileIsTransferRestricted.Payload) {
        let Type = OwnedIdentityTransferProtocolNotification.KeycloakAuthenticationRequiredAsProfileIsTransferRestricted.self
        let userInfo: [String : Any] = [
            Type.Payload.Key.protocolInstanceUID.rawValue: payload.protocolInstanceUID,
            Type.Payload.Key.keycloakConfiguration.rawValue: payload.keycloakConfiguration,
            Type.Payload.Key.ownedCryptoIdentity.rawValue: payload.ownedCryptoIdentity,
            Type.Payload.Key.keycloakTransferProofElements.rawValue: payload.keycloakTransferProofElements,
        ]
        self.init(name: Type.name, object: nil, userInfo: userInfo)
    }

}


extension ObvNotificationDelegate {
    
    private func addObserverOfOwnedIdentityTransferProtocolNotification<Payload>(descriptor: OwnedIdentityTransferProtocolNotification.NotificationDescriptor<Payload>, using block: @escaping (Payload) -> Void) -> NSObjectProtocol {
        let token = addObserver(forName: descriptor.name, queue: nil) { notification in
            let payload = descriptor.convert(notification)
            Task {
                block(payload)
            }
        }
        return token
    }

    
    func addObserverOfOwnedIdentityTransferProtocolNotification(_ kind: OwnedIdentityTransferProtocolNotification.KindForObserving) -> NSObjectProtocol {
        switch kind {
        case .sourceDisplaySessionNumber(payload: let payload):
            let Type = OwnedIdentityTransferProtocolNotification.SourceDisplaySessionNumber.self
            let notificationDescriptor: OwnedIdentityTransferProtocolNotification.NotificationDescriptor = .init(name: Type.name, convert: Type.Payload.init)
            return addObserverOfOwnedIdentityTransferProtocolNotification(descriptor: notificationDescriptor, using: payload)
        case .ownedIdentityTransferProtocolFailed(payload: let payload):
            let Type = OwnedIdentityTransferProtocolNotification.OwnedIdentityTransferProtocolFailed.self
            let notificationDescriptor: OwnedIdentityTransferProtocolNotification.NotificationDescriptor = .init(name: Type.name, convert: Type.Payload.init)
            return addObserverOfOwnedIdentityTransferProtocolNotification(descriptor: notificationDescriptor, using: payload)
        case .userEnteredIncorrectTransferSessionNumber(payload: let payload):
            let Type = OwnedIdentityTransferProtocolNotification.UserEnteredIncorrectTransferSessionNumber.self
            let notificationDescriptor: OwnedIdentityTransferProtocolNotification.NotificationDescriptor = .init(name: Type.name, convert: Type.Payload.init)
            return addObserverOfOwnedIdentityTransferProtocolNotification(descriptor: notificationDescriptor, using: payload)
        case .sasIsAvailable(payload: let payload):
            let Type = OwnedIdentityTransferProtocolNotification.SasIsAvailable.self
            let notificationDescriptor: OwnedIdentityTransferProtocolNotification.NotificationDescriptor = .init(name: Type.name, convert: Type.Payload.init)
            return addObserverOfOwnedIdentityTransferProtocolNotification(descriptor: notificationDescriptor, using: payload)
        case .processingReceivedSnapshotOntargetDevice(payload: let payload):
            let Type = OwnedIdentityTransferProtocolNotification.ProcessingReceivedSnapshotOntargetDevice.self
            let notificationDescriptor: OwnedIdentityTransferProtocolNotification.NotificationDescriptor = .init(name: Type.name, convert: Type.Payload.init)
            return addObserverOfOwnedIdentityTransferProtocolNotification(descriptor: notificationDescriptor, using: payload)
        case .successfulTransferOnTargetDevice(payload: let payload):
            let Type = OwnedIdentityTransferProtocolNotification.SuccessfulTransferOnTargetDevice.self
            let notificationDescriptor: OwnedIdentityTransferProtocolNotification.NotificationDescriptor = .init(name: Type.name, convert: Type.Payload.init)
            return addObserverOfOwnedIdentityTransferProtocolNotification(descriptor: notificationDescriptor, using: payload)
        case .waitingForSASOnSourceDevice(payload: let payload):
            let Type = OwnedIdentityTransferProtocolNotification.WaitingForSASOnSourceDevice.self
            let notificationDescriptor: OwnedIdentityTransferProtocolNotification.NotificationDescriptor = .init(name: Type.name, convert: Type.Payload.init)
            return addObserverOfOwnedIdentityTransferProtocolNotification(descriptor: notificationDescriptor, using: payload)
        case .protocolFinishedSuccessfullyOnSourceDeviceAsSnapshotSentWasSent(payload: let payload):
            let Type = OwnedIdentityTransferProtocolNotification.ProtocolFinishedSuccessfullyOnSourceDeviceAsSnapshotSentWasSent.self
            let notificationDescriptor: OwnedIdentityTransferProtocolNotification.NotificationDescriptor = .init(name: Type.name, convert: Type.Payload.init)
            return addObserverOfOwnedIdentityTransferProtocolNotification(descriptor: notificationDescriptor, using: payload)
        case .keycloakAuthenticationRequiredAsProfileIsTransferRestricted(payload: let payload):
            let Type = OwnedIdentityTransferProtocolNotification.KeycloakAuthenticationRequiredAsProfileIsTransferRestricted.self
            let notificationDescriptor: OwnedIdentityTransferProtocolNotification.NotificationDescriptor = .init(name: Type.name, convert: Type.Payload.init)
            return addObserverOfOwnedIdentityTransferProtocolNotification(descriptor: notificationDescriptor, using: payload)
        }
    }

    
    func postOwnedIdentityTransferProtocolNotification(_ kind: OwnedIdentityTransferProtocolNotification.KindForPosting) {
        Task {
            let notification: Notification
            switch kind {
            case .sourceDisplaySessionNumber(payload: let payload):
                notification = .init(payload: payload)
            case .ownedIdentityTransferProtocolFailed(payload: let payload):
                notification = .init(payload: payload)
            case .userEnteredIncorrectTransferSessionNumber(payload: let payload):
                notification = .init(payload: payload)
            case .sasIsAvailable(payload: let payload):
                notification = .init(payload: payload)
            case .processingReceivedSnapshotOntargetDevice(payload: let payload):
                notification = .init(payload: payload)
            case .successfulTransferOnTargetDevice(payload: let payload):
                notification = .init(payload: payload)
            case .waitingForSASOnSourceDevice(payload: let payload):
                notification = .init(payload: payload)
            case .protocolFinishedSuccessfullyOnSourceDeviceAsSnapshotSentWasSent(payload: let payload):
                notification = .init(payload: payload)
            case .keycloakAuthenticationRequiredAsProfileIsTransferRestricted(payload: let payload):
                notification = .init(payload: payload)
            }
            post(name: notification.name, userInfo: notification.userInfo)
        }
    }

}
