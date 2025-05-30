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
import os.log
import QuickLook
import MobileCoreServices
import CoreData
import ObvUICoreData
import ObvSettings
import ObvAppCoreConstants


/// The purpose of this coordinator is to manage all the hard links to fyles within Olvid. It subscribes to `RequestHardLinkToFyle` notifications.
/// These notifications provide a completion handler that this coordinator calls on a background thread as soon as a hard link is avaible for the requested
/// fyle.
///
/// At launch, this coordinator also cleans any hard link created during past launch of the App.
final class HardLinksToFylesManager {
    
    fileprivate static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: HardLinksToFylesManager.self))
    
    /// This directory will contain all the hardlinks
    private let currentSessionDirectoryForHardlinks: URL
    
    /// Directories created in previous sessions. We delete all these directories in a background thread.
    private let previousDirectories: [URL]
    
    private let queueForDeletingPreviousDirectories = DispatchQueue(label: "Queue for deleting previous directories containing hard links")
    
    private let queueForNotifications = OperationQueue.createSerialQueue(name: "HardLinksToFylesManager serial queue")
    
    private var observationTokens = [NSObjectProtocol]()

    private var appType: ObvUICoreDataConstants.AppCategory

    static func makeHardLinksToFylesManagerForMainApp() -> Self {
        let url = ObvUICoreDataConstants.ContainerURL.forFylesHardlinksWithinMainApp.url
        return Self(appType: .mainApp, url: url)
    }

    static func makeHardLinksToFylesManagerForShareExtension() -> Self {
        let url = ObvUICoreDataConstants.ContainerURL.forFylesHardlinksWithinShareExtension.url
        return Self(appType: .shareExtension, url: url)
    }

    private init(appType: ObvUICoreDataConstants.AppCategory, url: URL) {
        self.appType = appType
        self.previousDirectories = try! FileManager.default.contentsOfDirectory(atPath: url.path).map { url.appendingPathComponent($0) }
        self.currentSessionDirectoryForHardlinks = url.appendingPathComponent(UUID().description)
        try! FileManager.default.createDirectory(at: self.currentSessionDirectoryForHardlinks, withIntermediateDirectories: true, attributes: nil)
        deletePreviousDirectories()
        observeNotifications()
    }
    
    
    private func observeNotifications() {
        observationTokens.append(contentsOf: [
            ObvMessengerCoreDataNotification.observePersistedMessagesWereDeleted(queue: queueForNotifications) { [weak self] (discussionPermanentID, messagePermanentIDs) in
                self?.processPersistedMessagesWereWipedOrDeleted(discussionPermanentID: discussionPermanentID, messagePermanentIDs: messagePermanentIDs)
            },
            ObvMessengerCoreDataNotification.observePersistedDiscussionWasDeleted(queue: queueForNotifications) { [weak self] discussionPermanentID, _ in
                self?.processPersistedDiscussionWasDeletedNotification(discussionPermanentID: discussionPermanentID)
            },
            ObvMessengerCoreDataNotification.observePersistedMessagesWereWiped(queue: queueForNotifications) { [weak self] (discussionPermanentID, messagePermanentIDs) in
                self?.processPersistedMessagesWereWipedOrDeleted(discussionPermanentID: discussionPermanentID, messagePermanentIDs: messagePermanentIDs)
            },
            ObvMessengerInternalNotification.observeDraftToSendWasReset(queue: queueForNotifications) { [weak self] (discussionPermanentID, draftPermanentID) in
                self?.processDraftToSendWasResetNotification(discussionPermanentID: discussionPermanentID, draftPermanentID: draftPermanentID)
            },
            ObvMessengerInternalNotification.observeDraftFyleJoinWasDeleted(queue: queueForNotifications) { [weak self] (discussionPermanentID, draftPermanentID, draftFyleJoinPermanentID) in
                self?.processDraftFyleJoinWasDeletedNotification(discussionPermanentID: discussionPermanentID, draftPermanentID: draftPermanentID, draftFyleJoinPermanentID: draftFyleJoinPermanentID)
            },
            ObvMessengerInternalNotification.observeFyleMessageJoinWasWiped(queue: queueForNotifications) { [weak self] (discussionPermanentID, messagePermanentID, fyleMessageJoinPermanentID) in
                self?.processFyleMessageJoinWasWiped(discussionPermanentID: discussionPermanentID, messagePermanentID: messagePermanentID, fyleMessageJoinPermanentID: fyleMessageJoinPermanentID)
            },
            HardLinksToFylesNotifications.observeRequestHardLinkToFyle() { [weak self] (fyleElement, completionHandler) in
                self?.requestHardLinkToFyle(fyleElement: fyleElement, completionHandler: completionHandler)
            },
            HardLinksToFylesNotifications.observeRequestAllHardLinksToFyles() { [weak self] (fyleElements, completionHandler) in
                self?.requestAllHardLinksToFyles(fyleElements: fyleElements, completionHandler: completionHandler)
            },
        ])
    }
    
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        self.deleteCurrentDirectory()
    }
    
    
    private static let errorDomain = "HardLinksToFylesManager"
    private static func makeError(message: String) -> Error { NSError(domain: errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    
    private func deleteCurrentDirectory() {
        os_log("We will delete the current directory at %{public}@", log: Self.log, type: .info, currentSessionDirectoryForHardlinks.path)
        do {
            try FileManager.default.removeItem(at: currentSessionDirectoryForHardlinks)
            os_log("The current directory at %{public}@ was deleted", log: Self.log, type: .info, currentSessionDirectoryForHardlinks.path)
        } catch let error {
            os_log("Could not delete directory at %{public}@: %{public}@", log: Self.log, type: .error, currentSessionDirectoryForHardlinks.path, error.localizedDescription)
        }
    }
    
    
    private func deletePreviousDirectories() {
        queueForDeletingPreviousDirectories.async { [weak self] in
            guard let _self = self else { return }
            for url in _self.previousDirectories {
                do {
                    os_log("We will delete a previous directory at %{public}@", log: Self.log, type: .info, url.path)
                    try FileManager.default.removeItem(at: url)
                    os_log("We deleted a previous directory at %{public}@", log: Self.log, type: .info, url.path)
                } catch let error {
                    os_log("Could not delete directory at %{public}@: %{public}@", log: Self.log, type: .error, url.path, error.localizedDescription)
                }
            }
        }
    }

    // MARK: Public request API

    func requestHardLinkToFyle(fyleElement: FyleElement, completionHandler: @escaping (Result<HardLinkToFyle, Error>) -> Void) {
        queueForNotifications.addOperation {
            do {
                let hardlink = try HardLinkToFyle(fyleElement: fyleElement, currentSessionDirectoryForHardlinks: self.currentSessionDirectoryForHardlinks, log: Self.log)
                completionHandler(.success(hardlink))
                return
            } catch {
                os_log("Failed to create HardLink: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                completionHandler(.failure(error))
                return
            }
        }
    }

    func requestAllHardLinksToFyles(fyleElements: [FyleElement], completionHandler: @escaping ([HardLinkToFyle?]) -> Void) {
        queueForNotifications.addOperation {
            let hardlinks = fyleElements.map {
                try? HardLinkToFyle(fyleElement: $0, currentSessionDirectoryForHardlinks: self.currentSessionDirectoryForHardlinks, log: Self.log)
            }
            completionHandler(hardlinks)
        }
    }

    // MARK: Processing notifications

    private func processPersistedMessagesWereWipedOrDeleted(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentIDs: Set<ObvManagedObjectPermanentID<PersistedMessage>>) {
        for messagePermanentID in messagePermanentIDs {
            do {
                try FyleElementForFyleMessageJoinWithStatus.trashMessageDirectory(
                    discussionPermanentID: discussionPermanentID,
                    messagePermanentID: messagePermanentID,
                    in: currentSessionDirectoryForHardlinks)
            } catch {
                os_log("Failed to delete hard links of message: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
        }
        do {
            try FyleElementForFyleMessageJoinWithStatus.trashDiscussionDirectoryIfEmpty(
                discussionPermanentID: discussionPermanentID,
                in: currentSessionDirectoryForHardlinks)
        } catch {
            os_log("Failed to delete hard links of message: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }
    
    
    private func processPersistedDiscussionWasDeletedNotification(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>) {
        do {
            try FyleElementForFyleMessageJoinWithStatus.trashDiscussionDirectory(
                discussionPermanentID: discussionPermanentID,
                in: currentSessionDirectoryForHardlinks)
        } catch {
            os_log("Failed to delete hard links of discussion: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }


    private func processDraftToSendWasResetNotification(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>) {
        do {
            try FyleElementForPersistedDraftFyleJoin.trashDraftDirectory(
                discussionPermanentID: discussionPermanentID,
                draftPermanentID: draftPermanentID,
                in: currentSessionDirectoryForHardlinks)
            try FyleElementForFyleMessageJoinWithStatus.trashDiscussionDirectoryIfEmpty(
                discussionPermanentID: discussionPermanentID,
                in: currentSessionDirectoryForHardlinks)
        } catch {
            os_log("Failed to delete hard links of draft: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }

    private func processDraftFyleJoinWasDeletedNotification(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, draftFyleJoinPermanentID: ObvManagedObjectPermanentID<PersistedDraftFyleJoin>) {
        do {
            try FyleElementForPersistedDraftFyleJoin.trashDraftFyleJoinDirectory(
                discussionPermanentID: discussionPermanentID,
                draftPermanentID: draftPermanentID,
                draftFyleJoinPermanentID: draftFyleJoinPermanentID,
                in: currentSessionDirectoryForHardlinks)
            try FyleElementForFyleMessageJoinWithStatus.trashDiscussionDirectoryIfEmpty(
                discussionPermanentID: discussionPermanentID,
                in: currentSessionDirectoryForHardlinks)
        } catch {
            os_log("Failed to delete hard links of draft fyle join: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }
    
    
    private func processFyleMessageJoinWasWiped(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentID: ObvManagedObjectPermanentID<PersistedMessage>, fyleMessageJoinPermanentID: ObvManagedObjectPermanentID<FyleMessageJoinWithStatus>) {
        do {
            try FyleElementForFyleMessageJoinWithStatus.trashFyleMessageJoinWithStatusDirectory(
                discussionPermanentID: discussionPermanentID,
                messagePermanentID: messagePermanentID,
                fyleMessageJoinPermanentID: fyleMessageJoinPermanentID,
                in: currentSessionDirectoryForHardlinks)
            try FyleElementForFyleMessageJoinWithStatus.trashMessageDirectoryIfEmpty(
                discussionPermanentID: discussionPermanentID,
                messagePermanentID: messagePermanentID,
                in: currentSessionDirectoryForHardlinks)
            try FyleElementForFyleMessageJoinWithStatus.trashDiscussionDirectoryIfEmpty(
                discussionPermanentID: discussionPermanentID,
                in: currentSessionDirectoryForHardlinks)
        } catch {
            os_log("Failed to delete hard link to fyle message join: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }

}

// MARK: - HardLinkToFyle

final class HardLinkToFyle: NSObject, QLPreviewItem {

    let creationDate = Date()
    let contentType: UTType
    let fyleURL: URL
    let fileName: String
    private(set) var hardlinkURL: URL?
    private(set) var activityItemProvider: ActivityItemProvider?
    private(set) var itemProvider: NSItemProvider?
    private(set) var uiDragItem: UIDragItem?

    override func isEqual(_ object: Any?) -> Bool {
        guard let otherObject = object as? HardLinkToFyle else { return false }
        return self.contentType == otherObject.contentType && self.fyleURL == otherObject.fyleURL && self.fileName == otherObject.fileName && self.hardlinkURL == otherObject.hardlinkURL
    }
    
    override var debugDescription: String {
        "HardLinkToFyle(creationDate: \(creationDate.debugDescription) contentType: \(contentType.debugDescription), fileName: \(fileName), fyleURL: \(fyleURL), hardlinkURL: \(hardlinkURL?.path ?? "nil")"
    }
    
    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(contentType)
        hasher.combine(fyleURL)
        hasher.combine(fileName)
        hasher.combine(hardlinkURL)
        return hasher.finalize()
    }
    
    private static func makeError(message: String) -> Error { NSError(domain: "HardLinkToFyle", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { HardLinkToFyle.makeError(message: message) }


    final class ActivityItemProvider: UIActivityItemProvider, @unchecked Sendable {
        
        private let hardlinkURL: URL
        private let contentType: UTType
        
        fileprivate init(hardlinkURL: URL, contentType: UTType) {
            self.hardlinkURL = hardlinkURL
            self.contentType = contentType
            super.init(placeholderItem: hardlinkURL)
        }
        
        override var item: Any {
            return hardlinkURL
        }

        var excludedActivityTypes: [UIActivity.ActivityType]? {
            if contentType.conforms(to: .image) {
                return [.openInIBooks]
            } else {
                return []
            }
        }

    }
    

    fileprivate init(fyleElement: FyleElement, currentSessionDirectoryForHardlinks: URL, log: OSLog) throws {
        let log = HardLinksToFylesManager.log
        os_log("Starting creation of HardLinkToFyle for fyle %{public}@", log: log, type: .info, fyleElement.fyleURL.lastPathComponent)
        self.contentType = fyleElement.contentType
        self.fyleURL = fyleElement.fyleURL
        self.fileName = fyleElement.fileName
        self.itemProvider = NSItemProvider(fyleElement: fyleElement)
        self.uiDragItem = UIDragItem(fyleElement: fyleElement)
        guard fyleElement.fullFileIsAvailable else {
            os_log("Since the full file for fyle %{public}@ is not available, the hardlink won't contain a hardlink URL", log: log, type: .info, fyleElement.fyleURL.lastPathComponent)
            self.hardlinkURL = nil
            self.activityItemProvider = nil
            super.init()
            return
        }
        os_log("Since the full file for fyle %{public}@ is available, we create a hardlink on disk now", log: log, type: .info, fyleElement.fyleURL.lastPathComponent)
        let directoryForHardLink = fyleElement.directoryForHardLink(in: currentSessionDirectoryForHardlinks)
        try FileManager.default.createDirectory(at: directoryForHardLink, withIntermediateDirectories: true, attributes: nil)
        let appropriateFilename = HardLinkToFyle.determineAppropriateFilename(originalFilename: fyleElement.fileName, contentType: fyleElement.contentType)
        let hardlinkURL = directoryForHardLink.appendingPathComponent(appropriateFilename, isDirectory: false)
        try HardLinkToFyle.linkOrCopyItem(at: fyleElement.fyleURL, to: hardlinkURL, log: log)
        self.hardlinkURL = hardlinkURL
        self.activityItemProvider = ActivityItemProvider(hardlinkURL: hardlinkURL, contentType: fyleElement.contentType)
        super.init()
    }
    

    private static func determineAppropriateFilename(originalFilename: String, contentType: UTType) -> String {
        let escapedFilename = originalFilename.escapedStringForFyleElementDirectoryOrFilename()
        // We have a specific case of .m4a files to fix the issue where Android sends audio/mpeg as a MIME type of .m4a files
        if let contentTypeFromFilename = UTType(filenameExtension: (originalFilename as NSString).pathExtension), (contentTypeFromFilename == contentType || contentTypeFromFilename.conforms(to: .mpeg4Audio)) {
            return escapedFilename
        } else if let preferredFilenameExtension = contentType.preferredFilenameExtension {
            return [String(escapedFilename.prefix(ObvMessengerConstants.maxCountForFilename-preferredFilenameExtension.count-1)), preferredFilenameExtension].joined(separator: ".")
        } else {
            return String(escapedFilename.prefix(ObvMessengerConstants.maxCountForFilename))
        }
    }
    

    
    private static func linkOrCopyItem(at fyleURL: URL, to hardlinkURL: URL, log: OSLog) throws {
        let log = HardLinksToFylesManager.log
        os_log("Trying to link or copy item to disk during the creation of the HardLinkToFyle for fyle %{public}@ to the following hardlink URL: %{public}@", log: log, type: .info, fyleURL.lastPathComponent, hardlinkURL.description)
        guard !FileManager.default.fileExists(atPath: hardlinkURL.path) else {
            os_log("The hardlink URL already exists for the HardLinkToFyle for fyle %{public}@", log: log, type: .info, fyleURL.lastPathComponent)
            return
        }
        do {
            try FileManager.default.linkItem(at: fyleURL, to: hardlinkURL)
        } catch {
            os_log("Could not create hardlink for fyle %{public}@: %{public}@. We try to copy the file.", log: log, type: .error, fyleURL.lastPathComponent, error.localizedDescription)
            do {
                try FileManager.default.copyItem(at: fyleURL, to: hardlinkURL)
            } catch let error {
                os_log("Could not create hardlink: %{public}@", log: log, type: .fault, error.localizedDescription)
                throw error
            }
        }
        os_log("a hardlink was created for fyle %{public}@", log: log, type: .info, fyleURL.lastPathComponent)
    }

    // MARK: QLPreviewItem
    
    var previewItemURL: URL? {
        return self.hardlinkURL
    }
    
    var previewItemTitle: String? {
        if self.hardlinkURL == nil {
            return CommonString.Title.downloadingFile
        } else {
            return nil // Keep default title
        }
    }

}

extension FyleJoin {
    var genericFyleElement: FyleElement? {
        return FyleElementForDraftFyleJoin(self)
    }
}

struct FyleElementForDraftFyleJoin: FyleElement {
    
    let fileName: String
    let contentType: UTType
    //let uti: String
    let fullFileIsAvailable: Bool
    let fyleURL: URL
    let sha256: Data

    init?(_ fyleJoin: FyleJoin) {
        guard let fyle = fyleJoin.fyle else { return nil }
        self.fileName = fyleJoin.fileName
        self.contentType = fyleJoin.contentType
        self.fullFileIsAvailable = true
        self.fyleURL = fyle.url
        self.sha256 = fyle.sha256
    }
    
    private init(fileName: String, contentType: UTType, fullFileIsAvailable: Bool, fyleURL: URL, sha256: Data) {
        self.fileName = fileName
        self.contentType = contentType
        self.fullFileIsAvailable = fullFileIsAvailable
        self.fyleURL = fyleURL
        self.sha256 = sha256
    }

    
    static func makeError(message: String) -> Error { NSError(domain: "FyleElementForDraftFyleJoin", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    func directoryForHardLink(in currentSessionDirectoryForHardlinks: URL) -> URL {
        currentSessionDirectoryForHardlinks
            .appendingPathComponent(sha256.hexString(), isDirectory: true)
    }
    
    func replacingFullFileIsAvailable(with newFullFileIsAvailable: Bool) -> FyleElement {
        Self.init(fileName: fileName, contentType: contentType, fullFileIsAvailable: newFullFileIsAvailable, fyleURL: fyleURL, sha256: sha256)
    }
}


// MARK: - System types' extensions

fileprivate extension NSItemProvider {
    
    convenience init?(fyleElement: FyleElement) {
        guard fyleElement.fullFileIsAvailable else { return nil }
        self.init(item: fyleElement.fyleURL as NSURL, typeIdentifier: fyleElement.contentType.identifier)
        self.suggestedName = fyleElement.fileName
    }
    
}


fileprivate extension UIDragItem {
    
    convenience init?(fyleElement: FyleElement) {
        guard fyleElement.fullFileIsAvailable else { return nil }
        guard let itemProvider = NSItemProvider(fyleElement: fyleElement) else { return nil }
        self.init(itemProvider: itemProvider)
    }
    
}
