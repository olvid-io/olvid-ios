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

@MainActor
public protocol ObvAppBackupSetupRouterDelegate: AnyObject {
    @MainActor func getOrCreateDeviceBackupSeed(_ router: ObvAppBackupSetupRouter, saveToKeychain: Bool) async throws -> BackupSeed
    @MainActor func userWantsToDeactivateBackups(_ router: ObvAppBackupSetupRouter) async throws
    @MainActor func userHasFinishedTheBackupsSetup(_ router: ObvAppBackupSetupRouter)
    @MainActor func userWantsToBeRemindedToWriteDownBackupKey(_ router: ObvAppBackupSetupRouter) async
}


@MainActor
public final class ObvAppBackupSetupRouter {
    
    private let router: Router
    fileprivate weak var delegate: ObvAppBackupSetupRouterDelegate?
    public let localNavigationController: UINavigationController?

    public init(navigationController: UINavigationController?, delegate: ObvAppBackupSetupRouterDelegate, context: ObvAppBackupSetupContext) {
        if let navigationController {
            self.localNavigationController = nil
            self.router = Router(navigationController: navigationController, context: context)
        } else {
            let nav = UINavigationController()
            self.localNavigationController = nav
            self.router = Router(navigationController: nav, context: context)
        }
        self.delegate = delegate
        self.router.parentRouter = self
    }

}


// MARK: - Public API

extension ObvAppBackupSetupRouter {
    
    public func pushInitialViewController() {
        router.pushInitialViewController()
    }
    
}


// MARK: - Internal router

@MainActor
fileprivate final class Router {
    
    private weak var navigationController: UINavigationController?
    fileprivate let initialNavigationStack: [UIViewController]
    fileprivate weak var parentRouter: ObvAppBackupSetupRouter?
    private let context: ObvAppBackupSetupContext

    init(navigationController: UINavigationController, context: ObvAppBackupSetupContext) {
        self.navigationController = navigationController
        self.initialNavigationStack = navigationController.viewControllers
        self.context = context
    }
 
    
    func pushInitialViewController() {
        let vc = ChooseAutomaticBackupsOrNavigateToAdvancedSettingsHostingView(context: context, delegate: self)
        guard let navigationController else { assertionFailure(); return }
        if navigationController.viewControllers.isEmpty {
            navigationController.setViewControllers([vc], animated: false)
        } else {
            navigationController.pushViewController(vc, animated: true)
        }
    }

}


// MARK: - Implementing ChooseAutomaticBackupsOrNavigateToAdvancedSettingsHostingViewDelegate

extension Router: ChooseAutomaticBackupsOrNavigateToAdvancedSettingsHostingViewDelegate {
    
    func userChoseToActivateBackupsAndToSaveDeviceSeedToKeychainThusNewSeedMustBeGenerated(_ vc: ChooseAutomaticBackupsOrNavigateToAdvancedSettingsHostingView) async throws -> ObvCrypto.BackupSeed {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
        return try await delegate.getOrCreateDeviceBackupSeed(parentRouter, saveToKeychain: true)
    }
    
    
    /// This is called when the user chooses the recommended scenario (activate backups and save the key to the Keychain), after the whole process is successful.
    func userChoseToActivateBackupsAndToSaveDeviceSeedToKeychainAndNewSeedWasGenerated(_ vc: ChooseAutomaticBackupsOrNavigateToAdvancedSettingsHostingView, backupSeed: ObvCrypto.BackupSeed) {
        switch context {
        case .onboarding:
            guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); return }
            delegate.userHasFinishedTheBackupsSetup(parentRouter)
        case .afterOnboardingWithoutMigratingFromLegacyBackups, .afterOnboardingMigratingFromLegacyBackups:
            let vc = AutomaticBackupSuccessfullyActivatedConfirmationViewController(delegate: self)
            navigationController?.setViewControllers([vc], animated: true)
        }
    }
    
    
    func userChoseToActivateBackupsAndToSaveDeviceSeedToKeychainAndNewSeedFailedToBeGenerated(_ vc: ChooseAutomaticBackupsOrNavigateToAdvancedSettingsHostingView) {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); return }
        delegate.userHasFinishedTheBackupsSetup(parentRouter)
    }
    
    
    func userWantsToSeeAdvancedSetupParameters(_ vc: ChooseAutomaticBackupsOrNavigateToAdvancedSettingsHostingView) async {
        let vc = AdvancedSetupParametersHostingView(delegate: self)
        navigationController?.pushViewController(vc, animated: true)
    }
    
 
    func userChoseBackupModeAndTheNewSeedFailedToBeGenerated(_ vc: ChooseAutomaticBackupsOrNavigateToAdvancedSettingsHostingView) {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); return }
        delegate.userHasFinishedTheBackupsSetup(parentRouter)
    }

}


// MARK: - Implementing AutomaticBackupSuccessfullyActivatedConfirmationViewControllerDelegate


extension Router: AutomaticBackupSuccessfullyActivatedConfirmationViewControllerDelegate {
    
    func userWantsToDismissAutomaticBackupSuccessfullyActivatedConfirmationView(_ vc: AutomaticBackupSuccessfullyActivatedConfirmationViewController) {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); return }
        delegate.userHasFinishedTheBackupsSetup(parentRouter)
    }
    
}


// MARK: - AdvancedSetupParametersHostingViewDelegate

extension Router: AdvancedSetupParametersHostingViewDelegate {
    
    func userValidatedAdvancedSetupParameterThusNewSeedMustBeGenerated(_ vc: AdvancedSetupParametersHostingView, saveToKeychain: Bool) async throws -> ObvCrypto.BackupSeed {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); throw ObvError.delegateOrParentRouterIsNil }
        return try await delegate.getOrCreateDeviceBackupSeed(parentRouter, saveToKeychain: saveToKeychain)
    }

    
    func userValidatedAdvancedSetupParameterAndDoNotWantBackups(_ vc: AdvancedSetupParametersHostingView) async throws {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); return }
        try await delegate.userWantsToDeactivateBackups(parentRouter)
        delegate.userHasFinishedTheBackupsSetup(parentRouter)
    }
    
    
    func userValidatedAdvancedSetupParameterAndNewSeedWasGenerated(_ vc: AdvancedSetupParametersHostingView, backupSeed: ObvCrypto.BackupSeed, savedToKeychain: Bool) {
        if savedToKeychain {
            guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); return }
            delegate.userHasFinishedTheBackupsSetup(parentRouter)
        } else {
            let vc = BackupKeyDisplayerHostingHostingView(model: .init(backupSeed: backupSeed), delegate: self)
            navigationController?.pushViewController(vc, animated: true)
        }
    }
    
    func userValidatedAdvancedSetupParameterButNewSeedFailedToBeGenerate(_ vc: AdvancedSetupParametersHostingView) {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); return }
        delegate.userHasFinishedTheBackupsSetup(parentRouter)
    }
    
    
    func userValidatedAdvancedSetupParameterButDeactivationFailed(_ vc: AdvancedSetupParametersHostingView) {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); return }
        delegate.userHasFinishedTheBackupsSetup(parentRouter)
    }
        
}


// MARK: - Implementing BackupKeyDisplayerHostingHostingViewDelegate

extension Router: BackupKeyDisplayerHostingHostingViewDelegate {
    
    /// Called when user confirms they wrote down the device backup seed. In that case, we can simply dismiss this flow.
    func userConfirmedWritingDownTheBackupKey(_ vc: BackupKeyDisplayerHostingHostingView, remindToSaveBackupKey: Bool) {
        guard let parentRouter, let delegate = parentRouter.delegate else { assertionFailure(); return }
        if remindToSaveBackupKey {
            Task { await delegate.userWantsToBeRemindedToWriteDownBackupKey(parentRouter) }
        }
        delegate.userHasFinishedTheBackupsSetup(parentRouter)
    }

}


// MARK: - Errors

extension Router {
    
    enum ObvError: Error {
        case delegateOrParentRouterIsNil
    }
    
}



// MARK: - Previews

@MainActor
private final class DelegateForPreviews: ObvAppBackupSetupRouterDelegate {
        
    private var neverBackupMyProfile: Bool = false
    
    func userChangedAdvancedSetupParameter(_ router: ObvAppBackupSetupRouter, neverBackupMyProfile: Bool) async throws {
        try await Task.sleep(seconds: 2)
        self.neverBackupMyProfile = neverBackupMyProfile
    }
    
    
    func userWantsToKnowAdvancedSetupParameterValueForNeverBackupMyProfile(router: ObvAppBackupSetupRouter) async -> Bool {
        return neverBackupMyProfile
    }
    
    
    func getOrCreateDeviceBackupSeed(_ router: ObvAppBackupSetupRouter, saveToKeychain: Bool) async throws -> BackupSeed {
        try await Task.sleep(seconds: 1)
        return .init(with: Data.init(repeating: 0x05, count: 20))!
    }
    
    func userHasFinishedTheBackupsSetup(_ router: ObvAppBackupSetupRouter) {}
    
    func userWantsToDeactivateBackups(_ router: ObvAppBackupSetupRouter) async throws {}
    
    func userWantsToBeRemindedToWriteDownBackupKey(_ router: ObvAppBackupSetupRouter) {}

}


/// This view controller illustrates the use of the router when the context is either `.afterOnboardingMigratingFromLegacyBackups`
/// or `.afterOnboardingWithoutMigratingFromLegacyBackups`. In that case, we pass `nil` for the navigation of the router and
/// use the one it creates.
private final class ViewControllerForPreviews: UIViewController {
    
    let router: ObvAppBackupSetupRouter
    let delegateForPreviews: DelegateForPreviews
    
    init(context: ObvAppBackupSetupContext) {
        let delegateForPreviews = DelegateForPreviews()
        self.delegateForPreviews = delegateForPreviews
        self.router = ObvAppBackupSetupRouter(navigationController: nil, delegate: delegateForPreviews, context: context)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        router.pushInitialViewController()
        guard let nav = router.localNavigationController else { assertionFailure(); return }
        self.present(nav, animated: true)
    }
    
}


private final class AlternateViewControllerForPreviews: UINavigationController {
    
    private var router: ObvAppBackupSetupRouter?
    private let delegateForPreviews: DelegateForPreviews
    private let rootViewController = UIViewController(nibName: nil, bundle: nil)

    init() {
        self.delegateForPreviews = DelegateForPreviews()
        super.init(rootViewController: rootViewController)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.rootViewController.view.backgroundColor = .red
        self.router = ObvAppBackupSetupRouter(navigationController: self, delegate: delegateForPreviews, context: .onboarding)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.router?.pushInitialViewController()
    }
    
}

@available(iOS 17.0, *)
#Preview("After onboarding") {
    ViewControllerForPreviews(context: .afterOnboardingWithoutMigratingFromLegacyBackups)
}

@available(iOS 17.0, *)
#Preview("After onboarding") {
    ViewControllerForPreviews(context: .afterOnboardingMigratingFromLegacyBackups)
}


@available(iOS 17.0, *)
#Preview("During onboarding") {
    AlternateViewControllerForPreviews()
}
