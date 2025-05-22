/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import OSLog
import CoreData
import OlvidUtils
import ObvMetaManager


final class DeleteObsoleteObliviousChannelsOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private let channelDelegate: any ObvChannelDelegate
    private let identityDelegate: any ObvIdentityDelegate
    private let logger: Logger
    
    init(channelDelegate: any ObvChannelDelegate, identityDelegate: any ObvIdentityDelegate, logSubsystem: String) {
        self.channelDelegate = channelDelegate
        self.identityDelegate = identityDelegate
        self.logger = Logger(subsystem: logSubsystem, category: "DeleteObsoleteObliviousChannelsOperation")
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        // Get the remote device uids associated to all the oblivious channels we have
        let remoteDeviceUidsAssociatedToAnObliviousChannel: Set<ObliviousChannelIdentifier>
        do {
            remoteDeviceUidsAssociatedToAnObliviousChannel = try channelDelegate.getAllRemoteDeviceUidsAssociatedToAnObliviousChannel(within: obvContext)
        } catch let error {
            logger.fault("Could not get all remote device uids associated to an oblivious channel: \(error.localizedDescription)")
            assertionFailure()
            return
        }
        
        // Get the remote device uids associated to all the device we have within the identity manager

        let remoteDeviceUidsKnownToTheIdentityManager: Set<ObliviousChannelIdentifier>
        do {
            remoteDeviceUidsKnownToTheIdentityManager = try identityDelegate.getAllRemoteOwnedDevicesUidsAndContactDeviceUids(within: obvContext)
        } catch let error {
            logger.fault("Could not get all device uids known to the identity manager: \(error.localizedDescription)")
            assertionFailure()
            return
        }
        
        // Get a set of device corresponding to obsolete oblivious channels
        
        let obsoleteObliviousChannels = remoteDeviceUidsAssociatedToAnObliviousChannel.subtracting(remoteDeviceUidsKnownToTheIdentityManager)
        
        // Delete all the obsolete oblivious channels
        
        logger.info("[Bootstraping] Number of obsolete oblivious channels to delete: \(obsoleteObliviousChannels.count)")
        
        for obsoleteChannel in obsoleteObliviousChannels {
            do {
                try channelDelegate.deleteObliviousChannelBetweenCurentDeviceWithUid(currentDeviceUid: obsoleteChannel.currentDeviceUid,
                                                                                     andTheRemoteDeviceWithUid: obsoleteChannel.remoteDeviceUid,
                                                                                     ofRemoteIdentity: obsoleteChannel.remoteCryptoIdentity,
                                                                                     within: obvContext)
            } catch let error {
                logger.fault("Could not delete an obsolete oblivious channel: \(error.localizedDescription)")
                assertionFailure()
                // Continue anyway
            }
        }

    }
    
}
