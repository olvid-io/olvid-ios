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


@MainActor
public protocol ObvAppBackupOnboardingRouterDelegate: AnyObject {
    func userWantsToFetchDeviceBakupFromServer(_ router: ObvAppBackupOnboardingRouter) async throws -> AsyncStream<ObvDeviceBackupFromServerWithAppInfoKind>
    func userWantsToUseDeviceBackupSeed(_ router: ObvAppBackupOnboardingRouter, deviceBackupSeed: BackupSeed) async throws -> ObvListOfDeviceBackupProfiles
    func userWantsToFetchAllProfileBackupsFromServer(_ router: ObvAppBackupOnboardingRouter, profileCryptoId: ObvCryptoId, profileBackupSeed: ObvCrypto.BackupSeed) async throws -> [ObvProfileBackupFromServer]
    func restoreProfileBackupFromServerNow(_ router: ObvAppBackupOnboardingRouter, profileBackupFromServerToRestore: ObvTypes.ObvProfileBackupFromServer, rawAuthState: Data?) async throws -> ObvRestoredOwnedIdentityInfos
    func userWantsToOpenProfile(_ router: ObvAppBackupOnboardingRouter, ownedCryptoId: ObvCryptoId)
    func userNeedsToProveCapacityToAuthenticateOnKeycloakServerAsTransferIsRestricted(_ router: ObvAppBackupOnboardingRouter, keycloakConfiguration: ObvKeycloakConfiguration) async throws -> Data
    func userWantsToRestoreLegacyBackup(_ router: ObvAppBackupOnboardingRouter, backupSeedManuallyEntered: BackupSeed)
    func fetchAvatarImage(_ router: ObvAppBackupOnboardingRouter, profileCryptoId: ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage?
    func getDeviceDeactivationConsequencesOfRestoringBackup(_ router: ObvAppBackupOnboardingRouter, ownedCryptoIdentity: ObvOwnedCryptoIdentity) async throws -> ObvDeviceDeactivationConsequence
    func userWantsToKeepAllDevicesActiveThanksToOlvidPlus(_ router: ObvAppBackupOnboardingRouter, ownedCryptoIdentity: ObvOwnedCryptoIdentity) async throws -> ObvDeviceDeactivationConsequence
    func userWantsToCancelProfileRestoration(_ router: ObvAppBackupOnboardingRouter)
}

public enum ObvDeviceDeactivationConsequence: Sendable {
    case noDeviceDeactivation
    case deviceDeactivations(deactivatedDevices: [OlvidPlatformAndDeviceName])
}


@MainActor
public final class ObvAppBackupOnboardingRouter {
    
    private let router: Router
    fileprivate weak var delegate: ObvAppBackupOnboardingRouterDelegate?

    public init(navigationController: UINavigationController, delegate: ObvAppBackupOnboardingRouterDelegate, userIsPerformingInitialOnboarding: Bool) {
        self.router = Router(navigationController: navigationController, userIsPerformingInitialOnboarding: userIsPerformingInitialOnboarding)
        self.delegate = delegate
        self.router.parentRouter = self
    }

}


// MARK: - Public API

extension ObvAppBackupOnboardingRouter {
    
    public func pushInitialViewController() {
        router.pushInitialViewController()
    }
    
}


// MARK: - Internal router

@MainActor
fileprivate final class Router {
    
    private weak var navigationController: UINavigationController?
    fileprivate let initialNavigationStack: [UIViewController]
    fileprivate weak var parentRouter: ObvAppBackupOnboardingRouter?
    private let userIsPerformingInitialOnboarding: Bool

    init(navigationController: UINavigationController, userIsPerformingInitialOnboarding: Bool) {
        self.navigationController = navigationController
        self.initialNavigationStack = navigationController.viewControllers
        self.userIsPerformingInitialOnboarding = userIsPerformingInitialOnboarding
    }
 
    
    func pushInitialViewController() {
        let vc = OnboardingBackupRestoreStartingPointHostingView(delegate: self)
        navigationController?.pushViewController(vc, animated: true)
    }

}



// MARK: - Implementing OnboardingBackupRestoreStartingPointHostingViewDelegate

extension Router: OnboardingBackupRestoreStartingPointHostingViewDelegate {
    
    func userWantsToRestoreBackupAutomaticallyFromICloudKeychain(_ vc: OnboardingBackupRestoreStartingPointHostingView) {
        let vc = ListOfBackupedProfilesAcrossDeviceHostingView(delegate: self, canNavigateToListOfProfileBackupsForProfilesOnDevice: false)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    func userWantsToRestoreBackupManually(_ vc: OnboardingBackupRestoreStartingPointHostingView) {
        let allowLegacyBackupRestoration = userIsPerformingInitialOnboarding
        let vc = EnterDeviceBackupSeedHostingView(allowLegacyBackupRestoration: allowLegacyBackupRestoration, delegate: self)
        navigationController?.pushViewController(vc, animated: true)
    }
    
}



// MARK: - Implementing ListOfBackupedProfilesAcrossDeviceHostingViewDelegate

extension Router: ListOfBackupedProfilesAcrossDeviceHostingViewDelegate {
    
    func userWantsToFetchDeviceBakupFromServer(_ vc: ListOfBackupedProfilesAcrossDeviceHostingView) async throws -> AsyncStream<ObvDeviceBackupFromServerWithAppInfoKind> {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
        return try await delegate.userWantsToFetchDeviceBakupFromServer(parentRouter)
    }
    
    
    func userWantsToNavigateToListOfAllProfileBackups(_ vc: ListOfBackupedProfilesAcrossDeviceHostingView, profileCryptoId: ObvTypes.ObvCryptoId, profileName: String, profileBackupSeed: ObvCrypto.BackupSeed) {
        let listOfProfileBackups = ObvListOfProfileBackups(profileCryptoId: profileCryptoId, profileBackupSeed: profileBackupSeed, delegate: self)
        let vc = ListOfBackupsOfProfileHostingView(listOfProfileBackups: listOfProfileBackups, profileName: profileName, context: .onboarding, delegate: self)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    func fetchAvatarImage(_ vc: ListOfBackupedProfilesAcrossDeviceHostingView, profileCryptoId: ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); return nil }
        return await delegate.fetchAvatarImage(parentRouter, profileCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, frameSize: frameSize)
    }
    
}


// MARK: - Implementing EnterDeviceBackupSeedHostingViewDelegate

extension Router: EnterDeviceBackupSeedHostingViewDelegate {

    func userWantsToUseDeviceBackupSeed(_ vc: EnterDeviceBackupSeedHostingView, deviceBackupSeed: ObvCrypto.BackupSeed) async throws -> ObvListOfDeviceBackupProfiles {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
        return try await delegate.userWantsToUseDeviceBackupSeed(parentRouter, deviceBackupSeed: deviceBackupSeed)
    }
    
    
    func userWantsToRestoreLegacyBackup(_ vc: EnterDeviceBackupSeedHostingView, backupSeedManuallyEntered: BackupSeed) {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); return }
        delegate.userWantsToRestoreLegacyBackup(parentRouter, backupSeedManuallyEntered: backupSeedManuallyEntered)
    }
    
    /// Called after the user entered a backup key that allowed to obtain a list of backuped profiles. This is called to allow to navigate to a view showing the obtained backups.
    func userWantsToNavigateToListOfBackupedProfilesAcrossDeviceView(_ vc: EnterDeviceBackupSeedHostingView, listModel: ObvListOfDeviceBackupProfiles) {
        let vc = EnteredDeviceBackupSeedResultViewController(
            listModel: listModel,
            canNavigateToListOfProfileBackupsForProfilesOnDevice: false,
            delegate: self)
        navigationController?.pushViewController(vc, animated: true)
    }

}


// MARK: - Implementing EnteredDeviceBackupSeedResultViewControllerDelegate

extension Router: EnteredDeviceBackupSeedResultViewControllerDelegate {
    
    func userWantsToNavigateToListOfAllProfileBackups(_ vc: EnteredDeviceBackupSeedResultViewController, profileCryptoId: ObvTypes.ObvCryptoId, profileName: String, profileBackupSeed: ObvCrypto.BackupSeed) {
        let listOfProfileBackups = ObvListOfProfileBackups(profileCryptoId: profileCryptoId, profileBackupSeed: profileBackupSeed, delegate: self)
        let vc = ListOfBackupsOfProfileHostingView(listOfProfileBackups: listOfProfileBackups, profileName: profileName, context: .onboarding, delegate: self)
        navigationController?.pushViewController(vc, animated: true)
    }
    

    func fetchAvatarImage(_ vc: EnteredDeviceBackupSeedResultViewController, profileCryptoId: ObvTypes.ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); return nil }
        return await delegate.fetchAvatarImage(parentRouter, profileCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, frameSize: frameSize)
    }
    
}


// MARK: - Implementing ObvListOfProfileBackupsDelegate

extension Router: ObvListOfProfileBackupsDelegate {
    
    func userWantsToFetchAllProfileBackupsFromServer(_ model: ObvListOfProfileBackups, profileCryptoId: ObvTypes.ObvCryptoId, profileBackupSeed: ObvCrypto.BackupSeed) async throws -> [ObvTypes.ObvProfileBackupFromServer] {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
        let profileBackupsFromServer = try await delegate.userWantsToFetchAllProfileBackupsFromServer(parentRouter, profileCryptoId: profileCryptoId, profileBackupSeed: profileBackupSeed)
        return profileBackupsFromServer
    }
    
}


// MARK: - Implementing ListOfBackupsOfProfileHostingViewDelegate

extension Router: ListOfBackupsOfProfileHostingViewDelegate {
    
    /// This is called when the user chooses a profile backup to restore, and confirms they want to restore it. In that case, we make sure this would not deactivate older devices.
    /// This is typically the case if the user hasn't made an in-app purchase and has no license for the identity to be restored. If this is the case, we push a warning screen.
    /// Otherwise, we simply push the view controller that will actually make the async call allowing to restore the backup.
    /// This strategy is the same to the one in the router of `ObvAppBackupSettingsRouter`.
    func userWantsToRestoreProfileBackup(_ vc: ListOfBackupsOfProfileHostingView, profileBackupFromServer: ObvProfileBackupFromServer) async throws {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }

        let consequence = try await delegate.getDeviceDeactivationConsequencesOfRestoringBackup(parentRouter,
                                                                                                ownedCryptoIdentity: profileBackupFromServer.parsedData.ownedCryptoIdentity)
        
        switch consequence {

        case .noDeviceDeactivation:
            
            try await proveCapacityToAuthenticateOnKeycloakServerIfRequiredThenRestoreProfile(profileBackupFromServer: profileBackupFromServer)

        case .deviceDeactivations:
            
            let model = DeviceDeactivationWarningOnBackupRestoreViewModel(
                profileBackupFromServerToRestore: profileBackupFromServer,
                deviceDeactivationConsequence: consequence)
            let vc = DeviceDeactivationWarningOnBackupRestoreHostingView(model: model, delegate: self)
            navigationController?.pushViewController(vc, animated: true)

        }
        
    }
    
}


// MARK: - Implementing DeviceDeactivationWarningOnBackupRestoreHostingViewDelegate

extension Router: DeviceDeactivationWarningOnBackupRestoreHostingViewDelegate {
    
    /// This method will eventually result in the presentation of a flow allowing the user to subscribe to Olvid+. It will return only when the user is done with the flow. It returns the new value
    /// of `ObvDeviceDeactivationConsequence`.
    func userWantsToKeepAllDevicesActiveThanksToOlvidPlus(_ vc: DeviceDeactivationWarningOnBackupRestoreHostingView, ownedCryptoIdentity: ObvOwnedCryptoIdentity) async throws -> ObvDeviceDeactivationConsequence {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
        return try await delegate.userWantsToKeepAllDevicesActiveThanksToOlvidPlus(parentRouter, ownedCryptoIdentity: ownedCryptoIdentity)
    }
    
    
    func userConfirmedSheWantsToRestoreProfileBackupNow(_ vc: DeviceDeactivationWarningOnBackupRestoreHostingView, profileBackupFromServer: ObvTypes.ObvProfileBackupFromServer) async throws {
        try await proveCapacityToAuthenticateOnKeycloakServerIfRequiredThenRestoreProfile(profileBackupFromServer: profileBackupFromServer)
    }
    
    
    func userWantsToCancelProfileRestoration(_ vc: DeviceDeactivationWarningOnBackupRestoreHostingView) {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); return }
        self.navigationController?.setViewControllers(initialNavigationStack, animated: true)
        delegate.userWantsToCancelProfileRestoration(parentRouter)
    }
    
}


// MARK: - Implementing ProfileRestoredConfirmationHostingViewDelegate

extension Router: ProfileRestoredConfirmationHostingViewDelegate {
    
    func fetchAvatarImage(_ vc: ProfileRestoredConfirmationHostingView, profileCryptoId: ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); return nil }
        return await delegate.fetchAvatarImage(parentRouter, profileCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, frameSize: frameSize)
    }
    
    
    func restoreProfileBackupFromServerNow(_ vc: ProfileRestoredConfirmationHostingView, profileBackupFromServerToRestore: ObvTypes.ObvProfileBackupFromServer, rawAuthState: Data?) async throws -> ObvRestoredOwnedIdentityInfos {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
        return try await delegate.restoreProfileBackupFromServerNow(parentRouter, profileBackupFromServerToRestore: profileBackupFromServerToRestore, rawAuthState: rawAuthState)
    }
    
    func userWantsToOpenProfile(_ vc: ProfileRestoredConfirmationHostingView, ownedCryptoId: ObvTypes.ObvCryptoId) {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); return }
        delegate.userWantsToOpenProfile(parentRouter, ownedCryptoId: ownedCryptoId)
    }
    
    
    func userWantsToRestoreAnotherProfile(_ vc: ProfileRestoredConfirmationHostingView) {
        if let vc = navigationController?.viewControllers.last(where: { $0 is EnterDeviceBackupSeedHostingView }) {
            navigationController?.popToViewController(vc, animated: true)
        } else if let vc = navigationController?.viewControllers.first(where: { $0 is OnboardingBackupRestoreStartingPointHostingView }) {
            navigationController?.popToViewController(vc, animated: true)
        } else {
            assertionFailure()
            navigationController?.setViewControllers(initialNavigationStack, animated: true)
        }
    }
    
    
    func navigateToErrorViewAsRestorationFailed(_ vc: ProfileRestoredConfirmationHostingView, error: any Error) {
        let vc = ProfileRestoreFailureHostingView(model: .init(error: error))
        navigationController?.setViewControllers(initialNavigationStack + [vc], animated: true)
    }
    
}


// MARK: - Helpers

extension Router {
    
    /// A very similar method is also implemented by the `Router` of `ObvAppBackupSettingsRouter`.
    private func proveCapacityToAuthenticateOnKeycloakServerIfRequiredThenRestoreProfile(profileBackupFromServer: ObvProfileBackupFromServer) async throws {
        
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }

        let rawAuthState: Data?

        switch profileBackupFromServer.parsedData.isKeycloakManaged {
        case .no:
            rawAuthState = nil
        case .yes(keycloakConfiguration: let keycloakConfiguration, isTransferRestricted: let isTransferRestricted):
            if isTransferRestricted {
                rawAuthState = try await delegate.userNeedsToProveCapacityToAuthenticateOnKeycloakServerAsTransferIsRestricted(parentRouter, keycloakConfiguration: keycloakConfiguration)
            } else {
                rawAuthState = nil
            }
        }
        
        // Remove certain view controllers of the stack
        
        guard let navigationController else { assertionFailure(); return }

        let filteredStack = navigationController.viewControllers
            .filter { vc in
                if vc is ListOfBackupedProfilesAcrossDeviceHostingView { return false }
                if vc is EnteredDeviceBackupSeedResultViewController { return false }
                if vc is ListOfBackupsOfProfileHostingView { return false }
                if vc is DeviceDeactivationWarningOnBackupRestoreHostingView { return false }
                return true
            }

        let vc = ProfileRestoredConfirmationHostingView(profileBackupFromServerToRestore: profileBackupFromServer, rawAuthState: rawAuthState, delegate: self)
        
        let newStack = filteredStack + [vc]
        
        navigationController.setViewControllers(newStack, animated: true)

    }
    
}



// MARK: - Errors

extension Router {
    
    enum ObvError: Error {
        case delegateOrParentRouterIsNil
    }
    
}
