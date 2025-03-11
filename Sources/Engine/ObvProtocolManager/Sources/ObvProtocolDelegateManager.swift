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

final class ObvProtocolDelegateManager {
    
    static let defaultLogSubsystem = "io.olvid.protocol"
    private(set) var logSubsystem = ObvProtocolDelegateManager.defaultLogSubsystem
    
    func prependLogSubsystem(with prefix: String) {
        logSubsystem = "\(prefix).\(logSubsystem)"
    }

    // MARK: Instance variables (internal delegates)

    let downloadedUserData: URL
    
    /// Directory where we store, e.g., photos during their upload.
    /// This directory is regularly cleaned (deleting files older than 15 days).
    let uploadingUserData: URL

    let receivedMessageDelegate: ReceivedMessageDelegate
    let protocolStarterDelegate: ProtocolStarterDelegate
    let contactTrustLevelWatcher: ContactTrustLevelWatcher // Not exactly a delegate, but still
    
    // MARK: Instance variables (external delegates)
    // Only when the `contextCreator`, the `notificationDelegate`, and the `identityDelegate` are set, the `ProtocolStarterCoordinator` can observe notifications. We notify the `ProtocolStarterCoordinator` each time one of these delegates is set. The third time, the `ProtocolStarterCoordinator` will automatically subscribe to notifications. Thanks to a mecanism within the DelegateManager, we know for sure that these delegates will be instantiated by the time the Manager is fully initialized. So we can safely force unwrapping.

    weak var channelDelegate: ObvChannelDelegate?
    weak var contextCreator: ObvCreateContextDelegate?
    weak var identityDelegate: ObvIdentityDelegate?
    weak var notificationDelegate: ObvNotificationDelegate?
    weak var solveChallengeDelegate: ObvSolveChallengeDelegate?
    weak var networkPostDelegate: ObvNetworkPostDelegate?
    weak var networkFetchDelegate: ObvNetworkFetchDelegate?
    weak var syncSnapshotDelegate: ObvSyncSnapshotDelegate?

    // MARK: Initialiazer
    init(downloadedUserData: URL, uploadingUserData: URL, receivedMessageDelegate: ReceivedMessageDelegate, protocolStarterDelegate: ProtocolStarterDelegate, contactTrustLevelWatcher: ContactTrustLevelWatcher) {
        self.downloadedUserData = downloadedUserData
        self.uploadingUserData = uploadingUserData
        self.receivedMessageDelegate = receivedMessageDelegate
        self.protocolStarterDelegate = protocolStarterDelegate
        self.contactTrustLevelWatcher = contactTrustLevelWatcher
    }
    
}
