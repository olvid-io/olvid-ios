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
import CoreData
import os.log
import OlvidUtils
import ObvCrypto
import ObvTypes
import ObvMetaManager


final class ObliviousChannelLifeManager: ObliviousChannelLifeDelegate {
    
    // MARK: Instance variables
    
    weak var delegateManager: ObvChannelDelegateManager?
    private static let logCategory = "ObliviousChannelLifeManager"
    
    func finalizeInitialization(within obvContext: ObvContext) throws {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvChannelDelegateManager.defaultLogSubsystem, category: ObliviousChannelLifeManager.logCategory)
            os_log("The Channel Delegate Manager is not set", log: log, type: .error)
            return
        }

        deleteExpiredKeyMaterialsAndProvisions(delegateManager: delegateManager, within: obvContext)

        // NOTE: Obsolete Oblivious channels (e.g., established with a remote device that do not exist anymore) are cleaned within the Engine

    }
    
    private static let errorDomain = "ObliviousChannelLifeManager"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }
    
    private func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: ObliviousChannelLifeManager.errorDomain, code: 0, userInfo: userInfo)
    }

}

extension ObliviousChannelLifeManager {
    

    private func deleteExpiredKeyMaterialsAndProvisions(delegateManager: ObvChannelDelegateManager, within obvContext: ObvContext) {
        do {
            try ObvObliviousChannel.clean(within: obvContext)
        } catch {
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ObliviousChannelLifeManager.logCategory)
            os_log("Could not clean ObvObliviousChannels (i.e., could not delete expired key material)", log: log, type: .fault)
            assertionFailure()
        }
    }
        
}

// MARK: - Implementing ObliviousChannelLifeDelegate

extension ObliviousChannelLifeManager {
    
    func deleteAllObliviousChannelsBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andTheDevicesOfContactIdentity contactCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvChannelDelegateManager.defaultLogSubsystem, category: ObliviousChannelLifeManager.logCategory)
            os_log("The Channel Delegate Manager is not set", log: log, type: .error)
            throw NSError()
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ObliviousChannelLifeManager.logCategory)
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            throw NSError()
        }
        
        let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
        
        /* Deleting a channel is done by executing a protocol step that first sends a message to the contact, notifying her that the channel will be deleted.
         * This message may trigger a synchronous self-ratchet of the (reception part of the) channel. In that case, the deletion performed here fails, unless
         * we refresh the current context (which was created *before* the self-ratchet procedure). Tricky isn't it?
         */
        
        obvContext.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump

        try ObvObliviousChannel.delete(currentDeviceUid: currentDeviceUid, remoteCryptoIdentity: contactCryptoIdentity, within: obvContext)
        
        os_log("We deleted all the oblivious channels that the owned identity %@ has with the contact identity %@", log: log, type: .debug, ownedIdentity.debugDescription, contactCryptoIdentity.debugDescription)
        
    }
    

    func deleteObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andTheRemoteDeviceWithUid remoteDeviceUid: UID, ofRemoteIdentity remoteIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvChannelDelegateManager.defaultLogSubsystem, category: ObliviousChannelLifeManager.logCategory)
            os_log("The Channel Delegate Manager is not set", log: log, type: .error)
            throw NSError()
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ObliviousChannelLifeManager.logCategory)
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            throw NSError()
        }
        
        let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
        
        try ObvObliviousChannel.delete(currentDeviceUid: currentDeviceUid, remoteDeviceUid: remoteDeviceUid, remoteIdentity: remoteIdentity, within: obvContext)
        
        os_log("We deleted the oblivious channels that the owned identity %@ has with the remote device UID %@", log: log, type: .debug, ownedIdentity.debugDescription, remoteDeviceUid.debugDescription)

        
    }
    
    func deleteObliviousChannelBetweenCurentDeviceWithUid(currentDeviceUid: UID, andTheRemoteDeviceWithUid remoteDeviceUid: UID, ofRemoteIdentity remoteIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        try ObvObliviousChannel.delete(currentDeviceUid: currentDeviceUid, remoteDeviceUid: remoteDeviceUid, remoteIdentity: remoteIdentity, within: obvContext)
    }
    
    func createObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andRemoteIdentity remoteCryptoIdentity: ObvCryptoIdentity, withRemoteDeviceUid remoteDeviceUid: UID, with seed: Seed, cryptoSuiteVersion: Int, within obvContext: ObvContext) throws {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvChannelDelegateManager.defaultLogSubsystem, category: ObliviousChannelLifeManager.logCategory)
            os_log("The Channel Delegate Manager is not set", log: log, type: .error)
            throw NSError()
        }

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ObliviousChannelLifeManager.logCategory)

        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            throw NSError()
        }
        
        let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
        
        // We check that the remote device uid is either a remote device uid of the owned identity or the device uid of a trusted contact of this owned identity
        
        let doCreateChannel: Bool
        if try identityDelegate.isIdentity(remoteCryptoIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext) {
            let contactDeviceUids = try identityDelegate.getDeviceUidsOfContactIdentity(remoteCryptoIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext)
            guard contactDeviceUids.contains(remoteDeviceUid) else {
                os_log("The device uid is not part of the trusted contact identity's list of device uids", log: log, type: .fault)
                throw makeError(message: "The device uid is not part of the trusted contact identity's list of device uids")
            }
            doCreateChannel = try identityDelegate.isContactIdentityActive(ownedIdentity: ownedIdentity, contactIdentity: remoteCryptoIdentity, within: obvContext)
        } else if try identityDelegate.isOwned(remoteCryptoIdentity, within: obvContext) {
            let contactDeviceUids = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(remoteCryptoIdentity, within: obvContext)
            guard contactDeviceUids.contains(remoteDeviceUid) else {
                os_log("The device uid is not part of the remote owned identity's list of device uids", log: log, type: .fault)
                throw makeError(message: "The device uid is not part of the remote owned identity's list of device uids")
            }
            doCreateChannel = true
        } else {
            doCreateChannel = false
        }
        
        guard doCreateChannel else {
            os_log("The contact device is neither a contact device nor an owned (remote) device", log: log, type: .fault)
            throw NSError()
        }
        
        _ = ObvObliviousChannel(currentDeviceUid: currentDeviceUid,
                                remoteCryptoIdentity: remoteCryptoIdentity,
                                remoteDeviceUid: remoteDeviceUid,
                                seed: seed,
                                cryptoSuiteVersion: cryptoSuiteVersion,
                                within: obvContext)
    }
    
    
    public func confirmObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andRemoteIdentity remoteIdentity: ObvCryptoIdentity, withRemoteDeviceUid remoteDeviceUid: UID, within obvContext: ObvContext) throws {
        guard let channel = try getObliviousChannelBetween(ownedIdentity: ownedIdentity, andRemoteIdentity: remoteIdentity, withRemoteDeviceUid: remoteDeviceUid, within: obvContext) else {
            throw NSError()
        }
        channel.confirm()
    }

    
    public func updateSendSeedOfObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andRemoteIdentity remoteIdentity: ObvCryptoIdentity, withRemoteDeviceUid remoteDeviceUid: UID, with seed: Seed, within obvContext: ObvContext) throws {
        guard let channel = try getObliviousChannelBetween(ownedIdentity: ownedIdentity, andRemoteIdentity: remoteIdentity, withRemoteDeviceUid: remoteDeviceUid, within: obvContext) else {
            throw NSError()
        }
        try channel.updateSendSeed(with: seed)
    }

    
    public func updateReceiveSeedOfObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andRemoteIdentity remoteIdentity: ObvCryptoIdentity, withRemoteDeviceUid remoteDeviceUid: UID, with seed: Seed, within obvContext: ObvContext) throws {
        guard let channel = try getObliviousChannelBetween(ownedIdentity: ownedIdentity, andRemoteIdentity: remoteIdentity, withRemoteDeviceUid: remoteDeviceUid, within: obvContext) else {
            throw NSError()
        }
        try channel.createNewProvision(with: seed)
    }

    
    public func anObliviousChannelExistsBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andRemoteIdentity remoteIdentity: ObvCryptoIdentity, withRemoteDeviceUid remoteDeviceUid: UID, within obvContext: ObvContext) throws -> Bool {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvChannelDelegateManager.defaultLogSubsystem, category: ObliviousChannelLifeManager.logCategory)
            os_log("The Channel Delegate Manager is not set", log: log, type: .error)
            throw NSError()
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ObliviousChannelLifeManager.logCategory)

        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            throw NSError()
        }
        
        let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
        let channel = try ObvObliviousChannel.get(currentDeviceUid: currentDeviceUid,
                                                  remoteCryptoIdentity: remoteIdentity,
                                                  remoteDeviceUid: remoteDeviceUid,
                                                  necessarilyConfirmed: false,
                                                  within: obvContext)
        return channel != nil

    }
    
    public func aConfirmedObliviousChannelExistsBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andRemoteIdentity remoteIdentity: ObvCryptoIdentity, withRemoteDeviceUid remoteDeviceUid: UID, within obvContext: ObvContext) throws -> Bool {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvChannelDelegateManager.defaultLogSubsystem, category: ObliviousChannelLifeManager.logCategory)
            os_log("The Channel Delegate Manager is not set", log: log, type: .error)
            throw NSError()
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ObliviousChannelLifeManager.logCategory)

        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            throw NSError()
        }
        
        let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
        let channel = try ObvObliviousChannel.get(currentDeviceUid: currentDeviceUid,
                                                  remoteCryptoIdentity: remoteIdentity,
                                                  remoteDeviceUid: remoteDeviceUid,
                                                  necessarilyConfirmed: true,
                                                  within: obvContext)
        return channel != nil
    }

    
    public func aConfirmedObliviousChannelExistsBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andRemoteIdentity remoteIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvChannelDelegateManager.defaultLogSubsystem, category: ObliviousChannelLifeManager.logCategory)
            os_log("The Channel Delegate Manager is not set", log: log, type: .error)
            throw NSError()
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ObliviousChannelLifeManager.logCategory)
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            throw NSError()
        }
        
        let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
        let channels = try ObvObliviousChannel.getAllConfirmedChannels(currentDeviceUid: currentDeviceUid,
                                                                       remoteCryptoIdentity: remoteIdentity,
                                                                       within: obvContext)
        return !channels.isEmpty
        
    }
    
    private func getObliviousChannelBetween(ownedIdentity: ObvCryptoIdentity, andRemoteIdentity remoteIdentity: ObvCryptoIdentity, withRemoteDeviceUid remoteDeviceUid: UID, within obvContext: ObvContext) throws -> ObvObliviousChannel? {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvChannelDelegateManager.defaultLogSubsystem, category: ObliviousChannelLifeManager.logCategory)
            os_log("The Channel Delegate Manager is not set", log: log, type: .error)
            throw NSError()
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ObliviousChannelLifeManager.logCategory)
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            throw NSError()
        }
        
        let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
        let channel = try ObvObliviousChannel.get(currentDeviceUid: currentDeviceUid,
                                                  remoteCryptoIdentity: remoteIdentity,
                                                  remoteDeviceUid: remoteDeviceUid,
                                                  necessarilyConfirmed: false,
                                                  within: obvContext)
        return channel
    }
    
    func getAllConfirmedObliviousChannelsBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andTheDevicesOfTheRemoteIdentity remoteIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> [UID] {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvChannelDelegateManager.defaultLogSubsystem, category: ObliviousChannelLifeManager.logCategory)
            os_log("The Channel Delegate Manager is not set", log: log, type: .error)
            throw NSError()
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ObliviousChannelLifeManager.logCategory)
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            throw NSError()
        }

        let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)

        let channels = try ObvObliviousChannel.getAllConfirmedChannels(currentDeviceUid: currentDeviceUid, remoteCryptoIdentity: remoteIdentity, within: obvContext)
        
        let remoteDeviceUids = channels.map { $0.remoteDeviceUid }
        
        return remoteDeviceUids
        
    }
}
