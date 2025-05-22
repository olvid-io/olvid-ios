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
import ObvCrypto


@MainActor
final class BackupSeedsForPreviews {
    
    
    private(set) static var forPreviews: [BackupSeed] = generateRandomBackupSeeds()
    
    static let prng = ObvCryptoSuite.sharedInstance.concretePRNG().init(with: Seed(with: Data(repeating: 0x00, count: Seed.minLength))!)

    private static func generateRandomBackupSeeds() -> [BackupSeed] {
        let backupSeeds: [BackupSeed] = (0..<5).map { _ in prng.genBackupSeed() }
        return backupSeeds
    }
    
    
    static func regenerateBackupSeedsForPreviews() {
        Self.forPreviews = generateRandomBackupSeeds()
    }

}


@MainActor
extension BackupSeed {
    
    
}
