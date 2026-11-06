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

import Foundation
import ObvCrypto
import ObvEncoder
import ObvServerInterface
import ObvTypes
import OlvidUtils
import OSLog


/// Encrypts the receipts we owe and uploads them, grouped by the server of the contact each one is owed to.
///
/// Reports the outcome of every request, because that outcome decides whether a row is deleted or sent again. A
/// swallowed failure deletes rows that never left the device.
///
/// Nothing here asserts on a failure: every failure path is one a test walks, and an `assertionFailure` stops a debug
/// build. Do not add the assertions back.
///
/// Everything it needs is handed to it — no delegate, no store — so it can be exercised on its own.
struct ReturnReceiptUploader {

    private static let logger = Logger(subsystem: "io.olvid.returnReceiptSend", category: "ReturnReceiptUploader")

    /// Only for `ObvServerUploadReturnReceipt.parseObvServerResponse`, which takes an `OSLog` rather than a `Logger`.
    private static let osLog = OSLog(subsystem: "io.olvid.returnReceiptSend", category: "ReturnReceiptUploader")

    /// How many receipts one request may carry, the server limiting the size of a request.
    private static let maximumNumberOfReceiptsPerRequest = 50

    private let network: any ReturnReceiptUploadNetwork

    init(network: any ReturnReceiptUploadNetwork = ReturnReceiptUploadNetworkUsingSharedURLSession()) {
        self.network = network
    }


    /// Encrypts these receipts, groups them by the server of their contact, cuts each group into requests, and
    /// uploads the requests.
    ///
    /// Does not throw: a failure is an outcome in the report, not an error, since the caller needs to hear about the
    /// requests that worked as well as the ones that did not.
    func upload(_ receiptsReadyToUpload: [ReturnReceiptReadyToUpload], flowId: FlowIdentifier) async -> ReturnReceiptUploadReport {

        var encryptedReturnReceipts = [EncryptedReturnReceipt]()
        var identifiersThatCanNeverBeSent = [ReturnReceiptIdentifier]()

        for receiptReadyToUpload in receiptsReadyToUpload {
            if let encryptedReturnReceipt = Self.encrypt(receiptReadyToUpload) {
                encryptedReturnReceipts.append(encryptedReturnReceipt)
            } else {
                // The reason was logged where it was found. The row must still be deleted, or it is read again by
                // every drain from now on.
                identifiersThatCanNeverBeSent.append(receiptReadyToUpload.returnReceipt.identifier)
            }
        }

        let requests: [(serverURL: URL, receipts: [EncryptedReturnReceipt])] = Dictionary(grouping: encryptedReturnReceipts, by: { $0.serverURL })
            .flatMap { serverURL, receiptsForThisServer in
                receiptsForThisServer
                    .toSlices(ofMaxSize: Self.maximumNumberOfReceiptsPerRequest)
                    .map { (serverURL: serverURL, receipts: $0) }
            }

        var outcomes = [ReturnReceiptUploadOutcome]()

        // Concurrent, and safe by construction: no receipt is in two requests, so no two of these settle the same
        // row.
        await withTaskGroup(of: ReturnReceiptUploadOutcome.self) { taskGroup in
            for request in requests {
                taskGroup.addTask {
                    await self.upload(request.receipts, toServer: request.serverURL, flowId: flowId)
                }
            }
            for await outcome in taskGroup {
                outcomes.append(outcome)
            }
        }

        return .init(outcomes: outcomes, identifiersThatCanNeverBeSent: identifiersThatCanNeverBeSent)

    }

}


// MARK: - Encrypting one receipt

extension ReturnReceiptUploader {

    /// One receipt, encrypted for its contact and ready to travel.
    private struct EncryptedReturnReceipt {
        let identifier: ReturnReceiptIdentifier
        let serverURL: URL
        let returnReceipt: ObvServerUploadReturnReceipt.ReturnReceipt
    }


    /// Nil when this receipt can never be sent, the reason being logged here.
    ///
    /// The encryption is deterministic — the generator is seeded rather than random — so the same receipt produced
    /// twice, by two owned devices or by two processes of this one, encrypts to the same bytes and the server reads
    /// the second as a duplicate. The design relies on a duplicate being free rather than on preventing one.
    private static func encrypt(_ receiptReadyToUpload: ReturnReceiptReadyToUpload) -> EncryptedReturnReceipt? {

        let identifier = receiptReadyToUpload.returnReceipt.identifier

        guard !receiptReadyToUpload.contactDeviceUIDs.isEmpty else {
            logger.error("A return receipt has no contact device to be sent to, so it can never be sent")
            return nil
        }

        let payload = ObvReturnReceiptPayload(
            author: identifier.contactIdentifier.ownedCryptoId,
            status: identifier.status,
            attachmentNumber: identifier.attachmentNumber)
            .obvEncode().rawData

        guard let encodedKey = ObvEncoded(withRawData: receiptReadyToUpload.returnReceipt.key) else {
            logger.fault("The key of a return receipt cannot be decoded, so it can never be sent")
            return nil
        }

        let encryptedPayload: EncryptedData
        do {
            let authenticatedEncryptionKey = try AuthenticatedEncryptionKeyDecoder.decode(encodedKey)
            let prngForDeterministicEncryption = ObvCryptoSuite.sharedInstance.concretePRNG().init(with: receiptReadyToUpload.seed)
            encryptedPayload = try ObvCryptoSuite.sharedInstance.authenticatedEncryption().encrypt(payload, with: authenticatedEncryptionKey, and: prngForDeterministicEncryption)
        } catch {
            logger.fault("The payload of a return receipt cannot be encrypted, so it can never be sent: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        return .init(
            identifier: identifier,
            // The server of the contact, who receives the receipt, not the one of the owned identity — they differ
            // on self-hosted servers. Carried by the value, which derived it exactly as the stored column the rows
            // are fetched by: a page read for one server and posted to another goes nowhere.
            serverURL: receiptReadyToUpload.returnReceipt.serverURL,
            returnReceipt: .init(
                toIdentity: identifier.contactIdentifier.contactCryptoId.cryptoIdentity,
                deviceUids: Array(receiptReadyToUpload.contactDeviceUIDs),
                nonce: identifier.nonce,
                encryptedPayload: encryptedPayload))

    }

}


// MARK: - Uploading one request

extension ReturnReceiptUploader {

    private func upload(_ encryptedReturnReceipts: [EncryptedReturnReceipt], toServer serverURL: URL, flowId: FlowIdentifier) async -> ReturnReceiptUploadOutcome {

        let identifiers = encryptedReturnReceipts.map { $0.identifier }

        func report(_ outcome: ReturnReceiptUploadOutcome.Outcome) -> ReturnReceiptUploadOutcome {
            .init(serverURL: serverURL, identifiers: identifiers, outcome: outcome)
        }

        do {

            let method = ObvServerUploadReturnReceipt(
                serverURL: serverURL,
                returnReceipts: encryptedReturnReceipts.map { $0.returnReceipt },
                flowId: flowId)

            // No identity delegate is set on the method: this upload is not authenticated, so building the request
            // never asks for one.

            // The request of an upload task must carry no body and no body stream, so the bytes are taken out of the
            // method here and handed to the upload call beside the request.
            guard let dataToSend = method.dataToSend else {
                Self.logger.fault("🧾 The data to send cannot be built for \(identifiers.count) return receipts")
                return report(.theUploadFailed)
            }
            method.dataToSend = nil

            let urlRequest = try method.getURLRequest()

            let (responseData, response) = try await network.upload(urlRequest, from: dataToSend)

            guard let httpResponse = response as? HTTPURLResponse else {
                Self.logger.fault("🧾 The answer to an upload of \(identifiers.count) return receipts is not an HTTP response")
                return report(.theUploadFailed)
            }

            guard httpResponse.statusCode == 200 else {
                Self.logger.error("🧾 The server answered \(httpResponse.statusCode) to an upload of \(identifiers.count) return receipts")
                return report(.theUploadFailed)
            }

            guard let status = ObvServerUploadReturnReceipt.parseObvServerResponse(responseData: responseData, using: Self.osLog) else {
                Self.logger.fault("🧾 The status returned by the server cannot be recovered")
                return report(.theUploadFailed)
            }

            switch status {
            case .generalError:
                Self.logger.error("🧾 The server returned a general error for an upload of \(identifiers.count) return receipts")
                return report(.theUploadFailed)
            case .ok:
                Self.logger.info("🧾 \(identifiers.count) return receipts were uploaded")
                return report(.theUploadSucceeded)
            }

        } catch {

            let outcome = Self.outcome(forAnErrorThrownWhileUploading: error)
            Self.logger.error("🧾 The upload of \(identifiers.count) return receipts failed: \(error.localizedDescription, privacy: .public)")
            return report(outcome)

        }

    }


    /// Whether a thrown error means no server ever saw the request.
    ///
    /// The set is asymmetric in its consequences: adding a code to it keeps a row that might have been delivered,
    /// removing one destroys a row that was about to be. When in doubt, a code belongs here.
    ///
    /// Everything that stops this device from reaching a server belongs here, and not only the two codes airplane
    /// mode gives. A phone abroad with data roaming off, on a network whose DNS will not answer, or suspended
    /// mid-upload has made no attempt at all — and this answer is what decides whether an over-age receipt is
    /// destroyed, so reading any of them as a refusal gives up on a backlog no server has ever been offered.
    private static func outcome(forAnErrorThrownWhileUploading error: Error) -> ReturnReceiptUploadOutcome.Outcome {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return .theUploadFailed }
        switch nsError.code {
        case Int(CFNetworkErrors.cfurlErrorNotConnectedToInternet.rawValue),
            Int(CFNetworkErrors.cfurlErrorNetworkConnectionLost.rawValue),
            Int(CFNetworkErrors.cfurlErrorCannotConnectToHost.rawValue),
            Int(CFNetworkErrors.cfurlErrorCannotFindHost.rawValue),
            Int(CFNetworkErrors.cfurlErrorDNSLookupFailed.rawValue),
            Int(CFNetworkErrors.cfurlErrorTimedOut.rawValue),
            Int(CFNetworkErrors.cfurlErrorInternationalRoamingOff.rawValue),
            Int(CFNetworkErrors.cfurlErrorDataNotAllowed.rawValue),
            Int(CFNetworkErrors.cfurlErrorCallIsActive.rawValue),
            Int(CFNetworkErrors.cfurlErrorSecureConnectionFailed.rawValue),
            Int(CFNetworkErrors.cfurlErrorCancelled.rawValue):
            return .theRequestNeverLeftTheDevice
        default:
            return .theUploadFailed
        }
    }

}
