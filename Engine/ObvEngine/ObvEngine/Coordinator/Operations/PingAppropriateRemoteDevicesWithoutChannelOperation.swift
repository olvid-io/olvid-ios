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
import OlvidUtils
import os.log
import ObvCrypto
import ObvMetaManager
import CoreData


final class PingAppropriateRemoteDevicesWithoutChannelOperation: ContextualOperationWithSpecificReasonForCancel<PingAppropriateRemoteDevicesWithoutChannelOperation.ReasonForCancel> {
    
    
    private let identityDelegate: ObvIdentityDelegate
    private let channelDelegate: ObvChannelDelegate
    private let protocolDelegate: ObvProtocolDelegate
    private let prng: PRNGService

    
    init(identityDelegate: ObvIdentityDelegate, channelDelegate: ObvChannelDelegate, protocolDelegate: ObvProtocolDelegate, prng: PRNGService) {
        self.identityDelegate = identityDelegate
        self.channelDelegate = channelDelegate
        self.protocolDelegate = protocolDelegate
        self.prng = prng
        super.init()
    }

    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        // Get all devices within the identity manager that haven't been pinged for a "long" time
        
        let existingDevices: Set<ObliviousChannelIdentifier>
        do {
            existingDevices = try identityDelegate.getAllRemoteOwnedDevicesUidsAndContactDeviceUidsWithLatestChannelCreationPingTimestamp(
                earlierThan: .now.addingTimeInterval(-ObvConstants.channelCreationPingInterval),
                within: obvContext)
        } catch {
            return cancel(withReason: .identityDelegateError(error: error))
        }

        guard !existingDevices.isEmpty else { return }
        
        // Get all existing channels
        
        let existingChannels: Set<ObliviousChannelIdentifier>
        do {
            existingChannels = try channelDelegate.getAllRemoteDeviceUidsAssociatedToAnObliviousChannel(within: obvContext)
        } catch {
            return cancel(withReason: .channelDelegate(error: error))
        }

        // Find devices with no channel
        
        let devicesWithNoChannel = existingDevices
            .subtracting(existingChannels)
        
        guard !devicesWithNoChannel.isEmpty else { return }

        // At this point, we know there is at least one (owned or contact) device with no channel.
        
        // Find all channel creation protocols
        
        let channelCreationProtocols: Set<ObliviousChannelIdentifierAlt>
        do {
            let channelCreationProtocolsWithOwnedDevice = try protocolDelegate.getAllObliviousChannelIdentifiersHavingARunningChannelCreationWithOwnedDeviceProtocolInstances(within: obvContext)
            let channelCreationProtocolsWithContactDevice = try protocolDelegate.getAllObliviousChannelIdentifiersHavingARunningChannelCreationWithContactDeviceProtocolInstances(within: obvContext)
            channelCreationProtocols = channelCreationProtocolsWithOwnedDevice.union(channelCreationProtocolsWithContactDevice)
        } catch {
            return cancel(withReason: .protocolDelegate(error: error))
        }

        // For each device with no channel, we check whether there is a channel creation protocol already handling this situation.
        // If not, we start one.
        
        for deviceWithNoChannel in devicesWithNoChannel {
            
            do {
                
                let ownedCryptoIdentity: ObvCryptoIdentity
                do {
                    ownedCryptoIdentity = try identityDelegate.getOwnedIdentityOfCurrentDeviceUid(deviceWithNoChannel.currentDeviceUid, within: obvContext)
                } catch {
                    assertionFailure()
                    continue
                }
                
                guard try identityDelegate.isOwnedIdentityActive(ownedIdentity: ownedCryptoIdentity, within: obvContext) else { continue }
                
                let channelCreationToFind = ObliviousChannelIdentifierAlt(ownedCryptoIdentity: ownedCryptoIdentity,
                                                                          remoteCryptoIdentity: deviceWithNoChannel.remoteCryptoIdentity,
                                                                          remoteDeviceUid: deviceWithNoChannel.remoteDeviceUid)
                
                if channelCreationProtocols.contains(channelCreationToFind) { continue }
                
                // If we reach this point, no channel creation protocol is started, we start one by pinging the remote device
                
                let msg: ObvChannelProtocolMessageToSend
                
                if channelCreationToFind.ownedCryptoIdentity == channelCreationToFind.remoteCryptoIdentity {
                    
                    msg = try protocolDelegate.getInitialMessageForChannelCreationWithOwnedDeviceProtocol(
                        ownedIdentity: channelCreationToFind.ownedCryptoIdentity,
                        remoteDeviceUid: channelCreationToFind.remoteDeviceUid)
                    
                } else {
                
                    msg = try protocolDelegate.getInitialMessageForChannelCreationWithContactDeviceProtocol(
                        betweenTheCurrentDeviceOfOwnedIdentity: ownedCryptoIdentity,
                        andTheDeviceUid: deviceWithNoChannel.remoteDeviceUid,
                        ofTheContactIdentity: deviceWithNoChannel.remoteCryptoIdentity)

                }
                                
                _ = try channelDelegate.postChannelMessage(msg, randomizedWith: prng, within: obvContext)
                
            } catch {
                assertionFailure()
                continue
            }
            
        }


        

    }
    
    
    // MARK: ReasonForCancel
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case identityDelegateError(error: Error)
        case channelDelegate(error: Error)
        case protocolDelegate(error: Error)
        case contextIsNil
        
        public var logType: OSLogType {
            switch self {
            case .channelDelegate,
                    .protocolDelegate,
                    .identityDelegateError,
                    .contextIsNil:
                return .fault
            }
        }
        
        public var errorDescription: String? {
            switch self {
            case .contextIsNil:
                return "Context is nil"
            case .identityDelegateError(error: let error):
                return "Identity delegate error: \(error.localizedDescription)"
            case .channelDelegate(error: let error):
                return "Channel delegate error: \(error.localizedDescription)"
            case .protocolDelegate(error: let error):
                return "Protocol delegate error: \(error.localizedDescription)"
            }
        }
        
        
    }

}
