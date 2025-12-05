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
  

import CoreData
import OSLog
import ObvCoreDataStack
import Foundation
import Intents
import UniformTypeIdentifiers
import ObvAppCoreConstants
import ObvEngine
import ObvTypes
import OlvidUtils
import SwiftUI
import ObvUICoreData
import ObvSettings
import ObvAppTypes


@objc(ShareViewController)
final class ShareViewController: UIViewController, ShareExtensionErrorViewControllerDelegate {

    private static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: "ShareViewController"))
    private let runningLog = RunningLogError()
    private let localAuthenticationDelegate: LocalAuthenticationDelegate = LocalAuthenticationManager()
    private let internalQueue = OperationQueue.createSerialQueue(name: "ShareViewController internal queue", qualityOfService: .userInitiated)
    private let userDefaults = UserDefaults(suiteName: ObvAppCoreConstants.appGroupIdentifier)

    private var shareViewHostingController: ShareViewHostingController?
    private var localAuthenticationViewController: LocalAuthenticationViewController?

    private var obvEngine: ObvEngine!
    private var model: ShareViewModel?

    private var wipeOp: WipeAllReadOnceAndLimitedVisibilityMessagesAfterLockOutOperation?

    private var observationTokens = [NSObjectProtocol]()

    private static let errorDomain = "ShareViewController"
    private static func makeError(message: String) -> Error { NSError(domain: Self.errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private var initializationPerformed = false

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        observeNotifications()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func observeNotifications() {
        observationTokens.append(contentsOf: [
            NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] (notification) in
                if ObvMessengerSettings.Privacy.localAuthenticationPolicy.lockScreen {
                    // Cancel to close the view if the share extention enter background mode, to avoid to stay authenticate indefinitely in background.
                    self?.cancelRequest()
                }
                self?.earlyAbortWipe()
            },
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Task {
            await performInitializationIfRequired()
        }
    }
    
    @MainActor
    private func performInitializationIfRequired() async {
        
        guard !initializationPerformed else { return }
        defer { initializationPerformed = true }
        
        do {
            // Initialize the CoreData Stack
            try ObvStack.initSharedInstance(transactionAuthor: ObvUICoreDataConstants.AppCategory.shareExtension.transactionAuthor, runningLog: runningLog, enableMigrations: false)

            // Initialize the Oblivious Engine
            try await initializeObliviousEngine(runningLog: runningLog)
        } catch let error {
            os_log("📤 Could not initialize the ObvStack and Engine within the main share view controller: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            if (error as NSError).code == CoreDataStackErrorCodes.migrationRequiredButNotEnabled.rawValue {
                let vc = ShareExtensionErrorViewController()
                vc.delegate = self
                vc.reason = .shouldUpdateToLatestVersion
                displayContentController(content: vc)
                return
            } else {
                let vc = ShareExtensionErrorViewController()
                vc.delegate = self
                vc.reason = .shouldLaunchTheApp
                displayContentController(content: vc)
                return
            }
        }

        // Make sure at least one owned identity has been generated within the main app
        
        let model: ShareViewModel
        do {
            let allOwnedIdentities = try PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentities(within: ObvStack.shared.viewContext)
            guard !allOwnedIdentities.isEmpty else {
                throw Self.makeError(message: "Cannot find any owned identity")
            }
            model = try ShareViewModel(allOwnedIdentities: allOwnedIdentities)
            self.model = model
        } catch {
            let vc = ShareExtensionErrorViewController()
            vc.delegate = self
            vc.reason = .shouldLaunchTheApp
            displayContentController(content: vc)
            return
        }

        // Instantiate the two view controllers that we might need and add them as child view controllers
        // The appropriate vc view will be added as a subview later, in showAppropriateViewControllerView()
        let shareViewHostingController = ShareViewHostingController(obvEngine: self.obvEngine,
                                                                    model: model,
                                                                    internalQueue: internalQueue,
                                                                    userDefaults: userDefaults)
        shareViewHostingController.delegate = self
        self.addChild(shareViewHostingController)
        shareViewHostingController.didMove(toParent: self)
        self.shareViewHostingController = shareViewHostingController

        let localAuthenticationViewController = LocalAuthenticationViewController(
            localAuthenticationDelegate: localAuthenticationDelegate,
            delegate: self)
        self.addChild(localAuthenticationViewController)
        localAuthenticationViewController.didMove(toParent: self)
        self.localAuthenticationViewController = localAuthenticationViewController

        // Show the appropriate view controller
        showAppropriateViewControllerView()

    }
    

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task {
            await performInitializationIfRequired()
            await authenticateIfRequired()
        }
    }

    
    private func showAppropriateViewControllerView() {
        
        guard let localAuthenticationViewController = localAuthenticationViewController else { assertionFailure(); return }
        guard let shareViewHostingController = shareViewHostingController else { assertionFailure(); return }
        guard let model else { assertionFailure(); return }

        let vcToShow = !model.isAuthenticated ? localAuthenticationViewController : shareViewHostingController
        let vcToHide = model.isAuthenticated ? localAuthenticationViewController : shareViewHostingController

        guard vcToShow.view.superview == nil else {
            // Nothing to do, the vc to show is already shown
            return
        }
        
        self.view.addSubview(vcToShow.view)
        vcToShow.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.pinAllSidesToSides(of: vcToShow.view)
        vcToShow.view.alpha = 0.0

        guard vcToHide.view.superview != nil else {
            // There is no vc to hide, we only show the vc to show without animation
            vcToShow.view.alpha = 1.0
            return
        }
        
        // If we reach this point, we can animate the transition from the vc to hide to the vc to show
        
        assert(vcToHide.view.superview != nil)
        assert(vcToShow.view.superview != nil)

        UIView.animate(withDuration: 0.1) {
            vcToShow.view.alpha = 1.0
        } completion: { finished in
            vcToHide.view.removeFromSuperview()
        }
    }
    
    
    private func authenticateIfRequired() async {
        guard let model else { assertionFailure("Should not occur. May be nil under testing conditions via Xcode with no owned identity set up."); return }
        if !model.isAuthenticated {
            await localAuthenticationViewController?.performLocalAuthentication(
                customPasscodePresentingViewController: self,
                uptimeAtTheTimeOfChangeoverToNotActiveState: nil)
        }
    }

    private func initializeObliviousEngine(runningLog: RunningLogError) async throws {
        do {
            let mainEngineContainer = ObvUICoreDataConstants.ContainerURL.mainEngineContainer.url
            ObvEngine.mainContainerURL = mainEngineContainer
            obvEngine = try await ObvEngine.startLimitedToSending(logPrefix: "LimitedEngine",
                                                                  sharedContainerIdentifier: ObvAppCoreConstants.appGroupIdentifier,
                                                                  supportBackgroundTasks: ObvMessengerConstants.isRunningOnRealDevice,
                                                                  remoteNotificationByteIdentifierForServer: ObvAppCoreConstants.remoteNotificationByteIdentifierForServer,
                                                                  appType: .shareExtension,
                                                                  runningLog: runningLog)
            debugPrint("The Oblivious Engine was initialized")
        } catch {
            debugPrint("[ERROR] Could not initialize the Oblivious Engine")
            throw Self.makeError(message: "Could not initialize the Oblivious Engine")
        }
    }
    
    private func completeRequest() {
        os_log("📤 Complete request.", log: Self.log, type: .info)
        doCompleteRequest()
    }

    private func doCompleteRequest() {
        shareViewHostingController = nil
        localAuthenticationViewController = nil
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.earlyAbortWipe()
    }

    // In the case where the share view is dismiss or put in backgroung while a wipe operation is running, we stop the operation ti be sure to have enough time to save the context even if the some messages was not deleted.
    // The operation take care to inform the app to finish to wipe.
    private func earlyAbortWipe() {
        // If `wipeOp` is nil, no wipe is in progress
        wipeOp?.earlyAbortWipe = true
    }

}

extension ShareViewController: ShareViewHostingControllerDelegate {

    var firstInputItems: NSExtensionItem? {
        extensionContext?.inputItems.first as? NSExtensionItem
    }

    var conversationIdentifier: String? {
        guard let intent = extensionContext?.intent else { return nil }
        guard let sendMessageIntent = intent as? INSendMessageIntent else { return nil }
        return sendMessageIntent.conversationIdentifier
    }

    func showProgress(progress: Progress) {
        showHUD(type: .progress(progress: progress))
    }
    
    func showSuccessAndCompleteRequestAfter(deadline: DispatchTime) {
        DispatchQueue.main.asyncAfter(deadline: deadline) { [weak self] in
            self?.showHUD(type: .checkmark) {
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                    self?.completeRequest()
                }
            }
        }
    }
    
    func showErrorAndCancelRequest() {
        DispatchQueue.main.async {
            self.showHUD(type: .text(text: CommonString.Word.Error)) {
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                    self.cancelRequest()
                }
            }
        }
    }


    func cancelRequest() {
        os_log("📤 Cancel request.", log: Self.log, type: .info)
        doCompleteRequest()
    }


}

extension ShareViewController: LocalAuthenticationViewControllerDelegate {

    func userLocalAuthenticationDidSucceed(authenticationWasPerformed: Bool) async {
        assert(Thread.isMainThread)
        assert(model != nil)
        self.model?.isAuthenticated = true
        showAppropriateViewControllerView()
    }

    func tooManyWrongPasscodeAttemptsCausedLockOut() {
        assert(Thread.isMainThread)
        let flowId = FlowIdentifier()
        let obvContext = ObvStack.shared.newBackgroundContext(flowId: flowId)

        guard ObvMessengerSettings.Privacy.lockoutCleanEphemeral else { return }

        wipeOp = WipeAllReadOnceAndLimitedVisibilityMessagesAfterLockOutOperation(userDefaults: userDefaults,
                                                                                  appType: .shareExtension,
                                                                                  wipeType: .startWipeFromAppOrShareExtension,
                                                                                  delegate: self)
        guard let wipeOp = wipeOp else { assertionFailure(); return }

        wipeOp.viewContext = ObvStack.shared.viewContext
        wipeOp.obvContext = obvContext
        internalQueue.addOperations([wipeOp], waitUntilFinished: false)

        let saveOp = SaveContextOperation(userDefaults: userDefaults)
        saveOp.viewContext = ObvStack.shared.viewContext
        saveOp.obvContext = obvContext
        internalQueue.addOperations([saveOp], waitUntilFinished: false)
    }
}


extension ShareViewController: WipeAllReadOnceAndLimitedVisibilityMessagesAfterLockOutOperationDelegate {

    func setExtensionFailedToWipeAllEphemeralMessagesBeforeDateOnUserDefaults(timestampOfLastMessageToWipe: Date?) {
        guard let userDefaults else { assertionFailure(); return }
        userDefaults.setExtensionFailedToWipeAllEphemeralMessagesBeforeDate(with: timestampOfLastMessageToWipe)
        ObvDarwinNotificationCenter.shared.post(ObvDarwinNotificationName.shareExtensionFailedToWipeAllEphemeralMessagesBeforeDate)
    }
    
}


protocol ShareViewHostingControllerDelegate: AnyObject {
    var firstInputItems: NSExtensionItem? { get }
    var conversationIdentifier: String? { get }

    func showProgress(progress: Progress)
    func showSuccessAndCompleteRequestAfter(deadline: DispatchTime)
    func showErrorAndCancelRequest()
    func cancelRequest()
}



// MARK: - ShareViewHostingController

final class ShareViewHostingController: UIHostingController<ShareView>, ShareViewModelDelegate {

    private static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: "ShareViewHostingController"))
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: "ShareViewHostingController"))
    private static let errorDomain = "ShareViewHostingController"
    private static func makeError(message: String) -> Error { NSError(domain: Self.errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    private let flowId: FlowIdentifier
    private let obvEngine: ObvEngine
    private let obvContext: ObvContext
    private let model: ShareViewModel
    private let internalQueue: OperationQueue
    private let userDefaults: UserDefaults?

    private var fyleJoinsProvider: FyleJoinsProvider?
    private var hardLinksToFylesManager: HardLinksToFylesManager!

    private var cacheOfLinkMetadata = [URL: ObvLinkMetadata]()
    
    private let loadItemProviderHelper = LoadItemProviderHelper()

    weak var delegate: ShareViewHostingControllerDelegate?

    init(obvEngine: ObvEngine, model: ShareViewModel, internalQueue: OperationQueue, userDefaults: UserDefaults?) {
        assert(Thread.isMainThread)
        
        self.flowId = FlowIdentifier()
        self.obvContext = ObvStack.shared.newBackgroundContext(flowId: flowId)
        self.obvEngine = obvEngine
        self.model = model
        self.internalQueue = internalQueue
        self.userDefaults = userDefaults

        let shareView = ShareView(model: model)
        super.init(rootView: shareView)
        self.model.delegate = self

        // Initialize the coordinators that allow to compute thumbnails
        self.hardLinksToFylesManager = HardLinksToFylesManager.makeHardLinksToFylesManagerForShareExtension()
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func closeView() {
        delegate?.cancelRequest()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.setupNavigationBar()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        Task {
            // Set the appropriate discussion
            try await model.setSelectedDiscussions(to: [])
            if let conversationIdentifier = delegate?.conversationIdentifier,
               let discussionIdentifier = ObvDiscussionIdentifier(conversationIdentifier),
               let discussion = try? PersistedDiscussion.getPersistedDiscussion(discussionIdentifier: discussionIdentifier, within: ObvStack.shared.viewContext) {
                try await model.setSelectedDiscussions(to: [discussion])
            }
            // Load the attachments
            do {
                try await initializeOperations()
            } catch {
                Self.logger.fault("Failed to load attachments: \(error.localizedDescription, privacy: .public)")
                delegate?.showErrorAndCancelRequest()
            }
        }
    }
    

    private func badge() -> UIImage? {
        guard let image = UIImage(named: "badge") else { return nil }
        let newSize = CGSize(width: 30.0, height: 30.0)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
        image.draw(in: CGRect(x: 0.0, y: 0.0, width: newSize.width, height: newSize.height))
        let newImage: UIImage? = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage
    }

    private func setupNavigationBar() {
        guard let item = navigationController?.navigationBar.items?.first else { return }
        item.rightBarButtonItem?.image = UIImage(systemIcon: .paperplaneFill)
        if let image = badge() {
            let imageView = UIImageView(image: image)
            item.titleView = imageView
        }
    }
    
    
    private enum ObvError: Error {
        case noAttachmentToProcess
        case couldNotLoadAnyAttachment
    }

    /// This method queues operations that can be executed independently of the discussion that will be selected by the user. The result of these operations will be used by operations later queued in ``func userWantsToSendMessages(to discussions: [PersistedDiscussion])``
    /// The last operation RequestHardLinksToFylesOperation is not required to send messages, but it is used to show previews of attachments in ShareView.
    private func initializeOperations() async throws {

        // Load the item providers
        
        guard let content = delegate?.firstInputItems else { return }
        let logger = Self.logger

        guard let itemProviders = content.attachments else {
            Self.logger.fault("No attachment to process within the share extension")
            throw ObvError.noAttachmentToProcess
        }
        
        let loadedItemProviders = try await self.loadItemProviderHelper.load(itemProviders, source: .shareExtension, progressProvider: nil)

        guard !loadedItemProviders.isEmpty else {
            Self.logger.fault("No attachment to process within the share extension")
            throw ObvError.couldNotLoadAnyAttachment
        }
        
        // Compute [Fyle] and [String] from [LoadedItemProvider]
        
        let op1 = CreateFylesFromLoadedFileRepresentationsOperation(loadedItemProviders: loadedItemProviders)
        self.fyleJoinsProvider = op1
        op1.viewContext = ObvStack.shared.viewContext
        op1.obvContext = obvContext
        op1.completionBlock = { [weak self] in
            guard let _self = self else { return }
            logger.info("📤 Create Fyles From Loaded File Representations Operation done.")
            guard let bodyTexts = op1.bodyTexts else { assertionFailure(); return }
            Task { @MainActor in
                _self.model.setBodyTexts(bodyTexts)
            }
        }
        internalQueue.addOperation(op1) // Don't wait
        
        let op2 = RequestHardLinksToFylesOperation(hardLinksToFylesManager: hardLinksToFylesManager, fyleJoinsProvider: op1)
        op2.completionBlock = { [weak self] in
            guard let _self = self else { return }
            logger.info("📤 Request HardLinks To Fyle Operation done.")
            guard let hardlinks = op2.hardlinks else { assertionFailure(); return }
            // Make sure we have a non-empty set of hardlinks. If this is not the case, we have nothing to share and thus show an error screen.
            guard !hardlinks.isEmpty else {
                logger.fault("📤 The set of hardlinks is empty. Nothing to share.")
                return
            }
            _self.model.setHardlinks(hardlinks)
        }
        op2.addDependency(op1)
        internalQueue.addOperation(op2) // Don't wait

        // If there is a link among the [LoadedItemProvider], this operation fetches a "link preview" for it so that we can add it to the message once the message is sent.
        
        if ObvMessengerSettings.Discussions.attachLinkPreviewToMessageSent {
            let op4 = FetchAndCacheObvLinkMetadataForFirstURLInLoadedItemProvidersOperation(
                loadedItemProvidersToPaste: loadedItemProviders.toPaste,
                currentURLsInCache: Set(cacheOfLinkMetadata.keys))
            op4.addDependency(op1)
            op4.completionBlock = {
                guard let (url, linkMetadata) = op4.fetchedMetadata else { return }
                DispatchQueue.main.async { [weak self] in
                    self?.cacheOfLinkMetadata[url] = linkMetadata
                }
            }
            internalQueue.addOperation(op4)
        }
                
        // Note that the (global) obvContext is *not* saved at this point. We will do it later, in ``func userWantsToSendMessages(to discussions: [PersistedDiscussion])``
        
    }
    
    
    /// This method creates all the `PersistedMessageSent` that we will have to send. It is called after the user taps on the "send" button.
    /// Note that the pre-processing made in `initializeOperations` did create the `fyleJoinsProvider` global variable that are required here.
    /// This method saves the global `obvContext` that was *not* saved in the `initializeOperations()` method: this makes it possible to have atomicity.
    private func createAllMessagesToSend(discussions: [PersistedDiscussion]) async throws -> [MessageSentPermanentID] {
        
        assert(Thread.isMainThread)
        
        let body: String? = model.text.trimmingWhitespacesAndNewlinesAndMapToNilIfZeroLength()
        guard let fyleJoinsProvider = self.fyleJoinsProvider else { assertionFailure(); return [] }
        
        // The operations executed in the initializeOperations() may provide attachments (i.e., FyleJoins) that we want to send with the message.
        // We get those attachments now

        assert(fyleJoinsProvider.isFinished)
        var fyleJoins = fyleJoinsProvider.fyleJoins
        
        // If the body contains an https URL, we might have a link preview available for in our local cache.
        // If this is the case, we add that "link preview" to the attachments (i.e., to the fyleJoins)
        // The operations executed to load and add the attachment are the same than those used in initializeOperations().
        
        if ObvMessengerSettings.Discussions.attachLinkPreviewToMessageSent {
            if let urlInBody = body?.extractURLs().filter({ $0.scheme?.lowercased() == "https" }).first, let linkMetadata = cacheOfLinkMetadata[urlInBody] {
                let itemProvider = NSItemProvider(item: linkMetadata, typeIdentifier: UTType.olvidLinkPreview.identifier)
                let loadedItemProviders = try await self.loadItemProviderHelper.load(itemProvider, source: .shareExtension, progressProvider: nil)
                let op1 = CreateFylesFromLoadedFileRepresentationsOperation(loadedItemProviders: loadedItemProviders)
                op1.viewContext = ObvStack.shared.viewContext
                op1.obvContext = obvContext
                await internalQueue.addAndAwaitOperation(op1)
                if let linkPreviewFyleJoins = op1.fyleJoins {
                    fyleJoins?.append(contentsOf: linkPreviewFyleJoins)
                }
            }
        }
        
        cacheOfLinkMetadata.removeAll()
        
        // Create and queue the operations allowing to create all the PersistedMessageSent
        
        var createMsgOps = [CreateUnprocessedPersistedMessageSentFromFylesAndStrings]()
        for discussion in discussions {
            let op = CreateUnprocessedPersistedMessageSentFromFylesAndStrings(body: body, fyleJoins: fyleJoins, discussionObjectID: discussion.typedObjectID, log: Self.log)
            op.viewContext = ObvStack.shared.viewContext
            op.obvContext = obvContext
            let log = Self.log
            op.completionBlock = {
                guard let index = discussions.firstIndex(of: discussion) else { return }
                os_log("📤 [%{public}@/%{public}@] Create Unprocessed Persisted Message Sent From Fyles And Strings done.", log: log, type: .info, String(index + 1), String(discussions.count))
            }
            createMsgOps.append(op)
            internalQueue.addOperation(op)
        }

        // Create the operation that saves the global context
        
        let saveOp = SaveContextOperation(userDefaults: userDefaults)
        saveOp.viewContext = ObvStack.shared.viewContext
        saveOp.obvContext = obvContext
        
        // Queue the save operation and wait until it is finished (and all ops are successfull) before returning the ObjectIDs of the create persisted messages to send.
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[MessageSentPermanentID], Error>) in
            internalQueue.addOperations([saveOp], waitUntilFinished: true)
            // Since we wait on a serial queue for the saveOp to be finished, we know that when reaching this point, all previous operations are also finished
            guard createMsgOps.allSatisfy({ !$0.isCancelled }) && !saveOp.isCancelled else {
                continuation.resume(throwing: Self.makeError(message: "Could not create all messages to send"))
                return
            }
            let messageSentPermanentIDs = createMsgOps.compactMap({ $0.messageSentPermanentID })
            assert(messageSentPermanentIDs.count == createMsgOps.count)
            continuation.resume(returning: messageSentPermanentIDs)
        }
    }


    /// This method performs an engine request allowing to send the message referenced by the `messageObjectID` parameter. It returns *after* the PersistedMessageSent is modified in DB using the identifier returned by the engine.
    /// The `dispatchGroupForEngine` parameter will allow to wait until all the engine completion handler are called before dismissing the share extension view.
    private func sendUnprocessedMessageToSend(_ messageSentPermanentID: MessageSentPermanentID, dispatchGroupForEngine: DispatchGroup, progress: Progress) async throws {

        let obvContext = ObvStack.shared.newBackgroundContext(flowId: flowId)
        
        // Send the message with the engine.
        // Note that this code should be improved: we rely on the fact that the completion handler called by the engine is never called if the operation cancels.
        // We are indeed supposing that exacly one of these callbacks is called.
        // 2024-12-18: Since we set callCompletionWhenMessageAndAttachmentsAreSent=true, the completion is called when all attachments are sent (i.e., stored on the server).
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // When callCompletionWhenMessageAndAttachmentsAreSent is set to true, the engine waits until the message to sent is deleted from the outbox before calling the completion
            // handler passed to SendUnprocessedPersistedMessageSentOperation. This is not ok under macOS, as it is often the case that the message is actually sent by the app instead of
            // the extension (probably, because the attachment is sent by a background session, which makes it possible for the app to be notified instead of the share extension).
            // In that case, the engine (of the share extension) is never notified that the message was deleted from its outbox, and thus our callback is never called. For this reason,
            // under macOS, we don't wait until the message is sent to call the completion handler.
            #if targetEnvironment(macCatalyst)
            let op = SendUnprocessedPersistedMessageSentOperation(messageSentPermanentID: messageSentPermanentID, alsoPostToOtherOwnedDevices: true, extendedPayloadProvider: nil, obvEngine: obvEngine)
            progress.completedUnitCount += 1
            #else
            dispatchGroupForEngine.enter()
            let op = SendUnprocessedPersistedMessageSentOperation(messageSentPermanentID: messageSentPermanentID, alsoPostToOtherOwnedDevices: true, extendedPayloadProvider: nil, obvEngine: obvEngine, callCompletionWhenMessageAndAttachmentsAreSent: true) {
                // Called by the engine when the message and its attachments were taken into account
                progress.completedUnitCount += 1
                dispatchGroupForEngine.leave()
            }
            #endif
            op.viewContext = ObvStack.shared.viewContext
            op.obvContext = obvContext
            internalQueue.addOperations([op], waitUntilFinished: true)
            guard !op.isCancelled else {
                continuation.resume(throwing: Self.makeError(message: "SendUnprocessedPersistedMessageSentOperation failed"))
                return
            }
            
            let saveOp = SaveContextOperation(userDefaults: userDefaults)
            saveOp.viewContext = ObvStack.shared.viewContext
            saveOp.obvContext = obvContext
            internalQueue.addOperations([saveOp], waitUntilFinished: true)
            
            if saveOp.isCancelled {
                continuation.resume(throwing: Self.makeError(message: "SaveContextOperation failed in sendUnprocessedMessageToSend"))
            } else {
                continuation.resume()
            }
        }
    }
    
    
    
    func userWantsToSendMessages(to discussions: [PersistedDiscussion]) async {
        
        assert(Thread.isMainThread)
        
        os_log("📤 Sending message", log: Self.log, type: .info)
        
        guard !discussions.isEmpty else { assertionFailure(); return }

        let progress = Progress(totalUnitCount: Int64(2*discussions.count + 2))
        progress.isCancellable = false
        delegate?.showProgress(progress: progress)
        
        let messageSentPermanentIDs: [MessageSentPermanentID]
        do {
            messageSentPermanentIDs = try await createAllMessagesToSend(discussions: discussions)
        } catch {
            os_log("📤 Could not create all messages to send: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            delegate?.showErrorAndCancelRequest()
            return
        }
        progress.completedUnitCount += 1

        // If we reach this point, all the PersistedMessageSent are saved in the App DB. They are still unprocessed though.
        // We now send them one by one using the engine.
        
        let dispatchGroupForEngine = DispatchGroup()
        
        for messageSentPermanentID in messageSentPermanentIDs {
            do {
                try await sendUnprocessedMessageToSend(messageSentPermanentID, dispatchGroupForEngine: dispatchGroupForEngine, progress: progress)
            } catch {
                os_log("📤 Could not send one of the messages", log: Self.log, type: .fault, error.localizedDescription)
                assertionFailure() // Continue anyway
            }
            progress.completedUnitCount += 1
        }
        
        // We wait until all the engine completion handler are called before going any further
        
        internalQueue.addOperation { [weak self] in
            dispatchGroupForEngine.wait()
            progress.completedUnitCount += 1  
            // If we reach this point, we know for sure that *all* messages to send were sent by the engine
            debugPrint(progress.completedUnitCount, progress.totalUnitCount)
            Task { await ObvDarwinNotificationCenter.shared.post(ObvDarwinNotificationName.shareExtensionDidPostMessage) }
            // Give some time to the progress to reach 100 percent and complete the request
            Task { [weak self] in
                await self?.delegate?.showSuccessAndCompleteRequestAfter(deadline: .now() + .milliseconds(300))
            }
        }

    }

}
