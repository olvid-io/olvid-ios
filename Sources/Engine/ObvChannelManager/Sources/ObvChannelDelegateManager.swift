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
import ObvMetaManager

final class ObvChannelDelegateManager {
    
    static let defaultLogSubsystem = "io.olvid.channel"
    private(set) var logSubsystem = ObvChannelDelegateManager.defaultLogSubsystem
    
    func prependLogSubsystem(with prefix: String) {
        logSubsystem = "\(prefix).\(logSubsystem)"
    }

    // MARK: Instance variables (internal delegates)
    
    let networkReceivedMessageDecryptorDelegate: NetworkReceivedMessageDecryptorDelegate
    let obliviousChannelLifeDelegate: ObliviousChannelLifeDelegate
    
    // MARK: Instance variables (external delegates). Thanks to a mecanism within the DelegateManager, we know for sure that these delegates will be instantiated by the time the Manager is fully initialized. So we can safely force unwrapping.
    
    weak var obvUserInterfaceChannelDelegate: ObvUserInterfaceChannelDelegate?
    weak var identityDelegate: ObvIdentityDelegate?
    weak var keyWrapperForIdentityDelegate: ObvKeyWrapperForIdentityDelegate?
    weak var networkPostDelegate: ObvNetworkPostDelegate?
    weak var networkFetchDelegate: ObvNetworkFetchDelegate?
    weak var protocolDelegate: ObvProtocolDelegate?
    weak var fullRatchetProtocolStarterDelegate: ObvFullRatchetProtocolStarterDelegate?
    weak var notificationDelegate: ObvNotificationDelegate?
    
    // MARK: Initialiazer
    
    init(networkReceivedMessageDecryptorDelegate: NetworkReceivedMessageDecryptorDelegate, obliviousChannelLifeDelegate: ObliviousChannelLifeDelegate) {
        self.networkReceivedMessageDecryptorDelegate = networkReceivedMessageDecryptorDelegate
        self.obliviousChannelLifeDelegate = obliviousChannelLifeDelegate
    }
}
