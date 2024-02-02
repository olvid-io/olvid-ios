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
import OlvidUtils
import os.log
import ObvTypes
import ObvMetaManager
import ObvCrypto


extension DeviceCapabilitiesDiscoveryProtocol {
    
    enum StepId: Int, ConcreteProtocolStepId, CaseIterable {
        
        case addOwnCapabilitiesAndSendThemToAllContactsAndOwnedDevices = 0
        case sendOwnCapabilitiesToContactDevice = 1
        case sendOwnCapabilitiesToOtherOwnedDevice = 2
        case processReceivedContactDeviceCapabilities = 3
        case processReceivedOwnedDeviceCapabilities = 4

        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
            switch self {
            case .addOwnCapabilitiesAndSendThemToAllContactsAndOwnedDevices:
                let step = AddOwnCapabilitiesAndSendThemToAllContactsAndOwnedDevicesStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .sendOwnCapabilitiesToContactDevice:
                let step = SendOwnCapabilitiesToContactDeviceStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .sendOwnCapabilitiesToOtherOwnedDevice:
                let step = SendOwnCapabilitiesToOtherOwnedDeviceStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .processReceivedContactDeviceCapabilities:
                let step = ProcessReceivedContactDeviceCapabilitiesStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .processReceivedOwnedDeviceCapabilities:
                let step = ProcessReceivedOwnedDeviceCapabilitiesStep(from: concreteProtocol, and: receivedMessage)
                return step
            }
        }

    }
     
    
    // MARK: - AddOwnCapabilitiesAndSendThemToAllContactsAndOwnedDevicesStep
    
    final class AddOwnCapabilitiesAndSendThemToAllContactsAndOwnedDevicesStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitialForAddingOwnCapabilitiesMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: InitialForAddingOwnCapabilitiesMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity, // We cannot access ownedIdentity directly at this point,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: DeviceCapabilitiesDiscoveryProtocol.logCategory)
            
            let newOwnCapabilities = receivedMessage.newOwnCapabilities

            // We add the new capabilities to the current device of the owned identity. If these capabilities already exist, do nothing and return.
            
            let previousOwnCapabilities: Set<ObvCapability>
            do {
                let currentOwnCapabilities = try identityDelegate.getCapabilitiesOfCurrentDeviceOfOwnedIdentity(ownedIdentity: ownedIdentity, within: obvContext)
                guard currentOwnCapabilities != newOwnCapabilities else {
                    os_log("The new capabilities of the current device are identical to those already known to the identity delegate. There is nothing left to do, we finish this protocol.", log: log, type: .info)
                    return FinishedState()
                }
                try identityDelegate.setCapabilitiesOfCurrentDeviceOfOwnedIdentity(ownedIdentity: ownedIdentity, newCapabilities: newOwnCapabilities, within: obvContext)
                previousOwnCapabilities = currentOwnCapabilities ?? Set<ObvCapability>()
            }
            
            // If the previous own capabilities did not have the oneToOneContacts capability, but the new capabilities do, we request our own OneToOne status
            // To the contact. The reason is the following: since we just added the oneToOneContacts capability, we are in the situation where we consider
            // *all* our contacts as OneToOne. But some of these contacts (who have had the oneToOneContacts capability before we did) might consider us as
            // A non-OneToOne contact. Our objective is to reconciale with these contacts. So we send a RequestOwnOneToOneStatusFromContactMessage from the
            // OneToOneContactInvitationProtocol to all our contacts. For each of our contacts, one of the following is true:
            // - The contact does not have the oneToOneContacts capability, and she will discard our message.
            // - The contact has the oneToOneContacts capability and
            //   - Considers us to be OneToOne too, or invited us to be OneToOne. In that case, she will answer with a OneToOneResponseMessage (with invitationAccepted=true).
            //   - Considers us to be non-OneToOne. In that case, she will anser with a OneToOneResponseMessage (with invitationAccepted=false), that
            //     We will process in the AliceProcessesUnexpectedBobResponseStep, where we will downgrade the contact.
            
            if !previousOwnCapabilities.contains(.oneToOneContacts) && newOwnCapabilities.contains(.oneToOneContacts) {
                let allContactIdentities = try identityDelegate.getContactsOfOwnedIdentity(ownedIdentity, within: obvContext)
                let channel = ObvChannelSendChannelType.Local(ownedIdentity: ownedIdentity)
                let newProtocolInstanceUid = UID.gen(with: prng)
                let coreMessage = CoreProtocolMessage(channelType: channel,
                                                      cryptoProtocolId: .oneToOneContactInvitation,
                                                      protocolInstanceUid: newProtocolInstanceUid)
                let message = OneToOneContactInvitationProtocol.InitialOneToOneStatusSyncRequestMessage(coreProtocolMessage: coreMessage, contactsToSync: allContactIdentities)
                guard let messageToSend = message.generateObvChannelProtocolMessageToSend(with: prng) else {
                    assertionFailure()
                    throw DeviceCapabilitiesDiscoveryProtocol.makeError(message: "Implementation error")
                }
                do {
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Failed to request our own OneToOne status to our contact", log: log, type: .fault)
                    throw error
                }
            }
            
            // We send all the capabilities of the current device of the owned identity to all its contact.

            do {
                let contactIdentites = try identityDelegate.getContactsOfOwnedIdentity(ownedIdentity, within: obvContext)
                if !contactIdentites.isEmpty {
                    let channel = ObvChannelSendChannelType.AllConfirmedObliviousChannelsWithContactIdentities(contactIdentities: contactIdentites, fromOwnedIdentity: ownedIdentity)
                    let coreMessage = getCoreMessage(for: channel)
                    let concreteMessage = OwnCapabilitiesToContactMessage(coreProtocolMessage: coreMessage,
                                                                          ownCapabilities: newOwnCapabilities,
                                                                          isReponse: false)
                    guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        assertionFailure()
                        throw DeviceCapabilitiesDiscoveryProtocol.makeError(message: "Implementation error")
                    }
                    do {
                        _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                    } catch {
                        os_log("Failed to inform our contacts of the change of the current device new capabilities (2): %{public}@", log: log, type: .fault, error.localizedDescription)
                        throw error
                    }
                }
            }
            
            // We send all the capabilities of the current device to the other devices of the owned identity

            do {
                let numberOfOtherDevicesOfOwnedIdentity = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext).count
                if numberOfOtherDevicesOfOwnedIdentity > 0 {
                    let coreMessage = getCoreMessage(for: .AllConfirmedObliviousChannelsWithOtherDevicesOfOwnedIdentity(ownedIdentity: ownedIdentity))
                    let concreteMessage = OwnCapabilitiesToSelfMessage(coreProtocolMessage: coreMessage,
                                                                       ownCapabilities: newOwnCapabilities,
                                                                       isReponse: false)
                    guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        assertionFailure()
                        throw DeviceCapabilitiesDiscoveryProtocol.makeError(message: "Implementation error")
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                }
            }

            // Return the new state

            return FinishedState()
        }
    }

    
    // MARK: - SendOwnCapabilitiesToContactDeviceStep
    
    final class SendOwnCapabilitiesToContactDeviceStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitialSingleContactDeviceMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: InitialSingleContactDeviceMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity, // We cannot access ownedIdentity directly at this point,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: DeviceCapabilitiesDiscoveryProtocol.logCategory)
            
            let contactIdentity = receivedMessage.contactIdentity
            let contactDeviceUid = receivedMessage.contactDeviceUid
            let isResponse = receivedMessage.isResponse

            // Get a fresh set of all the capabilities of the current device of the owned identity.
            
            guard let currentCapabilities = try identityDelegate.getCapabilitiesOfCurrentDeviceOfOwnedIdentity(ownedIdentity: ownedIdentity, within: obvContext) else {
                assertionFailure()
                throw Self.makeError(message: "The owned capabilities are not known yet, which un expected at this point")
            }

            // We send all the capabilities of the current device of the owned identity to the device of the contact

            let coreMessage = getCoreMessage(for: ObvChannelSendChannelType.ObliviousChannel(to: contactIdentity, remoteDeviceUids: [contactDeviceUid], fromOwnedIdentity: ownedIdentity, necessarilyConfirmed: true))
            let concreteMessage = OwnCapabilitiesToContactMessage(coreProtocolMessage: coreMessage,
                                                                  ownCapabilities: currentCapabilities,
                                                                  isReponse: isResponse)
            guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                assertionFailure()
                throw DeviceCapabilitiesDiscoveryProtocol.makeError(message: "Implementation error")
            }
            do {
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            } catch {
                os_log("Failed to inform one of our contacts of the change of the current device new capabilities (3)", log: log, type: .fault)
                throw error
            }

            // Return the new state

            return FinishedState()
        }
    }
    
    
    // MARK: - SendOwnCapabilitiesToOtherOwnedDeviceStep
    
    final class SendOwnCapabilitiesToOtherOwnedDeviceStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitialSingleOwnedDeviceMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: InitialSingleOwnedDeviceMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity, // We cannot access ownedIdentity directly at this point,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: DeviceCapabilitiesDiscoveryProtocol.logCategory)
            
            let otherOwnedDeviceUid = receivedMessage.otherOwnedDeviceUid
            let isResponse = receivedMessage.isResponse

            // Get a fresh set of all the capabilities of the current device of the owned identity.
            
            guard let currentCapabilities = try identityDelegate.getCapabilitiesOfCurrentDeviceOfOwnedIdentity(ownedIdentity: ownedIdentity, within: obvContext) else {
                assertionFailure()
                throw Self.makeError(message: "The owned capabilities are not known yet, which un expected at this point")
            }

            // We send all the capabilities of the current device of the owned identity to the other owned device

            let coreMessage = getCoreMessage(for: ObvChannelSendChannelType.ObliviousChannel(to: ownedIdentity, remoteDeviceUids: [otherOwnedDeviceUid], fromOwnedIdentity: ownedIdentity, necessarilyConfirmed: true))
            let concreteMessage = OwnCapabilitiesToSelfMessage(coreProtocolMessage: coreMessage,
                                                               ownCapabilities: currentCapabilities,
                                                               isReponse: isResponse)
            guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                assertionFailure()
                throw DeviceCapabilitiesDiscoveryProtocol.makeError(message: "Implementation error")
            }
            do {
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            } catch {
                os_log("Failed to inform one of our contacts of the change of the current device new capabilities (3)", log: log, type: .fault)
                throw error
            }

            // Return the new state

            return FinishedState()
        }
    }


    
    // MARK: - ProcessReceivedContactDeviceCapabilitiesStep
    
    final class ProcessReceivedContactDeviceCapabilitiesStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: OwnCapabilitiesToContactMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: OwnCapabilitiesToContactMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity, // We cannot access ownedIdentity directly at this point,
                       expectedReceptionChannelInfo: .AnyObliviousChannel(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: DeviceCapabilitiesDiscoveryProtocol.logCategory)
            
            let rawContactObvCapabilities = receivedMessage.rawContactObvCapabilities
            let isResponse = receivedMessage.isResponse
            
            // Determine the origin of the message (contact identity and contact device uid)
            
            guard let receptionChannelInfo = receivedMessage.receptionChannelInfo else {
                os_log("Could not determine reception channel infos. This is a bug", log: log, type: .fault)
                assertionFailure()
                throw DeviceCapabilitiesDiscoveryProtocol.makeError(message: "Could not determine reception channel infos")
            }
            guard let remoteIdentity = receptionChannelInfo.getRemoteIdentity() else {
                os_log("Could not determine remote identity. This is a bug", log: log, type: .fault)
                assertionFailure()
                throw DeviceCapabilitiesDiscoveryProtocol.makeError(message: "Could not determine remote identity")
            }
            guard let remoteDeviceUid = receptionChannelInfo.getRemoteDeviceUid() else {
                os_log("Could not determine remote device uid. This is a bug", log: log, type: .fault)
                assertionFailure()
                throw DeviceCapabilitiesDiscoveryProtocol.makeError(message: "Could not determine remote device uid")
            }
            
            // Check whether this contact device already has capabilities. If this is not the case, send a OwnCapabilitiesToContactMessage to it,
            // So as to make sure her device knows about our own current device capabilities. This is typically necessary when the contact just upgraded the app and
            // Understands capabilities for the first time.
            
            let currentContactObvCapabilities = try identityDelegate.getCapabilitiesOfContactDevice(ownedIdentity: ownedIdentity,
                                                                                                         contactIdentity: remoteIdentity,
                                                                                                         contactDeviceUid: remoteDeviceUid,
                                                                                                         within: obvContext)
            if !isResponse && (currentContactObvCapabilities == nil || currentContactObvCapabilities?.isEmpty == true) {
                
                let channel = ObvChannelSendChannelType.Local(ownedIdentity: ownedIdentity)
                let coreMessage = getCoreMessage(for: channel)
                let message = InitialSingleContactDeviceMessage(coreProtocolMessage: coreMessage, contactIdentity: remoteIdentity, contactDeviceUid: remoteDeviceUid, isResponse: true)
                guard let messageToSend = message.generateObvChannelProtocolMessageToSend(with: prng) else {
                    assertionFailure()
                    throw DeviceCapabilitiesDiscoveryProtocol.makeError(message: "Implementation error")
                }
                do {
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Failed to inform our contact of the current device capabilities", log: log, type: .fault)
                    throw error
                }

            }
            
            // Replace the contact capabilities with the one we just received

            try identityDelegate.setRawCapabilitiesOfContactDevice(ownedIdentity: ownedIdentity,
                                                                   contactIdentity: remoteIdentity,
                                                                   uid: remoteDeviceUid,
                                                                   newRawCapabilities: rawContactObvCapabilities,
                                                                   within: obvContext)

            // Return the new state

            return FinishedState()
        }
    }


    // MARK: - ProcessReceivedOwnedDeviceCapabilitiesStep
    
    final class ProcessReceivedOwnedDeviceCapabilitiesStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: OwnCapabilitiesToSelfMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: OwnCapabilitiesToSelfMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity, // We cannot access ownedIdentity directly at this point,
                       expectedReceptionChannelInfo: .AnyObliviousChannelWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: DeviceCapabilitiesDiscoveryProtocol.logCategory)
            
            let rawOtherOwnDeviceObvCapabilities = receivedMessage.rawOtherOwnDeviceObvCapabilities
            let isResponse = receivedMessage.isReponse
            
            // Determine the origin of the message (remote owned device UID)
            
            guard let receptionChannelInfo = receivedMessage.receptionChannelInfo else {
                os_log("Could not determine reception channel infos. This is a bug", log: log, type: .fault)
                assertionFailure()
                throw DeviceCapabilitiesDiscoveryProtocol.makeError(message: "Could not determine reception channel infos")
            }
            guard let otherOwnedDeviceUid = receptionChannelInfo.getRemoteDeviceUid() else {
                os_log("Could not determine remote device uid. This is a bug", log: log, type: .fault)
                assertionFailure()
                throw DeviceCapabilitiesDiscoveryProtocol.makeError(message: "Could not determine remote device uid")
            }
            
            // Check whether this remote owned device already has capabilities. If this is not the case, send a OwnCapabilitiesToSelf to it,
            // So as to make sure this other owned device knows about our own current device capabilities. This is typically necessary when the
            // Other device just upgraded the app and understands capabilities for the first time.
            
            let currentCapabilitiesOfOtherOwnDevice = try identityDelegate.getCapabilitiesOfOtherOwnedDevice(ownedIdentity: ownedIdentity, deviceUID: otherOwnedDeviceUid, within: obvContext)
            
            if !isResponse && (currentCapabilitiesOfOtherOwnDevice == nil || currentCapabilitiesOfOtherOwnDevice?.isEmpty == true) {

                let channel = ObvChannelSendChannelType.Local(ownedIdentity: ownedIdentity)
                let coreMessage = getCoreMessage(for: channel)
                let message = InitialSingleOwnedDeviceMessage(coreProtocolMessage: coreMessage, otherOwnedDeviceUid: otherOwnedDeviceUid, isResponse: true)
                guard let messageToSend = message.generateObvChannelProtocolMessageToSend(with: prng) else {
                    assertionFailure()
                    throw DeviceCapabilitiesDiscoveryProtocol.makeError(message: "Implementation error")
                }
                do {
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Failed to inform our other owned device of the current device capabilities", log: log, type: .fault)
                    throw error
                }
                
            }
            
            // Replace the remote owned device capabilities with the ones we just received

            try identityDelegate.setRawCapabilitiesOfOtherDeviceOfOwnedIdentity(ownedIdentity: ownedIdentity,
                                                                                deviceUID: otherOwnedDeviceUid,
                                                                                newRawCapabilities: rawOtherOwnDeviceObvCapabilities,
                                                                                within: obvContext)
            // Return the new state

            return FinishedState()
        }
    }

}
