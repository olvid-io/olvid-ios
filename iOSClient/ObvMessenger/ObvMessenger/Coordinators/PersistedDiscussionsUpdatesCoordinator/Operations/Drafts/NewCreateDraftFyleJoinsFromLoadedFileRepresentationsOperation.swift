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
import CoreData
import os.log
import ObvEngine
import ObvCrypto
import ObvUICoreData
import OlvidUtils
import UniformTypeIdentifiers


/// This operation takes an array of loaded file representations as an input. This array is typically the output of a several `LoadFileRepresentationOperation` operations.
/// Each of these `LoadFileRepresentationOperation` operations provides a `loadedFileRepresentation` variable (unless the operation cancels)
/// that the caller uses as one of the items of the `loadedFileRepresentations` input of this operation, which turns each of these representation into a `DraftFyleJoin`.
/// This operation also moves the file found at the temporary URL found in `loadedFileRepresentation`
/// to an appropriate location for the `DraftFyleJoin`.
final class NewCreateDraftFyleJoinsFromLoadedFileRepresentationsOperation: ContextualOperationWithSpecificReasonForCancel<NewCreateDraftFyleJoinsFromLoadedFileRepresentationsOperationReasonForCancel> {
        
    private func cancelAndContinue(withReason reason: NewCreateDraftFyleJoinsFromLoadedFileRepresentationsOperationReasonForCancel) {
        guard self.reasonForCancel == nil else { return }
        self.reasonForCancel = reason
    }
    
    let Sha256 = ObvCryptoSuite.sharedInstance.hashFunctionSha256()

    private let draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>
    private let log: OSLog
    private let loadedItemProvidersType: LoadedItemProvidersType
    private let completionHandler: ((Bool) -> Void)?
    
    enum LoadedItemProvidersType {
        case loadedItemProviders(loadedItemProviders: [LoadedItemProvider])
        case operationsProvidingLoadedItemProvider(operations: [OperationProvidingLoadedItemProvider])
    }
    
    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { Self.makeError(message: message) }

    init(draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, loadedItemProviders: [LoadedItemProvider], completionHandler: ((Bool) -> Void)?, log: OSLog) {
        self.draftPermanentID = draftPermanentID
        self.loadedItemProvidersType = .loadedItemProviders(loadedItemProviders: loadedItemProviders)
        self.log = log
        self.completionHandler = completionHandler
        super.init()
    }
    
    init(draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, operationsProvidingLoadedItemProvider: [OperationProvidingLoadedItemProvider], completionHandler: ((Bool) -> Void)?, log: OSLog) {
        self.draftPermanentID = draftPermanentID
        self.loadedItemProvidersType = .operationsProvidingLoadedItemProvider(operations: operationsProvidingLoadedItemProvider)
        self.log = log
        self.completionHandler = completionHandler
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        let loadedItemProviders: [LoadedItemProvider]
        switch loadedItemProvidersType {
        case .loadedItemProviders(loadedItemProviders: let providers):
            loadedItemProviders = providers
        case .operationsProvidingLoadedItemProvider(operations: let operations):
            assert(operations.allSatisfy({$0.isFinished}))
            loadedItemProviders = operations.compactMap({ $0.loadedItemProvider })
        }
        
        // We add as many attachments as we can
        
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
                guard let fyle: Fyle = try? Fyle.getOrCreate(sha256: sha256, within: obvContext.context) else {
                    cancelAndContinue(withReason: .couldNotGetOrCreateFyle)
                    tempURLsToDelete.append(tempURL)
                    continue
                }
                
                // Create a PersistedDraftFyleJoin (if required)
                do {
                    try createDraftFyleJoin(draftPermanentID: draftPermanentID, fileName: filename, fileType: fileType, fyle: fyle, within: obvContext.context)
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
                
                guard let draft = try? PersistedDraft.getManagedObject(withPermanentID: draftPermanentID, within: obvContext.context) else {
                    cancelAndContinue(withReason: .couldNotGetDraft)
                    continue
                }
                
                draft.appendContentToBody(textContent)
                
            case .url(content: let url):
                
                guard let draft = try? PersistedDraft.getManagedObject(withPermanentID: draftPermanentID, within: obvContext.context) else {
                    cancelAndContinue(withReason: .couldNotGetDraft)
                    continue
                }
                draft.appendContentToBody(url.absoluteString)
                
            }
            
        }
        
        for urlToDelete in tempURLsToDelete {
            try? urlToDelete.moveToTrash()
        }
        
        if isCancelled {
            completionHandler?(false)
        } else {
            let localCompletionHandler = self.completionHandler
            if obvContext.context.hasChanges {
                do {
                    let draftPermanentID = self.draftPermanentID
                    try obvContext.addContextDidSaveCompletionHandler { error in
                        guard error == nil else {
                            localCompletionHandler?(false)
                            return
                        }
                        ObvStack.shared.viewContext.perform {
                            if let draftInViewContext = ObvStack.shared.viewContext.registeredObjects
                                .filter({ !$0.isDeleted })
                                .first(where: { ($0 as? PersistedDraft)?.objectPermanentID == draftPermanentID }) {
                                ObvStack.shared.viewContext.refresh(draftInViewContext, mergeChanges: true)
                            }
                            localCompletionHandler?(true)
                        }
                    }
                } catch {
                    localCompletionHandler?(false)
                }
            } else {
                obvContext.addEndOfScopeCompletionHandler {
                    localCompletionHandler?(true)
                }
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


enum NewCreateDraftFyleJoinsFromLoadedFileRepresentationsOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case contextIsNil
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
        case .contextIsNil:
            return "Context is nil"
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
