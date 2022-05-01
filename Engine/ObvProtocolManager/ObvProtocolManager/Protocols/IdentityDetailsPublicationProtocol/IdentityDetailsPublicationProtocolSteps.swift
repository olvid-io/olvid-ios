/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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
import ObvMetaManager
import ObvCrypto
import OlvidUtils


// MARK: - Protocol Steps

extension IdentityDetailsPublicationProtocol {
    
    enum StepId: Int, ConcreteProtocolStepId, CaseIterable {
        
        case StartPhotoUpload = 0
        case ReceiveDetails = 1
        case SendDetails = 2
        
        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
            
            switch self {
                
            case .StartPhotoUpload:
                let step = StartPhotoUploadStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .ReceiveDetails:
                let step = ReceiveDetailsStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .SendDetails:
                let step = SendDetailsStep(from: concreteProtocol, and: receivedMessage)
                return step
            }
        }
    }

    // MARK: - StartPhotoUploadStep
    
    final class StartPhotoUploadStep: ProtocolStep, TypedConcreteProtocolStep {
     
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitialMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: IdentityDetailsPublicationProtocol.InitialMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: IdentityDetailsPublicationProtocol.logCategory)

            let version = receivedMessage.version
            
            // Get the current published owned identity details
            
            var ownedIdentityDetailsElements: IdentityDetailsElements
            let photoURL: URL?
            do {
                (ownedIdentityDetailsElements, photoURL) = try identityDelegate.getPublishedIdentityDetailsOfOwnedIdentity(ownedIdentity, within: obvContext)
            } catch {
                os_log("Could not get owned identity details", log: log, type: .fault)
                return CancelledState()
            }
            
            // Make sure the owned identity details correspond to the version we have to publish
            
            guard ownedIdentityDetailsElements.version == version else {
                os_log("The current version of the published identity details in DB does not correspond to the one to publish", log: log, type: .error)
                return CancelledState()
            }
            
            
            // If required, upload a photo

            if let photoURL = photoURL, ownedIdentityDetailsElements.photoServerKeyAndLabel == nil {

                let photoServerKeyAndLabel = PhotoServerKeyAndLabel.generate(with: prng)
                do {
                    ownedIdentityDetailsElements = try identityDelegate.setPhotoServerKeyAndLabelForPublishedIdentityDetailsOfOwnedIdentity(ownedIdentity, withPhotoServerKeyAndLabel: photoServerKeyAndLabel, within: obvContext)
                } catch {
                    os_log("Could not set server key and label", log: log, type: .fault)
                    return CancelledState()
                }
                
                assert(photoServerKeyAndLabel == ownedIdentityDetailsElements.photoServerKeyAndLabel)

                // Send the encrypted photo
                
                let coreMessage = getCoreMessage(for: .ServerQuery(ownedIdentity: ownedIdentity))
                let concreteMessage = ServerPutPhotoMessage.init(coreProtocolMessage: coreMessage)
                let serverQueryType = ObvChannelServerQueryMessageToSend.QueryType.putUserData(label: photoServerKeyAndLabel.label, dataURL: photoURL, dataKey: photoServerKeyAndLabel.key)
                guard let messageToSend = concreteMessage.generateObvChannelServerQueryMessageToSend(serverQueryType: serverQueryType) else { return nil }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)

                return UploadingPhotoState(ownedIdentityDetailsElements: ownedIdentityDetailsElements)
                
            } else {
                
                // We have no photo to upload so we can send the detail now
                
                guard let contactIdentites = try? identityDelegate.getContactsOfOwnedIdentity(ownedIdentity, within: obvContext) else {
                    os_log("Could not get contacts of owned identity", log: log, type: .fault)
                    return CancelledState()
                }
                
                // Instead of sending one message for all contacts, we send one message per contact (for privacy reasons).
                
                for contactIndentity in contactIdentites {
                    
                    let coreMessage = getCoreMessage(for: ObvChannelSendChannelType.AllConfirmedObliviousChannelsWithContactIdentities(contactIdentities: [contactIndentity], fromOwnedIdentity: ownedIdentity))
                    let concreteMessage = SendDetailsMessage(coreProtocolMessage: coreMessage,
                                                             contactIdentityDetailsElements: ownedIdentityDetailsElements)
                    guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                    do {
                        _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                    } catch {
                        os_log("Could not post SendDetailsMessage in StartPhotoUploadStep to the identity %@", log: log, type: .error, contactIndentity.debugDescription)
                    }
            
                }
                
                return DetailsSentState()
                
            }
        }
    }

    
    // MARK: - SendDetailsStep
    
    final class SendDetailsStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: UploadingPhotoState
        let receivedMessage: ServerPutPhotoMessage
        
        init?(startState: UploadingPhotoState, receivedMessage: IdentityDetailsPublicationProtocol.ServerPutPhotoMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: IdentityDetailsPublicationProtocol.logCategory)
            
            let ownedIdentityDetailsElements = startState.ownedIdentityDetailsElements
            
            guard let contactIdentites = try? identityDelegate.getContactsOfOwnedIdentity(ownedIdentity, within: obvContext) else {
                os_log("Could not get contacts of owned identity", log: log, type: .fault)
                return CancelledState()
            }
            
            // We send one message per contact instead of one message to all contacts
            
            for contactIdentity in contactIdentites {
                
                let coreMessage = getCoreMessage(for: ObvChannelSendChannelType.AllConfirmedObliviousChannelsWithContactIdentities(contactIdentities: [contactIdentity], fromOwnedIdentity: ownedIdentity))
                let concreteMessage = SendDetailsMessage(coreProtocolMessage: coreMessage,
                                                         contactIdentityDetailsElements: ownedIdentityDetailsElements)
                guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                do {
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Could not post SendDetailsMessage in SendDetailsStep to identity %@", log: log, type: .error, contactIdentity.debugDescription)
                }

            }
            
            
            return DetailsSentState()
            
        }

        
    }

    // MARK: - ReceiveDetailsStep
    
    final class ReceiveDetailsStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: SendDetailsMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: IdentityDetailsPublicationProtocol.SendDetailsMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AnyObliviousChannel(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: IdentityDetailsPublicationProtocol.logCategory)

            let contactIdentityDetailsElements = receivedMessage.contactIdentityDetailsElements

            guard let contactIdentity = receivedMessage.receptionChannelInfo?.getRemoteIdentity() else {
                os_log("Could not determine remote identity", log: log, type: .fault)
                return CancelledState()
            }
            
            // Download the photo if required
            
            if contactIdentityDetailsElements.photoServerKeyAndLabel != nil {
                
                let currentContactIdentityDetailsElements: IdentityDetailsElements?
                let currentPhotoURL: URL?
                
                do {
                    if let currentValues = try identityDelegate.getPublishedIdentityDetailsOfContactIdentity(contactIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext) {
                        currentContactIdentityDetailsElements = currentValues.contactIdentityDetailsElements
                        currentPhotoURL = currentValues.photoURL
                    } else {
                        currentContactIdentityDetailsElements = nil
                        currentPhotoURL = nil
                    }
                } catch {
                    os_log("Could not get identity details of contact identity", log: log, type: .fault)
                    return CancelledState()
                }
                
                if currentPhotoURL == nil || currentContactIdentityDetailsElements?.photoServerKeyAndLabel?.label != contactIdentityDetailsElements.photoServerKeyAndLabel?.label || currentContactIdentityDetailsElements?.photoServerKeyAndLabel?.key.data != contactIdentityDetailsElements.photoServerKeyAndLabel?.key.data {
                    
                    // Launch a child protocol instance for downloading the photo. To do so, we post an appropriate message on the loopback channel. In this particular case, we do not need to "link" this protocol to the current protocol.
                    
                    let childProtocolInstanceUid = UID.gen(with: prng)
                    let coreMessage = getCoreMessageForOtherLocalProtocol(otherCryptoProtocolId: .DownloadIdentityPhoto,
                                                                          otherProtocolInstanceUid: childProtocolInstanceUid)
                    let childProtocolInitialMessage = DownloadIdentityPhotoChildProtocol.InitialMessage(
                        coreProtocolMessage: coreMessage,
                        contactIdentity: contactIdentity,
                        contactIdentityDetailsElements: contactIdentityDetailsElements)
                    guard let messageToSend = childProtocolInitialMessage.generateObvChannelProtocolMessageToSend(with: prng) else { throw NSError() }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
            }
            
            // Store the published contact details
            
            do {
                try identityDelegate.updatePublishedIdentityDetailsOfContactIdentity(contactIdentity, ofOwnedIdentity: ownedIdentity, with: contactIdentityDetailsElements, allowVersionDowngrade: false, within: obvContext)
            } catch {
                os_log("Could not update contact identity details elements", log: log, type: .fault)
                return CancelledState()
            }
            
            return DetailsReceivedState()
            
        }

    }
    
}
