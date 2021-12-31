/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import MobileCoreServices
import CoreDataStack
import ObvEngine
import ObvCrypto
import Contacts
import OlvidUtils

@objc(MainShareViewController)
final class MainShareViewController: UIViewController, ShareExtensionShouldUpdateToLatestVersionViewControllerDelegate {
    
    private var obvEngine: ObvEngine!
    private var hardLinksToFylesCoordinator: HardLinksToFylesCoordinator!
    private var thumbnailCoordinator: ThumbnailCoordinator!
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))
    private var shareNavigationController: UINavigationController!
    private let logSubsystem = "io.olvid.messenger.shareextension"
    private var observationTokens = [NSObjectProtocol]()
    private let inMemoryDraft = InMemoryDraft()
    private var selectedDiscussion: PersistedDiscussion?
    private let runningLog = RunningLogError()
    
    private let internalQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        queue.name = "PersistedDiscussionsUpdatesCoordinator internal queue"
        return queue
    }()

    var delegate: MainShareViewControllerDelegate?
    
    // These two Booleans allow to exit the share extension at the appropriate, by waiting that both are true before dismissing the share extension.
    // The engine one is set to true within a completion handler passed to the engine, that executes the completion handler as soon as an URLSession download task has been resumed. Of course, this is not visible from the Share Extension view point ;-)
    // The second Boolean is set to true as soon as the call the post method of the engine returns.
    private var engineHasCompletedEssentialPostTasks = false
    private var shareExtensionHasCompletedEssentialPostTasks = false
    
    var parentExtensionContext: NSExtensionContext! // Passed by the parent VC
    
    deinit {
        debugPrint("deinit of MainShareViewController")
    }
    
    private func initializeObliviousEngine(runningLog: RunningLogError) throws {
        do {
            let mainEngineContainer = ObvMessengerConstants.containerURL.mainEngineContainer
            ObvEngine.mainContainerURL = mainEngineContainer
            obvEngine = try ObvEngine.startLimitedToSending(logPrefix: "LimitedEngine",
                                                            sharedContainerIdentifier: ObvMessengerConstants.appGroupIdentifier,
                                                            supportBackgroundTasks: ObvMessengerConstants.isRunningOnRealDevice,
                                                            appType: .shareExtension,
                                                            runningLog: runningLog)
            debugPrint("The Oblivious Engine was initialized")
        } catch {
            debugPrint("[ERROR] Could not initialize the Oblivious Engine")
            throw NSError()
        }
    }
    
    
    private func observeNSManagedObjectContextDidSaveNotifications() {
        let NotificationName = NSNotification.Name.NSManagedObjectContextDidSave
        let token = NotificationCenter.default.addObserver(forName: NotificationName, object: nil, queue: OperationQueue.main) { (notification) in
            ObvStack.shared.viewContext.mergeChanges(fromContextDidSave: notification)
        }
        observationTokens.append(token)
    }
    
    
    /// This is called when starting the share extension. This allows to make sure that all the registered
    /// object within the view context a refetched from the database, so that they are up to date.
    /// Warning: this does not solve all issues. One issue that is not solved is the following: the user sends an attachment using the share
    /// extensions. The attachment gets uploaded. The user starts the share extension again (without opening the app), the progress of the previous
    /// uploaded file does not reflect an appropriate progress. The reason is that this is indeed what the app database knows about. If, instead, the user
    /// starts the app, the app database gets updated (with a bootstrapping mechanism). If the user then closes the app and get back to the share extension,
    /// everything is updated as expected. So this method is really usefull to update the viewContext, nothing more.
    private func refreshObjectsInViewContext() {
        for object in ObvStack.shared.viewContext.registeredObjects {
            ObvStack.shared.viewContext.refresh(object, mergeChanges: false)
        }
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        os_log("Views loaded within the share extension", log: log, type: .debug)
        
        // Initialize the CoreData Stack
        do {
            try ObvStack.initSharedInstance(transactionAuthor: ObvMessengerConstants.AppType.shareExtension.transactionAuthor, runningLog: runningLog, enableMigrations: false)
        } catch let error {
            os_log("Could initialize the ObvStack within the main share view controller: %{public}@", log: log, type: .fault, error.localizedDescription)
            if (error as NSError).code == CoreDataStackErrorCodes.migrationRequiredButNotEnabled.rawValue {
                let vc = ShareExtensionShouldUpdateToLatestVersionViewController()
                vc.delegate = self
                displayContentController(content: vc)
                return
            } else {
                return animateOutAndExit()
            }
        }

        // Initialize the Oblivious Engine
        do {
            try initializeObliviousEngine(runningLog: runningLog)
        } catch {
            os_log("Could initialize the engine within the main share view controller", log: log, type: .fault)
            return animateOutAndExit()
        }
        
        // Initialize the coordinators that allow to compute thumbnails
        self.hardLinksToFylesCoordinator = HardLinksToFylesCoordinator(appType: .shareExtension)
        self.thumbnailCoordinator = ThumbnailCoordinator(appType: .shareExtension)
        
        // Initialize the theming
        _ = AppTheme.shared
        
        // Updating the view context
        refreshObjectsInViewContext()
        
        prepareComposeMessageDataSource()
        
        let allDiscussionsVC = AllDiscussionsViewController()
        allDiscussionsVC.delegate = self
        allDiscussionsVC.title = CommonString.Word.Discussions
        
        shareNavigationController = ObvNavigationController(rootViewController: allDiscussionsVC)
        shareNavigationController.navigationBar.prefersLargeTitles = true
        
        let cancelButtom = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(userSelectedCancel))
        allDiscussionsVC.navigationItem.setLeftBarButton(cancelButtom, animated: false)
        
        displayContentController(content: shareNavigationController)
    }
    
    
    override func didReceiveMemoryWarning() {
        os_log("Did receive memory warning (MainShareViewController)", log: log, type: .fault)
    }
    
    
    @objc(userSelectedCancel)
    private func userSelectedCancel() {
        return animateOutAndExit()
    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        animateIn()
    }
    
    
    private func animateIn() {
        self.view.transform = CGAffineTransform(translationX: 0, y: self.view.frame.size.height)
        UIView.animate(withDuration: 0.25, animations: { () -> Void in
            self.view.transform = CGAffineTransform.identity
        })
    }
    
    
    private func tryToAnimateOutAndExit() {
        assert(Thread.isMainThread)
        guard self.engineHasCompletedEssentialPostTasks == true else { return }
        guard self.shareExtensionHasCompletedEssentialPostTasks == true else { return }
        
        // We can dimiss. Show a checkmark HUD, wait for a little time and exit
        
        self.showHUD(type: .checkmark) {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1000)) { [weak self] in
                self?.animateOutAndExit()
            }
        }
        
    }
    
    
    func animateOutAndExit() {
        assert(Thread.isMainThread)
        delegate?.animateOutAndExit()
    }
    

    private var attachmentsAreReady = false
    
    private func prepareComposeMessageDataSource() {
        
        guard let content = parentExtensionContext.inputItems[0] as? NSExtensionItem else { return }
        
        guard let itemProviders = content.attachments else {
            os_log("No attachment to process within the share extension", log: log, type: .error)
            return
        }
        
        let op = LoadFileRepresentationsThenCreateInMemoryDraftFyleCompositeOperation(inMemoryDraft: inMemoryDraft, itemProviders: itemProviders, log: log)
        op.completionBlock = { [weak self] in
            DispatchQueue.main.async {
                self?.attachmentsAreReady = true
                self?.tryToShowDiscussion()
            }
        }
        internalQueue.addOperation(op)
        
        
    }
    
}


extension MainShareViewController: AllDiscussionsViewControllerDelegate {
    
    func userDidSelect(_ selectedDiscussion: PersistedDiscussion) {
        os_log("User did select a persisted discussion", log: log, type: .debug)
        self.selectedDiscussion = selectedDiscussion
        tryToShowDiscussion()
    }
    
    
    private func tryToShowDiscussion() {
        
        assert(Thread.isMainThread)
        
        hideHUD()
        
        guard attachmentsAreReady else {
            showHUD(type: .spinner)
            return
        }
        
        NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType).refreshAllObjects()
        guard let selectedDiscussion = self.selectedDiscussion else { return }
        guard selectedDiscussion.managedObjectContext == ObvStack.shared.viewContext else { assertionFailure(); return }
        inMemoryDraft.setDiscussion(to: selectedDiscussion)
        guard inMemoryDraft.isReady else { return }
        
        let singleDiscussionVC = SingleDiscussionViewController(collectionViewLayout: UICollectionViewLayout())
        singleDiscussionVC.hideProgresses = true
        singleDiscussionVC.discussion = selectedDiscussion
        singleDiscussionVC.restrictToLastMessages = true
        singleDiscussionVC.composeMessageViewDataSource = ComposeMessageDataSourceInMemory(inMemoryDraft: inMemoryDraft)
        singleDiscussionVC.composeMessageViewDocumentPickerDelegate = nil
        singleDiscussionVC.weakComposeMessageViewSendMessageDelegate = self
        singleDiscussionVC.uiApplication = nil
        
        let cancelButtom = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(userSelectedCancel))
        singleDiscussionVC.navigationItem.setLeftBarButton(cancelButtom, animated: false)
        
        os_log("We will now push the single discussion view controller", log: log, type: .debug)
        
        shareNavigationController.pushViewController(singleDiscussionVC, animated: true)
        
    }
    
}


// MARK: - ComposeMessageViewSendMessageDelegate


extension MainShareViewController: ComposeMessageViewSendMessageDelegate {
    
    func userWantsToSendMessageInComposeMessageView(_ composeMessageView: ComposeMessageView) {
        
        assert(Thread.current.isMainThread)
        
        guard inMemoryDraft.isReady else { return }
        
        composeMessageView.freeze()
        defer {
            DispatchQueue.main.async {
                composeMessageView.unfreeze()
            }
        }

        inMemoryDraft.body = composeMessageView.textView.text // Within the share extension, this is the only thing that may have changed
        
        let op1 = CreateUnprocessedPersistedMessageSentFromInMemoryDraftOperation(inMemoryDraft: inMemoryDraft)
        internalQueue.addOperations([op1], waitUntilFinished: true)

        guard !op1.isCancelled else {
            if let reason = op1.reasonForCancel {
                os_log("CreateUnprocessedPersistedMessageSentFromInMemoryDraftOperation failed: %{public}@", log: log, type: reason.logType, reason.localizedDescription)
            } else {
                assertionFailure()
                os_log("CrateUnprocessedPersistedMessageSentFromPersistedDraftOperation failed without specifying a reason. This is a bug.", log: log, type: .fault)
            }
            DispatchQueue.main.async { [weak self] in self?.animateOutAndExit() }
            return
        }

        guard let persistedMessageSentObjectID = op1.persistedMessageSentObjectID else {
            os_log("CrateUnprocessedPersistedMessageSentFromPersistedDraftOperation did not cancel but we did not return a persistedMessageSentObjectID. This is a bug.", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let op2 = ComputeExtendedPayloadOperation(persistedMessageSentObjectID: persistedMessageSentObjectID)
        let op3 = SendUnprocessedPersistedMessageSentOperation(persistedMessageSentObjectID: persistedMessageSentObjectID, extendedPayloadOp: op2, obvEngine: obvEngine) { [weak self] in
            // This completion handler is called when all the expectations of the flow have been met, i.e., when all the attachment(s) chunk(s) have been resumed.
            DispatchQueue.main.async {
                self?.engineHasCompletedEssentialPostTasks = true
                self?.tryToAnimateOutAndExit()
            }
        }
        
        let log = self.log
        let composedOp = CompositionOfTwoContextualOperations(op1: op2, op2: op3, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        composedOp.completionBlock = {
            guard !op3.isCancelled else {
                if let reason = op3.reasonForCancel {
                    os_log("SendUnprocessedPersistedMessageSentOperation failed: %{public}@", log: log, type: reason.logType, reason.localizedDescription)
                } else {
                    assertionFailure()
                    os_log("SendUnprocessedPersistedMessageSentOperation failed without specifying a reason. This is a bug.", log: log, type: .fault)
                }
                DispatchQueue.main.async { [weak self] in self?.animateOutAndExit() }
                return
            }
            
            DispatchQueue.main.async { [weak self] in
                
                // Quick and dirty way to clear the text field and to remove the attachments from the keyboard accessory
                self?.inMemoryDraft.reset()
                composeMessageView.clearText()
                composeMessageView.collectionView.reloadData()
                composeMessageView.textView.resignFirstResponder()
                
                // Try to hide the share extension
                self?.shareExtensionHasCompletedEssentialPostTasks = true
                self?.tryToAnimateOutAndExit()
                
                // Display a HUD asking the user to wait until we have resumed the required attachment tasks
                self?.showHUD(type: .spinner)

            }
        }
        
        internalQueue.addOperations([composedOp], waitUntilFinished: false) // We cannot set true here
        
    }
    
}


protocol MainShareViewControllerDelegate: AnyObject {
    
    func animateOutAndExit()
    
}
