/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvCrypto
import Contacts
import ObvKeycloakManager


enum NewOnboardingState {
    
    enum ProfileKind {
        case unmanaged(ownedCryptoId: ObvCryptoId)
        case keycloakManaged(ownedCryptoId: ObvCryptoId)
        case backupRestored(ownedCryptoId: ObvCryptoId)
        case transferred(ownedCryptoId: ObvCryptoId, postTransferError: Error?)
        var ownedCryptoId: ObvCryptoId {
            switch self {
            case .unmanaged(let ownedCryptoId),
                    .keycloakManaged(let ownedCryptoId),
                    .backupRestored(let ownedCryptoId),
                    .transferred(let ownedCryptoId, _):
                return ownedCryptoId
            }
        }
    }
    
    case initial
    case userWantsToChooseUnmanagedDetails
    case userIndicatedSheHasAnExistingProfile
    case userWantsToManuallyConfigureTheIdentityProvider
    case userWantsToRestoreSomeBackup
    case userWantsToChooseNameForCurrentDevice
    case userWantsToRestoreThisEncryptedBackup(encryptedBackup: Data)
    case userWantsToRestoreThisDecryptedBackup(backupRequestIdentifier: UUID)
    case keycloakConfigAvailable(keycloakConfiguration: ObvKeycloakConfiguration, isConfiguredFromMDM: Bool)
    case keycloakUserDetailsAndStuffAvailable(keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff, keycloakState: ObvKeycloakState)
    case shouldRequestPermission(profileKind: ProfileKind, category: NewAutorisationRequesterViewController.AutorisationCategory)
    case finalize(profileKind: ProfileKind)
    
    // States while transfering an owned identity
    case finalOwnedIdentityTransferCheckOnSourceDevice(ownedCryptoId: ObvCryptoId, ownedDetails: CNContact, enteredSAS: ObvOwnedIdentityTransferSas, ownedDeviceDiscoveryResult: ObvOwnedDeviceDiscoveryResult, targetDeviceName: String, protocolInstanceUID: UID, deviceToKeepActive: ObvOwnedDeviceDiscoveryResult.Device?)
    case userMustChooseDeviceToKeepActiveOnSourceDevice(ownedCryptoId: ObvCryptoId, ownedDetails: CNContact, enteredSAS: ObvOwnedIdentityTransferSas, ownedDeviceDiscoveryResult: ObvOwnedDeviceDiscoveryResult, currentDeviceIdentifier: Data, targetDeviceName: String, protocolInstanceUID: UID)
    case userMustEnterSASOnSourceDevice(sasExpectedOnInput: ObvOwnedIdentityTransferSas, targetDeviceName: String, ownedCryptoId: ObvCryptoId, ownedDetails: CNContact, protocolInstanceUID: UID)
    case userWantsToDisplaySasOnThisTargetDevice(currentDeviceName: String, protocolInstanceUID: UID, sas: ObvOwnedIdentityTransferSas)
    case userWantsToEnterTransferCode(currentDeviceName: String)
    case successfulTransferWasPerfomed(transferredOwnedCryptoId: ObvCryptoId, postTransferError: Error?)
    case showOwnedIdentityTransferFailed(error: Error)
    case userWantsToProceedWithAddingDevice(ownedCryptoId: ObvCryptoId, ownedDetails: CNContact)

    
    var currentDeviceName: String? {
        switch self {
        case .userWantsToEnterTransferCode(currentDeviceName: let currentDeviceName),
                .userWantsToDisplaySasOnThisTargetDevice(currentDeviceName: let currentDeviceName, protocolInstanceUID: _, sas: _):
            return currentDeviceName
        default:
            return nil
        }
    }
    
    
    var ownedIdentityTransferProtocolInstanceUID: UID? {
        switch self {
        case .initial,
                .userWantsToChooseUnmanagedDetails,
                .userIndicatedSheHasAnExistingProfile,
                .userWantsToRestoreSomeBackup,
                .userWantsToChooseNameForCurrentDevice,
                .userWantsToRestoreThisEncryptedBackup,
                .userWantsToRestoreThisDecryptedBackup,
                .keycloakConfigAvailable,
                .keycloakUserDetailsAndStuffAvailable,
                .shouldRequestPermission,
                .userWantsToEnterTransferCode,
                .successfulTransferWasPerfomed,
                .userWantsToManuallyConfigureTheIdentityProvider,
                .showOwnedIdentityTransferFailed,
                .finalize,
                .userWantsToProceedWithAddingDevice:
            return nil
        case .finalOwnedIdentityTransferCheckOnSourceDevice(_, _, _, _, _, let protocolInstanceUID, _),
                .userMustChooseDeviceToKeepActiveOnSourceDevice(_, _, _, _, _, _, let protocolInstanceUID),
                .userMustEnterSASOnSourceDevice(_, _, _, _, let protocolInstanceUID),
                .userWantsToDisplaySasOnThisTargetDevice(_, let protocolInstanceUID, _):
            return protocolInstanceUID
        }
    }
    
    
    var userIsEnteringTransferCode: Bool {
        switch self {
        case .userWantsToEnterTransferCode:
            return true
        default:
            return false
        }
    }
    

    /// Returns the owned crypto id generated or transferred during the onboarding process if we are in a state occuring after the generation of the owned identity.
    var ownedCryptoId: ObvCryptoId? {
        switch self {
        case .initial:
            return nil
        case .userIndicatedSheHasAnExistingProfile:
            return nil
        case .userWantsToChooseUnmanagedDetails:
            return nil
        case .userWantsToRestoreSomeBackup:
            return nil
        case .userWantsToRestoreThisEncryptedBackup:
            return nil
        case .userWantsToRestoreThisDecryptedBackup:
            return nil
        case .keycloakConfigAvailable:
            return nil
        case .keycloakUserDetailsAndStuffAvailable:
            return nil
        case .userWantsToChooseNameForCurrentDevice:
            return nil
        case .userWantsToEnterTransferCode:
            return nil
        case .userWantsToDisplaySasOnThisTargetDevice:
            return nil
        case .showOwnedIdentityTransferFailed:
            return nil
        case .userWantsToManuallyConfigureTheIdentityProvider:
            return nil
        case .finalOwnedIdentityTransferCheckOnSourceDevice(ownedCryptoId: let ownedCryptoId, ownedDetails: _, enteredSAS: _, ownedDeviceDiscoveryResult: _, targetDeviceName: _, protocolInstanceUID: _, deviceToKeepActive: _):
            return ownedCryptoId
        case .userMustChooseDeviceToKeepActiveOnSourceDevice(ownedCryptoId: let ownedCryptoId, ownedDetails: _, enteredSAS: _, ownedDeviceDiscoveryResult: _, currentDeviceIdentifier: _, targetDeviceName: _, protocolInstanceUID: _):
            return ownedCryptoId
        case .userMustEnterSASOnSourceDevice(sasExpectedOnInput: _, targetDeviceName: _, ownedCryptoId: let ownedCryptoId, ownedDetails: _, protocolInstanceUID: _):
            return ownedCryptoId
        case .successfulTransferWasPerfomed(transferredOwnedCryptoId: let transferredOwnedCryptoId, postTransferError: _):
            return transferredOwnedCryptoId
        case .shouldRequestPermission(let profileKind, _):
            return profileKind.ownedCryptoId
        case .finalize(let profileKind):
            return profileKind.ownedCryptoId
        case .userWantsToProceedWithAddingDevice(ownedCryptoId: let ownedCryptoId, ownedDetails: _):
            return ownedCryptoId
        }
    }
        
    
    var profileKind: ProfileKind? {
        switch self {
        case .shouldRequestPermission(profileKind: let profileKind, category: _),
                .finalize(profileKind: let profileKind):
            return profileKind
        case .initial,
                .userWantsToChooseUnmanagedDetails,
                .userIndicatedSheHasAnExistingProfile,
                .userWantsToManuallyConfigureTheIdentityProvider,
                .userWantsToRestoreSomeBackup,
                .userWantsToChooseNameForCurrentDevice,
                .userWantsToRestoreThisEncryptedBackup,
                .userWantsToRestoreThisDecryptedBackup,
                .keycloakConfigAvailable,
                .keycloakUserDetailsAndStuffAvailable,
                .finalOwnedIdentityTransferCheckOnSourceDevice,
                .userMustChooseDeviceToKeepActiveOnSourceDevice,
                .userMustEnterSASOnSourceDevice,
                .userWantsToDisplaySasOnThisTargetDevice,
                .userWantsToEnterTransferCode,
                .successfulTransferWasPerfomed,
                .showOwnedIdentityTransferFailed,
                .userWantsToProceedWithAddingDevice:
            return nil
        }
    }

}
