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
import OSLog
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
import ObvPollFeature
import ObvLicenceActivationFlow
import ObvOwnedIdentityChooser
import ObvSharedDataSources
import ObvInvitationFlow
import ObvCells
import ObvUIGroupSharedBetweenV1AndV2
import ObvSingleOwnedIdentity


// MARK: - MetaFlowControllerDelegate

@MainActor
protocol MetaFlowControllerDelegate: AnyObject {
    func userRequestedAppDatabaseSyncWithEngine(metaFlowController: MetaFlowController) async throws
    func userWantsToSendDraft(_ metaFlowController: MetaFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, textBody: String, mentions: Set<MessageJSON.UserMention>) async throws
    func userWantsToAddAttachmentsToDraft(_ metaFlowController: MetaFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, itemProviders: [NSItemProvider], source: LoadItemProviderHelper.ItemProviderProviderSource) async throws -> [LoadedItemProviderToPaste]
    func userWantsToAddAttachmentsToDraftFromURLs(_ metaFlowController: MetaFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, urls: [URL]) async throws
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
    func userWantsToUpdatePollVote(_ metaFlowController: MetaFlowController, ownedCryptoId: ObvCryptoId, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, pollVoteCandidateUuid: UUID, voted: Bool, version: Int) async throws
    func userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice(_ metaFlowController: MetaFlowController) async throws
    func userWantsToStopSharingLocationInDiscussion(_ metaFlowController: MetaFlowController, discussionIdentifier: ObvDiscussionIdentifier) async throws
    func userWantsToReplaceTrustedDetailsByPublishedDetails(_ metaFlowController: MetaFlowController, groupIdentifier: ObvGroupV2Identifier) async throws
    func userWantsToDeleteOwnedIdentityAndHasConfirmed(_ metaFlowController: MetaFlowController, ownedCryptoId: ObvCryptoId, globalOwnedIdentityDeletion: Bool) async throws
    
    func userWantsToShowMapToSendOrShareLocationContinuously(_ metaFlowController: MetaFlowController, presentingViewController: UIViewController, discussionIdentifier: ObvDiscussionIdentifier) async throws
    func userWantsToCreatePoll(_ metaFlowController: MetaFlowController, presentingViewController: UIViewController, discussionIdentifier: ObvDiscussionIdentifier) async throws
    func userWantsToMarkAllMessagesAsReadInDiscussion(_ metaFlowController: MetaFlowController, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) async throws
    func userWantsToReorderPinnedDiscussions(_ metaFlowController: MetaFlowController, ownedCryptoId: ObvCryptoId, objectIDOfPinnedDiscussions: [TypeSafeManagedObjectID<PersistedDiscussion>]) async throws

    func userWantsToArchiveDiscussions(_ metaFlowController: MetaFlowController, discussionObjectIDs: [TypeSafeManagedObjectID<PersistedDiscussion>]) async throws
    func userWantsToUnarchiveDiscussions(_ metaFlowController: MetaFlowController, discussionObjectIDs: [TypeSafeManagedObjectID<PersistedDiscussion>]) async throws

    func userWantsToDeleteDiscussionsAndHasConfirmed(_ metaFlowController: MetaFlowController, discussionObjectIDs: [TypeSafeManagedObjectID<PersistedDiscussion>], deletionType: DeletionType) async throws
    func userWantsToProcessReceiptsStoredForLater(_ metaFlowController: MetaFlowController, ownedCryptoId: ObvCryptoId, returnReceiptElements: Set<ObvReturnReceiptElements>) async
    
    @MainActor
    func presentAlertAsOsUpgradeIsRequired(_ metaFlowController: MetaFlowController, presentingViewController: UIViewController)

    func userWantsToUpdatePersonalNote(_ metaFlowController: MetaFlowController, with newText: String?, about: PersonalNoteEditorView.Model.About) async throws
    func userDidSeeNewDetailsOfContact(_ metaFlowController: MetaFlowController, contactIdentifier: ObvTypes.ObvContactIdentifier)

    func freshContactIdentityReceivedWhileShowingSingleContactView(_ metaFlowController: MetaFlowController, contactIdentity: ObvContactIdentity) async

    func userHasSeenPublishedDetails(_ metaFlowController: MetaFlowController, publishedDetails: PublishedDetailsValidationViewModel) async throws

    func userWantsToHideOwnedIdentity(_ metaFlowController: MetaFlowController, ownedCryptoId: ObvCryptoId, password: String) async throws
    func userWantsToUnhideOwnedIdentity(_ metaFlowController: MetaFlowController, ownedCryptoId: ObvCryptoId) async throws

    func userWantsToUpdateOwnedCustomDisplayName(_ metaFlowController: MetaFlowController, ownedCryptoId: ObvTypes.ObvCryptoId, newCustomDisplayName: String?) async throws

}


@MainActor
final class MetaFlowController: UIViewController {
    
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

    private let userDefaults = UserDefaults(suiteName: ObvAppCoreConstants.appGroupIdentifier)

    // Shall only be accessed on the main thread
    private var automaticallyNavigateToCreatedDisplayedContactGroup = false
    
    private let obvEngine: ObvEngine
    
    /// This is used during the onboarding flow, when the user wants to see the subscription to Olvid+
    private var continuationAndOwnedCryptoIdentity: (continuation: CheckedContinuation<ObvAppBackup.ObvDeviceDeactivationConsequence, any Error>, ownedCryptoIdentity: ObvOwnedCryptoIdentity)?
    
    private var continuationsForObtainingAvatar: CheckedContinuation<UIImage?, Never>?
    
    private let localOwnedIdentityChooserViewControllerDelegate = LocalOwnedIdentityChooserViewControllerDelegate()
    
    private let localAvatarViewAppDataSource: LocalAvatarViewAppDataSource
    private let localObvSingleContactViewAppDataSourceDelegate: LocalObvSingleContactViewAppDataSourceDelegateImplementation
    private let localLicenseActivationViewControllerAppDataSourceDelegate: LocalNewLicenseActivationViewControllerAppDataSourceDelegate
    private let localTrustOriginsListViewAppDataSourceDelegate: LocalTrustOriginsListViewAppDataSourceDelegate
    private let localSingleGroupV1MainViewAppDataSourceDelegate: LocalSingleGroupV1MainViewAppDataSourceDelegate
    private let localEditGroupNameAndPictureViewAppDataSourceDelegate: LocalEditGroupNameAndPictureViewAppDataSourceDelegate
    private let localChooseDeviceToReactivateViewAppDataSourceDelegate: LocalChooseDeviceToReactivateViewAppDataSourceDelegate
    private let localOwnedDetailedInfosViewAppDataSourceDelegate: LocalOwnedDetailedInfosViewAppDataSourceDelegate
        
    private let dataSources: ObvDataSources
    
    init(obvEngine: ObvEngine,
         createPasscodeDelegate: CreatePasscodeDelegate,
         localAuthenticationDelegate: LocalAuthenticationDelegate,
         appBackupDelegate: AppBackupDelegate,
         storeKitDelegate: StoreKitDelegate,
         metaFlowControllerDelegate: MetaFlowControllerDelegate,
         shouldShowCallBanner: Bool) {
        
        self.obvEngine = obvEngine
        self.createPasscodeDelegate = createPasscodeDelegate
        self.localAuthenticationDelegate = localAuthenticationDelegate
        self.appBackupDelegate = appBackupDelegate
        self.storeKitDelegate = storeKitDelegate
        self.metaFlowControllerDelegate = metaFlowControllerDelegate
        self.localAvatarViewAppDataSource = LocalAvatarViewAppDataSource(obvEngine: obvEngine)
        self.localObvSingleContactViewAppDataSourceDelegate = .init(engine: obvEngine)
        self.localLicenseActivationViewControllerAppDataSourceDelegate = .init(engine: obvEngine)
        self.localTrustOriginsListViewAppDataSourceDelegate = .init(engine: obvEngine)
        self.localSingleGroupV1MainViewAppDataSourceDelegate = .init(engine: obvEngine)
        self.localEditGroupNameAndPictureViewAppDataSourceDelegate = .init(engine: obvEngine)
        self.localChooseDeviceToReactivateViewAppDataSourceDelegate = .init(engine: obvEngine)
        self.localOwnedDetailedInfosViewAppDataSourceDelegate = .init(engine: obvEngine)
        self.dataSources = .init(avatarViewAppDataSourceDelegate: localAvatarViewAppDataSource,
                                 singleContactViewAppDataSourceDelegate: localObvSingleContactViewAppDataSourceDelegate,
                                 licenseActivationViewControllerAppDataSourceDelegate: localLicenseActivationViewControllerAppDataSourceDelegate,
                                 trustOriginsListViewAppDataSourceDelegate: localTrustOriginsListViewAppDataSourceDelegate,
                                 singleGroupV1MainViewAppDataSourceDelegate: localSingleGroupV1MainViewAppDataSourceDelegate,
                                 editGroupNameAndPictureViewAppDataSourceDelegate: localEditGroupNameAndPictureViewAppDataSourceDelegate,
                                 chooseDeviceToReactivateViewAppDataSourceDelegate: localChooseDeviceToReactivateViewAppDataSourceDelegate,
                                 ownedDetailedInfosViewAppDataSourceDelegate: localOwnedDetailedInfosViewAppDataSourceDelegate,
                                 obvEngine: obvEngine,
                                 backgroundContext: ObvStack.shared.newBackgroundContext(),
                                 viewContext: ObvStack.shared.viewContext)
        
        super.init(nibName: nil, bundle: nil)
        
        localObvSingleContactViewAppDataSourceDelegate.delegate = self
        
        // If the RootViewController indicates that there is a call in progress, show the call banner.
        // This happens when the app was force quitted before receiving a CallKit incoming call. In that case,
        // if the user launches the app from the CallKit UI, this MetFlowController is not instantiated during launch
        // as the in-hous call view is shown instead. As a consequence, this MetaFlowController did not receive the
        // notification about the call. So we need to have the information about this call at init time.
        
        shouldShowCallBannerOnViewDidLoad = shouldShowCallBanner
                
        observeDidBecomeActiveNotifications()
        
        // Internal notifications
        
        observeUserTriedToAccessCameraButAccessIsDeniedNotifications()
        observeUserWantsToIntroduceContactToAnotherContactNotifications()
        observeOutgoingCallFailedBecauseUserDeniedRecordPermissionNotifications()
        observeVoiceMessageFailedBecauseUserDeniedRecordPermissionNotifications()
        observeRejectedIncomingCallBecauseUserDeniedRecordPermissionNotifications()
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
            await PersistedGroupV2.addObvObserver(self)
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
        self.presentOnTop(alert, animated: true)
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
                if await NewAppStateManager.shared.olvidURLRouter == nil {
                    await NewAppStateManager.shared.setOlvidURLRouter(to: _self)
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
                    storeKitDelegate: storeKitDelegate,
                    dataSources: self.dataSources,
                    actions: self)
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
                    dataSource: self,
                    olvidShopViewActions: self,
                    olvidShopViewDataSources: self.dataSources.olvidShopViewDataSources)
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
            case .configuration(let configurationKind):
                switch configurationKind {
                case .keycloakConfig(let keycloakConfig):
                    return .init(keycloakConfiguration: keycloakConfig)
                case .serverAndAPIKey, .betaConfiguration:
                    assertionFailure()
                    return nil
                }
            case .invitation, .mutualScan, .openIdRedirect:
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


// MARK: - Implementing OlvidShopViewActions

extension MetaFlowController: OlvidShopViewActions {
    
    func refreshSubscriptionStatus() async throws {
        guard let storeKitDelegate else { throw ObvError.storeKitDelegateIsNil }
        _ = try await storeKitDelegate.refreshSubscriptionStatus()
    }
    
    
    func userWantsToBuy(_ view: ObvSubscription.OlvidShopView, product: Product) async throws -> ObvAppTypes.StoreKitDelegatePurchaseResult {
        guard let storeKitDelegate else {
            throw ObvError.storeKitDelegateIsNil
        }
        return try await storeKitDelegate.userWantsToBuy(product)
    }

    func getCurrentActiveSubscriptionPublisher(_ view: ObvSubscription.OlvidShopView) throws -> Published<Product?>.Publisher {
        guard let storeKitDelegate else { assertionFailure(); throw ObvError.storeKitDelegateIsNil }
        return try storeKitDelegate.getCurrentActiveSubscriptionPublisher()
    }

}

// MARK: - Implementing UserTriesToAccessPaidFeatureViewActions

extension MetaFlowController: UserTriesToAccessPaidFeatureViewActions {
    
    func queryServerForFreeTrial(_ view: ObvSubscription.UserTriesToAccessPaidFeatureView, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> Bool {
        try await obvEngine.queryServerForFreeTrial(for: ownedCryptoId)
    }
    
    func startFreeTrial(_ view: ObvSubscription.UserTriesToAccessPaidFeatureView, ownedCryptoId: ObvTypes.ObvCryptoId) async throws {
        try await obvEngine.startFreeTrial(for: ownedCryptoId)
    }
    
    func userWantsToChooseUserToCall(_ view: ObvSubscription.UserTriesToAccessPaidFeatureView, ownedCryptoId: ObvTypes.ObvCryptoId) {
        //ObvMessengerInternalNotification.userWantsToCallOrUpdateCallCapabilityButWeShouldCheckSheIsAllowedTo
        // For now, we simply dismiss the view. We should do better here and present a list of contacts to call
        self.presentedViewController?.dismiss(animated: true)
    }
    
}


// MARK: - Implementing MainFlowViewControllerActions

extension MetaFlowController: MainFlowViewControllerActions {
    
    // Other protocol implementations are enough
    
}

// MARK: - Implementing LocalObvSingleContactViewAppDataSourceDelegateImplementationDelegate

extension MetaFlowController: LocalObvSingleContactViewAppDataSourceDelegateImplementationDelegate {
    
    fileprivate func freshContactIdentityReceivedWhileShowingSingleContactView(_ implementation: LocalObvSingleContactViewAppDataSourceDelegateImplementation, contactIdentity: ObvTypes.ObvContactIdentity) async {
        guard let metaFlowControllerDelegate else { assertionFailure(); return }
        await metaFlowControllerDelegate.freshContactIdentityReceivedWhileShowingSingleContactView(self, contactIdentity: contactIdentity)
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
        return await self.dataSources.fetchAvatarImage(profileCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, frameSize: frameSize)
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
        await self.routeOlvidURL(olvidURL)
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
        Self.logger.info("💰 Will perform an owned device discovery")
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

    
    func onboardingRequiresToRegisterAndUploadOwnedIdentityToKeycloakServer(ownedCryptoId: ObvTypes.ObvCryptoId, keycloakUserIdAndState: (keycloakUserId: String, obvKeycloakState: ObvTypes.ObvKeycloakState)?) async throws {
        try await KeycloakManagerSingleton.shared.uploadOwnIdentity(ownedCryptoId: ownedCryptoId, keycloakUserIdAndState: keycloakUserIdAndState)
    }

    
    func onboardingRequiresKeycloakAuthentication(
        onboardingFlow: NewOnboardingFlowViewController,
        keycloakConfiguration: ObvKeycloakConfiguration,
        keycloakServerKeyAndConfig: (jwks: ObvJWKSet, serviceConfig: OIDServiceConfiguration)
    ) async throws -> (keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff, keycloakState: ObvKeycloakState) {
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
    
    
    /// This method is the last method called by the `NewOnboardingFlowViewController` when it was launched to bind an existing profile to a keycloak server. At the moment it is called,
    /// the existing profile was successfully bound, so there is nothing left to do except to dismiss the onboarding flow.
    func onboardingIsFinished(onboardingFlow: NewOnboardingFlowViewController, existingOwnedCryptoIdBoundToKeycloak: ObvCryptoId) async {
        
        onboardingFlow.dismiss(animated: true)
        
        Self.logger.fault("End of the onboarding flow allowing to bind an existing profile to a keycloak server")
        
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
    /// In this case, we want to present the subscription flow and recalculate the value of `ObvDeviceDeactivationConsequence` when it is dismissed.
    func userWantsToKeepAllDevicesActiveThanksToOlvidPlus(ownedCryptoIdentity: ObvOwnedCryptoIdentity) async throws -> ObvAppBackup.ObvDeviceDeactivationConsequence {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ObvAppBackup.ObvDeviceDeactivationConsequence, any Error>) in
            if let currentContinuation = self.continuationAndOwnedCryptoIdentity?.continuation {
                self.continuationAndOwnedCryptoIdentity = nil
                currentContinuation.resume(throwing: ObvError.userCancelled)
            }
            self.continuationAndOwnedCryptoIdentity = (continuation, ownedCryptoIdentity)
            self.userWantsToSubscribeOlvidPlus()
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


// MARK: - Implementing OlvidShopViewNavigation

extension MetaFlowController: OlvidShopViewNavigation {

    /// This method is called when the user explicitly wants to dismiss the `OlvidShopView`.
    /// After dismissal, the `OlvidShopViewController` delegate’s `olvidShopViewControllerDidDisappear(_:)` method is automatically invoked,
    /// allowing for UI updates (e.g., refreshing the onboarding flow if the shop was presented during onboarding).
    func userWantsToDismissPresentedOlvidShopView(_ view: ObvSubscription.OlvidShopView) {
        self.presentedViewController?.dismiss(animated: true)
    }
    
}


// MARK: - Implementing OlvidShopViewControllerNavigation

extension MetaFlowController: OlvidShopViewControllerNavigation {
    
    /// Called after the `OlvidShopViewController` is dismissed.
    ///
    /// This method is triggered when the user dismisses the view controller,
    /// either by tapping a button in the `OlvidShopView` or by swiping to dismiss.
    /// If the shop was presented during onboarding, this callback allows to update the onboarding UI as needed.
    func olvidShopViewControllerDidDisappear(_ vc: ObvSubscription.OlvidShopViewController) {
        (self.dataSources.tipCellViewAppDataSource as? TipCellViewAppDataSource)?.olvidShopViewControllerDidDisappear()
        Task { await processOnboardingContinuationIfRequired() }
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
    
    
    func userWantsToStartFreeTrialNow(ownedCryptoId: ObvCryptoId) async throws {
        try await obvEngine.startFreeTrial(for: ownedCryptoId)
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

extension MetaFlowController: @preconcurrency MainFlowViewControllerDelegate {
    
    func userWantsToDismissOlvidPlusSuccessfulSubscriptionView(_ mainFlowViewController: MainFlowViewController) {
        userDefaults?.set(nil, forKey: ObvMessengerConstants.UserDefaultsKeys.olvidPlusSubscriptionConfirmationTipToDisplay.rawValue)
        (dataSources.tipCellViewAppDataSource as? TipCellViewAppDataSource)?.refreshTip()
    }
    
    func userWantsToDiscoverOlvidPlus(_ mainFlowViewController: MainFlowViewController) {
        userWantsToSubscribeOlvidPlus()
    }

    func userWantsToUpdateOwnedCustomDisplayName(_ mainFlowViewController: MainFlowViewController, ownedCryptoId: ObvTypes.ObvCryptoId, newCustomDisplayName: String?) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToUpdateOwnedCustomDisplayName(self, ownedCryptoId: ownedCryptoId, newCustomDisplayName: newCustomDisplayName)
    }

    func userWantsToUnhideOwnedIdentity(_ mainFlowViewController: MainFlowViewController, ownedCryptoId: ObvCryptoId) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToUnhideOwnedIdentity(self, ownedCryptoId: ownedCryptoId)
    }
    
    func userWantsToHideOwnedIdentity(_ mainFlowViewController: MainFlowViewController, ownedCryptoId: ObvCryptoId, password: String) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToHideOwnedIdentity(self, ownedCryptoId: ownedCryptoId, password: password)
    }
    
    func userWantsToAddOwnedProfile(_ mainFlowViewController: MainFlowViewController) {
        Task { await processUserWantsToAddOwnedProfileNotification() }
    }
    
    func userWantsToUpdateGroupNameAndPicture(_ mainFlowViewController: MainFlowViewController, groupV1Identifier: ObvTypes.ObvGroupV1Identifier, changes: Set<ObvUIGroupSharedBetweenV1AndV2.EditGroupNameAndPictureView.Change>) async throws {
        let obvContactGroup = try await obvEngine.getContactGroupOwned(groupUid: groupV1Identifier.groupV1Identifier.groupUid, ownedCryptoId: groupV1Identifier.ownedCryptoId)
        var coreDetails: ObvGroupCoreDetails = obvContactGroup.trustedOrLatestCoreDetails
        var photoURL: URL? = obvContactGroup.trustedOrLatestPhotoURL
        for change in changes {
            switch change {
            case .groupDetails(let groupCoreDetails):
                coreDetails = groupCoreDetails
            case .groupPhoto(let newPhotoURL):
                photoURL = newPhotoURL
            }
        }
        let newObvGroupDetails = ObvGroupDetails(coreDetails: coreDetails, photoURL: photoURL)
        try await obvEngine.updateDetailsOfOwnedContactGroup(using: newObvGroupDetails, ownedCryptoId: groupV1Identifier.ownedCryptoId, groupUid: groupV1Identifier.groupV1Identifier.groupUid)
    }
    
    func userWantsToAddSelectedUsersToExistingGroup(_ mainFlowViewController: MainFlowViewController, groupV1Identifier: ObvGroupV1Identifier, newGroupMembers: Set<ObvCryptoId>) async throws {
        try await self.obvEngine.inviteContactsToGroupOwned(groupUid: groupV1Identifier.groupV1Identifier.groupUid, ownedCryptoId: groupV1Identifier.ownedCryptoId, newGroupMembers: newGroupMembers)
    }
    
    func userWantsToRemoveMembersFromGroupV1(_ mainFlowViewController: MainFlowViewController, groupV1Identifier: ObvGroupV1Identifier, removedGroupMembers: Set<ObvCryptoId>) async throws {
        try await self.obvEngine.removeContactsFromGroupOwned(groupUid: groupV1Identifier.groupV1Identifier.groupUid, ownedCryptoId: groupV1Identifier.ownedCryptoId, removedGroupMembers: removedGroupMembers)
    }
    
    func userHasSeenPublishedDetails(_ mainFlowViewController: MainFlowViewController, publishedDetails: PublishedDetailsValidationViewModel) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userHasSeenPublishedDetails(self, publishedDetails: publishedDetails)
    }
    
    func userDidSeeNewDetailsOfContact(_ mainFlowViewController: MainFlowViewController, contactIdentifier: ObvTypes.ObvContactIdentifier) {
        guard let metaFlowControllerDelegate else { assertionFailure(); return }
        metaFlowControllerDelegate.userDidSeeNewDetailsOfContact(self, contactIdentifier: contactIdentifier)
    }
    
    func userWantsToUpdatePersonalNote(_ mainFlowViewController: MainFlowViewController, with newText: String?, about: PersonalNoteEditorView.Model.About) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToUpdatePersonalNote(self, with: newText, about: about)
    }
    
    func userWantsToProcessReceiptsStoredForLater(_ mainFlowViewController: MainFlowViewController, ownedCryptoId: ObvCryptoId, returnReceiptElements: Set<ObvReturnReceiptElements>) async {
        guard let metaFlowControllerDelegate else { assertionFailure(); return }
        await metaFlowControllerDelegate.userWantsToProcessReceiptsStoredForLater(self, ownedCryptoId: ownedCryptoId, returnReceiptElements: returnReceiptElements)
    }
    
    func userWantsToDeleteDiscussionsAndHasConfirmed(_ mainFlowViewController: MainFlowViewController, discussionObjectIDs: [TypeSafeManagedObjectID<PersistedDiscussion>], deletionType: DeletionType) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToDeleteDiscussionsAndHasConfirmed(self, discussionObjectIDs: discussionObjectIDs, deletionType: deletionType)
    }
    
    func userWantsToArchiveDiscussions(_ mainFlowViewController: MainFlowViewController, discussionObjectIDs: [TypeSafeManagedObjectID<PersistedDiscussion>]) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToArchiveDiscussions(self, discussionObjectIDs: discussionObjectIDs)
    }
    
    
    func userWantsToUnarchiveDiscussions(_ mainFlowViewController: MainFlowViewController, discussionObjectIDs: [TypeSafeManagedObjectID<PersistedDiscussion>]) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToUnarchiveDiscussions(self, discussionObjectIDs: discussionObjectIDs)
    }
    
    
    func userWantsToReorderPinnedDiscussions(_ mainFlowViewController: MainFlowViewController, ownedCryptoId: ObvCryptoId, objectIDOfPinnedDiscussions: [TypeSafeManagedObjectID<PersistedDiscussion>]) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToReorderPinnedDiscussions(self, ownedCryptoId: ownedCryptoId, objectIDOfPinnedDiscussions: objectIDOfPinnedDiscussions)
    }
    
    
    func userWantsToMarkAllMessagesAsReadInDiscussion(_ mainFlowViewController: MainFlowViewController, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToMarkAllMessagesAsReadInDiscussion(self, discussionObjectID: discussionObjectID)
    }
    
    
    func userWantsToDeleteOwnedIdentityAndHasConfirmed(_ mainFlowViewController: MainFlowViewController, ownedCryptoId: ObvCryptoId, globalOwnedIdentityDeletion: Bool) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToDeleteOwnedIdentityAndHasConfirmed(self, ownedCryptoId: ownedCryptoId, globalOwnedIdentityDeletion: globalOwnedIdentityDeletion)
    }
    
    /// This is called when the user taps the "refresh" button on her own identity screen. This method request the current subscriptions to store
    /// kit. If a valid subscription is found, it associated to each owned identity present on this device by contacting Olvid's servers.
    /// Then, if there is a "current" owned identity, we refresh the permissions by requesting them from Olvid's servers.
    func userWantsToRefreshSubscriptionStatus(_ mainFlowViewController: MainFlowViewController, ownedCryptoId: ObvCryptoId?) async throws -> [StoreKitDelegatePurchaseResult] {
        return try await refreshSubscriptionStatus(ownedCryptoId: ownedCryptoId)
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
        self.userWantsToSubscribeOlvidPlus()
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
            let dataSource = ObvMapViewControllerAppDataSource(ownedCryptoId: ownedCryptoId, viewContext: ObvStack.shared.viewContext)
            let mapViewController = ObvMapViewController(dataSource: dataSource, avatarViewDataSource: self.dataSources.avatarViewDataSource, actions: self)
            mapViewController.modalPresentationStyle = .overFullScreen
            presentingViewController.presentOnTop(mapViewController, animated: true)
        } else {
            throw ObvError.osUpgradeRequired
        }
    }
    
    
    func userWantsToShowMapToConsultLocationSharedContinously(_ mainFlowViewController: MainFlowViewController, presentingViewController: UIViewController, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>) async throws {
        if #available(iOS 17.0, *) {
            let initialDeviceIdentifierToSelect = try await determineObvDeviceIdentifierAssociatedToMessageObjectID(messageObjectID)
            let dataSource = try ObvMapViewControllerAppDataSource(messageObjectID: messageObjectID, viewContext: ObvStack.shared.viewContext)
            let mapViewController = ObvMapViewController(dataSource: dataSource, avatarViewDataSource: self.dataSources.avatarViewDataSource, actions: self, initialDeviceIdentifierToSelect: initialDeviceIdentifierToSelect)
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
    
    func userWantsToCreatePoll(_ mainFlowViewController: MainFlowViewController, presentingViewController: UIViewController, discussionIdentifier: ObvDiscussionIdentifier) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToCreatePoll(self, presentingViewController: presentingViewController, discussionIdentifier: discussionIdentifier)
    }
    
    /// Called when the user wants to display the interface allowing to see the details of a specific poll.
    func userWantsToDisplayPollView(_ mainFlowViewController: MainFlowViewController, presentingViewController: UIViewController, pollObjectID: TypeSafeManagedObjectID<PersistedPoll>) async throws {
        
        _ = await NewAppStateManager.shared.waitUntilAppIsInitializedAndMetaFlowControllerViewDidAppearAtLeastOnce()
        
        if #available(iOS 17, *) {

            let vc = PollHostingController(
                pollIdentifier: PollIdentifier.persistedPollObjectID(pollObjectID.objectID),
                pollDataSource: dataSources.pollViewDataSource,
                avatarViewDataSource: self.dataSources.avatarViewDataSource)
            
            presentingViewController.present(vc, animated: true, completion: nil)
            
        } else {
            
            guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
            metaFlowControllerDelegate.presentAlertAsOsUpgradeIsRequired(self, presentingViewController: presentingViewController)
            
            
        }

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
    
    func userWantsToUpdatePollVote(_ mainFlowViewController: MainFlowViewController, ownedCryptoId: ObvCryptoId, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, pollVoteCandidateUuid: UUID, voted: Bool, version: Int) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToUpdatePollVote(self, ownedCryptoId: ownedCryptoId, messageObjectID: messageObjectID, pollVoteCandidateUuid: pollVoteCandidateUuid, voted: voted, version: version)
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
    
    
    func userWantsToAddAttachmentsToDraftFromURLs(_ mainFlowViewController: MainFlowViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, urls: [URL]) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToAddAttachmentsToDraftFromURLs(self, draftObjectID: draftObjectID, urls: urls)
    }
    
    
    func userWantsToAddAttachmentsToDraft(_ mainFlowViewController: MainFlowViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, itemProviders: [NSItemProvider], source: LoadItemProviderHelper.ItemProviderProviderSource) async throws -> [LoadedItemProviderToPaste] {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        return try await metaFlowControllerDelegate.userWantsToAddAttachmentsToDraft(self, draftObjectID: draftObjectID, itemProviders: itemProviders, source: source)
    }
    
    
    func userWantsToSendDraft(mainFlowViewController: MainFlowViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, textBody: String, mentions: Set<MessageJSON.UserMention>) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToSendDraft(self, draftObjectID: draftObjectID, textBody: textBody, mentions: mentions)
    }
    
    
    func userRequestedAppDatabaseSyncWithEngine(mainFlowViewController: MainFlowViewController) async throws {
        assert(metaFlowControllerDelegate != nil)
        try await metaFlowControllerDelegate?.userRequestedAppDatabaseSyncWithEngine(metaFlowController: self)
    }
    
    
    @MainActor
    func userWantsToPublishGroupV2Modification(_ mainFlowViewController: MainFlowViewController, groupObjectID: TypeSafeManagedObjectID<PersistedGroupV2>, changeset: ObvGroupV2.Changeset) async throws {
        assert(Thread.isMainThread) // Required because we access automaticallyNavigateToCreatedDisplayedContactGroup
        
        Self.logger.debug("🧑‍🧑‍🧒‍🧒 Call to userWantsToPublishGroupV2Modification(_ mainFlowViewController: MainFlowViewController, groupObjectID: TypeSafeManagedObjectID<PersistedGroupV2>, changeset: ObvGroupV2.Changeset)")

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
    
    func userWantsToPublishGroupV1Creation(_ mainFlowViewController: MainFlowViewController, ownedCryptoId: ObvCryptoId, groupDetails: ObvGroupDetails, otherGroupMembers: Set<ObvCryptoId>) async throws {
        try await obvEngine.startGroupV1CreationProtocol(groupName: groupDetails.coreDetails.name,
                                                         groupDescription: groupDetails.coreDetails.description,
                                                         groupMembers: otherGroupMembers,
                                                         ownedCryptoId: ownedCryptoId,
                                                         photoURL: groupDetails.photoURL)
    }
    
    func userWantsToPublishGroupV2Creation(_ mainFlowViewController: MainFlowViewController, groupCoreDetails: GroupV2CoreDetails, ownPermissions: Set<ObvGroupV2.Permission>, otherGroupMembers: Set<ObvGroupV2.IdentityAndPermissions>, ownedCryptoId: ObvCryptoId, photoURL: URL?, groupType: ObvGroupType) async throws {
        assert(Thread.isMainThread) // Required because we access automaticallyNavigateToCreatedDisplayedContactGroup
        
        // Make sure all the members can be reached (i.e., have a prekey or/and a channel with our current owned device)
        let contactsThatCannotBeReached = try await self.contactsThatCannotBeReached(ownedCryptoId: ownedCryptoId, contactCryptoIds: Set(otherGroupMembers.map({ $0.identity })))
        assert(contactsThatCannotBeReached.isEmpty, "Those contacts should have been filtered out earlier in the group creation/clone process")
        
        // Remove the members that cannot be reached (this should not happen, we should have removed those earlier in the process)
        let otherGroupMembersToConsider = otherGroupMembers.filter({ !contactsThatCannotBeReached.contains($0.identity) })
        
        automaticallyNavigateToCreatedDisplayedContactGroup = true
        let obvEngine = self.obvEngine
        let serializedGroupCoreDetails = try groupCoreDetails.jsonEncode()
        let serializedGroupType = try groupType.toSerializedGroupType()
        try await obvEngine.startGroupV2CreationProtocol(serializedGroupCoreDetails: serializedGroupCoreDetails,
                                                         ownPermissions: ownPermissions,
                                                         otherGroupMembers: otherGroupMembersToConsider,
                                                         ownedCryptoId: ownedCryptoId,
                                                         photoURL: photoURL,
                                                         serializedGroupType: serializedGroupType)
    }
    
    
    /// Returns a subset of `contactCryptoIds`, only containing the `ObvCryptoId`s of the contacts that cannot be reached. This is used when creating a group, in order to discard non-reachable contacts
    /// from the set of requested other group members.
    private func contactsThatCannotBeReached(ownedCryptoId: ObvCryptoId, contactCryptoIds: Set<ObvCryptoId>) async throws -> Set<ObvCryptoId> {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Set<ObvCryptoId>, any Error>) in
            ObvStack.shared.performBackgroundTask { context in
                var contactsThatCannotBeReached = Set<ObvCryptoId>()
                do {
                    for contactCryptoId in contactCryptoIds {
                        let contactIdentifier = ObvContactIdentifier(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
                        let canBeReached = try PersistedObvContactIdentity.atLeastOneDeviceAllowsThisContactToReceiveMessages(contactIdentifier: contactIdentifier, within: context)
                        if !canBeReached {
                            contactsThatCannotBeReached.insert(contactCryptoId)
                        }
                    }
                    return continuation.resume(returning: contactsThatCannotBeReached)
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
    
    
    func userWantsToAddNewDevice(_ viewController: MainFlowViewController, ownedCryptoId: ObvCryptoId) async {
        guard let (ownedDetails, isKeycloakManaged) = try? await getOwnedIdentityDetails(ownedCryptoId: ownedCryptoId) else { assertionFailure(); return }
        let isTransferRestricted: Bool
        if isKeycloakManaged {
            guard let _isTransferRestricted = (try? await obvEngine.getOwnedIdentityKeycloakState(with: ownedCryptoId))?.keycloakState.isTransferRestricted else { assertionFailure(); return }
            isTransferRestricted = _isTransferRestricted
        } else {
            isTransferRestricted = false
        }
        let newOnboardingFlowViewController = NewOnboardingFlowViewController(
            logSubsystem: ObvAppCoreConstants.logSubsystem,
            directoryForTempFiles: ObvUICoreDataConstants.ContainerURL.forTempFiles.url,
            mode: .addNewDevice(ownedCryptoId: ownedCryptoId, ownedDetails: ownedDetails, isTransferRestricted: isTransferRestricted),
            dataSource: self,
            olvidShopViewActions: self,
            olvidShopViewDataSources: self.dataSources.olvidShopViewDataSources)
        newOnboardingFlowViewController.delegate = self
        await self.presentedViewController?.dismissAndAwaitCompletion(animated: true)
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
    
    func userWantsToReplaceTrustedDetailsByPublishedDetails(_ mainFlowViewController: MainFlowViewController, groupIdentifier: ObvGroupV1Identifier) async throws {
        try await obvEngine.trustPublishedDetailsOfJoinedContactGroup(ownedCryptoId: groupIdentifier.ownedCryptoId, groupUid: groupIdentifier.groupV1Identifier.groupUid, groupOwner: groupIdentifier.groupV1Identifier.groupOwner)
    }

    func userWantsToReplaceTrustedDetailsByPublishedDetails(_ mainFlowViewController: MainFlowViewController, groupIdentifier: ObvGroupV2Identifier) async throws {
        guard let metaFlowControllerDelegate else { assertionFailure(); throw ObvError.metaFlowControllerDelegateIsNil }
        try await metaFlowControllerDelegate.userWantsToReplaceTrustedDetailsByPublishedDetails(self, groupIdentifier: groupIdentifier)
    }
    
    
    func userWantsToLeaveGroup(_ mainFlowViewController: MainFlowViewController, groupIdentifier: ObvGroupIdentifier) async throws {
        switch groupIdentifier {
        case .groupV1(let groupIdentifier):
            try await obvEngine.leaveGroupV1Joined(groupV1Identifier: groupIdentifier)
        case .groupV2(let groupIdentifier):
            try await obvEngine.leaveGroupV2(ownedCryptoId: groupIdentifier.ownedCryptoId, groupIdentifier: groupIdentifier.identifier.appGroupIdentifier)
        }
    }
    
    
    func userWantsToDisbandGroup(_ mainFlowViewController: MainFlowViewController, groupIdentifier: ObvGroupIdentifier) async throws {
        switch groupIdentifier {
        case .groupV1(let groupIdentifier):
            try await obvEngine.performDisbandOfGroupV1(groupV1Identifier: groupIdentifier)
        case .groupV2(let groupIdentifier):
            try await obvEngine.performDisbandOfGroupV2(ownedCryptoId: groupIdentifier.ownedCryptoId, groupIdentifier: groupIdentifier.identifier.appGroupIdentifier)
        }
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
    
    
//    private func observeUserWantsToUserWantsToLeaveJoinedContactGroupNotifications() {
//        let NotificationType = MessengerInternalNotification.UserWantsToLeaveJoinedContactGroup.self
//        let token = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: nil) { [weak self] (notification) in
//            guard let (groupOwner, groupUid, ownedCryptoId, sourceView) = NotificationType.parse(notification) else { return }
//            Task { [weak self] in
//                await self?.processUserWantsToLeaveJoinedContactGroup(groupOwner: groupOwner,
//                                                                      groupUid: groupUid,
//                                                                      ownedCryptoId: ownedCryptoId,
//                                                                      sourceView: sourceView)
//            }
//        }
//        observationTokens.append(token)
//    }
    
    
//    @MainActor
//    private func processUserWantsToLeaveJoinedContactGroup(groupOwner: ObvCryptoId, groupUid: UID, ownedCryptoId: ObvCryptoId, sourceView: UIView) {
//        guard self.currentOwnedCryptoId == ownedCryptoId else { return }
//        self.leaveJoinedContactGroup(groupOwner: groupOwner, groupUid: groupUid, ownedCryptoId: ownedCryptoId, sourceView: sourceView, confirmed: false)
//    }

    
//    private func leaveJoinedContactGroup(groupOwner: ObvCryptoId, groupUid: UID, ownedCryptoId: ObvCryptoId, sourceView: UIView, confirmed: Bool) {
//        
//        if confirmed {
//            
//            let log = self.log
//            let localEngine = self.obvEngine
//            DispatchQueue(label: "Background queue for requesting leaveContactGroupJoined to engine").async {
//                do {
//                    try localEngine.leaveContactGroupJoined(ownedCryptoId: ownedCryptoId, groupUid: groupUid, groupOwner: groupOwner)
//                } catch {
//                    os_log("Could not leave contact group joined", log: log, type: .error)
//                }
//            }
//
//        } else {
//            let alert = UIAlertController(title: CommonString.Title.leaveGroup,
//                                          message: Strings.leaveGroupExplanation,
//                                          preferredStyleForTraitCollection: self.traitCollection)
//            alert.addAction(UIAlertAction(title: CommonString.Title.leaveGroup, style: .destructive, handler: { [weak self] (action) in
//                if let presentedViewController = self?.presentedViewController {
//                    presentedViewController.dismiss(animated: true, completion: {
//                        self?.leaveJoinedContactGroup(groupOwner: groupOwner, groupUid: groupUid, ownedCryptoId: ownedCryptoId, sourceView: sourceView, confirmed: true)
//                    })
//                } else {
//                    self?.leaveJoinedContactGroup(groupOwner: groupOwner, groupUid: groupUid, ownedCryptoId: ownedCryptoId, sourceView: sourceView, confirmed: true)
//                }
//            }))
//            alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))
//            DispatchQueue.main.async { [weak self] in
//                guard let _self = self else { return }
//                alert.popoverPresentationController?.sourceView = sourceView
//                if let presentedViewController = _self.presentedViewController {
//                    presentedViewController.present(alert, animated: true)
//                } else {
//                    _self.present(alert, animated: true)
//                }
//            }
//            
//        }
//
//    }
    
    
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
        await presentedViewController?.dismissAndAwaitCompletion(animated: true)
        let newOnboardingFlowViewController = NewOnboardingFlowViewController(
            logSubsystem: ObvAppCoreConstants.logSubsystem,
            directoryForTempFiles: ObvUICoreDataConstants.ContainerURL.forTempFiles.url,
            mode: .addProfile,
            dataSource: self,
            olvidShopViewActions: self,
            olvidShopViewDataSources: self.dataSources.olvidShopViewDataSources)
        newOnboardingFlowViewController.delegate = self
        present(newOnboardingFlowViewController, animated: true)
    }
    
}


// MARK: - Switching current owned identity

extension MetaFlowController {
    
    /// Changes the current owned identity of the user. Called as a response to the corresponding notification.
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
    }
    
}


// MARK: OlvidURLHandler

extension MetaFlowController: OlvidURLRouter {

    /// The `NewAppStateManager` calls this method from its `func handleOlvidURL(_ olvidURL: OlvidURL)`, as we are its `olvidURLHandler`.
    /// This method should **always** be called first during the processing of an `OlvidURL`. One possible way of doing this is to call `NewAppStateManager.shared.handleOlvidURL(...)`.
    func routeOlvidURL(_ olvidURL: OlvidURL) async {
        
        switch olvidURL.category {
            
        case .openIdRedirect:
            
            // If the OlvidURL is an openId redirect, we handle it immediately.
            await handleOlvidURLOfTypeOpenIdRedirectWithURL(opendIdRedirectURL: olvidURL.url)
            
        case .configuration(let configurationKind):
            
            switch configurationKind {
                
            case .serverAndAPIKey(let serverAndAPIKey):
                await handleOlvidURLOfTypeConfigurationWithServerAndAPIKey(serverAndAPIKey: serverAndAPIKey)
                
            case .betaConfiguration(let betaConfiguration):
                await handleOlvidURLOfTypeConfigurationWithBetaConfiguration(betaConfiguration: betaConfiguration)
                
            case .keycloakConfig(let keycloakConfig):
                await handleOlvidURLOfTypeConfigurationWithKeycloakConfiguration(keycloakConfig: keycloakConfig)
                
            }
            
        case .mutualScan(mutualScanURL: let mutualScanURL):
            
            do {
                try await self.mainFlowViewController?.handleOlvidURLOfTypeMutualScan(mutualScanURL: mutualScanURL)
            } catch {
                Self.logger.fault("Could not handle OlvidURL of type mutual scan: \(error)")
                assertionFailure()
            }
                            
        case .invitation(urlIdentity: let remoteURLIdentity):
            
            await handleOlvidURLOfTypeInvitation(remoteURLIdentity: remoteURLIdentity)
            
        }

    }
    
    
    /// Handles the activation and the deactivation of Beta settings.
    ///
    /// This is a helper method for `func handleOlvidURL(_ olvidURL: OlvidURL)`.
    ///
    private func handleOlvidURLOfTypeConfigurationWithBetaConfiguration(betaConfiguration: BetaConfiguration) async {
        await self.presentedViewController?.dismissAndAwaitCompletion(animated: true)
        let vc = BetaSettingsActivationViewController(isAccessToAdvancedSettingsEnabled: betaConfiguration.beta)
        self.present(vc, animated: true)
    }
    
    
    /// Handles license assignment to a user's profile.
    ///
    /// This is a helper method for `func handleOlvidURL(_ olvidURL: OlvidURL)`.
    ///
    /// Four scenarios are considered:
    /// 1. Initial Onboarding: If the user has no profiles, the license is passed to the onboarding flow.
    /// 2. Adding a New Profile: If an onboarding is already presented, the license is passed to create a new profile.
    /// 3. Single Profile: If only one profile exists, the license activation screen is shown for that profile.
    /// 4. Multiple Profiles: If multiple profiles exist, the user selects the target profile, switches to it, and the license activation screen is displayed.
    private func handleOlvidURLOfTypeConfigurationWithServerAndAPIKey(serverAndAPIKey: ServerAndAPIKey) async {
        
        if let onboardingFlowViewController {
            // We are performing the initial onboarding.
            await onboardingFlowViewController.handleOlvidURLOfTypeConfigurationWithServerAndAPIKey(serverAndAPIKey: serverAndAPIKey)
        } else if let onboardingFlowViewController = presentedViewController as? NewOnboardingFlowViewController {
            // We are creating a new profile.
            await onboardingFlowViewController.handleOlvidURLOfTypeConfigurationWithServerAndAPIKey(serverAndAPIKey: serverAndAPIKey)
        } else {
            // Since there is no onboarding, we expect to have at least one existing profile.
            // Let the user choose the profile she wants to use for this license.
            await self.presentedViewController?.dismissAndAwaitCompletion(animated: true)
            let chosenOwnedCryptoId: ObvCryptoId
            do {
                guard let _chosenOwnedCryptoId = try await requestAppropriateOwnedIdentityToProcessExternallyScannedOrTappedOlvidURL() else {
                    // The user dismissed the profile chooser, we discard the OlvidURL
                    return
                }
                chosenOwnedCryptoId = _chosenOwnedCryptoId
            } catch {
                Self.logger.fault("Could not handle OlvidURL of type .configuration containing a serverAndAPIKey: \(error)")
                assertionFailure()
                return
            }
            // Switch to the chosen profile
            await self.switchToOwnedIdentity(ownedCryptoId: chosenOwnedCryptoId)
            // Present the view allowing the user to consult and accept the license
            let dataSource = self.dataSources.licenseActivationViewDataSource
            let vc = NewLicenseActivationViewController(ownedCryptoId: chosenOwnedCryptoId, serverAndAPIKey: serverAndAPIKey, dataSource: dataSource, actions: self)
            await self.presentedViewController?.dismissAndAwaitCompletion(animated: true)
            self.present(vc, animated: true)
        }

    }
    
    
    private func handleOlvidURLOfTypeInvitation(remoteURLIdentity: ObvURLIdentity) async {
        
        // Let the user choose the profile she wants to use for this license.
        await self.presentedViewController?.dismissAndAwaitCompletion(animated: true)
        let chosenOwnedCryptoId: ObvCryptoId
        do {
            guard let _chosenOwnedCryptoId = try await requestAppropriateOwnedIdentityToProcessExternallyScannedOrTappedOlvidURL() else {
                // The user dismissed the profile chooser, we discard the OlvidURL
                return
            }
            chosenOwnedCryptoId = _chosenOwnedCryptoId
        } catch {
            Self.logger.fault("Could not handle OlvidURL of type .invitation: \(error)")
            assertionFailure()
            return
        }
        // Switch to the chosen profile
        await self.switchToOwnedIdentity(ownedCryptoId: chosenOwnedCryptoId)

        // Handle the invitation link with the chosent profile
        assert(self.mainFlowViewController != nil)
        await self.mainFlowViewController?.handleExternalInvitation(remoteURLIdentity: remoteURLIdentity)
        
    }
    
    /// Handles a scanned (or tapped) keycloak configuration.
    ///
    /// This is a helper method for `func handleOlvidURL(_ olvidURL: OlvidURL)`.
    ///
    /// Four scenarios are considered:
    /// 1. Initial Onboarding: If the user has no profiles, the keycloak configuration is passed to the onboarding flow.
    /// 2. Adding a New Profile: If an onboarding is already presented, the keycloak configuration is passed to create a new profile.
    /// 3. Single Profile: If only one profile exists, we launch a new onboarding in the `.bindExistingProfileToKeycloak` mode, allowing the user to bind the profile to a keycloak server.
    /// 4. Multiple Profiles: If multiple profiles exist, the user selects the target profile, switches to it. We then launch a new onboarding in the `.bindExistingProfileToKeycloak` mode, allowing the user to bind the profile to a keycloak server.
    private func handleOlvidURLOfTypeConfigurationWithKeycloakConfiguration(keycloakConfig: ObvKeycloakConfigurationAndServer) async {
        
        if let onboardingFlowViewController {
            // We are performing the initial onboarding.
            await onboardingFlowViewController.handleOlvidURLOfTypeConfigurationWithKeycloakConfigurationAndServer(keycloakConfig: keycloakConfig)
        } else if let onboardingFlowViewController = presentedViewController as? NewOnboardingFlowViewController {
            // We are creating a new profile.
            await onboardingFlowViewController.handleOlvidURLOfTypeConfigurationWithKeycloakConfigurationAndServer(keycloakConfig: keycloakConfig)
        } else {
            // Since there is no onboarding, we expect to have at least one existing profile.
            // Let the user choose the profile she wants to use for this keycloak configuration.
            await self.presentedViewController?.dismissAndAwaitCompletion(animated: true)
            let chosenOwnedCryptoId: ObvCryptoId
            do {
                guard let _chosenOwnedCryptoId = try await requestAppropriateOwnedIdentityToProcessExternallyScannedOrTappedOlvidURL() else {
                    // The user dismissed the profile chooser, we discard the OlvidURL
                    return
                }
                chosenOwnedCryptoId = _chosenOwnedCryptoId
            } catch {
                Self.logger.fault("Could not handle OlvidURL of type .configuration containing a serverAndAPIKey: \(error)")
                assertionFailure()
                return
            }
            // Switch to the chosen profile
            await self.switchToOwnedIdentity(ownedCryptoId: chosenOwnedCryptoId)
            // The user chose the profile to bind. We launch an onboarding flow in the .bindExistingProfileToKeycloak mode
            let vc = NewOnboardingFlowViewController(
                logSubsystem: ObvAppCoreConstants.logSubsystem,
                directoryForTempFiles: ObvUICoreDataConstants.ContainerURL.forTempFiles.url,
                mode: .bindExistingProfileToKeycloak(ownedCryptoId: chosenOwnedCryptoId,
                                                     keycloakConfigurationAndServer: keycloakConfig),
                dataSource: self,
                olvidShopViewActions: self,
                olvidShopViewDataSources: self.dataSources.olvidShopViewDataSources)
            vc.delegate = self
            await self.presentedViewController?.dismissAndAwaitCompletion(animated: true)
            self.present(vc, animated: true)
        }

    }
    
    
    private func handleOlvidURLOfTypeOpenIdRedirectWithURL(opendIdRedirectURL: URL) async {
        do {
            _ = try await KeycloakManagerSingleton.shared.resumeExternalUserAgentFlow(with: opendIdRedirectURL)
            os_log("Successfully resumed the external user agent flow", log: Self.log, type: .info)
        } catch {
            os_log("Failed to resume external user agent flow: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }
    }
    
}


// MARK: - Implementing NewLicenseActivationViewActions

extension MetaFlowController: NewLicenseActivationViewActions {
    
    /// Called when the user accepts to activate a new license for the owned crypto id.
    func userWantsToActivateNewLicense(_ view: ObvLicenceActivationFlow.NewLicenseActivationView, ownedCryptoId: ObvTypes.ObvCryptoId, serverAndAPIKey: ObvTypes.ServerAndAPIKey) async throws {
        try await obvEngine.registerOwnedAPIKeyOnServerNow(ownedCryptoId: ownedCryptoId, apiKey: serverAndAPIKey.apiKey)
    }
    
    func userWantsToDismissNewLicenseActivationView(_ view: ObvLicenceActivationFlow.NewLicenseActivationView) {
        self.presentedViewController?.dismiss(animated: true)
    }
    
}


// MARK: - Helper to choose an owned identity when required for an OlvidURL

extension MetaFlowController {
    
    /// Highly asynchronous sequence that allows to present the owned identity chooser (if appropriate) and that returns the user choice.
    ///
    /// If there is no profile on this device, this method throws. If there is exactly one profile on this device, it is immediately returned.
    /// Otherwise, it presents an `OwnedIdentityChooserViewController` and returns the
    /// chosen owned `ObvCryptoId`. If the user cancels by either dismissing the controller or tapping the cancel button, this method returns nil.
    private func requestAppropriateOwnedIdentityToProcessExternallyScannedOrTappedOlvidURL() async throws -> ObvCryptoId? {

        let ownedIdentities: [PersistedObvOwnedIdentity]
        do {
            let notHiddenOwnedIdentities = try PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentities(within: ObvStack.shared.viewContext)
            if let currentOwnedCryptoId = self.currentOwnedCryptoId, let currentOwnedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: currentOwnedCryptoId, within: ObvStack.shared.viewContext), currentOwnedIdentity.isHidden {
                ownedIdentities = [currentOwnedIdentity] + notHiddenOwnedIdentities
            } else {
                ownedIdentities = notHiddenOwnedIdentities
            }
        } catch {
            Self.logger.fault("Could not get all owned identities: \(error)")
            assertionFailure()
            throw error
        }
        
        if let currentOrFirstOwnedCryptoId = self.currentOwnedCryptoId ?? ownedIdentities.first?.cryptoId {
            
            if ownedIdentities.count == 1 {
                
                // There is exactly one profile on this phone, we return it now

                return currentOrFirstOwnedCryptoId

            } else {
                
                // There is more than one profile to choose from

                return try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<ObvCryptoId?, any Error>) in
                    
                    guard let self else { return continuation.resume(throwing: ObvError.ownedIdentityChooserViewControllerFlowWasCancelled) }

                    self.localOwnedIdentityChooserViewControllerDelegate.set(continuation: continuation)
                    
                    let callbackOnViewDidDisappear: (() -> Void) = { [weak self] in
                        Task { await self?.localOwnedIdentityChooserViewControllerDelegate.userDismissedTheOwnedIdentityChooserViewController() }
                    }
                    
                    let ownedIdentityChooserVC = OwnedIdentityChooserViewController(
                        currentOwnedCryptoId: currentOrFirstOwnedCryptoId,
                        actions: localOwnedIdentityChooserViewControllerDelegate,
                        dataSource: self.dataSources.ownedIdentityChooserViewDataSource,
                        avatarViewDataSource: self.dataSources.avatarViewDataSource,
                        configuration: .init(mode: .selectProfile,
                                             explanation: String(localized: "PLEASE_SELECT_A_PROFILE_BEFORE_CONTINUING"),
                                             title: "MY_PROFILES",
                                             isEmbeddedInHostingController: true),
                        callbackOnViewDidDisappear: callbackOnViewDidDisappear,
                        toggleToDismiss: .init(get: { false }, set: { [weak self] value in
                            guard value else { return }
                            (self?.presentedViewController as? OwnedIdentityChooserViewController)?.dismiss(animated: true)
                        }))
                    
                    // Under iPhone, we use a popover presentation style. Since we have no source view, we cannot do the same under iPad or mac.
                    // Note that this method gets also called when the user taps an invitation link in a Safari window. In that case, we cannot have a source view anyway.
                    if traitCollection.userInterfaceIdiom == .phone {
                        ownedIdentityChooserVC.modalPresentationStyle = .popover
                        if let popover = ownedIdentityChooserVC.popoverPresentationController {
                            let sheet = popover.adaptiveSheetPresentationController
                            sheet.detents = [.medium(), .large()]
                            sheet.prefersGrabberVisible = true
                            if #available(iOS 26.0, *) {
                                // Keep the default preferredCornerRadius
                            } else {
                                sheet.preferredCornerRadius = 16.0
                            }
                        }
                    } else {
                        ownedIdentityChooserVC.modalPresentationStyle = .formSheet
                    }

                    present(ownedIdentityChooserVC, animated: true)
                    
                }

            }
            
        } else {
            
            // There are no profiles on this device
            
            throw ObvError.noProfileToChoose
            
        }
        
    }
    
    
    private func configureAndPresentOwnedIdentityChooserViewControllerWhenProcessingExternallyScannedOrTappedOlvidURL() async {
        
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
        case noProfileToChoose
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
        case ownedIdentityChooserViewControllerFlowWasCancelled
        
        var errorDescription: String? {
            switch self {
            case .ownedIdentityChooserViewControllerFlowWasCancelled:
                return "Owned identity chooser view controller flow was cancelled"
            case .noProfileToChoose:
                return "No profile to choose"
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
            case .ownedIdentityChooserViewControllerFlowWasCancelled:
                return nil
            case .noProfileToChoose:
                return nil
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
    /// Then, if an owned identity is specified, we refresh the permissions by requesting them from Olvid's servers.
    func refreshSubscriptionStatus(ownedCryptoId: ObvCryptoId?) async throws -> [ObvAppTypes.StoreKitDelegatePurchaseResult] {
        guard let storeKitDelegate else { assertionFailure(); throw ObvError.storeKitDelegateIsNil }
        let results = try await storeKitDelegate.refreshSubscriptionStatus()
        if let ownedCryptoId {
            _ = try await obvEngine.refreshAPIPermissions(of: ownedCryptoId)
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

// MARK: - Private helpers

extension MetaFlowController {
    
    /// Presents the `OlvidShopView`, allowing the user to subscribe to an Olvid+ plan.
    ///
    /// This method is primarily used during a device transfer process, where the user is shown a list of devices that will be deactivated after the transfer.
    /// In this context, the user has the option to tap a button to keep all their devices active by subscribing to Olvid+.
    ///
    /// Also used when the user taps on the "Discover Olvid+" button on one of the Olvid+ tips.
    ///
    /// - Note: One of the methods calling this one stores a continuation locally, enabling the onboarding flow to update the UI accordingly.
    private func userWantsToSubscribeOlvidPlus() {
        let vc = OlvidShopViewController(
            dataSources: self.dataSources.olvidShopViewDataSources,
            navigation: self,
            actions: self,
            viewControllerNavigation: self)
        if let presentedViewController = self.presentedViewController {
            presentedViewController.present(vc, animated: true)
        } else {
            self.present(vc, animated: true)
        }
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
                self.presentOnTop(picker, animated: true)
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


// MARK: - Observing the app database

extension MetaFlowController: PersistedObvOwnedIdentityObserver {
    
    /// Handles the transition of `APIPermissions` from `[]` to `[.canCall, .multidevice]` to determine whether an
    /// `olvidPlusSuccessfulSubscription` tip should be displayed.
    ///
    /// When this transition occurs, the method checks if the user has either:
    /// - Subscribed to Olvid+ directly, or
    /// - Received access via family sharing.
    ///
    /// If a valid subscription is detected:
    /// 1. A `userDefaults` value is set to track the subscription type.
    /// 2. A refresh of the tips displayed at the top of the recent discussions list is requested. This refresh displays a tip confirming the user's access to Olvid+ features.
    ///
    /// The displayed tip includes a dismiss button, which calls `MetaFlowController.userWantsToDismissOlvidPlusSuccessfulSubscriptionView`.
    /// This method removes the `userDefaults` value and triggers another refresh to hide the tip.
    func theAPIPermissionsOfOwnedIdentityDidChange(ownedCryptoId: ObvCryptoId, oldAPIPermissions: APIPermissions, newAPIPermissions: APIPermissions) async {
        do {
            guard oldAPIPermissions == [] && newAPIPermissions.contains([.canCall, .multidevice]) else { return }
            guard let storeKitDelegate else { throw ObvError.storeKitDelegateIsNil }
            guard let ownershipType = try await storeKitDelegate.getOwnershipTypeForTipNotificationOfJustMadeSubscription() else { return }
            userDefaults?.set(ownershipType.rawValue, forKey: ObvMessengerConstants.UserDefaultsKeys.olvidPlusSubscriptionConfirmationTipToDisplay.rawValue)
            (dataSources.tipCellViewAppDataSource as? TipCellViewAppDataSource)?.refreshTip()
        } catch {
            assertionFailure()
        }
    }
    
    
    func aPersistedObvOwnedIdentityWasDeleted(ownedCryptoId: ObvCryptoId) async {
        do {
            try await setupAndShowAppropriateChildViewControllers(ownedCryptoIdGeneratedDuringOnboarding: nil)
        } catch {
            assertionFailure()
        }
    }
    
    func newPersistedObvOwnedIdentity(ownedCryptoId: ObvCryptoId, isActive: Bool) async {
        // When a new owned identity is created, we refresh the subscriptions to make sure any existing valid subscription
        // is immediately associated to this new owned identity
        do {
            let results = try await refreshSubscriptionStatus(ownedCryptoId: nil)
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
                        .revoked,
                        .isUpgraded:
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


// MARK: - Helper class

/// This private helper class is used to allow the MetaFlowController to offer a simple API allowing the user to choose one of her profiles when processing
/// an OlvidURL.
@MainActor
private final class LocalOwnedIdentityChooserViewControllerDelegate: OwnedIdentityChooserViewActionsProtocol {
        
    private var continuation: CheckedContinuation<ObvCryptoId?, any Error>?
    
    func set(continuation: CheckedContinuation<ObvCryptoId?, any Error>) {
        failExistingContinuationIfRequired() // This sets self.continuation to nil
        self.continuation = continuation
    }
    
    func failExistingContinuationIfRequired() {
        guard let continuation = self.continuation else { return }
        self.continuation = nil
        continuation.resume(returning: nil)
    }
    
    func userDismissedTheOwnedIdentityChooserViewController() async {
        guard let continuation = self.continuation else { return }
        self.continuation = nil
        continuation.resume(returning: nil)
    }

    // Implementing OwnedIdentityChooserViewActionsProtocol
    
    func userChoseProfile(_ view: ObvOwnedIdentityChooser.OwnedIdentityChooserView, chosenOwnedCryptoId: ObvTypes.ObvCryptoId) async throws {
        guard let continuation = self.continuation else { return }
        self.continuation = nil
        continuation.resume(returning: chosenOwnedCryptoId)
    }
    
    func userWantsToEditCurrentOwnedIdentity(_ view: ObvOwnedIdentityChooser.OwnedIdentityChooserView, currentOwnedCryptoId: ObvTypes.ObvCryptoId) async {
        assertionFailure("Unexpected as the OwnedIdentityChooserViewController is in selectProfile mode")
    }
    
    func userWantsToAddNewProfile(_ view: ObvOwnedIdentityChooser.OwnedIdentityChooserView) async {
        assertionFailure("Unexpected as the OwnedIdentityChooserViewController is in selectProfile mode")
    }

}


// MARK: - Helper struct

private actor LocalAvatarViewAppDataSource: ObvAvatarViewAppDataSourceDelegate {
    
    private let obvEngine: ObvEngine
    
    init(obvEngine: ObvEngine) {
        self.obvEngine = obvEngine
    }
    
    func getUserDataNow(ownedCryptoId: ObvTypes.ObvCryptoId, encodedServerKeyAndLabel: Data?) async throws -> Data? {
        return try await obvEngine.getUserDataNow(ownedCryptoId: ownedCryptoId, encodedServerKeyAndLabel: encodedServerKeyAndLabel)
    }
    
    nonisolated
    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        ObvStack.shared.performBackgroundTask(block)
    }
    
    
}


// MARK: - Helper struct

private protocol LocalObvSingleContactViewAppDataSourceDelegateImplementationDelegate: AnyObject {
    func freshContactIdentityReceivedWhileShowingSingleContactView(_ implementation: LocalObvSingleContactViewAppDataSourceDelegateImplementation, contactIdentity: ObvContactIdentity) async
}

private final class LocalObvSingleContactViewAppDataSourceDelegateImplementation: ObvSingleContactViewAppDataSourceDelegate {
        
    private let engine: ObvEngine
    weak var delegate: LocalObvSingleContactViewAppDataSourceDelegateImplementationDelegate?
    
    init(engine: ObvEngine) {
        self.engine = engine
    }
    
    func getAsyncStreamOfObvContactIdentity(_ dataSource: ObvSingleContactViewAppDataSource, for contactIdentifier: ObvContactIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvContactIdentity>) {
        return try await engine.getAsyncStreamOfObvContactIdentity(for: contactIdentifier)
    }

    func finishAsyncSequenceOfObvContactIdentity(_ dataSource: ObvSingleContactViewAppDataSource, streamUUID: UUID) {
        engine.finishAsyncSequenceOfObvContactIdentity(streamUUID: streamUUID)
    }
 
    
    func freshContactIdentityReceivedWhileShowingSingleContactView(_ dataSource: ObvSingleContactViewAppDataSource, contactIdentity: ObvContactIdentity) async {
        guard let delegate else { assertionFailure(); return }
        await delegate.freshContactIdentityReceivedWhileShowingSingleContactView(self, contactIdentity: contactIdentity)
    }
    
}


// MARK: - Helper struct

private final class LocalNewLicenseActivationViewControllerAppDataSourceDelegate: NewLicenseActivationViewControllerAppDataSourceDelegate {

    private let engine: ObvEngine
    
    init(engine: ObvEngine) {
        self.engine = engine
    }

    func getApiKeyElementsFromServer(_ dataSource: NewLicenseActivationViewControllerAppDataSource, ownedCryptoId: ObvCryptoId, apiKey: UUID) async throws -> ObvTypes.APIKeyElements {
        let apiKeyElements = try await engine.queryAPIKeyStatus(for: ownedCryptoId, apiKey: apiKey)
        return apiKeyElements
    }

}


// Helper

private final class LocalTrustOriginsListViewAppDataSourceDelegate: ObvTrustOriginsListViewAppDataSourceDelegate {
            
    private let engine: ObvEngine
    
    init(engine: ObvEngine) {
        self.engine = engine
    }

    func getAsyncStreamOfObvTrustOrigin(_ dataSource: ObvTrustOriginsListViewAppDataSource, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<[ObvTypes.ObvTrustOrigin]>) {
        return try await engine.getAsyncStreamOfObvTrustOrigin(contactIdentifier: contactIdentifier)
    }

    func finishAsyncStreamOfObvTrustOrigin(_ dataSource: ObvTrustOriginsListViewAppDataSource, streamUUID: UUID) {
        engine.finishAsyncStreamOfObvTrustOrigin(streamUUID: streamUUID)
    }

}


private final class LocalSingleGroupV1MainViewAppDataSourceDelegate: SingleGroupV1MainViewAppDataSourceDelegate {
            
    private let engine: ObvEngine
    
    init(engine: ObvEngine) {
        self.engine = engine
    }


    func getAsyncStreamOfJoinedGroupV1Details(_ dataSource: SingleGroupV1MainViewAppDataSource, groupIdentifier: ObvTypes.ObvGroupV1Identifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvTypes.ObvGroupTrustedAndPublishedDetails>) {
        return try await engine.getAsyncStreamOfJoinedGroupV1Details(groupIdentifier: groupIdentifier)
    }
    
    func finishAsyncStreamOfJoinedGroupV1Details(_ dataSource: SingleGroupV1MainViewAppDataSource, streamUUID: UUID) {
        engine.finishAsyncStreamOfJoinedGroupV1Details(streamUUID: streamUUID)
    }

}


private final class LocalEditGroupNameAndPictureViewAppDataSourceDelegate: EditGroupNameAndPictureViewAppDataSourceDelegate {
    
    private let engine: ObvEngine
    
    init(engine: ObvEngine) {
        self.engine = engine
    }

    func getAsyncStreamOfJoinedGroupV1Details(_ dataSource: EditGroupNameAndPictureViewAppDataSource, groupIdentifier: ObvTypes.ObvGroupV1Identifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvTypes.ObvGroupTrustedAndPublishedDetails>) {
        return try await engine.getAsyncStreamOfJoinedGroupV1Details(groupIdentifier: groupIdentifier)
    }
    
    func finishAsyncStreamOfJoinedGroupV1Details(_ dataSource: EditGroupNameAndPictureViewAppDataSource, streamUUID: UUID) {
        engine.finishAsyncStreamOfJoinedGroupV1Details(streamUUID: streamUUID)
    }
    
}


private final class LocalChooseDeviceToReactivateViewAppDataSourceDelegate: ObvChooseDeviceToReactivateViewAppDataSourceDelegate {
    
    private let engine: ObvEngine
    
    init(engine: ObvEngine) {
        self.engine = engine
    }

    func performOwnedDeviceDiscoveryNow(_ dataSource: ObvChooseDeviceToReactivateViewAppDataSource, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> ObvTypes.ObvOwnedDeviceDiscoveryResult {
        try await engine.performOwnedDeviceDiscoveryNow(ownedCryptoId: ownedCryptoId)
    }
    
}


private final class LocalOwnedDetailedInfosViewAppDataSourceDelegate: ObvOwnedDetailedInfosViewAppDataSourceDelegate {
        
    private let engine: ObvEngine
    
    init(engine: ObvEngine) {
        self.engine = engine
    }

    func getOwnedIdentityKeycloakState(_ dataSource: ObvOwnedDetailedInfosViewAppDataSource, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> ObvTypes.ObvKeycloakStateAndUserDetails? {
        return try await engine.getOwnedIdentityKeycloakState(with: ownedCryptoId)
    }
    
    func getRegisteredKeycloakAPIKey(_ dataSource: ObvOwnedDetailedInfosViewAppDataSource, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> UUID? {
        return try await engine.getKeycloakAPIKey(ownedCryptoId: ownedCryptoId)
    }

}
