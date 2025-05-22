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


@MainActor
public protocol ObvAppBackupSettingsRouterDelegate: AnyObject {
    func getDeviceActiveBackupSeed(_ router: ObvAppBackupSettingsRouter) async throws -> ObvCrypto.BackupSeed?
    func usersWantsToGetBackupParameterIsSynchronizedWithICloud(_ router: ObvAppBackupSettingsRouter) async throws -> Bool
    func usersWantsToChangeBackupParameterIsSynchronizedWithICloud(_ router: ObvAppBackupSettingsRouter, newIsSynchronizedWithICloud: Bool) async throws
    func userWantsToPerformBackupNow(_ router: ObvAppBackupSettingsRouter) async throws
    func userWantsToEraseAndGenerateNewDeviceBackupSeed(_ router: ObvAppBackupSettingsRouter) async throws -> ObvCrypto.BackupSeed
    func userWantsToFetchDeviceBakupFromServer(_ router: ObvAppBackupSettingsRouter) async throws -> AsyncStream<ObvDeviceBackupFromServerWithAppInfoKind>
    func userWantsToUseDeviceBackupSeed(_ router: ObvAppBackupSettingsRouter, deviceBackupSeed: BackupSeed) async throws -> ObvListOfDeviceBackupProfiles
    func userWantsToFetchAllProfileBackupsFromServer(_ router: ObvAppBackupSettingsRouter, profileCryptoId: ObvCryptoId, profileBackupSeed: ObvCrypto.BackupSeed) async throws -> [ObvProfileBackupFromServer]
    func restoreProfileBackupFromServerNow(_ router: ObvAppBackupSettingsRouter, profileBackupFromServerToRestore: ObvTypes.ObvProfileBackupFromServer, rawAuthState: Data?) async throws -> ObvRestoredOwnedIdentityInfos
    func userWantsToOpenProfile(_ router: ObvAppBackupSettingsRouter, ownedCryptoId: ObvCryptoId)
    func userNeedsToProveCapacityToAuthenticateOnKeycloakServerAsTransferIsRestricted(_ router: ObvAppBackupSettingsRouter, keycloakConfiguration: ObvKeycloakConfiguration) async throws -> Data
    func userWantsToSubscribeOlvidPlus(_ router: ObvAppBackupSettingsRouter)
    func userWantsToAddDevice(_ router: ObvAppBackupSettingsRouter)
    func userWantsToResetThisDeviceSeedAndBackups(_ router: ObvAppBackupSettingsRouter) async throws
    func userWantsToDeleteProfileBackupFromSettings(_ router: ObvAppBackupSettingsRouter, infoForDeletion: ObvProfileBackupFromServer.InfoForDeletion) async throws
    func fetchAvatarImage(_ router: ObvAppBackupSettingsRouter, profileCryptoId: ObvTypes.ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage?
    func getDeviceDeactivationConsequencesOfRestoringBackup(_ router: ObvAppBackupSettingsRouter, ownedCryptoIdentity: ObvOwnedCryptoIdentity) async throws -> ObvDeviceDeactivationConsequence
    func userWantsToKeepAllDevicesActiveThanksToOlvidPlus(_ router: ObvAppBackupSettingsRouter, ownedCryptoIdentity: ObvOwnedCryptoIdentity) async throws -> ObvDeviceDeactivationConsequence
    func userWantsToCancelProfileRestoration(_ router: ObvAppBackupSettingsRouter)
    func userWantsToBeRemindedToWriteDownBackupKey(_ router: ObvAppBackupSettingsRouter) async
}



@MainActor
public final class ObvAppBackupSettingsRouter {
    
    private let router: Router
    fileprivate weak var delegate: ObvAppBackupSettingsRouterDelegate?
    
    
    public init(subscriptionStatus: ObvSubscriptionStatusForAppBackup, navigationController: UINavigationController, delegate: ObvAppBackupSettingsRouterDelegate) {
        self.router = Router(navigationController: navigationController, subscriptionStatus: subscriptionStatus)
        self.delegate = delegate
        self.router.parentRouter = self
    }
    
}


// MARK: - Public API

extension ObvAppBackupSettingsRouter {
    
    public func pushInitialViewController() {
        router.pushInitialViewController()
    }
    
}


// MARK: - Internal router

@MainActor
fileprivate final class Router {
    
    private weak var navigationController: UINavigationController?
    fileprivate let initialNavigationStack: [UIViewController]
    fileprivate weak var parentRouter: ObvAppBackupSettingsRouter?
    private let subscriptionStatus: ObvSubscriptionStatusForAppBackup

    init(navigationController: UINavigationController, subscriptionStatus: ObvSubscriptionStatusForAppBackup) {
        self.navigationController = navigationController
        self.initialNavigationStack = navigationController.viewControllers
        self.subscriptionStatus = subscriptionStatus
    }
 
    
    func pushInitialViewController() {
        let vc = NewBackupSettingsHostingView(subscriptionStatus: subscriptionStatus, delegate: self)
        self.navigationController?.pushViewController(vc, animated: true)
    }

}



// MARK: - Implementing NewBackupSettingsHostingViewDelegate

extension Router: NewBackupSettingsHostingViewDelegate {
        
    func userWantsToNavigateToNavigateToSecuritySettings(_ vc: ObvAppBackup.NewBackupSettingsHostingView) {
        let vc = SecurityManagementHostingView(delegate: self)
        navigationController?.pushViewController(vc, animated: true)
    }

    
    func userWantsToNavigateToManageBackups(_ vc: NewBackupSettingsHostingView) {
        let vc = ManageBackupsHostingView(delegate: self)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    
    func usersWantsToGetBackupParameterIsSynchronizedWithICloud(_ vc: NewBackupSettingsHostingView) async throws -> Bool {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
        return try await delegate.usersWantsToGetBackupParameterIsSynchronizedWithICloud(parentRouter)
    }
    
    
    func usersWantsToChangeBackupParameterIsSynchronizedWithICloud(_ vc: NewBackupSettingsHostingView, newIsSynchronizedWithICloud: Bool) async throws {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
        return try await delegate.usersWantsToChangeBackupParameterIsSynchronizedWithICloud(parentRouter, newIsSynchronizedWithICloud: newIsSynchronizedWithICloud)
    }

    
    func userWantsToSubscribeOlvidPlus(_ vc: NewBackupSettingsHostingView) {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); return }
        return delegate.userWantsToSubscribeOlvidPlus(parentRouter)
    }
    
    
    func userWantsToAddDevice(_ vc: NewBackupSettingsHostingView) {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); return }
        return delegate.userWantsToAddDevice(parentRouter)
    }
    
    
    func userWantsToPerformABackupNow(_ vc: NewBackupSettingsHostingView) async throws {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
        try await delegate.userWantsToPerformBackupNow(parentRouter)
    }
    
}


// MARK: - Implementing SecurityManagementHostingViewDelegate

extension Router: SecurityManagementHostingViewDelegate {
    
    func userWantsToNavigateToBackupKeyDisplayerView(_ vc: SecurityManagementHostingView) {
        self.userWantsToNavigateToBackupKeyDisplayerView()
    }
    
    
    func userWantsToNavigateToStolenOrCompromisedKeyView(_ vc: SecurityManagementHostingView) {
        let vc = StolenOrCompromisedKeyHostingView(delegate: self)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    
    func userWantsToResetThisDeviceSeedAndBackups(_ vc: SecurityManagementHostingView) async throws {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
        try await delegate.userWantsToResetThisDeviceSeedAndBackups(parentRouter)
        // If we reach this point, this device backup configuartion was reset. We can navigate back to the settings
        navigationController?.popToRootViewController(animated: true)
    }

}


// MARK: - Implementing ManageBackupsHostingViewDelegate

extension Router: ManageBackupsHostingViewDelegate {
    
    func userWantsToSeeListOfBackupedProfilesAcrossDevice(_ yourBackupsHostingView: ManageBackupsHostingView) {
        let vc = ListOfBackupedProfilesAcrossDeviceHostingView(delegate: self, canNavigateToListOfProfileBackupsForProfilesOnDevice: true)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    
    func userWantsToSeeListOfBackupedProfilesPerDevice(_ yourBackupsHostingView: ManageBackupsHostingView) {
        let vc = ListOfBackupedProfilesPerDeviceHostingView(delegate: self, canNavigateToListOfProfileBackupsForProfilesOnDevice: true)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    
    func userWantsToEnterDeviceBackupSeed(_ yourBackupsHostingView: ManageBackupsHostingView) {
        let vc = EnterDeviceBackupSeedHostingView(allowLegacyBackupRestoration: false, delegate: self)
        navigationController?.pushViewController(vc, animated: true)
    }
        
}


// MARK: - Implementing BackupKeyDisplayerHostingHostingViewDelegate

extension Router: BackupKeyDisplayerHostingHostingViewDelegate {
    
    func userConfirmedWritingDownTheBackupKey(_ vc: BackupKeyDisplayerHostingHostingView, remindToSaveBackupKey: Bool) {
        guard navigationController?.viewControllers.last == vc else { assertionFailure(); return }
        navigationController?.popViewController(animated: true)
        if remindToSaveBackupKey {
            guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); return }
            Task { await delegate.userWantsToBeRemindedToWriteDownBackupKey(parentRouter) }
        }
    }
    
}


// MARK: - Implementing StolenOrCompromisedKeyHostingViewDelegate

extension Router: StolenOrCompromisedKeyHostingViewDelegate {
    
    func userWantsToEraseAndGenerateNewDeviceBackupSeed(_ vc: StolenOrCompromisedKeyHostingView) async throws {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
        _ = try await delegate.userWantsToEraseAndGenerateNewDeviceBackupSeed(parentRouter)
    }
    
    
    func userWantsToNavigateToBackupKeyDisplayerView(_ vc: StolenOrCompromisedKeyHostingView) {
        self.userWantsToNavigateToBackupKeyDisplayerView()
    }

}


// MARK: - Implementing ListOfBackupedProfilesAcrossDeviceHostingViewDelegate

extension Router: ListOfBackupedProfilesAcrossDeviceHostingViewDelegate {
    
    func userWantsToFetchDeviceBakupFromServer(_ vc: ListOfBackupedProfilesAcrossDeviceHostingView) async throws -> AsyncStream<ObvDeviceBackupFromServerWithAppInfoKind> {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
        return try await delegate.userWantsToFetchDeviceBakupFromServer(parentRouter)
    }
    
    
    func userWantsToNavigateToListOfAllProfileBackups(_ vc: ListOfBackupedProfilesAcrossDeviceHostingView, profileCryptoId: ObvCryptoId, profileName: String, profileBackupSeed: ObvCrypto.BackupSeed) {
        let listOfProfileBackups = ObvListOfProfileBackups(profileCryptoId: profileCryptoId, profileBackupSeed: profileBackupSeed, delegate: self)
        let vc = ListOfBackupsOfProfileHostingView(listOfProfileBackups: listOfProfileBackups, profileName: profileName, context: .settings(actions: self), delegate: self)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    
    func fetchAvatarImage(_ vc: ListOfBackupedProfilesAcrossDeviceHostingView, profileCryptoId: ObvTypes.ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); return nil }
        return await delegate.fetchAvatarImage(parentRouter, profileCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, frameSize: frameSize)
    }

}


// MARK: - Implementing ContextOfListOfBackupsOfProfileSettingsActionsDelegate

extension Router: ContextOfListOfBackupsOfProfileSettingsActionsDelegate {
    
    func userWantsToRestoreProfileBackupFromSettingsMenu(profileBackupFromServer: ObvTypes.ObvProfileBackupFromServer) async throws {
        
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
    
    func userWantsToDeleteProfileBackupFromSettingsMenu(infoForDeletion: ObvProfileBackupFromServer.InfoForDeletion) async throws {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
        try await delegate.userWantsToDeleteProfileBackupFromSettings(parentRouter, infoForDeletion: infoForDeletion)
    }
    
}


// MARK: - Implementing DeviceDeactivationWarningOnBackupRestoreHostingViewDelegate

extension Router: DeviceDeactivationWarningOnBackupRestoreHostingViewDelegate {
    
    func userWantsToKeepAllDevicesActiveThanksToOlvidPlus(_ vc: DeviceDeactivationWarningOnBackupRestoreHostingView, ownedCryptoIdentity: ObvCrypto.ObvOwnedCryptoIdentity) async throws -> ObvDeviceDeactivationConsequence {
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


// MARK: - Implementing ListOfBackupsOfProfileHostingViewDelegate

extension Router: ListOfBackupsOfProfileHostingViewDelegate {
    
    /// This is called when the user chooses a profile backup to restore, and confirms they want to restore it. In that case, we make sure this would not deactivate older devices.
    /// This is typically the case if the user hasn't made an in-app purchase and has no license for the identity to be restored. If this is the case, we push a warning screen.
    /// Otherwise, we simply push the view controller that will actually make the async call allowing to restore the backup.
    /// This strategy is the same to the one in the router of `ObvAppBackupOnboardingRouter`.
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


// MARK: - Implementing ProfileRestoredConfirmationHostingViewDelegate

extension Router: ProfileRestoredConfirmationHostingViewDelegate {
    
    func fetchAvatarImage(_ vc: ProfileRestoredConfirmationHostingView, profileCryptoId: ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); return nil }
        return await delegate.fetchAvatarImage(parentRouter, profileCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, frameSize: frameSize)
    }
    
    
    func restoreProfileBackupFromServerNow(_ vc: ProfileRestoredConfirmationHostingView, profileBackupFromServerToRestore: ObvProfileBackupFromServer, rawAuthState: Data?) async throws -> ObvRestoredOwnedIdentityInfos {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
        return try await delegate.restoreProfileBackupFromServerNow(parentRouter, profileBackupFromServerToRestore: profileBackupFromServerToRestore, rawAuthState: rawAuthState)
    }
    
    
    func userWantsToOpenProfile(_ vc: ProfileRestoredConfirmationHostingView, ownedCryptoId: ObvCryptoId) {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); return }
        delegate.userWantsToOpenProfile(parentRouter, ownedCryptoId: ownedCryptoId)
    }
    
    
    func userWantsToRestoreAnotherProfile(_ vc: ProfileRestoredConfirmationHostingView) {
        if let vc = navigationController?.viewControllers.first(where: { $0 is ManageBackupsHostingView }) {
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


// MARK: - Implementing ObvListOfProfileBackupsDelegate

extension Router: ObvListOfProfileBackupsDelegate {
    
    func userWantsToFetchAllProfileBackupsFromServer(_ model: ObvListOfProfileBackups, profileCryptoId: ObvCryptoId, profileBackupSeed: ObvCrypto.BackupSeed) async throws -> [ObvProfileBackupFromServer] {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
        let profileBackupsFromServer = try await delegate.userWantsToFetchAllProfileBackupsFromServer(parentRouter, profileCryptoId: profileCryptoId, profileBackupSeed: profileBackupSeed)
        return profileBackupsFromServer
    }
    
}


// MARK: - Implementing ListOfDeviceBackupsFromServerHostingViewDelegate

extension Router: ListOfDeviceBackupsFromServerHostingViewDelegate {
    
    func userWantsToFetchDeviceBakupFromServer(_ vc: ListOfBackupedProfilesPerDeviceHostingView) async throws -> AsyncStream<ObvDeviceBackupFromServerWithAppInfoKind> {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
        return try await delegate.userWantsToFetchDeviceBakupFromServer(parentRouter)
    }
    
    
    func userWantsToShowAllBackupsOfProfile(_ vc: ListOfBackupedProfilesPerDeviceHostingView, profileCryptoId: ObvCryptoId, profileName: String, profileBackupSeed: ObvCrypto.BackupSeed) {
        let listOfProfileBackups = ObvListOfProfileBackups(profileCryptoId: profileCryptoId, profileBackupSeed: profileBackupSeed, delegate: self)
        let vc = ListOfBackupsOfProfileHostingView(listOfProfileBackups: listOfProfileBackups, profileName: profileName, context: .settings(actions: self), delegate: self)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    
    func fetchAvatarImage(_ vc: ListOfBackupedProfilesPerDeviceHostingView, profileCryptoId: ObvTypes.ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
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
        assertionFailure("We do not allow restoring a legacy backup from the settings")
        return
    }
    
    /// Called after the user entered a backup key that allowed to obtain a list of backuped profiles. This is called to allow to navigate to a view showing the obtained backups.
    func userWantsToNavigateToListOfBackupedProfilesAcrossDeviceView(_ vc: EnterDeviceBackupSeedHostingView, listModel: ObvListOfDeviceBackupProfiles) {
        let vc = EnteredDeviceBackupSeedResultViewController(
            listModel: listModel,
            canNavigateToListOfProfileBackupsForProfilesOnDevice: true,
            delegate: self)
        navigationController?.pushViewController(vc, animated: true)
    }

}


// MARK: - Implementing EnteredDeviceBackupSeedResultViewControllerDelegate

extension Router: EnteredDeviceBackupSeedResultViewControllerDelegate {
    
    func userWantsToNavigateToListOfAllProfileBackups(_ vc: EnteredDeviceBackupSeedResultViewController, profileCryptoId: ObvTypes.ObvCryptoId, profileName: String, profileBackupSeed: ObvCrypto.BackupSeed) {
        let listOfProfileBackups = ObvListOfProfileBackups(profileCryptoId: profileCryptoId, profileBackupSeed: profileBackupSeed, delegate: self)
        let vc = ListOfBackupsOfProfileHostingView(listOfProfileBackups: listOfProfileBackups, profileName: profileName, context: .settings(actions: self), delegate: self)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    func fetchAvatarImage(_ vc: EnteredDeviceBackupSeedResultViewController, profileCryptoId: ObvTypes.ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); return nil }
        return await delegate.fetchAvatarImage(parentRouter, profileCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, frameSize: frameSize)
    }
    
}


// MARK: - Private helpers

extension Router {
    
    private func userWantsToNavigateToBackupKeyDisplayerView() {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); return }
        Task {
            guard let deviceBackupSeed = try await delegate.getDeviceActiveBackupSeed(parentRouter) else { assertionFailure(); return }
            let model = BackupKeyDisplayerView.Model(backupSeed: deviceBackupSeed)
            let vc = BackupKeyDisplayerHostingHostingView(model: model, delegate: self)
            navigationController?.pushViewController(vc, animated: true)
        }
    }
    
    
    /// A very similar method is also implemented by the `Router` of `ObvAppBackupOnboardingRouter`.
    private func proveCapacityToAuthenticateOnKeycloakServerIfRequiredThenRestoreProfile(profileBackupFromServer: ObvProfileBackupFromServer) async throws {
        
        let rawAuthState: Data?

        switch profileBackupFromServer.parsedData.isKeycloakManaged {
        case .no:
            rawAuthState = nil
        case .yes(keycloakConfiguration: let keycloakConfiguration, isTransferRestricted: let isTransferRestricted):
            if isTransferRestricted {
                guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
                rawAuthState = try await delegate.userNeedsToProveCapacityToAuthenticateOnKeycloakServerAsTransferIsRestricted(parentRouter, keycloakConfiguration: keycloakConfiguration)
            } else {
                rawAuthState = nil
            }
        }
        
        // Remove certain view controllers of the stack
        
        let vc = ProfileRestoredConfirmationHostingView(profileBackupFromServerToRestore: profileBackupFromServer, rawAuthState: rawAuthState, delegate: self)
        
        guard let navigationController else { assertionFailure(); return }
        
        guard let index = navigationController.viewControllers.firstIndex(where: { $0 is ListOfBackupedProfilesAcrossDeviceHostingView }) else {
            navigationController.pushViewController(vc, animated: true)
            return
        }
        
        let newStack = [UIViewController](navigationController.viewControllers[0..<index] + [vc])
        
        navigationController.setViewControllers(newStack, animated: true)
        
    }

    
}


// MARK: - Errors

extension Router {
    
    enum ObvError: Error {
        case delegateOrParentRouterIsNil
    }
    
}





// MARK: - Previews

#if DEBUG

@available(iOS 17.0, *)
#Preview {
    PreviewSettingsNavigationController()
}

#endif
