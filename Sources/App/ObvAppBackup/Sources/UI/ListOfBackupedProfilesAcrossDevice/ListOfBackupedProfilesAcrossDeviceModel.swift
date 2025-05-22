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


protocol ListOfBackupedProfilesAcrossDeviceModelDelegate: AnyObject {
    @MainActor func userWantsToFetchDeviceBakupFromServer(_ model: ListOfBackupedProfilesAcrossDeviceModel) async throws -> AsyncStream<ObvDeviceBackupFromServerWithAppInfoKind>
}


@MainActor
final class ListOfBackupedProfilesAcrossDeviceModel: ListOfBackupedProfilesAcrossDeviceModelProtocol {
    
    @Published private(set) var listModel: ObvListOfDeviceBackupProfiles?
    
    /// We don't want to show the backups progressively. So we accumulate them until we are sure we have them all.
    private var accumulatedListModel = ObvListOfDeviceBackupProfiles(profiles: [])
    
    weak var delegate: ListOfBackupedProfilesAcrossDeviceModelDelegate?

    func onTask() async {
        guard let delegate = delegate else { assertionFailure(); return }
        do {
            for try await deviceBackupFromServerKind in try await delegate.userWantsToFetchDeviceBakupFromServer(self) {
                switch deviceBackupFromServerKind {
                case .thisPhysicalDeviceHasNoBackupSeed:
                    continue
                case .errorOccuredForFetchingBackupOfThisPhysicalDevice(error: _):
                    continue
                case .thisPhysicalDevice(let profiles):
                    accumulatedListModel.insertProfileIfNotAlreadyExisting(profiles.profiles)
                case .keychain(let profiles):
                    accumulatedListModel.insertProfileIfNotAlreadyExisting(profiles.profiles)
                case .errorOccuredForFetchingBackupsFromKeychain(error: _):
                    continue
                }
            }
            withAnimation {
                listModel = accumulatedListModel
            }
        } catch {
            assertionFailure()
        }
    }

}
