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
import ObvCrypto
import ObvTypes
import ObvDesignSystem
import ObvAppTypes

#if DEBUG

/// Preview view controller allowing to preview the settings part of this backup module.
final class PreviewSettingsNavigationController: UINavigationController {
    
    init() {
        let rootViewController = PreviewSettingsRootViewController()
        super.init(rootViewController: rootViewController)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}


private final class PreviewSettingsRootViewController: UIViewController {
    
    private var router: ObvAppBackupSettingsRouter?
    private var isSynchronizedWithICloud = true
    
    override func viewDidLoad() {
        super.viewDidLoad()
        guard let navigationController = self.navigationController else { return }
        router = .init(subscriptionStatus: .noSubscription, navigationController: navigationController, delegate: self)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        router?.pushInitialViewController()
    }
    
}


extension PreviewSettingsRootViewController: ObvAppBackupSettingsRouterDelegate {
    
    func getDeviceDeactivationConsequencesOfRestoringBackup(_ router: ObvAppBackupSettingsRouter, ownedCryptoIdentity: ObvCrypto.ObvOwnedCryptoIdentity) async throws -> ObvDeviceDeactivationConsequence {
        .deviceDeactivations(deactivatedDevices: [
            OlvidPlatformAndDeviceName(identifier: Data(repeating: 0, count: 20), deviceName: "Alice's iPad", platform: .iPad),
            OlvidPlatformAndDeviceName(identifier: Data(repeating: 0, count: 20), deviceName: "Alice's iPad", platform: .iPad),
        ])
    }
    
    
    func userWantsToKeepAllDevicesActiveThanksToOlvidPlus(_ router: ObvAppBackupSettingsRouter, ownedCryptoIdentity: ObvCrypto.ObvOwnedCryptoIdentity) async throws -> ObvDeviceDeactivationConsequence {
        try await Task.sleep(seconds: 2)
        // Simulate a purchase made by the user
        return .noDeviceDeactivation
        // Simulate the situation where the user comes back with no purchase
//        let deactivatedDevices: [OlvidPlatformAndDeviceName] = [
//            OlvidPlatformAndDeviceName(identifier: Data(repeating: 0, count: 20), deviceName: "Alice's iPad", platform: .iPad),
//            OlvidPlatformAndDeviceName(identifier: Data(repeating: 0, count: 20), deviceName: "Alice's iPad", platform: .iPad),
//        ]
//        return .deviceDeactivations(deactivatedDevices: deactivatedDevices)
    }
    
    
    func userWantsToCancelProfileRestoration(_ router: ObvAppBackupSettingsRouter) {
        // We don't simulate anything here
    }
    
    
    func userWantsToBeRemindedToWriteDownBackupKey(_ router: ObvAppBackupSettingsRouter) {
        // We don't simulate anything here
    }
    

    func fetchAvatarImage(_ router: ObvAppBackupSettingsRouter, profileCryptoId: ObvTypes.ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        let actions = AvatarActionsForPreviews()
        return await actions.fetchAvatarImage(profileCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, frameSize: frameSize)
    }
    
    
    func userWantsToDeleteProfileBackupFromSettings(_ router: ObvAppBackupSettingsRouter, infoForDeletion: ObvTypes.ObvProfileBackupFromServer.InfoForDeletion) async throws {
        // Not implemented in previews
    }
    
    
    func userWantsToResetThisDeviceSeedAndBackups(_ router: ObvAppBackupSettingsRouter) async throws {
        // Simulate success by sleeping for 1s
        try await Task.sleep(seconds: 1)
    }
    
    func userWantsToSubscribeOlvidPlus(_ router: ObvAppBackupSettingsRouter) {
        // Not testable
    }
    
    func userWantsToAddDevice(_ router: ObvAppBackupSettingsRouter) {
        // Not testable
    }
    
    func userNeedsToProveCapacityToAuthenticateOnKeycloakServerAsTransferIsRestricted(_ router: ObvAppBackupSettingsRouter, keycloakConfiguration: ObvTypes.ObvKeycloakConfiguration) async throws -> Data {
        // Not testable
        assertionFailure()
        return Data()
    }
    
    
    func userWantsToOpenProfile(_ router: ObvAppBackupSettingsRouter, ownedCryptoId: ObvTypes.ObvCryptoId) {
        // Nothing to preview here
    }
    
    
    func restoreProfileBackupFromServerNow(_ router: ObvAppBackupSettingsRouter, profileBackupFromServerToRestore: ObvProfileBackupFromServer, rawAuthState: Data?) async throws -> ObvRestoredOwnedIdentityInfos {
        try await Task.sleep(seconds: 2)
        let restoredOwnedIdentityInfos = ObvRestoredOwnedIdentityInfos(ownedCryptoId: PreviewsHelper.cryptoIds.first!,
                                                                       firstNameThenLastName: PreviewsHelper.coreDetails.first!.getDisplayNameWithStyle(.firstNameThenLastName),
                                                                       positionAtCompany: PreviewsHelper.coreDetails.first!.getDisplayNameWithStyle(.positionAtCompany),
                                                                       displayedLetter: PreviewsHelper.coreDetails.first!.getDisplayNameWithStyle(.firstNameThenLastName).first ?? "A",
                                                                       isKeycloakManaged: false)
        return restoredOwnedIdentityInfos
    }
    
    
    func userWantsToFetchAllProfileBackupsFromServer(_ router: ObvAppBackupSettingsRouter, profileCryptoId: ObvCryptoId, profileBackupSeed: ObvCrypto.BackupSeed) async throws -> [ObvProfileBackupFromServer] {
        return ProfileBackupsForPreviews.profileBackups
    }
    
    
    func getDeviceActiveBackupSeed(_ router: ObvAppBackupSettingsRouter) async throws -> ObvCrypto.BackupSeed? {
        return BackupSeedsForPreviews.forPreviews[0]
    }
    
    func usersWantsToGetBackupParameterIsSynchronizedWithICloud(_ router: ObvAppBackupSettingsRouter) async throws -> Bool {
        try! await Task.sleep(seconds: 1)
        return isSynchronizedWithICloud
    }
    
    func usersWantsToChangeBackupParameterIsSynchronizedWithICloud(_ router: ObvAppBackupSettingsRouter, newIsSynchronizedWithICloud: Bool) async throws {
        try! await Task.sleep(seconds: 1)
        isSynchronizedWithICloud = newIsSynchronizedWithICloud
    }
    
    func userWantsToPerformBackupNow(_ router: ObvAppBackupSettingsRouter) async throws {
        try await Task.sleep(seconds: 5)
    }
    
    func userWantsToEraseAndGenerateNewDeviceBackupSeed(_ router: ObvAppBackupSettingsRouter) async throws -> ObvCrypto.BackupSeed {
        BackupSeedsForPreviews.regenerateBackupSeedsForPreviews()
        return BackupSeedsForPreviews.forPreviews[0]
    }
    
    func userWantsToFetchDeviceBakupFromServer(_ router: ObvAppBackupSettingsRouter) async throws -> AsyncStream<ObvDeviceBackupFromServerWithAppInfoKind> {
        return AsyncStream(ObvDeviceBackupFromServerWithAppInfoKind.self) { (continuation: AsyncStream<ObvDeviceBackupFromServerWithAppInfoKind>.Continuation) in
            Task {
                try await Task.sleep(seconds: 1)
                do {
                    let list: ObvListOfDeviceBackupProfiles = .init(
                        profiles: [
                            ListOfBackupedProfilesFromServerViewModelProfileForPreviews.profiles[0],
                            ListOfBackupedProfilesFromServerViewModelProfileForPreviews.profiles[1],
                        ])
                    let deviceBackup: ObvDeviceBackupFromServerWithAppInfoKind = .thisPhysicalDevice(list)
                    continuation.yield(deviceBackup)
                }
                try await Task.sleep(seconds: 1)
                do {
                    let list: ObvListOfDeviceBackupProfiles = .init(
                        profiles: [
                            ListOfBackupedProfilesFromServerViewModelProfileForPreviews.profiles[2],
                        ])
                    let deviceBackup: ObvDeviceBackupFromServerWithAppInfoKind = .keychain(list)
                    continuation.yield(deviceBackup)
                }
                continuation.finish()
            }
        }
    }
    
    func userWantsToUseDeviceBackupSeed(_ router: ObvAppBackupSettingsRouter, deviceBackupSeed: ObvCrypto.BackupSeed) async throws -> ObvListOfDeviceBackupProfiles {
        
        try await Task.sleep(seconds: 1)
        
        let list: ObvListOfDeviceBackupProfiles = .init(
            profiles: [
                ListOfBackupedProfilesFromServerViewModelProfileForPreviews.profiles[2],
            ])

        return list
        
    }

}

#endif
