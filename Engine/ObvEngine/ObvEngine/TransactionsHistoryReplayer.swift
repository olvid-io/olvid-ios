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
import CoreData
import os.log
import ObvMetaManager
import ObvTypes
import OlvidUtils


final class TransactionsHistoryReplayer {
    
    private static let errorDomain = "TransactionsHistoryReplayer"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    private let sharedContainerIdentifier: String
    private let appType: AppType
    private let internalQueue = DispatchQueue(label: "Internal queue of TransactionsHistoryReplayer")
    weak var networkPostDelegate: ObvNetworkPostDelegate?
    weak var createContextDelegate: ObvCreateContextDelegate?
    
    public var logSubsystem: String = ObvEngine.defaultLogSubsystem
    public func prependLogSubsystem(with prefix: String) {
        logSubsystem = "\(prefix).\(logSubsystem)"
    }
    private lazy var log = OSLog(subsystem: logSubsystem, category: String(describing: TransactionsHistoryReplayer.self))

    private let tokenQueue = DispatchQueue(label: "Internal Queue for accessing _lastHistoryToken")
    
    private let savedHistoryTokensDirectoryName = "HistoryTokens"
    private var savedHistoryTokensFileName: String {
        switch appType {
        case .mainApp: return "tokenForMainApp.data"
        case .notificationExtension: return "tokenForNotificationExtension.data"
        case .shareExtension: return "tokenForShareExtension.data"
        }
    }

    init(sharedContainerIdentifier: String, appType: AppType) {
        self.sharedContainerIdentifier = sharedContainerIdentifier
        self.appType = appType
    }
    
    
    private func readHistoryToken() throws -> NSPersistentHistoryToken? {
        guard let historyTokenURL = getHistoryTokenURL() else { throw TransactionsHistoryReplayer.makeError(message: "Could not get history token URL. Could not try to read the token from disk.") }
        guard FileManager.default.fileExists(atPath: historyTokenURL.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: historyTokenURL)
        } catch {
            // Since the data could not be read, we delete the data
            try? FileManager.default.removeItem(at: historyTokenURL)
            throw error
        }
        do {
            return try NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: data)
        } catch {
            // Since the data could not be read, we delete the data
            try? FileManager.default.removeItem(at: historyTokenURL)
            throw error
        }
    }
    
    
    private func writeHistoryToken(token: NSPersistentHistoryToken) throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        guard let historyTokenURL = getHistoryTokenURL() else { throw TransactionsHistoryReplayer.makeError(message: "Could not get history token URL. Cannot try to save the last history token to disk")}
        try data.write(to: historyTokenURL)
    }
    
    
    
    func replayTransactionsHistory(flowId: FlowIdentifier) throws {
        
        guard let createContextDelegate = self.createContextDelegate else {
            os_log("The create context delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        guard let networkPostDelegate = self.networkPostDelegate else {
            assertionFailure()
            throw TransactionsHistoryReplayer.makeError(message: "The network post delegate is not set")
        }
        
        try internalQueue.sync {
                        
                    
            try createContextDelegate.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
                
                let latestHistoryToken: NSPersistentHistoryToken
                if #available(iOS 12.0, *) {
                    guard let token = createContextDelegate.persistentStoreCoordinator.currentPersistentHistoryToken(fromStores: nil) else { return }
                    latestHistoryToken = token
                } else {
                    guard let token = getCurrentPersistentHistoryTokenUnderIOS11(within: obvContext) else { return }
                    latestHistoryToken = token
                }
            
                guard let savedHistoryToken = try readHistoryToken() else {
                    // This happens the very first time, since the token file does not exists.
                    // So we create the file, purge the history and return.
                    try writeHistoryToken(token: latestHistoryToken)
                    purgeTransactionsHistory(before: latestHistoryToken, within: obvContext)
                    try obvContext.save(logOnFailure: log)
                    return
                }

                // Create a history fetch request
                
                let request: NSPersistentHistoryChangeRequest
                if #available(iOS 13, *) {
                    // Create predicates to limit the history to the transactions prior the current token and the last execution of this method
                    let predicates = [NSPredicate(format: "token <= %@", latestHistoryToken),
                                      NSPredicate(format: "%@ < token", savedHistoryToken)]
                    let historyFetchRequest = NSPersistentHistoryTransaction.fetchRequest!
                    historyFetchRequest.predicate = NSCompoundPredicate(type: .and, subpredicates: predicates)
                    request = NSPersistentHistoryChangeRequest.fetchHistory(withFetch: historyFetchRequest)
                } else {
                    // Simplified request under iOS 12 and before
                    request = NSPersistentHistoryChangeRequest.fetchHistory(after: savedHistoryToken)
                }
                
                // Get the results and all the transactions
                
                let result: NSPersistentHistoryResult?
                do {
                    result = try obvContext.execute(request) as? NSPersistentHistoryResult
                } catch {
                    os_log("Could not execute history fetch request: %{public}@", log: log, type: .fault, error.localizedDescription)
                    return
                }
                
                guard let transactions = result?.result as? [NSPersistentHistoryTransaction] else {
                    os_log("Could not extract history of transactions", log: log, type: .fault)
                    assertionFailure()
                    return
                }
                
                os_log("There are %d transactions within the history. We replay them now.", log: log, type: .info, transactions.count)
                
                // Transfer the transactions to all the delegates that can do something with it.
                // For now, this only concerns the network send manager.
                
                networkPostDelegate.replayTransactionsHistory(transactions: transactions, within: obvContext)
                
                // If we reach this point, we have replayed all previous transactions.
                // We can write the new token value and delete the history prior this token.
                
                do {
                    try writeHistoryToken(token: latestHistoryToken)
                } catch {
                    os_log("Could not write last history token to disk", log: log, type: .fault)
                    assertionFailure()
                }
                
                purgeTransactionsHistory(before: latestHistoryToken, within: obvContext)
                
                try obvContext.save(logOnFailure: log)
                
            }
            
        }
        
    }
    
    
    private func purgeTransactionsHistory(before token: NSPersistentHistoryToken, within obvContext: ObvContext) {
        guard appType == .mainApp else { return }
        let purgeHistoryRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: token)
        do {
            _ = try obvContext.execute(purgeHistoryRequest)
        } catch {
            os_log("Could not purge transactions history: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }
    
    @available(iOS, deprecated:12.0, message: "Only used under iOS 11")
    private func getCurrentPersistentHistoryTokenUnderIOS11(within obvContext: ObvContext) -> NSPersistentHistoryToken? {
        var timeInterval: TimeInterval = 60 // One minute
        for _ in 0..<20 {
            let date = Date(timeIntervalSinceNow: -timeInterval)
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: date)
            guard let result = try? obvContext.execute(request) as? NSPersistentHistoryResult else { return nil }
            guard let transactions = result.result as? [NSPersistentHistoryTransaction] else { continue }
            guard !transactions.isEmpty else { continue }
            if let token = transactions.last?.token {
                return token
            }
            timeInterval *= 2
        }
        return nil
    }
        
}


// MARK: Helpers

extension TransactionsHistoryReplayer {
    
    private func getHistoryTokenURL() -> URL? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sharedContainerIdentifier) else {
            os_log("Could not get container URL", log: log, type: .fault)
            assertionFailure()
            return nil
        }
        let tokenDirectoryURL = containerURL.appendingPathComponent("Engine", isDirectory: true).appendingPathComponent(savedHistoryTokensDirectoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: tokenDirectoryURL.path) {
            do {
                try FileManager.default.createDirectory(at: tokenDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                os_log("Could not create directory for storing history tokens: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return nil
            }
        }
        return tokenDirectoryURL.appendingPathComponent(savedHistoryTokensFileName, isDirectory: false)
    }

}
