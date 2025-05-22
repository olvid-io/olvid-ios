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
import ObvCrypto
import ObvDesignSystem


@MainActor
public protocol ListOfBackupedProfilesFromServerViewModelProtocol: ObservableObject, Identifiable {
    associatedtype Profile: BackupedProfileFromServerViewModelProtocol
    var profiles: [Profile] { get }
}


protocol ListOfBackupedProfilesFromServerViewActionsProtocol: AnyObject, BackupedProfileFromServerViewActionsProtocol {
    @MainActor func userWantsToNavigateToListOfAllProfileBackups(profileCryptoId: ObvCryptoId, profileName: String, profileBackupSeed: BackupSeed)
}


struct ListOfBackupedProfilesFromServerView<Model: ListOfBackupedProfilesFromServerViewModelProtocol>: View {
        
    let title: String?
    @ObservedObject var model: Model
    let actions: any ListOfBackupedProfilesFromServerViewActionsProtocol
    let canNavigateToListOfProfileBackupsForProfilesOnDevice: Bool
    
    private struct SectionContentView: View {
        
        @ObservedObject var model: Model
        let actions: any ListOfBackupedProfilesFromServerViewActionsProtocol
        let canNavigateToListOfProfileBackupsForProfilesOnDevice: Bool
        
        private var sortedProfiles: [Model.Profile] {
            model.profiles.sorted {
                // Profiles on this device appear at the end of the list
                if $0.isOnThisDevice != $1.isOnThisDevice {
                    return $1.isOnThisDevice
                } else {
                    return $0.firstNameThenLastName < $1.firstNameThenLastName
                }
            }
        }
        
        var body: some View {
            if model.profiles.isEmpty {
                Text("NO_BACKUP_FOUND")
                    .listRowSeparator(.hidden)
            } else {
                ForEach(sortedProfiles) { profile in
                    if !profile.isOnThisDevice || canNavigateToListOfProfileBackupsForProfilesOnDevice {
                        Button {
                            actions.userWantsToNavigateToListOfAllProfileBackups(profileCryptoId: profile.ownedCryptoId, profileName: profile.firstNameThenLastName, profileBackupSeed: profile.profileBackupSeed)
                        } label: {
                            BackupedProfileFromServerView(model: profile, actions: actions, showChevron: true)
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(.init(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .buttonStyle(.plain)
                    } else {
                        BackupedProfileFromServerView(model: profile, actions: actions, showChevron: false)
                            .listRowSeparator(.hidden)
                            .listRowInsets(.init(top: 0, leading: 16, bottom: 0, trailing: 16))
                    }
                }
            }
        }
    }
    
    
    var body: some View {
        if let title {
            Section(title) {
                SectionContentView(model: model, actions: actions, canNavigateToListOfProfileBackupsForProfilesOnDevice: canNavigateToListOfProfileBackupsForProfilesOnDevice)
            }
        } else {
            Section {
                SectionContentView(model: model, actions: actions, canNavigateToListOfProfileBackupsForProfilesOnDevice: canNavigateToListOfProfileBackupsForProfilesOnDevice)
            }
        }
    }
    
}









// MARK: - Previews

#if DEBUG

private final class ActionsForPreviews: ListOfBackupedProfilesFromServerViewActionsProtocol {

    func fetchAvatarImage(profileCryptoId: ObvTypes.ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        let avatarActionsForPreviews = AvatarActionsForPreviews()
        return await avatarActionsForPreviews.fetchAvatarImage(profileCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, frameSize: frameSize)
    }
    
    func userWantsToNavigateToListOfAllProfileBackups(profileCryptoId: ObvTypes.ObvCryptoId, profileName: String, profileBackupSeed: ObvCrypto.BackupSeed) {}
}

#Preview("With section title") {
    List {
        ListOfBackupedProfilesFromServerView(title: String(localizedInThisBundle: "THIS_DEVICE_BACKUPS"),
                                             model: ListOfBackupedProfilesFromServerViewModelForPreviews(range: 0..<4),
                                             actions: ActionsForPreviews(),
                                             canNavigateToListOfProfileBackupsForProfilesOnDevice: false)
    }
    .listStyle(.plain)
    .listRowSpacing(10)
}


#Preview("Without section title") {
    List {
        ListOfBackupedProfilesFromServerView(title: nil,
                                             model: ListOfBackupedProfilesFromServerViewModelForPreviews(range: 0..<4),
                                             actions: ActionsForPreviews(),
                                             canNavigateToListOfProfileBackupsForProfilesOnDevice: true)
    }
    .listStyle(.plain)
    .listRowSpacing(10)
}


#Preview("No backup") {
    List {
        ListOfBackupedProfilesFromServerView(title: String(localizedInThisBundle: "THIS_DEVICE_BACKUPS"),
                                             model: ListOfBackupedProfilesFromServerViewModelForPreviews(range: 0..<0),
                                             actions: ActionsForPreviews(),
                                             canNavigateToListOfProfileBackupsForProfilesOnDevice: true)
    }
    .listStyle(.plain)
    .listRowSpacing(10)
}

#endif
