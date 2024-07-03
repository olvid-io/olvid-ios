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
import ObvCrypto
import ObvMetaManager
import OlvidUtils
import os.log


struct PreKeyChannel: ObvNetworkChannel {

    let keyWrapper: ObvKeyWrapperForIdentityDelegate
    let remoteDeviceUID: UID
    let remoteCryptoId: ObvCryptoIdentity
    let ownedIdentity: ObvCryptoIdentity
    let obvContext: ObvContext

    private static let logCategory = "PreKeyChannel"
    
    func wrapMessageKey(_ messageKey: any AuthenticatedEncryptionKey, randomizedWith prng: any PRNGService) -> ObvNetworkMessageToSend.Header? {
        
        do {
            guard let wrappedMessageKey = try keyWrapper.wrap(messageKey,
                                                              forRemoteDeviceUID: remoteDeviceUID,
                                                              ofRemoteCryptoId: remoteCryptoId,
                                                              ofOwnedCryptoId: ownedIdentity,
                                                              randomizedWith: prng,
                                                              within: obvContext) else {
                return nil
            }
            
            return .init(toIdentity: remoteCryptoId, deviceUid: remoteDeviceUID, wrappedMessageKey: wrappedMessageKey)
            
        } catch {
            assertionFailure()
            return nil
        }

        
    }
    
    
    static func unwrapMessageKey(wrappedKey: ObvCrypto.EncryptedData, toOwnedIdentity: ObvCrypto.ObvCryptoIdentity, delegateManager: ObvChannelDelegateManager, within obvContext: OlvidUtils.ObvContext) throws -> UnwrapMessageKeyResult {

        guard let keyWrapperForIdentityDelegate = delegateManager.keyWrapperForIdentityDelegate else {
            assertionFailure()
            throw ObvError.noKeyWrapperForIdentityDelegate
        }
        
        let result: ResultOfUnwrapWithPreKey
        do {
            result = try keyWrapperForIdentityDelegate.unwrapWithPreKey(wrappedKey, forOwnedIdentity: toOwnedIdentity, within: obvContext)
        } catch {
            throw ObvError.keyWrapperForIdentityDelegateDidThrow(error: error)
        }
        
        switch result {
            
        case .contactIsRevokedAsCompromised:
            
            return .contactIsRevokedAsCompromised

        case .couldNotUnwrap:
            
            return .couldNotUnwrap
            
        case .unwrapSucceededButRemoteCryptoIdIsUnknown(remoteCryptoIdentity: let remoteCryptoIdentity):
            
            return .unwrapSucceededButRemoteCryptoIdIsUnknown(remoteCryptoIdentity: remoteCryptoIdentity)
            
        case .unwrapSucceeded(let messageKey, let receptionChannelInfo):
            
            let updateOrCheckGKMV2SupportOnMessageContentAvailable = { (messageContent: Data) in
                let authEnc = messageKey.algorithmImplementationByteId.algorithmImplementation
                guard authEnc.verifyMessageKey(messageKey: messageKey, message: messageContent) else {
                    assertionFailure()
                    throw ObvError.messageKeyDoesNotSupportGKMV2AlthoughItShould
                }
            }
            
            return .unwrapSucceeded(messageKey: messageKey,
                                    receptionChannelInfo: receptionChannelInfo,
                                    updateOrCheckGKMV2SupportOnMessageContentAvailable: updateOrCheckGKMV2SupportOnMessageContentAvailable)

        }
        
    }
    
        
    var cryptoSuiteVersion: ObvCrypto.SuiteVersion {
        ObvCryptoSuite.sharedInstance.minAcceptableVersion
    }
    

    static func acceptableChannelsForPosting(_ message: any ObvChannelMessageToSend, delegateManager: ObvChannelDelegateManager, within obvContext: OlvidUtils.ObvContext) throws -> [any ObvChannel] {

        assertionFailure("Not expected to be called, acceptable pre-keys channels are computed in ObvObliviousChannel")
        
        return []

    }
    
    
    enum ObvError: Error {
        case noKeyWrapperForIdentityDelegate
        case keyWrapperForIdentityDelegateDidThrow(error: Error)
        case messageKeyDoesNotSupportGKMV2AlthoughItShould
    }
    
}
