/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import OlvidUtils
import os.log
import CoreData
import ObvCrypto
import ObvUICoreData
import UniformTypeIdentifiers


/// This is a legacy operation, use `NewLoadFileRepresentationsThenCreateDraftFyleJoinsCompositeOperation` instead
final class LoadFileRepresentationsThenCreateDraftFyleJoinsCompositeOperation: Operation {
    
    private func logReasonOfCancelledOperations(_ operations: [OperationThatCanLogReasonForCancel]) {
        let cancelledOps = operations.filter({ $0.isCancelled })
        for op in cancelledOps {
            op.logReasonIfCancelled(log: log)
        }
    }

    private let internalQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "LoadedFileRepresentationsThenCreateDraftFyleJoinsCompositeOperation internal queue"
        return queue
    }()
    
    private let draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>
    private let itemProvidersOrItemURL: [ItemProviderOrItemURL]
    private let log: OSLog
    
    init(draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, itemProviders: [NSItemProvider], log: OSLog) {
        self.draftPermanentID = draftPermanentID
        self.itemProvidersOrItemURL = itemProviders.map { ItemProviderOrItemURL.itemProvider(itemProvider: $0) }
        self.log = log
        super.init()
    }

    init(draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, fileURLs: [URL], log: OSLog) {
        self.draftPermanentID = draftPermanentID
        self.itemProvidersOrItemURL = fileURLs.map { ItemProviderOrItemURL.itemURL(url: $0) }
        self.log = log
        super.init()
    }

    override func main() {
        
        let loadItemProviderOperations = itemProvidersOrItemURL.map { LoadItemProviderOperation(itemProviderOrItemURL: $0, progressAvailable: { _ in }) }
        internalQueue.addOperations(loadItemProviderOperations, waitUntilFinished: true)
        logReasonOfCancelledOperations(loadItemProviderOperations)
        
        let loadedItemProviders = loadItemProviderOperations.compactMap({ $0.loadedItemProvider })
        let createDraftFyleJoinsOperation = CreateDraftFyleJoinsFromLoadedFileRepresentationsOperation(draftPermanentID: draftPermanentID, loadedItemProviders: loadedItemProviders, log: log)
        internalQueue.addOperations([createDraftFyleJoinsOperation], waitUntilFinished: true)
        createDraftFyleJoinsOperation.logReasonIfCancelled(log: log)
        
    }
    
}



/// This operation takes an array of loaded file representations as an input. This array is typically the output of a several `LoadFileRepresentationOperation` operations.
/// Each of these `LoadFileRepresentationOperation` operations provides a `loadedFileRepresentation` variable (unless the operation cancels)
/// that the caller uses as one of the items of the `loadedFileRepresentations` input of this operation, which turns each of these representation into a `DraftFyleJoin`.
/// This operation also moves the file found at the temporary URL found in `loadedFileRepresentation`
/// to an appropriate location for the `DraftFyleJoin`.
fileprivate final class CreateDraftFyleJoinsFromLoadedFileRepresentationsOperation: OperationWithSpecificReasonForCancel<CreateDraftFyleJoinsFromLoadedFileRepresentationsOperationReasonForCancel> {
        
    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { Self.makeError(message: message) }

    private func cancelAndContinue(withReason reason: CreateDraftFyleJoinsFromLoadedFileRepresentationsOperationReasonForCancel) {
        guard self.reasonForCancel == nil else { return }
        self.reasonForCancel = reason
    }

    let Sha256 = ObvCryptoSuite.sharedInstance.hashFunctionSha256()

    private let draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>
    private let log: OSLog
    private let loadedItemProviders: [LoadedItemProvider]
    
    init(draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, loadedItemProviders: [LoadedItemProvider], log: OSLog) {
        self.draftPermanentID = draftPermanentID
        self.loadedItemProviders = loadedItemProviders
        self.log = log
        super.init()
    }
    
    override func main() {
        
        // We add as many attachments as we can
        ObvStack.shared.performBackgroundTaskAndWait { (context) in

            var tempURLsToDelete = [URL]()

            for loadedItemProvider in loadedItemProviders {
                
                switch loadedItemProvider {
                
                case .file(tempURL: let tempURL, fileType: let fileType, filename: let filename):
                    
                    // Compute the sha256 of the file
                    let sha256: Data
                    do {
                        sha256 = try Sha256.hash(fileAtUrl: tempURL)
                    } catch {
                        cancelAndContinue(withReason: .couldNotComputeSha256)
                        tempURLsToDelete.append(tempURL)
                        continue
                    }
                    
                    // Get or create a Fyle
                    guard let fyle: Fyle = try? Fyle.getOrCreate(sha256: sha256, within: context) else {
                        cancelAndContinue(withReason: .couldNotGetOrCreateFyle)
                        tempURLsToDelete.append(tempURL)
                        continue
                    }
                    
                    // Create a PersistedDraftFyleJoin (if required)
                    do {
                        try createDraftFyleJoin(draftPermanentID: draftPermanentID, fileName: filename, fileType: fileType, fyle: fyle, within: context)
                    } catch {
                        cancelAndContinue(withReason: .couldNotCreateDraftFyleJoin)
                        tempURLsToDelete.append(tempURL)
                        continue
                    }
                    
                    // We move the received file to a permanent location

                    do {
                        try fyle.moveFileToPermanentURL(from: tempURL, logTo: log)
                    } catch {
                        cancelAndContinue(withReason: .couldNotMoveFileToPermanentURL(error: error))
                        tempURLsToDelete.append(tempURL)
                        continue
                    }
                    
                case .text(content: let textContent):

                    let qBegin = Locale.current.quotationBeginDelimiter ?? "\""
                    let qEnd = Locale.current.quotationEndDelimiter ?? "\""

                    let textToAppend = [qBegin, textContent, qEnd].joined(separator: "")

                    guard let draft = try? PersistedDraft.getManagedObject(withPermanentID: draftPermanentID, within: context) else {
                        cancelAndContinue(withReason: .couldNotGetDraft)
                        continue
                    }

                    draft.appendContentToBody(textToAppend)
                    
                case .url(content: let url):
                    
                    guard let draft = try? PersistedDraft.getManagedObject(withPermanentID: draftPermanentID, within: context) else {
                        cancelAndContinue(withReason: .couldNotGetDraft)
                        continue
                    }
                    draft.appendContentToBody(url.absoluteString)
    
                }
            }
            
            for urlToDelete in tempURLsToDelete {
                try? urlToDelete.moveToTrash()
            }
            
            do {
                try context.save()
            } catch {
                os_log("Could not save context: %{public}@", log: log, type: .error, error.localizedDescription)
                return cancel(withReason: .coreDataError(error: error))
            }
            
        }
        
    }

    
    private func createDraftFyleJoin(draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, fileName: String, fileType: UTType, fyle: Fyle, within context: NSManagedObjectContext) throws {
        if try PersistedDraftFyleJoin.get(draftPermanentID: draftPermanentID, fyleObjectID: fyle.objectID, within: context) == nil {
            guard PersistedDraftFyleJoin(draftPermanentID: draftPermanentID, fyleObjectID: fyle.objectID, fileName: fileName, uti: fileType.identifier, within: context) != nil else {
                throw makeError(message: "Could not create PersistedDraftFyleJoin")
            }
        }
    }

}


fileprivate enum CreateDraftFyleJoinsFromLoadedFileRepresentationsOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case couldNotComputeSha256
    case couldNotGetOrCreateFyle
    case couldNotCreateDraftFyleJoin
    case couldNotMoveFileToPermanentURL(error: Error)
    case coreDataError(error: Error)
    case couldNotGetDraft

    var logType: OSLogType {
        return .fault
    }
    
    var errorDescription: String? {
        switch self {
        case .couldNotComputeSha256:
            return "Could not compute SHA256 of the file"
        case .couldNotGetOrCreateFyle:
            return "Could not get or create Fyle"
        case .couldNotCreateDraftFyleJoin:
            return "Could not create DraftFyleJoin"
        case .couldNotMoveFileToPermanentURL(error: let error):
            return "Could not move file to permanent URL: \(error.localizedDescription)"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotGetDraft:
            return "Could not get Draft"

        }
    }
}
