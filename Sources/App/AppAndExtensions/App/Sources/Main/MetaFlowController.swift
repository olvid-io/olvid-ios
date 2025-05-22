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
import os.log
import CoreData
import StoreKit
@preconcurrency import ObvEngine
@preconcurrency import ObvCrypto
@preconcurrency import ObvTypes
import SwiftUI
import AVFAudio
import ObvUI
@preconcurrency import ObvUICoreData
import UniformTypeIdentifiers
import ObvSettings
import ObvDesignSystem
import ObvJWS
import AppAuth
import Contacts
import ObvAppCoreConstants
import ObvKeycloakManager
import ObvOnboarding
import ObvAppTypes
import ObvSubscription
import ObvAppBackup
import ObvImageEditor
import PhotosUI
import ObvLocation


// MARK: - MetaFlowControllerDelegate

protocol MetaFlowControllerDelegate: AnyObject {
    func userRequestedAppDatabaseSyncWithEngine(metaFlowController: MetaFlowController) async throws
    func userWantsToSendDraft(_ metaFlowController: MetaFlowController, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, textBody: String, mentions: Set<MessageJSON.UserMention>) async throws
    func userWantsToAddAttachmentsToDraft(_ metaFlowController: MetaFlowController, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, itemProviders: [NSItemProvider]) async throws
    func userWantsToAddAttachmentsToDraftFromURLs(_ metaFlowController: MetaFlowController, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, urls: [URL]) async throws
    func userWantsToUpdateDraftBodyAndMentions(_ metaFlowController: MetaFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, body: String, mentions: Set<MessageJSON.UserMention>) async throws
    func userWantsToDeleteAttachmentsFromDraft(_ metaFlowController: MetaFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, draftTypeToDelete: DeleteAllDraftFyleJoinOfDraftOperation.DraftType) async
    func userWantsToReplyToMessage(_ metaFlowController: MetaFlowController, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws
    func userWantsToDownloadReceivedFyleMessageJoinWithStatus(_ metaFlowController: MetaFlowController, receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) async throws
    func userWantsToPauseDownloadReceivedFyleMessageJoinWithStatus(_ metaFlowController: MetaFlowController, receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) async throws
    func userWantsToPauseSentFyleMessageJoinWithStatusFromOtherOwnedDevice(_ metaFlowController: MetaFlowController, sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>) async throws
    func userWantsToDownloadSentFyleMessageJoinWithStatusFromOtherOwnedDevice(_ metaFlowController: MetaFlowController, sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>) async throws
    func userWantsToRemoveReplyToMessage(_ metaFlowController: MetaFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws
    func insertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty(_ metaFlowController: MetaFlowController, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, markAsRead: Bool) async throws
    func userWantsToUpdateDraftExpiration(_ metaFlowController: MetaFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, value: PersistedDiscussionSharedConfigurationValue?) async throws
    func userWantsToReadReceivedMessageThatRequiresUserAction(_ metaFlowController: MetaFlowController, ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageId: ReceivedMessageIdentifier) async throws
    func updatedSetOfCurrentlyDisplayedMessagesWithLimitedVisibility(_ metaFlowController: MetaFlowController, discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentIDs: Set<ObvManagedObjectPermanentID<PersistedMessage>>) async throws
    func messagesAreNotNewAnymore(_ metaFlowController: MetaFlowController, ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageIds: [MessageIdentifier]) async throws
    func userWantsToUpdateReaction(_ metaFlowController: MetaFlowController, ownedCryptoId: ObvCryptoId, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, newEmoji: String?) async throws
    func userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice(_ metaFlowController: MetaFlowController) async throws
    func userWantsToStopSharingLocationInDiscussion(_ metaFlowController: MetaFlowController, discussionIdentifier: ObvDiscussionIdentifier) async throws
    func userWantsToReplaceTrustedDetailsByPublishedDetails(_ metaFlowController: MetaFlowController, groupIdentifier: ObvGroupV2Identifier) async throws
    func userWantsToDeleteOwnedIdentityAndHasConfirmed(_ metaFlowController: MetaFlowController, ownedCryptoId: ObvCryptoId, globalOwnedIdentityDeletion: Bool) async throws
    
    func userWantsToShowMapToSendOrShareLocationContinuously(_ metaFlowController: MetaFlowController, presentingViewController: UIViewController, discussionIdentifier: ObvDiscussionIdentifier) async throws

}




@MainActor
final class MetaFlowController: UIViewController, OlvidURLHandler {
    
    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: MetaFlowController.self))
    private static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: MetaFlowController.self))
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: MetaFlowController.self))

    var observationTokens = [NSObjectProtocol]()
    
    required init?(coder aDecoder: NSCoder) { fatalError("die") }
    
    private let queueForSynchronizingFyleCreation = DispatchQueue(label: "queueForSynchronizingFyleCreation")
    
    private static let errorDomain = "MetaFlowController"
    private func makeError(message: String) -> Error { NSError(domain: MetaFlowController.errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    
    // Coordinators and Services
    
    private var mainFlowViewController: MainFlowViewController?
    private var onboardingFlowViewController: NewOnboardingFlowViewController?

    private weak var createPasscodeDelegate: CreatePasscodeDelegate?
    private weak var localAuthenticationDelegate: LocalAuthenticationDelegate?
    private weak var appBackupDelegate: AppBackupDelegate?
    private weak var storeKitDelegate: StoreKitDelegate?
    private weak var metaFlowControllerDelegate: MetaFlowControllerDelegate?

    /// To ensure a smooth transistion during a cold boot, we add the launcscreen's view as the first child view.
    /// Once the other child views are show, we hide this view to prevent glitches (e.g., when switch back and forth between the call and the main view).
    /// So we keep a reference to it to make this hiding easy.
    private var launchView: UIView?

    private let callBannerView = CallBannerView()
    private let viewOnTopOfCallBannerView = UIView()
    
    private var mainFlowViewControllerConstraintsWithoutCallBannerView = [NSLayoutConstraint]()
    private var mainFlowViewControllerConstraintsWithCallBannerView = [NSLayoutConstraint]()

    private var currentOwnedCryptoId: ObvCryptoId? = nil
    
    private var viewDidLoadWasCalled = false
    private var shouldShowCallBannerOnViewDidLoad = false

    private var viewDidAppearWasCalledAtLeastOnce = false
    private var completionHandlersToCallOnViewDidAppear = [() -> Void]()

    /// Used when presenting the navigation stack allowing to configure the backup seed of new backups
    private var router: ObvAppBackupSetupRouter?

    // Shall only be accessed on the main thread
    private var automaticallyNavigateToCreatedDisplayedContactGroup = false
    
    private let obvEngine: ObvEngine
    
    private lazy var avatarHelper = AvatarHelper(obvEngine: obvEngine)
    
    /// This is used during the onboarding flow, when the user wants to see the subscription to Olvid+
    private var continuationAndOwnedCryptoIdentity: (continuation: CheckedContinuation<ObvAppBackup.ObvDeviceDeactivationConsequence, any Error>, ownedCryptoIdentity: ObvOwnedCryptoIdentity)?
    
    private var continuationsForObtainingAvatar: CheckedContinuation<UIImage?, Never>?
    
    init(obvEngine: ObvEngine, createPasscodeDelegate: CreatePasscodeDelegate, localAuthenticationDelegate: LocalAuthenticationDelegate, appBackupDelegate: AppBackupDelegate, storeKitDelegate: StoreKitDelegate, metaFlowControllerDelegate: MetaFlowControllerDelegate, shouldShowCallBanner: Bool) {
        
        self.obvEngine = obvEngine
        self.createPasscodeDelegate = createPasscodeDelegate
        self.localAuthenticationDelegate = localAuthenticationDelegate
        self.appBackupDelegate = appBackupDelegate
        self.storeKitDelegate = storeKitDelegate
        self.metaFlowControllerDelegate = metaFlowControllerDelegate

        super.init(nibName: nil, bundle: nil)
        
        // If the RootViewController indicates that there is a call in progress, show the call banner.
        // This happens when the app was force quitted before receiving a CallKit incoming call. In that case,
        // if the user launches the app from the CallKit UI, this MetFlowController is not instantiated during launch
        // as the in-hous call view is shown instead. As a consequence, this MetaFlowController did not receive the
        // notification about the call. So we need to have the information about this call at init time.
        
        shouldShowCallBannerOnViewDidLoad = shouldShowCallBanner
                
        observeDidBecomeActiveNotifications()
        
        // Internal notifications
        
        observeUserTriedToAccessCameraButAccessIsDeniedNotifications()
        observeUserWantsToDeleteOwnedContactGroupNotifications()
        observeUserWantsToLeaveJoinedContactGroupNotifications()
        observeUserWantsToIntroduceContactToAnotherContactNotifications()
        observeOutgoingCallFailedBecauseUserDeniedRecordPermissionNotifications()
        observeVoiceMessageFailedBecauseUserDeniedRecordPermissionNotifications()
        observeRejectedIncomingCallBecauseUserDeniedRecordPermissionNotifications()
        observePastedStringIsNotValidOlvidURLNotifications()
        observeUserDidTapOnMissedMessageBubbleNotifications()
        observeUserWantsToNavigateToDeepLinkNotifications()
        observeRequestUserDeniedRecordPermissionAlertNotifications()
        observeInstalledOlvidAppIsOutdatedNotification()

        observationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeUserOwnedIdentityWasRevokedByKeycloak(queue: OperationQueue.main) { [weak self] ownedCryptoId in
                self?.processUserOwnedIdentityWasRevokedByKeycloak(ownedCryptoId: ownedCryptoId)
            },
        ])
        
        // Listening to ObvEngine Notification
        
        observationTokens.append(contentsOf: [
            ObvEngineNotificationNew.observeWellKnownDownloadedSuccess(within: NotificationCenter.default) { [weak self] _, appInfo in
                self?.processWellKnownAppInfo(appInfo)
            },
            ObvEngineNotificationNew.observeWellKnownUpdatedSuccess(within: NotificationCenter.default) { [weak self] _, appInfo in
                self?.processWellKnownAppInfo(appInfo)
            },
            ObvEngineNotificationNew.observeAnOwnedIdentityTransferProtocolFailed(within: NotificationCenter.default) { [weak self] ownedCryptoId, protocolInstanceUID, error in
                Task { [weak self] in await self?.processAnOwnedIdentityTransferProtocolFailed(ownedCryptoId: ownedCryptoId, protocolInstanceUID: protocolInstanceUID, error: error) }
            },
        ])
        
        // App notifications
        
        observationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeUserWantsToRestartChannelEstablishmentProtocol { [weak self] (contactCryptoId, ownedCryptoId) in
                self?.processUserWantsToRestartChannelEstablishmentProtocol(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
            },
            ObvMessengerInternalNotification.observeUserWantsToCreateNewGroupV1(queue: OperationQueue.main) { [weak self] (groupName, groupDescription, groupMembersCryptoIds, ownedCryptoId, photoURL) in
                self?.processUserWantsToCreateNewGroupV1(groupName: groupName, groupDescription: groupDescription, groupMembersCryptoIds: groupMembersCryptoIds, ownedCryptoId: ownedCryptoId, photoURL: photoURL)
            },
            ObvMessengerCoreDataNotification.observeDisplayedContactGroupWasJustCreated { [weak self] permanentID in
                Task { await self?.processDisplayedContactGroupWasJustCreated(permanentID: permanentID) }
            },
            ObvMessengerInternalNotification.observeUserWantsToAddOwnedProfile { [weak self] in
                Task { await self?.processUserWantsToAddOwnedProfileNotification() }
            },
            ObvMessengerInternalNotification.observeUserWantsToSwitchToOtherOwnedIdentity { [weak self] ownedCryptoId in
                Task { await self?.processUserWantsToSwitchToOtherOwnedIdentity(ownedCryptoId: ownedCryptoId) }
            },
            ObvMessengerInternalNotification.observeUserWantsToSwitchToOtherHiddenOwnedIdentity { [weak self] password in
                Task { await self?.processUserWantsToSwitchToOtherHiddenOwnedIdentity(password: password) }
            },
            ObvMessengerCoreDataNotification.observeOwnedIdentityHiddenStatusChanged { [weak self] _, isHidden in
                guard isHidden else { return }
                Task { await self?.askUserToChooseHiddenProfileClosePolicyIfItIsNotSetYet() }
            },
            ObvMessengerInternalNotification.observeCloseAnyOpenHiddenOwnedIdentity { [weak self] in
                Task { await self?.switchToNonHiddenOwnedIdentityIfCurrentIsHidden() }
            },
            ObvMessengerCoreDataNotification.observePersistedContactWasUpdated { [weak self] contactObjectID in
                Task { await self?.refreshViewContextsRegisteredObjectsOnUpdateOfPersistedObvContactIdentity(with: contactObjectID) }
            },
            ObvMessengerCoreDataNotification.observeFyleMessageJoinWithStatusWasInserted { [weak self] fyleMessageJoinObjectID in
                Task { await self?.refreshViewContextsRegisteredObjectsOnUpdateOfFyleMessageJoinWithStatus(with: fyleMessageJoinObjectID) }
            },
            ObvMessengerCoreDataNotification.observeFyleMessageJoinWithStatusWasUpdated { [weak self] fyleMessageJoinObjectID in
                Task { await self?.refreshViewContextsRegisteredObjectsOnUpdateOfFyleMessageJoinWithStatus(with: fyleMessageJoinObjectID) }
            },
        ])
        
        // VoIP notifications
        
        observationTokens.append(contentsOf: [
            VoIPNotification.observeNewCallToShow { [weak self] _ in
                Task { [weak self] in await self?.setupAndShowAppropriateCallBanner(shouldShowCallBanner: true, animate: true) }
            },
            VoIPNotification.observeNoMoreCallInProgress { [weak self] in
                Task(priority: .userInitiated) { [weak self] in
                    os_log("☎️🔚 Observed observeNoMoreCallInProgress notification", log: Self.log, type: .info)
                    await self?.setupAndShowAppropriateCallBanner(shouldShowCallBanner: false, animate: true)
                }
            }
        ])

        Task {
            // Observing database changes
            await PersistedObvOwnedIdentity.addObvObserver(self)
            await PersistedObvContactIdentity.addObvObserver(self)
            await PersistedContactGroup.addObvObserver(self)
            await PersistedGroupV2.addObserver(self)
            await PersistedDiscussionLocalConfiguration.addObvObserver(self)
            await PersistedDiscussionSharedConfiguration.addObvObserver(self)
            await PersistedDiscussion.addObvObserver(self)
        }

    }
    
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    
    private struct AppInfoKey {
        static let minimumAppVersion = "min_ios"
        static let latestAppVersion = "latest_ios"
    }
    
    private func processWellKnownAppInfo(_ appInfo: [String: AppInfo]) {
        switch appInfo[AppInfoKey.minimumAppVersion] {
        case .int(let version):
            ObvMessengerSettings.AppVersionAvailable.minimum = version
        default:
            assertionFailure()
        }
        switch appInfo[AppInfoKey.latestAppVersion] {
        case .int(let version):
            ObvMessengerSettings.AppVersionAvailable.latest = version
        default:
            assertionFailure()
        }
        os_log("Minimum recommended app build version from server: %{public}@", log: log, type: .info, String(describing: ObvMessengerSettings.AppVersionAvailable.minimum))
        os_log("Latest recommended app build version from server: %{public}@", log: log, type: .info, String(describing: ObvMessengerSettings.AppVersionAvailable.latest))
        os_log("Installed app build version: %{public}@", log: log, type: .info, ObvAppCoreConstants.bundleVersion)
    }
    
    
    private func processAnOwnedIdentityTransferProtocolFailed(ownedCryptoId: ObvCryptoId, protocolInstanceUID: UID, error: Error) async {
        if let onboardingFlowViewController {
            await onboardingFlowViewController.anOwnedIdentityTransferProtocolFailed(ownedCryptoId: ownedCryptoId, protocolInstanceUID: protocolInstanceUID, error: error)
        } else if let onboardingFlowViewController = presentedViewController as? NewOnboardingFlowViewController {
            await onboardingFlowViewController.anOwnedIdentityTransferProtocolFailed(ownedCryptoId: ownedCryptoId, protocolInstanceUID: protocolInstanceUID, error: error)
        } else {
            debugPrint("Could not find onboarding")
        }
    }


    private func observePastedStringIsNotValidOlvidURLNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observePastedStringIsNotValidOlvidURL(queue: OperationQueue.main) { [weak self] in
            self?.showAlertWhenPastedStringIsNotValidOlvidURL()
        })
    }
    
    private func observeOutgoingCallFailedBecauseUserDeniedRecordPermissionNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeOutgoingCallFailedBecauseUserDeniedRecordPermission { [weak self] in
            Task { [weak self] in await  self?.presentUserDeniedRecordPermissionAlert(message: Strings.AlertOutgoingCallFailedBecauseUserDeniedRecordPermission.message) }
        })
    }

    private func observeVoiceMessageFailedBecauseUserDeniedRecordPermissionNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeVoiceMessageFailedBecauseUserDeniedRecordPermission { [weak self] in
            Task { [weak self] in await self?.presentUserDeniedRecordPermissionAlert(message: Strings.AlertVoiceMessageFailedBecauseUserDeniedRecordPermission.message) }
        })
    }

    
    private func observeRejectedIncomingCallBecauseUserDeniedRecordPermissionNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeRejectedIncomingCallBecauseUserDeniedRecordPermission { [weak self] in
            Task { [weak self] in await self?.presentUserDeniedRecordPermissionAlert(message: Strings.AlertRejectedIncomingCallBecauseUserDeniedRecordPermission.message) }
        })
    }
    
    
    private func observeRequestUserDeniedRecordPermissionAlertNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeRequestUserDeniedRecordPermissionAlert { [weak self] in
            Task { [weak self] in await self?.presentUserDeniedRecordPermissionAlert(message: Strings.AlertRejectedIncomingCallBecauseUserDeniedRecordPermission.message) }
        })
    }
    
    
    private func observeUserDidTapOnMissedMessageBubbleNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeUserDidTapOnMissedMessageBubble(queue: OperationQueue.main) { [weak self] in
            let alert = UIAlertController(title: NSLocalizedString("DIALOG_MISSING_MESSAGES_TITLE", comment: ""),
                                          message: NSLocalizedString("DIALOG_MISSING_MESSAGES_MESSAGE", comment: ""),
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .cancel, handler: nil))
            self?.present(alert, animated: true)
        })
    }
    
    
    private func processUserOwnedIdentityWasRevokedByKeycloak(ownedCryptoId: ObvCryptoId) {
        assert(Thread.isMainThread)
        let alert = UIAlertController(title: NSLocalizedString("DIALOG_OWNED_IDENTITY_WAS_REVOKED_BY_KEYCLOAK_TITLE", comment: ""),
                                      message: NSLocalizedString("DIALOG_OWNED_IDENTITY_WAS_REVOKED_BY_KEYCLOAK_MESSAGE", comment: ""),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }
    
    
    private func observeInstalledOlvidAppIsOutdatedNotification() {
        observationTokens.append(ObvMessengerInternalNotification.observeInstalledOlvidAppIsOutdated(queue: OperationQueue.main) { [weak self] presentingViewController in
            let menu = UIAlertController(
                title: Strings.AppDialogOutdatedAppVersion.title,
                message: Strings.AppDialogOutdatedAppVersion.message,
                preferredStyle: UIDevice.current.actionSheetIfPhoneAndAlertOtherwise)
            let updateAction = UIAlertAction(title: Strings.AppDialogOutdatedAppVersion.positiveButtonTitle, style: .default) { _ in
                guard UIApplication.shared.canOpenURL(ObvMessengerConstants.shortLinkToOlvidAppIniTunes) else { assertionFailure(); return }
                UIApplication.shared.open(ObvMessengerConstants.shortLinkToOlvidAppIniTunes, options: [:], completionHandler: nil)
            }
            let laterAction = UIAlertAction(title: Strings.AppDialogOutdatedAppVersion.negativeButtonTitle, style: .cancel)
            menu.addAction(updateAction)
            menu.addAction(laterAction)
            guard let presentingViewController: UIViewController = presentingViewController ?? self else { return }
            presentingViewController.present(menu, animated: true)
        })
    }

    
    @MainActor
    private func presentUserDeniedRecordPermissionAlert(message: String) async {
        assert(Thread.isMainThread)
        guard AVAudioSession.sharedInstance().recordPermission != .granted else { return }
        let alert = UIAlertController(title: nil,
                                      message: message,
                                      preferredStyle: .alert)
        if ObvMessengerConstants.targetEnvironmentIsMacCatalyst {
            alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .default, handler: nil))
        } else {
            alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel, handler: nil))
            if let appSettings = URL(string: UIApplication.openSettingsURLString) {
                alert.addAction(UIAlertAction(title: Strings.goToSettingsButtonTitle, style: .default, handler: { (_) in
                    UIApplication.shared.open(appSettings, options: [:])
                }))
            }
        }
        if let presentedViewController = presentedViewController {
            presentedViewController.present(alert, animated: true)
        } else {
            present(alert, animated: true)
        }
    }

    
    private func observeUserWantsToNavigateToDeepLinkNotifications() {
        let log = self.log
        os_log("🥏🏁 We observe UserWantsToNavigateToDeepLink notifications", log: log, type: .info)
        observationTokens.append(ObvMessengerInternalNotification.observeUserWantsToNavigateToDeepLink { [weak self] (deepLink) in
            DispatchQueue.main.async {
                os_log("🥏🏁 We received a UserWantsToNavigateToDeepLink notification", log: log, type: .info)
                guard let _self = self else { return }
                let toExecuteAfterViewDidAppear = { [weak self] in
                    guard let _self = self else { return }
                    VoIPNotification.hideCallView.postOnDispatchQueue()
                    Task.detached(priority: .userInitiated) {
                        await _self.mainFlowViewController?.performCurrentDeepLinkInitialNavigation(deepLink: deepLink)
                    }
                }
                if _self.viewDidAppearWasCalledAtLeastOnce {
                    toExecuteAfterViewDidAppear()
                } else {
                    _self.completionHandlersToCallOnViewDidAppear.append(toExecuteAfterViewDidAppear)
                }
            }
        })
    }

}


// MARK: - Implementing MetaFlowDelegate

extension MetaFlowController {
            
    override func viewDidLoad() {
        super.viewDidLoad()
        viewDidLoadWasCalled = true
        
        // Since  ``MetaFlowController.setupAndShowAppropriateChildViewControllers(ownedCryptoIdGeneratedDuringOnboarding:completion:)`` is async,
        // we need to add an appropriate background view identical to the one shown in the ``InitializerViewController`` to prevent a quick transition
        // through a black screen.
        let launchScreenStoryBoard = UIStoryboard(name: "LaunchScreen", bundle: nil)
        guard let launchViewController = launchScreenStoryBoard.instantiateInitialViewController() else { assertionFailure(); return }
        self.launchView = launchViewController.view
        self.view.addSubview(launchViewController.view)
        launchViewController.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.pinAllSidesToSides(of: launchViewController.view)

        self.view.addSubview(callBannerView)
        callBannerView.translatesAutoresizingMaskIntoConstraints = false
        callBannerView.isHidden = true
        
        self.view.addSubview(viewOnTopOfCallBannerView)
        viewOnTopOfCallBannerView.translatesAutoresizingMaskIntoConstraints = false
        viewOnTopOfCallBannerView.backgroundColor = AppTheme.shared.colorScheme.systemBackground
        viewOnTopOfCallBannerView.isHidden = true
        
        Task {
            do {
                try await setupAndShowAppropriateChildViewControllers(ownedCryptoIdGeneratedDuringOnboarding: nil)
            } catch {
                os_log("Could not determine which child view controller to show", log: log, type: .fault)
                assertionFailure()
                return
            }
            
            // See the comment in the initializer
            if shouldShowCallBannerOnViewDidLoad {
                await setupAndShowAppropriateCallBanner(shouldShowCallBanner: true, animate: false)
            }
        }
        
    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !viewDidAppearWasCalledAtLeastOnce {
            ObvMessengerInternalNotification.metaFlowControllerViewDidAppear
                .postOnDispatchQueue()
        } else {
            // The notification is sent from the observeDidBecomeActiveNotifications()method
        }
        
        viewDidAppearWasCalledAtLeastOnce = true
        
        while let completion = completionHandlersToCallOnViewDidAppear.popLast() {
            completion()
        }
        
    }
    
    
    // We send the metaFlowControllerViewDidAppear notification when the application becomes active, but only of viewDidAppearWasCalled is true.
    //
    // When the app is launched after a cold boot, the metaFlowControllerViewDidAppear notification is not called here, but in the viewDidAppear method.
    // When the app is re-launched from the background, the viewDidAppear is not called, and the metaFlowControllerViewDidAppear notification is sent anyway, thanks to this method.
    private func observeDidBecomeActiveNotifications() {
        observationTokens.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
            Task { [weak self] in await self?.processDidBecomeActiveNotification() }
        })
    }
    
    
    @MainActor
    private func processDidBecomeActiveNotification() {
        guard self.viewDidAppearWasCalledAtLeastOnce == true else { return }
        ObvMessengerInternalNotification.metaFlowControllerViewDidAppear
            .postOnDispatchQueue()
    }
    
    
    /// Called by the SceneDelegate
    @MainActor
    func sceneDidBecomeActive(_ scene: UIScene) {
        assert(viewDidAppearWasCalledAtLeastOnce)
        mainFlowViewController?.sceneDidBecomeActive(scene)
    }
    
    
    /// Called by the SceneDelegate
    @MainActor
    func sceneWillResignActive(_ scene: UIScene) {
        assert(viewDidAppearWasCalledAtLeastOnce)
        mainFlowViewController?.sceneWillResignActive(scene)
    }
    

    @MainActor
    private func setupAndShowAppropriateCallBanner(shouldShowCallBanner: Bool, animate: Bool) async {
        assert(Thread.isMainThread)
        guard viewDidLoadWasCalled else { return }
        
        if shouldShowCallBanner {
            
            setupMainFlowViewControllerConstraintsWithCallBannerViewIfNecessary()
            NSLayoutConstraint.deactivate(mainFlowViewControllerConstraintsWithoutCallBannerView)
            NSLayoutConstraint.activate(mainFlowViewControllerConstraintsWithCallBannerView)
            callBannerView.isHidden = false
            
        } else {

            setupMainFlowViewControllerConstraintsWithoutCallBannerViewIfNecessary()
            NSLayoutConstraint.deactivate(mainFlowViewControllerConstraintsWithCallBannerView)
            NSLayoutConstraint.activate(mainFlowViewControllerConstraintsWithoutCallBannerView)
            callBannerView.isHidden = true

        }
        
        view.setNeedsUpdateConstraints()
        if animate {
            UIView.animate(withDuration: 0.3) { [weak self] in
                self?.view.layoutIfNeeded()
            }
        }

    }
    
    /// When deleting the last owned identity, we want to restart all over: show the onboarding screen and remove the main flow from the hierarchy
    private func destroyCurrentMainFlowViewController() {
        if let mainFlowViewController {
            mainFlowViewController.view.removeFromSuperview()
            mainFlowViewController.willMove(toParent: nil)
            mainFlowViewController.removeFromParent()
            mainFlowViewController.didMove(toParent: nil)
        }
        mainFlowViewController = nil
        mainFlowViewControllerConstraintsWithoutCallBannerView.removeAll()
        mainFlowViewControllerConstraintsWithCallBannerView.removeAll()
    }

    
    private func destroyCurrentOnboardingFlowViewController() {
        if let onboardingFlowViewController {
            onboardingFlowViewController.view.removeFromSuperview()
            onboardingFlowViewController.willMove(toParent: nil)
            onboardingFlowViewController.removeFromParent()
            onboardingFlowViewController.didMove(toParent: nil)
        }
        onboardingFlowViewController  = nil
    }
    
    
    /// Asks the user to choose a hidding policy if it is not set yet.
    ///
    /// This is typically called each time an owned identity becomes hidden.
    @MainActor
    func askUserToChooseHiddenProfileClosePolicyIfItIsNotSetYet() async {
        let traitCollection = self.traitCollection
        guard ObvMessengerSettings.Privacy.hiddenProfileClosePolicyHasYetToBeSet else { return }
        let alert = UIAlertController(title: Strings.AlertChooseHiddenProfileClosePolicy.title,
                                      message: Strings.AlertChooseHiddenProfileClosePolicy.message,
                                      preferredStyleForTraitCollection: traitCollection)
        alert.addAction(.init(title: Strings.AlertChooseHiddenProfileClosePolicy.actionManualSwitching, style: .default) { _ in
            ObvMessengerSettings.Privacy.hiddenProfileClosePolicy = .manualSwitching
        })
        alert.addAction(.init(title: Strings.AlertChooseHiddenProfileClosePolicy.actionScreenLock, style: .default) { [weak self] _ in
            ObvMessengerSettings.Privacy.hiddenProfileClosePolicy = .screenLock
            Task { await self?.askUserToActivateScreenLockIfNoneExists() }
        })
        alert.addAction(.init(title: Strings.AlertChooseHiddenProfileClosePolicy.actionBackground, style: .default) { [weak self] _ in
            ObvMessengerSettings.Privacy.hiddenProfileClosePolicy = .background
            // Show another alert allowing to choose the time interval allowed in background
            let alert = UIAlertController(title: Strings.AlertTimeIntervalForBackgroundHiddenProfileClosePolicy.title,
                                          message: nil,
                                          preferredStyleForTraitCollection: traitCollection)
            for timeInterval in ObvMessengerSettings.Privacy.TimeIntervalForBackgroundHiddenProfileClosePolicy.allCases {
                alert.addAction(.init(title: Strings.AlertTimeIntervalForBackgroundHiddenProfileClosePolicy.actionTitle(for: timeInterval), style: .default) { _ in
                    ObvMessengerSettings.Privacy.timeIntervalForBackgroundHiddenProfileClosePolicy = timeInterval
                })
            }
            if let presentedViewController = self?.presentedViewController {
                presentedViewController.present(alert, animated: true)
            } else {
                self?.present(alert, animated: true)
            }
        })
        if let presentedViewController {
            presentedViewController.present(alert, animated: true)
        } else {
            present(alert, animated: true)
        }
    }
    
    
    /// When a user creates a hidden profile with a `.screenLock` close policy, we make sure she actually has a screen lock activated.
    /// If not, we recommend to activate a screen lock and provide a way to navigate to the appropriate settings screen.
    @MainActor func askUserToActivateScreenLockIfNoneExists() async {
        guard ObvMessengerSettings.Privacy.localAuthenticationPolicy == .none else { return }
        // The user has no screen lock (i.e., no local authentication policy), we recommend to activate one now.
        let alert = UIAlertController(title: Strings.AlertShouldActivateScreenLockAfterCreatingHiddenProfile.title,
                                      message: Strings.AlertShouldActivateScreenLockAfterCreatingHiddenProfile.message,
                                      preferredStyleForTraitCollection: traitCollection)
        alert.addAction(.init(title: Strings.AlertShouldActivateScreenLockAfterCreatingHiddenProfile.actionGotToPrivacySettings, style: .default) { _ in
            let deepLink = ObvDeepLink.privacySettings
            ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                .postOnDispatchQueue()
        })
        alert.addAction(.init(title: CommonString.Word.Later, style: .cancel))
        if let presentedViewController = presentedViewController {
            presentedViewController.present(alert, animated: true)
        } else {
            present(alert, animated: true)
        }
    }

    
    @MainActor
    private func setupAndShowAppropriateChildViewControllers(ownedCryptoIdGeneratedDuringOnboarding: ObvCryptoId?, completion: (@MainActor (Result<Void,Error>) -> Void)? = nil) async throws {
        
        assert(viewDidLoadWasCalled)
        assert(Thread.isMainThread)
        
        let internalCompletion = { (result: Result<Void,Error>) -> Void in
            Task { [weak self] in
                assert(Thread.isMainThread)
                guard let _self = self else { return }
                if await NewAppStateManager.shared.olvidURLHandler == nil {
                    await NewAppStateManager.shared.setOlvidURLHandler(to: _self)
                }
                completion?(result)
            }
        }
        
        // Determine the most appropriate owned identity to show

        let appropriateOwnedCryptoIdToShow: ObvCryptoId?
        if let ownedCryptoIdGeneratedDuringOnboarding {
            appropriateOwnedCryptoIdToShow = ownedCryptoIdGeneratedDuringOnboarding
        } else {
            appropriateOwnedCryptoIdToShow = await getMostAppropriateOwnedCryptoIdToShow()
        }
        
        if let ownedCryptoId = appropriateOwnedCryptoIdToShow {
                        
            if mainFlowViewController == nil {
                guard let createPasscodeDelegate, let appBackupDelegate, let localAuthenticationDelegate, let storeKitDelegate else {
                    assertionFailure(); return
                }
                mainFlowViewController = MainFlowViewController(
                    ownedCryptoId: ownedCryptoId,
                    obvEngine: obvEngine,
                    createPasscodeDelegate: createPasscodeDelegate,
                    localAuthenticationDelegate: localAuthenticationDelegate,
                    appBackupDelegate: appBackupDelegate,
                    mainFlowViewControllerDelegate: self,
                    storeKitDelegate: storeKitDelegate)
            }

            guard let mainFlowViewController else {
                assertionFailure()
                internalCompletion(.failure(makeError(message: "No main flow view controller")))
                return
            }
                        
            if let currentFirstChild = children.first {
                            
                guard currentFirstChild != mainFlowViewController else {
                    presentedViewController?.dismiss(animated: true)
                    await processUserWantsToSwitchToOtherOwnedIdentity(ownedCryptoId: ownedCryptoId)
                    return
                }
                
                // The current first child view controller is not the mainFlowViewController.
                // We will transition to it.
                
                if currentFirstChild == onboardingFlowViewController {
                    mainFlowViewController.anOwnedIdentityWasJustCreatedOrRestored = true
                }
                
                if mainFlowViewController.parent == nil {
                    mainFlowViewController.willMove(toParent: self)
                    addChild(mainFlowViewController)
                    mainFlowViewController.didMove(toParent: self)
                }
                                
                transition(from: currentFirstChild, to: mainFlowViewController, duration: 0.9, options: [.transitionFlipFromLeft]) { [weak self] in
                    // Animation block
                    guard let _self = self else { return }
                    _self.setupMainFlowViewControllerConstraintsWithoutCallBannerViewIfNecessary()
                    NSLayoutConstraint.activate(_self.mainFlowViewControllerConstraintsWithoutCallBannerView)
                    _self.callBannerView.isHidden = true
                } completion: { [weak self] _ in
                    currentFirstChild.view.removeFromSuperview()
                    currentFirstChild.removeFromParent() // Automatic call to didMove(...) ?
                    mainFlowViewController.didMove(toParent: self)
                    internalCompletion(.success(()))
                    self?.destroyCurrentOnboardingFlowViewController()
                    Task {
                        await self?.switchToOwnedIdentity(ownedCryptoId: ownedCryptoId)
                    }
                }
                         
            } else {
                
                // This view controller has no child view controller.
                // We set this first child to the mainFlowViewController
                
                addChild(mainFlowViewController) // automatically calls willMove(toParent: self)
                mainFlowViewController.didMove(toParent: self)
                
                view.addSubview(mainFlowViewController.view)
                mainFlowViewController.view.translatesAutoresizingMaskIntoConstraints = false
                setupMainFlowViewControllerConstraintsWithoutCallBannerViewIfNecessary()
                NSLayoutConstraint.activate(mainFlowViewControllerConstraintsWithoutCallBannerView)
                callBannerView.isHidden = true
                launchView?.removeFromSuperview()
                launchView = nil
                
                internalCompletion(.success(()))

                await switchToOwnedIdentity(ownedCryptoId: ownedCryptoId)

            }
            
        } else {
            
            destroyCurrentMainFlowViewController()
            self.currentOwnedCryptoId = nil

            if let onboardingFlowViewController {
                if onboardingFlowViewController.parent != nil {
                    // Nothing left to do
                    return
                } else {
                    assertionFailure()
                }
            } else {
                //onboardingFlowViewController = OnboardingFlowViewController(obvEngine: obvEngine, appBackupDelegate: appBackupDelegate)
                let mdmConfig = getMDMConfigurationForOnboarding()
                onboardingFlowViewController = NewOnboardingFlowViewController(
                    logSubsystem: ObvAppCoreConstants.logSubsystem,
                    directoryForTempFiles: ObvUICoreDataConstants.ContainerURL.forTempFiles.url,
                    mode: .initialOnboarding(mdmConfig: mdmConfig),
                    dataSource: self)
                onboardingFlowViewController?.delegate = self
            }
            
            guard let onboardingFlowViewController else {
                assertionFailure()
                internalCompletion(.failure(makeError(message: "No onboarding flow view controller")))
                return
            }
            
            if let currentFirstChild = children.first {
                
                if currentFirstChild != onboardingFlowViewController {
                    // Happens when deleting the last owned identity
                    currentFirstChild.view.removeFromSuperview()
                    currentFirstChild.willMove(toParent: nil)
                    currentFirstChild.removeFromParent()
                    currentFirstChild.didMove(toParent: nil)
                } else {
                    internalCompletion(.success(()))
                    return
                }
                
            }
                
            // This view controller has no child view controller.
            // We set this first child to the onboardingFlowViewController
            
            addChild(onboardingFlowViewController)
            onboardingFlowViewController.didMove(toParent: self)
            
            view.addSubview(onboardingFlowViewController.view)
            onboardingFlowViewController.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                onboardingFlowViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
                onboardingFlowViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                onboardingFlowViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                onboardingFlowViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ])
            
            internalCompletion(.success(()))
                
        }

    }
    
    
    /// Helper method called to configure the very first onboarding
    private func getMDMConfigurationForOnboarding() -> Onboarding.MDMConfiguration? {
        
        if ObvMessengerSettings.MDM.isConfiguredFromMDM,
           let mdmConfigurationURI = ObvMessengerSettings.MDM.Configuration.uri,
           let olvidURL = OlvidURL(urlRepresentation: mdmConfigurationURI) {
            
            switch olvidURL.category {
            case .configuration(_, _, let keycloakConfig):
                guard let keycloakConfig else { return nil }
                return .init(keycloakConfiguration: keycloakConfig)
            default:
                assertionFailure()
                return nil
            }
        }
        
        return nil
        
    }
    
    
    /// Returns the most appropriate owned identity to show. Returns `nil` if no owned identity exists.
    @MainActor private func getMostAppropriateOwnedCryptoIdToShow() async -> ObvCryptoId? {
        guard let latestCurrentOWnedIdentityStored = await LatestCurrentOwnedIdentityStorage.shared.getLatestCurrentOwnedIdentityStored() else {
            // Return a random non hidden owned identity if one can be found
            return await getRandomExistingNonHiddenOwnedCryptoId()
        }
        guard let hiddenCryptoId = latestCurrentOWnedIdentityStored.hiddenCryptoId else {
            let nonHiddenCryptoId = latestCurrentOWnedIdentityStored.nonHiddenCryptoId
            // Make sure the identity still exists, otherwise, return a random non hidden owned identity
            guard (try? PersistedObvOwnedIdentity.get(cryptoId: nonHiddenCryptoId, within: ObvStack.shared.viewContext)) != nil else {
                return await getRandomExistingNonHiddenOwnedCryptoId()
            }
            return nonHiddenCryptoId
        }
        // If we reach this point, we are in the complex situation where the latest current identity was a hidden one. We must determine if it is appropriate to show it.
        guard (try? PersistedObvOwnedIdentity.get(cryptoId: hiddenCryptoId, within: ObvStack.shared.viewContext)) != nil else {
            return await getRandomExistingNonHiddenOwnedCryptoId()
        }
        switch ObvMessengerSettings.Privacy.hiddenProfileClosePolicy {
        case .manualSwitching:
            return hiddenCryptoId
        case .screenLock, .background:
            assertionFailure("The hidden cryptoId should have been cleared by now")
            return latestCurrentOWnedIdentityStored.nonHiddenCryptoId
        }
    }
    
    
    @MainActor private func getRandomExistingNonHiddenOwnedCryptoId() async -> ObvCryptoId? {
        guard let ownedIdentities = try? PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentities(within: ObvStack.shared.viewContext) else { assertionFailure(); return nil }
        return ownedIdentities.first?.cryptoId
    }
    
    
    @MainActor
    private func setupMainFlowViewControllerConstraintsWithoutCallBannerViewIfNecessary() {
        guard let mainFlowViewController = self.mainFlowViewController else { return }
        guard mainFlowViewControllerConstraintsWithoutCallBannerView.isEmpty else { return }
        mainFlowViewControllerConstraintsWithoutCallBannerView = [
            mainFlowViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            mainFlowViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainFlowViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mainFlowViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        ]
    }
    
    
    private func setupMainFlowViewControllerConstraintsWithCallBannerViewIfNecessary() {
        assert(Thread.isMainThread)
        guard let mainFlowViewController = self.mainFlowViewController else { assertionFailure(); return }
        guard mainFlowViewControllerConstraintsWithCallBannerView.isEmpty else { return }
        mainFlowViewControllerConstraintsWithCallBannerView = [
            viewOnTopOfCallBannerView.topAnchor.constraint(equalTo: view.topAnchor),
            viewOnTopOfCallBannerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            viewOnTopOfCallBannerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            viewOnTopOfCallBannerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            callBannerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            callBannerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            callBannerView.bottomAnchor.constraint(equalTo: mainFlowViewController.view.topAnchor),
            callBannerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainFlowViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainFlowViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mainFlowViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        ]
    }
    
}


// MARK: - NewOnboardingFlowViewControllerDelegate

extension MetaFlowController: NewOnboardingFlowViewControllerDelegate {
    
    func userWantsToBeRemindedToWriteDownBackupKey(_ onboardingFlow: ObvOnboarding.NewOnboardingFlowViewController) async {
        await userWantsToBeRemindedToWriteDownBackupKey()
    }
    
    
    func shouldSetupNewBackupsDuringOnboarding(_ onboardingFlow: NewOnboardingFlowViewController) async -> Bool {
        if ObvMessengerSettings.Backup.userDidSetupBackupsAtLeastOnce {
            return false
        } else if await userHasAnActiveDeviceBackupSeed() {
            return false
        } else {
            return true
        }
    }
    
    func userWantsToDeactivateBackups(_ onboardingFlow: ObvOnboarding.NewOnboardingFlowViewController) async throws {
        try await userWantsToDeactivateBackups()
    }
    
    
    /// This method is called from the onboarding during the profile backup restore process. At the end of this process, just before actually restoring the profile,
    /// the user may be in a situation where restoring will deactivate all their older devices. The user then has the option to subscribe to Olvid+ to keep all their devices active by tapping on a button that eventually calls this method.
    /// In this case, we want to present the subscription flow and recalculate the value of `ObvDeviceDeactivationConsiquence` when it is dismissed.
    func userWantsToKeepAllDevicesActiveThanksToOlvidPlus(_ onboardingFlow: ObvOnboarding.NewOnboardingFlowViewController, ownedCryptoIdentity: ObvOwnedCryptoIdentity) async throws -> ObvAppBackup.ObvDeviceDeactivationConsequence {
        return try await self.userWantsToKeepAllDevicesActiveThanksToOlvidPlus(ownedCryptoIdentity: ownedCryptoIdentity)
    }
    
    
    /// This is called just before restoring a profile backup from the onboarding, in order to determine the consequence of this restoration in terms of devices deactivations.
    func getDeviceDeactivationConsequencesOfRestoringBackup(_ onboardingFlow: NewOnboardingFlowViewController, ownedCryptoIdentity: ObvOwnedCryptoIdentity) async throws -> ObvDeviceDeactivationConsequence {
        return try await self.getDeviceDeactivationConsequencesOfRestoringBackup(ownedCryptoIdentity: ownedCryptoIdentity)
    }
    
        
    func getOrCreateDeviceBackupSeed(_ onboardingFlow: ObvOnboarding.NewOnboardingFlowViewController, saveToKeychain: Bool) async throws -> ObvCrypto.BackupSeed {
        return try await self.getOrCreateDeviceBackupSeed(saveToKeychain: saveToKeychain)
    }
    
    
    private func userHasAnActiveDeviceBackupSeed() async -> Bool {
        do {
            return try await obvEngine.getDeviceActiveBackupSeed() != nil
        } catch {
            assertionFailure()
            return true
        }
    }
    
    
    func fetchAvatarImage(_ onboardingFlow: ObvOnboarding.NewOnboardingFlowViewController, profileCryptoId: ObvTypes.ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        do {
            return try await self.avatarHelper.fetchAvatarImage(ownedCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, size: frameSize)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                return nil
            } else {
                assertionFailure()
                return nil
            }
        }
    }
    
    
    func userWantsToUseDeviceBackupSeed(_ onboardingFlow: NewOnboardingFlowViewController, deviceBackupSeed: BackupSeed) async throws -> ObvListOfDeviceBackupProfiles {
        return try await userWantsToUseDeviceBackupSeed(deviceBackupSeed: deviceBackupSeed)
    }

    
    func restoreProfileBackupFromServerNow(_ onboardingFlow: NewOnboardingFlowViewController, profileBackupFromServerToRestore: ObvProfileBackupFromServer, rawAuthState: Data?) async throws -> ObvRestoredOwnedIdentityInfos {
        return try await restoreProfileBackupFromServerNow(profileBackupFromServerToRestore: profileBackupFromServerToRestore,
                                                           rawAuthState: rawAuthState)
    }
    

    func userWantsToFetchAllProfileBackupsFromServer(_ onboardingFlow: NewOnboardingFlowViewController, profileCryptoId: ObvCryptoId, profileBackupSeed: BackupSeed) async throws -> [ObvProfileBackupFromServer] {
        return try await userWantsToFetchAllProfileBackupsFromServer(profileCryptoId: profileCryptoId, profileBackupSeed: profileBackupSeed)
    }
    
    
    func userWantsToFetchDeviceBakupFromServer(onboardingFlow: ObvOnboarding.NewOnboardingFlowViewController) async throws -> AsyncStream<ObvAppBackup.ObvDeviceBackupFromServerWithAppInfoKind> {
        return try await self.userWantsToFetchDeviceBakupFromServer(currentOwnedCryptoId: nil)
    }
    
    
    @MainActor
    func userPastedStringWhichIsNotValidOlvidURL(onboardingFlow: NewOnboardingFlowViewController) async {
        showAlertWhenPastedStringIsNotValidOlvidURL()
    }
    
    func handleOlvidURL(onboardingFlow: NewOnboardingFlowViewController, olvidURL: OlvidURL) async {
        await self.handleOlvidURL(olvidURL)
    }

    func onboardingRequiresKeycloakToSyncAllManagedIdentities() async {
        do {
            try await KeycloakManagerSingleton.shared.syncAllManagedIdentities()
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }
    
    
    @MainActor
    func userWantsToDismissOnboardingAfterSuccessfulOwnedIdentityTransferOnThisTargetDevice(onboardingFlow: NewOnboardingFlowViewController, transferredOwnedCryptoId: ObvCryptoId, userWantsToAddAnotherProfile: Bool) async {
        if mainFlowViewController != nil {
            await switchToOwnedIdentity(ownedCryptoId: transferredOwnedCryptoId)
            onboardingFlow.dismiss(animated: true)
        } else {
            do {
                try await setupAndShowAppropriateChildViewControllers(ownedCryptoIdGeneratedDuringOnboarding: transferredOwnedCryptoId) { result in
                    switch result {
                    case .success:
                        onboardingFlow.dismiss(animated: true) {
                            if userWantsToAddAnotherProfile {
                                ObvMessengerInternalNotification.userWantsToAddOwnedProfile
                                    .postOnDispatchQueue()
                            }
                        }
                    case .failure:
                        assertionFailure()
                    }
                }
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }

    
    func onboardingRequiresToPerformOwnedDeviceDiscoveryNow(for ownedCryptoId: ObvCryptoId) async throws -> (ownedDeviceDiscoveryResult: ObvOwnedDeviceDiscoveryResult, currentDeviceIdentifier: Data) {
        let ownedDeviceDiscoveryResult = try await obvEngine.performOwnedDeviceDiscoveryNow(ownedCryptoId: ownedCryptoId)
        let currentDeviceIdentifier = try await obvEngine.getCurrentDeviceIdentifier(ownedCryptoId: ownedCryptoId)
        return (ownedDeviceDiscoveryResult, currentDeviceIdentifier)
    }
    
    
    
    
    func onboardingIsShowingSasAndExpectingEndOfProtocol(onboardingFlow: NewOnboardingFlowViewController, protocolInstanceUID: UID, onSyncSnapshotReception: @escaping () -> Void, onSuccessfulTransfer: @escaping (ObvCryptoId, Error?) -> Void, onKeycloakAuthenticationNeeded: @escaping (ObvCryptoId, ObvKeycloakConfiguration, ObvKeycloakTransferProofElements) -> Void) async {
        await obvEngine.appIsShowingSasAndExpectingEndOfProtocol(
            protocolInstanceUID: protocolInstanceUID,
            onSyncSnapshotReception: onSyncSnapshotReception,
            onSuccessfulTransfer: onSuccessfulTransfer,
            onKeycloakAuthenticationNeeded: onKeycloakAuthenticationNeeded)
    }
    
    
    func onboardingRequiresToInitiateOwnedIdentityTransferProtocolOnTargetDevice(onboardingFlow: NewOnboardingFlowViewController, transferSessionNumber: ObvOwnedIdentityTransferSessionNumber, currentDeviceName: String, onIncorrectTransferSessionNumber: @escaping () -> Void, onAvailableSas: @escaping (UID, ObvOwnedIdentityTransferSas) -> Void) async throws {
        try await obvEngine.initiateOwnedIdentityTransferProtocolOnTargetDevice(
            currentDeviceName: currentDeviceName,
            transferSessionNumber: transferSessionNumber,
            onIncorrectTransferSessionNumber: onIncorrectTransferSessionNumber,
            onAvailableSas: onAvailableSas)
    }
    
    
    func onboardingRequiresToInitiateOwnedIdentityTransferProtocolOnSourceDevice(onboardingFlow: NewOnboardingFlowViewController, ownedCryptoId: ObvCryptoId, onAvailableSessionNumber: @MainActor @escaping (ObvOwnedIdentityTransferSessionNumber) -> Void, onAvailableSASExpectedOnInput: @MainActor @escaping (ObvOwnedIdentityTransferSas, String, UID) -> Void) async throws {
        try await obvEngine.initiateOwnedIdentityTransferProtocolOnSourceDevice(
            ownedCryptoId: ownedCryptoId,
            onAvailableSessionNumber: onAvailableSessionNumber,
            onAvailableSASExpectedOnInput: onAvailableSASExpectedOnInput)
    }
    
    
    func userWishesToFinalizeOwnedIdentityTransferFromSourceDevice(onboardingFlow: NewOnboardingFlowViewController, enteredSAS: ObvOwnedIdentityTransferSas, isTransferRestricted: Bool, deviceToKeepActive: UID?, ownedCryptoId: ObvCryptoId, protocolInstanceUID: UID) async throws {
        try await obvEngine.userEnteredValidSASOnSourceDeviceForOwnedIdentityTransferProtocol(
            enteredSAS: enteredSAS,
            isTransferRestricted: isTransferRestricted,
            deviceToKeepActive: deviceToKeepActive,
            ownedCryptoId: ownedCryptoId,
            protocolInstanceUID: protocolInstanceUID,
            snapshotSentToTargetDevice: {
                // Callback called when the snapshot was successfully sent to the target device
                // and thus, the protocol is finished on this source device. We can end the flow
                DispatchQueue.main.async { onboardingFlow.dismiss(animated: true) }
            })
    }
    
    
    func userWantsToCloseOnboardingAndCancelAnyOwnedTransferProtocol(onboardingFlow: NewOnboardingFlowViewController) async {
        do {
            try await obvEngine.userWantsToCancelAllOwnedIdentityTransferProtocols()
        } catch {
            assertionFailure()
        }
        
        onboardingFlow.dismiss(animated: true)

    }


    func onboardingRequiresToRegisterAndUploadOwnedIdentityToKeycloakServer(ownedCryptoId: ObvCryptoId) async throws {
        try await KeycloakManagerSingleton.shared.uploadOwnIdentity(ownedCryptoId: ownedCryptoId, keycloakUserIdAndState: nil)
    }

    
    func onboardingRequiresKeycloakAuthentication(onboardingFlow: NewOnboardingFlowViewController, keycloakConfiguration: ObvKeycloakConfiguration, keycloakServerKeyAndConfig: (jwks: ObvJWKSet, serviceConfig: OIDServiceConfiguration)) async throws -> (keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff, keycloakState: ObvKeycloakState) {
        let authState = try await KeycloakManagerSingleton.shared.authenticate(configuration: keycloakServerKeyAndConfig.serviceConfig,
                                                                               clientId: keycloakConfiguration.clientId,
                                                                               clientSecret: keycloakConfiguration.clientSecret,
                                                                               ownedCryptoId: nil)
        return try await getOwnedDetailsAfterSucessfullAuthentication(keycloakConfiguration: keycloakConfiguration,
                                                                      keycloakServerKeyAndConfig: keycloakServerKeyAndConfig,
                                                                      authState: authState)
    }
    
    
    @MainActor
    private func getOwnedDetailsAfterSucessfullAuthentication(keycloakConfiguration: ObvKeycloakConfiguration, keycloakServerKeyAndConfig: (jwks: ObvJWKSet, serviceConfig: OIDServiceConfiguration), authState: OIDAuthState) async throws -> (keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff, keycloakState: ObvKeycloakState) {
        
        let (keycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff) = try await KeycloakManagerSingleton.shared.getOwnDetails(
            keycloakServer: keycloakConfiguration.keycloakServerURL,
            authState: authState,
            clientSecret: keycloakConfiguration.clientSecret,
            jwks: keycloakServerKeyAndConfig.jwks,
            latestLocalRevocationListTimestamp: nil)
        
        if let minimumBuildVersion = keycloakServerRevocationsAndStuff.minimumIOSBuildVersion {
            guard ObvAppCoreConstants.bundleVersionAsInt >= minimumBuildVersion else {
                throw ObvError.installedOlvidAppIsOutdated
            }
        }

        let rawAuthState = try authState.serialize()
        
        let keycloakState = ObvKeycloakState(
            keycloakServer: keycloakConfiguration.keycloakServerURL,
            clientId: keycloakConfiguration.clientId,
            clientSecret: keycloakConfiguration.clientSecret,
            jwks: keycloakServerKeyAndConfig.jwks,
            rawAuthState: rawAuthState,
            signatureVerificationKey: keycloakUserDetailsAndStuff.serverSignatureVerificationKey,
            latestLocalRevocationListTimestamp: nil,
            latestGroupUpdateTimestamp: nil,
            isTransferRestricted: keycloakUserDetailsAndStuff.isTransferRestricted)
        
        return (keycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff, keycloakState)
        
    }

    
    func onboardingRequiresToDiscoverKeycloakServer(onboardingFlow: NewOnboardingFlowViewController, keycloakServerURL: URL) async throws -> (jwks: ObvJWKSet, serviceConfig: OIDServiceConfiguration) {
        return try await KeycloakManagerSingleton.shared.discoverKeycloakServer(for: keycloakServerURL)
    }
    

    func userWantsToEnableAutomaticBackup(onboardingFlow: NewOnboardingFlowViewController) async throws {

        guard !ObvMessengerSettings.Backup.isAutomaticBackupEnabled else { return }

        guard let appBackupDelegate else {
            throw ObvError.theAppBackupDelegateIsNotSet
        }
        
        // The user wants to activate automatic backup.
        // We must check whether it's possible.
        let defaultTitleAndMessageOnError = (title: "AUTOMATIC_BACKUP_COULD_NOT_BE_ENABLED_TITLE", message: "PLEASE_TRY_AGAIN_LATER")
        do {
            let accountStatus = try await appBackupDelegate.getAccountStatus()
            if case .available = accountStatus {
                obvEngine.userJustActivatedAutomaticBackup()
                ObvMessengerSettings.Backup.isAutomaticBackupEnabled = true
                return
            } else {
                let titleAndMessage = AppBackupManager.CKAccountStatusMessage(accountStatus) ?? AppBackupManager.CKAccountStatusMessage(.couldNotDetermine) ?? defaultTitleAndMessageOnError
                throw ObvError.ckAccountStatusError(title: titleAndMessage.title, message: titleAndMessage.message)
            }
        } catch {
            let titleAndMessage = AppBackupManager.CKAccountStatusMessage(.noAccount) ?? defaultTitleAndMessageOnError
            throw ObvError.ckAccountStatusError(title: titleAndMessage.title, message: titleAndMessage.message)
        }
        
    }
    
    
    @MainActor
    func onboardingRequiresToRestoreBackup(onboardingFlow: NewOnboardingFlowViewController, backupRequestIdentifier: UUID) async throws -> ObvCryptoId {
        let ownedDeviceName = UIDevice.current.preciseModel
        let cryptoIdsOfRestoredOwnedIdentities = try await obvEngine.restoreFullLegacyBackup(backupRequestIdentifier: backupRequestIdentifier, nameToGiveToCurrentDevice: ownedDeviceName)
        guard let randomCryptoId = cryptoIdsOfRestoredOwnedIdentities.first else {
            assertionFailure()
            throw ObvError.couldNotFindOwnedIdentity
        }
        // We obtained a list of restored owned identities. We only need to return one. We search for a non-hidden one
        do {
            let nonHiddenOwnedIdentities = try PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentities(within: ObvStack.shared.viewContext)
            let cryptoIdsOfNonHiddenOwnedIdentities = Set(nonHiddenOwnedIdentities.map { $0.cryptoId })
            return cryptoIdsOfNonHiddenOwnedIdentities.intersection(cryptoIdsOfRestoredOwnedIdentities).first ?? randomCryptoId
        } catch {
            // If something goes wrong, we return a "random" restored owned identity
            assertionFailure()
            return randomCryptoId
        }
    }
    
    
    func onboardingRequiresToRecoverBackupFromEncryptedBackup(onboardingFlow: NewOnboardingFlowViewController, encryptedBackup: Data, backupKey: String) async throws -> (backupRequestIdentifier: UUID, backupDate: Date) {
        return try await obvEngine.recoverLegacyBackupData(encryptedBackup, withBackupKey: backupKey)
    }
    
    
    func onboardingRequiresAcceptableCharactersForBackupKeyString() async -> CharacterSet {
        return obvEngine.getAcceptableCharactersForBackupKeyString()
    }
    
    
    func onboardingRequiresToGenerateOwnedIdentity(onboardingFlow: NewOnboardingFlowViewController, identityDetails: ObvIdentityDetails, nameForCurrentDevice: String, keycloakState: ObvKeycloakState?, customServerAndAPIKey: ServerAndAPIKey?) async throws -> ObvCryptoId {
        let usedCustomServerAndAPIKey: ServerAndAPIKey?
        if keycloakState != nil {
            usedCustomServerAndAPIKey = nil
        } else {
            usedCustomServerAndAPIKey = customServerAndAPIKey // nil, most of the time
        }
        let generatedOwnedCryptoId = try await obvEngine.generateOwnedIdentity(
            onServerURL: usedCustomServerAndAPIKey?.server ?? ObvAppCoreConstants.serverURL,
            with: identityDetails,
            nameForCurrentDevice: nameForCurrentDevice,
            keycloakState: keycloakState)
        if let apiKey = usedCustomServerAndAPIKey?.apiKey {
            _ = try await obvEngine.registerOwnedAPIKeyOnServerNow(ownedCryptoId: generatedOwnedCryptoId, apiKey: apiKey)
        }
        return generatedOwnedCryptoId
    }

    
    func onboardingIsFinished(onboardingFlow: NewOnboardingFlowViewController, ownedCryptoIdGeneratedDuringOnboarding: ObvTypes.ObvCryptoId) async {
        let log = self.log
        do {
            try await setupAndShowAppropriateChildViewControllers(ownedCryptoIdGeneratedDuringOnboarding: ownedCryptoIdGeneratedDuringOnboarding) { result in
                assert(Thread.isMainThread)
                switch result {
                case .failure(let error):
                    assertionFailure(error.localizedDescription)
                case .success:
                    os_log("Did setup and show the appropriate child view controller", log: log, type: .info)
                }
            }
        } catch {
            assertionFailure()
        }
    }

    
    func onboardingNeedsToPreventPrivacyWindowSceneFromShowingOnNextWillResignActive(onboardingFlow: NewOnboardingFlowViewController) async {
        preventPrivacyWindowSceneFromShowingOnNextWillResignActive()
    }
    
    
    func onboardingRequiresToSyncAppDatabasesWithEngine(onboardingFlow: NewOnboardingFlowViewController) async throws {
        try await requestSyncAppDatabasesWithEngine()
    }

    
    @MainActor
    private func requestSyncAppDatabasesWithEngine() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ObvMessengerInternalNotification.requestSyncAppDatabasesWithEngine(queuePriority: .veryHigh, isRestoringSyncSnapshotOrBackup: false) { result in
                switch result {
                case .failure(let error):
                    continuation.resume(throwing: error)
                case .success:
                    continuation.resume()
                }
            }.postOnDispatchQueue()
        }
    }

    
    func userNeedsToProveCapacityToAuthenticateOnKeycloakServerAsTransferIsRestricted(onboardingFlow: NewOnboardingFlowViewController, keycloakConfiguration: ObvKeycloakConfiguration, transferProofElements: ObvKeycloakTransferProofElements) async throws -> ObvKeycloakTransferProofAndAuthState {
        return try await KeycloakManagerSingleton.shared.userNeedsToProveCapacityToAuthenticateOnKeycloakServerAsTransferIsRestricted(keycloakConfiguration: keycloakConfiguration, transferProofElements: transferProofElements)
    }
    
    
    func userNeedsToProveCapacityToAuthenticateOnKeycloakServerAsTransferIsRestrictedDuringBackupRestore(onboardingFlow: NewOnboardingFlowViewController, keycloakConfiguration: ObvKeycloakConfiguration) async throws -> Data {
        return try await KeycloakManagerSingleton.shared.userNeedsToProveCapacityToAuthenticateOnKeycloakServerAsTransferIsRestrictedDuringBackupRestore(keycloakConfiguration: keycloakConfiguration)
    }
    
    
    func userProvidesProofOfAuthenticationOnKeycloakServer(onboardingFlow: NewOnboardingFlowViewController, ownedCryptoId: ObvCryptoId, protocolInstanceUID: UID, proof: ObvKeycloakTransferProofAndAuthState) async throws {
        try await obvEngine.userProvidesProofOfAuthenticationOnKeycloakServer(ownedCryptoId: ownedCryptoId, protocolInstanceUID: protocolInstanceUID, proof: proof)
    }

}


// MARK: - Helpers for maps

extension MetaFlowController {
    
    /// Helper function allowing to determine the device identifier from which a location was sent, given the identifier of the message associated with that location.
    private func determineObvDeviceIdentifierAssociatedToMessageObjectID(_ messageObjectID: TypeSafeManagedObjectID<PersistedMessage>) async throws -> ObvDeviceIdentifier? {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ObvDeviceIdentifier?, any Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    let deviceIdentifier: ObvDeviceIdentifier?
                    let message = try PersistedMessage.get(with: messageObjectID, within: context)
                    if let messageSent = message as? PersistedMessageSent {
                        deviceIdentifier = try messageSent.locationContinuousSent?.ownedDevice?.obvDeviceIdentifier
                    } else if let messageReceived = message as? PersistedMessageReceived {
                        deviceIdentifier = try messageReceived.locationContinuousReceived?.contactDevice?.obvDeviceIdentifier
                    } else {
                        assertionFailure()
                        deviceIdentifier = nil
                    }
                    return continuation.resume(returning: deviceIdentifier)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }

}


// MARK: - Helper methods for new backups

extension MetaFlowController {
    
    /// Called when the user chooses the deactivate backups from the "advanced settings" screen of the backup setup flow, and when the user "resets" the backups from the settings.
    private func userWantsToDeactivateBackups() async throws {
        try await obvEngine.userWantsToResetThisDeviceSeedAndBackups()
        ObvMessengerSettings.Backup.userDidSetupBackupsAtLeastOnce = true
    }

    
    /// This method is called from the onboarding or from the settings during the profile backup restore process. At the end of this process, just before actually restoring the profile,
    /// the user may be in a situation where restoring will deactivate all their older devices. The user then has the option to subscribe to Olvid+ to keep all their devices active by tapping on a button that eventually calls this method.
    /// In this case, we want to present the subscription flow and recalculate the value of `ObvDeviceDeactivationConsiquence` when it is dismissed.
    func userWantsToKeepAllDevicesActiveThanksToOlvidPlus(ownedCryptoIdentity: ObvOwnedCryptoIdentity) async throws -> ObvAppBackup.ObvDeviceDeactivationConsequence {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ObvAppBackup.ObvDeviceDeactivationConsequence, any Error>) in
            if let currentContinuation = self.continuationAndOwnedCryptoIdentity?.continuation {
                self.continuationAndOwnedCryptoIdentity = nil
                currentContinuation.resume(throwing: ObvError.userCancelled)
            }
            self.continuationAndOwnedCryptoIdentity = (continuation, ownedCryptoIdentity)
            let ownedCryptoId = ObvCryptoId(cryptoIdentity: ownedCryptoIdentity.getObvCryptoIdentity())
            self.userWantsToSubscribeOlvidPlus(ownedCryptoId: ownedCryptoId)
        }
    }
    
    
    private func getDeviceDeactivationConsequencesOfRestoringBackup(ownedCryptoIdentity: ObvOwnedCryptoIdentity) async throws -> ObvDeviceDeactivationConsequence {
        
        // Get the current owned devices of the profile
        
        let ownedDeviceDiscoveryResult: ObvOwnedDeviceDiscoveryResult = try await obvEngine.performOwnedDeviceDiscoveryNow(ownedCryptoIdentity: ownedCryptoIdentity)
        
        // If the user has no active owned devices, there cannot be any device deactivation
        
        guard !ownedDeviceDiscoveryResult.devices.isEmpty else {
            return .noDeviceDeactivation
        }
        
        // If the user's profile has multidevice activated, there won't be any device deactivation
        
        guard !ownedDeviceDiscoveryResult.isMultidevice else {
            return .noDeviceDeactivation
        }
        
        // At this point, the only "hope" is that the user's has an active in-app purchase
        // Note that we return `noDeviceDeactivation` when there is a subscription: this assumes
        // the app **will** associate the subscription with the restored owned identity as soon as it
        // is restored.
        
        guard let storeKitDelegate else {
            assertionFailure()
            throw ObvError.storeKitDelegateIsNil
        }
                
        let multideviceSubscriptionIsActive = try await storeKitDelegate.userWantsToKnowIfMultideviceSubscriptionIsActive()

        guard !multideviceSubscriptionIsActive else {
            return .noDeviceDeactivation
        }
        
        // If we reach this point, restoring the profile would deactivate certain devices
        
        let deactivatedDevices: [OlvidPlatformAndDeviceName] = ownedDeviceDiscoveryResult.devices.map { device in
            OlvidPlatformAndDeviceName(identifier: device.identifier, deviceName: device.name ?? String(device.identifier.hexString().prefix(4)), platform: .unknown)
        }.sorted()
        return .deviceDeactivations(deactivatedDevices: deactivatedDevices)

    }
    
    
    private func getOrCreateDeviceBackupSeed(saveToKeychain: Bool) async throws -> ObvCrypto.BackupSeed {

        ObvMessengerSettings.Backup.userDidSetupBackupsAtLeastOnce = true
        
        let serverURLForStoringDeviceBackup = ObvAppCoreConstants.serverURLForStoringDeviceBackup
        try await deactivateLegacyBackupsNow()
        
        let deviceBackupSeed: BackupSeed
        
        if let existingActiveBackupSeed = try await obvEngine.getDeviceActiveBackupSeed() {
            deviceBackupSeed = existingActiveBackupSeed
        } else {
            deviceBackupSeed = try await obvEngine.createDeviceBackupSeed(serverURLForStoringDeviceBackup: serverURLForStoringDeviceBackup, saveToKeychain: saveToKeychain)
        }
        
        
        return deviceBackupSeed
        
    }
    
    
    private func deactivateLegacyBackupsNow() async throws {
        // If legacy backups are configured, remove them
        guard try await obvEngine.getCurrentLegacyBackupKeyInformation() != nil else {
            // No legacy backup, nothing left to do
            return
        }
        // Best effort to delete old iCloud backups
        ObvMessengerInternalNotification.userWantsToStartIncrementalCleanBackup(cleanAllDevices: false)
            .postOnDispatchQueue()
        // The rest is done at the engine level
    }

    
    private func restoreProfileBackupFromServerNow(profileBackupFromServerToRestore: ObvProfileBackupFromServer, rawAuthState: Data?) async throws -> ObvRestoredOwnedIdentityInfos {
        let currentDeviceName = UIDevice.current.preciseModel
        try await obvEngine.restoreProfileBackupFromServerNow(profileBackupFromServerToRestore: profileBackupFromServerToRestore,
                                                              currentDeviceName: currentDeviceName,
                                                              rawAuthState: rawAuthState)
        // If we reach this point, the profile should now be available within the app
        let restoredOwnedIdentityInfos = try await getRestoredOwnedIdentityInfosForAppDatabase(ownedCryptoId: profileBackupFromServerToRestore.ownedCryptoId)
        return restoredOwnedIdentityInfos
    }
    
    
    private func getRestoredOwnedIdentityInfosForAppDatabase(ownedCryptoId: ObvCryptoId) async throws -> ObvRestoredOwnedIdentityInfos {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ObvRestoredOwnedIdentityInfos, any Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: context) else {
                        assertionFailure()
                        throw ObvError.couldNotFindOwnedIdentity
                    }
                    let isKeycloakManaged = ownedIdentity.isKeycloakManaged
                    let restoredOwnedIdentityInfos = ObvRestoredOwnedIdentityInfos(ownedCryptoId: ownedCryptoId,
                                                                                   firstNameThenLastName: ownedIdentity.identityCoreDetails.getDisplayNameWithStyle(.firstNameThenLastName),
                                                                                   positionAtCompany: ownedIdentity.identityCoreDetails.getDisplayNameWithStyle(.positionAtCompany),
                                                                                   displayedLetter: (ownedIdentity.customDisplayName ?? ownedIdentity.fullDisplayName).first ?? "?",
                                                                                   isKeycloakManaged: isKeycloakManaged)
                    return continuation.resume(returning: restoredOwnedIdentityInfos)
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
    
    
    /// Private method used during onboarding and when the user navigates to the backup settings.
    private func userWantsToFetchAllProfileBackupsFromServer(profileCryptoId: ObvCryptoId, profileBackupSeed: ObvCrypto.BackupSeed) async throws -> [ObvProfileBackupFromServer] {
        let serverURLForStoringDeviceBackup = ObvAppCoreConstants.serverURLForStoringDeviceBackup
        let backupSeedAndStorageServerURL = ObvBackupSeedAndStorageServerURL(backupSeed: profileBackupSeed, serverURLForStoringDeviceBackup: serverURLForStoringDeviceBackup)
        let profileBackupsFromServer: [ObvProfileBackupFromServer] = try await obvEngine.userWantsToFetchAllProfileBackupsFromServer(profileCryptoId: profileCryptoId, backupSeedAndStorageServerURL: backupSeedAndStorageServerURL)
        return profileBackupsFromServer
    }

    
    private func userWantsToFetchDeviceBakupFromServer(currentOwnedCryptoId: ObvCryptoId?) async throws -> AsyncStream<ObvDeviceBackupFromServerWithAppInfoKind> {
        
        return AsyncStream(ObvDeviceBackupFromServerWithAppInfoKind.self) { (continuation: AsyncStream<ObvDeviceBackupFromServerWithAppInfoKind>.Continuation) in
            Task {
                
                for try await deviceBackupFromServerKind in try await obvEngine.userWantsToFetchDeviceBakupFromServer() {
                    
                    switch deviceBackupFromServerKind {
                        
                    case .thisPhysicalDeviceHasNoBackupSeed:
                        continuation.yield(.thisPhysicalDeviceHasNoBackupSeed)
                        
                    case .errorOccuredForFetchingBackupOfThisPhysicalDevice(error: let error):
                        continuation.yield(.errorOccuredForFetchingBackupOfThisPhysicalDevice(error: error))
                        
                    case .thisPhysicalDevice(let deviceBackupFromServer):
                        let profiles: ObvListOfDeviceBackupProfiles = await .init(deviceBackupFromServer: deviceBackupFromServer)
                        let profilesToShow: ObvListOfDeviceBackupProfiles
                        if let currentOwnedCryptoId {
                            profilesToShow = await filterOutProfilesHiddenOnThisDevice(currentOwnedCryptoId: currentOwnedCryptoId, profiles: profiles)
                        } else {
                            profilesToShow = profiles
                        }
                        continuation.yield(.thisPhysicalDevice(profilesToShow))
                        
                    case .keychain(let deviceBackupFromServer):
                        let profiles: ObvListOfDeviceBackupProfiles = await .init(deviceBackupFromServer: deviceBackupFromServer)
                        continuation.yield(.keychain(profiles))

                    case .errorOccuredForFetchingBackupsFromKeychain(error: let error):
                        continuation.yield(.errorOccuredForFetchingBackupsFromKeychain(error: error))
                        
                    }
                }
                continuation.finish()
            }
        }
        
    }
    
    
    private func userWantsToUseDeviceBackupSeed(deviceBackupSeed: ObvCrypto.BackupSeed) async throws -> ObvAppBackup.ObvListOfDeviceBackupProfiles {
        let serverURLForStoringDeviceBackup = ObvAppCoreConstants.serverURLForStoringDeviceBackup
        let backupSeedAndStorageServerURL = ObvBackupSeedAndStorageServerURL(backupSeed: deviceBackupSeed, serverURLForStoringDeviceBackup: serverURLForStoringDeviceBackup)
        guard let deviceBackupFromServer = try await obvEngine.userWantsToUseDeviceBackupSeed(backupSeedAndStorageServerURL: backupSeedAndStorageServerURL) else {
            // No device backup found for this key
            throw ObvError.noDeviceBackupFoundForThisBackupSeed
        }
        let profiles = await ObvListOfDeviceBackupProfiles(deviceBackupFromServer: deviceBackupFromServer)
        return profiles
    }

    
}


// MARK: - SubscriptionPlansViewActionsProtocol (required for NewOnboardingFlowViewControllerDelegate)

extension MetaFlowController {

    func fetchSubscriptionPlans(for ownedCryptoId: ObvCryptoId, alsoFetchFreePlan: Bool) async throws -> (freePlanIsAvailable: Bool, products: [Product]) {
        
        // Step 1: Ask the engine (i.e., Olvid's server) whether a free trial is still available for this identity
        let freePlanIsAvailable: Bool
        if alsoFetchFreePlan {
            freePlanIsAvailable = (try? await obvEngine.queryServerForFreeTrial(for: ownedCryptoId)) ?? false
        } else {
            freePlanIsAvailable = false
        }

        // Step 2: As StoreKit about available products
        assert(storeKitDelegate != nil)
        let products = try await storeKitDelegate?.userRequestedListOfSKProducts() ?? []

        return (freePlanIsAvailable, products)
    }
    
    
    func userWantsToStartFreeTrialNow(ownedCryptoId: ObvCryptoId) async throws -> APIKeyElements {
        let newAPIKeyElements = try await obvEngine.startFreeTrial(for: ownedCryptoId)
        return newAPIKeyElements
    }
    
    
    func userWantsToBuy(_ product: Product) async throws -> StoreKitDelegatePurchaseResult {
        guard let storeKitDelegate else { assertionFailure(); throw ObvError.storeKitDelegateIsNil }
        return try await storeKitDelegate.userWantsToBuy(product)
    }
    
    
    func userWantsToRestorePurchases() async throws {
        guard let storeKitDelegate else { assertionFailure(); throw ObvError.storeKitDelegateIsNil }
        return try await storeKitDelegate.userWantsToRestorePurchases()
    }
    
}


// MARK: - MainFlowViewControllerDelegate

extension MetaFlowController: MainFlowViewControllerDelegate {
    
    func userWantsToDeleteOwnedIdentityAndHasConfirmed(_ mainFlowViewController: MainFlowViewController, ownedCryptoId: ObvCryptoId, globalOwnedIdentityDeletion: Bool) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToDeleteOwnedIdentityAndHasConfirmed(self, ownedCryptoId: ownedCryptoId, globalOwnedIdentityDeletion: globalOwnedIdentityDeletion)
    }
    
    /// This is called when the user taps the "refresh" button on her own identity screen. This method request the current subscriptions to store
    /// kit. If a valid subscription is found, it associated to each owned identity present on this device by contacting Olvid's servers.
    /// Then, if there is a "current" owned identity, we refresh the permissions by requesting them from Olvid's servers.
    func userWantsToRefreshSubscriptionStatus(_ mainFlowViewController: MainFlowViewController) async throws -> [ObvSubscription.StoreKitDelegatePurchaseResult] {
        return try await refreshSubscriptionStatus()
    }
    
    
    func userWantsToDisplayBackupKey(_ mainFlowViewController: MainFlowViewController) {
        Task {
            if let backupSeed = try await obvEngine.getDeviceActiveBackupSeed() {
                // We show the backup key
                let vc = BackupKeyDisplayerHostingHostingView(model: .init(backupSeed: backupSeed), delegate: self)
                self.present(vc, animated: true)
            } else {
                // Unexpected, as we should not be displaying the proposal to write down the backup
                // key, if there is no backup key yet
                assertionFailure()
                await userWantsToConfigureNewBackups(context: .afterOnboardingWithoutMigratingFromLegacyBackups)
            }
        }
    }
    
    
    func userWantsToBeRemindedToWriteDownBackupKey(_ mainFlowViewController: MainFlowViewController) async {
        await userWantsToBeRemindedToWriteDownBackupKey()
    }
    
    
    func userWantsToConfigureNewBackups(_ mainFlowViewController: MainFlowViewController, context: ObvAppBackup.ObvAppBackupSetupContext) {
        Task { await userWantsToConfigureNewBackups(context: context) }
    }
    
    
    private func userWantsToConfigureNewBackups(context: ObvAppBackupSetupContext) async {
        
        // Just make sure the user does not already have a device backup seed (which should not happen since this method was called)
        guard await !userHasAnActiveDeviceBackupSeed() else {
            assertionFailure("This method should not have been called in the first place")
            ObvMessengerSettings.Backup.userDidSetupBackupsAtLeastOnce = true
            return
        }
        
        let router = ObvAppBackupSetupRouter(navigationController: nil, delegate: self, context: context)
        self.router = router // Strong pointer to the router
        router.pushInitialViewController()
        guard let nav = router.localNavigationController else { assertionFailure(); return }
        nav.setNavigationBarHidden(true, animated: false)
        if let presentedViewController {
            presentedViewController.present(nav, animated: true)
        } else {
            self.present(nav, animated: true)
        }
        
    }
    
    
    /// This is called just before restoring a profile backup from the settings, in order to determine the consequence of this restoration in terms of devices deactivations.
    func getDeviceDeactivationConsequencesOfRestoringBackup(_ mainFlowViewController: MainFlowViewController, ownedCryptoIdentity: ObvCrypto.ObvOwnedCryptoIdentity) async throws -> ObvAppBackup.ObvDeviceDeactivationConsequence {
        return try await self.getDeviceDeactivationConsequencesOfRestoringBackup(ownedCryptoIdentity: ownedCryptoIdentity)
    }
    
    
    /// This method is called from the settings during the profile backup restore process. At the end of this process, just before actually restoring the profile,
    /// the user may be in a situation where restoring will deactivate all their older devices. The user then has the option to subscribe to Olvid+ to keep all their devices active by tapping on a button that eventually calls this method.
    /// In this case, we want to present the subscription flow and recalculate the value of `ObvDeviceDeactivationConsiquence` when it is dismissed.
    func userWantsToKeepAllDevicesActiveThanksToOlvidPlus(_ mainFlowViewController: MainFlowViewController, ownedCryptoIdentity: ObvCrypto.ObvOwnedCryptoIdentity) async throws -> ObvAppBackup.ObvDeviceDeactivationConsequence {
        return try await self.userWantsToKeepAllDevicesActiveThanksToOlvidPlus(ownedCryptoIdentity: ownedCryptoIdentity)
    }
    
    
    func fetchAvatarImage(_ mainFlowViewController: MainFlowViewController, profileCryptoId: ObvTypes.ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        do {
            return try await self.avatarHelper.fetchAvatarImage(ownedCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, size: frameSize)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                return nil
            } else {
                assertionFailure()
                return nil
            }
        }
    }
    
    
    func userWantsToDeleteProfileBackupFromSettings(_ mainFlowViewController: MainFlowViewController, infoForDeletion: ObvProfileBackupFromServer.InfoForDeletion) async throws {
        try await obvEngine.userWantsToDeleteProfileBackup(infoForDeletion: infoForDeletion)
    }
    
    
    func userWantsToResetThisDeviceSeedAndBackups(_ mainFlowViewController: MainFlowViewController) async throws {
        try await userWantsToDeactivateBackups()
    }
    
    
    func userWantsToAddDevice(_ mainFlowViewController: MainFlowViewController) {
        guard let currentOwnedCryptoId else { assertionFailure(); return }
        let deepLink = ObvDeepLink.myId(ownedCryptoId: currentOwnedCryptoId)
        Task {
            _ = await NewAppStateManager.shared.waitUntilAppIsInitializedAndMetaFlowControllerViewDidAppearAtLeastOnce()
            ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                .postOnDispatchQueue()
        }
    }
    
    
    func userWantsToSubscribeOlvidPlus(_ mainFlowViewController: MainFlowViewController) {
        guard let currentOwnedCryptoId else { assertionFailure(); return }
        self.userWantsToSubscribeOlvidPlus(ownedCryptoId: currentOwnedCryptoId)
    }
    
    
    func userNeedsToProveCapacityToAuthenticateOnKeycloakServerAsTransferIsRestricted(_ mainFlowViewController: MainFlowViewController, keycloakConfiguration: ObvKeycloakConfiguration) async throws -> Data {
        return try await KeycloakManagerSingleton.shared.userNeedsToProveCapacityToAuthenticateOnKeycloakServerAsTransferIsRestrictedDuringBackupRestore(keycloakConfiguration: keycloakConfiguration)
    }
    
    
    func restoreProfileBackupFromServerNow(_ mainFlowViewController: MainFlowViewController, profileBackupFromServerToRestore: ObvProfileBackupFromServer, rawAuthState: Data?) async throws -> ObvRestoredOwnedIdentityInfos {
        return try await self.restoreProfileBackupFromServerNow(profileBackupFromServerToRestore: profileBackupFromServerToRestore,
                                                                rawAuthState: rawAuthState)
    }
    
    
    func userWantsToFetchAllProfileBackupsFromServer(_ mainFlowViewController: MainFlowViewController, profileCryptoId: ObvCryptoId, profileBackupSeed: ObvCrypto.BackupSeed) async throws -> [ObvProfileBackupFromServer] {
        let profileBackupsFromServer = try await userWantsToFetchAllProfileBackupsFromServer(profileCryptoId: profileCryptoId, profileBackupSeed: profileBackupSeed)
        return profileBackupsFromServer
    }
    
    
    func userWantsToUseDeviceBackupSeed(_ mainFlowViewController: MainFlowViewController, deviceBackupSeed: BackupSeed) async throws -> ObvListOfDeviceBackupProfiles {
        return try await userWantsToUseDeviceBackupSeed(deviceBackupSeed: deviceBackupSeed)
    }
    
    
    func userWantsToFetchDeviceBakupFromServer(_ mainFlowViewController: MainFlowViewController, currentOwnedCryptoId: ObvCryptoId) async throws -> AsyncStream<ObvDeviceBackupFromServerWithAppInfoKind> {
        return try await self.userWantsToFetchDeviceBakupFromServer(currentOwnedCryptoId: currentOwnedCryptoId)
    }
    
    
    func userWantsToShowMapToConsultLocationSharedContinously(_ mainFlowViewController: MainFlowViewController, presentingViewController: UIViewController, ownedCryptoId: ObvCryptoId) async throws {
        if #available(iOS 17.0, *) {
            let dataSource = ObvMapViewControllerAppDataSource(ownedCryptoId: ownedCryptoId, delegate: self)
            let mapViewController = ObvMapViewController(dataSource: dataSource, actions: self)
            mapViewController.modalPresentationStyle = .overFullScreen
            presentingViewController.presentOnTop(mapViewController, animated: true)
        } else {
            throw ObvError.osUpgradeRequired
        }
    }
    
    
    func userWantsToShowMapToConsultLocationSharedContinously(_ mainFlowViewController: MainFlowViewController, presentingViewController: UIViewController, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>) async throws {
        if #available(iOS 17.0, *) {
            let initialDeviceIdentifierToSelect = try await determineObvDeviceIdentifierAssociatedToMessageObjectID(messageObjectID)
            let dataSource = try ObvMapViewControllerAppDataSource(messageObjectID: messageObjectID, delegate: self)
            let mapViewController = ObvMapViewController(dataSource: dataSource, actions: self, initialDeviceIdentifierToSelect: initialDeviceIdentifierToSelect)
            mapViewController.modalPresentationStyle = .overFullScreen
            presentingViewController.presentOnTop(mapViewController, animated: true)
        } else {
            throw ObvError.osUpgradeRequired
        }
    }
    
    
    func userWantsToShowMapToSendOrShareLocationContinuously(_ mainFlowViewController: MainFlowViewController, presentingViewController: UIViewController, discussionIdentifier: ObvDiscussionIdentifier) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToShowMapToSendOrShareLocationContinuously(self, presentingViewController: presentingViewController, discussionIdentifier: discussionIdentifier)
    }
    
    
    func userWantsToStopSharingLocationInDiscussion(_ mainFlowViewController: MainFlowViewController, discussionIdentifier: ObvDiscussionIdentifier) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToStopSharingLocationInDiscussion(self, discussionIdentifier: discussionIdentifier)
    }
    
    
    func userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice(_ mainFlowViewController: MainFlowViewController) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice(self)
    }
    
    
    func userWantsToUpdateReaction(_ mainFlowViewController: MainFlowViewController, ownedCryptoId: ObvCryptoId, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, newEmoji: String?) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToUpdateReaction(self, ownedCryptoId: ownedCryptoId, messageObjectID: messageObjectID, newEmoji: newEmoji)
    }
    
    
    func messagesAreNotNewAnymore(_ mainFlowViewController: MainFlowViewController, ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageIds: [MessageIdentifier]) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.messagesAreNotNewAnymore(self, ownedCryptoId: ownedCryptoId, discussionId: discussionId, messageIds: messageIds)
    }
    
    
    func updatedSetOfCurrentlyDisplayedMessagesWithLimitedVisibility(_ mainFlowViewController: MainFlowViewController, discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentIDs: Set<ObvManagedObjectPermanentID<PersistedMessage>>) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.updatedSetOfCurrentlyDisplayedMessagesWithLimitedVisibility(self, discussionPermanentID: discussionPermanentID, messagePermanentIDs: messagePermanentIDs)
    }
    
    
    func userWantsToReadReceivedMessageThatRequiresUserAction(_ mainFlowViewController: MainFlowViewController, ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageId: ReceivedMessageIdentifier) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToReadReceivedMessageThatRequiresUserAction(self, ownedCryptoId: ownedCryptoId, discussionId: discussionId, messageId: messageId)
    }
    
    
    func userWantsToUpdateDraftExpiration(_ mainFlowViewController: MainFlowViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, value: PersistedDiscussionSharedConfigurationValue?) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToUpdateDraftExpiration(self, draftObjectID: draftObjectID, value: value)
    }
    
    
    func insertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty(_ mainFlowViewController: MainFlowViewController, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, markAsRead: Bool) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.insertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty(self, discussionObjectID: discussionObjectID, markAsRead: markAsRead)
    }
    
    
    func userWantsToRemoveReplyToMessage(_ mainFlowViewController: MainFlowViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToRemoveReplyToMessage(self, draftObjectID: draftObjectID)
    }
    
    
    func userWantsToPauseSentFyleMessageJoinWithStatusFromOtherOwnedDevice(_ mainFlowViewController: MainFlowViewController, sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToPauseSentFyleMessageJoinWithStatusFromOtherOwnedDevice(self, sentJoinObjectID: sentJoinObjectID)
    }
    
    
    func userWantsToDownloadSentFyleMessageJoinWithStatusFromOtherOwnedDevice(_ mainFlowViewController: MainFlowViewController, sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToDownloadSentFyleMessageJoinWithStatusFromOtherOwnedDevice(self, sentJoinObjectID: sentJoinObjectID)
    }
    
    
    func userWantsToPauseDownloadReceivedFyleMessageJoinWithStatus(_ mainFlowViewController: MainFlowViewController, receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToPauseDownloadReceivedFyleMessageJoinWithStatus(self, receivedJoinObjectID: receivedJoinObjectID)
    }
    
    
    func userWantsToDownloadReceivedFyleMessageJoinWithStatus(_ mainFlowViewController: MainFlowViewController, receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToDownloadReceivedFyleMessageJoinWithStatus(self, receivedJoinObjectID: receivedJoinObjectID)
    }
    
    
    func userWantsToReplyToMessage(_ mainFlowViewController: MainFlowViewController, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToReplyToMessage(self, messageObjectID: messageObjectID, draftObjectID: draftObjectID)
    }
    
    
    func userWantsToDeleteAttachmentsFromDraft(_ mainFlowViewController: MainFlowViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, draftTypeToDelete: DeleteAllDraftFyleJoinOfDraftOperation.DraftType) async {
        guard let metaFlowControllerDelegate else { assertionFailure(); return }
        await metaFlowControllerDelegate.userWantsToDeleteAttachmentsFromDraft(self, draftObjectID: draftObjectID, draftTypeToDelete: draftTypeToDelete)
    }
    
    func userWantsToUpdateDraftBodyAndMentions(_ mainFlowViewController: MainFlowViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, body: String, mentions: Set<MessageJSON.UserMention>) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToUpdateDraftBodyAndMentions(self, draftObjectID: draftObjectID, body: body, mentions: mentions)
    }
    
    
    func userWantsToAddAttachmentsToDraftFromURLs(_ mainFlowViewController: MainFlowViewController, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, urls: [URL]) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToAddAttachmentsToDraftFromURLs(self, draftPermanentID: draftPermanentID, urls: urls)
    }
    
    
    func userWantsToAddAttachmentsToDraft(_ mainFlowViewController: MainFlowViewController, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, itemProviders: [NSItemProvider]) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToAddAttachmentsToDraft(self, draftPermanentID: draftPermanentID, itemProviders: itemProviders)
    }
    
    
    func userWantsToSendDraft(mainFlowViewController: MainFlowViewController, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, textBody: String, mentions: Set<MessageJSON.UserMention>) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToSendDraft(self, draftPermanentID: draftPermanentID, textBody: textBody, mentions: mentions)
    }
    
    
    func userRequestedAppDatabaseSyncWithEngine(mainFlowViewController: MainFlowViewController) async throws {
        assert(metaFlowControllerDelegate != nil)
        try await metaFlowControllerDelegate?.userRequestedAppDatabaseSyncWithEngine(metaFlowController: self)
    }
    
    
    @MainActor
    func userWantsToPublishGroupV2Modification(_ mainFlowViewController: MainFlowViewController, groupObjectID: TypeSafeManagedObjectID<PersistedGroupV2>, changeset: ObvGroupV2.Changeset) async throws {
        assert(Thread.isMainThread) // Required because we access automaticallyNavigateToCreatedDisplayedContactGroup
        
        guard let group = try PersistedGroupV2.get(objectID: groupObjectID, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
        guard group.ownedIdentityIsAdmin else { assertionFailure(); return }
        guard !changeset.isEmpty else { return }
        
        // If the user decided to change the group type, we make sure that the permissions of each member (after the update)
        // will be coherent with the group type.
        
        let changesetToConsider: ObvGroupV2.Changeset
        
        if let serializedGroupType = changeset.changes.compactMap({ $0.serializedGroupTypeInChange }).first {
            
            let newGroupType = try ObvGroupType(serializedGroupType: serializedGroupType)
            let adminPermissions = ObvGroupType.exactPermissions(of: .admin, forGroupType: newGroupType)
            let regularPermissions = ObvGroupType.exactPermissions(of: .regularMember, forGroupType: newGroupType)

            var changesToConsider = Set<ObvGroupV2.Change>()
            var cryptoIdsConsideredForPermissions: Set<ObvCryptoId> = []
            var ownPermissionsConsidered: Bool = false
            
            // Make sure the received changes are coherent with the new group type
            
            for change in changeset.changes {
                
                switch change {
                    
                case .memberRemoved(contactCryptoId: let contactCryptoId):
                    changesToConsider.insert(change)
                    cryptoIdsConsideredForPermissions.insert(contactCryptoId)
                    
                case .memberAdded(contactCryptoId: let contactCryptoId, permissions: let permissions):
                    let permissionsToConsider = permissions.contains(.groupAdmin) ? adminPermissions : regularPermissions
                    changesToConsider.insert(.memberAdded(contactCryptoId: contactCryptoId, permissions: permissionsToConsider))
                    cryptoIdsConsideredForPermissions.insert(contactCryptoId)

                case .memberChanged(contactCryptoId: let contactCryptoId, permissions: let permissions):
                    let permissionsToConsider = permissions.contains(.groupAdmin) ? adminPermissions : regularPermissions
                    changesToConsider.insert(.memberChanged(contactCryptoId: contactCryptoId, permissions: permissionsToConsider))
                    cryptoIdsConsideredForPermissions.insert(contactCryptoId)

                case .ownPermissionsChanged(permissions: let permissions):
                    let permissionsToConsider = permissions.contains(.groupAdmin) ? adminPermissions : regularPermissions
                    changesToConsider.insert(.ownPermissionsChanged(permissions: permissionsToConsider))
                    ownPermissionsConsidered = true
                    
                case .groupDetails:
                    changesToConsider.insert(change)

                case .groupPhoto:
                    changesToConsider.insert(change)

                case .groupType:
                    changesToConsider.insert(change)
                    
                }
            }
            
            // Scan through all members of the group and make sure the permissions they will have after
            // the update are coherent with the new group type.
            
            for otherMember in group.otherMembers {
                guard !cryptoIdsConsideredForPermissions.contains(otherMember.cryptoId) else { continue }
                let permissionsToConsider = otherMember.isAnAdmin ? adminPermissions : regularPermissions
                changesToConsider.insert(.memberChanged(contactCryptoId: otherMember.cryptoId, permissions: permissionsToConsider))
            }
            
            // Make sure our own permissions will be coherent
            
            if !ownPermissionsConsidered {
                let permissionsToConsider = group.ownedIdentityIsAdmin ? adminPermissions : regularPermissions
                changesToConsider.insert(.ownPermissionsChanged(permissions: permissionsToConsider))
            }
                        
            changesetToConsider = try .init(changes: changesToConsider)
            
        } else {
            
            changesetToConsider = changeset
            
        }
                
        // Request the update
        
        automaticallyNavigateToCreatedDisplayedContactGroup = true
        let obvEngine = self.obvEngine
        guard let ownedCryptoId = try? group.ownCryptoId else { assertionFailure(); return }
        let groupIdentifier = group.groupIdentifier
        DispatchQueue(label: "Background queue for calling obvEngine.updateGroupV2").async {
            do {
                try obvEngine.updateGroupV2(ownedCryptoId: ownedCryptoId, groupIdentifier: groupIdentifier, changeset: changesetToConsider)
            } catch {
                assertionFailure()
            }
        }
    }
    
    
    @MainActor
    func userWantsToPublishGroupV2Creation(groupCoreDetails: GroupV2CoreDetails, ownPermissions: Set<ObvGroupV2.Permission>, otherGroupMembers: Set<ObvGroupV2.IdentityAndPermissions>, ownedCryptoId: ObvCryptoId, photoURL: URL?, groupType: ObvAppTypes.ObvGroupType) async throws {
        assert(Thread.isMainThread) // Required because we access automaticallyNavigateToCreatedDisplayedContactGroup
        automaticallyNavigateToCreatedDisplayedContactGroup = true
        let obvEngine = self.obvEngine
        let serializedGroupCoreDetails = try groupCoreDetails.jsonEncode()
        let serializedGroupType = try groupType.toSerializedGroupType()
        try await obvEngine.startGroupV2CreationProtocol(serializedGroupCoreDetails: serializedGroupCoreDetails,
                                                         ownPermissions: ownPermissions,
                                                         otherGroupMembers: otherGroupMembers,
                                                         ownedCryptoId: ownedCryptoId,
                                                         photoURL: photoURL,
                                                         serializedGroupType: serializedGroupType)
    }
    
    
    func userWantsToAddNewDevice(_ viewController: MainFlowViewController, ownedCryptoId: ObvCryptoId) async {
        guard let (ownedDetails, isKeycloakManaged) = try? await getOwnedIdentityDetails(ownedCryptoId: ownedCryptoId) else { assertionFailure(); return }
        let isTransferRestricted: Bool
        if isKeycloakManaged {
            guard let _isTransferRestricted = (try? obvEngine.getOwnedIdentityKeycloakState(with: ownedCryptoId))?.obvKeycloakState?.isTransferRestricted else { assertionFailure(); return }
            isTransferRestricted = _isTransferRestricted
        } else {
            isTransferRestricted = false
        }
        let newOnboardingFlowViewController = NewOnboardingFlowViewController(
            logSubsystem: ObvAppCoreConstants.logSubsystem,
            directoryForTempFiles: ObvUICoreDataConstants.ContainerURL.forTempFiles.url,
            mode: .addNewDevice(ownedCryptoId: ownedCryptoId, ownedDetails: ownedDetails, isTransferRestricted: isTransferRestricted),
            dataSource: self)
        newOnboardingFlowViewController.delegate = self
        present(newOnboardingFlowViewController, animated: true)
    }
    
    
    private func getOwnedIdentityDetails(ownedCryptoId: ObvCryptoId) async throws -> (ownedDetails: CNContact, isKeycloakManaged: Bool)? {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(ownedDetails: CNContact, isKeycloakManaged: Bool)?, Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: context) else {
                        return continuation.resume(returning: nil)
                    }
                    let ownedDetails = ownedIdentity.asCNContact
                    let isKeycloakManaged = ownedIdentity.isKeycloakManaged
                    continuation.resume(returning: (ownedDetails, isKeycloakManaged))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func fetchAvatarImage(_ mainFlowViewController: MainFlowViewController, localPhotoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return try await self.avatarHelper.fetchAvatarImage(localPhotoURL: localPhotoURL, size: avatarSize)
    }
    
    
    func userWantsToReplaceTrustedDetailsByPublishedDetails(_ mainFlowViewController: MainFlowViewController, groupIdentifier: ObvGroupV2Identifier) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToReplaceTrustedDetailsByPublishedDetails(self, groupIdentifier: groupIdentifier)
    }
    
    
    func userWantsToLeaveGroup(_ mainFlowViewController: MainFlowViewController, groupIdentifier: ObvGroupV2Identifier) async throws {
        try await obvEngine.leaveGroupV2(ownedCryptoId: groupIdentifier.ownedCryptoId, groupIdentifier: groupIdentifier.identifier.appGroupIdentifier)
    }
    
    
    func userWantsToDisbandGroup(_ mainFlowViewController: MainFlowViewController, groupIdentifier: ObvGroupV2Identifier) async throws {
        try await obvEngine.performDisbandOfGroupV2(ownedCryptoId: groupIdentifier.ownedCryptoId, groupIdentifier: groupIdentifier.identifier.appGroupIdentifier)
    }
        
    
    func userWantsObtainAvatar(_ mainFlowViewController: MainFlowViewController, avatarSource: ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return try await self.userWantsObtainAvatar(avatarSource: avatarSource, avatarSize: avatarSize)
    }
    
}


// MARK: - Implementing ObvMapViewControllerActionsProtocol

@available(iOS 17.0, *)
extension MetaFlowController: ObvMapViewControllerActionsProtocol {
    
    func userWantsToDismissObvMapView(_ vc: ObvMapViewController) {
        vc.dismiss(animated: true)
    }
    
}


// MARK: - Implementing ObvMapViewControllerAppDataSourceDelegate

@available(iOS 17.0, *)
extension MetaFlowController: ObvMapViewControllerAppDataSourceDelegate {
    
    func fetchAvatar(_ vc: ObvMapViewControllerAppDataSource, photoURL: URL, avatarSize: ObvAvatarSize) async throws -> UIImage? {
        do {
            return try await self.avatarHelper.fetchAvatarImage(localPhotoURL: photoURL, size: avatarSize)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                return nil
            } else {
                assertionFailure()
                return nil
            }
        }
    }
    
}


// MARK: - Implementing BackupKeyDisplayerHostingHostingViewDelegate

extension MetaFlowController: BackupKeyDisplayerHostingHostingViewDelegate {
    
    func userConfirmedWritingDownTheBackupKey(_ vc: ObvAppBackup.BackupKeyDisplayerHostingHostingView, remindToSaveBackupKey: Bool) {
        if presentedViewController == vc {
            vc.dismiss(animated: true) {
                ObvMessengerSettings.Backup.dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey = remindToSaveBackupKey ? .now : nil
            }
        } else {
            ObvMessengerSettings.Backup.dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey = remindToSaveBackupKey ? .now : nil
        }
    }
    
}


// MARK: - Implementing ObvAppBackupSetupRouterDelegate

extension MetaFlowController: ObvAppBackupSetupRouterDelegate {
    
    func userWantsToBeRemindedToWriteDownBackupKey(_ router: ObvAppBackup.ObvAppBackupSetupRouter) async {
        await userWantsToBeRemindedToWriteDownBackupKey()
    }
    
    
    func userWantsToDeactivateBackups(_ router: ObvAppBackupSetupRouter) async throws {
        try await self.userWantsToDeactivateBackups()
    }
    
    
    func getOrCreateDeviceBackupSeed(_ router: ObvAppBackup.ObvAppBackupSetupRouter, saveToKeychain: Bool) async throws -> ObvCrypto.BackupSeed {
        return try await self.getOrCreateDeviceBackupSeed(saveToKeychain: saveToKeychain)
    }

    
    func userConfirmedWritingDownTheBackupKey(_ router: ObvAppBackup.ObvAppBackupSetupRouter) {
        router.localNavigationController?.dismiss(animated: true)
    }
    
    
    func userHasFinishedTheBackupsSetup(_ router: ObvAppBackup.ObvAppBackupSetupRouter) {
        router.localNavigationController?.dismiss(animated: true)
    }
    
}


// MARK: - Implementing NewOnboardingFlowViewControllerDataSource

extension MetaFlowController: NewOnboardingFlowViewControllerDataSource {
    
    func getAnOwnedIdentityExistingOnThisDevice() async -> ObvTypes.ObvCryptoId? {
        do {
            let allOwnedIdentities = try PersistedObvOwnedIdentity.getAllActive(within: ObvStack.shared.viewContext)
            return allOwnedIdentities.first(where: { !$0.isHidden })?.cryptoId
        } catch {
            assertionFailure(error.localizedDescription)
            return nil
        }
    }
    
}



// MARK: - Feeding the contact database

extension MetaFlowController {
    
    
    private func observeUserWantsToDeleteOwnedContactGroupNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeUserWantsToDeleteOwnedContactGroup { [weak self] ownedCryptoId, groupUid in
            Task { await self?.deleteOwnedContactGroup(groupUid: groupUid, ownedCryptoId: ownedCryptoId, confirmed: false) }
        })
    }

    
    @MainActor
    private func deleteOwnedContactGroup(groupUid: UID, ownedCryptoId: ObvCryptoId, confirmed: Bool) async {
        
        if confirmed {

            do {
                try await obvEngine.disbandGroupV1(groupUid: groupUid, ownedCryptoId: ownedCryptoId)
            } catch {
                let uiAlert = UIAlertController(title: Strings.AlertDeleteOwnedGroupFailed.title, message: Strings.AlertDeleteOwnedGroupFailed.message, preferredStyle: .alert)
                let okAction = UIAlertAction(title: CommonString.Word.Ok, style: .default, handler: nil)
                uiAlert.addAction(okAction)
                
                if let presentedViewController {
                    presentedViewController.present(uiAlert, animated: true)
                } else {
                    present(uiAlert, animated: true)
                }
            }
            
        } else {
            
            let alert = UIAlertController(title: CommonString.Title.deleteGroup,
                                          message: Strings.deleteGroupExplanation,
                                          preferredStyleForTraitCollection: self.traitCollection)
            alert.addAction(UIAlertAction(title: CommonString.AlertButton.performDeletionAction, style: .destructive, handler: { [weak self] (action) in
                Task { await self?.deleteOwnedContactGroup(groupUid: groupUid, ownedCryptoId: ownedCryptoId, confirmed: true) }
            }))
            alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))
            
            if let presentedViewController = presentedViewController {
                presentedViewController.present(alert, animated: true)
            } else {
                present(alert, animated: true)
            }
            
        }
        
    }
    
    
    private func observeUserWantsToLeaveJoinedContactGroupNotifications() {
        let NotificationType = MessengerInternalNotification.UserWantsToLeaveJoinedContactGroup.self
        let token = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: nil) { [weak self] (notification) in
            guard let (groupOwner, groupUid, ownedCryptoId, sourceView) = NotificationType.parse(notification) else { return }
            Task { [weak self] in
                await self?.processUserWantsToLeaveJoinedContactGroup(groupOwner: groupOwner,
                                                                      groupUid: groupUid,
                                                                      ownedCryptoId: ownedCryptoId,
                                                                      sourceView: sourceView)
            }
        }
        observationTokens.append(token)
    }
    
    
    @MainActor
    private func processUserWantsToLeaveJoinedContactGroup(groupOwner: ObvCryptoId, groupUid: UID, ownedCryptoId: ObvCryptoId, sourceView: UIView) {
        guard self.currentOwnedCryptoId == ownedCryptoId else { return }
        self.leaveJoinedContactGroup(groupOwner: groupOwner, groupUid: groupUid, ownedCryptoId: ownedCryptoId, sourceView: sourceView, confirmed: false)
    }

    
    private func leaveJoinedContactGroup(groupOwner: ObvCryptoId, groupUid: UID, ownedCryptoId: ObvCryptoId, sourceView: UIView, confirmed: Bool) {
        
        if confirmed {
            
            let log = self.log
            let localEngine = self.obvEngine
            DispatchQueue(label: "Background queue for requesting leaveContactGroupJoined to engine").async {
                do {
                    try localEngine.leaveContactGroupJoined(ownedCryptoId: ownedCryptoId, groupUid: groupUid, groupOwner: groupOwner)
                } catch {
                    os_log("Could not leave contact group joined", log: log, type: .error)
                }
            }

        } else {
            let alert = UIAlertController(title: CommonString.Title.leaveGroup,
                                          message: Strings.leaveGroupExplanation,
                                          preferredStyleForTraitCollection: self.traitCollection)
            alert.addAction(UIAlertAction(title: CommonString.Title.leaveGroup, style: .destructive, handler: { [weak self] (action) in
                if let presentedViewController = self?.presentedViewController {
                    presentedViewController.dismiss(animated: true, completion: {
                        self?.leaveJoinedContactGroup(groupOwner: groupOwner, groupUid: groupUid, ownedCryptoId: ownedCryptoId, sourceView: sourceView, confirmed: true)
                    })
                } else {
                    self?.leaveJoinedContactGroup(groupOwner: groupOwner, groupUid: groupUid, ownedCryptoId: ownedCryptoId, sourceView: sourceView, confirmed: true)
                }
            }))
            alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))
            DispatchQueue.main.async { [weak self] in
                guard let _self = self else { return }
                alert.popoverPresentationController?.sourceView = sourceView
                if let presentedViewController = _self.presentedViewController {
                    presentedViewController.present(alert, animated: true)
                } else {
                    _self.present(alert, animated: true)
                }
            }
            
        }

    }
    
    
    private func observeUserWantsToIntroduceContactToAnotherContactNotifications() {
        let token = ObvMessengerInternalNotification.observeUserWantsToIntroduceContactToAnotherContact() { [weak self] (ownedCryptoId, contactCryptoId, otherContactCryptoIds) in
            guard let _self = self else { return }
            guard !otherContactCryptoIds.isEmpty else { assertionFailure(); return }
            guard _self.currentOwnedCryptoId == ownedCryptoId else { return }
            guard !otherContactCryptoIds.contains(contactCryptoId) else { assertionFailure(); return }
            ObvStack.shared.performBackgroundTask { [weak self] (context) in
                guard let ownedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: context) else { return }
                guard let contactFromEngine = try? self?.obvEngine.getContactIdentity(with: contactCryptoId, ofOwnedIdentityWith: ownedIdentity.cryptoId) else { assertionFailure(); return }
                let contactCoreDetails = contactFromEngine.publishedIdentityDetails?.coreDetails ?? contactFromEngine.trustedIdentityDetails.coreDetails
                let otherContactsFromEngine = otherContactCryptoIds.compactMap {
                    try? self?.obvEngine.getContactIdentity(with: $0, ofOwnedIdentityWith: ownedIdentity.cryptoId)
                }
                guard otherContactsFromEngine.count == otherContactCryptoIds.count else { assertionFailure(); return }
                let otherContactsWithCoreDetails = otherContactsFromEngine.map { ($0.cryptoId, $0.publishedIdentityDetails?.coreDetails ?? $0.trustedIdentityDetails.coreDetails) }
                Task { [weak self] in
                    await self?.introduceContact(contactCryptoId, withCoreDetails: contactCoreDetails, to: otherContactsWithCoreDetails, forOwnedCryptoId: ownedCryptoId, confirmed: false)
                }
            }
        }
        observationTokens.append(token)
    }
    
    
    @MainActor
    private func introduceContact(_ contactCryptoId: ObvCryptoId, withCoreDetails contactCoreDetails: ObvIdentityCoreDetails, to otherContacts: [(cryptoId: ObvCryptoId, coreDetails: ObvIdentityCoreDetails)], forOwnedCryptoId ownedCryptoId: ObvCryptoId, confirmed: Bool) async {
        
        
        guard !otherContacts.isEmpty else { assertionFailure(); return }
        
        if confirmed {

            let log = self.log
            let obvEngine = self.obvEngine

            DispatchQueue(label: "Dispatching a call to the engine of the main thread").async {

                do {
                    try obvEngine.startContactMutualIntroductionProtocol(of: contactCryptoId, with: Set(otherContacts.map({ $0.cryptoId })), forOwnedId: ownedCryptoId)
                } catch {
                    os_log("Could not start ContactMutualIntroductionProtocol", log: log, type: .fault)
                    return
                }
                
                let other = otherContacts.first!
                let message = Strings.AlertMutualIntroductionPerformedSuccessfully.message(contactCoreDetails.getDisplayNameWithStyle(.firstNameThenLastName),
                                                                                           other.coreDetails.getDisplayNameWithStyle(.firstNameThenLastName),
                                                                                           otherContacts.count-1)
                
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: Strings.AlertMutualIntroductionPerformedSuccessfully.title,
                                                  message: message,
                                                  preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .default))
                    DispatchQueue.main.async { [weak self] in
                        if let presentedViewController = self?.presentedViewController {
                            presentedViewController.present(alert, animated: true)
                        } else {
                            self?.present(alert, animated: true)
                        }
                    }
                }
                
            }
            
            
        } else {
            
            assert(Thread.current == Thread.main)
            
            let other = otherContacts.first!
            let message = Strings.AlertMutualIntroduction.message(contactCoreDetails.getDisplayNameWithStyle(.firstNameThenLastName),
                                                                  other.coreDetails.getDisplayNameWithStyle(.firstNameThenLastName),
                                                                  otherContacts.count-1)
            
            let alert = UIAlertController(title: Strings.AlertMutualIntroduction.title,
                                          message: message,
                                          preferredStyleForTraitCollection: self.traitCollection)            
            alert.addAction(UIAlertAction(title: Strings.AlertMutualIntroduction.actionPerformIntroduction, style: .default, handler: { (action) in
                Task { [weak self] in await self?.introduceContact(contactCryptoId, withCoreDetails: contactCoreDetails, to: otherContacts, forOwnedCryptoId: ownedCryptoId, confirmed: true) }
            }))
            alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))
            if let presentedViewController = self.presentedViewController {
                presentedViewController.present(alert, animated: true)
            } else {
                present(alert, animated: true)
            }
            
        }
    }
    
    
    private func showAlertWhenPastedStringIsNotValidOlvidURL() {
        assert(Thread.isMainThread)
        let alert = UIAlertController(title: CommonString.Word.Oups,
                                      message: Strings.pastedStringIsNotValidOlvidURL,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .default))
        if let presentedViewController {
            presentedViewController.present(alert, animated: true)
        } else {
            present(alert, animated: true)
        }
        
    }
    
    
}


// MARK: - Misc and protocols starters

extension MetaFlowController {
    
    private func processUserWantsToRestartChannelEstablishmentProtocol(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId) {
        do {
            try obvEngine.restartAllOngoingChannelEstablishmentProtocolsWithContactIdentity(with: contactCryptoId, ofOwnedIdentyWith: ownedCryptoId)
        } catch {
            DispatchQueue.main.async { [weak self] in
                let alert = UIAlertController(title: Strings.AlertChannelEstablishementRestartedFailed.title, message: "", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .default))
                self?.present(alert, animated: true)
            }
            return
        }
        
        // Display a feedback alert
        DispatchQueue.main.async { [weak self] in
            let alert = UIAlertController(title: Strings.AlertChannelEstablishementRestarted.title, message: "", preferredStyle: .alert)
            alert.addAction(UIAlertAction.init(title: CommonString.Word.Ok, style: .default))
            self?.present(alert, animated: true)
        }

    }
    

    private func observeUserTriedToAccessCameraButAccessIsDeniedNotifications() {
        let NotificationType = MessengerInternalNotification.UserTriedToAccessCameraButAccessIsDenied.self
        let token = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: nil) { [weak self] (notification) in
            Task { [weak self] in await self?.processUserTriedToAccessCameraButAccessIsDenied() }
        }
        observationTokens.append(token)
    }
    
    
    @MainActor
    private func processUserTriedToAccessCameraButAccessIsDenied() {
        let alert = UIAlertController(title: Strings.authorizationRequired, message: Strings.cameraAccessDeniedExplanation, preferredStyle: .alert)
        if let appSettings = URL(string: UIApplication.openSettingsURLString) {
            alert.addAction(UIAlertAction(title: Strings.goToSettingsButtonTitle, style: .default, handler: { (_) in
                UIApplication.shared.open(appSettings, options: [:])
            }))
        }
        alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel, handler: nil))
        if let presentedViewController = self.presentedViewController {
            presentedViewController.present(alert, animated: true)
        } else {
            self.present(alert, animated: true)
        }
    }
    

    private func processUserWantsToCreateNewGroupV1(groupName: String, groupDescription: String?, groupMembersCryptoIds: Set<ObvCryptoId>, ownedCryptoId: ObvCryptoId, photoURL: URL?) {
        assert(Thread.isMainThread) // Required because we access automaticallyNavigateToCreatedDisplayedContactGroup
        automaticallyNavigateToCreatedDisplayedContactGroup = true
        let obvEngine = self.obvEngine
        let log = self.log
        DispatchQueue(label: "Background queue for calling obvEngine.startGroupCreationProtocol").async {
            do {
                try obvEngine.startGroupCreationProtocol(groupName: groupName, groupDescription: groupDescription, groupMembers: groupMembersCryptoIds, ownedCryptoId: ownedCryptoId, photoURL: photoURL)
            } catch {
                os_log("Failed to create GroupV1: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
        }
    }
    

    @MainActor
    private func processDisplayedContactGroupWasJustCreated(permanentID: ObvManagedObjectPermanentID<DisplayedContactGroup>) async {
        assert(Thread.isMainThread) // Required because we access automaticallyNavigateToCreatedDisplayedContactGroup
        guard automaticallyNavigateToCreatedDisplayedContactGroup else { return }
        guard let currentOwnedCryptoId else { return }
        guard let displayedContactGroup = try? DisplayedContactGroup.getManagedObject(withPermanentID: permanentID, within: ObvStack.shared.viewContext) else { return }
        guard let ownedCryptoId = try? displayedContactGroup.ownedCryptoId else { assertionFailure(); return }
        guard currentOwnedCryptoId == ownedCryptoId else { return }
        // We only automatically navigate to groups we juste created, where we are admin
        guard displayedContactGroup.ownPermissionAdmin else { return }
        // Navigate to the group
        automaticallyNavigateToCreatedDisplayedContactGroup = false
        let deepLink = ObvDeepLink.groupV1Details(ownedCryptoId: currentOwnedCryptoId, objectPermanentID: permanentID)
        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
            .postOnDispatchQueue()
    }

    
    @MainActor
    private func processUserWantsToAddOwnedProfileNotification() async {
        presentedViewController?.dismiss(animated: true)
        let newOnboardingFlowViewController = NewOnboardingFlowViewController(
            logSubsystem: ObvAppCoreConstants.logSubsystem,
            directoryForTempFiles: ObvUICoreDataConstants.ContainerURL.forTempFiles.url,
            mode: .addProfile,
            dataSource: self)
        newOnboardingFlowViewController.delegate = self
        present(newOnboardingFlowViewController, animated: true)
    }
    
}


// MARK: - Switching current owned identity

extension MetaFlowController {
    
    /// Changes the current owned identity of the user. Called as a response to the corresponding notification and from the MainFlowViewController as well, when processing an externally tapped or scanned `OlvidURL`.
    @MainActor func processUserWantsToSwitchToOtherOwnedIdentity(ownedCryptoId: ObvCryptoId) async {
        presentedViewController?.dismiss(animated: true)
        await switchToOwnedIdentity(ownedCryptoId: ownedCryptoId)
    }
    
    
    @MainActor
    private func processUserWantsToSwitchToOtherHiddenOwnedIdentity(password: String) async {
        let ownedCryptoId: ObvCryptoId
        do {
            guard let unlockedOwnedIdentity = try PersistedObvOwnedIdentity.getHiddenOwnedIdentity(password: password, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
            ownedCryptoId = unlockedOwnedIdentity.cryptoId
        } catch {
            assertionFailure(error.localizedDescription)
            return
        }
        await switchToOwnedIdentity(ownedCryptoId: ownedCryptoId)
    }
    
    
    /// Certain events trigger the immediate closing of a hidden owned identity if one is open. For example, when using a custom passcode, we should close any open hidden identity.
    /// When this is required, a `CloseAnyOpenHiddenOwnedIdentity` notification is sent, and we process it here, where we simply switch to any non-hidden identity.
    @MainActor func switchToNonHiddenOwnedIdentityIfCurrentIsHidden() async {
        guard let currentOwnedCryptoId else { return }
        guard let ownedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: currentOwnedCryptoId, within: ObvStack.shared.viewContext) else {
            await switchToNonHiddenOwnedIdentity()
            return
        }
        guard ownedIdentity.isHidden else { return }
        // If we reach this point, the current owned identity is hidden. We close it, as requested.
        await switchToNonHiddenOwnedIdentity()
    }
    
    
    /// Alows to switch to the most appropriate non-hidden owned identity
    @MainActor private func switchToNonHiddenOwnedIdentity() async {
        let ownedCryptoId: ObvCryptoId
        if let _ownedCryptoId = await LatestCurrentOwnedIdentityStorage.shared.getLatestCurrentOwnedIdentityStored()?.nonHiddenCryptoId {
            ownedCryptoId = _ownedCryptoId
        } else {
            guard let ownedIdentity = try? PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentities(within: ObvStack.shared.viewContext).first else { assertionFailure(); return }
            ownedCryptoId = ownedIdentity.cryptoId
        }
        await switchToOwnedIdentity(ownedCryptoId: ownedCryptoId)
    }
    
    
    /// Called from the other aboves methods when they need to switch identity.
    @MainActor private func switchToOwnedIdentity(ownedCryptoId: ObvCryptoId) async {
        let isHidden: Bool
        do {
            guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: ObvStack.shared.viewContext) else { return }
            isHidden = ownedIdentity.isHidden
        } catch {
            assertionFailure(error.localizedDescription)
            return
        }
        guard let mainFlowViewController else { assertionFailure(); return }
        self.currentOwnedCryptoId = ownedCryptoId
        await LatestCurrentOwnedIdentityStorage.shared.storeLatestCurrentOwnedCryptoId(ownedCryptoId, isHidden: isHidden)
        await mainFlowViewController.switchCurrentOwnedCryptoId(to: ownedCryptoId)
        
        ObvMessengerInternalNotification.metaFlowControllerDidSwitchToOwnedIdentity(ownedCryptoId: ownedCryptoId)
            .postOnDispatchQueue()
    }
    
}


// MARK: OlvidURLHandler

extension MetaFlowController {

    func handleOlvidURL(_ olvidURL: OlvidURL) async {
        // If the OlvidURL is an openId redirect, we handle it immediately.
        // Otherwise, we passe it down to the olvidURLHandler
        if let opendIdRedirectURL = olvidURL.isOpenIdRedirectWithURL {
            do {
                _ = try await KeycloakManagerSingleton.shared.resumeExternalUserAgentFlow(with: opendIdRedirectURL)
                os_log("Successfully resumed the external user agent flow", log: Self.log, type: .info)
            } catch {
                os_log("Failed to resume external user agent flow: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
        } else {
            if let olvidURLHandler = self.presentedViewController as? OlvidURLHandler {
                // When the onboarding is presented (e.g., to create a second profile), this allows to pass any scanned URL to it (in particular, keycloak configurations)
                await olvidURLHandler.handleOlvidURL(olvidURL)
            } else {
                guard let olvidURLHandler = self.children.compactMap({ $0 as? OlvidURLHandler }).first else { assertionFailure(); return }
                await olvidURLHandler.handleOlvidURL(olvidURL)
            }
        }
    }

}


// MARK: - Refreshing the view context on certain Core Data notifications


extension MetaFlowController {
    
    @MainActor
    private func refreshViewContextsRegisteredObjectsOnUpdateOfPersistedObvContactIdentity(with contactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>) async {
        guard let contact = ObvStack.shared.viewContext.registeredObject(for: contactObjectID.objectID) as? PersistedObvContactIdentity else { return }
        ObvStack.shared.viewContext.refresh(contact, mergeChanges: true)
        guard let oneToOneDiscussionObjectID = contact.oneToOneDiscussion?.objectID else { return }
        guard let oneToOneDiscussion = ObvStack.shared.viewContext.registeredObject(for: oneToOneDiscussionObjectID) as? PersistedOneToOneDiscussion else { return }
        ObvStack.shared.viewContext.refresh(oneToOneDiscussion, mergeChanges: true)
    }
 
    
    @MainActor
    private func refreshViewContextsRegisteredObjectsOnUpdateOfFyleMessageJoinWithStatus(with fyleMessageJoinObjectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>) async {
        guard let join = ObvStack.shared.viewContext.registeredObject(for: fyleMessageJoinObjectID.objectID) as? FyleMessageJoinWithStatus else { return }
        ObvStack.shared.viewContext.refresh(join, mergeChanges: true)
        guard let messageObjectID = join.message?.objectID else { return }
        guard let message = ObvStack.shared.viewContext.registeredObject(for: messageObjectID) as? PersistedMessage else { return }
        ObvStack.shared.viewContext.refresh(message, mergeChanges: true)
    }
    
}


// MARK: - Errors

extension MetaFlowController {
    
    enum ObvError: LocalizedError {
        case couldNotFindOwnedIdentity
        case couldNotCompressImage
        case theAppBackupDelegateIsNotSet
        case ckAccountStatusError(title: String, message: String?)
        case installedOlvidAppIsOutdated
        case storeKitDelegateIsNil
        case metaFlowControllerDelegateIsNil
        case userCancelled
        case groupTypeIsNil
        case unexpectedGroupMemberPermissions
        case couldNotDetermineGroupMemberPermissions
        case noDeviceBackupFoundForThisBackupSeed
        case osUpgradeRequired
        
        var errorDescription: String? {
            switch self {
            case .couldNotFindOwnedIdentity:
                return "Could not find owned identity"
            case .couldNotCompressImage:
                return "Could not compress image"
            case .theAppBackupDelegateIsNotSet:
                return "The app backup delegate is not set"
            case .ckAccountStatusError(title: let title, message: _):
                return title
            case .installedOlvidAppIsOutdated:
                return "The installed Olvid App is outdated"
            case .storeKitDelegateIsNil:
                return "The store kit delegate is nil"
            case .metaFlowControllerDelegateIsNil:
                return "Meta flow controller delegate is nil"
            case .userCancelled:
                return "User cancelled"
            case .groupTypeIsNil:
                return "The group type is nil"
            case .unexpectedGroupMemberPermissions:
                return "Unexpected group member permissions"
            case .couldNotDetermineGroupMemberPermissions:
                return "Could not determine group member permissions"
            case .noDeviceBackupFoundForThisBackupSeed:
                return "No device backup found for this backup seed"
            case .osUpgradeRequired:
                return "OS upgrade required"
            }
        }
        
        var recoverySuggestion: String? {
            switch self {
            case .couldNotFindOwnedIdentity:
                return nil
            case .couldNotCompressImage:
                return nil
            case .theAppBackupDelegateIsNotSet:
                return nil
            case .ckAccountStatusError(_, let message):
                return message
            case .installedOlvidAppIsOutdated:
                return nil
            case .storeKitDelegateIsNil:
                return nil
            case .metaFlowControllerDelegateIsNil:
                return nil
            case .userCancelled:
                return nil
            case .groupTypeIsNil:
                return nil
            case .unexpectedGroupMemberPermissions:
                return nil
            case .couldNotDetermineGroupMemberPermissions:
                return nil
            case .noDeviceBackupFoundForThisBackupSeed:
                return nil
            case .osUpgradeRequired:
                return nil
            }
        }
        
    }
    
}


// MARK: - Private helpers for subscriptions

extension MetaFlowController {
    
    /// This is called when the user taps the "refresh" button on her own identity screen and when a new owned identity is inserted in the app database.
    /// This method request the current subscriptions to store
    /// kit. If a valid subscription is found, it associated to each owned identity present on this device by contacting Olvid's servers.
    /// Then, if there is a "current" owned identity, we refresh the permissions by requesting them from Olvid's servers.
    func refreshSubscriptionStatus() async throws -> [ObvSubscription.StoreKitDelegatePurchaseResult] {
        guard let storeKitDelegate else { assertionFailure(); throw ObvError.storeKitDelegateIsNil }
        let results = try await storeKitDelegate.userWantsToRefreshSubscriptionStatus()
        if let currentOwnedCryptoId {
            _ = try await obvEngine.refreshAPIPermissions(of: currentOwnedCryptoId)
        }
        return results
    }

}


// MARK: - Various helpers for new backups

extension MetaFlowController {
    
    /// This method can be called from the onboarding, the backup setup, or from the settings, when the user taps
    /// on the button (bellow the displayed device backup key) indicating that she wants to be reminded about writing down
    /// the backup key.
    private func userWantsToBeRemindedToWriteDownBackupKey() async {
        ObvMessengerSettings.Backup.dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey = .now
    }
    
}


// MARK: - Helpers for relaying backup profiles

fileprivate extension ObvListOfDeviceBackupProfiles {
    
    convenience init(deviceBackupFromServer: ObvDeviceBackupFromServer) async {
        
        var profiles = [ObvListOfDeviceBackupProfiles.Profile]()
        for deviceBackupFromServerProfile in deviceBackupFromServer.profiles {
            let customDisplayName: String?
            if let appDeviceSnapshotNode = deviceBackupFromServer.appNode as? AppDeviceSnapshotNode {
                customDisplayName = appDeviceSnapshotNode.getCustomDisplayNameForOwnedCryptoId(deviceBackupFromServerProfile.ownedCryptoId)
            } else {
                customDisplayName = nil
                assertionFailure("Unexpected app node")
            }
            let profile = await ObvListOfDeviceBackupProfiles.Profile(deviceBackupFromServerProfile: deviceBackupFromServerProfile, customDisplayName: customDisplayName)
            profiles.append(profile)
        }
        
        self.init(profiles: profiles)
        
    }
    
}

fileprivate extension ObvListOfDeviceBackupProfiles.Profile {
 
    convenience init(deviceBackupFromServerProfile: ObvDeviceBackupFromServer.Profile, customDisplayName: String?) async {
        let ownedCryptoId = deviceBackupFromServerProfile.ownedCryptoId
        let coreDetails = deviceBackupFromServerProfile.coreDetails
        let isOnDevice = await (try? Self.isOnThisDevice(ownedCryptoId: ownedCryptoId)) ?? false
        self.init(ownedCryptoId: ownedCryptoId,
                  coreDetails: coreDetails,
                  customDisplayName: customDisplayName,
                  isOnThisDevice: isOnDevice,
                  profileBackupSeed: deviceBackupFromServerProfile.backupSeed,
                  showGreenShield: deviceBackupFromServerProfile.isKeycloakManaged,
                  encodedPhotoServerKeyAndLabel: deviceBackupFromServerProfile.encodedPhotoServerKeyAndLabel)
    }
    
    
    private static func isOnThisDevice(ownedCryptoId: ObvCryptoId) async throws -> Bool {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    let isOnDevice = (try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: context)) != nil
                    return continuation.resume(returning: isOnDevice)
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
    
}


// MARK: - Helper function for hiding backup profiles of profiles hidden on this device

extension MetaFlowController {
    
    private func filterOutProfilesHiddenOnThisDevice(currentOwnedCryptoId: ObvCryptoId, profiles: ObvListOfDeviceBackupProfiles) async -> ObvListOfDeviceBackupProfiles {
        
        var ownedCryptoIdsToHide = await getAllHiddenOwnedIdentities()
        ownedCryptoIdsToHide.remove(currentOwnedCryptoId) // The current owned identity can be shown, even if it's a hidden owned identity
        
        if ownedCryptoIdsToHide.isEmpty {
            return profiles
        } else {
            return .init(profiles: profiles.profiles.filter({ !ownedCryptoIdsToHide.contains($0.ownedCryptoId) }))
        }
        
    }
    
    
    /// Helper function for `filterOutProfilesHiddenOnThisDevice(profiles:)`.
    private func getAllHiddenOwnedIdentities() async -> Set<ObvCryptoId> {
        return await withCheckedContinuation { (continuation: CheckedContinuation<Set<ObvCryptoId>, Never>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    let ownedCryptoIds = try PersistedObvOwnedIdentity.getAllHiddenOwnedIdentities(within: context).map({ $0.cryptoId })
                    return continuation.resume(returning: Set(ownedCryptoIds))
                } catch {
                    assertionFailure()
                    return continuation.resume(returning: [])
                }
            }
        }
    }
    
}


// MARK: - Helper functions for subscriptions and implementing SubscriptionPlansViewDismissActionsProtocol

extension MetaFlowController: SubscriptionPlansViewDismissActionsProtocol {
    
    private func userWantsToSubscribeOlvidPlus(ownedCryptoId: ObvCryptoId) {
        let model = SubscriptionPlansViewModel(
            ownedCryptoId: ownedCryptoId,
            showFreePlanIfAvailable: true)
        let vc = SubscriptionPlansHostingView(model: model, actions: self, dismissActions: self)
        if let presentedViewController = self.presentedViewController {
            presentedViewController.present(vc, animated: true)
        } else {
            self.present(vc, animated: true)
        }
    }

    
    func userWantsToDismissSubscriptionPlansView() async {
        presentedViewController?.dismiss(animated: true)
        await processOnboardingContinuationIfRequired()
    }
    
    
    func dismissSubscriptionPlansViewAfterPurchaseWasMade() async {
        presentedViewController?.dismiss(animated: true)
        await processOnboardingContinuationIfRequired()
    }
    
    
    private func processOnboardingContinuationIfRequired() async {
        guard let (continuation, ownedCryptoIdentity) = self.continuationAndOwnedCryptoIdentity else { return }
        self.continuationAndOwnedCryptoIdentity = nil
        do {
            let consequence = try await getDeviceDeactivationConsequencesOfRestoringBackup(ownedCryptoIdentity: ownedCryptoIdentity)
            return continuation.resume(returning: consequence)
        } catch {
            return continuation.resume(throwing: error)
        }
                
    }
            
}


// MARK: - Helper allowing to capture an avatar using the camera, the photo library, or the files app

extension MetaFlowController {
    
    private func userWantsObtainAvatar(avatarSource: ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {

        removeAnyPreviousContinuation()
        
        switch avatarSource {
            
        case .camera:
            
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return nil }
            
            let picker = UIImagePickerController()
            picker.delegate = self
            picker.allowsEditing = false
            picker.sourceType = .camera
            picker.cameraDevice = .front

            let imageFromPicker = await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
                self.continuationsForObtainingAvatar = continuation
                if let presentedViewController = self.presentedViewController {
                    presentedViewController.present(picker, animated: true)
                } else {
                    present(picker, animated: true)
                }
            }

            guard let imageFromPicker else { return nil }
            
            let resizedImage = await resizeImageFromPicker(imageFromPicker: imageFromPicker)
            
            return resizedImage

        case .photoLibrary:
            
            guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else { return nil }

            var configuration = PHPickerConfiguration()
            configuration.selectionLimit = 1
            configuration.filter = .images
            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = self
            
            let imageFromPicker = await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
                self.continuationsForObtainingAvatar = continuation
                self.presentOnTop(picker, animated: true)
            }
            
            guard let imageFromPicker else { return nil }
            
            let resizedImage = await resizeImageFromPicker(imageFromPicker: imageFromPicker)
            
            return resizedImage

        case .files:
            
            let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.jpeg, .png], asCopy: true)
            documentPicker.delegate = self
            documentPicker.allowsMultipleSelection = false
            documentPicker.shouldShowFileExtensions = false

            let imageFromPicker = await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
                self.continuationsForObtainingAvatar = continuation
                self.presentOnTop(documentPicker, animated: true)
            }

            guard let imageFromPicker else { return nil }

            let resizedImage = await resizeImageFromPicker(imageFromPicker: imageFromPicker)
            
            return resizedImage
        }
        
    }
    
    private func removeAnyPreviousContinuation() {
        if let continuationsForObtainingAvatar {
            continuationsForObtainingAvatar.resume(returning: nil)
            self.continuationsForObtainingAvatar = nil
        }
    }


    // Resizing the photos received from the camera or the photo library
    
    private func resizeImageFromPicker(imageFromPicker: UIImage) async -> UIImage? {
        
        let imageEditor = ObvImageEditorViewController(originalImage: imageFromPicker,
                                                       showZoomButtons: ObvAppCoreConstants.targetEnvironmentIsMacCatalyst,
                                                       maxReturnedImageSize: (1024, 1024),
                                                       delegate: self)
        
        removeAnyPreviousContinuation()

        let resizedImage = await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            self.continuationsForObtainingAvatar = continuation
            self.presentOnTop(imageEditor, animated: true)
        }
        
        return resizedImage

    }

}


// MARK: - Implementing ObvImageEditorViewControllerDelegate (used when resizing an avatar)

extension MetaFlowController: ObvImageEditorViewControllerDelegate {
    
    func userCancelledImageEdition(_ imageEditor: ObvImageEditorViewController) async {
        imageEditor.dismiss(animated: true)
        guard let continuationsForObtainingAvatar else { assertionFailure(); return }
        self.continuationsForObtainingAvatar = nil
        continuationsForObtainingAvatar.resume(returning: nil)
    }

    
    func userConfirmedImageEdition(_ imageEditor: ObvImageEditorViewController, image: UIImage) async {
        imageEditor.dismiss(animated: true)
        guard let continuationsForObtainingAvatar else { assertionFailure(); return }
        self.continuationsForObtainingAvatar = nil
        continuationsForObtainingAvatar.resume(returning: image)
    }

}


// MARK: - Implementing UIDocumentPickerDelegate (used as when choosing a photo from the files app for an avatar)

extension MetaFlowController: UIDocumentPickerDelegate {
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        
        controller.dismiss(animated: true)
        guard let continuationsForObtainingAvatar else { assertionFailure(); return }
        self.continuationsForObtainingAvatar = nil
        guard let url = urls.first else { return continuationsForObtainingAvatar.resume(returning: nil) }

        let needToCallStopAccessingSecurityScopedResource = url.startAccessingSecurityScopedResource()
                
        let image = UIImage(contentsOfFile: url.path)

        if needToCallStopAccessingSecurityScopedResource {
            url.stopAccessingSecurityScopedResource()
        }

        return continuationsForObtainingAvatar.resume(returning: image)

    }
    
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        
        controller.dismiss(animated: true)
        guard let continuationsForObtainingAvatar else { return }
        self.continuationsForObtainingAvatar = nil
        continuationsForObtainingAvatar.resume(returning: nil)
        
    }

}

// MARK: - Implementing PHPickerViewControllerDelegate (used as when choosing a photo from the library for an avatar)

extension MetaFlowController: PHPickerViewControllerDelegate {
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let continuationsForObtainingAvatar else { assertionFailure(); return }
        self.continuationsForObtainingAvatar = nil
        if results.count == 1, let result = results.first {
            result.itemProvider.loadObject(ofClass: UIImage.self) { item, error in
                guard error == nil else {
                    continuationsForObtainingAvatar.resume(returning: nil)
                    return
                }
                guard let image = item as? UIImage else {
                    continuationsForObtainingAvatar.resume(returning: nil)
                    return
                }
                continuationsForObtainingAvatar.resume(returning: image)
            }
        } else {
            continuationsForObtainingAvatar.resume(with: .success(nil))
        }
    }

}


// MARK: - Implementing UIImagePickerControllerDelegate (used as when taking a photo for an avatar)

extension MetaFlowController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
 
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        assert(Thread.isMainThread)
        picker.dismiss(animated: true)
        guard let continuationsForObtainingAvatar else { assertionFailure(); return }
        self.continuationsForObtainingAvatar = nil
        let image = info[.originalImage] as? UIImage
        continuationsForObtainingAvatar.resume(returning: image)
    }
    
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        assert(Thread.isMainThread)
        picker.dismiss(animated: true)
        guard let continuationsForObtainingAvatar else { assertionFailure(); return }
        self.continuationsForObtainingAvatar = nil
        continuationsForObtainingAvatar.resume(returning: nil)
    }

}


// MARK: - Internal helper pour fetch avatars during onboarding and settings, while showing profile backups that can be restored

private actor AvatarHelper {
    
    let obvEngine: ObvEngine
    
    init(obvEngine: ObvEngine) {
        self.obvEngine = obvEngine
    }
    
    private var cache = NSCache<NSData, UIImage>()
    
    private var cacheOfLocalImages = NSCache<NSURL, UIImage>()
    
    func fetchAvatarImage(ownedCryptoId: ObvTypes.ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, size: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        
        let frameSizeInPixels = await size.frameSizeInPixels
        
        // Try to fetch the image from the local app database
        if let image = try await fetchAvatarImageOfPersistedObvOwnedIdentity(ownedCryptoId: ownedCryptoId) {
            let thumbnail = image.preparingThumbnail(of: frameSizeInPixels)
            return thumbnail
        }
        
        if let image = cache.object(forKey: ownedCryptoId.getIdentity() as NSData) {
            let thumbnail = image.preparingThumbnail(of: frameSizeInPixels)
            return thumbnail
        }

        // Forward the request to the engine, so as to fetch the image from the server
        if let imageData = try await obvEngine.getUserDataNow(ownedCryptoId: ownedCryptoId, encodedServerKeyAndLabel: encodedPhotoServerKeyAndLabel), let image = UIImage(data: imageData) {
            self.cache.setObject(image, forKey: ownedCryptoId.getIdentity() as NSData, cost: imageData.count)
            let thumbnail = image.preparingThumbnail(of: frameSizeInPixels)
            return thumbnail
        }
                
        return nil
        
    }
    
    /// Appropriate function to call to fetch an avatar image (for an owned identity, a contact, a group member, a group, ...), when the local URL of the photo is known.
    func fetchAvatarImage(localPhotoURL: URL, size: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        
        let image: UIImage
        
        if let cachedImage = cacheOfLocalImages.object(forKey: localPhotoURL as NSURL) {
            image = cachedImage
        } else {
            let data = try Data(contentsOf: localPhotoURL)
            guard let imageFromDisk = UIImage(data: data) else { return nil }
            cacheOfLocalImages.setObject(imageFromDisk, forKey: localPhotoURL as NSURL, cost: data.count)
            image = imageFromDisk
        }
        
        let frameSizeInPixels = await size.frameSizeInPixels
        let thumbnail = image.preparingThumbnail(of: frameSizeInPixels)
        return thumbnail
        
    }
    

    /// Helper function for `fetchAvatarImage(_:ownedCryptoId:)`. It allows to fetch an return an avatar photo for the owned identity asynchronously.
    private func fetchAvatarImageOfPersistedObvOwnedIdentity(ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> UIImage? {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage?, any Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: context) else {
                        return continuation.resume(returning: nil)
                    }
                    guard let photoURL = ownedIdentity.photoURL else {
                        return continuation.resume(returning: nil)
                    }
                    let data = try Data(contentsOf: photoURL)
                    let image = UIImage(data: data)
                    return continuation.resume(returning: image)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }

}


// MARK: - Observing the app database

extension MetaFlowController: PersistedObvOwnedIdentityObserver {
    
    func aPersistedObvOwnedIdentityWasDeleted(ownedCryptoId: ObvCryptoId) async {
        do {
            try await setupAndShowAppropriateChildViewControllers(ownedCryptoIdGeneratedDuringOnboarding: nil)
        } catch {
            assertionFailure()
        }
    }
    
    
    func newPersistedObvOwnedIdentity(ownedCryptoId: ObvTypes.ObvCryptoId, isActive: Bool) async {
        // When a new owned identity is created, we refresh the subscriptions to make sure any existing valid subscription
        // is immediately associated to this new owned identity
        do {
            let results = try await refreshSubscriptionStatus()
            var aSubscriptionIfValidOnServer = false
            for result in results {
                switch result {
                case .purchaseSucceeded(let serverVerificationResult):
                    switch serverVerificationResult {
                    case .succeededAndSubscriptionIsValid:
                        aSubscriptionIfValidOnServer = true
                    case .succeededButSubscriptionIsExpired,
                            .failed:
                        continue
                    }
                case .userCancelled,
                        .pending,
                        .expired,
                        .revoked:
                    continue
                }
            }
            if aSubscriptionIfValidOnServer {
                Self.logger.info("A valid subscription was found and was re-associated to all owned identities")
            } else {
                Self.logger.info("No valid subscription found")
            }
        } catch {
            Self.logger.fault("Could not refresh subscription status after the insertion of a new owned identity: \(error)")
            assertionFailure()
        }
    }
    
    
    func aPersistedObvOwnedIdentityIsHiddenChanged(ownedCryptoId: ObvTypes.ObvCryptoId, isHidden: Bool) async {
        // This observer does nothing
    }
    
    func previousBackedUpDeviceSnapShotIsObsoleteAsPersistedObvOwnedIdentityChanged() async {
        do {
            try await obvEngine.previousBackedUpDeviceSnapShotIsObsolete()
        } catch {
            Self.logger.fault("Failed to schedule device backup: \(error)")
            assertionFailure()
        }
    }
    
    func previousBackedUpProfileSnapShotIsObsoleteAsPersistedObvOwnedIdentityChanged(ownedCryptoId: ObvCryptoId) async {
        do {
            try await obvEngine.previousBackedUpProfileSnapShotIsObsoleteAsOwnedIdentityChangedWithinApp(ownedCryptoId: ownedCryptoId)
        } catch {
            Self.logger.fault("Failed to schedule profile backup: \(error)")
            assertionFailure()
        }
    }

}


extension MetaFlowController: PersistedObvContactIdentityObserver {
    
    func previousBackedUpProfileSnapShotIsObsoleteAsPersistedObvContactIdentityChanged(ownedCryptoId: ObvTypes.ObvCryptoId) async {
        do {
            try await obvEngine.previousBackedUpProfileSnapShotIsObsoleteAsOwnedIdentityChangedWithinApp(ownedCryptoId: ownedCryptoId)
        } catch {
            Self.logger.fault("Failed to schedule profile backup: \(error)")
            assertionFailure()
        }
    }
    
}


extension MetaFlowController: PersistedContactGroupObserver {
    
    func previousBackedUpProfileSnapShotIsObsoleteAsPersistedContactGroupChanged(ownedCryptoId: ObvTypes.ObvCryptoId) async {
        do {
            try await obvEngine.previousBackedUpProfileSnapShotIsObsoleteAsOwnedIdentityChangedWithinApp(ownedCryptoId: ownedCryptoId)
        } catch {
            Self.logger.fault("Failed to schedule profile backup: \(error)")
            assertionFailure()
        }
    }
    
}


extension MetaFlowController: PersistedGroupV2Observer {
    
    func previousBackedUpProfileSnapShotIsObsoleteAsPersistedGroupV2Changed(ownedCryptoId: ObvTypes.ObvCryptoId) async {
        do {
            try await obvEngine.previousBackedUpProfileSnapShotIsObsoleteAsOwnedIdentityChangedWithinApp(ownedCryptoId: ownedCryptoId)
        } catch {
            Self.logger.fault("Failed to schedule profile backup: \(error)")
            assertionFailure()
        }
    }
    
}


extension MetaFlowController: PersistedDiscussionLocalConfigurationObserver {
    
    func aPersistedDiscussionLocalConfigurationWasUpdated(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, value: ObvUICoreData.PersistedDiscussionLocalConfigurationValue) async {
        // We do nothing in this observer
    }
    
    func previousBackedUpProfileSnapShotIsObsoleteAsPersistedDiscussionLocalConfigurationChanged(ownedCryptoId: ObvTypes.ObvCryptoId) async {
        do {
            try await obvEngine.previousBackedUpProfileSnapShotIsObsoleteAsOwnedIdentityChangedWithinApp(ownedCryptoId: ownedCryptoId)
        } catch {
            Self.logger.fault("Failed to schedule profile backup: \(error)")
            assertionFailure()
        }
    }
    
}


extension MetaFlowController: PersistedDiscussionSharedConfigurationObserver {
    
    func previousBackedUpProfileSnapShotIsObsoleteAsPersistedDiscussionSharedConfigurationChanged(ownedCryptoId: ObvTypes.ObvCryptoId) async {
        do {
            try await obvEngine.previousBackedUpProfileSnapShotIsObsoleteAsOwnedIdentityChangedWithinApp(ownedCryptoId: ownedCryptoId)
        } catch {
            Self.logger.fault("Failed to schedule profile backup: \(error)")
            assertionFailure()
        }
    }
    
}


extension MetaFlowController: PersistedDiscussionObserver {
    
    func aPersistedDiscussionWasInsertedOrReactivated(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier) async {
        // This observer does nothing
    }
    
    func aPersistedDiscussionStatusChanged(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, status: ObvUICoreData.PersistedDiscussion.Status) async {
        // This observer does nothing
    }
    
    func aPersistedDiscussionIsArchivedChanged(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, isArchived: Bool) async {
        // This observer does nothing
    }
    
    func aPersistedDiscussionWasDeleted(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier) async {
        // This observer does nothing
    }
    
    func aPersistedDiscussionWasRead(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, localDateWhenDiscussionRead: Date) async {
        // This observer does nothing
    }
    
    
    func previousBackedUpProfileSnapShotIsObsoleteAsPersistedDiscussionChanged(ownedCryptoId: ObvTypes.ObvCryptoId) async {
        do {
            try await obvEngine.previousBackedUpProfileSnapShotIsObsoleteAsOwnedIdentityChangedWithinApp(ownedCryptoId: ownedCryptoId)
        } catch {
            Self.logger.fault("Failed to schedule profile backup: \(error)")
            assertionFailure()
        }
    }
    
}
