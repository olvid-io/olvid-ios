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
import ObvMetaManager
import ObvCrypto
import ObvTypes
import OlvidUtils


public final class ObvNetworkFetchManagerImplementationDummy: ObvNetworkFetchDelegate, ObvErrorMaker {
    
    public static var errorDomain = "ObvNetworkFetchManagerImplementationDummy"
    static let defaultLogSubsystem = "io.olvid.network.fetch.dummy"
    lazy public var logSubsystem: String = {
        return ObvNetworkFetchManagerImplementationDummy.defaultLogSubsystem
    }()
    
    public func prependLogSubsystem(with prefix: String) {
        logSubsystem = "\(prefix).\(logSubsystem)"
        self.log = OSLog(subsystem: logSubsystem, category: "ObvNetworkFetchManagerImplementationDummy")
    }

    public func applicationAppearedOnScreen(forTheFirstTime: Bool, flowId: FlowIdentifier) async {}

    // MARK: Instance variables
    
    private var log: OSLog

    // MARK: Initialiser

    public init() {
        self.log = OSLog(subsystem: ObvNetworkFetchManagerImplementationDummy.defaultLogSubsystem, category: "ObvNetworkFetchManagerImplementationDummy")
    }
    
    public func registerOwnedAPIKeyOnServerNow(ownedCryptoIdentity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier) async throws -> ObvRegisterApiKeyResult {
        os_log("registerOwnedAPIKeyOnServerNow does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "registerOwnedAPIKeyOnServerNow does nothing in this dummy implementation")
    }
    
    public func registerPushNotification(_ pushNotification: ObvPushNotificationType, flowId: FlowIdentifier) {
        os_log("registerPushNotification does nothing in this dummy implementation", log: log, type: .error)
    }

    public func updatedListOfOwnedIdentites(activeOwnedCryptoIdsAndCurrentDeviceUIDs: Set<OwnedCryptoIdentityAndCurrentDeviceUID>, flowId: FlowIdentifier) async throws {
        os_log("updatedListOfOwnedIdentites does nothing in this dummy implementation", log: log, type: .error)
    }

    public func queryServerWellKnown(serverURL: URL, flowId: FlowIdentifier) {
        os_log("queryServerWellKnown does nothing in this dummy implementation", log: log, type: .error)
    }

    public func verifyReceiptAndRefreshAPIPermissions(appStoreReceiptElements: ObvAppStoreReceipt, flowId: FlowIdentifier) async throws -> [ObvCryptoIdentity : ObvAppStoreReceipt.VerificationStatus] {
        os_log("verifyReceiptAndRefreshAPIPermissions does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "verifyReceiptAndRefreshAPIPermissions does nothing in this dummy implementation")
    }

    public func queryFreeTrial(for identity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> Bool {
        os_log("queryFreeTrial does nothing in this dummy implementation", log: log, type: .error)
        return true
    }

    public func startFreeTrial(for identity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> APIKeyElements {
        os_log("startFreeTrial does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "startFreeTrial does nothing in this dummy implementation")
    }
    
    public func refreshAPIPermissions(of ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> APIKeyElements {
        os_log("refreshAPIPermissions does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "refreshAPIPermissions does nothing in this dummy implementation")
    }

    public func queryAPIKeyStatus(for identity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier) async throws -> APIKeyElements {
        os_log("queryAPIKeyStatus does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "queryAPIKeyStatus does nothing in this dummy implementation")
    }

    public func getTurnCredentials(ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> ObvTurnCredentials {
        os_log("getTurnCredentials does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getTurnCredentials does nothing in this dummy implementation")
    }
    
    public func getWebSocketState(ownedIdentity: ObvCryptoIdentity) async throws -> (state: URLSessionTask.State, pingInterval: TimeInterval?) {
        os_log("getWebSocketState does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getWebSocketState does nothing in this dummy implementation")
    }

    public func connectWebsockets(activeOwnedCryptoIdsAndCurrentDeviceUIDs: Set<OwnedCryptoIdentityAndCurrentDeviceUID>, flowId: FlowIdentifier) async throws {
        os_log("connectWebsockets does nothing in this dummy implementation", log: log, type: .error)
    }

    public func disconnectWebsockets(flowId: FlowIdentifier) {
        os_log("disconnectWebsockets does nothing in this dummy implementation", log: log, type: .error)
    }

    public func downloadMessages(for ownedIdentity: ObvCrypto.ObvCryptoIdentity, flowId: OlvidUtils.FlowIdentifier) async {
        os_log("downloadMessages(for:flowId:) does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func getEncryptedMessage(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) -> ObvNetworkReceivedMessageEncrypted? {
        os_log("getEncryptedMessage(messageId: MessageIdentifier) does nothing in this dummy implementation", log: log, type: .error)
        return nil
    }
    
    public func getDecryptedMessage(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) -> ObvNetworkReceivedMessageDecrypted? {
        os_log("getDecryptedMessage(messageId: MessageIdentifier) does nothing in this dummy implementation", log: log, type: .error)
        return nil
    }
    
    public func allAttachmentsCanBeDownloadedForMessage(withId: ObvMessageIdentifier, within: ObvContext) throws -> Bool {
        os_log("allAttachmentsCanBeDownloadedForMessage(withId: MessageIdentifier, within: ObvContext) does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "allAttachmentsCanBeDownloadedForMessage(withId: MessageIdentifier, within: ObvContext) does nothing in this dummy implementation")
    }
    
    public func allAttachmentsHaveBeenDownloadedForMessage(withId: ObvMessageIdentifier, within: ObvContext) throws -> Bool {
        os_log("allAttachmentsHaveBeenDownloadedForMessage(withId: MessageIdentifier, within: ObvContext) does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "allAttachmentsHaveBeenDownloadedForMessage(withId: MessageIdentifier, within: ObvContext) does nothing in this dummy implementation")
    }
    
    public func attachment(withId: ObvAttachmentIdentifier, canBeDownloadedwithin: ObvContext) throws -> Bool {
        os_log("attachment(withId: AttachmentIdentifier, canBeDownloadedwithin: ObvContext) does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "attachment(withId: AttachmentIdentifier, canBeDownloadedwithin: ObvContext) does nothing in this dummy implementation")
    }
  
    public func getAttachment(withId attachmentId: ObvAttachmentIdentifier, within obvContext: ObvContext) -> ObvNetworkFetchReceivedAttachment? {
        os_log("getAttachment(withId: AttachmentIdentifier) does nothing in this dummy implementation", log: log, type: .error)
        return nil
    }
    
    public func backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: String) -> Bool {
        os_log("backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: String) does nothing in this dummy implementation", log: log, type: .error)
        return false
    }
    
    public func processCompletionHandler(_: @escaping () -> Void, forHandlingEventsForBackgroundURLSessionWithIdentifier: String, withinFlowId: FlowIdentifier) {
        os_log("storeCompletionHandler(_: @escaping () -> Void, forHandlingEventsForBackgroundURLSessionWithIdentifier: String, withinFlowId: FlowIdentifier) does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func deleteApplicationMessageAndAttachments(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) async throws {
        os_log("deleteMessageAndAttachments does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func markApplicationMessageForDeletionAndProcessAttachments(messageId: ObvMessageIdentifier, attachmentsProcessingRequest: ObvAttachmentsProcessingRequest, flowId: FlowIdentifier) async throws {
        os_log("markMessageForDeletion(messageId: MessageIdentifier, within: ObvContext) does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func markAttachmentForDeletion(attachmentId: ObvTypes.ObvAttachmentIdentifier, flowId: OlvidUtils.FlowIdentifier) async throws {
        os_log("markAttachmentForDeletion(attachmentId: AttachmentIdentifier, within: ObvContext) does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func resumeDownloadOfAttachment(attachmentId: ObvTypes.ObvAttachmentIdentifier, flowId: OlvidUtils.FlowIdentifier) async throws {
        os_log("resumeDownloadOfAttachment does nothing in this dummy implementation", log: log, type: .error)
    }

    public func appCouldNotFindFileOfDownloadedAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) async throws {
        os_log("appCouldNotFindFileOfDownloadedAttachment does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func pauseDownloadOfAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) {
        os_log("pauseDownloadOfAttachment does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func requestDownloadAttachmentProgressesUpdatedSince(date: Date) async throws -> [ObvAttachmentIdentifier: Float] {
        os_log("requestDownloadAttachmentProgressesUpdatedSince does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "requestDownloadAttachmentProgressesUpdatedSince does nothing in this dummy implementation")
    }
    
    public func connectWebSocket() {
        os_log("connectWebSocket() does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func disconnectWebSocket() {
        os_log("disconnectWebSocket() does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func sendDeleteReturnReceipt(ownedIdentity: ObvCryptoIdentity, serverUid: UID) throws {
        os_log("sendDeleteReturnReceipt() does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func postServerQuery(_: ServerQuery, within: ObvContext) {
        os_log("postServerQuery(_: ServerQuery, within: ObvContext) does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func prepareForOwnedIdentityDeletion(ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws {
        os_log("prepareForOwnedIdentityDeletion does nothing in this dummy implementation", log: log, type: .error)
    }

    public func finalizeOwnedIdentityDeletion(ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) throws {
        os_log("finalizeOwnedIdentityDeletion does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func performOwnedDeviceDiscoveryNow(ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> EncryptedData {
        os_log("performOwnedDeviceDiscoveryNow does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "performOwnedDeviceDiscoveryNow does nothing in this dummy implementation")
    }
    
    // MARK: - Implementing ObvManager
    
    public let requiredDelegates = [ObvEngineDelegateType]()
    
    public func fulfill(requiredDelegate: AnyObject, forDelegateType: ObvEngineDelegateType) throws {}
    
    public func finalizeInitialization(flowId: FlowIdentifier, runningLog: RunningLogError) throws {}
    
    
}
