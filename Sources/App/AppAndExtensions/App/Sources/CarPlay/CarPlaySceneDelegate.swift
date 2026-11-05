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

import Foundation
import UIKit
import AVFoundation
import ObvTypes
import OSLog
import ObvAppTypes
import ObvUICoreData
import ObvSettings
import ObvEngine
import ObvCarPlay
import ObvAppCoreConstants

#if canImport(CarPlay)
import CarPlay
@preconcurrency import Intents


@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "CarPlaySceneDelegate")
    
    private weak var interfaceController: CPInterfaceController?
    
    private var discussionsTemplate: CarPlayDiscussionsListTemplate?
    
    private var dataSources: CarPlayDataSources?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        Self.logger.info("[CarPlay] willConnectTo")
        if !connectionOptions.userActivities.isEmpty {
            Self.logger.info("[CarPlay] Scene will connect with user activities")
            Task {
                for userActivity in connectionOptions.userActivities {
                    await continueUserActivity(userActivity)
                }
            }
        }
    }
    
    // MARK: CPTemplateApplicationSceneDelegate
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        Self.logger.info("[CarPlay] didConnect")
        ensureSiriAuthorization()
        self.interfaceController = interfaceController
        // In its own task, so that the discussions list does not wait for it
        Task {
            await UserNotificationsCoordinator.requestCarPlayNotificationAuthorizationUnlessEnabled()
        }
        Task { [weak self] in
            guard let self else { return }
            _ = await NewAppStateManager.shared.waitUntilAppIsInitialized()
            do {
                try await self.startDiscussionsList()
            } catch {
                Self.logger.error("[CarPlay] Failed to start discussions list: \(error.localizedDescription)")
                self.presentErrorAlert(message: NSLocalizedString("CARPLAY_ERROR_LOADING_DISCUSSIONS", comment: ""))
            }
        }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        Self.logger.info("[CarPlay] didDisconnect")
        self.interfaceController = nil
        discussionsTemplate?.stopFetch()
        discussionsTemplate = nil
        dataSources = nil
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        Task {
            await continueUserActivity(userActivity)
        }
    }
    
    func continueUserActivity(_ userActivity: NSUserActivity) async {
        Self.logger.info("[CarPlay] continueUserActivity: \(userActivity.activityType, privacy: .public)")
        _ = await NewAppStateManager.shared.waitUntilAppIsInitialized()
        if let startCallIntent = userActivity.interaction?.intent as? INStartCallIntent {
            Self.logger.info("[CarPlay] Received INStartCallIntent")
            await processINStartCallIntent(startCallIntent: startCallIntent)
        } else {
            Self.logger.error("[CarPlay] Received unhandled user activity type: \(userActivity.activityType, privacy: .public)")
        }
    }

    /// Called when the user taps on a previous call in the system call log, or initiates a call via Siri on CarPlay.
    ///
    /// `StartCallIntentHandler.confirm` already validated microphone permission, contact reachability,
    /// and subscription before returning `.ready`. This method only needs to resolve
    /// `ownedIdentityForRequestingTurnCredentials` and post the call notification.
    ///
    /// Posts `userWantsToCallOrUpdateCallCapabilityAndIsAllowedTo` directly — bypassing
    /// `userWantsToCallOrUpdateCallCapabilityButWeShouldCheckSheIsAllowedTo` which is only observed
    /// by `MainFlowViewController` (never alive when the app is launched headlessly for CarPlay).
    private func processINStartCallIntent(startCallIntent: INStartCallIntent) async {
        Self.logger.info("[CarPlay] processINStartCallIntent")
        ObvStack.shared.performBackgroundTask { [weak self] context in
            guard let params = startCallIntent.callParameters(within: context) else {
                Self.logger.fault("[CarPlay] Could not determine call parameters")
                Task { self?.presentErrorAlert(message: NSLocalizedString("CARPLAY_ERROR_CALL_FAILED", comment: "")) }
                return
            }
            guard let ownedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: params.ownedCryptoId, within: context),
                  let ownedIdentityForRequestingTurnCredentials = ownedIdentity.ownedCryptoIdAllowedToEmitSecureCall else {
                Self.logger.fault("[CarPlay] Could not determine ownedIdentityForRequestingTurnCredentials")
                Task { self?.presentErrorAlert(message: NSLocalizedString("CARPLAY_ERROR_CALL_FAILED", comment: "")) }
                return
            }
            Self.logger.info("[CarPlay] Placing call")
            ObvMessengerInternalNotification.userWantsToCallOrUpdateCallCapabilityAndIsAllowedTo(
                ownedCryptoId: params.ownedCryptoId,
                contactCryptoIds: params.contactCryptoIds,
                ownedIdentityForRequestingTurnCredentials: ownedIdentityForRequestingTurnCredentials,
                groupId: params.groupId,
                startCallIntent: startCallIntent)
                .postOnDispatchQueue()
        }
    }
    
    
    private func ensureSiriAuthorization() {
        switch INPreferences.siriAuthorizationStatus() {
        case .notDetermined:
            INPreferences.requestSiriAuthorization { _ in }
        case .restricted:
            return
        case .denied:
            return
        case .authorized:
            return
        @unknown default:
            return
        }
    }

    
    // MARK: - Error alerts

    @MainActor
    private func presentErrorAlert(message: String) {
        guard let interfaceController else { return }
        let okAction = CPAlertAction(title: String(localized: "OK"), style: .cancel) { _ in
            interfaceController.dismissTemplate(animated: true, completion: nil)
        }
        let alert = CPAlertTemplate(titleVariants: [message], actions: [okAction])
        interfaceController.presentTemplate(alert, animated: true, completion: nil)
    }

    // MARK: - Discussions list

    private func startDiscussionsList() async throws {

        guard let interfaceController,
              let currentOwnedCryptoId = await MostAppropriateOwnedIdentityHelper(context: ObvStack.shared.newBackgroundContext()).mostAppropriateOwnedCryptoIdToShow(),
              let currentOwnedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: currentOwnedCryptoId, within: ObvStack.shared.viewContext) else { return }

        let viewContext = ObvStack.shared.viewContext
        let backgroundContext = ObvStack.shared.newBackgroundContext()

        dataSources = CarPlayDataSources(viewContext: viewContext,
                                         backgroundContext: backgroundContext)

        guard let dataSources else { return }

        let template = CarPlayDiscussionsListTemplate(
            currentOwnedCryptoId: currentOwnedCryptoId,
            effectiveAPIPermissionsOfCurrentOwnedIdentity: currentOwnedIdentity.effectiveAPIPermissions,
            dataSource: dataSources.carPlayDiscussionsListViewDataSource,
            interfaceController: interfaceController)
        
        self.discussionsTemplate = template

        try await interfaceController.setRootTemplate(template.listTemplate, animated: true)

        try await template.performFetch()

    }

}

#endif
