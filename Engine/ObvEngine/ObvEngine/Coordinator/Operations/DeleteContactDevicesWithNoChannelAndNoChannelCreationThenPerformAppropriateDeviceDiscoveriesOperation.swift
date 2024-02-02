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
import ObvCrypto
import ObvMetaManager
import CoreData


/// This operation deletes all devices found within the identity manager if they have no associated channel and no oingoing channel creation protocol with the current device. For each (owned or contact) identity corresponding to a deleted device, we start a device discovery.
final class DeleteContactDevicesWithNoChannelAndNoChannelCreationThenPerformAppropriateDeviceDiscoveriesOperation: ContextualOperationWithSpecificReasonForCancel<DeleteContactDevicesWithNoChannelAndNoChannelCreationThenPerformAppropriateDeviceDiscoveriesOperation.ReasonForCancel> {
    
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
        
        // Get all existing devices within the identity manager
        
        let existingDevices: Set<ObliviousChannelIdentifier>
        do {
            existingDevices = try identityDelegate.getAllRemoteOwnedDevicesUidsAndContactDeviceUids(within: obvContext)
        } catch {
            return cancel(withReason: .identityDelegateError(error: error))
        }
        
        // Get all existing channels
        
        let existingChannels: Set<ObliviousChannelIdentifier>
        do {
            existingChannels = try channelDelegate.getAllRemoteDeviceUidsAssociatedToAnObliviousChannel(within: obvContext)
        } catch {
            return cancel(withReason: .channelDelegate(error: error))
        }
        
        // Find devices with no channel and no channel creation protocol
        
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
        // We delete all devices with no channel and no ongoing channel creation protocol, and keep track of the corresponding identities:
        // we will start a device discovery for them.
        
        var deviceDiscoveriesToStart = Set<ObliviousChannelIdentifierAlt>()
        
        for deviceWithNoChannel in devicesWithNoChannel {
            
            let ownedCryptoIdentity: ObvCryptoIdentity
            do {
                ownedCryptoIdentity = try identityDelegate.getOwnedIdentityOfCurrentDeviceUid(deviceWithNoChannel.currentDeviceUid, within: obvContext)
            } catch {
                assertionFailure()
                continue
            }
            
            let channelCreationToFind = ObliviousChannelIdentifierAlt(ownedCryptoIdentity: ownedCryptoIdentity,
                                                                      remoteCryptoIdentity: deviceWithNoChannel.remoteCryptoIdentity,
                                                                      remoteDeviceUid: deviceWithNoChannel.remoteDeviceUid)
            
            if channelCreationProtocols.contains(channelCreationToFind) { continue }
            
            deviceDiscoveriesToStart.insert(channelCreationToFind)
            
            // If we reach this point, we found a device with no channel and with no ongoing channel creation protocol.
            // We delete this device and add the corresponding remote identity to the set of identities for which we want to perform a device discovery.
            
            do {
                if deviceWithNoChannel.remoteCryptoIdentity == ownedCryptoIdentity {
                    try identityDelegate.removeOtherDeviceForOwnedIdentity(ownedCryptoIdentity,
                                                                           otherDeviceUid: deviceWithNoChannel.remoteDeviceUid,
                                                                           within: obvContext)
                } else {
                    try identityDelegate.removeDeviceForContactIdentity(deviceWithNoChannel.remoteCryptoIdentity,
                                                                        withUid: deviceWithNoChannel.remoteDeviceUid,
                                                                        ofOwnedIdentity: ownedCryptoIdentity,
                                                                        within: obvContext)
                }
            } catch {
                assertionFailure()
                continue
            }
            
        }
        
        // Finally, we start the required channel creations
        
        for deviceDiscoveryToStart in deviceDiscoveriesToStart {
            
            do {
                
                let message: ObvChannelProtocolMessageToSend
                if deviceDiscoveryToStart.ownedCryptoIdentity == deviceDiscoveryToStart.remoteCryptoIdentity {
                    message = try protocolDelegate.getInitiateOwnedDeviceDiscoveryMessage(ownedCryptoIdentity: deviceDiscoveryToStart.ownedCryptoIdentity)
                } else {
                    message = try protocolDelegate.getInitialMessageForContactDeviceDiscoveryProtocol(ownedIdentity: deviceDiscoveryToStart.ownedCryptoIdentity, contactIdentity: deviceDiscoveryToStart.remoteCryptoIdentity)
                }
                
                _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                
            } catch {
                assertionFailure(error.localizedDescription)
                // continue
            }
            
        }
        
    }
        
    
    
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

