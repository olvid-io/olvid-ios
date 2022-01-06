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
import ObvCrypto
import MobileCoreServices
import OlvidUtils

/// This operation takes an array of loaded file representations as an input. This array is typically the output of a several `LoadFileRepresentationOperation` operations.
/// Each of these `LoadFileRepresentationOperation` operations provides a `loadedFileRepresentation` variable (unless the operation cancels)
/// that the caller uses as one of the items of the `loadedFileRepresentations` input of this operation, which adds each of these representations to an "in memory" draft.
///
/// This operation is very similar to the `CreateDraftFyleJoinsFromLoadedFileRepresentationsOperation`, except that it
/// adds the created Fyles to an "in memory" draft instead of creating a `DraftFyleJoin`.
final class CreateInMemoryDraftFyleFromLoadedFileRepresentationsOperation: OperationWithSpecificReasonForCancel<CreateInMemoryDraftFyleFromLoadedFileRepresentationsOperationReasonForCancel> {
        
    private func cancelAndContinue(withReason reason: CreateInMemoryDraftFyleFromLoadedFileRepresentationsOperationReasonForCancel) {
        guard self.reasonForCancel == nil else { return }
        self.reasonForCancel = reason
    }

    private let Sha256 = ObvCryptoSuite.sharedInstance.hashFunctionSha256()

    private let log: OSLog
    private let loadedItemProviders: [LoadedItemProvider]
    private let inMemoryDraft: InMemoryDraft

    init(inMemoryDraft: InMemoryDraft, loadedItemProviders: [LoadedItemProvider], log: OSLog) {
        self.inMemoryDraft = inMemoryDraft
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
                    guard let fyle: Fyle = try? Fyle.getOrCreate(sha256: sha256, within: context) else {
                        cancelAndContinue(withReason: .couldNotGetOrCreateFyle)
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
                    
                    do {
                        try context.save()
                    } catch {
                        os_log("Could not save context: %{public}@", log: log, type: .error, error.localizedDescription)
                        cancelAndContinue(withReason: .coreDataError(error: error))
                        tempURLsToDelete.append(tempURL)
                        continue
                    }

                    inMemoryDraft.appendFyle(fyle.objectID, fileName: filename, uti: uti)

                case .text(content: let textWithinAttachment):
                
                    let qBegin = Locale.current.quotationBeginDelimiter ?? "\""
                    let qEnd = Locale.current.quotationEndDelimiter ?? "\""

                    let textToAppend = [qBegin, textWithinAttachment, qEnd].joined(separator: "")
                    inMemoryDraft.appendText(textToAppend)

                case .url(content: let url):
                    
                    inMemoryDraft.appendText(url.absoluteString)

                }
                
            }

            for urlToDelete in tempURLsToDelete {
                try? urlToDelete.moveToTrash()
            }
            
            // Whatever the UTI, we save the context
            
            do {
                try context.save()
            } catch {
                os_log("Could not save context: %{public}@", log: log, type: .error, error.localizedDescription)
                return cancel(withReason: .coreDataError(error: error))
            }

        }
        
    }

    
}


fileprivate extension String {
    
    func utiConformsTo(_ otherUTI: CFString) -> Bool {
        UTTypeConformsTo(self as CFString, otherUTI)
    }
    
}




enum CreateInMemoryDraftFyleFromLoadedFileRepresentationsOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case couldNotComputeSha256
    case couldNotGetOrCreateFyle
    case couldNotCreateDraftFyleJoin
    case couldNotMoveFileToPermanentURL(error: Error)
    case couldNotReadFileContent(error: Error)
    case coreDataError(error: Error)

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
        case .couldNotReadFileContent(error: let error):
            return "Could not read file content: \(error.localizedDescription)"
        }
    }
}
