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
import ObvDesignSystem
import ObvCrypto
import ObvTypes


@MainActor
protocol ListOfBackupedProfilesAcrossDeviceModelProtocol: AnyObject, ObservableObject {
    associatedtype ListOfBackupedProfilesFromServerViewModel: ListOfBackupedProfilesFromServerViewModelProtocol
    var listModel: ListOfBackupedProfilesFromServerViewModel? { get }
    func onTask() async
}


protocol ListOfBackupedProfilesAcrossDeviceViewActionsProtocol: ListOfBackupedProfilesFromServerViewActionsProtocol {
    // Same methods than those specified in ListOfBackupedProfilesFromServerViewActionsProtocol
}


/// This view lists all available backuped profiles accross several backuped devices. In a way, it's the "transposed" version of `ListOfDeviceBackupsFromServerView`.
struct ListOfBackupedProfilesAcrossDeviceView<Model: ListOfBackupedProfilesAcrossDeviceModelProtocol>: View {
    
    @ObservedObject var model: Model
    let actions: any ListOfBackupedProfilesFromServerViewActionsProtocol
    let canNavigateToListOfProfileBackupsForProfilesOnDevice: Bool

    private func onTask() async {
        await model.onTask()
    }

    private struct Title: View {
        let numberOfBackupsFound: Int
        var body: some View {
            HStack(alignment: .firstTextBaseline) {
                Spacer(minLength: 0)
                ObvHeaderView(
                    title: String(localizedInThisBundle: "LIST_OF_AVAILABLE_BACKUPED_PROFILES"),
                    subtitle: String(localizedInThisBundle: "\(numberOfBackupsFound)_BACKUPED_PROFILES_FOUND"))
                Spacer(minLength: 0)
            }
        }
    }
    
    
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
        
        if let listModel = model.listModel {
            
            List {
                
                Title(numberOfBackupsFound: listModel.profiles.count)
                    .listRowSeparator(.hidden)
                    .padding(.bottom, 20)

                if !listModel.profiles.isEmpty {
                    ListOfBackupedProfilesFromServerView(title: nil,
                                                         model: listModel,
                                                         actions: actions,
                                                         canNavigateToListOfProfileBackupsForProfilesOnDevice: canNavigateToListOfProfileBackupsForProfilesOnDevice)
                }
                
                Spacer()
                    .listRowSeparator(.hidden)
                
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
private final class MergedListOfDevicesProfileBackupsFromServerViewModelForPreviews: ListOfBackupedProfilesAcrossDeviceModelProtocol {
    
    private let range: Range<Int>
    @Published private(set) var listModel: ListOfBackupedProfilesFromServerViewModelForPreviews?
    
    init(range: Range<Int>) {
        self.range = range
    }
    
    func onTask() async {
        try! await Task.sleep(seconds: 1)
        withAnimation {
            self.listModel = ListOfBackupedProfilesFromServerViewModelForPreviews(range: range)
        }

    }
    
}


private final class ActionsForPreviews: ListOfBackupedProfilesAcrossDeviceViewActionsProtocol {

    func userWantsToNavigateToListOfAllProfileBackups(profileCryptoId: ObvTypes.ObvCryptoId, profileName: String, profileBackupSeed: ObvCrypto.BackupSeed) {}
    
    func fetchAvatarImage(profileCryptoId: ObvTypes.ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        let avatarActionsForPreviews = AvatarActionsForPreviews()
        return await avatarActionsForPreviews.fetchAvatarImage(profileCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, frameSize: frameSize)
    }

}



#Preview {
    ListOfBackupedProfilesAcrossDeviceView(model: MergedListOfDevicesProfileBackupsFromServerViewModelForPreviews(range: 0..<2),
                                           actions: ActionsForPreviews(), canNavigateToListOfProfileBackupsForProfilesOnDevice: true)
}

#endif
