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

import Foundation
import CoreData
import os.log
import ObvEngine
import ObvCrypto
import OlvidUtils


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

    private let draftObjectID: TypeSafeManagedObjectID<PersistedDraft>
    private let log: OSLog
    private let loadedItemProviders: [LoadedItemProvider]
    private let completionHandler: ((Bool) -> Void)?
    
    init(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, loadedItemProviders: [LoadedItemProvider], completionHandler: ((Bool) -> Void)?, log: OSLog) {
        self.draftObjectID = draftObjectID
        self.loadedItemProviders = loadedItemProviders
        self.log = log
        self.completionHandler = completionHandler
        super.init()
    }
    
    override func main() {

        guard let obvContext = self.obvContext else {
            assertionFailure()
            completionHandler?(false)
            return cancel(withReason: .contextIsNil)
        }

        // We add as many attachments as we can
        obvContext.performAndWait {

            var tempURLsToDelete = [URL]()

            for loadedItemProvider in loadedItemProviders {
                
                switch loadedItemProvider {
                
                case .file(tempURL: let tempURL, uti: let uti, filename: let filename):
                    
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
                        try createDraftFyleJoin(draftObjectID: draftObjectID, fileName: filename, uti: uti, fyle: fyle, within: obvContext.context)
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
                    
                    guard let draft = try? PersistedDraft.get(objectID: draftObjectID, within: obvContext.context) else {
                        cancelAndContinue(withReason: .couldNotGetDraft)
                        continue
                    }
                    
                    draft.appendContentToBody(textToAppend)
                    
                case .url(content: let url):
                    
                    guard let draft = try? PersistedDraft.get(objectID: draftObjectID, within: obvContext.context) else {
                        cancelAndContinue(withReason: .couldNotGetDraft)
                        continue
                    }
                    draft.appendContentToBody(url.absoluteString)
                    
                }
                
            }
            
            for urlToDelete in tempURLsToDelete {
                try? urlToDelete.moveToTrash()
            }

        }
        
        if isCancelled {
            completionHandler?(false)
        } else {
            do {
                let localDraftObjectID = self.draftObjectID
                let localCompletionHandler = self.completionHandler
                try obvContext.addContextDidSaveCompletionHandler { error in
                    guard error == nil else {
                        localCompletionHandler?(false)
                        return
                    }
                    ObvStack.shared.viewContext.perform {
                        if let draftInViewContext = try? ObvStack.shared.viewContext.existingObject(with: localDraftObjectID.objectID) as? PersistedDraft {
                            ObvStack.shared.viewContext.refresh(draftInViewContext, mergeChanges: true)
                        }
                        localCompletionHandler?(true)
                    }
                }
            } catch {
                completionHandler?(false)
            }
        }
                
    }

    
    private func createDraftFyleJoin(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, fileName: String, uti: String, fyle: Fyle, within context: NSManagedObjectContext) throws {
        if try PersistedDraftFyleJoin.get(draftObjectID: draftObjectID, fyleObjectID: fyle.objectID, within: context) == nil {
            guard PersistedDraftFyleJoin(draftObjectID: draftObjectID, fyleObjectID: fyle.objectID, fileName: fileName, uti: uti, within: context) != nil else {
                throw NSError()
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
