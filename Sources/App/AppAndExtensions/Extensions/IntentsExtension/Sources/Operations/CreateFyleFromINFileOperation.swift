/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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

import Intents
import Foundation
import OSLog
import OlvidUtils
import ObvCrypto
import ObvUICoreData
import CoreData
import ObvAppCoreConstants
import UniformTypeIdentifiers

final class CreateFyleFromINFileOperation: ContextualOperationWithSpecificReasonForCancel<CreateFyleFromINFileOperationReasonForCancel>, @unchecked Sendable, FyleJoinsProvider {

    private static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "CreateFyleFromINFileOperation")
    
    private let file: INFile

    init(file: INFile) {
        self.file = file
        super.init()
    }

    private(set) var fyleJoins: [FyleJoin]?

    private let Sha256 = ObvCryptoSuite.sharedInstance.hashFunctionSha256()

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        let fileData = file.data
        let fileType = file.typeIdentifier
        let filename = file.filename
        
        guard let fileType, let uttype = UTType(fileType) else {
            cancel(withReason: .couldNotComputeSha256)
            return
        }
        
        // Compute the sha256 of the file
        let sha256: Data = Sha256.hash(fileData)
        
        // Get or create a Fyle
        guard let fyle: Fyle = try? Fyle.getOrCreate(sha256: sha256, within: obvContext.context) else {
            cancel(withReason: .couldNotGetOrCreateFyle)
            return
        }
        
        // We move the received file to a permanent location
        do {
            try fyle.writeDataToPermanentURL(from: fileData, logTo: Self.log)
        } catch {
            cancel(withReason: .couldNotWriteDataToPermanentURL(error: error))
            return
        }
        
        let fyleJoin = FyleJoinImpl(fyle: fyle,
                                    fileName: filename,
                                    contentType: uttype,
                                    index: 0)
        
        self.fyleJoins = [fyleJoin]
    }

}


enum CreateFyleFromINFileOperationReasonForCancel: LocalizedErrorWithLogType {
    case couldNotComputeSha256
    case couldNotGetOrCreateFyle
    case couldNotWriteDataToPermanentURL(error: Error)
    
    var logType: OSLogType { .fault }
    
    var errorDescription: String? {
        switch self {
        case .couldNotComputeSha256: return "Could not compute SHA256 of the file"
        case .couldNotGetOrCreateFyle: return "Could not get or create Fyle"
        case .couldNotWriteDataToPermanentURL(error: let error): return "Could not write data to permanent URL: \(error.localizedDescription)"
        }
    }
}
