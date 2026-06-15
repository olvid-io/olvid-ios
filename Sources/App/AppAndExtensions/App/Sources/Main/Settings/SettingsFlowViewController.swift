/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvTypes
import ObvEngine
import ObvUICoreData
import ObvAppTypes
import ObvAppBackup
import ObvCrypto
import ObvDesignSystem
import ObvHistoryTransfer
import ObvSettings


final class SettingsFlowViewController: KeyboardNavigationController {

    private(set) var ownedCryptoId: ObvCryptoId!
    private(set) var obvEngine: ObvEngine!

    private weak var createPasscodeDelegate: CreatePasscodeDelegate?
    private weak var localAuthenticationDelegate: LocalAuthenticationDelegate?
    private weak var appBackupDelegate: AppBackupDelegate?
    private weak var settingsFlowViewControllerDelegate: SettingsFlowViewControllerDelegate?

    private var backupSettingsRouter: ObvAppBackupSettingsRouter? // Set whenever the user navigates to the backup settings

    private let dataSources: HistoryTransferNavigationStack.DataSources

    init(ownedCryptoId: ObvCryptoId,
         obvEngine: ObvEngine,
         createPasscodeDelegate: CreatePasscodeDelegate,
         localAuthenticationDelegate: LocalAuthenticationDelegate,
         appBackupDelegate: AppBackupDelegate,
         settingsFlowViewControllerDelegate: SettingsFlowViewControllerDelegate,
         dataSources: HistoryTransferNavigationStack.DataSources) {
        
        let allSettingsTableViewController = AllSettingsTableViewController(ownedCryptoId: ownedCryptoId)
        self.dataSources = dataSources

        super.init(rootViewController: allSettingsTableViewController)

        self.ownedCryptoId = ownedCryptoId
        self.obvEngine = obvEngine
        self.createPasscodeDelegate = createPasscodeDelegate
        self.localAuthenticationDelegate = localAuthenticationDelegate
        self.appBackupDelegate = appBackupDelegate
        self.settingsFlowViewControllerDelegate = settingsFlowViewControllerDelegate

        allSettingsTableViewController.delegate = self

        self.title = CommonString.Word.Settings

        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
        let image = UIImage(systemName: "gear", withConfiguration: symbolConfiguration)
        self.tabBarItem = UITabBarItem(title: nil, image: image, tag: 0)
    }
    
    required init?(coder aDecoder: NSCoder) { fatalError("die") }
    
}


// MARK: - View controller lifecycle

extension SettingsFlowViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if #available(iOS 26, *) {
            // We don't change the appearance under iOS 26
        } else {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            navigationBar.standardAppearance = appearance
        }

    }
    
}


// MARK: - AllSettingsTableViewControllerDelegate

extension SettingsFlowViewController: AllSettingsTableViewControllerDelegate {
    
    func pushSetting(_ setting: AllSettingsTableViewController.Setting, tableView: UITableView?, didSelectRowAt indexPath: IndexPath?) async {
        let settingViewController: UIViewController
        switch setting {
        case .contactsAndGroups:
            settingViewController = ContactsAndGroupsSettingsTableViewController(ownedCryptoId: ownedCryptoId, obvEngine: obvEngine)
        case .downloads:
            settingViewController = DownloadsSettingsTableViewController()
        case .interface:
            settingViewController = InterfaceSettingsTableViewController(ownedCryptoId: ownedCryptoId, actions: self)
        case .discussions:
            settingViewController = DiscussionsDefaultSettingsHostingViewController(ownedCryptoId: ownedCryptoId)
        case .privacy:
            guard let createPasscodeDelegate, let localAuthenticationDelegate else {
                assertionFailure(); return
            }
            settingViewController = PrivacyTableViewController(
                ownedCryptoId: ownedCryptoId,
                createPasscodeDelegate: createPasscodeDelegate,
                localAuthenticationDelegate: localAuthenticationDelegate)
        case .backup:
            // Three possible cases:
            // Case 1: the user has a new backup seed, we can navigate to the view controller provided in the ObvAppBackup module
            // Case 2: the user does not have a new backup seed, and has a legacy backup seed. We navigate to the legacy BackupTableViewController
            // Case 3: the user does not have a new backup seed, and has no legacy seed. We navigate to the appropriate view controller provided in the ObvAppBackup module
            do {
                if try await obvEngine.getDeviceActiveBackupSeed() != nil {
                    // We are in case 1
                    let navigationController = self
                    let subscriptionStatus = getSubscriptionStatusForAppBackupOfOwnedCryptoId(self.ownedCryptoId)
                    backupSettingsRouter = ObvAppBackupSettingsRouter(subscriptionStatus: subscriptionStatus, navigationController: navigationController, delegate: self)
                    backupSettingsRouter?.pushInitialViewController()
                    return
                } else if try await obvEngine.getCurrentLegacyBackupKeyInformation() != nil {
                    // We are in case 2
                    settingViewController = BackupTableViewController(obvEngine: obvEngine, appBackupDelegate: appBackupDelegate, delegate: self)
                } else {
                    // We are in case 3
                    if let tableView, let indexPath {
                        tableView.deselectRow(at: indexPath, animated: true)
                    }
                    settingsFlowViewControllerDelegate?.userWantsToConfigureNewBackups(self, context: .afterOnboardingWithoutMigratingFromLegacyBackups)
                    return
                }
            } catch {
                assertionFailure()
                return
            }
        case .about:
            settingViewController = AboutSettingsTableViewController()
        case .advanced:
            settingViewController = AdvancedSettingsViewController(ownedCryptoId: ownedCryptoId, obvEngine: obvEngine, delegate: self)
        case .voip:
            settingViewController = VoIPSettingsTableViewController()
        case .historyTransfer:
            // We present a stack for the history transfer, as the navigation is managed by SwiftUI.
            // Eventually, we will refactor this view to migrate to a full SwiftUI navigation for the settings.
            let vc = HistoryTransferNavigationStackHostingView(
                currentOwnedCryptoId: ownedCryptoId,
                temporaryDirectory: ObvUICoreDataConstants.ContainerURL.forTempFiles.url,
                dataSources: self.dataSources,
                actions: self)
            self.presentOnTop(vc, animated: true) {
                if let tableView, let indexPath {
                    tableView.deselectRow(at: indexPath, animated: true)
                }
            }
            return
        }
        settingViewController.navigationItem.largeTitleDisplayMode = .never
        
        if let allSettingsTableViewController = children.first as? AllSettingsTableViewController, allSettingsTableViewController.tableView.indexPathForSelectedRow == nil {
            allSettingsTableViewController.selectRowOfSetting(setting) { [weak self] in
                self?.pushViewController(settingViewController, animated: true)
            }
        } else {
            pushViewController(settingViewController, animated: true)
        }
    }
    
}


// MARK: - Implementing HistoryTransferNavigationStackActions

extension SettingsFlowViewController: HistoryTransferNavigationStackActions {
    
    func userRequiresMessageHistoryTransferService(_ view: ObvHistoryTransfer.LocalNetworkImportView) async throws -> any ObvHistoryTransfer.TransferServiceForLocalNetworkImportView {
        guard let settingsFlowViewControllerDelegate else { assertionFailure(); throw ObvError.settingsFlowViewControllerDelegateIsNil }
        return try await settingsFlowViewControllerDelegate.userRequiresMessageHistoryTransferService(self)
    }
    
        
    func userRequiresMessageHistoryTransferService(_ view: ObvHistoryTransfer.LocalNetworkExportView) async throws -> any ObvHistoryTransfer.TransferServiceForLocalNetworkExportView {
        guard let settingsFlowViewControllerDelegate else { assertionFailure(); throw ObvError.settingsFlowViewControllerDelegateIsNil }
        return try await settingsFlowViewControllerDelegate.userRequiresMessageHistoryTransferService(self)
    }

    
    /// Called on the source device when using the WebRTC (Wifi) method to transfer history. This method should eventually send a message to the other owned device (the destination), allowing it to show a confirmation screen to the user, allowing them
    /// to start or cancel the transfer. This method is highly asynchronous as it returns this decision.
    func historySourceDeviceWantsToSendTransferConfirmationRequestToDestinationOwnedDevice(
        _ view: ObvHistoryTransfer.LocalNetworkExportView,
        transferId: String,
        otherOwnedDeviceIdentifier: ObvTypes.ObvOwnedDeviceIdentifier
    ) async throws -> ObvHistoryTransfer.DestinationOwnedDeviceDecision {
        guard let settingsFlowViewControllerDelegate else { assertionFailure(); throw ObvError.settingsFlowViewControllerDelegateIsNil }
        return try await settingsFlowViewControllerDelegate.historySourceDeviceWantsToSendTransferConfirmationRequestToDestinationOwnedDevice(self, transferId: transferId, otherOwnedDeviceIdentifier: otherOwnedDeviceIdentifier)
    }
    
    
    func userWantsToDismissView(_ view: LocalNetworkExportView) {
        (self.presentedViewController as? HistoryTransferNavigationStackHostingView)?.dismiss(animated: true)
    }

    
    func userWantsToDismissHistoryTransferNavigationStack(_ view: HistoryTransferNavigationStack) {
        (self.presentedViewController as? HistoryTransferNavigationStackHostingView)?.dismiss(animated: true)
    }
    
    
    func userWantsToDismissView(_ view: ObvHistoryTransfer.LocalNetworkImportView) {
        (self.presentedViewController as? HistoryTransferNavigationStackHostingView)?.dismiss(animated: true)
    }

}


extension SettingsFlowViewController: ZipExportViewActions {
    
    func userRequiresMessageHistoryTransferService(_ view: ObvHistoryTransfer.ZipExportView) async throws -> any ObvHistoryTransfer.TransferServiceForZipExportView {
        guard let settingsFlowViewControllerDelegate else { assertionFailure(); throw ObvError.settingsFlowViewControllerDelegateIsNil }
        return try await settingsFlowViewControllerDelegate.userRequiresMessageHistoryTransferService(self)
    }
    
}


extension SettingsFlowViewController: ZipImportViewActions {
    
    func userRequiresMessageHistoryTransferService(_ view: ObvHistoryTransfer.ZipImportView) async throws -> any ObvHistoryTransfer.TransferServiceForZipImportView {
        guard let settingsFlowViewControllerDelegate else { assertionFailure(); throw ObvError.settingsFlowViewControllerDelegateIsNil }
        return try await settingsFlowViewControllerDelegate.userRequiresMessageHistoryTransferService(self)
    }

    func userWantsToDismissView(_ view: ZipImportView) {
        (self.presentedViewController as? HistoryTransferNavigationStackHostingView)?.dismiss(animated: true)
    }
    
}

// MARK: - Implementing InterfaceSettingsTableViewControllerActions

extension SettingsFlowViewController: InterfaceSettingsTableViewControllerActions {
    
    func userWantsToUpdateDiscussionLocalConfiguration(
        _ vc: InterfaceSettingsTableViewController,
        value: ObvUICoreData.PersistedDiscussionLocalConfigurationValue,
        localConfigurationObjectID: ObvUICoreData.TypeSafeManagedObjectID<ObvUICoreData.PersistedDiscussionLocalConfiguration>) async throws {
            guard let settingsFlowViewControllerDelegate else { assertionFailure(); throw ObvError.settingsFlowViewControllerDelegateIsNil }
            try await settingsFlowViewControllerDelegate.userWantsToUpdateDiscussionLocalConfiguration(self, value: value, localConfigurationObjectID: localConfigurationObjectID)
    }
    
}


// MARK: - Implementing ObvAppBackupSettingsRouterDelegate

extension SettingsFlowViewController: ObvAppBackupSettingsRouterDelegate {
    
    func userWantsToBeRemindedToWriteDownBackupKey(_ router: ObvAppBackup.ObvAppBackupSettingsRouter) async {
        guard let settingsFlowViewControllerDelegate else { assertionFailure(); return }
        await settingsFlowViewControllerDelegate.userWantsToBeRemindedToWriteDownBackupKey(self)
    }
    
    func getDeviceDeactivationConsequencesOfRestoringBackup(_ router: ObvAppBackup.ObvAppBackupSettingsRouter, ownedCryptoIdentity: ObvCrypto.ObvOwnedCryptoIdentity) async throws -> ObvAppBackup.ObvDeviceDeactivationConsequence {
        guard let settingsFlowViewControllerDelegate else { assertionFailure(); throw ObvError.settingsFlowViewControllerDelegateIsNil }
        return try await settingsFlowViewControllerDelegate.getDeviceDeactivationConsequencesOfRestoringBackup(self, ownedCryptoIdentity: ownedCryptoIdentity)
    }
    
    
    func userWantsToKeepAllDevicesActiveThanksToOlvidPlus(_ router: ObvAppBackup.ObvAppBackupSettingsRouter, ownedCryptoIdentity: ObvCrypto.ObvOwnedCryptoIdentity) async throws -> ObvAppBackup.ObvDeviceDeactivationConsequence {
        guard let settingsFlowViewControllerDelegate else { assertionFailure(); throw ObvError.settingsFlowViewControllerDelegateIsNil }
        return try await settingsFlowViewControllerDelegate.userWantsToKeepAllDevicesActiveThanksToOlvidPlus(self, ownedCryptoIdentity: ownedCryptoIdentity)
    }
    
    
    func userWantsToCancelProfileRestoration(_ router: ObvAppBackup.ObvAppBackupSettingsRouter) {
        self.backupSettingsRouter = nil
    }
    
    
    func fetchAvatarImage(_ router: ObvAppBackupSettingsRouter, profileCryptoId: ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        guard let settingsFlowViewControllerDelegate else { assertionFailure(); return nil }
        return await settingsFlowViewControllerDelegate.fetchAvatarImage(self, profileCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, frameSize: frameSize)
    }
    

    func userWantsToDeleteProfileBackupFromSettings(_ router: ObvAppBackupSettingsRouter, infoForDeletion: ObvProfileBackupFromServer.InfoForDeletion) async throws {
        guard let settingsFlowViewControllerDelegate else {
            assertionFailure()
            throw ObvError.settingsFlowViewControllerDelegateIsNil
        }
        try await settingsFlowViewControllerDelegate.userWantsToDeleteProfileBackupFromSettings(self, infoForDeletion: infoForDeletion)
    }
    
    
    func userWantsToResetThisDeviceSeedAndBackups(_ router: ObvAppBackupSettingsRouter) async throws {
        guard let settingsFlowViewControllerDelegate else {
            assertionFailure()
            throw ObvError.settingsFlowViewControllerDelegateIsNil
        }
        try await settingsFlowViewControllerDelegate.userWantsToResetThisDeviceSeedAndBackups(self)
    }
    
    
    func userWantsToSubscribeOlvidPlus(_ router: ObvAppBackup.ObvAppBackupSettingsRouter) {
        guard let settingsFlowViewControllerDelegate else {
            assertionFailure()
            return
        }
        settingsFlowViewControllerDelegate.userWantsToSubscribeOlvidPlus(self)
    }
    
    
    func userWantsToAddDevice(_ router: ObvAppBackup.ObvAppBackupSettingsRouter) {
        guard let settingsFlowViewControllerDelegate else {
            assertionFailure()
            return
        }
        settingsFlowViewControllerDelegate.userWantsToAddDevice(self)
    }
    
    
    func userWantsToOpenProfile(_ router: ObvAppBackupSettingsRouter, ownedCryptoId: ObvCryptoId) {
        self.dismiss(animated: true) {
            let deepLink = ObvDeepLink.latestDiscussions(ownedCryptoId: ownedCryptoId)
            ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                .postOnDispatchQueue()
        }
    }

    
    func restoreProfileBackupFromServerNow(_ router: ObvAppBackupSettingsRouter, profileBackupFromServerToRestore: ObvProfileBackupFromServer, rawAuthState: Data?) async throws -> ObvRestoredOwnedIdentityInfos {
        guard let settingsFlowViewControllerDelegate else {
            assertionFailure()
            throw ObvError.settingsFlowViewControllerDelegateIsNil
        }
        return try await settingsFlowViewControllerDelegate.restoreProfileBackupFromServerNow(self,
                                                                                              profileBackupFromServerToRestore: profileBackupFromServerToRestore,
                                                                                              rawAuthState: rawAuthState)
    }
    
    
    /// Called when the user wants to list all available backups of a specific profile.
    func userWantsToFetchAllProfileBackupsFromServer(_ router: ObvAppBackup.ObvAppBackupSettingsRouter, profileCryptoId: ObvCryptoId, profileBackupSeed: ObvCrypto.BackupSeed) async throws -> [ObvProfileBackupFromServer] {
        guard let settingsFlowViewControllerDelegate else {
            assertionFailure()
            throw ObvError.settingsFlowViewControllerDelegateIsNil
        }
        let profileBackupsFromServer = try await settingsFlowViewControllerDelegate.userWantsToFetchAllProfileBackupsFromServer(self, profileCryptoId: profileCryptoId, profileBackupSeed: profileBackupSeed)
        return profileBackupsFromServer
    }
    
    
    func getDeviceActiveBackupSeed(_ router: ObvAppBackup.ObvAppBackupSettingsRouter) async throws -> ObvCrypto.BackupSeed? {
        return try await obvEngine.getDeviceActiveBackupSeed()
    }
    
    
    func usersWantsToGetBackupParameterIsSynchronizedWithICloud(_ router: ObvAppBackup.ObvAppBackupSettingsRouter) async throws -> Bool {
        guard let settingsFlowViewControllerDelegate else {
            assertionFailure()
            throw ObvError.settingsFlowViewControllerDelegateIsNil
        }
        return try await settingsFlowViewControllerDelegate.usersWantsToGetBackupParameterIsSynchronizedWithICloud(self)
    }
    
    
    func usersWantsToChangeBackupParameterIsSynchronizedWithICloud(_ router: ObvAppBackup.ObvAppBackupSettingsRouter, newIsSynchronizedWithICloud: Bool) async throws {
        guard let settingsFlowViewControllerDelegate else {
            assertionFailure()
            throw ObvError.settingsFlowViewControllerDelegateIsNil
        }
        return try await settingsFlowViewControllerDelegate.usersWantsToChangeBackupParameterIsSynchronizedWithICloud(self, newIsSynchronizedWithICloud: newIsSynchronizedWithICloud)
    }
    
    
    func userWantsToPerformBackupNow(_ router: ObvAppBackup.ObvAppBackupSettingsRouter) async throws {
        try await settingsFlowViewControllerDelegate?.userWantsToPerformBackupNow(self)
    }
    
    
    func userWantsToEraseAndGenerateNewDeviceBackupSeed(_ router: ObvAppBackup.ObvAppBackupSettingsRouter) async throws -> ObvCrypto.BackupSeed {
        guard let settingsFlowViewControllerDelegate else {
            assertionFailure()
            throw ObvError.settingsFlowViewControllerDelegateIsNil
        }
        return try await settingsFlowViewControllerDelegate.userWantsToEraseAndGenerateNewDeviceBackupSeed(self)
    }

    
    func userWantsToFetchDeviceBakupFromServer(_ router: ObvAppBackup.ObvAppBackupSettingsRouter) async throws -> AsyncStream<ObvAppBackup.ObvDeviceBackupFromServerWithAppInfoKind> {
        guard let settingsFlowViewControllerDelegate else {
            assertionFailure()
            throw ObvError.settingsFlowViewControllerDelegateIsNil
        }
        return try await settingsFlowViewControllerDelegate.userWantsToFetchDeviceBakupFromServer(self)
    }
    
    
    func userWantsToUseDeviceBackupSeed(_ router: ObvAppBackup.ObvAppBackupSettingsRouter, deviceBackupSeed: ObvCrypto.BackupSeed) async throws -> ObvAppBackup.ObvListOfDeviceBackupProfiles {
        guard let settingsFlowViewControllerDelegate else {
            assertionFailure()
            throw ObvError.settingsFlowViewControllerDelegateIsNil
        }
        return try await settingsFlowViewControllerDelegate.userWantsToUseDeviceBackupSeed(self, deviceBackupSeed: deviceBackupSeed)
    }
    
    
    func userNeedsToProveCapacityToAuthenticateOnKeycloakServerAsTransferIsRestricted(_ router: ObvAppBackupSettingsRouter, keycloakConfiguration: ObvKeycloakConfiguration) async throws -> Data {
        guard let settingsFlowViewControllerDelegate else {
            assertionFailure()
            throw ObvError.settingsFlowViewControllerDelegateIsNil
        }
        return try await settingsFlowViewControllerDelegate.userNeedsToProveCapacityToAuthenticateOnKeycloakServerAsTransferIsRestricted(self, keycloakConfiguration: keycloakConfiguration)
    }
    
}


// MARK: - Errors

extension SettingsFlowViewController {
    
    enum ObvError: Error {
        case settingsFlowViewControllerDelegateIsNil
    }
    
}


// MARK: - Private helpers

extension SettingsFlowViewController {
    
    private func getSubscriptionStatusForAppBackupOfOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> ObvSubscriptionStatusForAppBackup {
        do {
            let apiKeyElements = try PersistedObvOwnedIdentity.getAPIKeyElementsOfOwnedCryptoId(ownedCryptoId, within: ObvStack.shared.viewContext)
            guard apiKeyElements.permissions.contains(.multidevice) else {
                return .noSubscription
            }
            let numberOfOwnedDevices = try PersistedObvOwnedIdentity.getNumberOfDevicesOfOwnedIdentity(ownedCryptoId: ownedCryptoId, within: ObvStack.shared.viewContext)
            if numberOfOwnedDevices > 1 {
                return .multideviceSubscriptionWithMultipleDevicesUsed
            } else {
                return .multideviceSubscriptionWithOnlyOneDeviceUsed
            }
        } catch {
            assertionFailure()
            return .noSubscription
        }
    }
    
}


// MARK: - Implementing AdvancedSettingsViewControllerDelegate

extension SettingsFlowViewController: AdvancedSettingsViewControllerDelegate {
    
    func userRequestedAppDatabaseSyncWithEngine(advancedSettingsViewController: AdvancedSettingsViewController) async throws {
        assert(settingsFlowViewControllerDelegate != nil)
        try await settingsFlowViewControllerDelegate?.userRequestedAppDatabaseSyncWithEngine(settingsFlowViewController: self)
    }
    
}

// MARK: - Implementing BackupTableViewControllerDelegate

extension SettingsFlowViewController: BackupTableViewControllerDelegate {
    
    func userWantsToConfigureNewBackups(_ backupTableViewController: BackupTableViewController, context: ObvAppBackupSetupContext) {
        settingsFlowViewControllerDelegate?.userWantsToConfigureNewBackups(self, context: context)
    }
    
}


// MARK: - SettingsFlowViewControllerProtocol

@MainActor
protocol SettingsFlowViewControllerDelegate: AnyObject {
    func userRequestedAppDatabaseSyncWithEngine(settingsFlowViewController: SettingsFlowViewController) async throws
    func userWantsToConfigureNewBackups(_ settingsFlowViewController: SettingsFlowViewController, context: ObvAppBackupSetupContext)
    func usersWantsToGetBackupParameterIsSynchronizedWithICloud(_ settingsFlowViewController: SettingsFlowViewController) async throws -> Bool
    func usersWantsToChangeBackupParameterIsSynchronizedWithICloud(_ settingsFlowViewController: SettingsFlowViewController, newIsSynchronizedWithICloud: Bool) async throws
    func userWantsToEraseAndGenerateNewDeviceBackupSeed(_ settingsFlowViewController: SettingsFlowViewController) async throws -> ObvCrypto.BackupSeed
    func userWantsToPerformBackupNow(_ settingsFlowViewController: SettingsFlowViewController) async throws
    func userWantsToFetchDeviceBakupFromServer(_ settingsFlowViewController: SettingsFlowViewController) async throws -> AsyncStream<ObvDeviceBackupFromServerWithAppInfoKind>
    func userWantsToUseDeviceBackupSeed(_ settingsFlowViewController: SettingsFlowViewController, deviceBackupSeed: BackupSeed) async throws -> ObvListOfDeviceBackupProfiles
    func userWantsToFetchAllProfileBackupsFromServer(_ settingsFlowViewController: SettingsFlowViewController, profileCryptoId: ObvCryptoId, profileBackupSeed: ObvCrypto.BackupSeed) async throws -> [ObvProfileBackupFromServer]
    func restoreProfileBackupFromServerNow(_ settingsFlowViewController: SettingsFlowViewController, profileBackupFromServerToRestore: ObvTypes.ObvProfileBackupFromServer, rawAuthState: Data?) async throws -> ObvRestoredOwnedIdentityInfos
    func userNeedsToProveCapacityToAuthenticateOnKeycloakServerAsTransferIsRestricted(_ settingsFlowViewController: SettingsFlowViewController, keycloakConfiguration: ObvKeycloakConfiguration) async throws -> Data
    func userWantsToSubscribeOlvidPlus(_ settingsFlowViewController: SettingsFlowViewController)
    func userWantsToAddDevice(_ settingsFlowViewController: SettingsFlowViewController)
    func userWantsToResetThisDeviceSeedAndBackups(_ settingsFlowViewController: SettingsFlowViewController) async throws
    func userWantsToDeleteProfileBackupFromSettings(_ settingsFlowViewController: SettingsFlowViewController, infoForDeletion: ObvProfileBackupFromServer.InfoForDeletion) async throws
    func fetchAvatarImage(_ settingsFlowViewController: SettingsFlowViewController, profileCryptoId: ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage?
    func getDeviceDeactivationConsequencesOfRestoringBackup(_ settingsFlowViewController: SettingsFlowViewController, ownedCryptoIdentity: ObvCrypto.ObvOwnedCryptoIdentity) async throws -> ObvAppBackup.ObvDeviceDeactivationConsequence
    func userWantsToKeepAllDevicesActiveThanksToOlvidPlus(_ settingsFlowViewController: SettingsFlowViewController, ownedCryptoIdentity: ObvCrypto.ObvOwnedCryptoIdentity) async throws -> ObvAppBackup.ObvDeviceDeactivationConsequence
    func userWantsToBeRemindedToWriteDownBackupKey(_ settingsFlowViewController: SettingsFlowViewController) async
    func userRequiresMessageHistoryTransferService(_ settingsFlowViewController: SettingsFlowViewController) async throws -> TransferService
    func userWantsToUpdateDiscussionLocalConfiguration(_ vc: SettingsFlowViewController, value: PersistedDiscussionLocalConfigurationValue, localConfigurationObjectID: TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>) async throws
    func historySourceDeviceWantsToSendTransferConfirmationRequestToDestinationOwnedDevice(_ vc: SettingsFlowViewController, transferId: String, otherOwnedDeviceIdentifier: ObvTypes.ObvOwnedDeviceIdentifier) async throws -> ObvHistoryTransfer.DestinationOwnedDeviceDecision
}
