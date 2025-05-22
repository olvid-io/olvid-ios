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
import ObvTypes
import ObvAppCoreConstants


@MainActor
struct ProfileBackupsForPreviews {
    
    static let prng = ObvCryptoSuite.sharedInstance.concretePRNG().init(with: Seed(with: Data(repeating: 0x00, count: Seed.minLength))!)
    static let serverURL = URL(string: "https://fake.server.olvid.io")!
    
    static let profileBackups: [ObvProfileBackupFromServer] = [
        .init(ownedCryptoId: PreviewsHelper.cryptoIds.first!,
              profileExistsOnThisDevice: false,
              parsedData: .init(numberOfGroups: 32,
                                numberOfContacts: 42,
                                isKeycloakManaged: .no,
                                encodedPhotoServerKeyAndLabel: nil,
                                ownedCryptoIdentity: ObvOwnedCryptoIdentity.gen(withServerURL: serverURL, using: prng),
                                coreDetails: PreviewsHelper.coreDetails[0]),
              identityNode: NodeForPreviews(),
              appNode: NodeForPreviews(),
              additionalInfosForProfileBackup: .init(
                nameOfDeviceWhichPerformedBackup: "Alice's iPad",
                platformOfDeviceWhichPerformedBackup: .iPad),
              creationDate: Date.now,
              backupSeed: BackupSeed(with: Data(repeating: 0, count: 20))!,
              threadUID: UID.zero,
              backupVersion: 0,
              backupMadeByThisDevice: true),
        .init(ownedCryptoId: PreviewsHelper.cryptoIds.first!,
              profileExistsOnThisDevice: true,
              parsedData: .init(numberOfGroups: 32,
                                numberOfContacts: 42,
                                isKeycloakManaged: .no,
                                encodedPhotoServerKeyAndLabel: nil,
                                ownedCryptoIdentity: ObvOwnedCryptoIdentity.gen(withServerURL: serverURL, using: prng),
                                coreDetails: PreviewsHelper.coreDetails[1]),
              identityNode: NodeForPreviews(),
              appNode: NodeForPreviews(),
              additionalInfosForProfileBackup: .init(
                nameOfDeviceWhichPerformedBackup: "Alice's iPhone",
                platformOfDeviceWhichPerformedBackup: .iPhone),
              creationDate: Date.now.advanced(by: -10_000),
              backupSeed: BackupSeed(with: Data(repeating: 1, count: 20))!,
              threadUID: UID.zero,
              backupVersion: 0,
              backupMadeByThisDevice: false),
        .init(ownedCryptoId: PreviewsHelper.cryptoIds.first!,
              profileExistsOnThisDevice: true,
              parsedData: .init(numberOfGroups: 12,
                                numberOfContacts: 22,
                                isKeycloakManaged: .no,
                                encodedPhotoServerKeyAndLabel: nil,
                                ownedCryptoIdentity: ObvOwnedCryptoIdentity.gen(withServerURL: serverURL, using: prng),
                                coreDetails: PreviewsHelper.coreDetails[2]),
              identityNode: NodeForPreviews(),
              appNode: NodeForPreviews(),
              additionalInfosForProfileBackup: .init(
                nameOfDeviceWhichPerformedBackup: "Windows",
                platformOfDeviceWhichPerformedBackup: .windows),
              creationDate: Date.now.advanced(by: -100_000),
              backupSeed: BackupSeed(with: Data(repeating: 2, count: 20))!,
              threadUID: UID.zero,
              backupVersion: 0,
              backupMadeByThisDevice: false),
    ]
    
}

private struct NodeForPreviews: ObvSyncSnapshotNode {
    var id = UUID()
}
