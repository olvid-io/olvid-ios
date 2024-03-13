/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import os.log
import CoreData
import ObvCrypto
import ObvMetaManager
import ObvProtocolManager
import ObvNotificationCenter
import ObvNetworkSendManager
import ObvNetworkFetchManager
import ObvIdentityManager
import ObvChannelManager
import ObvDatabaseManager
import ObvFlowManager
import ObvTypes
import ObvEncoder
import UserNotifications
import ObvServerInterface
import ObvBackupManager
import ObvSyncSnapshotManager
import OlvidUtils
import JWS


public final class ObvEngine: ObvManager {
    
    public static var mainContainerURL: URL? = nil
    
    private let delegateManager: ObvMetaManager
    private let engineCoordinator: EngineCoordinator
    let prng: PRNGService
    let appNotificationCenter: NotificationCenter
    let returnReceiptSender: ReturnReceiptSender
    private let transactionsHistoryReplayer: TransactionsHistoryReplayer
    private let protocolWaiter: ProtocolWaiter

    static let defaultLogSubsystem = "io.olvid.engine"
    public var logSubsystem: String = ObvEngine.defaultLogSubsystem
    public func prependLogSubsystem(with prefix: String) {
        logSubsystem = "\(prefix).\(logSubsystem)"
    }
    
    lazy var log = OSLog(subsystem: logSubsystem, category: "ObvEngine")
    
    var notificationCenterTokens = [NSObjectProtocol]()
    
    let dispatchQueueForPushNotificationRegistration = DispatchQueue(label: "dispatchQueueForPushNotificationRegistration")
    
    private let queueForComposedOperations = {
        let queue = OperationQueue()
        queue.name = "ObvEngine/EngineCoordinator queue for composed operations"
        return queue
    }()

    // We define a special queue for posting newObvReturnReceiptToProcess notifications to fix a bug occurring when a lot of return receipts are received at once.
    // In that case, creating one thread per receipt can lead to a complete hang of Olvid. Using one fixed thread (together with a fix made at the App level) should prevent the bug.
    let queueForPostingNewObvReturnReceiptToProcessNotifications = DispatchQueue(label: "Queue for posting a newObvReturnReceiptToProcess notification")
    
    let queueForPostingNotificationsToTheApp = DispatchQueue(label: "Queue for posting notifications to the app")
    
    private let queueForSynchronizingCallsToManagers = DispatchQueue(label: "Queue for synchronizing calls to managers")
    
    // MARK: - Public factory methods
    
    /// This method returns a full engine, with an initialized Core Data Stack
    public static func startFull(logPrefix: String, appNotificationCenter: NotificationCenter, backgroundTaskManager: ObvBackgroundTaskManager, sharedContainerIdentifier: String, supportBackgroundTasks: Bool, appType: AppType, runningLog: RunningLogError) throws -> ObvEngine {
        
        // The main container URL is shared between all the apps within the app group (i.e., between the main app, the share extension, and the notification extension).
        guard let mainContainerURL = ObvEngine.mainContainerURL else { throw makeError(message: "The main container URL is not set") }
        
        let prng = ObvCryptoSuite.sharedInstance.prngService()
        
        guard let inbox = ObvEngine.createAndConfigureBox("inbox", mainContainerURL: mainContainerURL) else { throw makeError(message: "Could not create and configure inbox") }
        guard let outbox = ObvEngine.createAndConfigureBox("outbox", mainContainerURL: mainContainerURL) else { throw makeError(message: "Could not create and configure outbox") }
        guard let database = ObvEngine.createAndConfigureBox("database", mainContainerURL: mainContainerURL) else { throw makeError(message: "Could not create and configure the database box") }
        guard let identityPhotos = ObvEngine.createAndConfigureBox("identityPhotos", mainContainerURL: mainContainerURL) else { throw makeError(message: "Could not create and configure the identityPhotos box") }
        guard let downloadedUserData = ObvEngine.createAndConfigureBox("downloadedUserData", mainContainerURL: mainContainerURL) else { throw makeError(message: "Could not create and configure the downloadedUserData box") }
        guard let uploadingUserData = ObvEngine.createAndConfigureBox("uploadingUserData", mainContainerURL: mainContainerURL) else { throw makeError(message: "Could not create and configure the uploadingUserData box") }
                
        // We create all the internal managers
        var obvManagers = [ObvManager]()
        
        // ObvBackupManager
        obvManagers.append(ObvBackupManagerImplementation(prng: prng))
        
        // ObvDatabaseManager
        ObvDatabaseManager.containerURL = database
        obvManagers.append(ObvDatabaseManager(name: "ObvEngine", transactionAuthor: appType.transactionAuthor, enableMigrations: true))

        // ObvNetworkPostDelegate
        obvManagers.append(ObvNetworkSendManagerImplementation(outbox: outbox, sharedContainerIdentifier: sharedContainerIdentifier, appType: appType, supportBackgroundFetch: supportBackgroundTasks))
        
        // ObvNetworkFetchDelegate
        obvManagers.append(ObvNetworkFetchManagerImplementation(inbox: inbox,
                                                                downloadedUserData: downloadedUserData,
                                                                prng: prng,
                                                                sharedContainerIdentifier: sharedContainerIdentifier,
                                                                supportBackgroundDownloadTasks: supportBackgroundTasks,
                                                                remoteNotificationByteIdentifierForServer: ObvEngineConstants.remoteNotificationByteIdentifierForServer,
                                                                logPrefix: logPrefix))
        
        // ObvSolveChallengeDelegate, ObvKeyWrapperForIdentityDelegate, ObvIdentityDelegate, ObvKemForIdentityDelegate
        let identityManager = ObvIdentityManagerImplementation(sharedContainerIdentifier: sharedContainerIdentifier, prng: prng, identityPhotosDirectory: identityPhotos)
        obvManagers.append(identityManager)
        
        // ObvSyncSnapshotDelegate
        let obvSyncSnapshotManagerImplementation = ObvSyncSnapshotManagerImplementation()
        // obvSyncSnapshotManagerImplementation.registerIdentityObvSyncSnapshotNodeMaker(identityManager)
        obvManagers.append(obvSyncSnapshotManagerImplementation)

        // ObvProcessDownloadedMessageDelegate, ObvChannelDelegate
        let channelManager = ObvChannelManagerImplementation(readOnly: false)
        obvManagers.append(channelManager)
        
        // ObvProtocolDelegate, ObvFullRatchetProtocolStarterDelegate
        obvManagers.append(ObvProtocolManager(prng: prng, downloadedUserData: downloadedUserData, uploadingUserData: uploadingUserData))
        
        // ObvNotificationDelegate
        obvManagers.append(ObvNotificationCenter())
        
        // ObvFlowDelegate
        obvManagers.append(ObvFlowManager(backgroundTaskManager: backgroundTaskManager, prng: prng))
        
        let fullEngine = try self.init(logPrefix: logPrefix,
                                       sharedContainerIdentifier: sharedContainerIdentifier,
                                       obvManagers: obvManagers,
                                       appNotificationCenter: appNotificationCenter,
                                       appType: appType,
                                       runningLog: runningLog)

        channelManager.setObvUserInterfaceChannelDelegate(fullEngine)
        
        fullEngine.engineCoordinator.delegateManager = fullEngine.delegateManager
        fullEngine.engineCoordinator.obvEngine = fullEngine
        
        return fullEngine

    }
    
    
    public static func startLimitedToSending(logPrefix: String, sharedContainerIdentifier: String, supportBackgroundTasks: Bool, appType: AppType, runningLog: RunningLogError) throws -> ObvEngine {

        guard let mainContainerURL = ObvEngine.mainContainerURL else {
            debugPrint("ObvEngine ERROR: the mainContainerURL is not set")
            throw makeError(message: "The mainContainerURL is not set")
        }

        let prng = ObvCryptoSuite.sharedInstance.prngService()

        guard let outbox = ObvEngine.createAndConfigureBox("outbox", mainContainerURL: mainContainerURL) else { throw makeError(message: "Could not create and configure outbox") }
        guard let database = ObvEngine.createAndConfigureBox("database", mainContainerURL: mainContainerURL) else { throw makeError(message: "Could not create and configure the database box") }
        guard let identityPhotos = ObvEngine.createAndConfigureBox("identityPhotos", mainContainerURL: mainContainerURL) else { throw makeError(message: "Could not create and configure the identityPhotos box") }

        // We create all the internal managers
        var obvManagers = [ObvManager]()

        // ObvBackupDelegate
        obvManagers.append(ObvBackupManagerImplementationDummy())
        
        // ObvDatabaseManager
        ObvDatabaseManager.containerURL = database
        obvManagers.append(ObvDatabaseManager(name: "ObvEngine", transactionAuthor: appType.transactionAuthor, enableMigrations: false))

        // ObvNetworkPostDelegate
        obvManagers.append(ObvNetworkSendManagerImplementation(outbox: outbox, sharedContainerIdentifier: sharedContainerIdentifier, appType: appType, supportBackgroundFetch: supportBackgroundTasks))

        // ObvNetworkFetchDelegate
        obvManagers.append(ObvNetworkFetchManagerImplementationDummy())

        // ObvSolveChallengeDelegate, ObvKeyWrapperForIdentityDelegate, ObvIdentityDelegate, ObvKemForIdentityDelegate
        obvManagers.append(ObvIdentityManagerImplementation(sharedContainerIdentifier: sharedContainerIdentifier, prng: prng, identityPhotosDirectory: identityPhotos))

        // ObvProcessDownloadedMessageDelegate, ObvChannelDelegate
        let channelManager = ObvChannelManagerImplementation(readOnly: false)
        obvManagers.append(channelManager)

        // ObvProtocolDelegate, ObvFullRatchetProtocolStarterDelegate
        obvManagers.append(ObvProtocolManagerDummy())

        // ObvNotificationDelegate
        obvManagers.append(ObvNotificationCenter())

        // ObvFlowDelegate
        obvManagers.append(ObvFlowManager(prng: prng))

        let dummyNotificationCenter = NotificationCenter.init()

        let engine = try self.init(logPrefix: logPrefix, sharedContainerIdentifier: sharedContainerIdentifier, obvManagers: obvManagers, appNotificationCenter: dummyNotificationCenter, appType: appType, runningLog: runningLog)

        channelManager.setObvUserInterfaceChannelDelegate(engine)
        
        return engine

    }
    
    
    public static func startLimitedToDecrypting(sharedContainerIdentifier: String, logPrefix: String, appType: AppType, runningLog: RunningLogError) throws -> ObvEngine {
        
        guard let mainContainerURL = ObvEngine.mainContainerURL else {
            debugPrint("ObvEngine ERROR: the mainContainerURL is not set")
            throw makeError(message: "The mainContainerURL is not set")
        }
        
        let prng = ObvCryptoSuite.sharedInstance.prngService()
        
        guard let database = ObvEngine.createAndConfigureBox("database", mainContainerURL: mainContainerURL) else { throw makeError(message: "Could not create and configure the database box") }
        guard let identityPhotos = ObvEngine.createAndConfigureBox("identityPhotos", mainContainerURL: mainContainerURL) else { throw makeError(message: "Could not create and configure the identityPhotos box") }

        // We create all the internal managers
        var obvManagers = [ObvManager]()
        
        // ObvDatabaseManager
        ObvDatabaseManager.containerURL = database
        obvManagers.append(ObvDatabaseManager(name: "ObvEngine", transactionAuthor: appType.transactionAuthor, enableMigrations: false))
        
        // ObvNetworkPostDelegate
        obvManagers.append(ObvNetworkSendManagerImplementationDummy())
        
        // ObvNetworkFetchDelegate
        obvManagers.append(ObvNetworkFetchManagerImplementationDummy())
        
        // ObvSolveChallengeDelegate, ObvKeyWrapperForIdentityDelegate, ObvIdentityDelegate, ObvKemForIdentityDelegate
        obvManagers.append(ObvIdentityManagerImplementation(sharedContainerIdentifier: sharedContainerIdentifier, prng: prng, identityPhotosDirectory: identityPhotos))
        
        // ObvProcessDownloadedMessageDelegate, ObvChannelDelegate
        let channelManager = ObvChannelManagerImplementation(readOnly: true)
        obvManagers.append(channelManager)
        
        // ObvProtocolDelegate, ObvFullRatchetProtocolStarterDelegate
        obvManagers.append(ObvProtocolManagerDummy())
        
        // ObvNotificationDelegate
        obvManagers.append(ObvNotificationCenterDummy())
        
        // ObvFlowDelegate
        obvManagers.append(ObvFlowManager(prng: prng))
        
        let dummyNotificationCenter = NotificationCenter.init()
        
        let engine = try self.init(logPrefix: logPrefix,
                                   sharedContainerIdentifier: sharedContainerIdentifier,
                                   obvManagers: obvManagers,
                                   appNotificationCenter: dummyNotificationCenter,
                                   appType: appType,
                                   runningLog: runningLog)

        channelManager.setObvUserInterfaceChannelDelegate(engine)
        
        return engine
        
    }
    
    // MARK: - Initializer
    
    init(logPrefix: String, sharedContainerIdentifier: String, obvManagers: [ObvManager], appNotificationCenter: NotificationCenter, appType: AppType, runningLog: RunningLogError) throws {
        
        self.prng = ObvCryptoSuite.sharedInstance.prngService()
        self.appNotificationCenter = appNotificationCenter
        self.returnReceiptSender = ReturnReceiptSender(prng: prng)
        self.transactionsHistoryReplayer = TransactionsHistoryReplayer(sharedContainerIdentifier: sharedContainerIdentifier, appType: appType)
        self.engineCoordinator = EngineCoordinator(logSubsystem: logSubsystem, prng: self.prng, queueForComposedOperations: queueForComposedOperations, appNotificationCenter: appNotificationCenter)
        delegateManager = ObvMetaManager()
        self.protocolWaiter = ProtocolWaiter(delegateManager: delegateManager, prng: prng)

        prependLogSubsystem(with: logPrefix)

        try obvManagers.forEach {
            $0.prependLogSubsystem(with: logPrefix)
            try delegateManager.register($0)
        }
        self.returnReceiptSender.prependLogSubsystem(with: logPrefix)
        self.returnReceiptSender.identityDelegate = self.identityDelegate
        setValueTransformers()
        let flowId = FlowIdentifier()
        os_log("Flow for finalizing the engine initialization: %{public}@", log: log, type: .debug, flowId.debugDescription)
        try delegateManager.initializationFinalized(flowId: flowId, runningLog: runningLog)
        try registerToInternalNotifications()
        self.transactionsHistoryReplayer.createContextDelegate = self.createContextDelegate
        self.transactionsHistoryReplayer.networkPostDelegate = self.networkPostDelegate
        
    }
    
    public func finalizeInitialization(flowId: FlowIdentifier, runningLog: RunningLogError) throws {}
    
    private func setValueTransformers() {
        ValueTransformer.setValueTransformer(EncryptedDataTransformer(), forName: .encryptedDataTransformerName)
        ValueTransformer.setValueTransformer(UIDTransformer(), forName: .uidTransformerName)
        ValueTransformer.setValueTransformer(ObvEncodedTransformer(), forName: .obvEncodedTransformerName)
        ValueTransformer.setValueTransformer(ObvCryptoIdentityTransformer(), forName: .obvCryptoIdentityTransformerName)
        ValueTransformer.setValueTransformer(ObvOwnedCryptoIdentityTransformer(), forName: .obvOwnedCryptoIdentityTransformerName)
        ValueTransformer.setValueTransformer(SeedTransformer(), forName: .seedTransformerName)
    }
    
    deinit {
        if let notificationDelegate = delegateManager.notificationDelegate {
            notificationCenterTokens.forEach {
                notificationDelegate.removeObserver($0)
            }
        }
    }
}

// MARK: Convenience method for creating the inbox and the outbox

extension ObvEngine {
    
    static func createAndConfigureBox(_ nameOfDirectory: String, mainContainerURL: URL) -> URL? {
        
        // Create the box
        
        let box = mainContainerURL.appendingPathComponent(nameOfDirectory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: box, withIntermediateDirectories: true, attributes: nil)
        } catch let error {
            debugPrint(error.localizedDescription)
            return nil
        }
        
        // Configure the box
        
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        do {
            var mutableBox = box
            try mutableBox.setResourceValues(resourceValues)
        } catch let error {
            debugPrint(error.localizedDescription)
            return nil
        }
        
        // Validate the box
        
        do {
            let urlResources = try box.resourceValues(forKeys: Set([.isDirectoryKey, .isWritableKey, .isExcludedFromBackupKey]))
            guard urlResources.isDirectory! else { return nil }
            guard urlResources.isWritable! else { return nil }
            guard urlResources.isExcludedFromBackup! else { return nil }
        } catch let error {
            debugPrint(error.localizedDescription)
            return nil
        }
        
        return box
    }
}

// MARK: Implementing ObvManager
extension ObvEngine {
    
    public func fulfill(requiredDelegate: AnyObject, forDelegateType: ObvEngineDelegateType) throws {}
    public var requiredDelegates: [ObvEngineDelegateType] { return [] }

}

// MARK: Logged access to the internal delegates
extension ObvEngine {
 
    var createContextDelegate: ObvCreateContextDelegate? {
        if delegateManager.createContextDelegate == nil {
            os_log("The create context delegate is not set", log: log, type: .fault)
            assertionFailure()
        }
        return delegateManager.createContextDelegate
    }

    var identityDelegate: ObvIdentityDelegate? {
        if delegateManager.identityDelegate == nil {
            os_log("The identity delegate is not set", log: log, type: .fault)
            assertionFailure()
        }
        return delegateManager.identityDelegate
    }
    
    var solveChallengeDelegate: ObvSolveChallengeDelegate? {
        if delegateManager.solveChallengeDelegate == nil {
            os_log("The solve challenge delegate is not set", log: log, type: .fault)
            assertionFailure()
        }
        return delegateManager.solveChallengeDelegate
    }

    var notificationDelegate: ObvNotificationDelegate? {
        if delegateManager.notificationDelegate == nil {
            os_log("The notification delegate is not set", log: log, type: .fault)
            assertionFailure()
        }
        return delegateManager.notificationDelegate
    }
    
    var channelDelegate: ObvChannelDelegate? {
        if delegateManager.channelDelegate == nil {
            os_log("The channel delegate is not set", log: log, type: .fault)
            assertionFailure()
        }
        return delegateManager.channelDelegate
    }
    
    var protocolDelegate: ObvProtocolDelegate? {
        if delegateManager.protocolDelegate == nil {
            os_log("The protocol delegate is not set", log: log, type: .fault)
            assertionFailure()
        }
        return delegateManager.protocolDelegate
    }
    
    var networkFetchDelegate: ObvNetworkFetchDelegate? {
        if delegateManager.networkFetchDelegate == nil {
            os_log("The network fetch delegate is not set", log: log, type: .fault)
            assertionFailure()
        }
        return delegateManager.networkFetchDelegate
    }
    
    var networkPostDelegate: ObvNetworkPostDelegate? {
        if delegateManager.networkPostDelegate == nil {
            os_log("The network post delegate is not set", log: log, type: .fault)
            assertionFailure()
        }
        return delegateManager.networkPostDelegate
    }

    var flowDelegate: ObvFlowDelegate? {
        if delegateManager.flowDelegate == nil {
            os_log("The flow delegate is not set", log: log, type: .fault)
            assertionFailure()
        }
        return delegateManager.flowDelegate
    }

    var backupDelegate: ObvBackupDelegate? {
        if delegateManager.backupDelegate == nil {
            os_log("The backup delegate is not set", log: log, type: .fault)
            assertionFailure()
        }
        return delegateManager.backupDelegate
    }
    
    var syncSnapshotDelegate: ObvSyncSnapshotDelegate? {
        if delegateManager.syncSnapshotDelegate == nil {
            os_log("The sync snapshot delegate is not set", log: log, type: .fault)
            assertionFailure()
        }
        return delegateManager.syncSnapshotDelegate
    }
    
}

// MARK: - Public API for managing the database

extension ObvEngine: ObvErrorMaker {

    public static let errorDomain = "ObvEngine"
    
    private func makeError(message: String) -> Error { Self.makeError(message: message) }

    private func replayTransactionsHistory() {
        let log = self.log
        DispatchQueue(label: "Engine queue for replaying transactions history").async { [weak self] in
            let flowId = FlowIdentifier()
            do {
                try self?.transactionsHistoryReplayer.replayTransactionsHistory(flowId: flowId)
            } catch {
                os_log("Could not replay transactions history: %{public}@", log: log, type: .fault, error.localizedDescription)
                // 2020-06-12 This seems to happen in practice, with the error below:
                // Error Domain=NSCocoaErrorDomain Code=4864 "*** -[NSKeyedUnarchiver _initForReadingFromData:error:throwLegacyExceptions:]: data is empty; did you forget to send -finishEncoding to the NSKeyedArchiver?" UserInfo={NSDebugDescription=*** -[NSKeyedUnarchiver _initForReadingFromData:error:throwLegacyExceptions:]: data is empty; did you forget to send -finishEncoding to the NSKeyedArchiver?}
                assertionFailure()
            }
        }
    }
    
    
    public func deleteHistoryConcerningTheAcknowledgementOfOutboxMessages(withTimestampFromServerEarlierOrEqualTo referenceDate: Date) async {
        assert(!Thread.isMainThread)
        guard let networkPostDelegate = networkPostDelegate else { assertionFailure(); return  }
        let flowId = FlowIdentifier()
        await networkPostDelegate.deleteHistoryConcerningTheAcknowledgementOfOutboxMessages(withTimestampFromServerEarlierOrEqualTo: referenceDate, flowId: flowId)
    }


    public func deleteHistoryConcerningTheAcknowledgementOfOutboxMessage(messageIdentifierFromEngine: Data, ownedIdentity: ObvCryptoId) async {
        assert(!Thread.isMainThread)
        guard let networkPostDelegate = networkPostDelegate else { assertionFailure(); return  }
        let flowId = FlowIdentifier()
        guard let messageIdentifier = ObvMessageIdentifier(rawOwnedCryptoIdentity: ownedIdentity.cryptoIdentity.getIdentity(), rawUid: messageIdentifierFromEngine) else {
            assertionFailure()
            return
        }
        await networkPostDelegate.deleteHistoryConcerningTheAcknowledgementOfOutboxMessage(messageIdentifier: messageIdentifier, flowId: flowId)
    }
    
}

// MARK: - Public API for managing Owned Identities

extension ObvEngine {
    
    public func getOwnedIdentity(with cryptoId: ObvCryptoId) throws -> ObvOwnedIdentity {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }

        let randomFlowId = FlowIdentifier()
        var obvOwnedIdentity: ObvOwnedIdentity!
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: randomFlowId) { obvContext in
            guard let _obvOwnedIdentity = ObvOwnedIdentity(ownedCryptoIdentity: cryptoId.cryptoIdentity, identityDelegate: identityDelegate, within: obvContext) else {
                throw makeError(message: "Could not get Owned Identity")
            }
            obvOwnedIdentity = _obvOwnedIdentity
        }
        return obvOwnedIdentity
    }
    
    
    public func getOwnedIdentities() throws -> Set<ObvOwnedIdentity> {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        
        let randomFlowId = FlowIdentifier()
        var ownedObvIdentities: Set<ObvOwnedIdentity>!
        var error: Error? = nil
        createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
            guard let cryptoIdentities = try? identityDelegate.getOwnedIdentities(within: obvContext) else {
                error = makeError(message: "Could not get owned identities")
                return
            }
            
            do {
                ownedObvIdentities = try Set<ObvOwnedIdentity>(cryptoIdentities.map {
                    guard let obvOwnedIdentity = ObvOwnedIdentity(ownedCryptoIdentity: $0, identityDelegate: identityDelegate, within: obvContext) else {
                        throw makeError(message: "Could not get Owned Identity")
                    }
                    return obvOwnedIdentity
                })
            } catch let _error {
                error = _error
                return
            }
        }
        guard error == nil else {
            throw error!
        }
        return ownedObvIdentities
    }
    
    
    public func generateOwnedIdentity(onServerURL serverURL: URL, with identityDetails: ObvIdentityDetails, nameForCurrentDevice: String, keycloakState: ObvKeycloakState?) async throws -> ObvCryptoId {
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            self?.generateOwnedIdentity(onServerURL: serverURL, with: identityDetails, nameForCurrentDevice: nameForCurrentDevice, keycloakState: keycloakState, completion: { result in
                switch result {
                case .failure(let failure):
                    continuation.resume(throwing: failure)
                case .success(let ownedCryptoId):
                    continuation.resume(returning: ownedCryptoId)
                }
            })
        }
    }
    
    
    private func generateOwnedIdentity(onServerURL serverURL: URL, with identityDetails: ObvIdentityDetails, nameForCurrentDevice: String, keycloakState: ObvKeycloakState?, completion: @escaping (Result<ObvCryptoId,Error>) -> Void) {
        
        // At this point, we should not pass signed details to the identity manager.
        assert(identityDetails.coreDetails.signedUserDetails == nil)
        
        guard let createContextDelegate else { completion(.failure(ObvError.createContextDelegateIsNil)); return }
        guard let identityDelegate else { completion(.failure(ObvError.identityDelegateIsNil)); return }

        let flowId = FlowIdentifier()

        do {
            try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
                guard let ownedCryptoIdentity = identityDelegate.generateOwnedIdentity(
                    onServerURL: serverURL,
                    with: identityDetails,
                    nameForCurrentDevice: nameForCurrentDevice,
                    keycloakState: keycloakState,
                    using: prng,
                    within: obvContext)
                else {
                    throw makeError(message: "Could not generate owned identity")
                }
                
                let publishedIdentityDetails = try identityDelegate.getPublishedIdentityDetailsOfOwnedIdentity(ownedCryptoIdentity, within: obvContext)
                let ownedCryptoId = ObvCryptoId(cryptoIdentity: ownedCryptoIdentity)
                try startIdentityDetailsPublicationProtocol(ownedIdentity: ownedCryptoId,
                                                            publishedIdentityDetailsVersion: publishedIdentityDetails.ownedIdentityDetailsElements.version,
                                                            within: obvContext)
                                
                let ownedDeviceUID = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedCryptoId.cryptoIdentity, within: obvContext)

                try startOwnedDeviceManagementProtocolForSettingOwnedDeviceName(
                    ownedCryptoId: ownedCryptoId,
                    ownedDeviceUID: ownedDeviceUID,
                    ownedDeviceName: nameForCurrentDevice,
                    within: obvContext)
                
                try obvContext.save(logOnFailure: log)
                completion(.success(ObvCryptoId(cryptoIdentity: ownedCryptoIdentity)))
            }
        } catch {
            completion(.failure(error))
            return
        }
        
    }
    
    
    public func deleteOwnedIdentity(with ownedCryptoId: ObvCryptoId, globalOwnedIdentityDeletion: Bool) throws {

        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }

        let ownedCryptoIdentity = ownedCryptoId.cryptoIdentity
        let flowId = FlowIdentifier()

        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { obvContext in        
            let message = try protocolDelegate.getInitiateOwnedIdentityDeletionMessage(
                ownedCryptoIdentityToDelete: ownedCryptoIdentity,
                globalOwnedIdentityDeletion: globalOwnedIdentityDeletion)
            _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
            try obvContext.save(logOnFailure: log)
        }
        
    }
    
    
    public func queryAPIKeyStatus(for identity: ObvCryptoId, apiKey: UUID) async throws -> APIKeyElements {
        guard let networkFetchDelegate else { throw ObvError.networkFetchDelegateIsNil }
        let randomFlowId = FlowIdentifier()
        return try await networkFetchDelegate.queryAPIKeyStatus(for: identity.cryptoIdentity, apiKey: apiKey, flowId: randomFlowId)
    }

    
    /// This is called during onboarding, when the user wants to check that the server and api key she entered is valid.
    public func queryAPIKeyStatus(serverURL: URL, apiKey: UUID) async throws -> APIKeyElements {
        do {
            let pkEncryptionImplemByteId = ObvCryptoSuite.sharedInstance.getDefaultPublicKeyEncryptionImplementationByteId()
            let authEmplemByteId = ObvCryptoSuite.sharedInstance.getDefaultAuthenticationImplementationByteId()
            let dummyOwnedIdentity = ObvOwnedCryptoIdentity.gen(withServerURL: serverURL,
                                                                forAuthenticationImplementationId: authEmplemByteId,
                                                                andPublicKeyEncryptionImplementationByteId: pkEncryptionImplemByteId,
                                                                using: prng)
            let dummyOwnedCryptoId = ObvCryptoId(cryptoIdentity: dummyOwnedIdentity.getObvCryptoIdentity())
            return try await queryAPIKeyStatus(for: dummyOwnedCryptoId, apiKey: apiKey)
        }
    }
    
    
    public func registerOwnedAPIKeyOnServerNow(ownedCryptoId: ObvCryptoId, apiKey: UUID) async throws -> ObvRegisterApiKeyResult {
        
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let networkFetchDelegate else { throw ObvError.networkFetchDelegateIsNil }

        let ownedCryptoIdentity = ownedCryptoId.cryptoIdentity
        let flowId = FlowIdentifier()
        
        // Make sure the owned identity is active and that it is *not* keycloak managed
        
        guard try identityDelegate.isOwnedIdentityActive(ownedIdentity: ownedCryptoIdentity, flowId: flowId) else {
            throw ObvError.ownedIdentityIsNotActive
        }
        
        guard try await !isOwnedIdentityKeycloakManaged(ownedIdentity: ownedCryptoIdentity, flowId: flowId) else {
            throw ObvError.ownedIdentityIsKeycloakManaged
        }
        
        let result = try await networkFetchDelegate.registerOwnedAPIKeyOnServerNow(ownedCryptoIdentity: ownedCryptoIdentity, apiKey: apiKey, flowId: flowId)
        
        return result
        
    }
    
    
    private func isOwnedIdentityKeycloakManaged(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> Bool {
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    let isKeycloakManaged = try identityDelegate.isOwnedIdentityKeycloakManaged(ownedIdentity: ownedIdentity, within: obvContext)
                    continuation.resume(returning: isKeycloakManaged)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    

    public func registerThenSaveKeycloakAPIKey(ownedCryptoId: ObvCryptoId, apiKey: UUID) async throws {
    
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let networkFetchDelegate else { throw ObvError.networkFetchDelegateIsNil }

        let ownedCryptoIdentity = ownedCryptoId.cryptoIdentity
        let flowId = FlowIdentifier()
        
        // Make sure the owned identity is active and that it is keycloak managed
        
        guard try identityDelegate.isOwnedIdentityActive(ownedIdentity: ownedCryptoIdentity, flowId: flowId) else {
            throw ObvError.ownedIdentityIsNotActive
        }
        
        guard try await isOwnedIdentityKeycloakManaged(ownedIdentity: ownedCryptoIdentity, flowId: flowId) else {
            throw ObvError.ownedIdentityIsNotKeycloakManaged
        }
        
        let result = try await networkFetchDelegate.registerOwnedAPIKeyOnServerNow(ownedCryptoIdentity: ownedCryptoIdentity, apiKey: apiKey, flowId: flowId)

        switch result {
        case .failed:
            throw ObvError.couldNotRegisterAPIKey
        case .invalidAPIKey:
            throw ObvError.couldNotRegisterAPIKeyAsItIsInvalid
        case .success:
            break
        }
        
        // If we reach this point, the api key registration was a success. We save it within the identity manager
        
        try await saveRegisteredKeycloakAPIKey(ownedCryptoIdentity: ownedCryptoIdentity, apiKey: apiKey, flowId: flowId)

    }
    
    
    private func saveRegisteredKeycloakAPIKey(ownedCryptoIdentity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier) async throws {
        
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        
        let log = self.log

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    try identityDelegate.saveRegisteredKeycloakAPIKey(ownedCryptoIdentity: ownedCryptoIdentity, apiKey: apiKey, within: obvContext)
                    try obvContext.save(logOnFailure: log)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
    }
    
    
    public func getKeycloakAPIKey(ownedCryptoId: ObvCryptoId) async throws -> UUID? {
        
        let ownedCryptoIdentity = ownedCryptoId.cryptoIdentity
        let flowId = FlowIdentifier()
        
        return try await getRegisteredKeycloakAPIKey(ownedCryptoIdentity: ownedCryptoIdentity, flowId: flowId)
        
    }
    
    
    private func getRegisteredKeycloakAPIKey(ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> UUID? {
        
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UUID?, Error>) in
            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    let apiKey = try identityDelegate.getRegisteredKeycloakAPIKey(ownedCryptoIdentity: ownedCryptoIdentity, within: obvContext)
                    continuation.resume(returning: apiKey)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
    }


    public func queryServerForFreeTrial(for identity: ObvCryptoId) async throws -> Bool {
        guard let networkFetchDelegate else { throw ObvError.networkFetchDelegateIsNil }
        let flowId = FlowIdentifier()
        let freeTrialAvailable = try await networkFetchDelegate.queryFreeTrial(for: identity.cryptoIdentity, flowId: flowId)
        return freeTrialAvailable
    }
    
    
    public func startFreeTrial(for identity: ObvCryptoId) async throws -> APIKeyElements {
        guard let networkFetchDelegate else { throw ObvError.networkFetchDelegateIsNil }
        let flowId = FlowIdentifier()
        let newAPIKeyElements = try await networkFetchDelegate.startFreeTrial(for: identity.cryptoIdentity, flowId: flowId)
        return newAPIKeyElements
    }

    
    public func processAppStorePurchase(signedAppStoreTransactionAsJWS: String, transactionIdentifier: UInt64) async throws -> [ObvCryptoId: ObvAppStoreReceipt.VerificationStatus] {

        guard let networkFetchDelegate else { assertionFailure(); throw ObvError.networkFetchDelegateIsNil }
        
        let flowId = FlowIdentifier()
        
        // The purchase must be processed for all active owned identities that are not keycloak managed
        
        let ownedCryptoIdentities = try await getActiveOwnedIdentitiesThatAreNotKeycloakManaged(flowId: flowId)
        
        guard !ownedCryptoIdentities.isEmpty else {
            return [:]
        }
        
        let appStoreReceiptElements = ObvAppStoreReceipt(
            ownedCryptoIdentities: ownedCryptoIdentities,
            signedAppStoreTransactionAsJWS: signedAppStoreTransactionAsJWS,
            transactionIdentifier: transactionIdentifier)
        
        let results = try await networkFetchDelegate.verifyReceiptAndRefreshAPIPermissions(appStoreReceiptElements: appStoreReceiptElements, flowId: flowId)
        return results.map({ ($0.key, $0.value) }).reduce(into: [:]) { dictToReturn, values in
            dictToReturn[ObvCryptoId(cryptoIdentity: values.0)] = values.1
        }
        
    }
    
    
    public func refreshAPIPermissions(of ownedCryptoId: ObvCryptoId) async throws -> APIKeyElements {
        
        guard let networkFetchDelegate else { throw ObvError.networkFetchDelegateIsNil }

        let flowId = FlowIdentifier()

        let apiKeyElements = try await networkFetchDelegate.refreshAPIPermissions(of: ownedCryptoId.cryptoIdentity, flowId: flowId)
        
        return apiKeyElements
        
    }
    

    public func requestRegisterToPushNotificationsForAllActiveOwnedIdentities(deviceTokens: (pushToken: Data, voipToken: Data?)?, defaultDeviceNameForFirstRegistration: String) async throws {
        
        let flowId = FlowIdentifier()
        
        let activeOwnedIdentitiesAndCurrentDeviceNames = try await getActiveOwnedIdentitiesAndCurrentDeviceNames(flowId: flowId)
        
        for (activeOwnedIdentity, currentDeviceName) in activeOwnedIdentitiesAndCurrentDeviceNames {
            
            try await requestRegisterToPushNotificationsForActiveOwnedIdentity(
                ownedIdentity: activeOwnedIdentity,
                deviceTokens: deviceTokens,
                deviceNameForFirstRegistration: currentDeviceName ?? defaultDeviceNameForFirstRegistration,
                optionalParameter: .none,
                flowId: flowId)
            
        }

    }
    
    
    private func getActiveOwnedIdentitiesAndCurrentDeviceNames(flowId: FlowIdentifier) async throws -> [ObvCryptoIdentity: String?] {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation< [ObvCryptoIdentity: String?], Error>) in
            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    let values = try identityDelegate.getActiveOwnedIdentitiesAndCurrentDeviceName(within: obvContext)
                    continuation.resume(returning: values)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
    }

    
    private func getActiveOwnedIdentitiesThatAreNotKeycloakManaged(flowId: FlowIdentifier) async throws -> Set<ObvCryptoIdentity> {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation< Set<ObvCryptoIdentity>, Error>) in
            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    let activeOwnedIdentities = try identityDelegate.getActiveOwnedIdentitiesThatAreNotKeycloakManaged(within: obvContext)
                    continuation.resume(returning: activeOwnedIdentities)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
    }

    
    public func reactivateOwnedIdentity(ownedCryptoId: ObvCryptoId, deviceTokens: (pushToken: Data, voipToken: Data?)?, deviceNameForFirstRegistration: String, replacedDeviceIdentifier: Data?) async throws {

        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }

        let replacedDeviceUid: UID?
        if let replacedDeviceIdentifier {
            replacedDeviceUid = UID(uid: replacedDeviceIdentifier)
        } else {
            replacedDeviceUid = nil
        }
        
        let flowId = FlowIdentifier()

        guard try !identityDelegate.isOwnedIdentityActive(ownedIdentity: ownedCryptoId.cryptoIdentity, flowId: flowId) else {
            return
        }

        try await requestRegisterToPushNotificationsForActiveOwnedIdentity(
            ownedIdentity: ownedCryptoId.cryptoIdentity,
            deviceTokens: deviceTokens,
            deviceNameForFirstRegistration: deviceNameForFirstRegistration,
            optionalParameter: .reactivateCurrentDevice(replacedDeviceUid: replacedDeviceUid),
            flowId: flowId)
        
    }
        
    
    private func requestRegisterToPushNotificationsForActiveOwnedIdentity(ownedIdentity: ObvCryptoIdentity, deviceTokens: (pushToken: Data, voipToken: Data?)?, deviceNameForFirstRegistration: String, optionalParameter: ObvPushNotificationType.OptionalParameter, flowId: FlowIdentifier) async throws {
        
        guard let networkFetchDelegate else { throw ObvError.networkFetchDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }

        let (currentDeviceUid, keycloakPushTopics) = try await getInfosForRegisteringToPushNotification(ownedIdentity: ownedIdentity, flowId: flowId)
        
        let commonParameters = ObvPushNotificationType.CommonParameters(
            keycloakPushTopics: keycloakPushTopics,
            deviceNameForFirstRegistration: deviceNameForFirstRegistration)
        
        let pushNotification: ObvPushNotificationType
        if let deviceTokens {
            let maskingUID = try await getMaskingUIDForPushNotifications(activeOwnedIdentity: ownedIdentity, pushToken: deviceTokens.pushToken, flowId: flowId, log: log)
            let remoteTypeParameters = ObvPushNotificationType.RemoteTypeParameters(pushToken: deviceTokens.pushToken, voipToken: deviceTokens.voipToken, maskingUID: maskingUID)
            pushNotification = .remote(ownedCryptoId: ownedIdentity, currentDeviceUID: currentDeviceUid, commonParameters: commonParameters, optionalParameter: optionalParameter, remoteTypeParameters: remoteTypeParameters)
        } else {
            pushNotification = .registerDeviceUid(ownedCryptoId: ownedIdentity, currentDeviceUID: currentDeviceUid, commonParameters: commonParameters, optionalParameter: optionalParameter)
        }
        
        do {
            
            try await networkFetchDelegate.registerPushNotification(pushNotification, flowId: flowId)
            
        } catch {
            
            if let error = error as? ObvNetworkFetchError.RegisterPushNotificationError {
                switch error {
                case .anotherDeviceIsAlreadyRegistered:
                    // If the server reports that another device is already registered, we deactivate the current device of the owned identity,
                    // delete all the devices of her contacts, and delete all oblivious channels from her current device (including channels with other owned devices).
                    // Note that we do not delete other owned devices, we only delete any oblivious we have with them.
                    let op1 = DeactivateOwnedIdentityAndMore(ownedCryptoIdentity: ownedIdentity, identityDelegate: identityDelegate, channelDelegate: channelDelegate)
                    let composedOp = try createCompositionOfOneContextualOperation(op1: op1)
                    try await protocolDelegate.executeOnQueueForProtocolOperations(operation: composedOp)
                case .couldNotParseReturnStatusFromServer:
                    break
                case .deviceToReplaceIsNotRegistered:
                    break
                case .invalidServerResponse:
                    break
                case .theDelegateManagerIsNotSet:
                    break
                }
                throw error
            } else {
                assertionFailure("This error should be turned into a ObvNetworkFetchError.RegisterPushNotificationError")
                throw error
            }
            
        }
        
        // If we reach this point, the registration was succesfull. This can only happen if the identity is active or was just reactivated.
        // So we make sure this device considers that the identity is active.
        
        try await reactivateOwnedIdentity(ownedCryptoIdentity: ownedIdentity, flowId: flowId)
        
    }
    
    
    private func reactivateOwnedIdentity(ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws {
        
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        
        let op1 = ActivateOwnedIdentityOperation(ownedCryptoIdentity: ownedCryptoIdentity, identityDelegate: identityDelegate)
        let composedOp = try createCompositionOfOneContextualOperation(op1: op1)
        
        try await protocolDelegate.executeOnQueueForProtocolOperations(operation: composedOp)
        
    }

    

    private func getInfosForRegisteringToPushNotification(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> (currentDeviceUid: UID, keycloakPushTopics: Set<String>) {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(currentDeviceUid: UID, keycloakPushTopics: Set<String>), Error>) in
            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
                    let keycloakPushTopics = try identityDelegate.getKeycloakPushTopics(ownedCryptoIdentity: ownedIdentity, within: obvContext)
                    continuation.resume(returning: (currentDeviceUid, keycloakPushTopics))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
    }
    
    
    public func getCurrentDeviceIdentifier(ownedCryptoId: ObvCryptoId) async throws -> Data {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }

        let flowId = FlowIdentifier()
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedCryptoId.cryptoIdentity, within: obvContext)
                    continuation.resume(returning: currentDeviceUid.raw)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

    }
    
    
    private func getMaskingUIDForPushNotifications(activeOwnedIdentity: ObvCryptoIdentity, pushToken: Data, flowId: FlowIdentifier, log: OSLog) async throws -> UID {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UID, Error>) in
            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    let maskingUID = try identityDelegate.getFreshMaskingUIDForPushNotifications(for: activeOwnedIdentity, pushToken: pushToken, within: obvContext)
                    try obvContext.save(logOnFailure: log)
                    continuation.resume(returning: maskingUID)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
    }
    
    
    public func updatePublishedIdentityDetailsOfOwnedIdentity(with ownedCryptoId: ObvCryptoId, with newIdentityDetails: ObvIdentityDetails) async throws {
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try updatePublishedIdentityDetailsOfOwnedIdentityInternal(with: ownedCryptoId, with: newIdentityDetails)
                continuation.resume()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        
    }
        

    private func updatePublishedIdentityDetailsOfOwnedIdentityInternal(with ownedCryptoId: ObvCryptoId, with newIdentityDetails: ObvIdentityDetails) throws {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }

        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { obvContext in
            try identityDelegate.updatePublishedIdentityDetailsOfOwnedIdentity(ownedCryptoId.cryptoIdentity,
                                                                               with: newIdentityDetails,
                                                                               within: obvContext)
            let version = try identityDelegate.getPublishedIdentityDetailsOfOwnedIdentity(ownedCryptoId.cryptoIdentity, within: obvContext).ownedIdentityDetailsElements.version
            try startIdentityDetailsPublicationProtocol(ownedIdentity: ownedCryptoId, publishedIdentityDetailsVersion: version, within: obvContext)
            try obvContext.save(logOnFailure: log)
        }
        
    }
    
    
    public func queryServerWellKnown(serverURL: URL) async throws {
        guard let networkFetchDelegate else { throw ObvError.networkFetchDelegateIsNil }
        let flowId = FlowIdentifier()
        try await networkFetchDelegate.queryServerWellKnown(serverURL: serverURL, flowId: flowId)
    }

    public func getOwnedIdentityKeycloakState(with ownedCryptoId: ObvCryptoId) throws -> (obvKeycloakState: ObvKeycloakState?, signedOwnedDetails: SignedObvKeycloakUserDetails?) {

        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }

        var keyCloakState: ObvKeycloakState?
        var signedOwnedDetails: SignedObvKeycloakUserDetails?
        let flowId = FlowIdentifier()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
            (keyCloakState, signedOwnedDetails) = try identityDelegate.getOwnedIdentityKeycloakState(
                ownedIdentity: ownedCryptoId.cryptoIdentity,
                within: obvContext)
        }
        return (keyCloakState, signedOwnedDetails)
    }
    
    
    public func getSignedContactDetails(ownedIdentity: ObvCryptoId, contactIdentity: ObvCryptoId, completion: @escaping (Result<SignedObvKeycloakUserDetails?,Error>) -> Void) throws {
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        let flowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: flowId) { (obvContext) in
            do {
                let signedContactDetails = try identityDelegate.getSignedContactDetails(
                    ownedIdentity: ownedIdentity.cryptoIdentity,
                    contactIdentity: contactIdentity.cryptoIdentity,
                    within: obvContext)
                completion(.success(signedContactDetails))
            } catch {
                completion(.failure(error))
            }
        }
    }

    
    public func getSignedContactDetailsAsync(ownedIdentity: ObvCryptoId, contactIdentity: ObvCryptoId) async throws -> SignedObvKeycloakUserDetails? {
        return try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<SignedObvKeycloakUserDetails?, Error>) in
            do {
                try self?.getSignedContactDetails(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity) { result in
                    switch result {
                    case .success(let signedObvKeycloakUserDetails):
                        continuation.resume(returning: signedObvKeycloakUserDetails)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }


    public func saveKeycloakAuthState(with ownedCryptoId: ObvCryptoId, rawAuthState: Data) throws {
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }

        os_log("🧥 Call to saveKeycloakAuthState", log: log, type: .info)
        
        let flowId = FlowIdentifier()
        try queueForSynchronizingCallsToManagers.sync {
            try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
                try identityDelegate.saveKeycloakAuthState(ownedIdentity: ownedCryptoId.cryptoIdentity, rawAuthState: rawAuthState, within: obvContext)
                try obvContext.save(logOnFailure: log)
            }
        }
    }

    public func saveKeycloakJwks(with ownedCryptoId: ObvCryptoId, jwks: ObvJWKSet) throws {
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }

        let flowId = FlowIdentifier()
        try queueForSynchronizingCallsToManagers.sync {
            try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
                try identityDelegate.saveKeycloakJwks(ownedIdentity: ownedCryptoId.cryptoIdentity, jwks: jwks, within: obvContext)
                try obvContext.save(logOnFailure: log)
            }
        }
    }

    public func getOwnedIdentityKeycloakUserId(with ownedCryptoId: ObvCryptoId) throws -> String? {
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }

        var userId: String?
        let flowId = FlowIdentifier()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
            userId = try identityDelegate.getOwnedIdentityKeycloakUserId(ownedIdentity: ownedCryptoId.cryptoIdentity, within: obvContext)
        }
        return userId
    }

    public func setOwnedIdentityKeycloakUserId(with ownedCryptoId: ObvCryptoId, userId: String?) throws {
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }

        let flowId = FlowIdentifier()
        try queueForSynchronizingCallsToManagers.sync {
            try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
                try identityDelegate.setOwnedIdentityKeycloakUserId(ownedIdentity: ownedCryptoId.cryptoIdentity, keycloakUserId: userId, within: obvContext)
                try obvContext.save(logOnFailure: log)
            }
        }
    }

    public func addKeycloakContact(with ownedCryptoId: ObvCryptoId, signedContactDetails: SignedObvKeycloakUserDetails) throws {
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }

        guard let contactIdentity = signedContactDetails.identity else { throw makeError(message: "Could not determine contact identity") }
        guard let contactIdentityToAdd = ObvCryptoIdentity(from: contactIdentity) else { throw makeError(message: "Could not parse contact identity") }
        
        let message = try protocolDelegate.getInitiateAddKeycloakContactMessageForKeycloakContactAdditionProtocol(
            ownedIdentity: ownedCryptoId.cryptoIdentity,
            contactIdentityToAdd: contactIdentityToAdd,
            signedContactDetails: signedContactDetails.signedUserDetails)

        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()

        try queueForSynchronizingCallsToManagers.sync {
            try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
                _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                try obvContext.save(logOnFailure: log)
            }
        }
    }

    
    /// This method asynchronously binds an owned identity to a keycloak server.
    public func bindOwnedIdentityToKeycloak(ownedCryptoId: ObvCryptoId, keycloakState: ObvKeycloakState, keycloakUserId: String) async throws {
        
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }

        let message = try protocolDelegate.getOwnedIdentityKeycloakBindingMessage(
            ownedCryptoIdentity: ownedCryptoId.cryptoIdentity,
            keycloakState: keycloakState,
            keycloakUserId: keycloakUserId)

        try await protocolWaiter.waitUntilEndOfProcessingOfProtocolMessage(message, log: log)

        // If we reach this point, the protocol message was processed (i.e., deleted from database)
        // It does not necessarily mean that the protocol was a success.
        // So we check the identity is indeed bound to keycloak
        
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: FlowIdentifier()) { obvContext in
            let isKeycloakManaged = try identityDelegate.isOwnedIdentityKeycloakManaged(ownedIdentity: ownedCryptoId.cryptoIdentity, within: obvContext)
            guard isKeycloakManaged else {
                throw Self.makeError(message: "The call to bindOwnedIdentityToKeycloak did fail")
            }
        }
        
    }
    
    
    /// This method asynchronously unbinds an owned identity from a keycloak server. During this process, new details are published for owned identity, based on the previously published details, but after removing the signed user details.
    /// This method eventually posts an `ownedIdentityUnbindingFromKeycloakPerformed` notification containing the result of the unbinding process.
    public func unbindOwnedIdentityFromKeycloak(ownedCryptoId: ObvCryptoId) async throws {
        
        do {
            
            guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
            guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
            guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
            guard let flowDelegate else { throw ObvError.flowDelegateIsNil }

            let message = try protocolDelegate.getOwnedIdentityKeycloakUnbindingMessage(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity)
            let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()
            
            try await protocolWaiter.waitUntilEndOfProcessingOfProtocolMessage(message, log: log)
            
            // If we reach this point, the protocol message was processed (i.e., deleted from database)
            // It does not necessarily mean that the protocol was a success.
            // So we check the identity is indeed bound to keycloak
            
            try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { obvContext in
                let isKeycloakManaged = try identityDelegate.isOwnedIdentityKeycloakManaged(ownedIdentity: ownedCryptoId.cryptoIdentity, within: obvContext)
                guard !isKeycloakManaged else {
                    throw Self.makeError(message: "The call to unbindOwnedIdentityFromKeycloak did fail")
                }
            }
            
            try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { [weak self] obvContext in
                guard let _self = self else { return }
                let version = try identityDelegate.getPublishedIdentityDetailsOfOwnedIdentity(ownedCryptoId.cryptoIdentity, within: obvContext).ownedIdentityDetailsElements.version
                try _self.startIdentityDetailsPublicationProtocol(ownedIdentity: ownedCryptoId, publishedIdentityDetailsVersion: version, within: obvContext)
                try obvContext.save(logOnFailure: _self.log)
            }
            
            ObvEngineNotificationNew.ownedIdentityUnbindingFromKeycloakPerformed(ownedIdentity: ownedCryptoId, result: .success(()))
                .postOnBackgroundQueue(within: appNotificationCenter)

        } catch {
            
            ObvEngineNotificationNew.ownedIdentityUnbindingFromKeycloakPerformed(ownedIdentity: ownedCryptoId, result: .failure(error))
                .postOnBackgroundQueue(within: appNotificationCenter)
            throw error

        }

    }


    public func setOwnedIdentityKeycloakSelfRevocationTestNonce(ownedCryptoId: ObvCryptoId, newSelfRevocationTestNonce: String?) throws {
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        let log = self.log
        let flowId = FlowIdentifier()
        // Synchronizing this call prevents a merge conflict with the operations made in updateKeycloakRevocationList(...)
        queueForSynchronizingCallsToManagers.async {
            createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { obvContext in
                do {
                    try identityDelegate.setOwnedIdentityKeycloakSelfRevocationTestNonce(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, newSelfRevocationTestNonce: newSelfRevocationTestNonce, within: obvContext)
                    try obvContext.save(logOnFailure: log)
                } catch {
                    os_log("Failed to set the new self revocation test nonce: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                }
            }
        }
    }
    
    
    public func getOwnedIdentityKeycloakSelfRevocationTestNonce(ownedCryptoId: ObvCryptoId) throws -> String? {
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        let flowId = FlowIdentifier()
        var selfRevocationTestNonce: String? = nil
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { obvContext in
            selfRevocationTestNonce = try identityDelegate?.getOwnedIdentityKeycloakSelfRevocationTestNonce(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, within: obvContext)
        }
        return selfRevocationTestNonce
    }
    
    
    public func setOwnedIdentityKeycloakSignatureKey(ownedCryptoId: ObvCryptoId, keycloakServersignatureVerificationKey: ObvJWK?) throws {
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        let flowId = FlowIdentifier()
        let log = self.log
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { obvContext in
            do {
                try identityDelegate.setOwnedIdentityKeycloakSignatureKey(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, keycloakServersignatureVerificationKey: keycloakServersignatureVerificationKey, within: obvContext)
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Failed to set the new keycloak server signature verification key: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                throw error
            }
        }
    }
    
    
    public func updateKeycloakRevocationList(ownedCryptoId: ObvCryptoId, latestRevocationListTimestamp: Date, signedRevocations: [String]) throws {
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        let flowId = FlowIdentifier()
        let log = self.log
        os_log("Updating the keycloak revocation list", log: log, type: .info)
        // Synchronizing this call prevents a merge conflict with the operations made in setOwnedIdentityKeycloakSelfRevocationTestNonce(...)
        try queueForSynchronizingCallsToManagers.sync {
            try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { obvContext in
                let compromisedContacts = try identityDelegate.verifyAndAddRevocationList(
                    ownedCryptoIdentity: ownedCryptoId.cryptoIdentity,
                    signedRevocations: signedRevocations,
                    revocationListTimetamp: latestRevocationListTimestamp,
                    within: obvContext)
                os_log("We have %d compromised contacts, we delete all the channels we have with them", log: log, type: .info, compromisedContacts.count)
                try compromisedContacts.forEach { compromisedContact in
                    try channelDelegate.deleteAllObliviousChannelsBetweenTheCurrentDeviceOf(ownedIdentity: ownedCryptoId.cryptoIdentity, andTheDevicesOfContactIdentity: compromisedContact, within: obvContext)
                }
                do {
                    try obvContext.save(logOnFailure: log)
                } catch {
                    createContextDelegate.debugPrintCurrentBackgroundContexts()
                    throw error
                }
            }
        }
    }
        
    
    public func updateKeycloakPushTopicsIfNeeded(ownedCryptoId: ObvCryptoId, deviceTokens: (pushToken: Data, voipToken: Data?)?, deviceNameForFirstRegistration: String, pushTopics: Set<String>) async throws {
        
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }

        let flowId = FlowIdentifier()
        let log = self.log
        
        ObvDisplayableLogs.shared.log("[🧥] Call to updateKeycloakPushTopicsIfNeeded with pushTopics \(pushTopics)")

        os_log("Updating the keycloak push topics within the engine", log: log, type: .info)
        
        let storedPushTopicsWereUpdated = try await updateKeycloakPushTopicsIfNeeded(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, pushTopics: pushTopics, flowId: flowId, log: log)
        guard storedPushTopicsWereUpdated else { return }
        
        guard try identityDelegate.isOwnedIdentityActive(ownedIdentity: ownedCryptoId.cryptoIdentity, flowId: flowId) else {
            assertionFailure()
            return
        }

        // The following call will take into account the new set of push topics
        
        try await requestRegisterToPushNotificationsForActiveOwnedIdentity(
            ownedIdentity: ownedCryptoId.cryptoIdentity,
            deviceTokens: deviceTokens,
            deviceNameForFirstRegistration: deviceNameForFirstRegistration,
            optionalParameter: .none,
            flowId: flowId)
        
    }
    
    
    private func getKeycloakPushTopics(ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> Set<String> {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Set<String>, Error>) in
            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    let allPushTopics = try identityDelegate.getKeycloakPushTopics(ownedCryptoIdentity: ownedCryptoIdentity, within: obvContext)
                    continuation.resume(returning: allPushTopics)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
    }
    
    
    private func updateKeycloakPushTopicsIfNeeded(ownedCryptoIdentity: ObvCryptoIdentity, pushTopics: Set<String>, flowId: FlowIdentifier, log: OSLog) async throws -> Bool {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    let storedPushTopicsUpdated = try identityDelegate.updateKeycloakPushTopicsIfNeeded(ownedCryptoIdentity: ownedCryptoIdentity, pushTopics: pushTopics, within: obvContext)
                    try obvContext.save(logOnFailure: log)
                    continuation.resume(returning: storedPushTopicsUpdated)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    
    public func getManagedOwnedIdentitiesAssociatedWithThePushTopic(_ pushTopic: String) throws -> Set<ObvOwnedIdentity> {
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        let flowId = FlowIdentifier()
        // No need to synchronize this call, its a simple query
        var ownedIdentities = Set<ObvOwnedIdentity>()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { obvContext in
            let ownedCryptoIds = try identityDelegate.getCryptoIdentitiesOfManagedOwnedIdentitiesAssociatedWithThePushTopic(pushTopic, within: obvContext)
            let _ownedIdentities = ownedCryptoIds.compactMap({
                ObvOwnedIdentity(ownedCryptoIdentity: $0, identityDelegate: identityDelegate, within: obvContext)
            })
            ownedIdentities = Set(_ownedIdentities)
        }
        return ownedIdentities
    }

    
    public func getSignedOwnedDetails(ownedIdentity: ObvCryptoId, completion: @escaping (Result<SignedObvKeycloakUserDetails?,Error>) -> Void) throws {
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        let flowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: flowId) { (obvContext) in
            do {
                guard let signedOwnedDetails = try identityDelegate.getOwnedIdentityKeycloakState(ownedIdentity: ownedIdentity.cryptoIdentity, within: obvContext).signedOwnedDetails else {
                    completion(.failure(Self.makeError(message: "Could not find signed owned details")))
                    return
                }
                completion(.success(signedOwnedDetails))
            } catch {
                completion(.failure(error))
            }
        }
    }

}


// MARK: - Public API for owned devices

extension ObvEngine {
    
    public func getAllOwnedDevicesOfOwnedIdentity(_ ownedCryptoId: ObvCryptoId) throws -> Set<ObvOwnedDevice> {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }

        let ownedCryptoIdentity = ownedCryptoId.cryptoIdentity
        
        var ownedDevices = Set<ObvOwnedDevice>()
        
        let flowId = FlowIdentifier()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { obvContext in
            // Deal with the current device
            let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedCryptoIdentity, within: obvContext)
            let infos = try identityDelegate.getInfosAboutOwnedDevice(withUid: currentDeviceUid, ownedCryptoIdentity: ownedCryptoIdentity, within: obvContext)
            let currentDevice = ObvOwnedDevice(
                identifier: currentDeviceUid.raw,
                ownedCryptoIdentity: ownedCryptoIdentity,
                secureChannelStatus: .currentDevice,
                name: infos.name,
                expirationDate: infos.expirationDate,
                latestRegistrationDate: infos.latestRegistrationDate)
            ownedDevices.insert(currentDevice)
            // Deal with remote owned devices
            let otherDeviceUids = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedCryptoIdentity, within: obvContext)
            for otherDeviceUid in otherDeviceUids {
                // Check if a channel exists between the current device and the remote owned device
                let channelExists = try channelDelegate.aConfirmedObliviousChannelExistsBetweenTheCurrentDeviceOf(
                    ownedIdentity: ownedCryptoIdentity,
                    andRemoteIdentity: ownedCryptoIdentity,
                    withRemoteDeviceUid: otherDeviceUid,
                    within: obvContext)
                let secureChannelStatus = channelExists ? ObvOwnedDevice.SecureChannelStatus.created : .creationInProgress
                let infos = try identityDelegate.getInfosAboutOwnedDevice(withUid: otherDeviceUid, ownedCryptoIdentity: ownedCryptoIdentity, within: obvContext)
                let otherOwnedDevice = ObvOwnedDevice(
                    identifier: otherDeviceUid.raw,
                    ownedCryptoIdentity: ownedCryptoIdentity,
                    secureChannelStatus: secureChannelStatus,
                    name: infos.name,
                    expirationDate: infos.expirationDate,
                    latestRegistrationDate: infos.latestRegistrationDate)
                ownedDevices.insert(otherOwnedDevice)
            }
        }
        
        return ownedDevices
    }
    
    
    public func getObvOwnedDevice(with ownedDeviceIdentifier: ObvOwnedDeviceIdentifier) throws -> ObvOwnedDevice? {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }

        let ownedCryptoIdentity = ownedDeviceIdentifier.ownedCryptoId.cryptoIdentity

        var ownedDeviceToReturn: ObvOwnedDevice?
        
        let flowId = FlowIdentifier()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { obvContext in
            
            let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedCryptoIdentity, within: obvContext)

            if currentDeviceUid == ownedDeviceIdentifier.deviceUID {
                
                let infos = try identityDelegate.getInfosAboutOwnedDevice(withUid: currentDeviceUid, ownedCryptoIdentity: ownedCryptoIdentity, within: obvContext)
                let currentDevice = ObvOwnedDevice(
                    identifier: currentDeviceUid.raw,
                    ownedCryptoIdentity: ownedCryptoIdentity,
                    secureChannelStatus: .currentDevice,
                    name: infos.name,
                    expirationDate: infos.expirationDate,
                    latestRegistrationDate: infos.latestRegistrationDate)
                ownedDeviceToReturn = currentDevice
                
            } else {
                
                let otherDeviceUid = ownedDeviceIdentifier.deviceUID

                guard try identityDelegate.isDevice(withUid: otherDeviceUid, aRemoteDeviceOfOwnedIdentity: ownedCryptoIdentity, within: obvContext) else {
                    ownedDeviceToReturn = nil
                    return
                }
                
                let channelExists = try channelDelegate.aConfirmedObliviousChannelExistsBetweenTheCurrentDeviceOf(
                    ownedIdentity: ownedCryptoIdentity,
                    andRemoteIdentity: ownedCryptoIdentity,
                    withRemoteDeviceUid: otherDeviceUid,
                    within: obvContext)
                let secureChannelStatus = channelExists ? ObvOwnedDevice.SecureChannelStatus.created : .creationInProgress
                let infos = try identityDelegate.getInfosAboutOwnedDevice(withUid: otherDeviceUid, ownedCryptoIdentity: ownedCryptoIdentity, within: obvContext)
                let otherOwnedDevice = ObvOwnedDevice(
                    identifier: otherDeviceUid.raw,
                    ownedCryptoIdentity: ownedCryptoIdentity,
                    secureChannelStatus: secureChannelStatus,
                    name: infos.name,
                    expirationDate: infos.expirationDate,
                    latestRegistrationDate: infos.latestRegistrationDate)
                ownedDeviceToReturn = otherOwnedDevice
                
            }

        }
        
        return ownedDeviceToReturn
        
    }
    
    public func getAllOwnedDevices() async throws -> Set<ObvOwnedDevice> {
        
        let ownedCryptoIdentities = try await getOwnedIdentities()
        
        var ownedDevices = Set<ObvOwnedDevice>()
        
        for ownedCryptoId in ownedCryptoIdentities {
            let devices = try getAllOwnedDevicesOfOwnedIdentity(.init(cryptoIdentity: ownedCryptoId))
            ownedDevices.formUnion(devices)
        }
        
        return ownedDevices
        
    }
    

    /// If it exists, this method first delete the channel we have with the owned device. It then relaunches the channel creation with the owned device.
    public func restartChannelEstablishmentProtocolsWithOwnedDevice(ownedCryptoId: ObvCryptoId, deviceIdentifier: Data) async throws {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }

        let log = self.log
        let prng = self.prng
        let ownedCryptoIdentity = ownedCryptoId.cryptoIdentity
        guard let remoteOwnedDeviceUid = UID(uid: deviceIdentifier) else {
            assertionFailure()
            throw Self.makeError(message: "Could not turn device identifier into a device UID")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in

            let flowId = FlowIdentifier()
            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
                
                do {
                    
                    let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedCryptoIdentity, within: obvContext)
                    
                    guard currentDeviceUid != remoteOwnedDeviceUid else {
                        assertionFailure()
                        throw Self.makeError(message: "Trying to restart channel establishement betwen the current device and itself, which makes no sense")
                    }
                    
                    guard try identityDelegate.isDevice(withUid: remoteOwnedDeviceUid, aRemoteDeviceOfOwnedIdentity: ownedCryptoIdentity, within: obvContext) else {
                        assertionFailure()
                        throw Self.makeError(message: "The remote device does not appear to exist")
                    }
                    
                    try channelDelegate.deleteObliviousChannelBetweenCurentDeviceWithUid(
                        currentDeviceUid: currentDeviceUid,
                        andTheRemoteDeviceWithUid: remoteOwnedDeviceUid,
                        ofRemoteIdentity: ownedCryptoIdentity,
                        within: obvContext)
                    
                    let message = try protocolDelegate.getInitialMessageForChannelCreationWithOwnedDeviceProtocol(ownedIdentity: ownedCryptoIdentity, remoteDeviceUid: remoteOwnedDeviceUid)
                    
                    _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                    try obvContext.save(logOnFailure: log)
                    
                    continuation.resume()
                    
                } catch {
                    continuation.resume(throwing: error)
                }

            }

        }
        
    }
    
}

// MARK: - Public API for managing contact identities

extension ObvEngine {
    
    public func getContactDeviceIdentifiersForWhichAChannelCreationProtocolExists(with contactCryptoId: ObvCryptoId, ofOwnedIdentityWith ownedCryptoId: ObvCryptoId) throws -> Set<Data> {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        
        var channelIds: Set<ObliviousChannelIdentifierAlt>!
        
        let flowId = FlowIdentifier()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
            channelIds = try protocolDelegate.getAllObliviousChannelIdentifiersHavingARunningChannelCreationWithContactDeviceProtocolInstances(within: obvContext)
                .filter({ $0.ownedCryptoIdentity == ownedCryptoId.cryptoIdentity && $0.remoteCryptoIdentity == contactCryptoId.cryptoIdentity })
        }
        
        return Set(channelIds.map({ $0.remoteDeviceUid.raw }))
        
    }
    
    
    public func getContactDeviceIdentifiersOfContactIdentity(with contactCryptoId: ObvCryptoId, ofOwnedIdentityWith ownedCryptoId: ObvCryptoId) throws -> Set<Data> {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        
        var contactDeviceIdentifiers: Set<Data>!
        let flowId = FlowIdentifier()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
            let contactDeviceUids = try identityDelegate.getDeviceUidsOfContactIdentity(contactCryptoId.cryptoIdentity,
                                                                                        ofOwnedIdentity: ownedCryptoId.cryptoIdentity,
                                                                                        within: obvContext)
            contactDeviceIdentifiers = Set(contactDeviceUids.map({ $0.raw }))
        }
        
        return contactDeviceIdentifiers
    }
    
    
    public func getContactIdentity(with contactCryptoId: ObvCryptoId, ofOwnedIdentityWith ownedCryptoId: ObvCryptoId) throws -> ObvContactIdentity? {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        
        var obvContactIdentity: ObvContactIdentity?
        
        let randomFlowId = FlowIdentifier()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: randomFlowId) { (obvContext) in
            guard try identityDelegate.isIdentity(contactCryptoId.cryptoIdentity, aContactIdentityOfTheOwnedIdentity: ownedCryptoId.cryptoIdentity, within: obvContext) else {
                // Return nil in this case
                return
            }
            guard let _obvContactIdentity = ObvContactIdentity(contactCryptoIdentity: contactCryptoId.cryptoIdentity,
                                                               ownedCryptoIdentity: ownedCryptoId.cryptoIdentity,
                                                               identityDelegate: identityDelegate,
                                                               within: obvContext) else {
                throw Self.makeError(message: "Could not create ObvContactIdentity")
            }
            obvContactIdentity = _obvContactIdentity
        }
        
        return obvContactIdentity
        
    }
    
    
    public func getContactsOfOwnedIdentity(with ownedCryptoId: ObvCryptoId) throws -> Set<ObvContactIdentity> {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }

        let contactIdentities: Set<ObvContactIdentity>
        
        do {
            var _contactIdentities: Set<ObvContactIdentity>?
            let randomFlowId = FlowIdentifier()
            createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
                
                let contactCryptoIdentities: Set<ObvCryptoIdentity>
                do {
                    contactCryptoIdentities = try identityDelegate.getContactsOfOwnedIdentity(ownedCryptoId.cryptoIdentity, within: obvContext)
                } catch {
                    os_log("Could not get contacts", log: log, type: .fault)
                    assertionFailure()
                    return
                }
                
                do {
                    _contactIdentities = try Set<ObvContactIdentity>(contactCryptoIdentities.map {
                        guard let obvContactIdentity = ObvContactIdentity(contactCryptoIdentity: $0, ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, identityDelegate: identityDelegate, within: obvContext) else { throw Self.makeError(message: "Could not create ObvContactIdentity") }
                        return obvContactIdentity
                    })
                } catch {
                    return
                }
            }
            guard _contactIdentities != nil else { throw ObvEngine.makeError(message: "Could not get contact identities of owned identity") }
            contactIdentities = _contactIdentities!
        }
        
        return contactIdentities
    }

    public func deleteContactIdentity(with contactCryptoId: ObvCryptoId, ofOwnedIdentyWith ownedCryptoId: ObvCryptoId) throws {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        
        // We prepare the appropriate message for starting the ObliviousChannelManagementProtocol step allowing to delete the contact
        
        let message = try protocolDelegate.getInitiateContactDeletionMessageForContactManagementProtocol(ownedIdentity: ownedCryptoId.cryptoIdentity,
                                                                                                         contactIdentityToDelete: contactCryptoId.cryptoIdentity)
        
        
        // The ObliviousChannelManagementProtocol fails to delete a contact if this contact is part of a group. We check this here and throw if this is the case.
        
        var error: Error?
        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()
        createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
            do {
                guard try !identityDelegate.contactIdentityBelongsToSomeContactGroup(contactCryptoId.cryptoIdentity, forOwnedIdentity: ownedCryptoId.cryptoIdentity, within: obvContext) else {
                    error = Self.makeError(message: "The contact identity does not belong to any contact group")
                    return
                }
            } catch let _error {
                error = _error
                return
            }
            
            // If we reach this point, we know that the contact does not belong the a joined group. We can start the protocol allowing to delete this contact.
            
            do {
                _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                try obvContext.save(logOnFailure: log)
            } catch let _error {
                error = _error
            }
        }
        guard error == nil else {
            throw error!
        }
    }
    
    
    public func getTrustOriginsOfContactIdentity(with contactCryptoId: ObvCryptoId, ofOwnedIdentyWith ownedCryptoId: ObvCryptoId) throws -> [ObvTrustOrigin] {

        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }

        var trustOrigins: [ObvTrustOrigin]!
        var error: Error?
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
            do {
                trustOrigins = try ObvTrustOrigin.getTrustOriginsOfContactIdentity(with: contactCryptoId, ofOwnedIdentyWith: ownedCryptoId, using: identityDelegate, within: obvContext)
            } catch let _error {
                error = _error
            }
        }
        guard error == nil else {
            throw error!
        }
        return trustOrigins
    }

    
    public func getAllObvContactDevicesOfContact(with contactIdentifier: ObvContactIdentifier) throws -> Set<ObvContactDevice> {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }

        var contactDevices = Set<ObvContactDevice>()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: FlowIdentifier()) { obvContext in
            
            guard try identityDelegate.isIdentity(contactIdentifier.contactCryptoId.cryptoIdentity, aContactIdentityOfTheOwnedIdentity: contactIdentifier.ownedCryptoId.cryptoIdentity, within: obvContext) else {
                // The contact does not exist, return an empty set of devices
                return
            }
            
            let allDeviceUids = try identityDelegate.getDeviceUidsOfContactIdentity(contactIdentifier.contactCryptoId.cryptoIdentity, ofOwnedIdentity: contactIdentifier.ownedCryptoId.cryptoIdentity, within: obvContext)
            let deviceUidsWithChannel = try channelDelegate.getRemoteDeviceUidsOfRemoteIdentity(
                contactIdentifier.contactCryptoId.cryptoIdentity, forWhichAConfirmedObliviousChannelExistsWithTheCurrentDeviceOfOwnedIdentity: contactIdentifier.ownedCryptoId.cryptoIdentity, within: obvContext)
            
            contactDevices = Set(allDeviceUids.compactMap { deviceUid in
                let secureChannelStatus: ObvContactDevice.SecureChannelStatus
                if deviceUidsWithChannel.contains(where: { $0 == deviceUid }) {
                    secureChannelStatus = .created
                } else {
                    secureChannelStatus = .creationInProgress
                }
                return ObvContactDevice(remoteDeviceUid: deviceUid, contactIdentifier: contactIdentifier, secureChannelStatus: secureChannelStatus)
            })
            
        }
        
        return contactDevices
        
    }
    
    
    public func getObvContactDevice(with contactDeviceIdentifier: ObvContactDeviceIdentifier) throws -> ObvContactDevice? {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        guard let identityDelegate else { throw ObvError.channelDelegateIsNil }

        var contactDevice: ObvContactDevice?
        
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: FlowIdentifier()) { obvContext in
            
            let contactDeviceUIDs = try identityDelegate.getDeviceUidsOfContactIdentity(
                contactDeviceIdentifier.contactCryptoId.cryptoIdentity,
                ofOwnedIdentity: contactDeviceIdentifier.ownedCryptoId.cryptoIdentity,
                within: obvContext)
            
            guard contactDeviceUIDs.contains(contactDeviceIdentifier.deviceUID) else {
                // The device does not exist, we return nil
                return
            }
                
            let confirmedChannelExists = try channelDelegate.aConfirmedObliviousChannelExistsBetweenTheCurrentDeviceOf(
                ownedIdentity: contactDeviceIdentifier.ownedCryptoId.cryptoIdentity,
                andRemoteIdentity: contactDeviceIdentifier.contactCryptoId.cryptoIdentity,
                withRemoteDeviceUid: contactDeviceIdentifier.deviceUID,
                within: obvContext)
            
            let secureChannelStatus: ObvContactDevice.SecureChannelStatus = confirmedChannelExists ? .created : .creationInProgress

            contactDevice = .init(remoteDeviceUid: contactDeviceIdentifier.deviceUID,
                                  contactIdentifier: .init(contactCryptoId: contactDeviceIdentifier.contactCryptoId, ownedCryptoId: contactDeviceIdentifier.ownedCryptoId),
                                  secureChannelStatus: secureChannelStatus)
        }
        
        return contactDevice

    }
    
    
    public func getAllObvContactDevicesOfContactsOfOwnedIdentity(_ ownedCryptoId: ObvCryptoId) async throws -> Set<ObvContactDevice> {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        
        let ownedCryptoIdentity = ownedCryptoId.cryptoIdentity

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Set<ObvContactDevice>, Error>) in
            createContextDelegate.performBackgroundTask(flowId: FlowIdentifier()) { obvContext in
                var allContactDevices = Set<ObvContactDevice>()
                do {
                    let allContactCryptoIds = try identityDelegate.getContactsOfOwnedIdentity(ownedCryptoIdentity, within: obvContext)
                    for contactCryptoId in allContactCryptoIds {
                        let allDeviceUids = try identityDelegate.getDeviceUidsOfContactIdentity(contactCryptoId, ofOwnedIdentity: ownedCryptoIdentity, within: obvContext)
                        let deviceUidsWithChannel = try channelDelegate.getRemoteDeviceUidsOfRemoteIdentity(
                            contactCryptoId, forWhichAConfirmedObliviousChannelExistsWithTheCurrentDeviceOfOwnedIdentity: ownedCryptoIdentity, within: obvContext)
                        let contactDevices = Set(allDeviceUids.compactMap { deviceUid in
                            let secureChannelStatus: ObvContactDevice.SecureChannelStatus
                            if deviceUidsWithChannel.contains(where: { $0 == deviceUid }) {
                                secureChannelStatus = .created
                            } else {
                                secureChannelStatus = .creationInProgress
                            }
                            return ObvContactDevice(remoteDeviceUid: deviceUid, contactIdentifier: .init(contactCryptoIdentity: contactCryptoId, ownedCryptoIdentity: ownedCryptoIdentity), secureChannelStatus: secureChannelStatus)
                        })
                        allContactDevices.formUnion(contactDevices)
                    }
                    return continuation.resume(returning: allContactDevices)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
        
    }
    

    public func updateTrustedIdentityDetailsOfContactIdentity(with contactCryptoId: ObvCryptoId, ofOwnedIdentityWithCryptoId ownedCryptoId: ObvCryptoId, with newTrustedIdentityDetails: ObvIdentityDetails) async throws {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        
        let flowId = FlowIdentifier()
        let prng = self.prng
        let log = self.log

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    
                    // Trust the details locally
                    
                    try identityDelegate.updateTrustedIdentityDetailsOfContactIdentity(contactCryptoId.cryptoIdentity,
                                                                                       ofOwnedIdentity: ownedCryptoId.cryptoIdentity,
                                                                                       with: newTrustedIdentityDetails,
                                                                                       within: obvContext)

                    // Since we updated the trusted details with the published details, we can request a trusted details and propagate them to our other owned devices
                    
                    let contactIdentityDetailsElements = try identityDelegate.getTrustedIdentityDetailsOfContactIdentity(
                        contactCryptoId.cryptoIdentity,
                        ofOwnedIdentity: ownedCryptoId.cryptoIdentity,
                        within: obvContext).contactIdentityDetailsElements
                    let serializedIdentityDetailsElements = try contactIdentityDetailsElements.jsonEncode()
                    let syncAtom = ObvSyncAtom.trustContactDetails(contactCryptoId: contactCryptoId, serializedIdentityDetailsElements: serializedIdentityDetailsElements)
                    let message = try protocolDelegate.getInitiateSyncAtomMessageForSynchronizationProtocol(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, syncAtom: syncAtom)
                    _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)

                    // Save the context
                    
                    try obvContext.save(logOnFailure: log)
                    
                    continuation.resume()
                    
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

    }
    
    
    public func unblockContactIdentity(with contactCryptoId: ObvCryptoId, ofOwnedIdentityWithCryptoId ownedCryptoId: ObvCryptoId) throws {

        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        
        let contactIdentifier = ObvContactIdentifier(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
        
        let randomFlowId = FlowIdentifier()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: randomFlowId) { obvContext in
            do {
                try identityDelegate.setContactForcefullyTrustedByUser(
                    ownedIdentity: ownedCryptoId.cryptoIdentity,
                    contactIdentity: contactCryptoId.cryptoIdentity,
                    forcefullyTrustedByUser: true,
                    within: obvContext)
                try deleteAllContactDevicesAndChannelsThenPerformContactDeviceDiscovery(
                    contactIdentifier: contactIdentifier,
                    within: obvContext)
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Could not unblock contact: %{public}@", log: log, type: .fault, error.localizedDescription)
                throw error
            }
        }
    }

    
    public func reblockContactIdentity(with contactCryptoId: ObvCryptoId, ofOwnedIdentityWithCryptoId ownedCryptoId: ObvCryptoId) throws {

        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }

        let randomFlowId = FlowIdentifier()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: randomFlowId) { obvContext in
            do {
                // We set forcefullyTrustedByUser to false (this deletes all the devices of the contact within the identity manager)
                try identityDelegate.setContactForcefullyTrustedByUser(
                    ownedIdentity: ownedCryptoId.cryptoIdentity,
                    contactIdentity: contactCryptoId.cryptoIdentity,
                    forcefullyTrustedByUser: false,
                    within: obvContext)
                // We delete all oblivious channels with this contact
                try channelDelegate.deleteAllObliviousChannelsBetweenTheCurrentDeviceOf(ownedIdentity: ownedCryptoId.cryptoIdentity, andTheDevicesOfContactIdentity: contactCryptoId.cryptoIdentity, within: obvContext)
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Could not unblock contact: %{public}@", log: log, type: .fault, error.localizedDescription)
                throw error
            }
        }
    }

    
    /// Starts a ``OneToOneContactInvitationProtocol``. In practice, this is called from a single place within the app (in the `ObvFlowController`) so as to make sure we always perform a simultaneous Keycloak invitation if possible.
    public func sendOneToOneInvitation(ownedIdentity: ObvCryptoId, contactIdentity: ObvCryptoId) throws {
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        
        let message = try protocolDelegate.getInitialMessageForOneToOneContactInvitationProtocol(ownedIdentity: ownedIdentity.cryptoIdentity, contactIdentity: contactIdentity.cryptoIdentity)
        let flowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: flowId) { [weak self] (obvContext) in
            guard let _self = self else { return }
            do {
                _ = try channelDelegate.postChannelMessage(message, randomizedWith: _self.prng, within: obvContext)
                try obvContext.save(logOnFailure: _self.log)
            } catch {
                os_log("Could not post initial message for starting OneToOne contact invitation protocol: %{public}@", log: _self.log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
        }
    }

    
    public func downgradeOneToOneContact(ownedIdentity: ObvCryptoId, contactIdentity: ObvCryptoId) throws {
        
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }

        let message = try protocolDelegate.getInitialMessageForDowngradingOneToOneContact(ownedIdentity: ownedIdentity.cryptoIdentity, contactIdentity: contactIdentity.cryptoIdentity)
        let flowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: flowId) { [weak self] (obvContext) in
            guard let _self = self else { return }
            do {
                _ = try channelDelegate.postChannelMessage(message, randomizedWith: _self.prng, within: obvContext)
                try obvContext.save(logOnFailure: _self.log)
            } catch {
                os_log("Could not post initial message for starting OneToOne contact invitation protocol: %{public}@", log: _self.log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
        }

    }
    
    
    public func requestOneStatusSyncRequest(ownedIdentity: ObvCryptoId, contactsToSync: Set<ObvCryptoId>) async throws {
        
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }

        let contactsToSync = Set(contactsToSync.map { $0.cryptoIdentity })
        
        let message = try protocolDelegate.getInitialMessageForOneStatusSyncRequest(ownedIdentity: ownedIdentity.cryptoIdentity, contactsToSync: contactsToSync)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let flowId = FlowIdentifier()
            do {
                try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { obvContext in
                    _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                    try obvContext.save(logOnFailure: log)
                    continuation.resume()
                    return
                }
            } catch {
                continuation.resume(throwing: error)
                return
            }
        }
        
    }
    
}


// MARK: - Public API for managing capabilities

extension ObvEngine {
    
    public func getCapabilitiesOfAllContactsOfOwnedIdentity(_ ownedCryptoId: ObvCryptoId) throws -> [ObvCryptoId: Set<ObvCapability>] {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        
        var results = [ObvCryptoId: Set<ObvCapability>]()
        let randomFlowId = FlowIdentifier()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: randomFlowId) { obvContext in
            let contactCapabilities = try identityDelegate.getCapabilitiesOfAllContactsOfOwnedIdentity(ownedCryptoId.cryptoIdentity, within: obvContext)
            contactCapabilities.forEach { (contactCryptoIdentity, capabilities) in
                results[ObvCryptoId(cryptoIdentity: contactCryptoIdentity)] = capabilities
            }
        }
        return results
        
    }
    
    public func getCapabilitiesOfContact(with contactIdentifier: ObvContactIdentifier) throws -> Set<ObvCapability>? {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        
        var contactCapabilities: Set<ObvCapability>?
        let randomFlowId = FlowIdentifier()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: randomFlowId) { obvContext in
            contactCapabilities = try identityDelegate.getCapabilitiesOfContactIdentity(
                ownedIdentity: contactIdentifier.ownedCryptoId.cryptoIdentity,
                contactIdentity: contactIdentifier.contactCryptoId.cryptoIdentity,
                within: obvContext)
        }
        return contactCapabilities

    }
    
    public func setCapabilitiesOfCurrentDeviceForAllOwnedIdentities(_ newObvCapabilities: Set<ObvCapability>) throws {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        let log = self.log
        let prng = self.prng

        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: randomFlowId) { obvContext in
            
            do {
                let ownedIdentities = try identityDelegate.getOwnedIdentities(within: obvContext)
                try ownedIdentities.forEach { ownedIdentity in
                    let message = try protocolDelegate.getInitialMessageForAddingOwnCapabilities(
                        ownedIdentity: ownedIdentity,
                        newOwnCapabilities: newObvCapabilities)
                    _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                }
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Could not set capabilities of current device UIDs of all own identities: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
            
        }
        
    }
    
    
    public func getCapabilitiesOfOwnedIdentity(_ ownedCryptoId: ObvCryptoId) throws -> Set<ObvCapability>? {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        
        var capabilities: Set<ObvCapability>? = nil
        let randomFlowId = FlowIdentifier()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: randomFlowId) { obvContext in
            capabilities = try identityDelegate.getCapabilitiesOfOwnedIdentity(ownedIdentity: ownedCryptoId.cryptoIdentity, within: obvContext)
        }
        return capabilities
        
    }

}


// MARK: - Public API for managing persisted `ObvDialog`s

extension ObvEngine {
    
    public func deleteDialog(with uuid: UUID) throws {
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        let randomFlowId = FlowIdentifier()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: randomFlowId) { (obvContext) in
            try deleteDialog(with: uuid, within: obvContext)
            try obvContext.save(logOnFailure: log)
        }
    }
    
    public func abortProtocol(associatedTo obvDialog: ObvDialog) throws {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }


        // Like un cochon
        guard let listOfEncoded = [ObvEncoded](obvDialog.encodedElements, expectedCount: 4) else {
            throw Self.makeError(message: "Could not abort protocol as we could not decode as a list of encoded")
        }
        guard let protocolInstanceUid = UID(listOfEncoded[1]) else {
            throw Self.makeError(message: "Could not abort protocol as we could not decode the protocol instance UID")
        }
        try protocolDelegate.abortProtocol(withProtocolInstanceUid: protocolInstanceUid,
                                           forOwnedIdentity: obvDialog.ownedCryptoId.cryptoIdentity)
        
        let randomFlowId = FlowIdentifier()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: randomFlowId) { (obvContext) in
            try deleteDialog(with: obvDialog.uuid, within: obvContext)
            try obvContext.save(logOnFailure: log)
        }
        
    }
    
    
    private func deleteDialog(with uid: UUID, within obvContext: ObvContext) throws {
        guard let persistedDialog = try PersistedEngineDialog.get(uid: uid, appNotificationCenter: appNotificationCenter, within: obvContext) else { return }
        try persistedDialog.delete()
    }
    
    
    /// When bootstraping the app, we want to resync the PersistedInvitations with the persisted dialogs of the engine. This methods allows to get all the dialogs.
    public func getAllDialogsWithinEngine() async throws -> [ObvDialog] {
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        let randomFlowId = FlowIdentifier()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ObvDialog], Error>) in
            do {
                try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: randomFlowId) { (obvContext) in
                    let persistedDialogs = try PersistedEngineDialog.getAll(appNotificationCenter: appNotificationCenter, within: obvContext)
                    let obvDialogs = persistedDialogs.compactMap({ $0.obvDialog })
                    continuation.resume(returning: obvDialogs)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    
    public func respondTo(_ obvDialog: ObvDialog) async throws {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }
        
        // Responding to an ObvDialog is a critical long-running task, so we always extend the app runtime to make sure that responding to a dialog (and all the resulting network exchanges) eventually finish, even if the app moves to the background between the call to this method and the moment the data is actually sent to the server.
        
        guard let flowId = try? flowDelegate.startBackgroundActivityForStartingOrResumingProtocol() else { return }
        let log = self.log
        let prng = self.prng
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    guard let encodedResponse = obvDialog.encodedResponse else {
                        let error = Self.makeError(message: "Could not obtain encoded response")
                        continuation.resume(throwing: error)
                        return
                    }
                    let timestamp = Date()
                    let channelDialogResponseMessageToSend = ObvChannelDialogResponseMessageToSend(uuid: obvDialog.uuid,
                                                                                                   toOwnedIdentity: obvDialog.ownedCryptoId.cryptoIdentity,
                                                                                                   timestamp: timestamp,
                                                                                                   encodedUserDialogResponse: encodedResponse,
                                                                                                   encodedElements: obvDialog.encodedElements)
                    _ = try channelDelegate.postChannelMessage(channelDialogResponseMessageToSend, randomizedWith: prng, within: obvContext)
                    try obvContext.save(logOnFailure: log)
                    continuation.resume()
                } catch {
                    os_log("Could not respond to obvDialog", log: log, type: .fault)
                    let error = Self.makeError(message: "Could not respond to obvDialog")
                    continuation.resume(throwing: error)
                }
            }
        }
        
    }
    
}


// MARK: - Public API for starting cryptographic protocols

extension ObvEngine {
    
    public func startTrustEstablishmentProtocolOfRemoteIdentity(with remoteCryptoId: ObvCryptoId, withFullDisplayName remoteFullDisplayName: String, forOwnedIdentyWith ownedCryptoId: ObvCryptoId) throws {
        
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        
        let log = self.log
        
        // Recover the published owned identity details
        var obvOwnedIdentity: ObvOwnedIdentity!
        var error: Error?
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
            guard let _obvOwnedIdentity = ObvOwnedIdentity(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, identityDelegate: identityDelegate, within: obvContext) else {
                error = Self.makeError(message: "Could not create ObvOwnedIdentity")
                return
            }
            obvOwnedIdentity = _obvOwnedIdentity
        }
        guard error == nil else {
            throw error!
        }
        
        // Starting a Trust Establishment protocol is a critical long-running task, so we always extend the app runtime to make sure that we can perform the required tasks, even if the app moves to the background between the call to this method and the moment the data is actually sent to the server.
        
        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()

        let protocolInstanceUid = UID.gen(with: prng)
        let message = try protocolDelegate.getInitialMessageForTrustEstablishmentProtocol(of: remoteCryptoId.cryptoIdentity,
                                                                                          withFullDisplayName: remoteFullDisplayName,
                                                                                          forOwnedIdentity: ownedCryptoId.cryptoIdentity,
                                                                                          withOwnedIdentityCoreDetails: obvOwnedIdentity.currentIdentityDetails.coreDetails,
                                                                                          usingProtocolInstanceUid: protocolInstanceUid)
        createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            do {
                _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                try obvContext.save(logOnFailure: log)
            } catch let _error {
                error = _error
            }
        }
        guard error == nil else {
            throw error!
        }
    }
    
    
    public func startContactMutualIntroductionProtocol(of remoteCryptoId: ObvCryptoId, with remoteCryptoIds: Set<ObvCryptoId>, forOwnedId ownedId: ObvCryptoId) throws {
        
        assert(!Thread.isMainThread)
        
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }
        
        let log = self.log
        
        // Starting a ContactMutualIntroductionProtocol is a critical long-running task, so we always extend the app runtime to make sure that we can perform the required tasks, even if the app moves to the background between the call to this method and the moment the data is actually sent to the server.
        
        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()

        var messages = [ObvChannelProtocolMessageToSend]()
        for otherRemoteCryptoId in remoteCryptoIds {
            let protocolInstanceUid = UID.gen(with: prng)
            let message = try protocolDelegate.getInitialMessageForContactMutualIntroductionProtocol(of: remoteCryptoId.cryptoIdentity,
                                                                                                     with: otherRemoteCryptoId.cryptoIdentity,
                                                                                                     byOwnedIdentity: ownedId.cryptoIdentity,
                                                                                                     usingProtocolInstanceUid: protocolInstanceUid)
            messages.append(message)
        }
        
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
            do {
                for message in messages {
                    _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                }
                try obvContext.save(logOnFailure: log)
            } catch {
                assertionFailure(error.localizedDescription)
                throw error
            }
        }
    }
    

    // This protocol is started when the user publishes her identity details
    private func startIdentityDetailsPublicationProtocol(ownedIdentity: ObvCryptoId, publishedIdentityDetailsVersion version: Int, within obvContext: ObvContext) throws {
        
        assert(!Thread.isMainThread)
        
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        
        let message = try protocolDelegate.getInitialMessageForIdentityDetailsPublicationProtocol(ownedIdentity: ownedIdentity.cryptoIdentity,
                                                                                                  publishedIdentityDetailsVersion: version)
        guard try identityDelegate.isOwned(ownedIdentity.cryptoIdentity, within: obvContext) else { throw makeError(message: "The identity is not owned") }
        _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
        
    }

    
    private func startOwnedDeviceManagementProtocolForSettingOwnedDeviceName(ownedCryptoId: ObvCryptoId, ownedDeviceUID: UID, ownedDeviceName: String, within obvContext: ObvContext) throws {
        
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        
        let request = ObvOwnedDeviceManagementRequest.setOwnedDeviceName(ownedDeviceUID: ownedDeviceUID, ownedDeviceName: ownedDeviceName)
        let message = try protocolDelegate.getInitiateOwnedDeviceManagementMessage(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, request: request)
                
        guard try identityDelegate.isOwned(ownedCryptoId.cryptoIdentity, within: obvContext) else { throw makeError(message: "The identity is not owned") }
        _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)

    }
    
    
    private func startOwnedDeviceManagementProtocolForDeactivatingOtherOwnedDevice(ownedCryptoId: ObvCryptoId, ownedDeviceUID: UID, within obvContext: ObvContext) throws {
        
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        
        let request = ObvOwnedDeviceManagementRequest.deactivateOtherOwnedDevice(ownedDeviceUID: ownedDeviceUID)
        let message = try protocolDelegate.getInitiateOwnedDeviceManagementMessage(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, request: request)

        guard try identityDelegate.isOwned(ownedCryptoId.cryptoIdentity, within: obvContext) else { throw makeError(message: "The identity is not owned") }
        _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
        
    }

    
    private func startOwnedDeviceManagementProtocolForSettingUnexpiringDevice(ownedCryptoId: ObvCryptoId, ownedDeviceUID: UID, within obvContext: ObvContext) throws {
        
        guard let channelDelegate else { assertionFailure(); throw ObvError.channelDelegateIsNil }
        guard let protocolDelegate else { assertionFailure(); throw ObvError.protocolDelegateIsNil }
        guard let identityDelegate else { assertionFailure(); throw ObvError.identityDelegateIsNil }
        
        let request = ObvOwnedDeviceManagementRequest.setUnexpiringDevice(ownedDeviceUID: ownedDeviceUID)
        let message = try protocolDelegate.getInitiateOwnedDeviceManagementMessage(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, request: request)

        guard try identityDelegate.isOwned(ownedCryptoId.cryptoIdentity, within: obvContext) else { throw makeError(message: "The identity is not owned") }
        _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
        
    }
    

    // This protocol is started when a group owner (an owned identity) publishes (latest) details for a (owned) contact group
    private func startOwnedGroupLatestDetailsPublicationProtocol(for groupStructure: GroupStructure, within obvContext: ObvContext) throws {
        
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        
        guard groupStructure.groupType == .owned else {
            throw Self.makeError(message: "Could not start owned group latest details publication protocol as the group type is not owned")
        }
        
        let message = try protocolDelegate.getOwnedGroupMembersChangedTriggerMessageForGroupManagementProtocol(groupUid: groupStructure.groupUid, ownedIdentity: groupStructure.groupOwner, within: obvContext)
        _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
    }
    
    
    public func requestChangeOfOwnedDeviceName(ownedCryptoId: ObvCryptoId, deviceIdentifier: Data, ownedDeviceName: String) async throws {
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        let log = self.log
        guard let ownedDeviceUID = UID(uid: deviceIdentifier) else { assertionFailure(); throw Self.makeError(message: "Could not decode device identifier") }
        try await withCheckedThrowingContinuation { continuation in
            do {
                try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: FlowIdentifier()) { obvContext in
                    try startOwnedDeviceManagementProtocolForSettingOwnedDeviceName(
                        ownedCryptoId: ownedCryptoId,
                        ownedDeviceUID: ownedDeviceUID,
                        ownedDeviceName: ownedDeviceName,
                        within: obvContext)
                    try obvContext.save(logOnFailure: log)
                    continuation.resume()
                }
            } catch {
                    continuation.resume(throwing: error)
            }
        }
    }
    
    
    public func requestDeactivationOfOtherOwnedDevice(ownedCryptoId: ObvCryptoId, deviceIdentifier: Data) async throws {
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        let log = self.log
        guard let ownedDeviceUID = UID(uid: deviceIdentifier) else { assertionFailure(); throw Self.makeError(message: "Could not decode device identifier") }
        try await withCheckedThrowingContinuation { continuation in
            do {
                try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: FlowIdentifier()) { obvContext in
                    try startOwnedDeviceManagementProtocolForDeactivatingOtherOwnedDevice(
                        ownedCryptoId: ownedCryptoId,
                        ownedDeviceUID: ownedDeviceUID,
                        within: obvContext)
                    try obvContext.save(logOnFailure: log)
                    continuation.resume()
                }
            } catch {
                    continuation.resume(throwing: error)
            }
        }
    }
    
    
    public func requestSettingUnexpiringDevice(ownedCryptoId: ObvCryptoId, deviceIdentifier: Data) async throws {
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        let log = self.log
        guard let ownedDeviceUID = UID(uid: deviceIdentifier) else { assertionFailure(); throw Self.makeError(message: "Could not decode device identifier") }
        try await withCheckedThrowingContinuation { continuation in
            do {
                try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: FlowIdentifier()) { obvContext in
                    try startOwnedDeviceManagementProtocolForSettingUnexpiringDevice(
                        ownedCryptoId: ownedCryptoId,
                        ownedDeviceUID: ownedDeviceUID,
                        within: obvContext)
                    try obvContext.save(logOnFailure: log)
                    continuation.resume()
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    
    /// This is similar to ``ObvEngine.deleteAllContactDevicesAndChannelsThenPerformContactDeviceDiscovery(with:ofOwnedIdentyWith:)``, except that we only delete the devices for which no channel is established yet. No chanel gets deleted here.
    public func restartAllOngoingChannelEstablishmentProtocolsWithContactIdentity(with contactCryptoId: ObvCryptoId, ofOwnedIdentyWith ownedCryptoId: ObvCryptoId) throws {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }
        
        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()

        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
            
            // Find all contact devices for which we have no channel
            let contactDeviceUidsWithoutChannel: Set<UID>
            do {
                let contactDeviceUidsWithChannel = Set<UID>(try channelDelegate.getRemoteDeviceUidsOfRemoteIdentity(contactCryptoId.cryptoIdentity,
                                                                                                                    forWhichAConfirmedObliviousChannelExistsWithTheCurrentDeviceOfOwnedIdentity: ownedCryptoId.cryptoIdentity,
                                                                                                                    within: obvContext))
                let allContactDeviceUids = try identityDelegate.getDeviceUidsOfContactIdentity(contactCryptoId.cryptoIdentity, ofOwnedIdentity: ownedCryptoId.cryptoIdentity, within: obvContext)
                contactDeviceUidsWithoutChannel = allContactDeviceUids.subtracting(contactDeviceUidsWithChannel)
            } catch let error {
                os_log("Could not get contact devices of remote identity", log: log, type: .fault)
                assertionFailure()
                throw error
            }
            
            // Delete these devices
            do {
                try identityDelegate.deleteDevicesOfContactIdentity(contactIdentity: contactCryptoId.cryptoIdentity,
                                                                    contactDeviceUids: contactDeviceUidsWithoutChannel,
                                                                    ownedIdentity: ownedCryptoId.cryptoIdentity,
                                                                    within: obvContext)
            } catch let error {
                os_log("Could not delete contact devices", log: log, type: .fault)
                assertionFailure()
                throw error
            }
            
            // We then launch a device discovery
            
            try performContactDeviceDiscoveryProtocol(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, contactCryptoIdentity: contactCryptoId.cryptoIdentity, within: obvContext)
            
            do {
                try obvContext.save(logOnFailure: log)
            } catch let error {
                os_log("Could not save context: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                throw error
            }

        }

    }
    

    /// This method first delete all channels and device uids with the contact identity. It then performs a device discovery. This is enough, since the device discovery will eventually add devices and thus, new channels will be created.
    public func deleteAllContactDevicesAndChannelsThenPerformContactDeviceDiscovery(contactIdentifier: ObvContactIdentifier) throws {
        
        assert(!Thread.isMainThread)
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }
        
        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()

        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
            
            try deleteAllContactDevicesAndChannelsThenPerformContactDeviceDiscovery(
                contactIdentifier: contactIdentifier,
                within: obvContext)
            
            do {
                try obvContext.save(logOnFailure: log)
            } catch let error {
                os_log("Could not save context: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                throw error
            }
            
        }
                
    }
    

    private func deleteAllContactDevicesAndChannelsThenPerformContactDeviceDiscovery(contactIdentifier: ObvContactIdentifier, within obvContext: ObvContext) throws {
        
        assert(!Thread.isMainThread)
        
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }

        let ownedCryptoIdentity = contactIdentifier.ownedCryptoId.cryptoIdentity
        let contactCryptoIdentity = contactIdentifier.contactCryptoId.cryptoIdentity
        
        try obvContext.performAndWaitOrThrow {
            
            // We delete all oblivious channels with this contact
            do {
                try channelDelegate.deleteAllObliviousChannelsBetweenTheCurrentDeviceOf(ownedIdentity: ownedCryptoIdentity, andTheDevicesOfContactIdentity: contactCryptoIdentity, within: obvContext)
            } catch {
                os_log("Could not recreate all channels with contact. We could not delete previous channels.", log: log, type: .fault)
                assertionFailure()
                throw error
            }
            
            // We then delete all previous contact devices
            do {
                try identityDelegate.deleteAllDevicesOfContactIdentity(contactIdentity: contactCryptoIdentity, ownedIdentity: ownedCryptoIdentity, within: obvContext)
            } catch let error {
                os_log("Could not recreate all channels with contact. We could not delete previous devices.", log: log, type: .fault)
                assertionFailure()
                throw error
            }
            
            // We then launch a device discovery
            
            try performContactDeviceDiscoveryProtocol(ownedCryptoIdentity: ownedCryptoIdentity, contactCryptoIdentity: contactCryptoIdentity, within: obvContext)
                        
        }

    }
    
    
    public func recreateChannelWithContactDevice(contactIdentifier: ObvContactIdentifier, contactDeviceIdentifier: Data) throws {
        
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        
        let ownedCryptoIdentity = contactIdentifier.ownedCryptoId.cryptoIdentity
        let contactCryptoIdentity = contactIdentifier.contactCryptoId.cryptoIdentity
        guard let contactDeviceUid = UID(uid: contactDeviceIdentifier) else { throw Self.makeError(message: "Could not decode device identifier") }

        os_log("🛟 [%{public}@] Since the app requested the re-creation of the channel with a device of the contact, we start a channel creation now", log: log, type: .info, contactCryptoIdentity.debugDescription)

        let msg: ObvChannelProtocolMessageToSend
        do {
            msg = try protocolDelegate.getInitialMessageForChannelCreationWithContactDeviceProtocol(betweenTheCurrentDeviceOfOwnedIdentity: ownedCryptoIdentity, andTheDeviceUid: contactDeviceUid, ofTheContactIdentity: contactCryptoIdentity)
        } catch {
            os_log("Could get initial message for starting channel creation with contact device protocol", log: log, type: .fault)
            assertionFailure()
            return
        }

        let flowId = FlowIdentifier()
        let prng = self.prng
        let log = self.log

        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { obvContext in
            
            do {
                _ = try channelDelegate.postChannelMessage(msg, randomizedWith: prng, within: obvContext)
            } catch {
                os_log("Could not start channel creation with contact device protocol", log: log, type: .fault)
                throw Self.makeError(message: "Could not start channel creation with contact device protocol")
            }
            
            do {
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Could not perform channel creation with contact device protocol: %{public}@", log: log, type: .fault, error.localizedDescription)
                throw Self.makeError(message: "Could not perform channel creation with contact device protocol: \(error.localizedDescription)")
            }

        }
                
    }
    
    
    public func performContactDeviceDiscovery(contactIdentifier: ObvContactIdentifier) throws {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }

        let ownedCryptoIdentity = contactIdentifier.ownedCryptoId.cryptoIdentity
        let contactCryptoIdentity = contactIdentifier.contactCryptoId.cryptoIdentity
        let log = self.log
        let flowId = FlowIdentifier()

        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { [weak self] obvContext in
            try self?.performContactDeviceDiscoveryProtocol(ownedCryptoIdentity: ownedCryptoIdentity, contactCryptoIdentity: contactCryptoIdentity, within: obvContext)
            try obvContext.save(logOnFailure: log)
        }
        
    }
    
    
    private func performContactDeviceDiscoveryProtocol(ownedCryptoIdentity: ObvCryptoIdentity, contactCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }

        // We then launch a device discovery
        let message: ObvChannelProtocolMessageToSend
        do {
            message = try protocolDelegate.getInitialMessageForContactDeviceDiscoveryProtocol(ownedIdentity: ownedCryptoIdentity, contactIdentity: contactCryptoIdentity)
        } catch let error {
            os_log("Could not get initial message for device discovery for contact identity protocol", log: log, type: .fault)
            assertionFailure()
            throw error
        }
        
        do {
            _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
        } catch let error {
            os_log("Could not post a local protocol message allowing to start a device discovery for a contact", log: log, type: .fault)
            assertionFailure()
            throw error
        }
        
    }

    
    public func computeMutualScanUrl(remoteIdentity: Data, ownedCryptoId: ObvCryptoId) throws -> ObvMutualScanUrl {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let solveChallengeDelegate = solveChallengeDelegate else { throw makeError(message: "The solve challenge delegate is not set") }

        guard let remoteCryptoId = ObvCryptoIdentity(from: remoteIdentity) else {
            throw makeError(message: "Could not turn data into an ObvCryptoIdentity")
        }

        var signature: Data?
        var fullDisplayName: String?

        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: FlowIdentifier()) { obvContext in
            let challengeType = ChallengeType.mutualScan(firstIdentity: remoteCryptoId, secondIdentity: ownedCryptoId.cryptoIdentity)
            guard let sig = try? solveChallengeDelegate.solveChallenge(challengeType, for: ownedCryptoId.cryptoIdentity, using: prng, within: obvContext) else {
                os_log("Could not compute signature", log: log, type: .fault)
                throw makeError(message: "Could not compute signature")
            }
            signature = sig
            let ownedIdentity = try getOwnedIdentity(with: ownedCryptoId)
            fullDisplayName = ownedIdentity.publishedIdentityDetails.coreDetails.getFullDisplayName()
        }
        
        guard let signature = signature, let fullDisplayName = fullDisplayName else { throw makeError(message: "Could not obtain signature") }
        
        return ObvMutualScanUrl(cryptoId: ownedCryptoId, fullDisplayName: fullDisplayName, signature: signature)
        
    }
    
    
    public func verifyMutualScanUrl(ownedCryptoId: ObvCryptoId, mutualScanUrl: ObvMutualScanUrl) -> Bool {
        let challengeType = ChallengeType.mutualScan(firstIdentity: ownedCryptoId.cryptoIdentity, secondIdentity: mutualScanUrl.cryptoId.cryptoIdentity)
        return ObvSolveChallengeStruct.checkResponse(mutualScanUrl.signature, to: challengeType, from: mutualScanUrl.cryptoId.cryptoIdentity)
    }
    
    
    public func startTrustEstablishmentWithMutualScanProtocol(ownedIdentity: ObvCryptoId, mutualScanUrl: ObvMutualScanUrl) throws {
        
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }

        // We then launch a device discovery
        let message: ObvChannelProtocolMessageToSend
        do {
            message = try protocolDelegate.getInitialMessageForTrustEstablishmentWithMutualScanProtocol(ownedIdentity: ownedIdentity.cryptoIdentity,
                                                                                                        remoteIdentity: mutualScanUrl.cryptoId.cryptoIdentity,
                                                                                                        signature: mutualScanUrl.signature)
        } catch let error {
            os_log("Could not get initial message for device discovery for contact identity protocol", log: log, type: .fault)
            assertionFailure()
            throw error
        }
        
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: FlowIdentifier()) { obvContext in
            do {
                _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
            } catch let error {
                os_log("Could not post a local protocol message allowing to start a device discovery for a contact", log: log, type: .fault)
                assertionFailure()
                throw error
            }

            do {
                try obvContext.save(logOnFailure: log)
            } catch let error {
                os_log("Could not save context: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                throw error
            }
        }

    }
    
}

// MARK: - Public API for managing groups V2

extension ObvEngine {
    
    public func startGroupV2CreationProtocol(serializedGroupCoreDetails: Data, ownPermissions: Set<ObvGroupV2.Permission>, otherGroupMembers: Set<ObvGroupV2.IdentityAndPermissions>, ownedCryptoId: ObvCryptoId, photoURL: URL?) throws {

        // The photoURL typically points to a photo stored in a cache directory managed by the app.
        // When requesting the protocol message to the protocol manager, it creates a local copy of this photo that it will manage.
        
        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }

        let log = self.log
        
        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()

        let otherMembers: Set<GroupV2.IdentityAndPermissions> = Set(otherGroupMembers.map({ GroupV2.IdentityAndPermissions(from: $0) }))
        let ownRawPermissions: Set<String> = Set(ownPermissions.map({ GroupV2.Permission(obvGroupV2Permission: $0) }).map({ $0.rawValue }))
        
        assert(otherMembers.count == otherGroupMembers.count)
        
        let message = try protocolDelegate.getInitiateGroupCreationMessageForGroupV2Protocol(ownedIdentity: ownedCryptoId.cryptoIdentity,
                                                                                             ownRawPermissions: ownRawPermissions,
                                                                                             otherGroupMembers: otherMembers,
                                                                                             serializedGroupCoreDetails: serializedGroupCoreDetails,
                                                                                             photoURL: photoURL,
                                                                                             flowId: flowId)
        
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { obvContext in
            
            // Make sure all the other group members have the appropriate capability
            
            for otherGroupMember in otherGroupMembers.map({ $0.identity }) {
                guard let capabilities = try identityDelegate.getCapabilitiesOfContactIdentity(
                    ownedIdentity: ownedCryptoId.cryptoIdentity,
                    contactIdentity: otherGroupMember.cryptoIdentity,
                    within: obvContext),
                      capabilities.contains(.groupsV2)
                else {
                    throw Self.makeError(message: "One of the requested group members hasn't the groupv2 capability")
                }
            }

            _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
            
            try obvContext.save(logOnFailure: log)
        }
        
    }
    

    public func getAllObvGroupV2OfOwnedIdentity(with ownedCryptoId: ObvCryptoId) throws -> Set<ObvGroupV2> {
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        var groups = Set<ObvGroupV2>()
        let randomFlowId = FlowIdentifier()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: randomFlowId) { obvContext in
            groups = try identityDelegate.getAllObvGroupV2(of: ownedCryptoId.cryptoIdentity, within: obvContext)
        }
        return groups
    }
    
    
    public func getObvGroupV2(with identifier: ObvGroupV2Identifier) throws -> ObvGroupV2? {
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        var group: ObvGroupV2?
        let randomFlowId = FlowIdentifier()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: randomFlowId) { obvContext in
            group = try identityDelegate.getObvGroupV2(with: identifier, within: obvContext)
        }
        return group
    }
    
    
    public func updateGroupV2(ownedCryptoId: ObvCryptoId, groupIdentifier: Data, changeset: ObvGroupV2.Changeset) throws {

        assert(!Thread.isMainThread)
        
        guard !changeset.isEmpty else { return }

        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }

        guard let encodedGroupIdentifier = ObvEncoded(withRawData: groupIdentifier),
              let groupIdentifier = ObvGroupV2.Identifier(encodedGroupIdentifier) else {
            assertionFailure()
            throw Self.makeError(message: "Could not parse group identifier")
        }
        
        let log = self.log

        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()

        let message = try protocolDelegate.getInitiateGroupUpdateMessageForGroupV2Protocol(ownedIdentity: ownedCryptoId.cryptoIdentity,
                                                                                           groupIdentifier: GroupV2.Identifier(obvGroupV2Identifier: groupIdentifier),
                                                                                           changeset: changeset,
                                                                                           flowId: flowId)

        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { obvContext in
            
            
            // Make sure all the other group members have the appropriate capability

            for change in changeset.changes {
                switch change {
                case .memberAdded(contactCryptoId: let otherGroupMember, permissions: _):
                    guard let capabilities = try identityDelegate.getCapabilitiesOfContactIdentity(
                        ownedIdentity: ownedCryptoId.cryptoIdentity,
                        contactIdentity: otherGroupMember.cryptoIdentity,
                        within: obvContext),
                          capabilities.contains(.groupsV2)
                    else {
                        throw Self.makeError(message: "One of the requested group members hasn't the groupv2 capability")
                    }
                default:
                    continue
                }
            }
            
            // If we reach this point, we can update the group
            
            _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
            try obvContext.save(logOnFailure: log)
        }

    }

    
    public func replaceTrustedDetailsByPublishedDetailsOfGroupV2(ownedCryptoId: ObvCryptoId, groupIdentifier: Data) async throws {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }

        guard let encodedGroupIdentifier = ObvEncoded(withRawData: groupIdentifier),
              let obvGroupIdentifier = ObvGroupV2.Identifier(encodedGroupIdentifier)
        else {
            assertionFailure()
            throw Self.makeError(message: "Could not parse group identifier")
        }

        let flowId = FlowIdentifier()
        let log = self.log
        let prng = self.prng
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    
                    // Trust de details locally
                    
                    try identityDelegate.replaceTrustedDetailsByPublishedDetailsOfGroupV2(
                        withGroupWithIdentifier: GroupV2.Identifier(obvGroupV2Identifier: obvGroupIdentifier),
                        of: ownedCryptoId.cryptoIdentity,
                        within: obvContext)
                    
                    // Propagate to our other owned devices
                    
                    let groupVersion = try identityDelegate.getVersionOfGroupV2(
                        withGroupWithIdentifier: GroupV2.Identifier(obvGroupV2Identifier: obvGroupIdentifier),
                        of: ownedCryptoId.cryptoIdentity,
                        within: obvContext)
                    let syncAtom = ObvSyncAtom.trustGroupV2Details(groupIdentifier: groupIdentifier, version: groupVersion)
                    let message = try protocolDelegate.getInitiateSyncAtomMessageForSynchronizationProtocol(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, syncAtom: syncAtom)
                    _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)

                    // Save the context
                    
                    try obvContext.save(logOnFailure: log)
                    
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
    }
    
    
    public func leaveGroupV2(ownedCryptoId: ObvCryptoId, groupIdentifier: Data) throws {
        
        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }

        let log = self.log
        
        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()

        guard let encodedGroupIdentifier = ObvEncoded(withRawData: groupIdentifier),
              let groupIdentifier = ObvGroupV2.Identifier(encodedGroupIdentifier)
        else {
            assertionFailure()
            throw Self.makeError(message: "Could not parse group identifier")
        }

        let message = try protocolDelegate.getInitiateGroupLeaveMessageForGroupV2Protocol(ownedIdentity: ownedCryptoId.cryptoIdentity,
                                                                                          groupIdentifier: GroupV2.Identifier(obvGroupV2Identifier: groupIdentifier),
                                                                                          flowId: flowId)
        
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { obvContext in
            _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
            try obvContext.save(logOnFailure: log)
        }

    }
    
    
    public func performReDownloadOfGroupV2(ownedCryptoId: ObvCryptoId, groupIdentifier: Data) throws {

        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }

        let log = self.log

        guard let encodedGroupIdentifier = ObvEncoded(withRawData: groupIdentifier),
              let groupIdentifier = ObvGroupV2.Identifier(encodedGroupIdentifier)
        else {
            assertionFailure()
            throw Self.makeError(message: "Could not parse group identifier")
        }

        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()

        let message = try protocolDelegate.getInitiateGroupReDownloadMessageForGroupV2Protocol(
            ownedIdentity: ownedCryptoId.cryptoIdentity,
            groupIdentifier: GroupV2.Identifier(obvGroupV2Identifier: groupIdentifier),
            flowId: flowId)
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { obvContext in
            _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
            try obvContext.save(logOnFailure: log)
        }

    }
    
    
    /// Start a owned device discovery protocol for the specified owned identity.
    public func performOwnedDeviceDiscovery(ownedCryptoId: ObvCryptoId) async throws {
        
        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }

        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()
        let log = self.log

        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { [weak self] obvContext in
            try self?.performOwnedDeviceDiscovery(ownedCryptoId: ownedCryptoId.cryptoIdentity, within: obvContext)
            try obvContext.save(logOnFailure: log)
        }
        
    }
    
    
    /// Start a owned device discovery protocol for the specified owned identity and return the server answer. This is used, .e.g, when reactivating the current device in order to show the list of other owned devices to the user.
    public func performOwnedDeviceDiscoveryNow(ownedCryptoId: ObvCryptoId) async throws -> ObvOwnedDeviceDiscoveryResult {

        guard let networkFetchDelegate else { throw ObvError.networkFetchDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }

        let flowId = FlowIdentifier()
        
        let encryptedOwnedDeviceDiscoveryResult = try await networkFetchDelegate.performOwnedDeviceDiscoveryNow(ownedCryptoId: ownedCryptoId.cryptoIdentity, flowId: FlowIdentifier())
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ObvOwnedDeviceDiscoveryResult, Error>) in
            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    let ownedDeviceDiscoveryResult = try identityDelegate.decryptEncryptedOwnedDeviceDiscoveryResult(encryptedOwnedDeviceDiscoveryResult, forOwnedCryptoId: ownedCryptoId.cryptoIdentity, within: obvContext)
                    let obvOwnedDeviceDiscoveryResult = ownedDeviceDiscoveryResult.obvOwnedDeviceDiscoveryResult
                    continuation.resume(returning: obvOwnedDeviceDiscoveryResult)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
    }
    
    
    private func performOwnedDeviceDiscovery(ownedCryptoId: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }

        let message = try protocolDelegate.getInitiateOwnedDeviceDiscoveryMessage(
            ownedCryptoIdentity: ownedCryptoId)

        _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
        
    }
    
    
    /// This method first delete all channels and other owned device. It then performs an owned device discovery. This is enough, since the owned device discovery will eventually add devices and thus, new channels will be created.
    public func deleteAllOtherOwnedDevicesAndChannelsThenPerformOwnedDeviceDiscovery(ownedCryptoId: ObvCryptoId) async throws {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }
        
        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()

        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { obvContext in
            
            try deleteAllOtherOwnedDevicesAndChannelsThenPerformOwnedDeviceDiscovery(
                ownedCryptoId: ownedCryptoId.cryptoIdentity,
                within: obvContext)
            
            do {
                try obvContext.save(logOnFailure: log)
            } catch let error {
                os_log("Could not save context: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                throw error
            }
            
        }
                
    }
    
    
    private func deleteAllOtherOwnedDevicesAndChannelsThenPerformOwnedDeviceDiscovery(ownedCryptoId: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        
        assert(!Thread.isMainThread)
        
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }

        try obvContext.performAndWaitOrThrow {
            
            let currentDeviceUID = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedCryptoId, within: obvContext)
            let otherOwnedDeviceUIDs = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedCryptoId, within: obvContext)

            // We delete all oblivious channels with this contact
            do {
                try otherOwnedDeviceUIDs.forEach { otherOwnedDeviceUID in
                    try channelDelegate.deleteObliviousChannelBetweenCurentDeviceWithUid(currentDeviceUid: currentDeviceUID, andTheRemoteDeviceWithUid: otherOwnedDeviceUID, ofRemoteIdentity: ownedCryptoId, within: obvContext)
                }
            } catch {
                os_log("Could not recreate all channels with contact. We could not delete previous channels.", log: log, type: .fault)
                assertionFailure()
                throw error
            }
            
            // We then delete all previous contact devices
            do {
                try otherOwnedDeviceUIDs.forEach { otherOwnedDeviceUID in
                    try identityDelegate.removeOtherDeviceForOwnedIdentity(ownedCryptoId, otherDeviceUid: otherOwnedDeviceUID, within: obvContext)
                }
            } catch let error {
                os_log("Could not recreate all channels with contact. We could not delete previous devices.", log: log, type: .fault)
                assertionFailure()
                throw error
            }
            
            // We then launch a device discovery
            
            try performOwnedDeviceDiscovery(ownedCryptoId: ownedCryptoId, within: obvContext)
                                    
        }

    }


    
    
    public func performOwnedDeviceDiscoveryForAllOwnedIdentities() async throws {
        try await performOwnedDeviceDiscoveryForAllOwnedIdentities(flowId: FlowIdentifier())
    }
    
    /// Start a owned device discovery protocol for all existing owned identities.
    func performOwnedDeviceDiscoveryForAllOwnedIdentities(flowId: FlowIdentifier) async throws {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }

        var allOwnedIdentities = Set<ObvCryptoIdentity>()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { obvContext in
            allOwnedIdentities = try identityDelegate.getOwnedIdentities(within: obvContext)
        }
        
        for ownedIdentity in allOwnedIdentities {
            try await performOwnedDeviceDiscovery(ownedCryptoId: ObvCryptoId(cryptoIdentity: ownedIdentity))
        }

    }

    
    public func performDisbandOfGroupV2(ownedCryptoId: ObvCryptoId, groupIdentifier: Data) throws {

        assert(!Thread.isMainThread)

        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }

        let log = self.log

        guard let encodedGroupIdentifier = ObvEncoded(withRawData: groupIdentifier),
              let groupIdentifier = ObvGroupV2.Identifier(encodedGroupIdentifier)
        else {
            assertionFailure()
            throw Self.makeError(message: "Could not parse group identifier")
        }

        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()

        let message = try protocolDelegate.getInitiateInitiateGroupDisbandMessageForGroupV2Protocol(ownedIdentity: ownedCryptoId.cryptoIdentity,
                                                                                                    groupIdentifier: GroupV2.Identifier(obvGroupV2Identifier: groupIdentifier),
                                                                                                    flowId: flowId)
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { obvContext in
            _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
            try obvContext.save(logOnFailure: log)
        }

    }

}


// MARK: - Public API for keycloak pushed groups

extension ObvEngine {
    
    public func updateKeycloakGroups(ownedCryptoId: ObvCryptoId, signedGroupBlobs: Set<String>, signedGroupDeletions: Set<String>, signedGroupKicks: Set<String>, keycloakCurrentTimestamp: Date) throws {

        assert(!Thread.isMainThread)

        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }

        let log = self.log

        guard !signedGroupBlobs.isEmpty || !signedGroupDeletions.isEmpty || !signedGroupKicks.isEmpty else {
            // Nothing to do, we return early
            return
        }
        
        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()

        let message = try protocolDelegate.getInitiateUpdateKeycloakGroupsMessageForGroupV2Protocol(ownedIdentity: ownedCryptoId.cryptoIdentity,
                                                                                                    signedGroupBlobs: signedGroupBlobs,
                                                                                                    signedGroupDeletions: signedGroupDeletions,
                                                                                                    signedGroupKicks: signedGroupKicks,
                                                                                                    keycloakCurrentTimestamp: keycloakCurrentTimestamp,
                                                                                                    flowId: flowId)
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { obvContext in
            _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
            try obvContext.save(logOnFailure: log)
        }


    }
    
    
    public func getOwnedIdentityFromMaskingUid() -> ObvCryptoId? {
        assertionFailure("Not implemented at this time since, when synchronizing a keycloak identity, we sync all keycloak identities")
        return nil
    }
    
}

// MARK: - Public API for managing groups

extension ObvEngine {
    
    public func startGroupCreationProtocol(groupName: String, groupDescription: String?, groupMembers: Set<ObvCryptoId>, ownedCryptoId: ObvCryptoId, photoURL: URL?) throws {
        
        guard !groupMembers.isEmpty else { return }
        
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        
        let log = self.log
        
        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()

        var members: Set<CryptoIdentityWithCoreDetails>!
        do {
            var error: Error?
            let randomFlowId = FlowIdentifier()
            createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
                let _contacts = Set(groupMembers.compactMap { ObvContactIdentity(contactCryptoIdentity: $0.cryptoIdentity,
                                                                                 ownedCryptoIdentity: ownedCryptoId.cryptoIdentity,
                                                                                 identityDelegate: identityDelegate,
                                                                                 within: obvContext) })
                guard _contacts.count == groupMembers.count else {
                    error = ObvEngine.makeError(message: "Could not start group creation. At least one of the contacts is invalid.")
                    return
                }
                members = Set(_contacts.map { CryptoIdentityWithCoreDetails(cryptoIdentity: $0.cryptoId.cryptoIdentity, coreDetails: $0.currentIdentityDetails.coreDetails) })
            }
            guard error == nil else { throw error! }
        }

        let groupCoreDetails = ObvGroupCoreDetails(name: groupName, description: groupDescription)
        let message = try protocolDelegate.getInitiateGroupCreationMessageForGroupManagementProtocol(groupCoreDetails: groupCoreDetails,
                                                                                                     photoURL: photoURL,
                                                                                                     pendingGroupMembers: members,
                                                                                                     ownedIdentity: ownedCryptoId.cryptoIdentity)
        
        var error: Error?
        createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            do {
                _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                try obvContext.save(logOnFailure: log)
            } catch let _error {
                error = _error
            }
        }
        guard error == nil else {
            throw error!
        }
        
    }
    
    
    public func disbandGroupV1(groupUid: UID, ownedCryptoId: ObvCryptoId) async throws {
        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }
        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()
        try await postDisbandGroupMessageForGroupManagementProtocol(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, groupUid: groupUid, flowId: flowId)
    }
    
    
    private func postDisbandGroupMessageForGroupManagementProtocol(ownedCryptoIdentity: ObvCryptoIdentity, groupUid: UID, flowId: FlowIdentifier) async throws {
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        let log = self.log
        let prng = self.prng
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    let message = try protocolDelegate.getDisbandGroupMessageForGroupManagementProtocol(
                        groupUid: groupUid,
                        ownedIdentity: ownedCryptoIdentity,
                        within: obvContext)
                    _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                    try obvContext.save(logOnFailure: log)
                    continuation.resume()
                } catch {
                    assertionFailure()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    
    public func inviteContactsToGroupOwned(groupUid: UID, ownedCryptoId: ObvCryptoId, newGroupMembers: Set<ObvCryptoId>) throws {
        
        guard !newGroupMembers.isEmpty else { return }
        
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }

        let log = self.log
        
        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()

        let newMembersCryptoIdentities = Set(newGroupMembers.map { $0.cryptoIdentity })
        let prng = self.prng
        
        var error: Error?
        createContextDelegate.performBackgroundTask(flowId: flowId) { (obvContext) in
            do {
                let message = try protocolDelegate.getAddGroupMembersMessageForAddingMembersToContactGroupOwned(groupUid: groupUid,
                                                                                                                ownedIdentity: ownedCryptoId.cryptoIdentity,
                                                                                                                newGroupMembers: newMembersCryptoIdentities,
                                                                                                                within: obvContext)
                _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                try obvContext.save(logOnFailure: log)
            } catch let _error {
                error = _error
            }
        }
        guard error == nil else {
            throw error!
        }

    }
    
    
    public func reInviteContactToGroupOwned(groupUid: UID, ownedCryptoId: ObvCryptoId, pendingGroupMember: ObvCryptoId) throws {
        
        let newGroupMembers = Set([pendingGroupMember])

        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        
        let log = self.log
        
        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()

        let newMembersCryptoIdentities = Set(newGroupMembers.map { $0.cryptoIdentity })
        let prng = self.prng
        
        var error: Error?
        createContextDelegate.performBackgroundTask(flowId: flowId) { (obvContext) in
            do {
                try identityDelegate.unmarkDeclinedPendingMemberAsDeclined(ownedIdentity: ownedCryptoId.cryptoIdentity,
                                                                           groupUid: groupUid,
                                                                           pendingMember: pendingGroupMember.cryptoIdentity,
                                                                           within: obvContext)
            } catch let _error {
                error = _error
            }
            do {
                let message = try protocolDelegate.getAddGroupMembersMessageForAddingMembersToContactGroupOwned(groupUid: groupUid,
                                                                                                                ownedIdentity: ownedCryptoId.cryptoIdentity,
                                                                                                                newGroupMembers: newMembersCryptoIdentities,
                                                                                                                within: obvContext)
                _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                try obvContext.save(logOnFailure: log)
            } catch let _error {
                error = _error
            }
        }
        guard error == nil else {
            throw error!
        }

        
    }
    
    
    public func removeContactsFromGroupOwned(groupUid: UID, ownedCryptoId: ObvCryptoId, removedGroupMembers: Set<ObvCryptoId>) throws {
        
        guard !removedGroupMembers.isEmpty else { return }
        
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        
        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()

        let removedMembersCryptoIdentities = Set(removedGroupMembers.map { $0.cryptoIdentity })
        let prng = self.prng
        let log = self.log
        
        var error: Error?
        createContextDelegate.performBackgroundTask(flowId: flowId) { (obvContext) in
            do {
                let message = try protocolDelegate.getRemoveGroupMembersMessageForGroupManagementProtocol(groupUid: groupUid,
                                                                                                          ownedIdentity: ownedCryptoId.cryptoIdentity,
                                                                                                          removedGroupMembers: removedMembersCryptoIdentities,
                                                                                                          within: obvContext)
                _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                try obvContext.save(logOnFailure: log)
            } catch let _error {
                error = _error
            }
        }
        guard error == nil else {
            throw error!
        }

        
    }
    
    public func getAllContactGroupsForOwnedIdentity(with ownedCryptoId: ObvCryptoId) throws -> Set<ObvContactGroup> {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        
        var obvContactGroups: Set<ObvContactGroup>!
        var error: Error?
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
            do {
                let groupStructures = try identityDelegate.getAllGroupStructures(ownedIdentity: ownedCryptoId.cryptoIdentity, within: obvContext)
                obvContactGroups = Set(groupStructures.compactMap({ (groupStructure) in
                    return ObvContactGroup(groupStructure: groupStructure, identityDelegate: identityDelegate, within: obvContext)
                }))
                guard obvContactGroups.count == groupStructures.count else {
                    throw Self.makeError(message: "While getting the contact groups of an owned identity, the number of contact groups is not equal to the number of group structures")
                }
            } catch let _error {
                error = _error
                return
            }
        }
        
        guard error == nil else {
            throw error!
        }
        
        return obvContactGroups
    }

    
    public func getContactGroupOwned(groupUid: UID, ownedCryptoId: ObvCryptoId) throws -> ObvContactGroup {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        
        var obvContactGroup: ObvContactGroup!
        var error: Error?
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
            do {
                guard let groupStructure = try identityDelegate.getGroupOwnedStructure(ownedIdentity: ownedCryptoId.cryptoIdentity, groupUid: groupUid, within: obvContext) else {
                    throw Self.makeError(message: "Could not get group owned structure")
                }
                guard let _obvContactGroup = ObvContactGroup(groupStructure: groupStructure, identityDelegate: identityDelegate, within: obvContext) else {
                    throw Self.makeError(message: "Could not create ObvContactGroup")
                }
                obvContactGroup = _obvContactGroup
            } catch let _error {
                error = _error
                return
            }
        }
        
        guard error == nil else {
            throw error!
        }
        
        return obvContactGroup

    }
    
    
    public func getContactGroupJoined(groupUid: UID, groupOwner: ObvCryptoId, ownedCryptoId: ObvCryptoId) throws -> ObvContactGroup {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        
        var obvContactGroup: ObvContactGroup!
        var error: Error?
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
            do {
                guard let groupStructure = try identityDelegate.getGroupJoinedStructure(ownedIdentity: ownedCryptoId.cryptoIdentity, groupUid: groupUid, groupOwner: groupOwner.cryptoIdentity, within: obvContext) else {
                    throw Self.makeError(message: "Could not get group joined structure")
                }
                guard let _obvContactGroup = ObvContactGroup(groupStructure: groupStructure, identityDelegate: identityDelegate, within: obvContext) else {
                    throw Self.makeError(message: "Could not create ObvContactGroup")
                }
                obvContactGroup = _obvContactGroup
            } catch let _error {
                error = _error
                return
            }
        }
        
        guard error == nil else {
            throw error!
        }
        
        return obvContactGroup
        
    }
    
    
    public func getContactGroup(groupIdentifier: ObvGroupV1Identifier) throws -> ObvContactGroup {
        
        switch groupIdentifier.groupType {
        case .owned:
            return try getContactGroupOwned(groupUid: groupIdentifier.groupV1Identifier.groupUid, ownedCryptoId: groupIdentifier.ownedCryptoId)
        case .joined:
            return try getContactGroupJoined(groupUid: groupIdentifier.groupV1Identifier.groupUid, groupOwner: groupIdentifier.groupV1Identifier.groupOwner, ownedCryptoId: groupIdentifier.ownedCryptoId)
        }
        
    }

    
    public func updateLatestDetailsOfOwnedContactGroup(using newGroupDetails: ObvGroupDetails, ownedCryptoId: ObvCryptoId, groupUid: UID) throws {
        
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        
        let randomFlowId = FlowIdentifier()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: randomFlowId) { (obvContext) in
            guard let currentGroupStructure = try identityDelegate.getGroupOwnedStructure(ownedIdentity: ownedCryptoId.cryptoIdentity, groupUid: groupUid, within: obvContext) else {
                throw makeError(message: "Could not find group structure")
            }
            guard currentGroupStructure.groupType == .owned else { throw makeError(message: "The group type is not owned") }
            let publishedGroupDetailsWithPhoto = currentGroupStructure.publishedGroupDetailsWithPhoto
            let currentLatestDetailsWithPhoto = currentGroupStructure.trustedOrLatestGroupDetailsWithPhoto
            let newCoreDetails = newGroupDetails.coreDetails
            
            let newPhotoServerKeyAndLabel: PhotoServerKeyAndLabel?
            let newPhotoURL: URL?
            if currentLatestDetailsWithPhoto.hasIdenticalPhotoThanPhotoAtURL(newGroupDetails.photoURL) {
                // The photo did not change, we can keep previous values
                newPhotoServerKeyAndLabel = currentLatestDetailsWithPhoto.photoServerKeyAndLabel
                newPhotoURL = currentLatestDetailsWithPhoto.photoURL
            } else {
                newPhotoServerKeyAndLabel = nil
                newPhotoURL = newGroupDetails.photoURL
            }
            
            let newLatestDetails = GroupDetailsElementsWithPhoto(coreDetails: newCoreDetails,
                                                                 version: publishedGroupDetailsWithPhoto.version+1,
                                                                 photoServerKeyAndLabel: newPhotoServerKeyAndLabel,
                                                                 photoURL: newPhotoURL)

            try identityDelegate.updateLatestDetailsOfContactGroupOwned(ownedIdentity: ownedCryptoId.cryptoIdentity, groupUid: groupUid, with: newLatestDetails, within: obvContext)
            try obvContext.save(logOnFailure: log)
        }
        
    }
    
    
    public func discardLatestDetailsOfOwnedContactGroup(ownedCryptoId: ObvCryptoId, groupUid: UID) throws {
        
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        
        do {
            var error: Error?
            let randomFlowId = FlowIdentifier()
            createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
                do {
                    guard let groupStructure = try identityDelegate.getGroupOwnedStructure(ownedIdentity: ownedCryptoId.cryptoIdentity, groupUid: groupUid, within: obvContext) else {
                        throw Self.makeError(message: "Could not get group owned structure")
                    }
                    guard groupStructure.groupType == .owned else {
                        throw Self.makeError(message: "Could not discard latest details of owned contact group as the group type is not owned")
                    }
                    try identityDelegate.discardLatestDetailsOfContactGroupOwned(ownedIdentity: ownedCryptoId.cryptoIdentity, groupUid: groupUid, within: obvContext)
                    try obvContext.save(logOnFailure: log)
                } catch let _error {
                    error = _error
                }
            }
            guard error == nil else { throw error! }
        }
        
    }

    
    public func publishLatestDetailsOfOwnedContactGroup(ownedCryptoId: ObvCryptoId, groupUid: UID) throws {
        
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }
        
        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
            
            try identityDelegate.publishLatestDetailsOfContactGroupOwned(ownedIdentity: ownedCryptoId.cryptoIdentity, groupUid: groupUid, within: obvContext)
            guard let groupStructure = try identityDelegate.getGroupOwnedStructure(ownedIdentity: ownedCryptoId.cryptoIdentity, groupUid: groupUid, within: obvContext) else {
                throw makeError(message: "Could not find group structure")
            }
            guard groupStructure.groupType == .owned else {
                throw Self.makeError(message: "Could not publish latest details of owned contact group as the group type is not owned")
            }
            try startOwnedGroupLatestDetailsPublicationProtocol(for: groupStructure, within: obvContext)
            try obvContext.save(logOnFailure: log)
        }
        
    }

    
    public func trustPublishedDetailsOfJoinedContactGroup(ownedCryptoId: ObvCryptoId, groupUid: UID, groupOwner: ObvCryptoId) async throws {
    
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        
        let flowId = FlowIdentifier()
        let log = self.log
        let prng = self.prng
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    
                    // Trust the published details locally
                    
                    guard let groupStructure = try identityDelegate.getGroupJoinedStructure(ownedIdentity: ownedCryptoId.cryptoIdentity, groupUid: groupUid, groupOwner: groupOwner.cryptoIdentity, within: obvContext) else {
                        throw Self.makeError(message: "Could not trust published details of joined contact group as we could not get the group joined structure")
                    }
                    
                    guard groupStructure.groupType == .joined else {
                        throw Self.makeError(message: "Could not trust published details of joined contact group as the group type is not .joined")
                    }
                    
                    try identityDelegate.trustPublishedDetailsOfContactGroupJoined(ownedIdentity: ownedCryptoId.cryptoIdentity, groupUid: groupUid, groupOwner: groupOwner.cryptoIdentity, within: obvContext)
                    
                    // Propagate to other owned devices
                    
                    let groupDetailsElements = try identityDelegate.getGroupJoinedInformationAndPublishedPhoto(
                        ownedIdentity: ownedCryptoId.cryptoIdentity,
                        groupUid: groupUid,
                        groupOwner: groupOwner.cryptoIdentity,
                        within: obvContext).groupDetailsElementsWithPhoto.groupDetailsElements
                    let serializedGroupDetailsElements = try groupDetailsElements.jsonEncode()
                    let syncAtom = ObvSyncAtom.trustGroupV1Details(groupOwner: groupOwner, groupUid: groupUid, serializedGroupDetailsElements: serializedGroupDetailsElements)
                    let message = try protocolDelegate.getInitiateSyncAtomMessageForSynchronizationProtocol(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, syncAtom: syncAtom)
                    _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                    
                    // Save the context
                    
                    try obvContext.save(logOnFailure: log)

                    continuation.resume()
                    
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
    }

    
    // Called when the owned identity decides to leave a group she joined
    public func leaveContactGroupJoined(ownedCryptoId: ObvCryptoId, groupUid: UID, groupOwner: ObvCryptoId) throws {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }

        let log = self.log
        
        let flowId = FlowIdentifier()
        var error: Error?
        createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            do {
                let message = try protocolDelegate.getLeaveGroupJoinedMessageForGroupManagementProtocol(ownedIdentity: ownedCryptoId.cryptoIdentity,
                                                                                                        groupUid: groupUid,
                                                                                                        groupOwner: groupOwner.cryptoIdentity,
                                                                                                        within: obvContext)
                _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                try obvContext.save(logOnFailure: log)
            } catch let _error {
                error = _error
            }
        }
        guard error == nil else { throw error! }
        
    }
    
    
    public func refreshContactGroupJoined(ownedCryptoId: ObvCryptoId, groupUid: UID, groupOwner: ObvCryptoId) throws {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }

        let log = self.log
        
        let flowId = FlowIdentifier()
        var error: Error?
        createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            do {
                let message = try protocolDelegate.getInitiateGroupMembersQueryMessageForGroupManagementProtocol(groupUid: groupUid, ownedIdentity: ownedCryptoId.cryptoIdentity, groupOwner: groupOwner.cryptoIdentity, within: obvContext)
                _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                try obvContext.save(logOnFailure: log)
            } catch let _error {
                error = _error
            }
        }
        guard error == nil else { throw error! }

    }
}

// MARK: - Public API for Return Receipt

extension ObvEngine {
        
    /// This method returns the status of each register websocket. This is essentially used for debugging the websockets.
    public func getWebSocketState(ownedIdentity: ObvCryptoId) async throws -> (URLSessionTask.State,TimeInterval?) {
        guard let networkFetchDelegate else { throw ObvError.networkFetchDelegateIsNil }
        return try await networkFetchDelegate.getWebSocketState(ownedIdentity: ownedIdentity.cryptoIdentity)
    }
    
    /// This method returns a 16 bytes nonce and a serialized encryption key. This is called when sending a message, in order to make it
    /// possible to have a return receipt back.
    public func generateReturnReceiptElements() -> (nonce: Data, key: Data) {
        return returnReceiptSender.generateReturnReceiptElements()
    }
    
    
    public func postReturnReceiptWithElements(_ elements: (nonce: Data, key: Data), andStatus status: Int, forContactCryptoId contactCryptoId: ObvCryptoId, ofOwnedIdentityCryptoId ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data, attachmentNumber: Int?) throws {
        
        os_log("🧾 Call to postReturnReceiptWithElements with nonce %{public}@ and attachmentNumber: %{public}@", log: log, type: .info, elements.nonce.hexString(), String(describing: attachmentNumber))
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }

        let contactCryptoIdentity = contactCryptoId.cryptoIdentity
        let ownedCryptoIdentity = ownedCryptoId.cryptoIdentity

        guard let messageUid = UID(uid: messageIdentifierFromEngine) else { assertionFailure(); throw makeError(message: "Could not parse message identifier from engine") }
        let messageId = ObvMessageIdentifier(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, uid: messageUid)

        // We do not need to start a flow in order to wait for the return receipt to be posted.
        // It was started when receiving the notification from the network manager informing the engine that a message / attachment is fully available.
        
        let flowId = FlowIdentifier()

        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
            let deviceUids = try identityDelegate.getDeviceUidsOfContactIdentity(contactCryptoIdentity, ofOwnedIdentity: ownedCryptoIdentity, within: obvContext)
            Task {
                try? await returnReceiptSender.postReturnReceiptWithElements(elements,
                                                                             andStatus: status,
                                                                             to: contactCryptoId,
                                                                             ownedCryptoId: ownedCryptoId,
                                                                             withDeviceUids: deviceUids,
                                                                             messageId: messageId,
                                                                             attachmentNumber: attachmentNumber,
                                                                             flowId: flowId)
                // We stop the flow that was created for us (see above) since we now that the upload of the return receipt was dealt with.
                // We do not distinguish between a success and a failure here.
                // Note also that, when the above call to `postReturnReceiptWithElements(...)` returns, the upload is either done or failed (note the `await` keyword).
                try? flowDelegate.stopBackgroundActivityForPostingReturnReceipt(messageId: messageId, attachmentNumber: attachmentNumber)
            }
        }
        
    }
    
    
    public func decryptPayloadOfObvReturnReceipt(_ obvReturnReceipt: ObvReturnReceipt, usingElements elements: (nonce: Data, key: Data)) throws -> (contactCryptoId: ObvCryptoId, status: Int, attachmentNumber: Int?) {
        return try returnReceiptSender.decryptPayloadOfObvReturnReceipt(obvReturnReceipt, usingElements: elements)
    }
    
    
    public func deleteObvReturnReceipt(_ obvReturnReceipt: ObvReturnReceipt) async {
        do {
            try await delegateManager.networkFetchDelegate?.sendDeleteReturnReceipt(ownedIdentity: obvReturnReceipt.identity, serverUid: obvReturnReceipt.serverUid)
        } catch let error {
            os_log("Could not delete the ReturnReceipt on server: %{public}@", log: log, type: .error, error.localizedDescription)
        }
    }
    
}

// MARK: - Public API for posting messages

extension ObvEngine {
    
    /// This method posts a message and its attachments to all the specified contacts.
    /// It returns a dictionary where the keys correspond to all the recipients for which the message has been successfully sent. Each value of the dictionary corresponds to a message identifier chosen by this engine. Note that two users on the same server will receive the same message identifier.
    /// - Parameters:
    ///   - messagePayload: The payload of the message.
    ///   - withUserContent: Set this to `true` if the sent message contains user content that can typically be displayed in a user notification. Set this to `false` for e.g. system receipts.
    ///   - attachmentsToSend: An array of attachments to send alongside the message.
    ///   - contactCryptoIds: The set of contacts to whom the message shall be sent.
    ///   - ownedCryptoId: The owned cryptoId sending the message.
    ///   - alsoPostToOtherOwnedDevices: Set this to `true` to send the message to the other devices of the owned identity
    ///   - completionHandler: A completion block, executed when the post has done was is required. Hint : for now, this is only used when calling this method from the share extension, in order to dismiss the share extension on post completion.
    public func post(messagePayload: Data, extendedPayload: Data?, withUserContent: Bool, isVoipMessageForStartingCall: Bool, attachmentsToSend: [ObvAttachmentToSend], toContactIdentitiesWithCryptoId contactCryptoIds: Set<ObvCryptoId>, ofOwnedIdentityWithCryptoId ownedCryptoId: ObvCryptoId, alsoPostToOtherOwnedDevices: Bool, completionHandler: (() -> Void)? = nil) throws -> [ObvCryptoId: Data] {
        
        guard !contactCryptoIds.isEmpty || alsoPostToOtherOwnedDevices else {
            completionHandler?()
            return [:]
        }
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }
        
        
        let attachments: [ObvChannelApplicationMessageToSend.Attachment] = attachmentsToSend.map {
            return ObvChannelApplicationMessageToSend.Attachment(fileURL: $0.fileURL,
                                                                 deleteAfterSend: $0.deleteAfterSend,
                                                                 byteSize: $0.totalUnitCount,
                                                                 metadata: $0.metadata)
        }

        let message = ObvChannelApplicationMessageToSend(toContactIdentities: Set(contactCryptoIds.map({ $0.cryptoIdentity })),
                                                         fromIdentity: ownedCryptoId.cryptoIdentity,
                                                         messagePayload: messagePayload,
                                                         extendedMessagePayload: extendedPayload,
                                                         withUserContent: withUserContent,
                                                         isVoipMessageForStartingCall: isVoipMessageForStartingCall,
                                                         attachments: attachments,
                                                         alsoPostToOtherOwnedDevices: alsoPostToOtherOwnedDevices)

        let flowId = try flowDelegate.startNewFlow(completionHandler: completionHandler)

        var messageIdentifierForContactToWhichTheMessageWasSent = [ObvCryptoId: Data]()

        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { [weak self] obvContext in
            guard let _self = self else { return }
                
            assert(!Thread.isMainThread)
            
            let messageIdentifiersForToIdentities = try channelDelegate.postChannelMessage(message, randomizedWith: _self.prng, within: obvContext)
            
            try messageIdentifiersForToIdentities.keys.forEach { messageId in
                let attachmentIds = (0..<attachmentsToSend.count).map { ObvAttachmentIdentifier(messageId: messageId, attachmentNumber: $0) }
                try flowDelegate.addBackgroundActivityForPostingApplicationMessageAttachmentsWithinFlow(withFlowId: flowId,
                                                                                                        messageId: messageId,
                                                                                                        attachmentIds: attachmentIds)
            }
            
            messageIdentifiersForToIdentities.forEach { messageId, contactCryptoIds in
                contactCryptoIds.forEach { contactCryptoIdendity in
                    let contactCryptoId = ObvCryptoId(cryptoIdentity: contactCryptoIdendity)
                    assert(!messageIdentifierForContactToWhichTheMessageWasSent.keys.contains(contactCryptoId))
                    messageIdentifierForContactToWhichTheMessageWasSent[contactCryptoId] = messageId.uid.raw
                }
            }
            
            try obvContext.save(logOnFailure: _self.log)

        }

        return messageIdentifierForContactToWhichTheMessageWasSent

    }
    
    
    public func cancelPostOfMessage(withIdentifier messageIdRaw: Data, ownedCryptoId: ObvCryptoId) throws {
        
        guard let networkPostDelegate = networkPostDelegate else { throw makeError(message: "The network post delegate is not set") }

        guard let uid = UID(uid: messageIdRaw) else { throw ObvEngine.makeError(message: "Could not parse message identifier") }
        let messageId = ObvMessageIdentifier(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, uid: uid)
        
        let randomFlowId = FlowIdentifier()
        try networkPostDelegate.cancelPostOfMessage(messageId: messageId, flowId: randomFlowId)
    }
    
}


// MARK: - Public API for receiving messages

extension ObvEngine {
    
    
    /// Called by the app when a received message is properly processed.
    public func messageWasProcessed(messageId: ObvMessageIdentifier, attachmentsProcessingRequest: ObvAttachmentsProcessingRequest) async throws {
        
        guard let networkFetchDelegate else { throw ObvError.networkFetchDelegateIsNil }
        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }

        let (flowId, flowCompletionHandler) = try flowDelegate.startBackgroundActivityForMarkingMessageForDeletionAndProcessingAttachments(messageId: messageId)
        
        /// Before notifying the app, we created a background activity for posting a return receipt. We stop it now, since we started another background activity
        try? flowDelegate.stopBackgroundActivityForPostingReturnReceipt(messageId: messageId, attachmentNumber: nil)
        
        try await networkFetchDelegate.markApplicationMessageForDeletionAndProcessAttachments(messageId: messageId, attachmentsProcessingRequest: attachmentsProcessingRequest, flowId: flowId)
        flowCompletionHandler()
        
    }
    
    
    public func deleteObvAttachment(attachmentNumber: Int, ofMessageWithIdentifier messageIdRaw: Data, ownedCryptoId: ObvCryptoId) async throws {
        
        guard let networkFetchDelegate else { throw ObvError.networkFetchDelegateIsNil }
        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }

        guard let uid = UID(uid: messageIdRaw) else { assertionFailure(); throw ObvError.couldNotParseMessageIdentifier }
        let messageId = ObvMessageIdentifier(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, uid: uid)
        let attachmentId = ObvAttachmentIdentifier(messageId: messageId, attachmentNumber: attachmentNumber)

        let (flowId, flowCompletionHandler) = try flowDelegate.startBackgroundActivityForMarkingAttachmentForDeletion(attachmentId: attachmentId)
        try await networkFetchDelegate.markAttachmentForDeletion(attachmentId: attachmentId, flowId: flowId)
        flowCompletionHandler()
        
    }
    
    
    /// Called, e.g., when the user performs a pull down to refresh in the list of recent discussion
    public func downloadAllMessagesForOwnedIdentities() async throws {
        
        guard let networkFetchDelegate else { assertionFailure(); return }
        guard let flowDelegate else { assertionFailure(); return }

        let ownedIdentities = try await getOwnedIdentities()
        
        var anErrorOccurred: Error?
        
        let flowId = FlowIdentifier()
        
        for ownedIdentity in ownedIdentities {
            do {
                let (_, completion) = try flowDelegate.startBackgroundActivityForDownloadingMessages(ownedIdentity: ownedIdentity)
                await networkFetchDelegate.downloadMessages(for: ownedIdentity, flowId: flowId)
                completion()
            } catch {
                anErrorOccurred = error
            }
        }
        
        if let anErrorOccurred {
            throw anErrorOccurred
        }

    }
    
    
    /// This method is called, e.g., when the user wants to delete a received message. This method marks the message and its attachments for deletion and returns before the message is actually deleted from the server, then from the inbox.
    public func cancelDownloadOfMessage(ownedCryptoId: ObvCryptoId, messageIdentifier: Data) async throws {
        
        guard let networkFetchDelegate else { throw ObvError.networkFetchDelegateIsNil }
        
        guard let uid = UID(uid: messageIdentifier) else { throw ObvEngine.makeError(message: "Could not parse message id") }
        let messageId = ObvMessageIdentifier(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, uid: uid)

        try await networkFetchDelegate.deleteApplicationMessageAndAttachments(messageId: messageId, flowId: FlowIdentifier())
        
    }
    
    
    /// Called by the app when it cannot find an attachment file although it was notified that the attachment was downloaded.
    public func appCouldNotFindFileOfDownloadedAttachment(_ attachmentNumber: Int, ofMessageWithIdentifier messageIdRaw: Data, ownedCryptoId: ObvCryptoId) async throws {
        
        guard let networkFetchDelegate else { assertionFailure(); throw ObvError.networkFetchDelegateIsNil }

        guard let uid = UID(uid: messageIdRaw) else { throw ObvEngine.makeError(message: "Could not parse message identifier") }
        let messageId = ObvMessageIdentifier(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, uid: uid)
        let attachmentId = ObvAttachmentIdentifier(messageId: messageId, attachmentNumber: attachmentNumber)
        
        let randomFlowId = FlowIdentifier()
        try await networkFetchDelegate.appCouldNotFindFileOfDownloadedAttachment(attachmentId: attachmentId, flowId: randomFlowId)

    }
    
    
    public func resumeDownloadOfAttachment(_ attachmentNumber: Int, ofMessageWithIdentifier messageIdRaw: Data, ownedCryptoId: ObvCryptoId) async throws {
        
        guard let networkFetchDelegate else { throw ObvError.networkFetchDelegateIsNil }

        guard let uid = UID(uid: messageIdRaw) else { throw ObvEngine.makeError(message: "Could not parse message identifier") }
        let messageId = ObvMessageIdentifier(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, uid: uid)
        let attachmentId = ObvAttachmentIdentifier(messageId: messageId, attachmentNumber: attachmentNumber)
        
        let randomFlowId = FlowIdentifier()
        try await networkFetchDelegate.resumeDownloadOfAttachment(attachmentId: attachmentId, flowId: randomFlowId)
        
    }

    
    public func pauseDownloadOfAttachment(_ attachmentNumber: Int, ofMessageWithIdentifier messageIdRaw: Data, ownedCryptoId: ObvCryptoId) async throws {
        
        guard let networkFetchDelegate else { throw ObvError.networkFetchDelegateIsNil }

        guard let uid = UID(uid: messageIdRaw) else { throw ObvEngine.makeError(message: "Could not parse message identifier") }
        let messageId = ObvMessageIdentifier(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, uid: uid)
        let attachmentId = ObvAttachmentIdentifier(messageId: messageId, attachmentNumber: attachmentNumber)
        
        let randomFlowId = FlowIdentifier()
        try await networkFetchDelegate.pauseDownloadOfAttachment(attachmentId: attachmentId, flowId: randomFlowId)
        
    }
    
    
    public func requestDownloadAttachmentProgressesUpdatedSince(date: Date) async throws -> [(ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data, attachmentNumber: Int, progress: Float)] {
        guard let networkFetchDelegate else { throw ObvError.networkFetchDelegateIsNil }
        let progresses = try await networkFetchDelegate.requestDownloadAttachmentProgressesUpdatedSince(date: date)
        let progressesToReturn = progresses.map { (attachmentId: ObvAttachmentIdentifier, progress: Float) in
            (ObvCryptoId(cryptoIdentity: attachmentId.messageId.ownedCryptoIdentity), attachmentId.messageId.uid.raw, attachmentId.attachmentNumber, progress)
        }
        return progressesToReturn
    }
    
    
    public func requestUploadAttachmentProgressesUpdatedSince(date: Date) async throws -> [(ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data, attachmentNumber: Int, progress: Float)] {
        guard let networkPostDelegate = networkPostDelegate else { throw makeError(message: "The network post delegate is not set") }
        let progresses = try await networkPostDelegate.requestUploadAttachmentProgressesUpdatedSince(date: date)
        let progressesToReturn = progresses.map { (attachmentId: ObvAttachmentIdentifier, progress: Float) in
            (ObvCryptoId(cryptoIdentity: attachmentId.messageId.ownedCryptoIdentity), attachmentId.messageId.uid.raw, attachmentId.attachmentNumber, progress)
        }
        return progressesToReturn
    }


}

// MARK: - Public API for Downloading Files in the Background, remote notifications, and background fetches

extension ObvEngine {
    
    public func storeCompletionHandler(_ handler: @escaping () -> Void, forHandlingEventsForBackgroundURLSessionWithIdentifier backgroundURLSessionIdentifier: String) async throws {
        
        let flowId = FlowIdentifier()
        
        guard let networkPostDelegate = networkPostDelegate else { throw Self.makeError(message: "The network post delegate is not set") }
        guard let networkFetchDelegate else { throw ObvError.networkFetchDelegateIsNil }

        if networkPostDelegate.backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: backgroundURLSessionIdentifier) {
            os_log("🌊 The background URLSession Identifier %{public}@ is appropriate for the Network Post Delegate", log: log, type: .info, backgroundURLSessionIdentifier)
            networkPostDelegate.storeCompletionHandler(handler, forHandlingEventsForBackgroundURLSessionWithIdentifier: backgroundURLSessionIdentifier, withinFlowId: flowId)
        }
        
        if await networkFetchDelegate.backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: backgroundURLSessionIdentifier) {
            os_log("🌊 The background URLSession Identifier %{public}@ is appropriate for the Network Fetch Delegate", log: log, type: .info, backgroundURLSessionIdentifier)
            await networkFetchDelegate.processCompletionHandler(handler, forHandlingEventsForBackgroundURLSessionWithIdentifier: backgroundURLSessionIdentifier, withinFlowId: flowId)
        }
        
    }

}


// MARK: - Public API for Decrypting application messages

extension ObvEngine {
    
    public func decrypt(encryptedPushNotification encryptedNotification: ObvEncryptedPushNotification) async throws -> ObvMessage {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        
        let log = self.log

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ObvMessage, Error>) in
            let randomFlowId = FlowIdentifier()
            createContextDelegate.performBackgroundTask(flowId: randomFlowId) { (obvContext) in
                do {
                    
                    guard let ownedIdentity = try identityDelegate.getOwnedIdentityAssociatedToMaskingUID(encryptedNotification.maskingUID, within: obvContext) else {
                        os_log("We could not find an appropriate owned identity associated to the masking UID", log: log, type: .error)
                        throw ObvError.noAppropriateOwnedIdentityFound
                    }
                    
                    let messageId = ObvMessageIdentifier(ownedCryptoIdentity: ownedIdentity, uid: encryptedNotification.messageIdFromServer)
                    let encryptedMessage = ObvNetworkReceivedMessageEncrypted(
                        messageId: messageId,
                        messageUploadTimestampFromServer: encryptedNotification.messageUploadTimestampFromServer,
                        downloadTimestampFromServer: encryptedNotification.messageUploadTimestampFromServer, /// Encrypted notifications do no have access to a download timestamp from server
                        localDownloadTimestamp: encryptedNotification.localDownloadTimestamp,
                        encryptedContent: encryptedNotification.encryptedContent,
                        wrappedKey: encryptedNotification.wrappedKey,
                        knownAttachmentCount: nil,
                        availableEncryptedExtendedContent: encryptedNotification.encryptedExtendedContent)

                    let decryptedMessage = try channelDelegate.decrypt(encryptedMessage, within: randomFlowId)

                    // We pass nil for the networkFetchDelegate since it is only used to decrypt attachements that are not yet available.
                    let obvMessage = try ObvMessage(networkReceivedMessage: decryptedMessage, networkFetchDelegate: nil, within: obvContext)

                    continuation.resume(returning: obvMessage)
                    
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
    }
    
}


// MARK: - Public API for notifying the various delegates of the App state

extension ObvEngine {
    
    public func applicationAppearedOnScreen(forTheFirstTime: Bool) async {
        let flowId = FlowIdentifier()
        Task { [weak self] in await self?.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime, flowId: flowId) }
    }

    
    public func applicationAppearedOnScreen(forTheFirstTime: Bool, flowId: FlowIdentifier) async {
        for manager in delegateManager.registeredManagers {
            await manager.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime, flowId: flowId)
        }
        replayTransactionsHistory() // 2022-02-24: Used to be called only if forTheFirstTime. We now want to empty the history as soon as possible.
        if forTheFirstTime {
            do {
                try await performOwnedDeviceDiscoveryForAllOwnedIdentities(flowId: flowId)
                // try await sendTriggerSyncSnapshotMessageToAllExistingSynchronizationProtocolInstances(flowId: flowId)
                // try await initiateIfRequiredSynchronizationProtocolInstanceForEachChannelWithAnotherOwnedDevice(flowId: flowId)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }

    
    /// This method allows to immediately download all messages from the server, for all owned identities, and connect all websockets.
    public func downloadMessagesAndConnectWebsockets() async throws {
        
        guard let networkFetchDelegate else { throw ObvError.networkFetchDelegateIsNil }
        guard let flowDelegate else { assertionFailure(); throw ObvError.flowDelegateIsNil }
        
        let flowId = FlowIdentifier()
        
        await networkFetchDelegate.connectWebsockets(flowId: flowId)
        
        var anErrorOccured: Error?
        
        let ownedIdentities = try await getOwnedIdentities()
        for ownedIdentity in ownedIdentities {
            do {
                let (_, completion) = try flowDelegate.startBackgroundActivityForDownloadingMessages(ownedIdentity: ownedIdentity)
                await networkFetchDelegate.downloadMessages(for: ownedIdentity, flowId: flowId)
                completion()
            } catch {
                anErrorOccured = error
            }
        }
        
        if let anErrorOccured {
            throw anErrorOccured
        }
        
    }
    
    
    public func disconnectWebsockets() async throws {
        guard let networkFetchDelegate else { throw ObvError.networkFetchDelegateIsNil }
        let flowId = FlowIdentifier()
        await networkFetchDelegate.disconnectWebsockets(flowId: flowId)
    }
        
}


// MARK: - Public API for backup

extension ObvEngine {
    
    public var isBackupRequired: Bool {
        return backupDelegate?.isBackupRequired ?? false
    }
    
    
    public func userJustActivatedAutomaticBackup() {
        backupDelegate?.userJustActivatedAutomaticBackup()
    }
    
    
    public func markBackupAsUploaded(backupKeyUid: UID, backupVersion: Int) async throws {
        let flowId = FlowIdentifier()
        try await backupDelegate?.markBackupAsUploaded(backupKeyUid: backupKeyUid, backupVersion: backupVersion, flowId: flowId)
    }

    
    public func markBackupAsExported(backupKeyUid: UID, backupVersion: Int) async throws {
        let flowId = FlowIdentifier()
        try await backupDelegate?.markBackupAsExported(backupKeyUid: backupKeyUid, backupVersion: backupVersion, flowId: flowId)
    }
    
    public func markBackupAsFailed(backupKeyUid: UID, backupVersion: Int) async throws {
        let flowId = FlowIdentifier()
        try await backupDelegate?.markBackupAsFailed(backupKeyUid: backupKeyUid, backupVersion: backupVersion, flowId: flowId)
    }
    
    
    public func getCurrentBackupKeyInformation() async throws -> ObvBackupKeyInformation? {
        
        guard let backupDelegate = self.backupDelegate else {
            os_log("The backup delegate is not set", log: log, type: .fault)
            assertionFailure()
            throw ObvEngine.makeError(message: "Internal error")
        }

        let flowId = FlowIdentifier()
                    
        let obvBackupKeyInformation: ObvBackupKeyInformation
        do {
            guard let backupKeyInformation = try await backupDelegate.getBackupKeyInformation(flowId: flowId) else { return nil }
            obvBackupKeyInformation = ObvBackupKeyInformation(backupKeyInformation: backupKeyInformation)
        } catch let error {
            os_log("Could not get backup key information: %{public}@", log: log, type: .fault, error.localizedDescription)
            throw error
        }
        
        return obvBackupKeyInformation
    }
    
    
    public func generateNewBackupKey() async {
        
        let flowId = FlowIdentifier()
        os_log("Generating a new backup key within flow %{public}@", log: log, type: .info, flowId.debugDescription)
        
        guard let backupDelegate = self.backupDelegate else {
            os_log("The backup delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        backupDelegate.generateNewBackupKey(flowId: flowId)
    }
    
    
    public func verifyBackupKeyString(_ backupSeedString: String) async throws -> Bool {
        
        guard let backupDelegate = self.backupDelegate else {
            os_log("The backup delegate is not set", log: log, type: .fault)
            assertionFailure()
            throw Self.makeError(message: "Internal error")
        }

        let flowId = FlowIdentifier()

        return try await backupDelegate.verifyBackupKey(backupSeedString: backupSeedString, flowId: flowId)
        
    }


    public func initiateBackup(forExport: Bool, requestUUID: UUID) async throws -> (backupKeyUid: UID, version: Int, encryptedContent: Data) {
        let flowId = requestUUID
        guard let backupDelegate = self.backupDelegate else { assertionFailure(); throw Self.makeError(message: "The backup delegate is not set") }
        os_log("Starting backup within flow %{public}@", log: log, type: .info, flowId.debugDescription)
        return try await backupDelegate.initiateBackup(forExport: forExport, backupRequestIdentifier: flowId)
    }

    
    public func getAcceptableCharactersForBackupKeyString() -> CharacterSet {
        return BackupSeed.acceptableCharacters
    }
    
    
    public func recoverBackupData(_ backupData: Data, withBackupKey backupKey: String) async throws -> (backupRequestIdentifier: UUID, backupDate: Date) {
        
        guard let backupDelegate = self.backupDelegate else {
            assertionFailure()
            throw makeError(message: "The backup delegate is not set")
        }

        let backupRequestIdentifier = FlowIdentifier()
        os_log("Starting backup decryption with backup identifier %{public}@", log: log, type: .info, backupRequestIdentifier.debugDescription)

        return try await backupDelegate.recoverBackupData(backupData, withBackupKey: backupKey, backupRequestIdentifier: backupRequestIdentifier)
        
    }
    
    
    /// Returns the ObvCryptoIds of the restored owned identities.
    public func restoreFullBackup(backupRequestIdentifier: FlowIdentifier, nameToGiveToCurrentDevice: String) async throws -> Set<ObvCryptoId> {
        
        os_log("Starting backup restore identified by %{public}@", log: log, type: .info, backupRequestIdentifier.debugDescription)
        
        guard let backupDelegate else { assertionFailure(); throw ObvError.backupDelegateIsNil }

        // Get a set of owned identities that exist before the backup restore
        
        let preExistingOwnedCryptoIds = try await getOwnedIdentities()
        
        // Restore the backup
        
        try await backupDelegate.restoreFullBackup(backupRequestIdentifier: backupRequestIdentifier)
        
        // Get the set of restore owned identities
        
        let restoredOwnedIdentities = try await getOwnedIdentities().subtracting(preExistingOwnedCryptoIds)
        
        // If we reach this point, the backup was successfully restored
        // We perform post-restore tasks
                
        // Set the current device name for all owned identities
        // We only do it locally, the following request (for push notification), will inform the server
        try setCurrentDeviceNameOfAllRestoredOwnedIdentitiesAfterBackupRestore(restoredOwnedIdentities: restoredOwnedIdentities, nameToGiveToCurrentDevice: nameToGiveToCurrentDevice)
        
        // Re-register all active owned identities to push notifications
        ObvEngineNotificationNew.serverRequiresAllActiveOwnedIdentitiesToRegisterToPushNotifications
            .postOnBackgroundQueue(within: appNotificationCenter)

        // Perform a re-download of all group v2
        try performReDownloadOfAllGroupV2AfterBackupRestore(backupRequestIdentifier: backupRequestIdentifier)
        
        // Since the notifications from the identity manager are not triggered during a backup restore,
        // we call the appropriate method from the engine coordinator now
        
        for ownedCryptoIdentity in restoredOwnedIdentities {
            engineCoordinator.processNewActiveOwnedIdentity(ownedCryptoIdentity: ownedCryptoIdentity, flowId: backupRequestIdentifier)
        }
        
        return Set(restoredOwnedIdentities.map({ ObvCryptoId(cryptoIdentity: $0) }))
        
    }
    
    
    /// Helper method used during a backup restore
    private func getOwnedIdentities() async throws -> Set<ObvCryptoIdentity> {
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: FlowIdentifier()) { obvContext in
                    let ownedCryptoIds = try identityDelegate.getOwnedIdentities(within: obvContext)
                    continuation.resume(returning: ownedCryptoIds)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    
    private func setCurrentDeviceNameOfAllRestoredOwnedIdentitiesAfterBackupRestore(restoredOwnedIdentities: Set<ObvCryptoIdentity>, nameToGiveToCurrentDevice: String) throws {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }

        let log = self.log
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: FlowIdentifier()) { obvContext in
            
            // We set the device names locally for all restored owned identities (active or not)
            for restoredOwnedIdentity in restoredOwnedIdentities {
                try identityDelegate.setCurrentDeviceNameOfOwnedIdentityAfterBackupRestore(ownedCryptoIdentity: restoredOwnedIdentity, nameForCurrentDevice: nameToGiveToCurrentDevice, within: obvContext)
            }
            
            try obvContext.save(logOnFailure: log)
        }
        
    }
    
    
    private func performReDownloadOfAllGroupV2AfterBackupRestore(backupRequestIdentifier: FlowIdentifier) throws {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }

        var allGroupsV2 = [ObvCryptoIdentity: Set<ObvGroupV2>]()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: backupRequestIdentifier) { obvContext in
            let allOwnedIdentities = try identityDelegate.getOwnedIdentities(within: obvContext)
            for identity in allOwnedIdentities {
                allGroupsV2[identity] = try identityDelegate.getAllObvGroupV2(of: identity, within: obvContext)
                    .filter { obvGroupV2 in
                        !obvGroupV2.keycloakManaged // We restrict to non-keycloak groups
                    }
            }
        }
        
        for (ownedIdentiy, groupsV2) in allGroupsV2 {
            for groupV2 in groupsV2 {
                try performReDownloadOfGroupV2(ownedCryptoId: ObvCryptoId(cryptoIdentity: ownedIdentiy), groupIdentifier: groupV2.appGroupIdentifier)
            }
        }
        
    }
    
    
    public func registerAppBackupableObject(_ appBackupableObject: ObvBackupable) throws {
        guard let backupDelegate = self.backupDelegate else {
            os_log("The backup delegate is not set", log: log, type: .fault)
            assertionFailure()
            throw ObvError.backupDelegateIsNil
        }
        backupDelegate.registerAppBackupableObject(appBackupableObject)
    }
    
    
    public func registerAppSnapshotableObject(_ appSnapshotableObject: ObvAppSnapshotable) throws {
        guard let syncSnapshotDelegate else {
            os_log("The backup delegate is not set", log: log, type: .fault)
            assertionFailure()
            throw ObvError.syncSnapshotDelegateIsNil
        }
        syncSnapshotDelegate.registerAppSnapshotableObject(appSnapshotableObject)
    }

}


// MARK: - Public API for User Data

extension ObvEngine {

    /// This is called when restoring a backup and after the migration to the first Olvid version that supports profile pictures
    public func downloadAllUserData() throws {
        
        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }

        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()

        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
            
            do {
                let items = try identityDelegate.getAllOwnedIdentityWithMissingPhotoUrl(within: obvContext)
                for (ownedIdentity, details) in items {
                    try startDownloadIdentityPhotoProtocolWithinTransaction(within: obvContext, ownedIdentity: ownedIdentity, contactIdentity: ownedIdentity, contactIdentityDetailsElements: details)
                }
            }
            
            do {
                let items = try identityDelegate.getAllContactsWithMissingPhotoUrl(within: obvContext)
                for (ownedIdentity, contactIdentity, details) in items {
                    try startDownloadIdentityPhotoProtocolWithinTransaction(within: obvContext, ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, contactIdentityDetailsElements: details)
                }
            }

            do {
                let items = try identityDelegate.getAllGroupsWithMissingPhotoUrl(within: obvContext)
                for (ownedIdentity, groupInformation) in items {
                    try startDownloadGroupPhotoProtocolWithinTransaction(within: obvContext, ownedIdentity: ownedIdentity, groupInformation: groupInformation)
                }
            }

            do {
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Could not download user data", log: log, type: .fault)
                assertionFailure()
                throw error
            }

        }
        
    }
    

    public func startDownloadIdentityPhotoProtocolWithinTransaction(within obvContext: ObvContext, ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, contactIdentityDetailsElements: IdentityDetailsElements) throws {
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        let message = try protocolDelegate.getInitialMessageForDownloadIdentityPhotoChildProtocol(ownedIdentity: ownedIdentity,
                                                                                                  contactIdentity: contactIdentity,
                                                                                                  contactIdentityDetailsElements: contactIdentityDetailsElements)
        _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
    }

    
    public func startDownloadGroupPhotoProtocolWithinTransaction(within obvContext: ObvContext, ownedIdentity: ObvCryptoIdentity, groupInformation: GroupInformation) throws {
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        let message = try protocolDelegate.getInitialMessageForDownloadGroupPhotoChildProtocol(ownedIdentity: ownedIdentity, groupInformation: groupInformation)
        _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
    }

}


// MARK: - Public API for Webrtc

extension ObvEngine {
    
    public func getTurnCredentials(ownedCryptoId: ObvCryptoId) async throws -> ObvTurnCredentials {
        guard let networkFetchDelegate else { assertionFailure(); throw ObvError.networkFetchDelegateIsNil }
        let flowId = FlowIdentifier()
        return try await networkFetchDelegate.getTurnCredentials(ownedCryptoId: ownedCryptoId.cryptoIdentity, flowId: flowId)
    }
    
}


// MARK: - Misc

extension ObvEngine {
    
    public func getServerAPIVersion() -> Int {
        return ObvServerInterfaceConstants.serverAPIVersion
    }
    
    
    public func computeTagForOwnedIdentity(with ownedIdentityCryptoId: ObvCryptoId, on data: Data) throws -> Data {
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        var _tag: Data?
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: FlowIdentifier()) { (obvContext) in
            _tag = try identityDelegate.computeTagForOwnedIdentity(ownedIdentityCryptoId.cryptoIdentity, on: data, within: obvContext)
        }
        guard let tag = _tag else {
            throw makeError(message: "The _tag variable is not set although it should be. This is a bug.")
        }
        return tag
    }
    
}



// Used to avoid "Expression implicitly coerced from 'T?' to Any" issue
public struct EngineOptionalWrapper<T> {
    public let value: T?

    public init() {
        self.value = nil
    }

    public init(_ value: T?) {
        self.value = value
    }
}



// MARK: - ObvUserInterfaceChannelDelegate

extension ObvEngine: ObvUserInterfaceChannelDelegate {
 
    /// This method gets called when the Channel Manager notifies that a new user dialog is about to be ready to be presented to the user.
    /// Within this method, we save a similar notification within the `PersistedEngineDialog` database.
    /// This database is in charge of sending a notification to the App.
    public func newUserDialogToPresent(obvChannelDialogMessageToSend: ObvChannelDialogMessageToSend, within obvContext: ObvContext) throws {
        
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        
        let obvDialog: ObvDialog
        do {
            
            switch obvChannelDialogMessageToSend.channelType {
            case .UserInterface(uuid: let uuid, ownedIdentity: let ownedCryptoIdentity, dialogType: let obvChannelDialogToSendType):
                
                // Construct an ObvOwnedIdentity
                
                let ownedIdentity: ObvOwnedIdentity
                do {
                    let _ownedIdentity = ObvOwnedIdentity(ownedCryptoIdentity: ownedCryptoIdentity, identityDelegate: identityDelegate, within: obvContext)
                    guard _ownedIdentity != nil else {
                        os_log("Could not get the owned identity", log: log, type: .fault)
                        return
                    }
                    ownedIdentity = _ownedIdentity!
                }
                
                // Construct the dialog category
                
                let category: ObvDialog.Category
                do {
                    switch obvChannelDialogToSendType {
                    
                    case .inviteSent(contact: let contact):
                        let urlIdentity = ObvURLIdentity(cryptoIdentity: contact.cryptoIdentity, fullDisplayName: contact.fullDisplayName)
                        category = ObvDialog.Category.inviteSent(contactIdentity: urlIdentity)
                    
                    case .acceptInvite(contact: let contact):
                        let obvContactIdentity = ObvGenericIdentity(cryptoIdentity: contact.cryptoIdentity, currentCoreIdentityDetails: contact.coreDetails)
                        category = ObvDialog.Category.acceptInvite(contactIdentity: obvContactIdentity)
                    
                    case .invitationAccepted(contact: let contact):
                        let obvContactIdentity = ObvGenericIdentity(cryptoIdentity: contact.cryptoIdentity, currentCoreIdentityDetails: contact.coreDetails)
                        category = ObvDialog.Category.invitationAccepted(contactIdentity: obvContactIdentity)
                    
                    case .sasExchange(contact: let contact, sasToDisplay: let sasToDisplay, numberOfBadEnteredSas: let numberOfBadEnteredSas):
                        let obvContactIdentity = ObvGenericIdentity(cryptoIdentity: contact.cryptoIdentity, currentCoreIdentityDetails: contact.coreDetails)
                        category = ObvDialog.Category.sasExchange(contactIdentity: obvContactIdentity, sasToDisplay: sasToDisplay, numberOfBadEnteredSas: numberOfBadEnteredSas)
                    
                    case .sasConfirmed(contact: let contact, sasToDisplay: let sasToDisplay, sasEntered: let sasEntered):
                        let obvContactIdentity = ObvGenericIdentity(cryptoIdentity: contact.cryptoIdentity, currentCoreIdentityDetails: contact.coreDetails)
                        category = ObvDialog.Category.sasConfirmed(contactIdentity: obvContactIdentity, sasToDisplay: sasToDisplay, sasEntered: sasEntered)
                    
                    case .mutualTrustConfirmed(contact: let contact):
                        let obvContactIdentity = ObvGenericIdentity(cryptoIdentity: contact.cryptoIdentity, currentCoreIdentityDetails: contact.coreDetails)
                        category = ObvDialog.Category.mutualTrustConfirmed(contactIdentity: obvContactIdentity)
                    
                    case .acceptMediatorInvite(contact: let contact, mediatorIdentity: let mediatorIdentity):
                        let obvContactIdentity = ObvGenericIdentity(cryptoIdentity: contact.cryptoIdentity, currentCoreIdentityDetails: contact.coreDetails)
                        guard let obvMediatorIdentity = ObvContactIdentity(contactCryptoIdentity: mediatorIdentity, ownedCryptoIdentity: ownedCryptoIdentity, identityDelegate: identityDelegate, within: obvContext) else { return }
                        category = ObvDialog.Category.acceptMediatorInvite(contactIdentity: obvContactIdentity, mediatorIdentity: obvMediatorIdentity.getGenericIdentity())
                        
                    case .mediatorInviteAccepted(contact: let contact, mediatorIdentity: let mediatorIdentity):
                        let obvContactIdentity = ObvGenericIdentity(cryptoIdentity: contact.cryptoIdentity, currentCoreIdentityDetails: contact.coreDetails)
                        guard let obvMediatorIdentity = ObvContactIdentity(contactCryptoIdentity: mediatorIdentity, ownedCryptoIdentity: ownedCryptoIdentity, identityDelegate: identityDelegate, within: obvContext) else { return }
                        category = ObvDialog.Category.mediatorInviteAccepted(contactIdentity: obvContactIdentity, mediatorIdentity: obvMediatorIdentity.getGenericIdentity())
                    
                    case .acceptGroupInvite(groupInformation: let groupInformation, pendingGroupMembers: let pendingMembers, receivedMessageTimestamp: _):
                        let obvGroupMembers: Set<ObvGenericIdentity> = Set(pendingMembers.map {
                            let obvIdentity = ObvGenericIdentity(cryptoIdentity: $0.cryptoIdentity, currentCoreIdentityDetails: $0.coreDetails)
                            return obvIdentity
                        })
                        let groupOwner: ObvGenericIdentity
                        if groupInformation.groupOwnerIdentity == ownedCryptoIdentity {
                            guard let _groupOwner = ObvOwnedIdentity(ownedCryptoIdentity: groupInformation.groupOwnerIdentity, identityDelegate: identityDelegate, within: obvContext) else { return }
                            groupOwner = _groupOwner.getGenericIdentity()
                        } else {
                            guard let _groupOwner = ObvContactIdentity.init(contactCryptoIdentity: groupInformation.groupOwnerIdentity, ownedCryptoIdentity: ownedCryptoIdentity, identityDelegate: identityDelegate, within: obvContext) else { return }
                            groupOwner = _groupOwner.getGenericIdentity()
                        }
                        category = ObvDialog.Category.acceptGroupInvite(groupMembers: obvGroupMembers, groupOwner: groupOwner)
                        
                    case .oneToOneInvitationSent(contact: let contact, ownedIdentity: let ownedIdentity):
                        guard let obvContact = ObvContactIdentity(contactCryptoIdentity: contact, ownedCryptoIdentity: ownedIdentity, identityDelegate: identityDelegate, within: obvContext) else {
                            assertionFailure()
                            return
                        }
                        category = ObvDialog.Category.oneToOneInvitationSent(contactIdentity: obvContact.getGenericIdentity())
                        
                    case .oneToOneInvitationReceived(contact: let contact, ownedIdentity: let ownedIdentity):
                        guard let obvContact = ObvContactIdentity(contactCryptoIdentity: contact, ownedCryptoIdentity: ownedIdentity, identityDelegate: identityDelegate, within: obvContext) else {
                            assertionFailure()
                            return
                        }
                        category = ObvDialog.Category.oneToOneInvitationReceived(contactIdentity: obvContact.getGenericIdentity())
                    
                    case .acceptGroupV2Invite(inviter: let inviter, group: let group):
                        category = ObvDialog.Category.acceptGroupV2Invite(inviter: inviter, group: group)
                        
                    case .freezeGroupV2Invite(inviter: let inviter, group: let group):
                        category = ObvDialog.Category.freezeGroupV2Invite(inviter: inviter, group: group)
                        
                    case .syncRequestReceivedFromOtherOwnedDevice(otherOwnedDeviceUID: let otherOwnedDeviceUID, syncAtom: let syncAtom):
                        category = ObvDialog.Category.syncRequestReceivedFromOtherOwnedDevice(otherOwnedDeviceIdentifier: otherOwnedDeviceUID.raw, syncAtom: syncAtom)

                    case .delete:
                        // This is a special case: we simply delete any existing realated PersistedEngineDialog and return
                        try PersistedEngineDialog.deletePersistedDialog(uid: uuid, appNotificationCenter: appNotificationCenter, within: obvContext)
                        return
                    }
                    
                    
                }
                
                // Construct the dialog
                
                obvDialog = ObvDialog(uuid: uuid,
                                      encodedElements: obvChannelDialogMessageToSend.encodedElements,
                                      ownedCryptoId: ownedIdentity.cryptoId,
                                      category: category)
            default:
                return
            }
        }
        
        // We have a dialog to present to the user, we persist it in the `PersistedEngineDialog` database. If another `PersistedEngineDialog` exist with the same UUID, it is part of the same protocol and we simply update this instance.
        if let previousDialog = try PersistedEngineDialog.get(uid: obvDialog.uuid, appNotificationCenter: appNotificationCenter, within: obvContext) {
            do {
                try previousDialog.update(with: obvDialog)
            } catch {
                os_log("Could not update PersistedEngineDialog with the new ObvDialog", log: log, type: .fault)
                obvContext.delete(previousDialog)
                _ = PersistedEngineDialog(with: obvDialog, appNotificationCenter: appNotificationCenter, within: obvContext)
            }
        } else {
            _ = PersistedEngineDialog(with: obvDialog, appNotificationCenter: appNotificationCenter, within: obvContext)
        }

    }
    
}


// MARK: - Transfer protocol / Adding a new owned device

extension ObvEngine {
    
    /// Called by the app in order to start an owned identity transfer protocol on the source device.
    /// - Parameters:
    ///   - ownedCryptoId: The `ObvCryptoId` of the owned identity.
    ///   - onAvailableSessionNumber: This block will be called by the engine as soon as the session number is available, passing it as a parameter. Since getting this session number requires a network interaction with the transfer server, this block may take a "long" time before being called.
    public func initiateOwnedIdentityTransferProtocolOnSourceDevice(ownedCryptoId: ObvCryptoId, onAvailableSessionNumber: @escaping (ObvOwnedIdentityTransferSessionNumber) -> Void, onAvailableSASExpectedOnInput: @escaping (ObvOwnedIdentityTransferSas, String, UID) -> Void) async throws {

        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }

        let ownedCryptoIdentity = ownedCryptoId.cryptoIdentity
        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()

        try await protocolDelegate.initiateOwnedIdentityTransferProtocolOnSourceDevice(
            ownedCryptoIdentity: ownedCryptoIdentity,
            onAvailableSessionNumber: onAvailableSessionNumber,
            onAvailableSASExpectedOnInput: onAvailableSASExpectedOnInput,
            flowId: flowId)
                
    }

    
    public func initiateOwnedIdentityTransferProtocolOnTargetDevice(currentDeviceName: String, transferSessionNumber: ObvOwnedIdentityTransferSessionNumber, onIncorrectTransferSessionNumber: @escaping () -> Void, onAvailableSas: @escaping (UID, ObvOwnedIdentityTransferSas) -> Void) async throws {
        
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }

        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()

        try await protocolDelegate.initiateOwnedIdentityTransferProtocolOnTargetDevice(currentDeviceName: currentDeviceName, transferSessionNumber: transferSessionNumber, onIncorrectTransferSessionNumber: onIncorrectTransferSessionNumber, onAvailableSas: onAvailableSas, flowId: flowId)

    }
    
    
    public func appIsShowingSasAndExpectingEndOfProtocol(protocolInstanceUID: UID, onSyncSnapshotReception: @escaping () -> Void, onSuccessfulTransfer: @escaping (ObvCryptoId, Error?) -> Void) async {
        guard let protocolDelegate else { assertionFailure(); return }
        await protocolDelegate.appIsShowingSasAndExpectingEndOfProtocol(
            protocolInstanceUID: protocolInstanceUID,
            onSyncSnapshotReception: onSyncSnapshotReception,
            onSuccessfulTransfer: onSuccessfulTransfer)
    }
    
    
    /// Called by the app during an owned identity transfer protocol on the source device, after the user entered a valid SAS.
    public func userEnteredValidSASOnSourceDeviceForOwnedIdentityTransferProtocol(enteredSAS: ObvOwnedIdentityTransferSas, deviceToKeepActive: UID?, ownedCryptoId: ObvCryptoId, protocolInstanceUID: UID, snapshotSentToTargetDevice: @escaping () -> Void) async throws {
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        try await protocolDelegate.continueOwnedIdentityTransferProtocolOnUserEnteredSASOnSourceDevice(
            enteredSAS: enteredSAS,
            deviceToKeepActive: deviceToKeepActive,
            ownedCryptoId: ownedCryptoId,
            protocolInstanceUID: protocolInstanceUID,
            snapshotSentToTargetDevice: snapshotSentToTargetDevice)
    }
    
    
    public func userWantsToCancelAllOwnedIdentityTransferProtocols() async throws {
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        let flowId = FlowIdentifier()
        try await protocolDelegate.cancelAllOwnedIdentityTransferProtocols(flowId: flowId)
    }
    
}


// MARK: - Sync between owned devices

extension ObvEngine {
    
    
    /// Called by the app when, e.g., the user performs a modification that should be transferred to other owned devices.
    /// - Parameters:
    ///   - syncAtom: The ObvSyncAtom created by the app that the engine should transfer to all other owned devices.
    ///   - ownedCryptoId: The owned identity making the change.
    public func requestPropagationToOtherOwnedDevices(of syncAtom: ObvSyncAtom, for ownedCryptoId: ObvCryptoId) async throws {
        
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
        guard let flowDelegate else { throw ObvError.flowDelegateIsNil }

        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()

        let message = try protocolDelegate.getInitiateSyncAtomMessageForSynchronizationProtocol(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, syncAtom: syncAtom)
        try await postChannelMessage(message, flowId: flowId)
        
    }
    
    
    private func postChannelMessage(_ message: ObvChannelProtocolMessageToSend, flowId: FlowIdentifier) async throws {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        
        let prng = self.prng
        let log = self.log

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                    try obvContext.save(logOnFailure: log)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

    }
    
    
    /// Each time we start the app, we send a trigger message to all existing synchronization protocol instances. This allows to make sure they properly resend any diff to the app, which is important as they are kept in memory.
//    private func sendTriggerSyncSnapshotMessageToAllExistingSynchronizationProtocolInstances(flowId: FlowIdentifier) async throws {
//
//        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
//        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
//
//        let log = self.log
//
//        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
//            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
//                do {
//                    try protocolDelegate.sendTriggerSyncSnapshotMessageToAllExistingSynchronizationProtocolInstances(within: obvContext)
//                    try obvContext.save(logOnFailure: log)
//                    continuation.resume()
//                } catch {
//                    continuation.resume(throwing: error)
//                }
//            }
//        }
//
//    }
    
    
    /// Each time we start the app, we look for other owned devices and make sure there is an oingoing SynchronizationProtocol between the current device and each of these remote devices.
    /// To do so, we send an InitiateSyncSnapshotMessage for each found other owned device. In case a protocol instance already exists (which is very likely), this message will simply be discarded by the protocol.
//    private func initiateIfRequiredSynchronizationProtocolInstanceForEachChannelWithAnotherOwnedDevice(flowId: FlowIdentifier) async throws {
//        
//        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
//        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
//        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
//        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
//        
//        let log = self.log
//        let prng = self.prng
//        
//        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
//            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
//                do {
//                    let ownedIdentities = try identityDelegate.getOwnedIdentities(within: obvContext)
//                    for ownedIdentity in ownedIdentities {
//                        let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
//                        let otherOwnedDeviceUids = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext)
//                        for otherOwnedDeviceUid in otherOwnedDeviceUids {
//                            let message = try protocolDelegate.getInitiateSyncSnapshotMessageForSynchronizationProtocol(ownedCryptoIdentity: ownedIdentity, currentDeviceUid: currentDeviceUid, otherOwnedDeviceUid: otherOwnedDeviceUid)
//                            _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
//                        }
//                    }
//                    if obvContext.context.hasChanges {
//                        try obvContext.save(logOnFailure: log)
//                    }
//                    continuation.resume()
//                } catch {
//                    continuation.resume(throwing: error)
//                }
//            }
//        }
//        
//    }

    
//    public func appRequestsTriggerOwnedDeviceSync(ownedCryptoId: ObvCryptoId) async throws {
//        
//        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
//        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }
//        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
//        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
//
//        let log = self.log
//        let prng = self.prng
//        let flowId = FlowIdentifier()
//
//        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
//            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
//                do {
//                    let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedCryptoId.cryptoIdentity, within: obvContext)
//                    let otherOwnedDeviceUids = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedCryptoId.cryptoIdentity, within: obvContext)
//                    for otherOwnedDeviceUid in otherOwnedDeviceUids {
//                        let message = try protocolDelegate.getTriggerSyncSnapshotMessageForSynchronizationProtocol(
//                            ownedCryptoIdentity: ownedCryptoId.cryptoIdentity,
//                            currentDeviceUid: currentDeviceUid,
//                            otherOwnedDeviceUid: otherOwnedDeviceUid,
//                            forceSendSnapshot: true)
//                        _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
//                    }
//                    if obvContext.context.hasChanges {
//                        try obvContext.save(logOnFailure: log)
//                    }
//                    continuation.resume()
//                } catch {
//                    continuation.resume(throwing: error)
//                }
//            }
//        }
//
//    }
    
}


// Re-downloading profile pictures

extension ObvEngine {
    
    /// This method allows the user to request the (re)download of potentially missing photos for owned identities.
    public func downloadMissingProfilePicturesForOwnedIdentities() async throws {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }

        let flowId = FlowIdentifier()
        let prng = self.prng
        let log = self.log

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
                do {

                    let infos = try identityDelegate.getInformationsAboutOwnedIdentitiesWithMissingPictureOnDisk(within: obvContext)

                    for info in infos {
                        
                        let message = try protocolDelegate.getInitialMessageForDownloadIdentityPhotoChildProtocol(
                            ownedIdentity: info.ownedCryptoId,
                            contactIdentity: info.ownedCryptoId,
                            contactIdentityDetailsElements: info.ownedIdentityDetailsElements)
                        _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)

                    }

                    try obvContext.save(logOnFailure: log)
                    
                    continuation.resume()
                    
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

    }
    
    
    /// This method allows the user to request the (re)download of potentially missing photos for contact groups v2.
    public func downloadMissingProfilePicturesForGroupsV2() async throws {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }

        let flowId = FlowIdentifier()
        let prng = self.prng
        let log = self.log

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
                do {

                    let infos = try identityDelegate.getInformationsAboutGroupsV2WithMissingContactPictureOnDisk(within: obvContext)

                    for info in infos {
                        
                        let message = try protocolDelegate.getInitialMessageForDownloadGroupV2PhotoProtocol(
                            ownedIdentity: info.ownedIdentity,
                            groupIdentifier: info.groupIdentifier,
                            serverPhotoInfo: info.serverPhotoInfo)
                        _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)

                    }

                    try obvContext.save(logOnFailure: log)
                    
                    continuation.resume()
                    
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

    }
    
    
    /// This method allows the user to request the (re)download of potentially missing photos for contact groups v1.
    public func downloadMissingProfilePicturesForGroupsV1() async throws {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }

        let flowId = FlowIdentifier()
        let prng = self.prng
        let log = self.log

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
                do {

                    let infos = try identityDelegate.getInformationsAboutGroupsV1WithMissingContactPictureOnDisk(within: obvContext)

                    for info in infos {
                        
                        let message = try protocolDelegate.getInitialMessageForDownloadGroupPhotoChildProtocol(
                            ownedIdentity: info.ownedIdentity,
                            groupInformation: info.groupInfo)
                        _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)

                    }

                    try obvContext.save(logOnFailure: log)
                    
                    continuation.resume()
                    
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

    }
    
    /// This method allows the user to request the (re)download of potentially missing photos for her contacts.
    public func downloadMissingProfilePicturesForContacts() async throws {
        
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { throw ObvError.identityDelegateIsNil }
        guard let channelDelegate else { throw ObvError.channelDelegateIsNil }
        guard let protocolDelegate else { throw ObvError.protocolDelegateIsNil }

        let flowId = FlowIdentifier()
        let prng = self.prng
        let log = self.log
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    
                    let infos = try identityDelegate.getInformationsAboutContactsWithMissingContactPictureOnDisk(within: obvContext)

                    for info in infos {
                        
                        let message = try protocolDelegate.getInitialMessageForDownloadIdentityPhotoChildProtocol(
                            ownedIdentity: info.ownedCryptoId,
                            contactIdentity: info.contactCryptoId,
                            contactIdentityDetailsElements: info.contactIdentityDetailsElements)
                        _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)

                    }
                    
                    try obvContext.save(logOnFailure: log)
                    
                    continuation.resume()
                    
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
    }
    
}


// MARK: - Errors

extension ObvEngine {
    
    enum ObvError: LocalizedError {
        
        case createContextDelegateIsNil
        case protocolDelegateIsNil
        case flowDelegateIsNil
        case notificationDelegateIsNil
        case channelDelegateIsNil
        case identityDelegateIsNil
        case backupDelegateIsNil
        case syncSnapshotDelegateIsNil
        case networkFetchDelegateIsNil
        case ownedIdentityIsNotActive
        case ownedIdentityIsKeycloakManaged
        case ownedIdentityIsNotKeycloakManaged
        case couldNotRegisterAPIKeyAsItIsInvalid
        case couldNotRegisterAPIKey
        case noAppropriateOwnedIdentityFound
        case couldNotParseMessageIdentifier

        var errorDescription: String? {
            switch self {
            case .createContextDelegateIsNil:
                return "Create context delegate is nil"
            case .protocolDelegateIsNil:
                return "Protocol delegate is nil"
            case .flowDelegateIsNil:
                return "Flow delegate is nil"
            case .channelDelegateIsNil:
                return "Channel delegate is nil"
            case .identityDelegateIsNil:
                return "Identity delegate is nil"
            case .backupDelegateIsNil:
                return "Backup delegate is nil"
            case .networkFetchDelegateIsNil:
                return "Network fetch delegate is nil"
            case .ownedIdentityIsNotActive:
                return "Owned identity is not active"
            case .ownedIdentityIsKeycloakManaged:
                return "Owned identity is keycloak managed"
            case .ownedIdentityIsNotKeycloakManaged:
                return "Owned identity is not keycloak managed"
            case .couldNotRegisterAPIKeyAsItIsInvalid:
                return "Could not register API key as it is invalid"
            case .couldNotRegisterAPIKey:
                return "Could not register API key"
            case .syncSnapshotDelegateIsNil:
                return "The sync snapshot delegate is nil"
            case .notificationDelegateIsNil:
                return "The notification delegate is nil"
            case .noAppropriateOwnedIdentityFound:
                return "No appropriate owned identity found"
            case .couldNotParseMessageIdentifier:
                return "Could not parse message identifier"
            }
        }
        
    }
    
}


// MARK: - Helpers for operations

extension ObvEngine {
        
    private func createCompositionOfOneContextualOperation<T: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T>) throws -> CompositionOfOneContextualOperation<T> {
        guard let createContextDelegate else { throw ObvError.createContextDelegateIsNil }
        let log = self.log
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: createContextDelegate, queueForComposedOperations: queueForComposedOperations, log: log, flowId: FlowIdentifier())
        composedOp.completionBlock = { [weak composedOp] in
            assert(composedOp != nil)
            composedOp?.logReasonIfCancelled(log: log)
        }
        return composedOp
    }

}
