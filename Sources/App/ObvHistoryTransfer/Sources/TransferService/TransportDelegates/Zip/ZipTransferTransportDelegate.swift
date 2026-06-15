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
import OSLog
import ObvTypes
import ObvAppCoreConstants
import ZipArchive


public protocol ZipTransferTransportDelegateDataSource: Sendable {
    func getDisplayNameOfContacts(ownedCryptoId: ObvCryptoId, contactCryptoIds: Set<ObvCryptoId>) async throws -> [ObvCryptoId : String]
}


actor ZipTransferTransportDelegate {
    
    let ownedCryptoId: ObvTypes.ObvCryptoId
    var role: TransferRole {
        switch zipTransferRole {
        case .source: return .source
        case .destination: return .destination
        }
    }
    
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "ZipTransferTransportDelegate")

    private(set) var transferTransportLayerState: TransferTransportLayerState = .initial

    private var continuationForTransferTransportLayerState: AsyncStream<TransferTransportLayerState>.Continuation?
    private var transferTransportLayerStateOnSetContinuation = [TransferTransportLayerState]()
    private var lastYieldedTransferTransportLayerState: TransferTransportLayerState?
    private let temporaryDirectory: URL
    private let directoryName: String
    private var zipDirectoryURL: URL { temporaryDirectory.appending(component: directoryName) }
    private var jsonZipExport: JsonZipExport
    private let password: String?
    private let zipTransferRole: ZipTransferRole

    var transferId: String? { nil }
    
    // Used when the role is "destination"
    private var dstDiscussionExpectedRangesForDiscussion = [JsonDiscussionIdentifier : DstDiscussionExpectedRanges]()
    
    // Used when the role is "source"
    private var contactCryptoIds = Set<ObvCryptoId>()
    
    private var deleteTemporaryFilesAndZipFileWasCalled = false
    
    private var dataSource: (any ZipTransferTransportDelegateDataSource)? {
        switch zipTransferRole {
        case .destination: return nil
        case .source(dataSource: let dataSource): return dataSource
        }
    }
    
    init(ownedCryptoId: ObvTypes.ObvCryptoId,
         password: String?,
         role: ZipTransferRole,
         temporaryDirectory: URL) {
        self.ownedCryptoId = ownedCryptoId
        self.zipTransferRole = role
        self.temporaryDirectory = temporaryDirectory.appending(path: "ZipTransferTransportDelegate")
        self.jsonZipExport = .init(ownedCryptoId: ownedCryptoId)
        self.password = password
        let now = Date.now
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy_MM_dd"
        self.directoryName = "olvid_export_\(formatter.string(from: now))"
    }
        
}


// MARK: - Implementing TransferTransportSendJsonMessageDelegateForSource

extension ZipTransferTransportDelegate: TransferTransportSendJsonMessageDelegateForSource {
    
    func connect(progressUpdater: any ConnectProgressUpdater) async throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        try FileManager.default.createDirectory(at: zipDirectoryURL, withIntermediateDirectories: true)
        switch zipTransferRole {
        case .source:
            break
        case .destination(zipFileURL: let zipFileURL):
            // We unzip the file
            try await self.unzipFile(atURL: zipFileURL, toDestination: zipDirectoryURL, password: self.password, progressUpdater: progressUpdater)
        }
        self.setTransferTransportLayerState(to: .ready)
        if deleteTemporaryFilesAndZipFileWasCalled {
            self.setTransferTransportLayerState(to: .closed(exportWasCancelledByUser: true))
            throw CancellationError()
        } else {
            self.setTransferTransportLayerState(to: .ready)
        }
    }
    
    func getAsyncStreamOfTransferTransportLayerState() -> AsyncStream<TransferTransportLayerState> {
        let stream = AsyncStream<TransferTransportLayerState> { (continuation: AsyncStream<TransferTransportLayerState>.Continuation) in
            continuationForTransferTransportLayerState?.finish()
            continuationForTransferTransportLayerState = continuation
            yieldAllTransferTransportLayerStates()
        }
        return stream
    }

    func userWantsToCancelTransfer(cancelSource: TransferTransportCancelSource) async {
        self.deleteTemporaryFilesAndZipFile()
    }
    
    func disconnect() async {
        Self.logger.debug("📰 Call to disconnect")
    }
    
    func send(srcDiscussionList: SrcDiscussionList) async throws -> DstExpectedSha256 {
        // In the ZIP transport there is no destination device to negotiate with, so we cannot receive a
        // real reply. We return the most conservative answer: request every attachment the source advertised.
        // This ensures nothing is omitted from the ZIP file.
        return .init(sha256s: srcDiscussionList.sha256s)
    }
    
    func send(srcDiscussionRanges: SrcDiscussionRanges) async throws -> DstDiscussionExpectedRanges {
        Self.logger.debug("📰 Adds discussion (and title) with identifier \(srcDiscussionRanges.discussionIdentifier.identifier.hexString().prefix(8)) to zip")
        self.jsonZipExport = self.jsonZipExport.addingDiscussions(srcDiscussionRanges)
        // In the ZIP transport there is no destination device to negotiate with, so we cannot receive a
        // real reply. We return the most conservative answer.
        return .init(discussionIdentifier: srcDiscussionRanges.discussionIdentifier, rangesByThreadAndSender: srcDiscussionRanges.rangesByThreadAndSender)
    }
        
    
    func send(srcMessages: SrcMessages) async throws {
        Self.logger.debug("📰 Adds \(srcMessages.messages.count) messages to zip for discussion \(srcMessages.discussionIdentifier.identifier.hexString().prefix(8))")
        self.jsonZipExport = self.jsonZipExport.addMessages(srcMessages)
        if srcMessages.sender.getIdentity() != self.ownedCryptoId.getIdentity() {
            self.contactCryptoIds.insert(srcMessages.sender)
        }
    }
    
    
    func send(srcDiscussionDone: SrcDiscussionDone) async throws {
        // No need to send this method when creating a zip file
        Self.logger.debug("📰 Zip is done with discussion \(srcDiscussionDone.discussionIdentifier.identifier.hexString().prefix(8))")
    }

    func send(attachmentAtURL url: URL, sha256: Data, progressUpdater: any FyleProgressUpdater) async throws {
        Self.logger.debug("📰 Adding file \(sha256.hexString().prefix(8)) to the zip archive")
        let attachmentDirectory = try self.createAttachmentDirectoryIfRequired()
        let destinationURL = attachmentDirectory.appendingPathComponent(sha256.hexString())
        do {
            try FileManager.default.linkItem(at: url, to: destinationURL)
        } catch {
            Self.logger.error("📰 Could not create a hardlink to a file, will try to copy the file.")
            try FileManager.default.copyItem(at: url, to: destinationURL)
        }
        guard let fileSize = try? destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            assertionFailure()
            throw ObvError.couldNotDetermineFileSize
        }
        self.jsonZipExport = self.jsonZipExport.addingSha256(sha256, fileSize: UInt64(fileSize))
        await progressUpdater.updateFyleProgress(sha256: sha256, totalNumberOfFyleBytesSent: UInt64(fileSize))
    }
    
    func send(srcTransferDone: SrcTransferDone, progressUpdater: any DoneProgressUpdater) async throws {
        Self.logger.debug("📰 Call to send(srcTransferDone:)")
        do {
            try await addContactsToJsonZipExport()
        } catch {
            Self.logger.error("📰 Could not set contacts in JSON: \(error)") // Continue anyway
        }
        do {
            try await addStaticFilesToZip()
        } catch {
            Self.logger.error("📰 Could not add static files to zip: \(error)") // Continue anyway
        }
        let jsonEncoder = JSONEncoder()
        let encodedJsonZipExport = try jsonEncoder.encode(self.jsonZipExport)
        let jsonZipExportURL = self.zipDirectoryURL.appending(path: JsonZipExport.discussionAndMessagesJsonFileName)
        try encodedJsonZipExport.write(to: jsonZipExportURL)
        // If we reach this point, we have a directory containing all the required information.
        // Its URL is `zipDirectoryURL` and we can zip it now.
        let zipURL = zipDirectoryURL.deletingLastPathComponent().appendingPathComponent("\(directoryName).zip", conformingTo: .zip)
        debugPrint(zipURL)
        debugPrint(zipDirectoryURL.path.appending(".zip"))
        try await self.createZipFile(atURL: zipURL,
                                     withContentsOfDirectory: zipDirectoryURL.path,
                                     password: self.password,
                                     progressUpdater: progressUpdater)
        Self.logger.debug("📰 Did write to \(JsonZipExport.discussionAndMessagesJsonFileName)")
    }
    
    
    private func addContactsToJsonZipExport() async throws {
        guard let dataSource else { assertionFailure(); return }
        let contactDisplaynameForCryptoId = try await dataSource.getDisplayNameOfContacts(ownedCryptoId: self.ownedCryptoId, contactCryptoIds: contactCryptoIds)
        let jsonZipContacts: [JsonZipContact] = contactDisplaynameForCryptoId.map { .init(contactCryptoId: $0, displayName: $1) }
        self.jsonZipExport = self.jsonZipExport.settingContacts(newContacts: jsonZipContacts)
    }
    
    
    private func addStaticFilesToZip() async throws {
        let files: [(resource: String, extension: String)] = [
            ("app", "js"),
            ("index", "html"),
            ("template", "html"),
            ("viewer", "css"),
        ]
        for file in files {
            if let url = ObvHistoryTransferResources.bundle.url(forResource: file.resource, withExtension: file.extension) {
                try FileManager.default.copyItem(at: url, to: self.zipDirectoryURL.appendingPathComponent(url.lastPathComponent))
            }
        }
    }
    
    
    private func createZipFile(atURL url: URL, withContentsOfDirectory directory: String, password: String?, progressUpdater: any DoneProgressUpdater) async throws {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            SSZipArchive.createZipFile(atPath: url.path,
                                       withContentsOfDirectory: directory,
                                       keepParentDirectory: false,
                                       compressionLevel: -1,
                                       password: password,
                                       aes: true) { entryNumber, total in
                Task {
                    if entryNumber >= total {
                        await progressUpdater.updateDoneProgress(entryNumber: entryNumber, total: total, zipFileURL: url)
                        return continuation.resume()
                    } else {
                        await progressUpdater.updateDoneProgress(entryNumber: entryNumber, total: total, zipFileURL: nil)
                    }
                }
            }
        }
    }
    
    
    func getMessageBatchSize() async -> Int {
        return Int.max
    }
    
    func receiveSha256sRequestedByDestination(allSha256ExpectedByDestination: DstExpectedSha256) async throws -> AsyncThrowingStream<Data, any Error> {
        let stream = AsyncThrowingStream<Data, any Error> { (continuation: AsyncThrowingStream<Data, any Error>.Continuation) in
            allSha256ExpectedByDestination.sha256s.keys.forEach { sha256 in
                continuation.yield(sha256)
            }
            continuation.finish()
        }
        return stream
    }
    
}


// MARK: - Implementing TransferTransportSendJsonMessageDelegateForDestination

extension ZipTransferTransportDelegate: TransferTransportSendJsonMessageDelegateForDestination {
    
    /// This is the first method called by the `DestinationTransferSteps`.
    func receiveSrcDiscussionList() async throws -> SrcDiscussionList {
        
        if deleteTemporaryFilesAndZipFileWasCalled {
            throw CancellationError()
        }
    
        let jsonZipExportURL = self.zipDirectoryURL.appending(path: JsonZipExport.discussionAndMessagesJsonFileName)
        guard FileManager.default.fileExists(atPath: jsonZipExportURL.path) else {
            assertionFailure()
            throw ObvError.jsonZipExportURLDoesNotExist
        }
        let jsonZipExportContent = try Data(contentsOf: jsonZipExportURL)
        let jsonDecoder = JSONDecoder()
        let decodedJsonZipExport = try jsonDecoder.decode(JsonZipExport.self, from: jsonZipExportContent)
        
        // Make sure the current jsonZipExport (set during initialization) has the owned identity than the one obtained from the zip
        // file. If this is the case, replace the jsonZipExport with the decoded one.
        
        guard self.jsonZipExport.ownedCryptoId.getIdentity() == decodedJsonZipExport.ownedCryptoId.getIdentity() else {
            throw TransferTransportDelegateError.ownedCryptoIdDoesNotMatch
        }
        
        self.jsonZipExport = decodedJsonZipExport
        
        // Return the discussion list
        
        return try self.jsonZipExport.srcDiscussionList
        
    }
    
    func receiveSrcDiscussionRanges(expectedDiscussionIdentifiers: [JsonDiscussionIdentifier]) async throws -> AsyncThrowingStream<SrcDiscussionRanges, any Error> {
        if deleteTemporaryFilesAndZipFileWasCalled {
            throw CancellationError()
        }
        let stream = self.jsonZipExport.getStreamOfSrcDiscussionRanges(ownedCryptoId: ownedCryptoId, expectedDiscussionIdentifiers: expectedDiscussionIdentifiers)
        return stream
    }
    
    func send(dstExpectedSha256: DstExpectedSha256) async throws {
        // Nothing to do during a zip import
        if deleteTemporaryFilesAndZipFileWasCalled {
            throw CancellationError()
        }
    }
    
    func send(dstDiscussionExpectedRanges: DstDiscussionExpectedRanges) async throws {
        if deleteTemporaryFilesAndZipFileWasCalled {
            throw CancellationError()
        }
        let discussionIdentifier = dstDiscussionExpectedRanges.discussionIdentifier
        guard dstDiscussionExpectedRangesForDiscussion[discussionIdentifier] == nil else {
            assertionFailure()
            throw ObvError.dstDiscussionExpectedRangesAlreadySetForThisDiscussion
        }
        dstDiscussionExpectedRangesForDiscussion[discussionIdentifier] = dstDiscussionExpectedRanges
    }
    
    func receiveStreamOfSrcMessages(numberOfExpectedMessages: Int) async throws -> AsyncThrowingStream<SrcMessages, any Error> {
        if deleteTemporaryFilesAndZipFileWasCalled {
            throw CancellationError()
        }
        let stream = self.jsonZipExport.getStreamOfSrcMessages(numberOfExpectedMessages: numberOfExpectedMessages, dstDiscussionExpectedRangesForDiscussion: dstDiscussionExpectedRangesForDiscussion)
        return stream
    }
    
    
    func send(dstRequestSha256: DstRequestSha256, expectedFileSize: UInt64, progressUpdater: any FyleProgressUpdater) async throws -> URL {
        let attachmentDirectory = self.zipDirectoryURL.appending(path: JsonZipExport.attachmentsDirectoryName, directoryHint: .isDirectory)
        
        let hexString = dstRequestSha256.sha256.hexString()
        let attachmentURL: URL
        let lowercaseURL = attachmentDirectory.appending(component: hexString.lowercased())
        let uppercaseURL = attachmentDirectory.appending(component: hexString.uppercased())
        if FileManager.default.fileExists(atPath: lowercaseURL.path) {
            attachmentURL = lowercaseURL
        } else if FileManager.default.fileExists(atPath: uppercaseURL.path) {
            attachmentURL = uppercaseURL
        } else {
            if deleteTemporaryFilesAndZipFileWasCalled {
                throw CancellationError()
            } else {
                assertionFailure()
                throw ObvError.requestedSha256DoesNotExistInZip
            }
        }
        guard let fileSize = try? attachmentURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            if deleteTemporaryFilesAndZipFileWasCalled {
                throw CancellationError()
            } else {
                assertionFailure()
                throw ObvError.couldNotDetermineFileSize
            }
        }
        guard expectedFileSize == fileSize else {
            assertionFailure()
            throw ObvError.unexpectedFileSize
        }
        return attachmentURL
    }
    
    
    func send(dstDoNotRequestSha256: DstDoNotRequestSha256) async throws {
        let attachmentDirectory = self.zipDirectoryURL.appending(path: JsonZipExport.attachmentsDirectoryName, directoryHint: .isDirectory)
        let attachmentURL = attachmentDirectory.appending(component: dstDoNotRequestSha256.sha256.hexString())
        if FileManager.default.fileExists(atPath: attachmentURL.path) {
            try FileManager.default.removeItem(at: attachmentURL)
        }
    }
    
}


// MARK: - Implementing TransferTransportDelegate

extension ZipTransferTransportDelegate: TransferTransportDelegate {
    
    // All methods are already implemented as we implement TransferTransportSendJsonMessageDelegateForDestination and TransferTransportSendJsonMessageDelegateForSource
    
}

// MARK: - Methods called by the TransferService, specific to this Zip delegate

extension ZipTransferTransportDelegate {
    
    func deleteTemporaryFilesAndZipFile() {
        deleteTemporaryFilesAndZipFileWasCalled = true
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }
    
}


// MARK: - Private methods on destination

extension ZipTransferTransportDelegate {
    
    private func unzipFile(atURL zipFileURL: URL, toDestination destinationURL: URL, password: String?, progressUpdater: any ConnectProgressUpdater) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            SSZipArchive.unzipFile(
                atPath: zipFileURL.path,
                toDestination: destinationURL.path,
                overwrite: true,
                password: password) { entry, zipInfo, entryNumber, total in
                    Self.logger.debug("📰 Unzipping entry \(entryNumber) of \(total)")
                    Task { await progressUpdater.updateConnectProgress(entryNumber: entryNumber, total: total) }
                } completionHandler: { path, succeeded, error in
                    Self.logger.info("📰 Unzipped file (error is \(error))")
                    if let error {
                        return continuation.resume(throwing: error)
                    } else {
                        return continuation.resume()
                    }
                }
        }
    }
    
}


// MARK: - Private methods

extension ZipTransferTransportDelegate {
    
    private func setTransferTransportLayerState(to newTransferTransportLayerState: TransferTransportLayerState) {
        guard self.transferTransportLayerState != newTransferTransportLayerState else { return }
        guard !self.transferTransportLayerState.isClosed else { return }
        transferTransportLayerState = newTransferTransportLayerState
        transferTransportLayerStateOnSetContinuation.insert(newTransferTransportLayerState, at: 0)
        yieldAllTransferTransportLayerStates()
    }

    
    /// Called when the continuation is set, and whenever the transfer transport layer state changes.
    private func yieldAllTransferTransportLayerStates() {
        if let lastYieldedTransferTransportLayerState {
            guard !lastYieldedTransferTransportLayerState.isClosed else { return }
        }
        guard let continuationForTransferTransportLayerState else { return }
        while let state = transferTransportLayerStateOnSetContinuation.popLast() {
            if self.lastYieldedTransferTransportLayerState != state {
                self.lastYieldedTransferTransportLayerState = state
                continuationForTransferTransportLayerState.yield(state)
            }
        }
    }
    
    
    private func createAttachmentDirectoryIfRequired() throws -> URL {
        let attachmentDirectory = self.zipDirectoryURL.appending(path: JsonZipExport.attachmentsDirectoryName, directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: attachmentDirectory.path) {
            try FileManager.default.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)
        }
        return attachmentDirectory
    }

}


// MARK: - Error

extension ZipTransferTransportDelegate {
    
    enum ObvError: Error {
        case jsonZipExportURLDoesNotExist
        case dstDiscussionExpectedRangesAlreadySetForThisDiscussion
        case requestedSha256DoesNotExistInZip
        case couldNotDetermineFileSize
        case unexpectedFileSize
    }
    
}
