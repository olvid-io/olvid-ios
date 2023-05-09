/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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
import ObvTypes


enum OnboardingState {
    case initial(externalOlvidURL: OlvidURL?)
    case userWantsToChooseUnmanagedDetails(userIsCreatingHerFirstIdentity: Bool, externalOlvidURL: OlvidURL?)
    case userWantsToManuallyConfigureTheIdentityProvider(externalOlvidURL: OlvidURL?)
    case userWantsToRestoreBackup(externalOlvidURL: OlvidURL?)
    case userSelectedBackupFileToRestore(backupFileURL: URL, externalOlvidURL: OlvidURL?)
    case userWantsToRestoreBackupNow(backupRequestUuid: UUID, externalOlvidURL: OlvidURL?)
    case keycloakConfigAvailable(keycloakConfig: KeycloakConfiguration, isConfiguredFromMDM: Bool, externalOlvidURL: OlvidURL?)
    case keycloakUserDetailsAndStuffAvailable(keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff, keycloakState: ObvKeycloakState, externalOlvidURL: OlvidURL?)
    case shouldRequestPermission(category: AutorisationRequesterHostingController.AutorisationCategory, externalOlvidURL: OlvidURL?)
    case finalize(externalOlvidURL: OlvidURL?)
    
    var externalOlvidURL: OlvidURL? {
        switch self {
        case .initial(let externalOlvidURL):
            return externalOlvidURL
        case .userWantsToChooseUnmanagedDetails(_, let externalOlvidURL):
            return externalOlvidURL
        case .userWantsToManuallyConfigureTheIdentityProvider(let externalOlvidURL):
            return externalOlvidURL
        case .userWantsToRestoreBackup(let externalOlvidURL):
            return externalOlvidURL
        case .userSelectedBackupFileToRestore(_, let externalOlvidURL):
            return externalOlvidURL
        case .userWantsToRestoreBackupNow(_, let externalOlvidURL):
            return externalOlvidURL
        case .keycloakConfigAvailable(_, _, let externalOlvidURL):
            return externalOlvidURL
        case .keycloakUserDetailsAndStuffAvailable(_, _, _, let externalOlvidURL):
            return externalOlvidURL
        case .shouldRequestPermission(_, let externalOlvidURL):
            return externalOlvidURL
        case .finalize(let externalOlvidURL):
            return externalOlvidURL
        }
    }
    
    /// Returns a copy of the current `OnboardingState`, after setting its `externalOlvidURL`.
    func addingExternalOlvidURL(_ externalOlvidURL: OlvidURL?) -> OnboardingState {
        switch self {
        case .initial:
            return .initial(externalOlvidURL: externalOlvidURL)
        case .userWantsToChooseUnmanagedDetails(let userIsCreatingHerFirstIdentity, _):
            return .userWantsToChooseUnmanagedDetails(userIsCreatingHerFirstIdentity: userIsCreatingHerFirstIdentity, externalOlvidURL: externalOlvidURL)
        case .userWantsToManuallyConfigureTheIdentityProvider:
            return .userWantsToManuallyConfigureTheIdentityProvider(externalOlvidURL: externalOlvidURL)
        case .userWantsToRestoreBackup:
            return .userWantsToRestoreBackup(externalOlvidURL: externalOlvidURL)
        case .userSelectedBackupFileToRestore(let backupFileURL, _):
            return .userSelectedBackupFileToRestore(backupFileURL: backupFileURL, externalOlvidURL: externalOlvidURL)
        case .userWantsToRestoreBackupNow(let backupRequestUuid, _):
            return .userWantsToRestoreBackupNow(backupRequestUuid: backupRequestUuid, externalOlvidURL: externalOlvidURL)
        case .keycloakConfigAvailable(let keycloakConfig, let isConfiguredFromMDM, _):
            return .keycloakConfigAvailable(keycloakConfig: keycloakConfig, isConfiguredFromMDM: isConfiguredFromMDM, externalOlvidURL: externalOlvidURL)
        case .keycloakUserDetailsAndStuffAvailable(let keycloakUserDetailsAndStuff, let keycloakServerRevocationsAndStuff, let keycloakState, _):
            return .keycloakUserDetailsAndStuffAvailable(keycloakUserDetailsAndStuff: keycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: keycloakServerRevocationsAndStuff, keycloakState: keycloakState, externalOlvidURL: externalOlvidURL)
        case .shouldRequestPermission(let category, _):
            return .shouldRequestPermission(category: category, externalOlvidURL: externalOlvidURL)
        case .finalize(let externalOlvidURL):
            return .finalize(externalOlvidURL: externalOlvidURL)
        }
    }
    
}
