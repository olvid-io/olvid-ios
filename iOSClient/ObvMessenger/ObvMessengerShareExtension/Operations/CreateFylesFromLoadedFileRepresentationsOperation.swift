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
import OlvidUtils
import ObvCrypto
import ObvUICoreData

protocol LoadedItemProviderProvider: Operation {
    var loadedItemProviders: [LoadedItemProvider]? { get }
}

final class CreateFylesFromLoadedFileRepresentationsOperation: ContextualOperationWithSpecificReasonForCancel<CreateFylesFromLoadedFileRepresentationsOperationReasonForCancel>, FyleJoinsProvider {

    private let loadedItemProviderProvider: LoadedItemProviderProvider
    private let log: OSLog

    init(loadedItemProviderProvider: LoadedItemProviderProvider, log: OSLog) {
        self.loadedItemProviderProvider = loadedItemProviderProvider
        self.log = log
        super.init()
    }

    private(set) var fyleJoins: [FyleJoin]?
    private(set) var bodyTexts: [String]?

    private func cancelAndContinue(withReason reason: CreateFylesFromLoadedFileRepresentationsOperationReasonForCancel) {
        guard self.reasonForCancel == nil else { return }
        self.reasonForCancel = reason
    }

    private let Sha256 = ObvCryptoSuite.sharedInstance.hashFunctionSha256()

    override func main() {
        assert(loadedItemProviderProvider.isFinished)

        guard let obvContext = self.obvContext else {
            cancel(withReason: .contextIsNil)
            return
        }

        guard let loadedItemProviders = loadedItemProviderProvider.loadedItemProviders else {
            cancel(withReason: .noLoadedItemProviders)
            return
        }

        obvContext.performAndWait {

            var tempURLsToDelete = [URL]()
            var fyleJoins = [FyleJoin]()
            var bodyTexts = [String]()

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

                    // We move the received file to a permanent location

                    do {
                        try fyle.moveFileToPermanentURL(from: tempURL, logTo: log)
                    } catch {
                        cancelAndContinue(withReason: .couldNotMoveFileToPermanentURL(error: error))
                        tempURLsToDelete.append(tempURL)
                        continue
                    }

                    let fyleJoin = FyleJoinImpl(fyle: fyle, fileName: filename, uti: uti, index: fyleJoins.count)

                    fyleJoins += [fyleJoin]

                case .text(content: let textContent):

                    let qBegin = Locale.current.quotationBeginDelimiter ?? "\""
                    let qEnd = Locale.current.quotationEndDelimiter ?? "\""

                    let textToAppend = [qBegin, textContent, qEnd].joined(separator: "")

                    bodyTexts.append(textToAppend)

                case .url(content: let url):
                    bodyTexts.append(url.absoluteString)
                }

            }

            self.bodyTexts = bodyTexts
            self.fyleJoins = fyleJoins

            for urlToDelete in tempURLsToDelete {
                try? urlToDelete.moveToTrash()
            }

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
