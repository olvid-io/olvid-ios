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

import SwiftUI
import ObvCrypto
import ObvTypes


/// `public` as this protocol is used during onboarding
public protocol ObvListOfProfileBackupsDelegate: AnyObject {
    @MainActor func userWantsToFetchAllProfileBackupsFromServer(_ model: ObvListOfProfileBackups, profileCryptoId: ObvCryptoId, profileBackupSeed: ObvCrypto.BackupSeed) async throws -> [ObvProfileBackupFromServer]
}



/// `public` as this view is used during onboarding
@MainActor
public final class ObvListOfProfileBackups: ListOfBackupsOfProfileViewModelProtocol {
    
    let profileCryptoId: ObvCryptoId
    public let profileBackupSeed: ObvCrypto.BackupSeed
    @Published public private(set) var listOfProfileBackups: ListOfProfileBackupsFromServerView.Model?
    
    private weak var delegate: ObvListOfProfileBackupsDelegate?
    
    /// `public` as this view is used during onboarding
    public init(profileCryptoId: ObvCryptoId, profileBackupSeed: ObvCrypto.BackupSeed, delegate: ObvListOfProfileBackupsDelegate) {
        self.profileCryptoId = profileCryptoId
        self.profileBackupSeed = profileBackupSeed
        self.listOfProfileBackups = nil
        self.delegate = delegate
    }
    
    public func fetchListOfProfileBackups() async {
        do {
            guard let delegate else { assertionFailure(); return }
            var allProfileBackups: [ObvProfileBackupFromServer] = try await delegate.userWantsToFetchAllProfileBackupsFromServer(self, profileCryptoId: profileCryptoId, profileBackupSeed: self.profileBackupSeed)
            allProfileBackups.sort(by: { $0.creationDate > $1.creationDate })
            guard let mostRecentProfileBackup = allProfileBackups.first else {
                listOfProfileBackups = .init(profileBackups: [], recommendedProfileBackup: nil)
                return
            }
            withAnimation {
                self.listOfProfileBackups = .init(profileBackups: allProfileBackups, recommendedProfileBackup: mostRecentProfileBackup)
            }
        } catch {
            withAnimation {
                listOfProfileBackups = .init(profileBackups: [], recommendedProfileBackup: nil)
            }
        }
    }
    
}
