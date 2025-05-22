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
public protocol ListOfBackupedProfilesPerDeviceModelProtocol: AnyObject, ObservableObject {
    associatedtype ListOfBackupedProfilesFromServerViewModel: ListOfBackupedProfilesFromServerViewModelProtocol
    var profilesBackedUpByThisDevice: ListOfBackupedProfilesFromServerViewModel? { get }
    var profilesBackupByAnotherDevice: [ListOfBackupedProfilesFromServerViewModel] { get }
    func onTask() async
}


protocol ListOfBackupedProfilesPerDeviceViewActionsProtocol: ListOfBackupedProfilesAcrossDeviceViewActionsProtocol {
    // Same methods than those specified in ListOfBackupedProfilesAcrossDeviceViewActionsProtocol
}


/// View that requests the download of a device backup from server then shows the included profiles
struct ListOfBackupedProfilesPerDeviceView<Model: ListOfBackupedProfilesPerDeviceModelProtocol>: View {
    
    @ObservedObject var model: Model
    let actions: any ListOfBackupedProfilesPerDeviceViewActionsProtocol
    let canNavigateToListOfProfileBackupsForProfilesOnDevice: Bool
    

    private func onTask() async {
        await model.onTask()
    }
    
    
    private struct Title: View {
        var body: some View {
            HStack(alignment: .firstTextBaseline) {
                Spacer(minLength: 0)
                ObvHeaderView(
                    title: String(localizedInThisBundle: "LIST_OF_AVAILABLE_BACKUPED_PROFILES"),
                    subtitle: nil)
                Spacer(minLength: 0)
            }
        }
    }
    

    private let titleThisDevice = String(localizedInThisBundle: "THIS_DEVICE_BACKUPS")
    private let titleOtherDevice = String(localizedInThisBundle: "OTHER_DEVICE_BACKUPS")
    
    
    private struct WaitingView: View {
        var body: some View {
            VStack {
                ProgressView()
                    .padding()
                    .progressViewStyle(.circular)
                Text("ONE_MOMENT_PLEASE")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                Text("PLEASE_WAIT_WHILE_WE_LOAD_THE_BACKUPS")
                    .multilineTextAlignment(.center)
                    .font(.headline)
            }
        }
    }


    var body: some View {

        if let profilesBackedUpByThisDevice = model.profilesBackedUpByThisDevice {
            
            List {
                
                Title()
                    .listRowSeparator(.hidden)
                    .padding(.bottom, 20)

                ListOfBackupedProfilesFromServerView(title: titleThisDevice,
                                                     model: profilesBackedUpByThisDevice,
                                                     actions: actions,
                                                     canNavigateToListOfProfileBackupsForProfilesOnDevice: canNavigateToListOfProfileBackupsForProfilesOnDevice)
                ForEach(model.profilesBackupByAnotherDevice.filter({ !$0.profiles.isEmpty })) { profiles in
                    ListOfBackupedProfilesFromServerView(title: titleOtherDevice,
                                                         model: profiles,
                                                         actions: actions,
                                                         canNavigateToListOfProfileBackupsForProfilesOnDevice: canNavigateToListOfProfileBackupsForProfilesOnDevice)
                }
            }
            .listStyle(.plain)
            .listRowSpacing(10)

        } else {
            
            WaitingView()
                .task(onTask)

        }
        
    }
}



// MARK: - Previews

#if DEBUG

@MainActor
private final class ModelForPreviews: ListOfBackupedProfilesPerDeviceModelProtocol {
    
    @Published private(set) var profilesBackedUpByThisDevice: ListOfBackupedProfilesFromServerViewModelForPreviews?
    @Published private(set) var profilesBackupByAnotherDevice: [ListOfBackupedProfilesFromServerViewModelForPreviews]

    
    init() {
        self.profilesBackedUpByThisDevice = nil
        self.profilesBackupByAnotherDevice = []
    }

    func onTask() async {

        try! await Task.sleep(for: 2)
        
        let profilesBackedUpByThisDevice = ListOfBackupedProfilesFromServerViewModelForPreviews(range: 0..<2)
        withAnimation {
            self.profilesBackedUpByThisDevice = profilesBackedUpByThisDevice
        }

        try! await Task.sleep(for: 1)

        do {
            let profilesBackupByOtherDevice = ListOfBackupedProfilesFromServerViewModelForPreviews(range: 1..<3)
            withAnimation {
                self.profilesBackupByAnotherDevice.append(profilesBackupByOtherDevice)
            }
        }

        try! await Task.sleep(for: 1)

        do {
            let profilesBackupByOtherDevice = ListOfBackupedProfilesFromServerViewModelForPreviews(range: 2..<4)
            withAnimation {
                self.profilesBackupByAnotherDevice.append(profilesBackupByOtherDevice)
            }
        }
        
    }
    
}


private final class ActionsForPreviews: ListOfBackupedProfilesPerDeviceViewActionsProtocol {

    func userWantsToNavigateToListOfAllProfileBackups(profileCryptoId: ObvCryptoId, profileName: String, profileBackupSeed: ObvCrypto.BackupSeed) {}
    
    func fetchAvatarImage(profileCryptoId: ObvTypes.ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        let avatarActionsForPreviews = AvatarActionsForPreviews()
        return await avatarActionsForPreviews.fetchAvatarImage(profileCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, frameSize: frameSize)
    }

}


#Preview {
    ListOfBackupedProfilesPerDeviceView(model: ModelForPreviews(), actions: ActionsForPreviews(), canNavigateToListOfProfileBackupsForProfilesOnDevice: true)
}

#endif
