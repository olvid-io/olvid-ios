/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import OSLog
import OlvidUtils
import ObvCrypto
import ObvUICoreData
import CoreData
import ObvAppCoreConstants


final class CreateFylesFromLoadedFileRepresentationsOperation: ContextualOperationWithSpecificReasonForCancel<CreateFylesFromLoadedFileRepresentationsOperationReasonForCancel>, @unchecked Sendable, FyleJoinsProvider {

    private static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "CreateFylesFromLoadedFileRepresentationsOperation")
    
    private let loadedItemProviders: [LoadedItemProvider]

    init(loadedItemProviders: [LoadedItemProvider]) {
        self.loadedItemProviders = loadedItemProviders
        super.init()
    }

    private(set) var fyleJoins: [FyleJoin]?
    private(set) var bodyTexts: [String]?

    private func cancelAndContinue(withReason reason: CreateFylesFromLoadedFileRepresentationsOperationReasonForCancel) {
        guard self.reasonForCancel == nil else { return }
        self.reasonForCancel = reason
    }

    private let Sha256 = ObvCryptoSuite.sharedInstance.hashFunctionSha256()

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        var tempURLsToDelete = [URL]()
        var fyleJoins = [FyleJoin]()
        var loadedItemProvidersToPaste = [LoadedItemProviderToPaste]()
        
        for loadedItemProvider in loadedItemProviders {
            
            switch loadedItemProvider {
                
            case .toAttach(let loadedItemProviderToAttach):
                
                let tempURL = loadedItemProviderToAttach.tempURL
                let fileType = loadedItemProviderToAttach.fileType
                let filename = loadedItemProviderToAttach.filename
                                
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
                
                // We move the received file to a permanent location
                
                do {
                    try fyle.moveFileToPermanentURL(from: tempURL, logTo: Self.log)
                } catch {
                    cancelAndContinue(withReason: .couldNotMoveFileToPermanentURL(error: error))
                    tempURLsToDelete.append(tempURL)
                    continue
                }
                
                let fyleJoin = FyleJoinImpl(fyle: fyle, fileName: filename, contentType: fileType, index: fyleJoins.count)
                
                fyleJoins += [fyleJoin]
                
            case .toPaste(let loadedItemProviderToPaste):
                
                loadedItemProvidersToPaste.append(loadedItemProviderToPaste)
                
            }
            
        }
        
        // In the special case where there is exactly one URL, we put it last in the bodyTexts.
        // This typically happens when sharing an article, where the shared content to paste contains
        // one URL, and one decription as text. In that case, we typically want the description to appear first.
        
        let numberOfURLsToPaste = loadedItemProvidersToPaste.count(where: { $0.isURL })
        if numberOfURLsToPaste == 1 {
            self.bodyTexts = loadedItemProvidersToPaste.sorted(by: \.sortOrder).map(\.textToPaste)
        } else {
            self.bodyTexts = loadedItemProvidersToPaste.map(\.textToPaste)
        }
        
        self.fyleJoins = fyleJoins
        
        for urlToDelete in tempURLsToDelete {
            try? urlToDelete.moveToTrash()
        }
        
    }

}



fileprivate extension LoadedItemProviderToPaste {
    
    /// Allows to easily place URLs last in the bodyTexts
    var sortOrder: Int {
        switch self {
        case .text: return 0
        case .url: return 1
        }
    }
    
}


enum CreateFylesFromLoadedFileRepresentationsOperationReasonForCancel: LocalizedErrorWithLogType {
    case contextIsNil
    case couldNotComputeSha256
    case couldNotGetOrCreateFyle
    case couldNotMoveFileToPermanentURL(error: Error)
    case noLoadedItemProviders

    var logType: OSLogType { .fault }

    var errorDescription: String? {
        switch self {
        case .contextIsNil: return "Context is nil"
        case .couldNotComputeSha256: return "Could not compute SHA256 of the file"
        case .couldNotGetOrCreateFyle: return "Could not get or create Fyle"
        case .couldNotMoveFileToPermanentURL(error: let error): return "Could not move file to permanent URL: \(error.localizedDescription)"
        case .noLoadedItemProviders: return "No loaded item provider in given operation"
        }
    }

}
