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
import ObvMetaManager


/// When the app receives an encrypted notification, it requests decryption from the engine.
/// If the notification is an encrypted user message (delivered via APNs) and the decrypted content
/// is a protocol message, this extension simplifies the process of creating an ObvProtocolMessage
/// instance based on the decrypted ReceivedProtocolMessage.
public extension ObvProtocolMessage {
    
    init(receivedProtocolMessage: ReceivedProtocolMessage) throws(ObvError) {
        
        guard let message = GenericReceivedProtocolMessage(with: receivedProtocolMessage.protocolReceivedMessage) else {
            assertionFailure()
            throw .couldNotParseReceivedProtocolMessage
        }
        
        switch message.cryptoProtocolId {
            
        case .ContactMutualIntroduction:
            
            guard let messageId = ContactMutualIntroductionProtocol.MessageId(rawValue: message.protocolMessageRawId) else {
                throw .couldNotParseMessageId
            }
            
            switch messageId {
                
            case .mediatorInvitation:
                
                let specificProtocolMessage: ContactMutualIntroductionProtocol.MediatorInvitationMessage
                do {
                    specificProtocolMessage = try ContactMutualIntroductionProtocol.MediatorInvitationMessage(withGenericReceivedProtocolMessage: message)
                } catch {
                    throw .specificProtocolMessageInitilizationError(error: error)
                }
                
                guard let remoteIdentity = receivedProtocolMessage.protocolReceivedMessage.receptionChannelInfo.getRemoteIdentity() else {
                    throw .couldNotDetermineRemoteIdentity
                }
                
                let remoteCryptoId = ObvCryptoId(cryptoIdentity: remoteIdentity)
                let ownedCryptoId = ObvCryptoId(cryptoIdentity: receivedProtocolMessage.protocolReceivedMessage.messageId.ownedCryptoIdentity)
                let introducedCryptoId = ObvCryptoId(cryptoIdentity: specificProtocolMessage.contactIdentity)
                let introducedIdentityCoreDetails = specificProtocolMessage.contactIdentityCoreDetails
                
                let mediator = ObvContactIdentifier(contactCryptoId: remoteCryptoId, ownedCryptoId: ownedCryptoId)
                self = .mutualIntroduction(mediator: mediator, introducedIdentity: introducedCryptoId, introducedIdentityCoreDetails: introducedIdentityCoreDetails)

            case .initial,
                    .acceptMediatorInviteDialog,
                    .propagateConfirmation,
                    .notifyContactOfAcceptedInvitation,
                    .propagateContactNotificationOfAcceptedInvitation,
                    .ack,
                    .dialogInformative,
                    .trustLevelIncreased,
                    .propagatedInitial:
                
                throw .unexpectedMessageId
                
            }
            
        case .contactDeviceDiscovery,
                .channelCreationWithContactDevice,
                .deviceDiscoveryForRemoteIdentity,
                .identityDetailsPublication,
                .downloadIdentityPhoto,
                .groupInvitation,
                .groupManagement,
                .contactManagement,
                .trustEstablishmentWithSAS,
                .trustEstablishmentWithMutualScan,
                .fullRatchet,
                .downloadGroupPhoto,
                .keycloakContactAddition,
                .contactCapabilitiesDiscovery,
                .oneToOneContactInvitation,
                .groupV2,
                .downloadGroupV2Photo,
                .ownedIdentityDeletionProtocol,
                .ownedDeviceDiscovery,
                .channelCreationWithOwnedDevice,
                .keycloakBindingAndUnbinding,
                .ownedDeviceManagement,
                .synchronization,
                .ownedIdentityTransfer:

            throw .unexpectedCryptoProtocolId
            
        }
        
        
    }
    
    enum ObvError: Error {
        case couldNotParseReceivedProtocolMessage
        case unexpectedCryptoProtocolId
        case couldNotParseMessageId
        case unexpectedMessageId
        case specificProtocolMessageInitilizationError(error: Error)
        case couldNotDetermineRemoteIdentity
    }
    
}
