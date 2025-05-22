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

import UIKit
import SwiftUI
import ObvDesignSystem
import ObvTypes


protocol ListOfBackupedProfilesPerDeviceModelDelegate: AnyObject {
    @MainActor func userWantsToFetchDeviceBakupFromServer(_ model: ListOfBackupedProfilesPerDeviceModel) async throws -> AsyncStream<ObvDeviceBackupFromServerWithAppInfoKind>
}


/// The engine's backup manager produces an async sequence of `ObvTypes.ObvDeviceBackupFromServerKind`. The App loops through this sequence and augments the
/// received values to create `ObvDeviceBackupFromServerWithAppInfoKind` elements that we receive here.
public enum ObvDeviceBackupFromServerWithAppInfoKind: Sendable {
    // Device backup key found on this physical device
    case thisPhysicalDeviceHasNoBackupSeed
    case errorOccuredForFetchingBackupOfThisPhysicalDevice(error: Error)
    case thisPhysicalDevice(ObvListOfDeviceBackupProfiles)
    // Device backup key found in the keychain
    case keychain(ObvListOfDeviceBackupProfiles)
    case errorOccuredForFetchingBackupsFromKeychain(error: Error)
}


/// In practice, this is instantiated by the MetaFlowController so it must be public.
@MainActor
public final class ListOfBackupedProfilesPerDeviceModel: ListOfBackupedProfilesPerDeviceModelProtocol {
        
    @Published public private(set) var profilesBackedUpByThisDevice: ObvListOfDeviceBackupProfiles?
    @Published public private(set) var profilesBackupByAnotherDevice = [ListOfBackupedProfilesFromServerViewModel]()
    
    weak var delegate: ListOfBackupedProfilesPerDeviceModelDelegate?
    
    
    
    public func onTask() async {
        guard let delegate = delegate else { assertionFailure(); return }
        do {
            for try await deviceBackupFromServerKind in try await delegate.userWantsToFetchDeviceBakupFromServer(self) {
                switch deviceBackupFromServerKind {
                case .thisPhysicalDeviceHasNoBackupSeed:
                    profilesBackedUpByThisDevice = .init(profiles: [])
                case .errorOccuredForFetchingBackupOfThisPhysicalDevice(error: _):
                    profilesBackedUpByThisDevice = .init(profiles: [])
                case .thisPhysicalDevice(let profiles):
                    withAnimation {
                        profilesBackedUpByThisDevice = profiles
                    }
                case .keychain(let profiles):
                    self.profilesBackupByAnotherDevice.append(profiles)
                case .errorOccuredForFetchingBackupsFromKeychain(error: _):
                    continue
                }
            }
        } catch {
            assertionFailure()
        }
    }
    
    enum ObvError: Error {
        case delegateIsNil
    }
    
}
