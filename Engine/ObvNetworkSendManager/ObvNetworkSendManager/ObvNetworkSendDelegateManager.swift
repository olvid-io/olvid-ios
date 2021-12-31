/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

/// As all managers, we expect this one to be uniquely instantiated (i.e., a singleton). The ObvNetworkSendManagerImplementation holds a strong reference to this manager. This manager holds a strong reference to:
/// - All coordinators (which are singleton)
/// - All delegate requirements of this framework (at this time, only one, conforming to `ObvCreateNSManagedObjectContextDelegate`).
/// This architecture ensures that all managers and coordinator do not leave the heap. All other references to these managers and coordinators (including this one) should be weak to avoid memory cycles.
final class ObvNetworkSendDelegateManager {

    let sharedContainerIdentifier: String
    let supportBackgroundFetch: Bool
    
    static let defaultLogSubsystem = "io.olvid.network.send"
    private(set) var logSubsystem = ObvNetworkSendDelegateManager.defaultLogSubsystem
    
    func prependLogSubsystem(with prefix: String) {
        logSubsystem = "\(prefix).\(logSubsystem)"
    }
    
    // MARK: Instance variables (internal delegates)
    
    let uploadMessageAndGetUidsDelegate: UploadMessageAndGetUidDelegate
    let networkSendFlowDelegate: NetworkSendFlowDelegate
    let uploadAttachmentChunksDelegate: UploadAttachmentChunksDelegate
    let tryToDeleteMessageAndAttachmentsDelegate: TryToDeleteMessageAndAttachmentsDelegate

    // MARK: Instance variables (external delegates)

    var contextCreator: ObvCreateContextDelegate?
    var notificationDelegate: ObvNotificationDelegate?
    weak var channelDelegate: ObvChannelDelegate?
    weak var identityDelegate: ObvIdentityDelegate?
    var simpleFlowDelegate: ObvSimpleFlowDelegate? // DEBUG 2019-10-17 Allows to keep a strong reference to the simpleFlowDelegate, required when uploading large attachment within the share extension

    // MARK: Initialiazer
    
    init(sharedContainerIdentifier: String, supportBackgroundFetch: Bool, networkSendFlowDelegate: NetworkSendFlowDelegate, uploadMessageAndGetUidsDelegate: UploadMessageAndGetUidDelegate, uploadAttachmentChunksDelegate: UploadAttachmentChunksDelegate, tryToDeleteMessageAndAttachmentsDelegate: TryToDeleteMessageAndAttachmentsDelegate) {
        self.sharedContainerIdentifier = sharedContainerIdentifier
        self.supportBackgroundFetch = supportBackgroundFetch
        self.networkSendFlowDelegate = networkSendFlowDelegate
        self.uploadMessageAndGetUidsDelegate = uploadMessageAndGetUidsDelegate
        self.uploadAttachmentChunksDelegate = uploadAttachmentChunksDelegate
        self.tryToDeleteMessageAndAttachmentsDelegate = tryToDeleteMessageAndAttachmentsDelegate
    }
    
}
