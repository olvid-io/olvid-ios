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
    
    public func forceRegisterToPushNotification(identity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        os_log("forceRegisterToPushNotification does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func updatedListOfOwnedIdentites(ownedIdentities: Set<ObvCryptoIdentity>, flowId: FlowIdentifier) {
        os_log("updatedListOfOwnedIdentites does nothing in this dummy implementation", log: log, type: .error)
    }

    public func queryServerWellKnown(serverURL: URL, flowId: FlowIdentifier) {
        os_log("queryServerWellKnown does nothing in this dummy implementation", log: log, type: .error)
    }

    public func verifyReceipt(ownedIdentity: ObvCryptoIdentity, receiptData: String, transactionIdentifier: String, flowId: FlowIdentifier) {
        os_log("verifyReceipt does nothing in this dummy implementation", log: log, type: .error)
    }
    public func queryFreeTrial(for identity: ObvCryptoIdentity, retrieveAPIKey: Bool, flowId: FlowIdentifier) {
        os_log("queryFreeTrial does nothing in this dummy implementation", log: log, type: .error)
    }

    public func resetServerSession(for identity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        os_log("resetServerSession does nothing in this dummy implementation", log: log, type: .error)
    }

    public func queryAPIKeyStatus(for identity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier) {
        os_log("queryAPIKeyStatus does nothing in this dummy implementation", log: log, type: .error)
    }

    public func getTurnCredentials(ownedIdenty: ObvCryptoIdentity, callUuid: UUID, username1: String, username2: String, flowId: FlowIdentifier) {
        os_log("getTurnCredentials does nothing in this dummy implementation", log: log, type: .error)
    }

    public func getWebSocketState(ownedIdentity: ObvCryptoIdentity, completionHander: @escaping (Result<(URLSessionTask.State, TimeInterval?), Error>) -> Void) {
        os_log("getWebSocketState does nothing in this dummy implementation", log: log, type: .error)
    }

    public func connectWebsockets(flowId: FlowIdentifier) {
        os_log("connectWebsockets does nothing in this dummy implementation", log: log, type: .error)
    }

    public func disconnectWebsockets(flowId: FlowIdentifier) {
        os_log("disconnectWebsockets does nothing in this dummy implementation", log: log, type: .error)
    }

    public func downloadMessages(for ownedIdentity: ObvCryptoIdentity, andDeviceUid deviceUid: UID, flowId: FlowIdentifier) {
        os_log("downloadMessages(for: ObvCryptoIdentity, andDeviceUid: UID, flowId: FlowIdentifier) does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func getEncryptedMessage(messageId: MessageIdentifier, flowId: FlowIdentifier) -> ObvNetworkReceivedMessageEncrypted? {
        os_log("getEncryptedMessage(messageId: MessageIdentifier) does nothing in this dummy implementation", log: log, type: .error)
        return nil
    }
    
    public func getDecryptedMessage(messageId: MessageIdentifier, flowId: FlowIdentifier) -> ObvNetworkReceivedMessageDecrypted? {
        os_log("getDecryptedMessage(messageId: MessageIdentifier) does nothing in this dummy implementation", log: log, type: .error)
        return nil
    }
    
    public func allAttachmentsCanBeDownloadedForMessage(withId: MessageIdentifier, within: ObvContext) throws -> Bool {
        os_log("allAttachmentsCanBeDownloadedForMessage(withId: MessageIdentifier, within: ObvContext) does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "allAttachmentsCanBeDownloadedForMessage(withId: MessageIdentifier, within: ObvContext) does nothing in this dummy implementation")
    }
    
    public func allAttachmentsHaveBeenDownloadedForMessage(withId: MessageIdentifier, within: ObvContext) throws -> Bool {
        os_log("allAttachmentsHaveBeenDownloadedForMessage(withId: MessageIdentifier, within: ObvContext) does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "allAttachmentsHaveBeenDownloadedForMessage(withId: MessageIdentifier, within: ObvContext) does nothing in this dummy implementation")
    }
    
    public func attachment(withId: AttachmentIdentifier, canBeDownloadedwithin: ObvContext) throws -> Bool {
        os_log("attachment(withId: AttachmentIdentifier, canBeDownloadedwithin: ObvContext) does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "attachment(withId: AttachmentIdentifier, canBeDownloadedwithin: ObvContext) does nothing in this dummy implementation")
    }
    
    public func set(remoteCryptoIdentity: ObvCryptoIdentity, messagePayload: Data, extendedMessagePayloadKey: AuthenticatedEncryptionKey?, andAttachmentsInfos: [ObvNetworkFetchAttachmentInfos], forApplicationMessageWithmessageId: MessageIdentifier, within obvContext: ObvContext) throws {
        os_log("set(remoteCryptoIdentity: ObvCryptoIdentity, messagePayload: Data, andAttachmentsInfos: [ObvNetworkFetchAttachmentInfos], forApplicationMessageWithMessageId: MessageIdentifier, within obvContext: ObvContext) does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "set(remoteCryptoIdentity: ObvCryptoIdentity, messagePayload: Data, andAttachmentsInfos: [ObvNetworkFetchAttachmentInfos], forApplicationMessageWithMessageId: MessageIdentifier, within obvContext: ObvContext) does nothing in this dummy implementation")
    }
    
    public func getAttachment(withId attachmentId: AttachmentIdentifier, within obvContext: ObvContext) -> ObvNetworkFetchReceivedAttachment? {
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
    
    public func deleteMessageAndAttachments(messageId: MessageIdentifier, within: ObvContext) {
        os_log("deleteMessageAndAttachments(messageId: MessageIdentifier, within: ObvContext) does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func markMessageForDeletion(messageId: MessageIdentifier, within: ObvContext) {
        os_log("markMessageForDeletion(messageId: MessageIdentifier, within: ObvContext) does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func markAttachmentForDeletion(attachmentId: AttachmentIdentifier, within: ObvContext) {
        os_log("markAttachmentForDeletion(attachmentId: AttachmentIdentifier, within: ObvContext) does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func resumeDownloadOfAttachment(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier) {
        os_log("resumeDownloadOfAttachment does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func pauseDownloadOfAttachment(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier) {
        os_log("pauseDownloadOfAttachment does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func requestDownloadAttachmentProgressesUpdatedSince(date: Date) async throws -> [AttachmentIdentifier: Float] {
        os_log("requestDownloadAttachmentProgressesUpdatedSince does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "requestDownloadAttachmentProgressesUpdatedSince does nothing in this dummy implementation")
    }
    
    public func register(pushNotificationType: ObvPushNotificationType, for: ObvCryptoIdentity, withDeviceUid: UID, within: ObvContext) {
        os_log("register(pushNotificationType: ObvPushNotificationType, for: ObvCryptoIdentity, withDeviceUid: UID, within: ObvContext) does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func registerIfRequired(pushNotificationType: ObvPushNotificationType, for: ObvCryptoIdentity, withDeviceUid: UID, within: ObvContext) {
        os_log("registerIfRequired(pushNotificationType: ObvPushNotificationType, for: ObvCryptoIdentity, withDeviceUid: UID, within: ObvContext) does nothing in this dummy implementation", log: log, type: .debug)
    }
    
    public func unregisterPushNotification(for: ObvCryptoIdentity, within: ObvContext) {
        os_log("unregisterPushNotification(for: ObvCryptoIdentity, within: ObvContext) does nothing in this dummy implementation", log: log, type: .error)
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

    // MARK: - Implementing ObvManager
    
    public let requiredDelegates = [ObvEngineDelegateType]()
    
    public func fulfill(requiredDelegate: AnyObject, forDelegateType: ObvEngineDelegateType) throws {}
    
    public func finalizeInitialization(flowId: FlowIdentifier, runningLog: RunningLogError) throws {}
    
    
}
