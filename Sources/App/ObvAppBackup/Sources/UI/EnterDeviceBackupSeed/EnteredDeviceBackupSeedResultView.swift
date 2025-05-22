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
import ObvTypes
import ObvDesignSystem
import ObvCrypto

protocol EnteredDeviceBackupSeedResultViewActionsProtocol: ListOfBackupedProfilesFromServerViewActionsProtocol {
    // No additional method for now
}


struct EnteredDeviceBackupSeedResultView<ListModel: ListOfBackupedProfilesFromServerViewModelProtocol>: View {

    let listModel: ListModel
    let actions: EnteredDeviceBackupSeedResultViewActionsProtocol
    let canNavigateToListOfProfileBackupsForProfilesOnDevice: Bool

    private let listTitle = String(localizedInThisBundle: "AVAILABLE_BACKUPED_PROFILES_FOR_THIS_KEY")

    var body: some View {
        List {
            
            HStack {
                Spacer(minLength: 0)
                ObvHeaderView(title: String(localizedInThisBundle: "AVAILABLE_BACKUPED_PROFILES_FOR_THIS_KEY"),
                              subtitle: nil)
                Spacer(minLength: 0)
            }
            .listRowSeparator(.hidden)
            .padding(.bottom, 20)
            
            ListOfBackupedProfilesFromServerView(title: nil,
                                                 model: listModel,
                                                 actions: actions,
                                                 canNavigateToListOfProfileBackupsForProfilesOnDevice: canNavigateToListOfProfileBackupsForProfilesOnDevice)
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .listRowSpacing(10)
    }
    
}


// MARK: - Previews

#if DEBUG

@MainActor
private final class ActionsForPreviews: EnteredDeviceBackupSeedResultViewActionsProtocol {

    func userWantsToNavigateToListOfAllProfileBackups(profileCryptoId: ObvCryptoId, profileName: String, profileBackupSeed: ObvCrypto.BackupSeed) {}

    func fetchAvatarImage(profileCryptoId: ObvTypes.ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        let actions = AvatarActionsForPreviews()
        return await actions.fetchAvatarImage(profileCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, frameSize: frameSize)
    }
    
}

@MainActor
private let listModelForPreviews = ListOfBackupedProfilesFromServerViewModelForPreviews(range: 0..<2)

private let actionsForPreviews = ActionsForPreviews()

#Preview {
    EnteredDeviceBackupSeedResultView(listModel: listModelForPreviews,
                                      actions: actionsForPreviews,
                                      canNavigateToListOfProfileBackupsForProfilesOnDevice: true)
}

#endif
