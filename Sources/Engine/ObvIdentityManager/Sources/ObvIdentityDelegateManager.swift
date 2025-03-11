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
import ObvCrypto
import ObvMetaManager

final class ObvIdentityDelegateManager {
    
    let sharedContainerIdentifier: String
    let identityPhotosDirectory: URL
    let prng: PRNGService

    static let defaultLogSubsystem = "io.olvid.identity"
    private(set) var logSubsystem = ObvIdentityDelegateManager.defaultLogSubsystem
    
    func prependLogSubsystem(with prefix: String) {
        logSubsystem = "\(prefix).\(logSubsystem)"
    }
    
    let queueForPostingNotifications = DispatchQueue(label: "ObvIdentityDelegateManager queue for posting notifications")

    // MARK: Internal delegates
    
    // None

    // MARK: Instance variables (external delegates). Thanks to a mecanism within the DelegateManager, we know for sure that these delegates will be instantiated by the time the Manager is fully initialized. So we can safely force unwrapping.
    
    weak var contextCreator: ObvCreateContextDelegate!
    weak var notificationDelegate: ObvNotificationDelegate!
    weak var networkFetchDelegate: ObvNetworkFetchDelegate?
    
    init(sharedContainerIdentifier: String, identityPhotosDirectory: URL, prng: PRNGService) {
        self.sharedContainerIdentifier = sharedContainerIdentifier
        self.identityPhotosDirectory = identityPhotosDirectory
        self.prng = prng
    }
}
