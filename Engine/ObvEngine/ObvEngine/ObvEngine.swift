/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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
import OlvidUtils
import JWS


public final class ObvEngine: ObvManager {
    
    public static var mainContainerURL: URL? = nil
    
    private let delegateManager: ObvMetaManager
    private let engineCoordinator: EngineCoordinator
    private let prng: PRNGService
    let appNotificationCenter: NotificationCenter
    let returnReceiptSender: ReturnReceiptSender
    private let transactionsHistoryReplayer: TransactionsHistoryReplayer

    static let defaultLogSubsystem = "io.olvid.engine"
    public var logSubsystem: String = ObvEngine.defaultLogSubsystem
    public func prependLogSubsystem(with prefix: String) {
        logSubsystem = "\(prefix).\(logSubsystem)"
    }
    
    lazy var log = OSLog(subsystem: logSubsystem, category: "ObvEngine")
    
    var notificationCenterTokens = [NSObjectProtocol]()
    
    let dispatchQueueForPushNotificationRegistration = DispatchQueue(label: "dispatchQueueForPushNotificationRegistration")
    
    // We define a special queue for posting newObvReturnReceiptToProcess notifications to fix a bug occurring when a lot of return receipts are received at once.
    // In that case, creating one thread per receipt can lead to a complete hang of Olvid. Using one fixed thread (together with a fix made at the App level) should prevent the bug.
    let queueForPostingNewObvReturnReceiptToProcessNotifications = DispatchQueue(label: "Queue for posting a newObvReturnReceiptToProcess notification")
    
    let queueForPostingNotificationsToTheApp = DispatchQueue(label: "Queue for posting notifications to the app")
    
    let queueForPerformingBootstrapMethods = DispatchQueue(label: "Background queue for performing the engine bootstrap methods")

    private let queueForSynchronizingCallsToManagers = DispatchQueue(label: "Queue for synchronizing calls to managers")
    
    // MARK: - Public factory methods
    
    public static func startFull(logPrefix: String, appNotificationCenter: NotificationCenter, uiApplication: UIApplication, sharedContainerIdentifier: String, supportBackgroundTasks: Bool, appType: AppType, runningLog: RunningLogError) throws -> ObvEngine {
        
        // The main container URL is shared between all the apps within the app group (i.e., between the main app, the share extension, and the notification extension).
        guard let mainContainerURL = ObvEngine.mainContainerURL else { throw makeError(message: "The main container URL is not set") }
        
        let prng = ObvCryptoSuite.sharedInstance.prngService()
        
        guard let inbox = ObvEngine.createAndConfigureBox("inbox", mainContainerURL: mainContainerURL) else { throw makeError(message: "Could not create and configure inbox") }
        guard let outbox = ObvEngine.createAndConfigureBox("outbox", mainContainerURL: mainContainerURL) else { throw makeError(message: "Could not create and configure outbox") }
        guard let database = ObvEngine.createAndConfigureBox("database", mainContainerURL: mainContainerURL) else { throw makeError(message: "Could not create and configure the database box") }
        guard let identityPhotos = ObvEngine.createAndConfigureBox("identityPhotos", mainContainerURL: mainContainerURL) else { throw makeError(message: "Could not create and configure the identityPhotos box") }
        guard let downloadedUserData = ObvEngine.createAndConfigureBox("downloadedUserData", mainContainerURL: mainContainerURL) else { throw makeError(message: "Could not create and configure the downloadedUserData box") }

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
                                                                remoteNotificationByteIdentifierForServer: ObvEngineConstants.remoteNotificationByteIdentifierForServer))
        
        // ObvSolveChallengeDelegate, ObvKeyWrapperForIdentityDelegate, ObvIdentityDelegate, ObvKemForIdentityDelegate
        obvManagers.append(ObvIdentityManagerImplementation(sharedContainerIdentifier: sharedContainerIdentifier, prng: prng, identityPhotosDirectory: identityPhotos))
        
        // ObvProcessDownloadedMessageDelegate, ObvChannelDelegate
        obvManagers.append(ObvChannelManagerImplementation(readOnly: false))
        
        // ObvProtocolDelegate, ObvFullRatchetProtocolStarterDelegate
        obvManagers.append(ObvProtocolManager(prng: prng, downloadedUserData: downloadedUserData))
        
        // ObvNotificationDelegate
        obvManagers.append(ObvNotificationCenter())
        
        // ObvFlowDelegate
        obvManagers.append(ObvFlowManager(uiApplication: uiApplication, prng: prng))
        
        let fullEngine = try self.init(logPrefix: logPrefix, sharedContainerIdentifier: sharedContainerIdentifier, obvManagers: obvManagers, appNotificationCenter: appNotificationCenter, appType: appType, runningLog: runningLog)

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
        obvManagers.append(ObvChannelManagerImplementation(readOnly: false))

        // ObvProtocolDelegate, ObvFullRatchetProtocolStarterDelegate
        obvManagers.append(ObvProtocolManagerDummy())

        // ObvNotificationDelegate
        obvManagers.append(ObvNotificationCenter())

        // ObvFlowDelegate
        obvManagers.append(ObvFlowManager(prng: prng))

        let dummyNotificationCenter = NotificationCenter.init()

        return try self.init(logPrefix: logPrefix, sharedContainerIdentifier: sharedContainerIdentifier, obvManagers: obvManagers, appNotificationCenter: dummyNotificationCenter, appType: appType, runningLog: runningLog)


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
        obvManagers.append(ObvChannelManagerImplementation(readOnly: true))
        
        // ObvProtocolDelegate, ObvFullRatchetProtocolStarterDelegate
        obvManagers.append(ObvProtocolManagerDummy())
        
        // ObvNotificationDelegate
        obvManagers.append(ObvNotificationCenterDummy())
        
        // ObvFlowDelegate
        obvManagers.append(ObvFlowManager(prng: prng))
        
        let dummyNotificationCenter = NotificationCenter.init()
        
        return try self.init(logPrefix: logPrefix, sharedContainerIdentifier: sharedContainerIdentifier, obvManagers: obvManagers, appNotificationCenter: dummyNotificationCenter, appType: appType, runningLog: runningLog)

        
    }
    
    // MARK: - Initializer
    
    init(logPrefix: String, sharedContainerIdentifier: String, obvManagers: [ObvManager], appNotificationCenter: NotificationCenter, appType: AppType, runningLog: RunningLogError) throws {
        
        self.prng = ObvCryptoSuite.sharedInstance.prngService()
        self.appNotificationCenter = appNotificationCenter
        self.returnReceiptSender = ReturnReceiptSender(sharedContainerIdentifier: sharedContainerIdentifier, prng: prng)
        self.transactionsHistoryReplayer = TransactionsHistoryReplayer(sharedContainerIdentifier: sharedContainerIdentifier, appType: appType)
        self.engineCoordinator = EngineCoordinator(logSubsystem: logSubsystem, prng: self.prng, appNotificationCenter: appNotificationCenter)
        delegateManager = ObvMetaManager()

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
        }
        return delegateManager.createContextDelegate
    }

    var identityDelegate: ObvIdentityDelegate? {
        if delegateManager.identityDelegate == nil {
            os_log("The identity delegate is not set", log: log, type: .fault)
        }
        return delegateManager.identityDelegate
    }
    
    var solveChallengeDelegate: ObvSolveChallengeDelegate? {
        if delegateManager.solveChallengeDelegate == nil {
            os_log("The solve challenge delegate is not set", log: log, type: .fault)
        }
        return delegateManager.solveChallengeDelegate
    }

    var notificationDelegate: ObvNotificationDelegate? {
        if delegateManager.notificationDelegate == nil {
            os_log("The notification delegate is not set", log: log, type: .fault)
        }
        return delegateManager.notificationDelegate
    }
    
    var channelDelegate: ObvChannelDelegate? {
        if delegateManager.channelDelegate == nil {
            os_log("The channel delegate is not set", log: log, type: .fault)
        }
        return delegateManager.channelDelegate
    }
    
    var protocolDelegate: ObvProtocolDelegate? {
        if delegateManager.protocolDelegate == nil {
            os_log("The protocol delegate is not set", log: log, type: .fault)
        }
        return delegateManager.protocolDelegate
    }
    
    var networkFetchDelegate: ObvNetworkFetchDelegate? {
        if delegateManager.networkFetchDelegate == nil {
            os_log("The network fetch delegate is not set", log: log, type: .fault)
        }
        return delegateManager.networkFetchDelegate
    }
    
    var networkPostDelegate: ObvNetworkPostDelegate? {
        if delegateManager.networkPostDelegate == nil {
            os_log("The network post delegate is not set", log: log, type: .fault)
        }
        return delegateManager.networkPostDelegate
    }

    var flowDelegate: ObvFlowDelegate? {
        if delegateManager.flowDelegate == nil {
            os_log("The flow delegate is not set", log: log, type: .fault)
        }
        return delegateManager.flowDelegate
    }

    var backupDelegate: ObvBackupDelegate? {
        if delegateManager.backupDelegate == nil {
            os_log("The backup delegate is not set", log: log, type: .fault)
        }
        return delegateManager.backupDelegate
    }
}

// MARK: - Public API for managing the database

extension ObvEngine {

    private static let errorDomain = "ObvEngine"
    
    private static func makeError(message: String) -> Error { NSError(domain: errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { Self.makeError(message: message) }
    
    public func replayTransactionsHistory() {
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
    
    
    public func deleteHistoryConcerningTheAcknowledgementOfOutboxMessages(_ arg: [(messageIdentifierFromEngine: Data, ownedIdentity: ObvCryptoId)]) {
        guard let networkPostDelegate = networkPostDelegate else { assertionFailure(); return  }
        let flowId = FlowIdentifier()
        let messageIdentifiers = arg.compactMap { MessageIdentifier(rawOwnedCryptoIdentity: $0.ownedIdentity.cryptoIdentity.getIdentity(), rawUid: $0.messageIdentifierFromEngine) }
        guard !messageIdentifiers.isEmpty else { return }
        networkPostDelegate.deleteHistoryConcerningTheAcknowledgementOfOutboxMessages(messageIdentifiers: messageIdentifiers, flowId: flowId)
    }
    
}

// MARK: - Public API for managing Owned Identities

extension ObvEngine {
    
    public func getOwnedIdentity(with cryptoId: ObvCryptoId) throws -> ObvOwnedIdentity {
        
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identity delegate is not set") }

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
        
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identity delegate is not set") }
        
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
    
    
    public func generateOwnedIdentity(withApiKey apiKey: UUID, onServerURL serverURL: URL, with identityDetails: ObvIdentityDetails, keycloakState: ObvKeycloakState?, completion: @escaping (Result<ObvCryptoId,Error>) -> Void) throws {
        
        // At this point, we should not pass signed details to the identity manager.
        assert(identityDetails.coreDetails.signedUserDetails == nil)
        
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identity delegate is not set") }

        let flowId = FlowIdentifier()

        var _ownedCryptoIdentity: ObvCryptoIdentity? = nil
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
            guard let ownedCryptoIdentity = identityDelegate.generateOwnedIdentity(withApiKey: apiKey, onServerURL: serverURL, with: identityDetails, keycloakState: keycloakState, using: prng, within: obvContext) else {
                throw makeError(message: "Could not generate owned identity")
            }
            let publishedIdentityDetails = try identityDelegate.getPublishedIdentityDetailsOfOwnedIdentity(ownedCryptoIdentity, within: obvContext)
            let ownedCryptoId = ObvCryptoId(cryptoIdentity: ownedCryptoIdentity)
            try startIdentityDetailsPublicationProtocol(ownedIdentity: ownedCryptoId, publishedIdentityDetailsVersion: publishedIdentityDetails.ownedIdentityDetailsElements.version, within: obvContext)

            do {
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Could not generate owned identity", log: log, type: .fault)
            }
            
            _ownedCryptoIdentity = ownedCryptoIdentity
            
        }
        guard let ownedCryptoIdentity = _ownedCryptoIdentity else { assertionFailure(); throw makeError(message: "Could not get owned identity. This is a bug.")}
        
        completion(.success(ObvCryptoId(cryptoIdentity: ownedCryptoIdentity)))

    }
    
    
    public func getApiKeyForOwnedIdentity(with ownedCryptoId: ObvCryptoId) throws -> UUID {
        
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identity delegate is not set") }
        
        let randomFlowId = FlowIdentifier()
        var apiKey: UUID!
        var error: Error?
        createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
            do {
                apiKey = try identityDelegate.getApiKeyOfOwnedIdentity(ownedCryptoId.cryptoIdentity, within: obvContext)
            } catch let _error {
                error = _error
            }
        }
        guard error == nil else {
            throw error!
        }
        return apiKey
        
    }
    
    
    public func queryAPIKeyStatus(for identity: ObvCryptoId, apiKey: UUID) {
        let randomFlowId = FlowIdentifier()
        networkFetchDelegate?.queryAPIKeyStatus(for: identity.cryptoIdentity, apiKey: apiKey, flowId: randomFlowId)
    }

    
    /// This is called during onboarding, when the user wants to check that the server and api key she entered is valid.
    public func queryAPIKeyStatus(serverURL: URL, apiKey: UUID) {
        do {
            let pkEncryptionImplemByteId = ObvCryptoSuite.sharedInstance.getDefaultPublicKeyEncryptionImplementationByteId()
            let authEmplemByteId = ObvCryptoSuite.sharedInstance.getDefaultAuthenticationImplementationByteId()
            let dummyOwnedIdentity = ObvOwnedCryptoIdentity.gen(withServerURL: serverURL,
                                                                forAuthenticationImplementationId: authEmplemByteId,
                                                                andPublicKeyEncryptionImplementationByteId: pkEncryptionImplemByteId,
                                                                using: prng)
            let dummyOwnedCryptoId = ObvCryptoId(cryptoIdentity: dummyOwnedIdentity.getObvCryptoIdentity())
            queryAPIKeyStatus(for: dummyOwnedCryptoId, apiKey: apiKey)
        }
    }
    
    
    /// This method allows to set the api key of an owned identity. If the identity is managed by a keycloak server, the caller must pass the URL of this server, otherwise
    /// this method fails. This protects agains setting "custom" (free trial or other) api keys for a managed owned identity.
    public func setAPIKey(for identity: ObvCryptoId, apiKey: UUID, keycloakServerURL: URL? = nil) throws {
        
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "createContextDelegate is not set") }
        guard let identityDelegate = identityDelegate else { throw makeError(message: "identityDelegate is not set") }
        guard let networkFetchDelegate = networkFetchDelegate else { throw makeError(message: "networkFetchDelegate is not set") }

        let log = self.log
        
        queueForSynchronizingCallsToManagers.async {
            let randomFlowId = FlowIdentifier()
            createContextDelegate.performBackgroundTask(flowId: randomFlowId) { (obvContext) in
                do {
                    try identityDelegate.setAPIKey(apiKey, forOwnedIdentity: identity.cryptoIdentity, keycloakServerURL: keycloakServerURL, within: obvContext)
                    try networkFetchDelegate.resetServerSession(for: identity.cryptoIdentity, within: obvContext)
                } catch {
                    os_log("Could not set new API Key / reset user's server session: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    return
                }
                do {
                    try obvContext.save(logOnFailure: log)
                } catch {
                    os_log("Could not set API Key: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    return
                }
            }
        }
        
    }
    
    /// Queries the server associated to the owned identity for a free trial API Key.
    public func queryServerForFreeTrial(for identity: ObvCryptoId, retrieveAPIKey: Bool) throws {
        guard let networkFetchDelegate = networkFetchDelegate else { throw makeError(message: "networkFetchDelegate is not set") }
        let flowId = FlowIdentifier()
        networkFetchDelegate.queryFreeTrial(for: identity.cryptoIdentity, retrieveAPIKey: retrieveAPIKey, flowId: flowId)
    }
    
    
    public func processAppStorePurchase(for identity: ObvCryptoId, receiptData: String, transactionIdentifier: String) {
        guard let networkFetchDelegate = networkFetchDelegate else { assertionFailure(); return }
        let flowId = FlowIdentifier()
        networkFetchDelegate.verifyReceipt(ownedIdentity: identity.cryptoIdentity, receiptData: receiptData, transactionIdentifier: transactionIdentifier, flowId: flowId)
    }
    
    
    public func refreshAPIPermissions(for identity: ObvCryptoId) throws {
        
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "createContextDelegate is not set") }
        guard let networkFetchDelegate = networkFetchDelegate else { throw makeError(message: "networkFetchDelegate is not set") }

        let log = self.log
        
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: randomFlowId) { (obvContext) in
            do {
                try networkFetchDelegate.resetServerSession(for: identity.cryptoIdentity, within: obvContext)
            } catch {
                os_log("Could not reset user's server session: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
            do {
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Could not set API Key: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
        }
        
    }
    
    
    public func registerToPushNotificationFor(deviceTokens: (pushToken: Data, voipToken: Data?)?, kickOtherDevices: Bool, useMultiDevice: Bool, completion: @escaping (Result<Void,Error>) -> Void) throws {

        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identity delegate is not set") }
        guard let networkFetchDelegate = networkFetchDelegate else { throw makeError(message: "The network fetch delegate is not set") }

        let log = self.log
        
        dispatchQueueForPushNotificationRegistration.async {
            
            let flowId = FlowIdentifier()
            createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in

                let ownedIdentities: Set<ObvCryptoIdentity>
                do {
                    ownedIdentities = try identityDelegate.getOwnedIdentities(within: obvContext)
                } catch {
                    os_log("Could not register to push notifications: %{public}@", log: log, type: .fault, error.localizedDescription)
                    completion(.failure(error))
                    return
                }

                guard !ownedIdentities.isEmpty else {
                    os_log("Could not register to push notifications: Could not find any owned identity in database", log: log, type: .fault)
                    completion(.failure(ObvEngine.makeError(message: "Could not register to push notifications: Could not find any owned identity in database")))
                    return
                }

                ownedIdentities.forEach { (ownedIdentity) in
                    if let currentDeviceUid = try? identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext),
                        let maskingUID = try? identityDelegate.getFreshMaskingUIDForPushNotifications(for: ownedIdentity, within: obvContext) {
                        let remotePushNotification: ObvPushNotificationType
                        let parameters = ObvPushNotificationParameters(kickOtherDevices: kickOtherDevices, useMultiDevice: useMultiDevice)
                        if let tokens = deviceTokens {
                            remotePushNotification = ObvPushNotificationType.remote(pushToken: tokens.pushToken, voipToken: tokens.voipToken, maskingUID: maskingUID, parameters: parameters)
                        } else {
                            remotePushNotification = ObvPushNotificationType.registerDeviceUid(parameters: parameters)
                        }
                        networkFetchDelegate.register(pushNotificationType: remotePushNotification, for: ownedIdentity, withDeviceUid: currentDeviceUid, within: obvContext)
                    }
                }
                
                do {
                    try obvContext.save(logOnFailure: log)
                } catch {
                    os_log("Could not register to push notifications: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    completion(.failure(error))
                    return
                }
                
                completion(.success(()))
                
            }
        }
        
    }
    
    public func updatePublishedIdentityDetailsOfOwnedIdentity(with ownedCryptoId: ObvCryptoId, with newIdentityDetails: ObvIdentityDetails) throws {
        
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identity delegate is not set") }
        guard let flowDelegate = flowDelegate else { throw makeError(message: "The flow delegate is not set") }

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
    
    public func queryServerWellKnown(serverURL: URL) throws {
        guard let networkFetchDelegate = networkFetchDelegate else { throw makeError(message: "The network fetch delegate is not set") }
        let flowId = FlowIdentifier()
        networkFetchDelegate.queryServerWellKnown(serverURL: serverURL, flowId: flowId)
    }

    public func getOwnedIdentityKeycloakState(with ownedCryptoId: ObvCryptoId) throws -> (obvKeycloakState: ObvKeycloakState?, signedOwnedDetails: SignedUserDetails?) {

        guard let createContextDelegate = createContextDelegate else { throw ObvEngine.makeError(message: "Create Context Delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw ObvEngine.makeError(message: "Identity Delegate is not set") }

        var keyCloakState: ObvKeycloakState?
        var signedOwnedDetails: SignedUserDetails?
        let flowId = FlowIdentifier()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
            (keyCloakState, signedOwnedDetails) = try identityDelegate.getOwnedIdentityKeycloakState(
                ownedIdentity: ownedCryptoId.cryptoIdentity,
                within: obvContext)
        }
        return (keyCloakState, signedOwnedDetails)
    }
    
    
    public func getSignedContactDetails(ownedIdentity: ObvCryptoId, contactIdentity: ObvCryptoId, completion: @escaping (Result<SignedUserDetails?,Error>) -> Void) throws {
        guard let createContextDelegate = createContextDelegate else { throw ObvEngine.makeError(message: "Create Context Delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw ObvEngine.makeError(message: "Identity Delegate is not set") }
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


    public func saveKeycloakAuthState(with ownedCryptoId: ObvCryptoId, rawAuthState: Data) throws {
        guard let createContextDelegate = createContextDelegate else { throw ObvEngine.makeError(message: "Create Context Delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw ObvEngine.makeError(message: "Identity Delegate is not set") }

        let flowId = FlowIdentifier()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
            try identityDelegate.saveKeycloakAuthState(ownedIdentity: ownedCryptoId.cryptoIdentity, rawAuthState: rawAuthState, within: obvContext)
            try obvContext.save(logOnFailure: log)
        }
    }

    public func saveKeycloakJwks(with ownedCryptoId: ObvCryptoId, jwks: ObvJWKSet) throws {
        guard let createContextDelegate = createContextDelegate else { throw ObvEngine.makeError(message: "Create Context Delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw ObvEngine.makeError(message: "Identity Delegate is not set") }

        let flowId = FlowIdentifier()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
            try identityDelegate.saveKeycloakJwks(ownedIdentity: ownedCryptoId.cryptoIdentity, jwks: jwks, within: obvContext)
            try obvContext.save(logOnFailure: log)
        }
    }

    public func getOwnedIdentityKeycloakUserId(with ownedCryptoId: ObvCryptoId) throws -> String? {
        guard let createContextDelegate = createContextDelegate else { throw ObvEngine.makeError(message: "Create Context Delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw ObvEngine.makeError(message: "Identity Delegate is not set") }

        var userId: String?
        let flowId = FlowIdentifier()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
            userId = try identityDelegate.getOwnedIdentityKeycloakUserId(ownedIdentity: ownedCryptoId.cryptoIdentity, within: obvContext)
        }
        return userId
    }

    public func setOwnedIdentityKeycloakUserId(with ownedCryptoId: ObvCryptoId, userId: String?) throws {
        guard let createContextDelegate = createContextDelegate else { throw ObvEngine.makeError(message: "Create Context Delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw ObvEngine.makeError(message: "Identity Delegate is not set") }

        let flowId = FlowIdentifier()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
            try identityDelegate.setOwnedIdentityKeycloakUserId(ownedIdentity: ownedCryptoId.cryptoIdentity, keycloakUserId: userId, within: obvContext)
            try obvContext.save(logOnFailure: log)
        }
    }

    public func addKeycloakContact(with ownedCryptoId: ObvCryptoId, signedContactDetails: SignedUserDetails) throws {
        guard let createContextDelegate = createContextDelegate else { throw ObvEngine.makeError(message: "Create Context Delegate is not set") }
        guard let protocolDelegate = protocolDelegate else { throw NSError() }
        guard let flowDelegate = flowDelegate else { return }
        guard let channelDelegate = channelDelegate else { throw ObvEngine.makeError(message: "Channel Delegate is not set") }

        guard let contactIdentity = signedContactDetails.identity else { throw makeError(message: "Could not determine contact identity") }
        guard let contactIdentityToAdd = ObvCryptoIdentity(from: contactIdentity) else { throw makeError(message: "Could not parse contact identity") }
        
        let message = try protocolDelegate.getInitiateAddKeycloakContactMessageForObliviousChannelManagementProtocol(
            ownedIdentity: ownedCryptoId.cryptoIdentity,
            contactIdentityToAdd: contactIdentityToAdd,
            signedContactDetails: signedContactDetails.signedUserDetails)

        var error: Error?
        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()

        createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            do {
                _ = try channelDelegate.post(message, randomizedWith: prng, within: obvContext)
                try obvContext.save(logOnFailure: log)
            } catch let _error {
                error = _error
            }
        }
        guard error == nil else {
            throw error!
        }
    }

    
    /// This method asynchronously binds an owned identity to a keycloak server.
    public func bindOwnedIdentityToKeycloak(ownedCryptoId: ObvCryptoId, keycloakState: ObvKeycloakState, keycloakUserId: String, completion: @escaping (Result<Void,Error>) -> Void) throws {
        
        guard let createContextDelegate = createContextDelegate else { throw ObvEngine.makeError(message: "Create Context Delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw ObvEngine.makeError(message: "Identity Delegate is not set") }
        let appNotificationCenter = self.appNotificationCenter
        let log = self.log

        let flowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
            let cryptoIdsOfContactsCertifiedByOwnKeycloak: Set<ObvCryptoId>
            do {
                let contactsCertifiedByOwnKeycloak = try identityDelegate.bindOwnedIdentityToKeycloak(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, keycloakUserId: keycloakUserId, keycloakState: keycloakState, within: obvContext)
                cryptoIdsOfContactsCertifiedByOwnKeycloak = Set(contactsCertifiedByOwnKeycloak.map({ ObvCryptoId(cryptoIdentity: $0) }))
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Failed to bind owned identity to keycloak server: %{public}@", log: log, type: .fault, error.localizedDescription)
                completion(.failure(error))
                return
            }
            completion(.success(()))
            ObvEngineNotificationNew.updatedSetOfContactsCertifiedByOwnKeycloak(ownedIdentity: ownedCryptoId, contactsCertifiedByOwnKeycloak: cryptoIdsOfContactsCertifiedByOwnKeycloak)
                .postOnBackgroundQueue(within: appNotificationCenter)
        }
        
    }
    
    
    /// This method asynchronously unbinds an owned identity from a keycloak server. During this process, new details are published for owned identity, based on the previously published details, but after removing the signed user details.
    /// This method eventually posts an `ownedIdentityUnbindingFromKeycloakPerformed` notification containing the result of the unbinding process.
    public func unbindOwnedIdentityFromKeycloakServer(ownedCryptoId: ObvCryptoId, completion: @escaping (Result<Void,Error>) -> Void) throws {
        
        guard let createContextDelegate = createContextDelegate else { throw ObvEngine.makeError(message: "Create Context Delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw ObvEngine.makeError(message: "Identity Delegate is not set") }
        let appNotificationCenter = self.appNotificationCenter
        let log = self.log

        let flowId = FlowIdentifier()
        queueForSynchronizingCallsToManagers.async {
            createContextDelegate.performBackgroundTask(flowId: flowId) { [weak self] obvContext in
                guard let _self = self else {
                    completion(.failure(ObvEngine.makeError(message: "Engine was deallocated")))
                    assertionFailure()
                    return
                }
                do {
                    try identityDelegate.unbindOwnedIdentityFromKeycloak(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, within: obvContext)
                    let version = try identityDelegate.getPublishedIdentityDetailsOfOwnedIdentity(ownedCryptoId.cryptoIdentity, within: obvContext).ownedIdentityDetailsElements.version
                    try _self.startIdentityDetailsPublicationProtocol(ownedIdentity: ownedCryptoId, publishedIdentityDetailsVersion: version, within: obvContext)
                    try obvContext.save(logOnFailure: log)
                } catch {
                    os_log("Failed to unbind owned identity from keycloak server: %{public}@", log: log, type: .fault, error.localizedDescription)
                    completion(.failure(error))
                    ObvEngineNotificationNew.ownedIdentityUnbindingFromKeycloakPerformed(ownedIdentity: ownedCryptoId, result: .failure(error))
                        .postOnBackgroundQueue(within: appNotificationCenter)
                    return
                }
                completion(.success(()))
                ObvEngineNotificationNew.ownedIdentityUnbindingFromKeycloakPerformed(ownedIdentity: ownedCryptoId, result: .success(()))
                    .postOnBackgroundQueue(within: appNotificationCenter)
            }
        }

    }
    
    
    /// When an owned identity is bound to a keycloak server, it receives a list of all the existing contacts that are also bound to the keycloak server. It may have missed the notification.
    /// This method, typically called during bootstrap, re-send the notification containing the latest set of all the contact bound to the same keycloak server as the owned identity.
    /// Of course, if the owned identity is not bound to a keycloak server, this method eventually send an empty send within the notification.
    public func requestSetOfContactsCertifiedByOwnKeycloakForAllOwnedCryptoIds() throws {
        
        guard let createContextDelegate = createContextDelegate else { throw ObvEngine.makeError(message: "Create Context Delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw ObvEngine.makeError(message: "Identity Delegate is not set") }
        let appNotificationCenter = self.appNotificationCenter
        let log = self.log

        let flowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
            guard let ownedCryptoIdentities = try? identityDelegate.getOwnedIdentities(within: obvContext) else { assertionFailure(); return }
            for ownedCryptoIdentity in ownedCryptoIdentities {
                let cryptoIdsOfContactsCertifiedByOwnKeycloak: Set<ObvCryptoId>
                do {
                    let contactsCertifiedByOwnKeycloak = try identityDelegate.getContactsCertifiedByOwnKeycloak(ownedCryptoIdentity: ownedCryptoIdentity, within: obvContext)
                    cryptoIdsOfContactsCertifiedByOwnKeycloak = Set(contactsCertifiedByOwnKeycloak.map({ ObvCryptoId(cryptoIdentity: $0) }))
                } catch {
                    os_log("Failed to obtain the contacts of the owned identity that are bound to the same keycloak: %{public}@", log: log, type: .fault, error.localizedDescription)
                    return
                }
                let ownedCryptoId = ObvCryptoId(cryptoIdentity: ownedCryptoIdentity)
                ObvEngineNotificationNew.updatedSetOfContactsCertifiedByOwnKeycloak(ownedIdentity: ownedCryptoId, contactsCertifiedByOwnKeycloak: cryptoIdsOfContactsCertifiedByOwnKeycloak)
                    .postOnBackgroundQueue(within: appNotificationCenter)
            }
            
        }

    }
    
    
    public func setOwnedIdentityKeycloakSelfRevocationTestNonce(ownedCryptoId: ObvCryptoId, newSelfRevocationTestNonce: String?) throws {
        guard let createContextDelegate = createContextDelegate else { throw ObvEngine.makeError(message: "Create Context Delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw ObvEngine.makeError(message: "Identity Delegate is not set") }
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
        guard let createContextDelegate = createContextDelegate else { throw ObvEngine.makeError(message: "Create Context Delegate is not set") }
        let flowId = FlowIdentifier()
        var selfRevocationTestNonce: String? = nil
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { obvContext in
            selfRevocationTestNonce = try identityDelegate?.getOwnedIdentityKeycloakSelfRevocationTestNonce(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, within: obvContext)
        }
        return selfRevocationTestNonce
    }
    
    
    public func setOwnedIdentityKeycloakSignatureKey(ownedCryptoId: ObvCryptoId, keycloakServersignatureVerificationKey: ObvJWK?) throws {
        guard let createContextDelegate = createContextDelegate else { assertionFailure(); throw ObvEngine.makeError(message: "Create Context Delegate is not set") }
        guard let identityDelegate = identityDelegate else { assertionFailure(); throw ObvEngine.makeError(message: "Identity Delegate is not set") }
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
        guard let createContextDelegate = createContextDelegate else { assertionFailure(); throw ObvEngine.makeError(message: "Create Context Delegate is not set") }
        guard let identityDelegate = identityDelegate else { assertionFailure(); throw ObvEngine.makeError(message: "Identity Delegate is not set") }
        guard let channelDelegate = channelDelegate else { throw ObvEngine.makeError(message: "Channel Delegate is not set") }
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
        
    
    public func updateKeycloakPushTopicsIfNeeded(ownedCryptoId: ObvCryptoId, pushTopics: Set<String>) throws {
        guard let createContextDelegate = createContextDelegate else { assertionFailure(); throw makeError(message: "Create Context Delegate is not set") }
        guard let identityDelegate = identityDelegate else { assertionFailure(); throw makeError(message: "Identity Delegate is not set") }
        guard let networkFetchDelegate = networkFetchDelegate else { throw makeError(message: "The network fetch delegate is not set") }
        let flowId = FlowIdentifier()
        let log = self.log
        os_log("Updating the keycloak push topics within the engine", log: log, type: .info)
        try queueForSynchronizingCallsToManagers.sync {
            try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { obvContext in
                let storedPushTopicsUpdated = try identityDelegate.updateKeycloakPushTopicsIfNeeded(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, pushTopics: pushTopics, within: obvContext)
                if storedPushTopicsUpdated {
                    try networkFetchDelegate.forceRegisterToPushNotification(identity: ownedCryptoId.cryptoIdentity, within: obvContext)
                }
                try obvContext.save(logOnFailure: log)
            }
        }

    }
    
    
    
    public func getManagedOwnedIdentitiesAssociatedWithThePushTopic(_ pushTopic: String) throws -> Set<ObvOwnedIdentity> {
        guard let createContextDelegate = createContextDelegate else { assertionFailure(); throw makeError(message: "Create Context Delegate is not set") }
        guard let identityDelegate = identityDelegate else { assertionFailure(); throw makeError(message: "Identity Delegate is not set") }
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

    
    public func getSignedOwnedDetails(ownedIdentity: ObvCryptoId, completion: @escaping (Result<SignedUserDetails?,Error>) -> Void) throws {
        guard let createContextDelegate = createContextDelegate else { throw ObvEngine.makeError(message: "Create Context Delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw ObvEngine.makeError(message: "Identity Delegate is not set") }
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


// MARK: - Public API for managing contact identities

extension ObvEngine {
    
    public func getContactDeviceIdentifiersForWhichAChannelCreationProtocolExists(with contactCryptoId: ObvCryptoId, ofOwnedIdentityWith ownedCryptoId: ObvCryptoId) throws -> Set<Data> {
        
        guard let createContextDelegate = createContextDelegate else { throw ObvEngine.makeError(message: "Create Context Delegate is not set") }
        guard let protocolDelegate = protocolDelegate else { throw ObvEngine.makeError(message: "Protocol Delegate is not set") }
        
        var channelIds: Set<ObliviousChannelIdentifierAlt>!
        
        let flowId = FlowIdentifier()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
            channelIds = try protocolDelegate.getAllObliviousChannelIdentifiersHavingARunningChannelCreationWithContactDeviceProtocolInstances(within: obvContext)
                .filter({ $0.ownedCryptoIdentity == ownedCryptoId.cryptoIdentity && $0.remoteCryptoIdentity == contactCryptoId.cryptoIdentity })
        }
        
        return Set(channelIds.map({ $0.remoteDeviceUid.raw }))
        
    }
    
    
    public func getContactDeviceIdentifiersOfContactIdentity(with contactCryptoId: ObvCryptoId, ofOwnedIdentityWith ownedCryptoId: ObvCryptoId) throws -> Set<Data> {
        
        guard let createContextDelegate = createContextDelegate else { throw ObvEngine.makeError(message: "Create Context Delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw ObvEngine.makeError(message: "Identity Delegate is not set") }
        
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
    
    
    public func getContactIdentity(with contactCryptoId: ObvCryptoId, ofOwnedIdentityWith ownedCryptoId: ObvCryptoId) throws -> ObvContactIdentity {
        
        guard let createContextDelegate = createContextDelegate else { throw ObvEngine.makeError(message: "Create Context Delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw ObvEngine.makeError(message: "Identity Delegate is not set") }
        
        
        var obvContactIdentity: ObvContactIdentity!
        var error: Error? = nil
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
            guard let _obvContactIdentity = ObvContactIdentity(contactCryptoIdentity: contactCryptoId.cryptoIdentity,
                                                               ownedCryptoIdentity: ownedCryptoId.cryptoIdentity,
                                                               identityDelegate: identityDelegate,
                                                               within: obvContext) else {
                error = NSError()
                return
            }
            obvContactIdentity = _obvContactIdentity
        }
        guard error == nil else {
            throw error!
        }
        
        return obvContactIdentity
        
    }
    
    public func getContactsOfOwnedIdentity(with ownedCryptoId: ObvCryptoId) throws -> Set<ObvContactIdentity> {
        
        guard let createContextDelegate = createContextDelegate else { throw ObvEngine.makeError(message: "Create Context Delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw ObvEngine.makeError(message: "Identity Delegate is not set") }

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
                        guard let obvContactIdentity = ObvContactIdentity(contactCryptoIdentity: $0, ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, identityDelegate: identityDelegate, within: obvContext) else { throw NSError() }
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
        
        guard let createContextDelegate = createContextDelegate else { throw ObvEngine.makeError(message: "Create Context Delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw ObvEngine.makeError(message: "Identity Delegate is not set") }
        guard let protocolDelegate = protocolDelegate else { throw makeError(message: "The protocol delegate is not set") }
        guard let flowDelegate = flowDelegate else { throw ObvEngine.makeError(message: "The flow delegate is not set") }
        guard let channelDelegate = channelDelegate else { throw ObvEngine.makeError(message: "Channel Delegate is not set") }
        
        // We prepare the appropriate message for starting the ObliviousChannelManagementProtocol step allowing to delete the contact
        
        let message = try protocolDelegate.getInitiateContactDeletionMessageForObliviousChannelManagementProtocol(ownedIdentity: ownedCryptoId.cryptoIdentity,
                                                                                                                  contactIdentityToDelete: contactCryptoId.cryptoIdentity)
        
        
        // The ObliviousChannelManagementProtocol fails to delete a contact if this contact is part of a group. We check this here and throw if this is the case.
        
        var error: Error?
        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()
        createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
            do {
                guard try !identityDelegate.contactIdentityBelongsToSomeContactGroup(contactCryptoId.cryptoIdentity, forOwnedIdentity: ownedCryptoId.cryptoIdentity, within: obvContext) else {
                    error = NSError()
                    return
                }
            } catch let _error {
                error = _error
                return
            }
            
            // If we reach this point, we know that the contact does not belong the a joined group. We can start the protocol allowing to delete this contact.
            
            do {
                _ = try channelDelegate.post(message, randomizedWith: prng, within: obvContext)
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

        guard let createContextDelegate = createContextDelegate else { throw ObvEngine.makeError(message: "Create Context Delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw ObvEngine.makeError(message: "Identity Delegate is not set") }

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

    
    /// This method returns the list of the contact's device uids for which a channel exist with the current device uid of the owned identity
    public func getAllObliviousChannelsEstablishedWithContactIdentity(with contactCryptoId: ObvCryptoId, ofOwnedIdentyWith ownedCryptoId: ObvCryptoId) throws -> Set<ObvContactDevice> {
        
        guard let createContextDelegate = createContextDelegate else { throw ObvEngine.makeError(message: "Create Context Delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw ObvEngine.makeError(message: "Identity Delegate is not set") }
        guard let channelDelegate = channelDelegate else { throw ObvEngine.makeError(message: "Channel Delegate is not set") }

        var error: Error?
        var contactDevices: Set<ObvContactDevice>!
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
            let contactDeviceUids: [UID]
            do {
                contactDeviceUids = try channelDelegate.getRemoteDeviceUidsOfRemoteIdentity(contactCryptoId.cryptoIdentity, forWhichAConfirmedObliviousChannelExistsWithTheCurrentDeviceOfOwnedIdentity: ownedCryptoId.cryptoIdentity, within: obvContext)
            } catch let _error {
                error = _error
                return
            }
            contactDevices = Set<ObvContactDevice>()
            contactDeviceUids.forEach {
                if let contactDevice = ObvContactDevice(contactDeviceUid: $0,
                                                        contactCryptoIdentity: contactCryptoId.cryptoIdentity,
                                                        ownedCryptoIdentity: ownedCryptoId.cryptoIdentity,
                                                        identityDelegate: identityDelegate,
                                                        within: obvContext) {
                    contactDevices.insert(contactDevice)
                }
            }
        }
        guard error == nil else {
            throw error!
        }
        return contactDevices
    }
    
    
    public func updateTrustedIdentityDetailsOfContactIdentity(with contactCryptoId: ObvCryptoId, ofOwnedIdentityWithCryptoId ownedCryptoId: ObvCryptoId, with newTrustedIdentityDetails: ObvIdentityDetails) throws {
        
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identity delegate is not set") }
        
        let randomFlowId = FlowIdentifier()
        var error: Error?
        createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
            do {
                try identityDelegate.updateTrustedIdentityDetailsOfContactIdentity(contactCryptoId.cryptoIdentity,
                                                                                   ofOwnedIdentity: ownedCryptoId.cryptoIdentity,
                                                                                   with: newTrustedIdentityDetails,
                                                                                   within: obvContext)
                try obvContext.save(logOnFailure: log)
            } catch let _error {
                error = _error
            }
        }
        guard error == nil else { throw error! }
        
    }
    
    
    public func unblockContactIdentity(with contactCryptoId: ObvCryptoId, ofOwnedIdentityWithCryptoId ownedCryptoId: ObvCryptoId) throws {

        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identity delegate is not set") }
        
        let randomFlowId = FlowIdentifier()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: randomFlowId) { obvContext in
            do {
                try identityDelegate.setContactForcefullyTrustedByUser(
                    ownedIdentity: ownedCryptoId.cryptoIdentity,
                    contactIdentity: contactCryptoId.cryptoIdentity,
                    forcefullyTrustedByUser: true,
                    within: obvContext)
                try reCreateAllChannelEstablishmentProtocolsWithContactIdentity(with: contactCryptoId.cryptoIdentity, ofOwnedIdentyWith: ownedCryptoId.cryptoIdentity, within: obvContext)
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Could not unblock contact: %{public}@", log: log, type: .fault, error.localizedDescription)
                throw error
            }
        }
    }

    
    public func reblockContactIdentity(with contactCryptoId: ObvCryptoId, ofOwnedIdentityWithCryptoId ownedCryptoId: ObvCryptoId) throws {

        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identity delegate is not set") }
        guard let channelDelegate = channelDelegate else { throw makeError(message: "The channel delegate is not set") }

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

}


// MARK: - Public API for managing capabilities

extension ObvEngine {
    
    public func getCapabilitiesOfAllContactsOfOwnedIdentity(_ ownedCryptoId: ObvCryptoId) throws -> [ObvCryptoId: Set<ObvCapability>] {
        
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identity delegate is not set") }
        
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
    
    
    public func setCapabilitiesOfCurrentDeviceForAllOwnedIdentities(_ newObvCapabilities: Set<ObvCapability>) throws {
        
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identity delegate is not set") }
        guard let protocolDelegate = protocolDelegate else { throw ObvEngine.makeError(message: "Protocol Delegate is not set") }
        guard let channelDelegate = channelDelegate else { throw ObvEngine.makeError(message: "Channel is not set") }
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
                    _ = try channelDelegate.post(message, randomizedWith: prng, within: obvContext)
                }
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Could not set capabilities of current device UIDs of all own identities: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
            
        }
        
    }
    
    
    public func getCapabilitiesOfOwnedIdentity(_ ownedCryptoId: ObvCryptoId) throws -> Set<ObvCapability> {
        
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identity delegate is not set") }
        
        var capabilities = Set<ObvCapability>()
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
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        var error: Error?
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
            deleteDialog(with: uuid, within: obvContext)
            do {
                try obvContext.save(logOnFailure: log)
            } catch let _error {
                error = _error
            }
        }
        guard error == nil else {
            throw error!
        }
    }
    
    public func abortProtocol(associatedTo obvDialog: ObvDialog) throws {
        
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let protocolDelegate = protocolDelegate else { throw makeError(message: "The protocol delegate is not set") }


        // Like un cochon
        guard let listOfEncoded = [ObvEncoded](obvDialog.encodedElements, expectedCount: 4) else { throw NSError() }
        guard let protocolInstanceUid = UID(listOfEncoded[1]) else { throw NSError() }
        try protocolDelegate.abortProtocol(withProtocolInstanceUid: protocolInstanceUid,
                                           forOwnedIdentity: obvDialog.ownedCryptoId.cryptoIdentity)
        
        var error: Error?
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
            deleteDialog(with: obvDialog.uuid, within: obvContext)
            do {
                try obvContext.save(logOnFailure: log)
            } catch let _error {
                error = _error
            }
        }
        guard error == nil else {
            throw error!
        }
        
    }
    
    
    private func deleteDialog(with uid: UUID, within obvContext: ObvContext) {
        guard let persistedDialog = PersistedEngineDialog.get(uid: uid, appNotificationCenter: appNotificationCenter, within: obvContext) else { return }
        obvContext.delete(persistedDialog)
    }
    
    
    public func resendDialogs() throws {
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        var error: Error?
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
            guard let persistedDialogs = PersistedEngineDialog.getAll(appNotificationCenter: appNotificationCenter, within: obvContext) else {
                error = NSError()
                return
            }
            persistedDialogs.forEach {
                $0.resend()
            }
            do {
                try obvContext.save(logOnFailure: log)
            } catch let _error {
                error = _error
            }
        }
        guard error == nil else {
            throw error!
        }
    }
    
    
    
    public func respondTo(_ obvDialog: ObvDialog) {
        
        guard let createContextDelegate = createContextDelegate else { assertionFailure(); return }
        guard let channelDelegate = channelDelegate else { assertionFailure(); return }
        guard let flowDelegate = flowDelegate else { assertionFailure(); return }
        
        // Responding to an ObvDialog is a critical long-running task, so we always extend the app runtime to make sure that responding to a dialog (and all the resulting network exchanges) eventually finish, even if the app moves to the background between the call to this method and the moment the data is actually sent to the server.
        
        guard let flowId = try? flowDelegate.startBackgroundActivityForStartingOrResumingProtocol() else { return }
        
        createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { [weak self] (obvContext) in
            guard let _self = self else { return }
            do {
                guard let encodedResponse = obvDialog.encodedResponse else { throw NSError() }
                let timestamp = Date()
                let channelDialogResponseMessageToSend = ObvChannelDialogResponseMessageToSend(uuid: obvDialog.uuid,
                                                                                               toOwnedIdentity: obvDialog.ownedCryptoId.cryptoIdentity,
                                                                                               timestamp: timestamp,
                                                                                               encodedUserDialogResponse: encodedResponse,
                                                                                               encodedElements: obvDialog.encodedElements)
                do {
                    _ = try channelDelegate.post(channelDialogResponseMessageToSend, randomizedWith: _self.prng, within: obvContext)
                    try obvContext.save(logOnFailure: _self.log)
                } catch {
                    os_log("Could not respond to obvDialog (1)", log: _self.log, type: .fault)
                }
            } catch {
                os_log("Could not respond to obvDialog (2)", log: _self.log, type: .fault)
            }
        }
    }
    
}


// MARK: - Public API for starting cryptographic protocols

extension ObvEngine {
    
    public func startTrustEstablishmentProtocolOfRemoteIdentity(with remoteCryptoId: ObvCryptoId, withFullDisplayName remoteFullDisplayName: String, forOwnedIdentyWith ownedCryptoId: ObvCryptoId) throws {
        
        guard let channelDelegate = channelDelegate else { throw makeError(message: "The channel delegate is not set") }
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let protocolDelegate = protocolDelegate else { throw makeError(message: "The protocol delegate is not set") }
        guard let flowDelegate = flowDelegate else { throw makeError(message: "The flow delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identity delegate is not set") }
        
        let log = self.log
        
        // Recover the published owned identity details
        var obvOwnedIdentity: ObvOwnedIdentity!
        var error: Error?
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
            guard let _obvOwnedIdentity = ObvOwnedIdentity(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, identityDelegate: identityDelegate, within: obvContext) else {
                error = NSError()
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
                _ = try channelDelegate.post(message, randomizedWith: prng, within: obvContext)
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
        
        guard let channelDelegate = channelDelegate else { throw makeError(message: "The channel delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identity delegate is not set") }
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let protocolDelegate = protocolDelegate else { throw makeError(message: "The protocol delegate is not set") }
        guard let flowDelegate = flowDelegate else { throw makeError(message: "The flow delegate is not set") }
        
        let log = self.log
        
        var contact: ObvContactIdentity!
        var otherContacts = Set<ObvContactIdentity>()
        var ownedIdentity: ObvOwnedIdentity!
        do {
            var error: Error?
            let randomFlowId = FlowIdentifier()
            createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
                guard let _contact = ObvContactIdentity(contactCryptoIdentity: remoteCryptoId.cryptoIdentity,
                                                        ownedCryptoIdentity: ownedId.cryptoIdentity,
                                                        identityDelegate: identityDelegate, within: obvContext)
                else {
                    error = ObvEngine.makeError(message: "Could not find contact identity. We may be trying to start a ContactMutualIntroductionProtocol between two contacts of distinct owned identities.")
                    return
                }
                contact = _contact
                ownedIdentity = _contact.ownedIdentity
                for cryptoId in remoteCryptoIds {
                    guard let _otherContact = ObvContactIdentity(contactCryptoIdentity: cryptoId.cryptoIdentity,
                                                           ownedCryptoIdentity: ownedId.cryptoIdentity,
                                                           identityDelegate: identityDelegate, within: obvContext)
                    else {
                        error = ObvEngine.makeError(message: "Could not find contact identity. We may be trying to start a ContactMutualIntroductionProtocol between two contacts of distinct owned identities.")
                        return
                    }
                    guard _otherContact.ownedIdentity ==  ownedIdentity else {
                        error = ObvEngine.makeError(message: "All contacts should belong to the same owned identity")
                        return
                    }
                    otherContacts.insert(_otherContact)
                }
                
            }
            guard error == nil else { throw error! }
        }
        
        // Starting a ContactMutualIntroductionProtocol is a critical long-running task, so we always extend the app runtime to make sure that we can perform the required tasks, even if the app moves to the background between the call to this method and the moment the data is actually sent to the server.
        
        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()

        var messages = [ObvChannelProtocolMessageToSend]()
        for otherContact in otherContacts {
            let protocolInstanceUid = UID.gen(with: prng)
            let message = try protocolDelegate.getInitialMessageForContactMutualIntroductionProtocol(of: contact.cryptoId.cryptoIdentity,
                                                                                                     withContactIdentityCoreDetails: contact.currentIdentityDetails.coreDetails,
                                                                                                     with: otherContact.cryptoId.cryptoIdentity,
                                                                                                     withOtherContactIdentityCoreDetails: otherContact.currentIdentityDetails.coreDetails,
                                                                                                     byOwnedIdentity: ownedIdentity.cryptoId.cryptoIdentity,
                                                                                                     usingProtocolInstanceUid: protocolInstanceUid)
            messages.append(message)
        }
        
        var error: Error?
        createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            do {
                for message in messages {
                    _ = try channelDelegate.post(message, randomizedWith: prng, within: obvContext)
                }
                try obvContext.save(logOnFailure: log)
            } catch let _error {
                error = _error
            }
        }
        guard error == nil else {
            throw error!
        }
    }
    

    // This protocol is started when the user publishes her identity details
    private func startIdentityDetailsPublicationProtocol(ownedIdentity: ObvCryptoId, publishedIdentityDetailsVersion version: Int, within obvContext: ObvContext) throws {
        
        guard let channelDelegate = channelDelegate else { throw makeError(message: "The channel delegate is not set") }
        guard let protocolDelegate = protocolDelegate else { throw makeError(message: "The protocol delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identity delegate is not set") }
        
        let message = try protocolDelegate.getInitialMessageForIdentityDetailsPublicationProtocol(ownedIdentity: ownedIdentity.cryptoIdentity,
                                                                                                  publishedIdentityDetailsVersion: version)
        guard try identityDelegate.isOwned(ownedIdentity.cryptoIdentity, within: obvContext) else { throw makeError(message: "The identity is not owned") }
        _ = try channelDelegate.post(message, randomizedWith: prng, within: obvContext)
        
    }

    
    // This protocol is started when a group owner (an owned identity) publishes (latest) details for a (owned) contact group
    private func startOwnedGroupLatestDetailsPublicationProtocol(for groupStructure: GroupStructure, within obvContext: ObvContext) throws {
        
        guard let channelDelegate = channelDelegate else { throw makeError(message: "The channel delegate is not set") }
        guard let protocolDelegate = protocolDelegate else { throw makeError(message: "The protocol delegate is not set") }
        
        guard groupStructure.groupType == .owned else { throw NSError() }
        
        let message = try protocolDelegate.getOwnedGroupMembersChangedTriggerMessageForGroupManagementProtocol(groupUid: groupStructure.groupUid, ownedIdentity: groupStructure.groupOwner, within: obvContext)
        _ = try channelDelegate.post(message, randomizedWith: prng, within: obvContext)
    }
    
    /// This is similar to reCreateAllChannelEstablishmentProtocolsWithContactIdentity, except that we only delete the devices for which no channel is established yet. No chanell gets deleted here.
    public func restartAllOngoingChannelEstablishmentProtocolsWithContactIdentity(with contactCryptoId: ObvCryptoId, ofOwnedIdentyWith ownedCryptoId: ObvCryptoId) throws {
        
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let channelDelegate = channelDelegate else { throw makeError(message: "The channel delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identity delegate is not set") }
        guard let flowDelegate = flowDelegate else { throw makeError(message: "The flow delegate is not set") }
        guard let protocolDelegate = protocolDelegate else { throw makeError(message: "The protocol delegate is not set") }
        
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
            let message: ObvChannelProtocolMessageToSend
            do {
                message = try protocolDelegate.getInitialMessageForDeviceDiscoveryForContactIdentityProtocol(ownedIdentity: ownedCryptoId.cryptoIdentity, contactIdentity: contactCryptoId.cryptoIdentity)
            } catch let error {
                os_log("Could not get initial message for device discovery for contact identity protocol", log: log, type: .fault)
                assertionFailure()
                throw error
            }
            
            do {
                _ = try channelDelegate.post(message, randomizedWith: prng, within: obvContext)
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
    

    /// This method first delete all channels and device uids with the contact identity. It then performs a device discovery. This enough, since the device discovery will eventually add devices and thus, new channels will be created.
    public func reCreateAllChannelEstablishmentProtocolsWithContactIdentity(with contactCryptoId: ObvCryptoId, ofOwnedIdentyWith ownedCryptoId: ObvCryptoId) throws {
        
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let flowDelegate = flowDelegate else { throw makeError(message: "The flow delegate is not set") }
        
        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()

        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
            
            try reCreateAllChannelEstablishmentProtocolsWithContactIdentity(with: contactCryptoId.cryptoIdentity, ofOwnedIdentyWith: ownedCryptoId.cryptoIdentity, within: obvContext)
            
            do {
                try obvContext.save(logOnFailure: log)
            } catch let error {
                os_log("Could not save context: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                throw error
            }
            
        }
                
    }
    
    
    private func reCreateAllChannelEstablishmentProtocolsWithContactIdentity(with contactCryptoIdentity: ObvCryptoIdentity, ofOwnedIdentyWith ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        
        guard let channelDelegate = channelDelegate else { throw makeError(message: "The channel delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identity delegate is not set") }
        guard let protocolDelegate = protocolDelegate else { throw makeError(message: "The protocol delegate is not set") }

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
            let message: ObvChannelProtocolMessageToSend
            do {
                message = try protocolDelegate.getInitialMessageForDeviceDiscoveryForContactIdentityProtocol(ownedIdentity: ownedCryptoIdentity, contactIdentity: contactCryptoIdentity)
            } catch let error {
                os_log("Could not get initial message for device discovery for contact identity protocol", log: log, type: .fault)
                assertionFailure()
                throw error
            }
            
            do {
                _ = try channelDelegate.post(message, randomizedWith: prng, within: obvContext)
            } catch let error {
                os_log("Could not post a local protocol message allowing to start a device discovery for a contact", log: log, type: .fault)
                assertionFailure()
                throw error
            }
                        
        }

    }

    
    public func computeMutualScanUrl(remoteIdentity: Data, ownedCryptoId: ObvCryptoId) throws -> ObvMutualScanUrl {
        
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let solveChallengeDelegate = solveChallengeDelegate else { throw makeError(message: "The solve challenge delegate is not set") }

        guard let remoteCryptoId = ObvCryptoIdentity(from: remoteIdentity) else {
            throw makeError(message: "Could not turn data into an ObvCryptoIdentity")
        }

        var signature: Data?
        var fullDisplayName: String?

        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: FlowIdentifier()) { obvContext in
            let identities = [remoteCryptoId, ownedCryptoId.cryptoIdentity]
            let challenge = identities.reduce(Data()) { $0 + $1.getIdentity() }
            let prefix = ObvConstants.trustEstablishmentWithMutualScanProtocolPrefix
            guard let sig = try? solveChallengeDelegate.solveChallenge(challenge, prefixedWith: prefix, for: ownedCryptoId.cryptoIdentity, using: prng, within: obvContext) else {
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
    
    
    public func verifyMutualScanUrl(ownedCryptoId: ObvCryptoId, mutualScanUrl: ObvMutualScanUrl) throws -> Bool {
        guard let solveChallengeDelegate = solveChallengeDelegate else { throw makeError(message: "The solve challenge delegate is not set") }
        let identities = [ownedCryptoId.cryptoIdentity, mutualScanUrl.cryptoId.cryptoIdentity]
        let challenge = identities.reduce(Data()) { $0 + $1.getIdentity() }
        let prefix = ObvConstants.trustEstablishmentWithMutualScanProtocolPrefix
        return solveChallengeDelegate.checkResponse(mutualScanUrl.signature, toChallenge: challenge, prefixedWith: prefix, from: mutualScanUrl.cryptoId.cryptoIdentity)
    }
    
    
    public func startTrustEstablishmentWithMutualScanProtocol(ownedIdentity: ObvCryptoId, mutualScanUrl: ObvMutualScanUrl) throws {
        
        guard let protocolDelegate = protocolDelegate else { throw makeError(message: "The protocol delegate is not set") }
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let channelDelegate = channelDelegate else { throw makeError(message: "The channel delegate is not set") }

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
                _ = try channelDelegate.post(message, randomizedWith: prng, within: obvContext)
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


// MARK: - Public API for managing groups

extension ObvEngine {
    
    public func startGroupCreationProtocol(groupName: String, groupDescription: String?, groupMembers: Set<ObvCryptoId>, ownedCryptoId: ObvCryptoId, photoURL: URL?) throws {
        
        guard !groupMembers.isEmpty else { return }
        
        guard let channelDelegate = channelDelegate else { throw makeError(message: "The channel delegate is not set") }
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let protocolDelegate = protocolDelegate else { throw makeError(message: "The protocol delegate is not set") }
        guard let flowDelegate = flowDelegate else { throw makeError(message: "The flow delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identity delegate is not set") }
        
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
                _ = try channelDelegate.post(message, randomizedWith: prng, within: obvContext)
                try obvContext.save(logOnFailure: log)
            } catch let _error {
                error = _error
            }
        }
        guard error == nil else {
            throw error!
        }
        
    }

    
    public func inviteContactsToGroupOwned(groupUid: UID, ownedCryptoId: ObvCryptoId, newGroupMembers: Set<ObvCryptoId>) throws {
        
        guard !newGroupMembers.isEmpty else { return }
        
        guard let protocolDelegate = protocolDelegate else { throw makeError(message: "The protocol delegate is not set") }
        guard let flowDelegate = flowDelegate else { throw makeError(message: "The flow delegate is not set") }
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let channelDelegate = channelDelegate else { throw makeError(message: "The channel delegate is not set") }

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
                _ = try channelDelegate.post(message, randomizedWith: prng, within: obvContext)
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

        guard let protocolDelegate = protocolDelegate else { throw makeError(message: "The protocol delegate is not set") }
        guard let flowDelegate = flowDelegate else { throw makeError(message: "The flow delegate is not set") }
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let channelDelegate = channelDelegate else { throw makeError(message: "The channel delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identity delegate is not set") }
        
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
                _ = try channelDelegate.post(message, randomizedWith: prng, within: obvContext)
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
        
        guard let protocolDelegate = protocolDelegate else { throw makeError(message: "The protocol delegate is not set") }
        guard let flowDelegate = flowDelegate else { throw makeError(message: "The flow delegate is not set") }
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let channelDelegate = channelDelegate else { throw makeError(message: "The channel delegate is not set") }
        
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
                _ = try channelDelegate.post(message, randomizedWith: prng, within: obvContext)
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
        
        guard let createContextDelegate = self.createContextDelegate else { throw makeError(message: "The create context delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identity delegate is not set") }
        
        var obvContactGroups: Set<ObvContactGroup>!
        var error: Error?
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
            do {
                let groupStructures = try identityDelegate.getAllGroupStructures(ownedIdentity: ownedCryptoId.cryptoIdentity, within: obvContext)
                obvContactGroups = Set(groupStructures.compactMap({ (groupStructure) in
                    return ObvContactGroup(groupStructure: groupStructure, identityDelegate: identityDelegate, within: obvContext)
                }))
                guard obvContactGroups.count == groupStructures.count else { throw NSError() }
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
        
        guard let createContextDelegate = self.createContextDelegate else { throw makeError(message: "The create context delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identity delegate is not set") }
        
        var obvContactGroup: ObvContactGroup!
        var error: Error?
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
            do {
                guard let groupStructure = try identityDelegate.getGroupOwnedStructure(ownedIdentity: ownedCryptoId.cryptoIdentity, groupUid: groupUid, within: obvContext) else {
                    throw NSError()
                }
                guard let _obvContactGroup = ObvContactGroup(groupStructure: groupStructure, identityDelegate: identityDelegate, within: obvContext) else {
                    throw NSError()
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
        
        guard let createContextDelegate = self.createContextDelegate else { throw makeError(message: "The create context delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identity delegate is not set") }
        
        var obvContactGroup: ObvContactGroup!
        var error: Error?
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
            do {
                guard let groupStructure = try identityDelegate.getGroupJoinedStructure(ownedIdentity: ownedCryptoId.cryptoIdentity, groupUid: groupUid, groupOwner: groupOwner.cryptoIdentity, within: obvContext) else {
                    throw NSError()
                }
                guard let _obvContactGroup = ObvContactGroup(groupStructure: groupStructure, identityDelegate: identityDelegate, within: obvContext) else {
                    throw NSError()
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

    
    public func updateLatestDetailsOfOwnedContactGroup(using newGroupDetails: ObvGroupDetails, ownedCryptoId: ObvCryptoId, groupUid: UID) throws {
        
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identity delegate is not set") }
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        
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
        
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identity delegate is not set") }
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        
        do {
            var error: Error?
            let randomFlowId = FlowIdentifier()
            createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
                do {
                    guard let groupStructure = try identityDelegate.getGroupOwnedStructure(ownedIdentity: ownedCryptoId.cryptoIdentity, groupUid: groupUid, within: obvContext) else {
                        throw NSError()
                    }
                    guard groupStructure.groupType == .owned else { throw NSError() }
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
        
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identity delegate is not set") }
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let flowDelegate = flowDelegate else { throw makeError(message: "The flow delegate is not set") }
        
        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
            
            try identityDelegate.publishLatestDetailsOfContactGroupOwned(ownedIdentity: ownedCryptoId.cryptoIdentity, groupUid: groupUid, within: obvContext)
            guard let groupStructure = try identityDelegate.getGroupOwnedStructure(ownedIdentity: ownedCryptoId.cryptoIdentity, groupUid: groupUid, within: obvContext) else {
                throw makeError(message: "Could not find group structure")
            }
            guard groupStructure.groupType == .owned else { throw NSError() }
            try startOwnedGroupLatestDetailsPublicationProtocol(for: groupStructure, within: obvContext)
            try obvContext.save(logOnFailure: log)
        }
        
    }

    
    public func trustPublishedDetailsOfJoinedContactGroup(ownedCryptoId: ObvCryptoId, groupUid: UID, groupOwner: ObvCryptoId) throws {
    
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identity delegate is not set") }
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        
        do {
            var error: Error?
            let randomFlowId = FlowIdentifier()
            createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
                do {
                    guard let groupStructure = try identityDelegate.getGroupJoinedStructure(ownedIdentity: ownedCryptoId.cryptoIdentity, groupUid: groupUid, groupOwner: groupOwner.cryptoIdentity, within: obvContext) else {
                        throw NSError()
                    }
                    guard groupStructure.groupType == .joined else { throw NSError() }
                    try identityDelegate.trustPublishedDetailsOfContactGroupJoined(ownedIdentity: ownedCryptoId.cryptoIdentity, groupUid: groupUid, groupOwner: groupOwner.cryptoIdentity, within: obvContext)
                    try obvContext.save(logOnFailure: log)
                } catch let _error {
                    error = _error
                }
            }
            guard error == nil else { throw error! }
        }

    }

    
    public func deleteOwnedContactGroup(ownedCryptoId: ObvCryptoId, groupUid: UID) throws {
        
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identity delegate is not set") }
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }

        do {
            var error: Error?
            let randomFlowId = FlowIdentifier()
            createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
                do {
                    try identityDelegate.deleteContactGroupOwned(ownedIdentity: ownedCryptoId.cryptoIdentity, groupUid: groupUid, within: obvContext)
                    try obvContext.save(logOnFailure: log)
                } catch let _error {
                    error = _error
                }
            }
            guard error == nil else { throw error! }
        }
    }
    
    
    // Called when the owned identity decides to leave a group she joined
    public func leaveContactGroupJoined(ownedCryptoId: ObvCryptoId, groupUid: UID, groupOwner: ObvCryptoId) throws {
        
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let protocolDelegate = protocolDelegate else { throw makeError(message: "The protocol delegate is not set") }
        guard let channelDelegate = channelDelegate else { throw makeError(message: "The channel delegate is not set") }

        let log = self.log
        
        let flowId = FlowIdentifier()
        var error: Error?
        createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            do {
                let message = try protocolDelegate.getLeaveGroupJoinedMessageForGroupManagementProtocol(ownedIdentity: ownedCryptoId.cryptoIdentity,
                                                                                                        groupUid: groupUid,
                                                                                                        groupOwner: groupOwner.cryptoIdentity,
                                                                                                        within: obvContext)
                _ = try channelDelegate.post(message, randomizedWith: prng, within: obvContext)
                try obvContext.save(logOnFailure: log)
            } catch let _error {
                error = _error
            }
        }
        guard error == nil else { throw error! }
        
    }
    
    
    public func refreshContactGroupJoined(ownedCryptoId: ObvCryptoId, groupUid: UID, groupOwner: ObvCryptoId) throws {
        
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let protocolDelegate = protocolDelegate else { throw makeError(message: "The protocol delegate is not set") }
        guard let channelDelegate = channelDelegate else { throw makeError(message: "The channel delegate is not set") }

        let log = self.log
        
        let flowId = FlowIdentifier()
        var error: Error?
        createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            do {
                let message = try protocolDelegate.getInitiateGroupMembersQueryMessageForGroupManagementProtocol(groupUid: groupUid, ownedIdentity: ownedCryptoId.cryptoIdentity, groupOwner: groupOwner.cryptoIdentity, within: obvContext)
                _ = try channelDelegate.post(message, randomizedWith: prng, within: obvContext)
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
    public func getWebSocketState(ownedIdentity: ObvCryptoId, completionHander: @escaping (Result<(URLSessionTask.State,TimeInterval?),Error>) -> Void) {
        networkFetchDelegate?.getWebSocketState(ownedIdentity: ownedIdentity.cryptoIdentity, completionHander: completionHander)
    }
    
    /// This method returns a 16 bytes nonce and a serialized encryption key. This is called when sending a message, in order to make it
    /// possible to have a return receipt back.
    public func generateReturnReceiptElements() -> (nonce: Data, key: Data) {
        return returnReceiptSender.generateReturnReceiptElements()
    }
    
    
    public func postReturnReceiptWithElements(_ elements: (nonce: Data, key: Data), andStatus status: Int, forContactCryptoId contactCryptoId: ObvCryptoId, ofOwnedIdentityCryptoId ownedCryptoId: ObvCryptoId) throws {
        
        guard let createContextDelegate = createContextDelegate else {
            os_log("The create context delegate is not set", log: log, type: .fault)
            assert(false)
            return
        }
        
        guard let identityDelegate = identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            assert(false)
            return
        }

        let contactCryptoIdentity = contactCryptoId.cryptoIdentity
        let ownedCryptoIdentity = ownedCryptoId.cryptoIdentity

        let randomFlowId = FlowIdentifier()
        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: randomFlowId) { (obvContext) in
            let deviceUids = try identityDelegate.getDeviceUidsOfContactIdentity(contactCryptoIdentity, ofOwnedIdentity: ownedCryptoIdentity, within: obvContext)
            try returnReceiptSender.postReturnReceiptWithElements(elements, andStatus: status, to: contactCryptoId, ownedCryptoId: ownedCryptoId, withDeviceUids: deviceUids)
        }
        
    }
    
    
    public func decryptPayloadOfObvReturnReceipt(_ obvReturnReceipt: ObvReturnReceipt, usingElements elements: (nonce: Data, key: Data)) throws -> (contactCryptoId: ObvCryptoId, status: Int) {
        return try returnReceiptSender.decryptPayloadOfObvReturnReceipt(obvReturnReceipt, usingElements: elements)
    }
    
    
    public func deleteObvReturnReceipt(_ obvReturnReceipt: ObvReturnReceipt) {
        do {
            try delegateManager.networkFetchDelegate?.sendDeleteReturnReceipt(ownedIdentity: obvReturnReceipt.identity, serverUid: obvReturnReceipt.serverUid)
        } catch let error {
            os_log("Could not delete the ReturnReceipt on server: %{public}@", log: log, type: .error, error.localizedDescription)
        }
    }
    
}

// MARK: - Public API for posting messages

extension ObvEngine {
    
    /// This method posts a message and its attachments to all the specified contacts.
    /// It returns a dictionary where the keys correspond to all the recipients for which the message has been successfully sent. Each value of the disctionnary correspond to a message identifier chosen by this engine. Note that two users on the same server will receive the same message identifier.
    /// - Parameters:
    ///   - messagePayload: The payload of the message.
    ///   - withUserContent: Set this to `true` if the sent message contains user content that can typically be displayed in a user notification. Set this to `false` for e.g. system receipts.
    ///   - attachmentsToSend: An array of attachments to send alongside the message.
    ///   - contactCryptoIds: The set of contacts to whom the message shall be sent.
    ///   - ownedCryptoId: The owned cryptoId sending the message.
    ///   - maxTimeIntervalAndHandler: The time interval  indicates the maximum amount of time this call is allowed to take in order to perform all its tasks (including async tasks). Note that the time does not start until essential expectations have been met. The (optional) associated completion handler is called when the timer starts, i.e., after essential expectations have been met. This essential expectations allow to make sure that the message (and its attachments) will eventually be posted.
    ///   - completionHandler: A completion block, executed when the post has done was is required. Hint : for now, this is only used when calling this method from the share extension, in order to dismiss the share extension on post completion.
    public func post(messagePayload: Data, extendedPayload: Data?, withUserContent: Bool, isVoipMessageForStartingCall: Bool, attachmentsToSend: [ObvAttachmentToSend], toContactIdentitiesWithCryptoId contactCryptoIds: Set<ObvCryptoId>, ofOwnedIdentityWithCryptoId ownedCryptoId: ObvCryptoId, completionHandler: (() -> Void)? = nil) throws -> [ObvCryptoId: Data] {
        
        guard let createContextDelegate = self.createContextDelegate else { throw makeError(message: "The create context delegate is not set") }
        guard let channelDelegate = self.channelDelegate else { throw makeError(message: "The channel delegate is not set") }
        guard let flowDelegate = self.flowDelegate else { throw makeError(message: "The flow delegate is not set") }
        
        
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
                                                         attachments: attachments)

        let flowId = try flowDelegate.startNewFlow(completionHandler: completionHandler)

        var messageIdentifierForContactToWhichTheMessageWasSent = [ObvCryptoId: Data]()

        try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { [weak self] obvContext in
            guard let _self = self else { return }
                
            let messageIdentifiersForToIdentities = try channelDelegate.post(message, randomizedWith: _self.prng, within: obvContext)
            
            try messageIdentifiersForToIdentities.keys.forEach { messageId in
                let attachmentIds = (0..<attachmentsToSend.count).map { AttachmentIdentifier(messageId: messageId, attachmentNumber: $0) }
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
        let messageId = MessageIdentifier(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, uid: uid)
        
        let randomFlowId = FlowIdentifier()
        try networkPostDelegate.cancelPostOfMessage(messageId: messageId, flowId: randomFlowId)
    }
    
    
    public func requestProgressesOfAllOutboxAttachmentsOfMessage(withIdentifier messageIdRaw: Data, ownedCryptoId: ObvCryptoId) throws {
        
        guard let networkPostDelegate = networkPostDelegate else { throw makeError(message: "The network post delegate is not set") }

        guard let uid = UID(uid: messageIdRaw) else { throw ObvEngine.makeError(message: "Could not parse message identifier") }
        let messageId = MessageIdentifier(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, uid: uid)
        
        let randomFlowId = FlowIdentifier()
        try networkPostDelegate.requestProgressesOfAllOutboxAttachmentsOfMessage(withIdentifier: messageId, flowId: randomFlowId)
        
    }
    
}


// MARK: - Public API for receiving messages

extension ObvEngine {
    
    
    public func deleteObvAttachment(attachmentNumber: Int, ofMessageWithIdentifier messageIdRaw: Data, ownedCryptoId: ObvCryptoId) throws {
        
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let networkFetchDelegate = networkFetchDelegate else { throw makeError(message: "The network fetch delegate is not set") }
        guard let flowDelegate = flowDelegate else { throw makeError(message: "The flow delegate is not set") }

        guard let uid = UID(uid: messageIdRaw) else { throw ObvEngine.makeError(message: "Could not parse message id") }
        let messageId = MessageIdentifier(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, uid: uid)
        let attachmentId = AttachmentIdentifier(messageId: messageId, attachmentNumber: attachmentNumber)

        guard let flowId = flowDelegate.startBackgroundActivityForDeletingAnAttachment(attachmentId: attachmentId) else { throw NSError() }
                
        var error: Error?
        createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            do {
                networkFetchDelegate.markAttachmentForDeletion(attachmentId: attachmentId, within: obvContext)
                try obvContext.save(logOnFailure: log)
            } catch let _error {
                error = _error
            }
        }
        guard error == nil else {
            throw error!
        }
        
    }
    
    
    public func delete(attachmentNumber: Int, ofMessageWithIdentifier messageIdRaw: Data, ownedCryptoId: ObvCryptoId) throws {
        
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let networkFetchDelegate = networkFetchDelegate else { throw makeError(message: "The network fetch delegate is not set") }
        guard let flowDelegate = flowDelegate else { throw makeError(message: "The flow delegate is not set") }
        
        guard let uid = UID(uid: messageIdRaw) else { throw ObvEngine.makeError(message: "Could not parse message id") }
        let messageId = MessageIdentifier(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, uid: uid)
        let attachmentId = AttachmentIdentifier(messageId: messageId, attachmentNumber: attachmentNumber)
        
        guard let flowId = flowDelegate.startBackgroundActivityForDeletingAnAttachment(attachmentId: attachmentId) else { throw NSError() }
        var error: Error?
        createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            do {
                networkFetchDelegate.markAttachmentForDeletion(attachmentId: attachmentId, within: obvContext)
                try obvContext.save(logOnFailure: log)
            } catch let _error {
                error = _error
            }
        }
        guard error == nil else {
            throw error!
        }

    }

    
    func getRefreshedObvAttachment(attachmentId: AttachmentIdentifier) throws -> ObvAttachment {
        
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let networkFetchDelegate = networkFetchDelegate else { throw makeError(message: "The network fetch delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identity delegate is not set") }
        
        var refreshedObvAttachment: ObvAttachment!
        var error: Error?
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
            do {
                refreshedObvAttachment = try ObvAttachment(attachmentId: attachmentId,
                                                           networkFetchDelegate: networkFetchDelegate,
                                                           identityDelegate: identityDelegate,
                                                           within: obvContext)
            } catch let _error {
                error = _error
            }
        }
        guard error == nil else {
            throw error!
        }
        return refreshedObvAttachment
    }
    
    
    public func downloadAllMessagesForOwnedIdentities() {
        
        guard let createContextDelegate = createContextDelegate else { assertionFailure(); return }
        guard let networkFetchDelegate = networkFetchDelegate else { assertionFailure(); return }
        guard let flowDelegate = flowDelegate else { assertionFailure(); return }
        guard let identityDelegate = identityDelegate else { assertionFailure(); return }

        let log = self.log
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: randomFlowId) { (obvContext) in
            do {
                guard let ownedIdentities = try? identityDelegate.getOwnedIdentities(within: obvContext) else { throw NSError() }
                try ownedIdentities.forEach { (ownedIdentity) in
                    guard let flowId = flowDelegate.startBackgroundActivityForDownloadingMessages(ownedIdentity: ownedIdentity) else { throw NSError() }
                    if let currentDeviceUid = try? identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext) {
                        networkFetchDelegate.downloadMessages(for: ownedIdentity, andDeviceUid: currentDeviceUid, flowId: flowId)
                    }
                }
            } catch {
                os_log("Could not download all messages for owned identities", log: log, type: .fault)
            }
        }
    }
    
    
    public func cancelDownloadOfMessage(withIdentifier messageIdRaw: Data, ownedCryptoId: ObvCryptoId) throws {
        
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let networkFetchDelegate = networkFetchDelegate else { throw makeError(message: "The network fetch delegate is not set") }
        guard let flowDelegate = flowDelegate else { throw makeError(message: "The flow delegate is not set") }
        
        guard let uid = UID(uid: messageIdRaw) else { throw ObvEngine.makeError(message: "Could not parse message id") }
        let messageId = MessageIdentifier(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, uid: uid)
        
        guard let flowId = flowDelegate.startBackgroundActivityForDeletingAMessage(messageId: messageId) else { throw NSError() }
        var error: Error?
        createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            obvContext.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump // In-memory changes (made here) trump (override) external (made elsewhere) changes. We do want to delete the message.
            do {
                networkFetchDelegate.deleteMessageAndAttachments(messageId: messageId, within: obvContext)
                try obvContext.save(logOnFailure: log)
            } catch let _error {
                error = _error
            }
        }
        guard error == nil else {
            throw error!
        }

    }
    
    
    public func requestProgressesOfAllInboxAttachmentsOfMessage(withIdentifier messageIdRaw: Data, ownedCryptoId: ObvCryptoId) throws {
        
        guard let networkFetchDelegate = networkFetchDelegate else { throw makeError(message: "The network fetch delegate is not set") }
        
        guard let uid = UID(uid: messageIdRaw) else { throw ObvEngine.makeError(message: "Could not parse message identifier") }
        let messageId = MessageIdentifier(ownedCryptoIdentity: ownedCryptoId.cryptoIdentity, uid: uid)
        
        let randomFlowId = FlowIdentifier()
        networkFetchDelegate.requestProgressesOfAllInboxAttachmentsOfMessage(withIdentifier: messageId, flowId: randomFlowId)
        
    }
}

// MARK: - Public API for Downloading Files in the Background, remote notifications, and background fetches

extension ObvEngine {
    
    public func storeCompletionHandler(_ handler: @escaping () -> Void, forHandlingEventsForBackgroundURLSessionWithIdentifier backgroundURLSessionIdentifier: String) {
        
        let flowId = FlowIdentifier()
        
        guard let networkPostDelegate = networkPostDelegate else {
            os_log("The network post delegate is not set", log: log, type: .fault)
            return
        }

        guard let networkFetchDelegate = networkFetchDelegate else {
            os_log("The network fetch delegate is not set", log: log, type: .fault)
            return
        }

        if networkPostDelegate.backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: backgroundURLSessionIdentifier) {
            os_log("The background URLSession Identifier %{public}@ is appropriate for the Network Post Delegate", log: log, type: .info, backgroundURLSessionIdentifier)
            networkPostDelegate.storeCompletionHandler(handler, forHandlingEventsForBackgroundURLSessionWithIdentifier: backgroundURLSessionIdentifier, withinFlowId: flowId)
        }
        
        if networkFetchDelegate.backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: backgroundURLSessionIdentifier) {
            os_log("The background URLSession Identifier %{public}@ is appropriate for the Network Fetch Delegate", log: log, type: .info, backgroundURLSessionIdentifier)
            networkFetchDelegate.processCompletionHandler(handler, forHandlingEventsForBackgroundURLSessionWithIdentifier: backgroundURLSessionIdentifier, withinFlowId: flowId)
        }
        
        if returnReceiptSender.backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: backgroundURLSessionIdentifier) {
            os_log("The background URLSession Identifier %{public}@ is appropriate for the Return Receipt Sender", log: log, type: .info, backgroundURLSessionIdentifier)
            self.returnReceiptSender.storeCompletionHandler(handler, forHandlingEventsForBackgroundURLSessionWithIdentifier: backgroundURLSessionIdentifier)
        }
    }

    
    public func application(didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        
        application(performFetchWithCompletionHandler: completionHandler)
        
    }

    
    public func application(performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        
        assert(!Thread.current.isMainThread)
        
        os_log("🌊 Call to the engine application(performFetchWithCompletionHandler:) method", log: log, type: .info)

        guard let flowDelegate = flowDelegate else {
            os_log("The flow delegate is not set", log: log, type: .fault)
            completionHandler(.failed)
            return
        }
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            completionHandler(.failed)
            return
        }
        
        guard let createContextDelegate = delegateManager.createContextDelegate else {
            os_log("The create context delegate is not set", log: log, type: .fault)
            completionHandler(.failed)
            return
        }
        
        guard let networkFetchDelegate = delegateManager.networkFetchDelegate else {
            os_log("The network Fetch Delegate is not set", log: log, type: .fault)
            completionHandler(.failed)
            return
        }
        
        // For now, we only handle the case where there is not more than one identity
        
        var ownedIdentity: ObvCryptoIdentity!
        var currentDeviceUid: UID!
        var error: Error?
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
            guard let identities = try? identityDelegate.getOwnedIdentities(within: obvContext) else {
                os_log("Could not get owned identities", log: log, type: .fault)
                completionHandler(.failed)
                error = NSError()
                return
            }
            switch identities.count {
            case 0:
                os_log("There is no owned identity", log: log, type: .error)
                completionHandler(.failed)
                error = NSError()
            case 1:
                ownedIdentity = identities.first!
                do {
                    currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
                } catch let _error {
                    os_log("Could not get current device uid", log: log, type: .fault)
                    completionHandler(.failed)
                    error = _error
                }
            default:
                os_log("For now, we only handle the case where there one, and only one owned identity", log: log, type: .fault)
                completionHandler(.failed)
                error = NSError()
            }
        }
        guard error == nil else {
            completionHandler(.failed)
            return
        }
        
        // If we reach this point, we found the owned identity concerned by the silent push notification. We can store the completion handler and ask the network fetch delegate to download her message(s).
        
        os_log("🌊 Will start a background activity for handling the remote notification", log: log, type: .info)
        
        let flowId: FlowIdentifier
        do {
            flowId = try flowDelegate.startBackgroundActivityForHandlingRemoteNotification(withCompletionHandler: completionHandler)
        } catch {
            completionHandler(.failed)
            assertionFailure()
            return
        }
        
        os_log("🌊🌊 Completion handler created within flow %{public}@", log: log, type: .info, flowId.debugDescription)
        
        networkFetchDelegate.downloadMessages(for: ownedIdentity,
                                              andDeviceUid: currentDeviceUid,
                                              flowId: flowId)

    }
    
}


// MARK: - Public API for Decrypting application messages

extension ObvEngine {
    
    public func decrypt(encryptedPushNotification encryptedNotification: EncryptedPushNotification) throws -> ObvMessage {
        
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The context delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identity delegate is not set") }
        guard let channelDelegate = channelDelegate else { throw makeError(message: "The channel delegate is not set") }
        guard let networkFetchDelegate = networkFetchDelegate else { throw makeError(message: "The network fetch delegate is not set") }

        let dummyFlowId = FlowIdentifier()

        var obvMessage: ObvMessage?
        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in

            let _ownedIdentity: ObvCryptoIdentity?
            do {
                _ownedIdentity = try identityDelegate.getOwnedIdentityAssociatedToMaskingUID(encryptedNotification.maskingUID, within: obvContext)
            } catch {
                os_log("The call to getOwnedIdentityAssociatedToMaskingUID failed: %{public}@", log: log, type: .fault, error.localizedDescription)
                return
            }
            
            guard let ownedIdentity = _ownedIdentity else {
                os_log("We could not find an appropriate owned identity associated to the masking UID", log: log, type: .error)
                return
            }

            let messageId = MessageIdentifier(ownedCryptoIdentity: ownedIdentity, uid: encryptedNotification.messageIdFromServer)
            let encryptedMessage = ObvNetworkReceivedMessageEncrypted(
                messageId: messageId,
                messageUploadTimestampFromServer: encryptedNotification.messageUploadTimestampFromServer,
                downloadTimestampFromServer: encryptedNotification.messageUploadTimestampFromServer, /// Encrypted notifications do no have access to a download timestamp from server
                localDownloadTimestamp: encryptedNotification.localDownloadTimestamp,
                encryptedContent: encryptedNotification.encryptedContent,
                wrappedKey: encryptedNotification.wrappedKey,
                attachmentCount: 0,
                hasEncryptedExtendedMessagePayload: false)
            let decryptedMessage: ObvNetworkReceivedMessageDecrypted
            do {
                decryptedMessage = try channelDelegate.decrypt(encryptedMessage, within: dummyFlowId)
            } catch {
                os_log("The channel delegate failed to decrypt the encrypted message", log: log, type: .error)
                return
            }

            do {
                obvMessage = try ObvMessage(networkReceivedMessage: decryptedMessage, networkFetchDelegate: networkFetchDelegate, identityDelegate: identityDelegate, within: obvContext)
            } catch {
                os_log("Could not decrypt the encrypted content", log: log, type: .fault)
                return
            }
        }

        guard obvMessage != nil else {
            os_log("Failed to return a decrypted obvMessage", log: log, type: .error)
            throw makeError(message: "Cannot return a decrypted ObvMessage")
        }
        return obvMessage!
        
    }
    
}


// MARK: - Public API for notifying the various delegates of the App state

extension ObvEngine {
    
    public func applicationIsInitializedAndActive() {
        let flowId = FlowIdentifier()
        applicationDidStartRunning(flowId: flowId)
    }

    
    public func applicationDidStartRunning(flowId: FlowIdentifier) {
        queueForPerformingBootstrapMethods.async { [weak self] in
            guard let _self = self else { return }
            for manager in _self.delegateManager.registeredManagers {
                manager.applicationDidStartRunning(flowId: flowId)
            }
        }
    }
    
    public func applicationDidEnterBackground() {
        queueForPerformingBootstrapMethods.async { [weak self] in
            guard let _self = self else { return }
            for manager in _self.delegateManager.registeredManagers {
                manager.applicationDidEnterBackground()
            }
        }
    }
    
    
    /// This method allows to immediately download all messages from the server, for all owned identities, and connect all websockets.
    public func downloadMessagesAndConnectWebsockets() throws {

        guard let createContextDelegate = createContextDelegate else { assertionFailure(); throw ObvEngine.makeError(message: "Create Context Delegate is not set") }
        guard let identityDelegate = identityDelegate else { assertionFailure(); throw makeError(message: "The identityDelegate is not set") }
        guard let networkFetchDelegate = networkFetchDelegate else { assertionFailure(); throw makeError(message: "The networkFetchDelegate is not set") }
        let log = self.log

        queueForPerformingBootstrapMethods.async {

            let flowId = FlowIdentifier()
            
            networkFetchDelegate.connectWebsockets(flowId: flowId)
            
            createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { obvContext in
            
                do {
                    let ownedidentities = try identityDelegate.getOwnedIdentities(within: obvContext)
                    try ownedidentities.forEach { ownedidentity in
                        let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedidentity, within: obvContext)
                        networkFetchDelegate.downloadMessages(for: ownedidentity, andDeviceUid: currentDeviceUid, flowId: obvContext.flowId)
                    }
                } catch {
                    os_log("Could not download all messages for all identities: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    return
                }
                
            }
            
        }
    }
    
    
    public func disconnectWebsockets() throws {
        
        guard let networkFetchDelegate = networkFetchDelegate else { assertionFailure(); throw makeError(message: "The networkFetchDelegate is not set") }

        queueForPerformingBootstrapMethods.async {
            let flowId = FlowIdentifier()
            networkFetchDelegate.disconnectWebsockets(flowId: flowId)
        }
        
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
    
    
    public func markBackupAsUploaded(backupKeyUid: UID, backupVersion: Int) throws {
        let flowId = FlowIdentifier()
        try backupDelegate?.markBackupAsUploaded(backupKeyUid: backupKeyUid, backupVersion: backupVersion, flowId: flowId)
    }

    
    public func markBackupAsExported(backupKeyUid: UID, backupVersion: Int) throws {
        let flowId = FlowIdentifier()
        try backupDelegate?.markBackupAsExported(backupKeyUid: backupKeyUid, backupVersion: backupVersion, flowId: flowId)
    }
    
    
    public func markBackupAsFailed(backupKeyUid: UID, backupVersion: Int) throws {
        let flowId = FlowIdentifier()
        try backupDelegate?.markBackupAsFailed(backupKeyUid: backupKeyUid, backupVersion: backupVersion, flowId: flowId)
    }
    
    
    public func getCurrentBackupKeyInformation() throws -> ObvBackupKeyInformation? {
        
        guard let backupDelegate = self.backupDelegate else {
            os_log("The backup delegate is not set", log: log, type: .fault)
            assertionFailure()
            throw ObvEngine.makeError(message: "Internal error")
        }

        let flowId = FlowIdentifier()
                    
        let obvBackupKeyInformation: ObvBackupKeyInformation
        do {
            guard let backupKeyInformation = try backupDelegate.getBackupKeyInformation(flowId: flowId) else { return nil }
            obvBackupKeyInformation = ObvBackupKeyInformation(backupKeyInformation: backupKeyInformation)
        } catch let error {
            os_log("Could not get backup key information: %{public}@", log: log, type: .fault, error.localizedDescription)
            throw error
        }
        
        return obvBackupKeyInformation
    }
    
    
    public func generateNewBackupKey() {
        
        let flowId = FlowIdentifier()
        os_log("Generating a new backup key within flow %{public}@", log: log, type: .info, flowId.debugDescription)
        
        guard let backupDelegate = self.backupDelegate else {
            os_log("The backup delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        backupDelegate.generateNewBackupKey(flowId: flowId)
    }
    
    
    public func verifyBackupKeyString(_ backupSeedString: String, completion: @escaping (Result<Void,Error>) -> Void) throws {
        
        guard let backupDelegate = self.backupDelegate else {
            os_log("The backup delegate is not set", log: log, type: .fault)
            assertionFailure()
            throw ObvEngine.makeError(message: "Internal error")
        }

        let flowId = FlowIdentifier()

        backupDelegate.verifyBackupKey(backupSeedString: backupSeedString, flowId: flowId, completion: completion)
        
    }


    public func initiateBackup(forExport: Bool, requestUUID: UUID) {
        let flowId = requestUUID
        os_log("Starting backup within flow %{public}@", log: log, type: .info, flowId.debugDescription)
        try? backupDelegate?.initiateBackup(forExport: forExport, backupRequestIdentifier: flowId)
    }

    
    public func getAcceptableCharactersForBackupKeyString() -> CharacterSet {
        return BackupSeed.acceptableCharacters
    }
    
    public func recoverBackupData(_ backupData: Data, withBackupKey backupKey: String, completion: @escaping (Result<(backupRequestIdentifier: UUID, backupDate: Date),BackupRestoreError>) -> Void) throws {
        
        guard let backupDelegate = self.backupDelegate else {
            assertionFailure()
            throw makeError(message: "The backup delegate is not set")
        }

        let backupRequestIdentifier = FlowIdentifier()
        os_log("Starting backup decryption with backup identifier %{public}@", log: log, type: .info, backupRequestIdentifier.debugDescription)

        DispatchQueue(label: "Queue for recovering backup data").async {
            backupDelegate.recoverBackupData(backupData, withBackupKey: backupKey, backupRequestIdentifier: backupRequestIdentifier, completion: completion)
        }
        
    }
    
    
    public func restoreFullBackup(backupRequestIdentifier: FlowIdentifier, completionHandler: @escaping ((Result<Void,Error>) -> Void)) throws {
        
        os_log("Starting backup restore identified by %{public}@", log: log, type: .info, backupRequestIdentifier.debugDescription)
        
        guard let backupDelegate = self.backupDelegate else {
            assertionFailure()
            throw makeError(message: "The backup delegate is not set")
        }
        
        DispatchQueue(label: "Background queue for restoring a backup within the engine").async {
            backupDelegate.restoreFullBackup(backupRequestIdentifier: backupRequestIdentifier, completionHandler: completionHandler)
        }
        
    }
    
    public func registerAppBackupableObject(_ appBackupableObject: ObvBackupable) throws {
        guard let backupDelegate = self.backupDelegate else {
            os_log("The backup delegate is not set", log: log, type: .fault)
            assertionFailure()
            throw ObvEngine.makeError(message: "Internal error")
        }
        backupDelegate.registerAppBackupableObject(appBackupableObject)
    }
    
}

// MARK: - Public API for User Data

extension ObvEngine {

    /// This is called when restoring a backup and after the migration to the first Olvid version that supports profile pictures
    public func downloadAllUserData() throws {
        
        guard let flowDelegate = flowDelegate else { throw ObvEngine.makeError(message: "The flow delegate is not set") }
        guard let createContextDelegate = createContextDelegate else { throw ObvEngine.makeError(message: "Create Context Delegate is not set") }
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identityDelegate is not set") }

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
        guard let protocolDelegate = protocolDelegate else { throw makeError(message: "The protocol delegate is not set") }
        guard let channelDelegate = channelDelegate else { throw ObvEngine.makeError(message: "Channel Delegate is not set") }
        let message = try protocolDelegate.getInitialMessageForDownloadIdentityPhotoChildProtocol(ownedIdentity: ownedIdentity,
                                                                                                  contactIdentity: contactIdentity,
                                                                                                  contactIdentityDetailsElements: contactIdentityDetailsElements)
        _ = try channelDelegate.post(message, randomizedWith: prng, within: obvContext)
    }

    
    public func startDownloadGroupPhotoProtocolWithinTransaction(within obvContext: ObvContext, ownedIdentity: ObvCryptoIdentity, groupInformation: GroupInformation) throws {
        guard let protocolDelegate = protocolDelegate else { throw makeError(message: "The protocol delegate is not set") }
        guard let channelDelegate = channelDelegate else { throw ObvEngine.makeError(message: "Channel Delegate is not set") }
        let message = try protocolDelegate.getInitialMessageForDownloadGroupPhotoChildProtocol(ownedIdentity: ownedIdentity, groupInformation: groupInformation)
        _ = try channelDelegate.post(message, randomizedWith: prng, within: obvContext)
    }

}


// MARK: - Public API for Webrtc

extension ObvEngine {
    
    public func getTurnCredentials(ownedIdenty: ObvCryptoId, callUuid: UUID) {
        let flowId = FlowIdentifier()
        networkFetchDelegate?.getTurnCredentials(ownedIdenty: ownedIdenty.cryptoIdentity, callUuid: callUuid, username1: "alice", username2: "bob", flowId: flowId)
    }
    
}


// MARK: - Misc

extension ObvEngine {
    
    public func getServerAPIVersion() -> Int {
        return ObvServerInterfaceConstants.serverAPIVersion
    }
    
    
    public func computeTagForOwnedIdentity(with ownedIdentityCryptoId: ObvCryptoId, on data: Data) throws -> Data {
        guard let createContextDelegate = createContextDelegate else { throw makeError(message: "The createContextDelegate is not set") }
        guard let identityDelegate = identityDelegate else { throw makeError(message: "The identityDelegate is not set") }
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
