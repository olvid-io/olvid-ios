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


/// This view is intended to be included in a `List` and shows the backups made of a single profile.
/// It expects one, and only one, profile to be such that `isRecommended` is `true`.
/// `public` as this view is used during onboarding.
public struct ListOfProfileBackupsFromServerView: View {
    
    let model: Model
    let context: ContextOfListOfBackupsOfProfile
    @Binding private var selectedProfileBackup: ObvProfileBackupFromServer?
    let refreshListRequested: () async -> Void
    @State private var deletionOrRestorationInProgress: Bool = false

    public struct Model {
        let profileBackups: [ObvProfileBackupFromServer]
        let recommendedProfileBackup: ObvProfileBackupFromServer?
    }

    init(model: Model, context: ContextOfListOfBackupsOfProfile, selectedProfileBackup: Binding<ObvProfileBackupFromServer?>, refreshListRequested: @escaping () async -> Void) {
        self.model = model
        self._selectedProfileBackup = selectedProfileBackup
        self.context = context
        self.refreshListRequested = refreshListRequested
    }
    
    public var body: some View {
        ForEach(model.profileBackups) { profileBackup in
            ProfileBackupsFromServerView(model: profileBackup,
                                         context: context,
                                         isRecommended: profileBackup.id == model.recommendedProfileBackup?.id,
                                         selectedBackup: $selectedProfileBackup,
                                         deletionOrRestorationInProgress: $deletionOrRestorationInProgress,
                                         refreshListRequested: refreshListRequested)
            .disabled(deletionOrRestorationInProgress)
            .listRowSeparator(.hidden)
            .listRowInsets(.init(top: 1, leading: 1, bottom: 1, trailing: 1))
        }
    }
}



// MARK: - Previews

#if DEBUG

private struct HelperForPreview: View {
    
    @State private var selectedProfileBackup: ObvProfileBackupFromServer?
    private let model: ListOfProfileBackupsFromServerView.Model
    private let context: ContextOfListOfBackupsOfProfile
    
    init(context: ContextOfListOfBackupsOfProfile) {
        let model = ListOfProfileBackupsFromServerView.Model(
            profileBackups: ProfileBackupsForPreviews.profileBackups,
            recommendedProfileBackup: ProfileBackupsForPreviews.profileBackups.first!)
        self.model = model
        self.selectedProfileBackup = ProfileBackupsForPreviews.profileBackups.first!
        self.context = context
    }
    
    var body: some View {
        ListOfProfileBackupsFromServerView(model: model, context: context, selectedProfileBackup: $selectedProfileBackup, refreshListRequested: {})
    }
}


private final class OtherActionsForPreviews: ContextOfListOfBackupsOfProfileSettingsActionsDelegate {
    func userWantsToRestoreProfileBackupFromSettingsMenu(profileBackupFromServer: ObvTypes.ObvProfileBackupFromServer) async throws {
        try? await Task.sleep(seconds: 3)
    }
    func userWantsToDeleteProfileBackupFromSettingsMenu(infoForDeletion: ObvTypes.ObvProfileBackupFromServer.InfoForDeletion) async throws {
        try? await Task.sleep(seconds: 3)
    }
}


#Preview("For onboarding") {
    List {
        HelperForPreview(context: .onboarding)
    }
    .listStyle(.plain)
    .listRowSpacing(10)
    .padding()
}

#Preview("For settings") {
    List {
        HelperForPreview(context: .settings(actions: OtherActionsForPreviews()))
    }
    .listStyle(.plain)
    .listRowSpacing(10)
    .padding()
}

#endif
