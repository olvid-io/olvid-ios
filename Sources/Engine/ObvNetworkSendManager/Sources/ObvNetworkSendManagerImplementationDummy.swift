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
import ObvTypes
import OlvidUtils
import ObvCrypto


public final class ObvNetworkSendManagerImplementationDummy: ObvNetworkPostDelegate, ObvErrorMaker {
    
    static let defaultLogSubsystem = "io.olvid.network.send.dummy"
    lazy public var logSubsystem: String = {
        return ObvNetworkSendManagerImplementationDummy.defaultLogSubsystem
    }()

    public func prependLogSubsystem(with prefix: String) {
        logSubsystem = "\(prefix).\(logSubsystem)"
        self.log = OSLog(subsystem: logSubsystem, category: "ObvNetworkFetchManagerImplementationDummy")
    }

    public func applicationAppearedOnScreen(forTheFirstTime: Bool, flowId: FlowIdentifier) async {}

    public static let errorDomain = "ObvNetworkSendManagerImplementationDummy"
    
    // MARK: Instance variables
    
    private var log: OSLog

    // MARK: Initialiser
    
    public init() {
        self.log = OSLog(subsystem: ObvNetworkSendManagerImplementationDummy.defaultLogSubsystem, category: "ObvNetworkSendManagerImplementationDummy")
    }

    
    public func post(_: ObvNetworkMessageToSend, within: ObvContext) throws {
        os_log("post(_: ObvNetworkMessageToSend, within: ObvContext) does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func cancelPostOfMessage(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) throws {
        os_log("cancelPostOfMessage(messageId: MessageIdentifier) does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func storeCompletionHandler(_: @escaping () -> Void, forHandlingEventsForBackgroundURLSessionWithIdentifier: String, withinFlowId: FlowIdentifier) {
        os_log("storeCompletionHandler(...) does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: String) -> Bool {
        os_log("backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: String) does nothing in this dummy implementation", log: log, type: .error)
        return false
    }
    
    public func requestUploadAttachmentProgressesUpdatedSince(date: Date) async throws -> [ObvAttachmentIdentifier: Float] {
        os_log("requestUploadAttachmentProgressesUpdatedSince does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "requestUploadAttachmentProgressesUpdatedSince does nothing in this dummy implementation")
    }
    
    public func prepareForOwnedIdentityDeletion(ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        os_log("prepareForOwnedIdentityDeletion does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "prepareForOwnedIdentityDeletion does nothing in this dummy implementation")
    }
        
    // MARK: - Implementing ObvManager

    public var requiredDelegates = [ObvEngineDelegateType]()

    public func fulfill(requiredDelegate: AnyObject, forDelegateType: ObvEngineDelegateType) throws {}
    
    public func finalizeInitialization(flowId: FlowIdentifier, runningLog: RunningLogError) throws {}
    
    public func replayTransactionsHistory(transactions: [NSPersistentHistoryTransaction], within: ObvContext) {}
    
    public func deleteHistoryConcerningTheAcknowledgementOfOutboxMessage(messageIdentifier: ObvMessageIdentifier, flowId: FlowIdentifier) async {}

    public func deleteHistoryConcerningTheAcknowledgementOfOutboxMessages(withTimestampFromServerEarlierOrEqualTo referenceDate: Date, flowId: FlowIdentifier) async {}

}
