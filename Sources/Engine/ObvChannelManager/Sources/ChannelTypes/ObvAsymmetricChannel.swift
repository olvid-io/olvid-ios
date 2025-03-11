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
import CoreData
import ObvTypes
import ObvCrypto
import ObvMetaManager
import OlvidUtils

final class ObvAsymmetricChannel: ObvNetworkChannel {
    
    private static let logCategory = "ObvAsymmetricChannel"
    
    private static let errorDomain = "ObvAsymmetricChannel"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    // MARK: Instance variables

    private let deviceUid: UID
    private let identity: ObvCryptoIdentity
    private var keyWrapperForIdentityDelegate: ObvKeyWrapperForIdentityDelegate
    let cryptoSuiteVersion: SuiteVersion
    weak var delegateManager: ObvChannelDelegateManager?
    
    // MARK: Init
    
    init(to identity: ObvCryptoIdentity, deviceUid: UID, delegateManager: ObvChannelDelegateManager) throws {
        guard let delegate = delegateManager.keyWrapperForIdentityDelegate else {
            assertionFailure()
            throw ObvError.keyWrapperForIdentityDelegateIsNil
        }
        self.keyWrapperForIdentityDelegate = delegate
        self.identity = identity
        self.deviceUid = deviceUid
        self.cryptoSuiteVersion = ObvCryptoSuite.sharedInstance.minAcceptableVersion // Maximizes the chances that the recipient will be able to decrypt
        self.delegateManager = delegateManager
    }
    
    // MARK: Encryption/Wrapping method and helpers
    
    func wrapMessageKey(_ messageKey: AuthenticatedEncryptionKey, randomizedWith prng: PRNGService) -> ObvNetworkMessageToSend.Header? {
        guard let wrappedMessageKey = keyWrapperForIdentityDelegate.wrap(messageKey, for: identity, randomizedWith: prng) else {
            assertionFailure()
            return nil
        }
        let header = ObvNetworkMessageToSend.Header(toIdentity: identity, deviceUid: deviceUid, wrappedMessageKey: wrappedMessageKey)
        return header
    }
    
    // MARK: Decryption/Unwrapping method and helpers
    
    static func unwrapMessageKey(wrappedKey: EncryptedData, toOwnedIdentity: ObvCryptoIdentity, delegateManager: ObvChannelDelegateManager, within obvContext: ObvContext) throws -> UnwrapMessageKeyResult {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ObvAsymmetricChannel.logCategory)

        guard let keyWrapperForIdentityDelegate = delegateManager.keyWrapperForIdentityDelegate else {
            os_log("The key wrapper for identity delegate is not set", log: log, type: .fault)
            assertionFailure()
            throw ObvError.keyWrapperForIdentityDelegateIsNil
        }
        
        guard let messageKey = keyWrapperForIdentityDelegate.unwrap(wrappedKey, for: toOwnedIdentity, within: obvContext) else { return .couldNotUnwrap }
        return .unwrapSucceeded(messageKey: messageKey,
                                receptionChannelInfo: .asymmetricChannel,
                                updateOrCheckGKMV2SupportOnMessageContentAvailable: nil)
    }
    
    
    enum ObvError: Error {
        case keyWrapperForIdentityDelegateIsNil
    }
    
}

extension ObvAsymmetricChannel {
    
    static func acceptableChannelsForPosting(_ message: ObvChannelMessageToSend, delegateManager: ObvChannelDelegateManager, within obvContext: ObvContext) throws -> [ObvChannel] {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ObvAsymmetricChannel.logCategory)
        
        let acceptableChannels: [ObvChannel]
        
        switch message.channelType {
            
        case .asymmetricChannel(to: let toIdentity, remoteDeviceUids: let remoteDeviceUids, fromOwnedIdentity: _):
            // Only protocol messages may be sent through AsymmetricChannel channels
            guard message.messageType == .ProtocolMessage else {
                throw ObvAsymmetricChannel.makeError(message: "Only protocol messages may be sent through AsymmetricChannel channels")
            }
            
            acceptableChannels = try remoteDeviceUids.map {
                try ObvAsymmetricChannel(to: toIdentity, deviceUid: $0, delegateManager: delegateManager)
            }
            
        case .asymmetricChannelBroadcast(to: let toIdentity, fromOwnedIdentity: _):
            // Only protocol messages may be sent through AsymmetricChannel channels
            guard message.messageType == .ProtocolMessage else {
                throw ObvAsymmetricChannel.makeError(message: "Only protocol messages may be sent through AsymmetricChannel channels")
            }
            
            let channel = try ObvAsymmetricChannel(to: toIdentity, deviceUid: ObvConstants.broadcastDeviceUid, delegateManager: delegateManager)
            acceptableChannels = [channel]

        default:
            os_log("Wrong message channel type", log: log, type: .fault)
            assertionFailure()
            throw ObvAsymmetricChannel.makeError(message: "Wrong message channel type")
        }
        
        return acceptableChannels
    }

}
