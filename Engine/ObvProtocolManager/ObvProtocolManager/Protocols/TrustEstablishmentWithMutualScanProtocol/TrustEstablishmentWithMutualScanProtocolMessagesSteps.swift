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
import OlvidUtils
import ObvMetaManager


extension TrustEstablishmentWithMutualScanProtocol {
    
    enum StepId: Int, ConcreteProtocolStepId {
        
        // Alice's side
        case AliceSend = 0
        case AliceHandlesPropagatedQRCode = 1
        case AliceAddsContact = 2
        
        // Bob's side
        case BobAddsContactAndConfirms = 3
        case BobHandlesPropagatedSignature = 4
        
        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
            switch self {
                
            // Alice's side
            case .AliceSend:
                let step = AliceSendStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .AliceHandlesPropagatedQRCode:
                let step = AliceHandlesPropagatedQRCodeStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .AliceAddsContact:
                let step = AliceAddsContactStep(from: concreteProtocol, and: receivedMessage)
                return step
                
            // Bob's side
            case .BobAddsContactAndConfirms:
                let step = BobAddsContactAndConfirmsStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .BobHandlesPropagatedSignature:
                let step = BobHandlesPropagatedSignatureStep(from: concreteProtocol, and: receivedMessage)
                return step
            }
        }
    }

    
    // MARK: - AliceSendStep
    
    final class AliceSendStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitialMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: InitialMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity, // We cannot access ownedIdentity directly at this point,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: TrustEstablishmentWithSASProtocol.logCategory)
            os_log("%{public}@: starting %{public}@", log: log, type: .info, String(describing: TrustEstablishmentWithSASProtocol.self), String(describing: Self.self))
            defer {
                os_log("%{public}@: ending %{public}@", log: log, type: .info, String(describing: TrustEstablishmentWithSASProtocol.self), String(describing: Self.self))
            }

            guard let channelDelegate = delegateManager.channelDelegate else {
                os_log("The channel delegate is not set", log: log, type: .fault)
                return CancelledState()
            }
            
            guard let identityDelegate = delegateManager.identityDelegate else {
                os_log("The identity delegate is not set", log: log, type: .fault)
                return CancelledState()
            }
            
            guard let solveChallengeDelegate = delegateManager.solveChallengeDelegate else {
                os_log("The solve challenge delegate is not set", log: log, type: .fault)
                return CancelledState()
            }

            let contactIdentity = receivedMessage.contactIdentity
            let signature = receivedMessage.signature
                        
            // Verify the signature
            
            do {
                let prefix = ObvConstants.trustEstablishmentWithMutualScanProtocolPrefix
                let challenge = ownedIdentity.getIdentity() + contactIdentity.getIdentity()
                guard solveChallengeDelegate.checkResponse(signature, toChallenge: challenge, prefixedWith: prefix, from: contactIdentity) else {
                    os_log("The signature is invalid", log: log, type: .error)
                    assertionFailure()
                    return CancelledState()
                }
            }
            
            // Send message to Bob
            
            let aliceDeviceUids = try identityDelegate.getDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext)
            let aliceCoreDetails = try identityDelegate.getIdentityDetailsOfOwnedIdentity(ownedIdentity, within: obvContext).publishedIdentityDetails.coreDetails
            let coreMessage = getCoreMessage(for: .AsymmetricChannelBroadcast(to: contactIdentity, fromOwnedIdentity: ownedIdentity))
            let concreteProtocolMessage = AliceSendsSignatureToBobMessage(coreProtocolMessage: coreMessage,
                                                                          aliceIdentity: ownedIdentity,
                                                                          signature: signature,
                                                                          aliceCoreDetails: aliceCoreDetails,
                                                                          aliceDeviceUids: Array(aliceDeviceUids))
            guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { throw TrustEstablishmentWithMutualScanProtocol.makeError(message: "Could not generate ObvChannelProtocolMessageToSend for AliceSendsSignatureToBobMessage") }
            _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)

            // Send propagate messages
            
            let numberOfOtherDevicesOfOwnedIdentity = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext).count
            if numberOfOtherDevicesOfOwnedIdentity > 0 {
                let coreMessage = getCoreMessage(for: .AllConfirmedObliviousChannelsWithOtherDevicesOfOwnedIdentity(ownedIdentity: ownedIdentity))
                let concreteProtocolMessage = AlicePropagatesQRCodeMessage(coreProtocolMessage: coreMessage,
                                                                           bobIdentity: contactIdentity,
                                                                           signature: signature)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { throw TrustEstablishmentWithMutualScanProtocol.makeError(message: "Could not generate ObvChannelProtocolMessageToSend for AlicePropagatesQRCodeMessage") }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Return the new state

            return WaitingForConfirmationState(bobIdentity: contactIdentity)
        }
    }

    
    // MARK: - AliceHandlesPropagatedQRCodeStep
    
    final class AliceHandlesPropagatedQRCodeStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: AlicePropagatesQRCodeMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: AlicePropagatesQRCodeMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity, // We cannot access ownedIdentity directly at this point,
                       expectedReceptionChannelInfo: .AnyObliviousChannelWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: TrustEstablishmentWithSASProtocol.logCategory)
            os_log("%{public}@: starting %{public}@", log: log, type: .info, String(describing: TrustEstablishmentWithSASProtocol.self), String(describing: Self.self))
            defer {
                os_log("%{public}@: ending %{public}@", log: log, type: .info, String(describing: TrustEstablishmentWithSASProtocol.self), String(describing: Self.self))
            }

            guard let solveChallengeDelegate = delegateManager.solveChallengeDelegate else {
                os_log("The solve challenge delegate is not set", log: log, type: .fault)
                return CancelledState()
            }

            let bobIdentity = receivedMessage.bobIdentity
            let signature = receivedMessage.signature
                        
            // Verify the signature
            
            do {
                let prefix = ObvConstants.trustEstablishmentWithMutualScanProtocolPrefix
                let challenge = ownedIdentity.getIdentity() + bobIdentity.getIdentity()
                guard solveChallengeDelegate.checkResponse(signature, toChallenge: challenge, prefixedWith: prefix, from: bobIdentity) else {
                    os_log("The signature is invalid", log: log, type: .error)
                    assertionFailure()
                    return CancelledState()
                }
            }
            
            // Return the new state

            return WaitingForConfirmationState(bobIdentity: bobIdentity)
        }
    }

    
    // MARK: - BobAddsContactAndConfirmsStep
    
    final class BobAddsContactAndConfirmsStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: AliceSendsSignatureToBobMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: AliceSendsSignatureToBobMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity, // We cannot access ownedIdentity directly at this point,
                       expectedReceptionChannelInfo: .AsymmetricChannel,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: TrustEstablishmentWithSASProtocol.logCategory)
            os_log("%{public}@: starting %{public}@", log: log, type: .info, String(describing: TrustEstablishmentWithSASProtocol.self), String(describing: Self.self))
            defer {
                os_log("%{public}@: ending %{public}@", log: log, type: .info, String(describing: TrustEstablishmentWithSASProtocol.self), String(describing: Self.self))
            }

            guard let channelDelegate = delegateManager.channelDelegate else {
                os_log("The channel delegate is not set", log: log, type: .fault)
                return CancelledState()
            }

            guard let solveChallengeDelegate = delegateManager.solveChallengeDelegate else {
                os_log("The solve challenge delegate is not set", log: log, type: .fault)
                return CancelledState()
            }

            guard let identityDelegate = delegateManager.identityDelegate else {
                os_log("The identity delegate is not set", log: log, type: .fault)
                return CancelledState()
            }

            let aliceIdentity = receivedMessage.aliceIdentity
            let signature = receivedMessage.signature
            let aliceCoreDetails = receivedMessage.aliceCoreDetails
            let aliceDeviceUids = receivedMessage.aliceDeviceUids
            
            // Verify the signature
            
            do {
                let prefix = ObvConstants.trustEstablishmentWithMutualScanProtocolPrefix
                let challenge = aliceIdentity.getIdentity() + ownedIdentity.getIdentity()
                guard solveChallengeDelegate.checkResponse(signature, toChallenge: challenge, prefixedWith: prefix, from: ownedIdentity) else {
                    os_log("The signature is invalid", log: log, type: .error)
                    assertionFailure()
                    return CancelledState()
                }
            }
            
            // Verify the signature is fresh
            
            guard try MutualScanSignatureReceived.exists(ownedCryptoIdentity: ownedIdentity, signature: signature, within: obvContext) == false else {
                os_log("Signature was already received", log: log, type: .error)
                return CancelledState()
            }
            
            // Store the signature

            _ = MutualScanSignatureReceived(ownedCryptoIdentity: ownedIdentity, signature: signature, within: obvContext)
            
            // Signature is valid and is fresh --> create the contact (if it does not already exists)

            if (try? identityDelegate.isIdentity(aliceIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext)) == true {
                guard try identityDelegate.isContactIdentityActive(ownedIdentity: ownedIdentity, contactIdentity: aliceIdentity, within: obvContext) else {
                    os_log("Contact is not active", log: log, type: .error)
                    return CancelledState()
                }
                try identityDelegate.addTrustOrigin(.direct(timestamp: Date()), toContactIdentity: aliceIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext)
            } else {
                try identityDelegate.addContactIdentity(aliceIdentity, with: aliceCoreDetails, andTrustOrigin: .direct(timestamp: Date()), forOwnedIdentity: ownedIdentity, within: obvContext)
            }
            for uid in aliceDeviceUids {
                try identityDelegate.addDeviceForContactIdentity(aliceIdentity, withUid: uid, ofOwnedIdentity: ownedIdentity, within: obvContext)
            }

            // Notify Alice she was added and send her our details

            let bobDeviceUids = try identityDelegate.getDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext)
            let bobCoreDetails = try identityDelegate.getIdentityDetailsOfOwnedIdentity(ownedIdentity, within: obvContext).publishedIdentityDetails.coreDetails
            let coreMessage = getCoreMessage(for: .AsymmetricChannelBroadcast(to: aliceIdentity, fromOwnedIdentity: ownedIdentity))
            let concreteProtocolMessage = BobSendsConfirmationAndDetailsToAliceMessage(coreProtocolMessage: coreMessage,
                                                                                       bobCoreDetails: bobCoreDetails,
                                                                                       bobDeviceUids: Array(bobDeviceUids))
            guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                throw TrustEstablishmentWithMutualScanProtocol.makeError(message: "Could not generate ObvChannelProtocolMessageToSend for BobSendsConfirmationAndDetailsToAliceMessage")
            }
            _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            
            // Propagate the message to other devices
            
            let numberOfOtherDevicesOfOwnedIdentity = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext).count
            if numberOfOtherDevicesOfOwnedIdentity > 0 {
                let coreMessage = getCoreMessage(for: .AllConfirmedObliviousChannelsWithOtherDevicesOfOwnedIdentity(ownedIdentity: ownedIdentity))
                let concreteProtocolMessage = BobPropagatesSignatureMessage(coreProtocolMessage: coreMessage,
                                                                            aliceIdentity: aliceIdentity,
                                                                            signature: signature,
                                                                            aliceCoreDetails: aliceCoreDetails,
                                                                            aliceDeviceUids: aliceDeviceUids)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                    throw TrustEstablishmentWithMutualScanProtocol.makeError(message: "Could not generate ObvChannelProtocolMessageToSend for BobPropagatesSignatureMessage")
                }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Send a notification so the app can automatically open the contact discussion

            let ownedIdentity = self.ownedIdentity
            try obvContext.addContextDidSaveCompletionHandler { error in
                guard error == nil else { return }
                ObvProtocolNotificationNew.mutualScanContactAdded(ownedIdentity: ownedIdentity, contactIdentity: aliceIdentity, signature: signature)
                    .postOnBackgroundQueue()
            }

            // Return the new state

            return FinishedState()
        }
    }

    
    
    // MARK: - BobHandlesPropagatedSignatureStep
    
    final class BobHandlesPropagatedSignatureStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: BobPropagatesSignatureMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: BobPropagatesSignatureMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity, // We cannot access ownedIdentity directly at this point,
                       expectedReceptionChannelInfo: .AnyObliviousChannelWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: TrustEstablishmentWithSASProtocol.logCategory)
            os_log("%{public}@: starting %{public}@", log: log, type: .info, String(describing: TrustEstablishmentWithSASProtocol.self), String(describing: Self.self))
            defer {
                os_log("%{public}@: ending %{public}@", log: log, type: .info, String(describing: TrustEstablishmentWithSASProtocol.self), String(describing: Self.self))
            }

            guard let solveChallengeDelegate = delegateManager.solveChallengeDelegate else {
                os_log("The solve challenge delegate is not set", log: log, type: .fault)
                return CancelledState()
            }

            guard let identityDelegate = delegateManager.identityDelegate else {
                os_log("The identity delegate is not set", log: log, type: .fault)
                return CancelledState()
            }

            let aliceIdentity = receivedMessage.aliceIdentity
            let signature = receivedMessage.signature
            let aliceCoreDetails = receivedMessage.aliceCoreDetails
            let aliceDeviceUids = receivedMessage.aliceDeviceUids
            
            // Verify the signature
            
            do {
                let prefix = ObvConstants.trustEstablishmentWithMutualScanProtocolPrefix
                let challenge = aliceIdentity.getIdentity() + ownedIdentity.getIdentity()
                guard solveChallengeDelegate.checkResponse(signature, toChallenge: challenge, prefixedWith: prefix, from: ownedIdentity) else {
                    os_log("The signature is invalid", log: log, type: .error)
                    assertionFailure()
                    return CancelledState()
                }
            }
            
            // Verify the signature is fresh
            
            guard try MutualScanSignatureReceived.exists(ownedCryptoIdentity: ownedIdentity, signature: signature, within: obvContext) == false else {
                os_log("Signature was already received", log: log, type: .error)
                return CancelledState()
            }
            
            // Store the signature

            _ = MutualScanSignatureReceived(ownedCryptoIdentity: ownedIdentity, signature: signature, within: obvContext)
            
            // Signature is valid and is fresh --> create the contact (if it does not already exists)

            if (try? identityDelegate.isIdentity(aliceIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext)) == true {
                try identityDelegate.addTrustOrigin(.direct(timestamp: Date()), toContactIdentity: aliceIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext)
            } else {
                try identityDelegate.addContactIdentity(aliceIdentity, with: aliceCoreDetails, andTrustOrigin: .direct(timestamp: Date()), forOwnedIdentity: ownedIdentity, within: obvContext)
            }
            for uid in aliceDeviceUids {
                try identityDelegate.addDeviceForContactIdentity(aliceIdentity, withUid: uid, ofOwnedIdentity: ownedIdentity, within: obvContext)
            }

            // Send a notification so the app can automatically open the contact discussion

            let ownedIdentity = self.ownedIdentity
            try obvContext.addContextDidSaveCompletionHandler { error in
                guard error == nil else { return }
                ObvProtocolNotificationNew.mutualScanContactAdded(ownedIdentity: ownedIdentity, contactIdentity: aliceIdentity, signature: signature)
                    .postOnBackgroundQueue()
            }

            // Return the new state

            return FinishedState()
        }
    }

    
    
    // MARK: - AliceAddsContactStep
    
    final class AliceAddsContactStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: WaitingForConfirmationState
        let receivedMessage: BobSendsConfirmationAndDetailsToAliceMessage
        
        init?(startState: WaitingForConfirmationState, receivedMessage: BobSendsConfirmationAndDetailsToAliceMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity, // We cannot access ownedIdentity directly at this point,
                       expectedReceptionChannelInfo: .AsymmetricChannel,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: TrustEstablishmentWithSASProtocol.logCategory)
            os_log("%{public}@: starting %{public}@", log: log, type: .info, String(describing: TrustEstablishmentWithSASProtocol.self), String(describing: Self.self))
            defer {
                os_log("%{public}@: ending %{public}@", log: log, type: .info, String(describing: TrustEstablishmentWithSASProtocol.self), String(describing: Self.self))
            }

            guard let identityDelegate = delegateManager.identityDelegate else {
                os_log("The identity delegate is not set", log: log, type: .fault)
                return CancelledState()
            }

            let bobIdentity = startState.bobIdentity
            let bobCoreDetails = receivedMessage.bobCoreDetails
            let bobDeviceUids = receivedMessage.bobDeviceUids
            
            // Bob added Alice to his contacts --> time for Alice to do the same

            if (try? identityDelegate.isIdentity(bobIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext)) == true {
                guard try identityDelegate.isContactIdentityActive(ownedIdentity: ownedIdentity, contactIdentity: bobIdentity, within: obvContext) else {
                    os_log("The identity is not active", log: log, type: .fault)
                    return CancelledState()
                }
                try identityDelegate.addTrustOrigin(.direct(timestamp: Date()), toContactIdentity: bobIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext)
            } else {
                try identityDelegate.addContactIdentity(bobIdentity, with: bobCoreDetails, andTrustOrigin: .direct(timestamp: Date()), forOwnedIdentity: ownedIdentity, within: obvContext)
            }
            for uid in bobDeviceUids {
                try identityDelegate.addDeviceForContactIdentity(bobIdentity, withUid: uid, ofOwnedIdentity: ownedIdentity, within: obvContext)
            }

            // Return the new state

            return FinishedState()
        }
    }

}
