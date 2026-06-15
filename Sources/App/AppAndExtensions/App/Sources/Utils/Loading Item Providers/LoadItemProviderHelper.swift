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
import MobileCoreServices
import UniformTypeIdentifiers
import OSLog
import UIKit
import Contacts
import OlvidUtils
import ObvUI
import ObvUICoreData
import ObvSettings
import ObvAppCoreConstants
import LinkPresentation
import ObvAppTypes


struct LoadedItemProviderToAttach {
    let tempURL: URL
    let fileType: UTType
    let filename: String
}

enum LoadedItemProviderToPaste {
    case text(content: String)
    case url(content: URL)
    var textToPaste: String {
        switch self {
        case .text(let text): return text
        case .url(let url): return url.absoluteString
        }
    }
    var isURL: Bool {
        switch self {
        case .text: return false
        case .url: return true
        }
    }
}


enum LoadedItemProvider {
    case toPaste(LoadedItemProviderToPaste)
    case toAttach(LoadedItemProviderToAttach)
}

extension [LoadedItemProvider] {
    var toPaste: [LoadedItemProviderToPaste] {
        return self.compactMap { loadedItemProvider in
            switch loadedItemProvider {
            case .toAttach: return nil
            case .toPaste(let loadedItemProviderToPaste): return loadedItemProviderToPaste
            }
        }
    }
    var toAttach: [LoadedItemProviderToAttach] {
        return self.compactMap { loadedItemProvider in
            switch loadedItemProvider {
            case .toPaste: return nil
            case .toAttach(let loadedItemProviderToAttach): return loadedItemProviderToAttach
            }
        }
    }
}

actor LoadItemProviderHelper {
    
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "LoadItemProviderHelper")

    private static let preferredTypes: [UTType] = [.fileURL, .jpeg, .png, .pdf, .mpeg4Movie, .mp3, .quickTimeMovie, .gif, .appleLinkpresentationMetadata, .webInternetLocation, .webP, .url, .utf8PlainText]
    private static let ignoredTypes: Set<UTType?> = Set([.groupActivitiesActivity, .Bitmoji.avatarID, .Bitmoji.comicID, .Bitmoji.packID, .appleFilesAppFile, .appleFinderNode])

    private struct UTTypesOfNSItemProvider: Sendable {
        let availableContentTypes: [UTType]
        let filteredContentTypes: [UTType]
        let preferredContentTypes: [UTType]
    }
    
    private static func filterContentTypes(registeredBy itemProvider: NSItemProvider) -> UTTypesOfNSItemProvider  {
        let availableContentTypes = itemProvider.registeredTypeIdentifiers(fileOptions: NSItemProviderFileOptions(rawValue: 0))
            .compactMap({ UTType($0) })
        Self.logger.info("Available type identifiers of the attachment: \(availableContentTypes.debugDescription, privacy: .public)")
        let filteredContentTypes = availableContentTypes.filter({ !Self.ignoredTypes.contains($0) })
        Self.logger.info("Filtered type identifiers of the attachment: \(filteredContentTypes.debugDescription, privacy: .public)")
        let preferredContentTypes = preferredTypes.filter({ filteredContentTypes.contains($0) })
        Self.logger.info("Preferred type identifiers of the attachment: \(preferredContentTypes.debugDescription, privacy: .public)")
        return UTTypesOfNSItemProvider(availableContentTypes: availableContentTypes,
                                       filteredContentTypes: filteredContentTypes,
                                       preferredContentTypes: preferredContentTypes)
    }
    
    private static func determineBestUTTypeToLoad(from types: UTTypesOfNSItemProvider) -> UTType? {
        types.preferredContentTypes.first ?? types.filteredContentTypes.first
    }

    
    /// This is notably used when importing files from the Files App under iOS from the compose message view.
    func load(_ itemURL: URL) -> LoadedItemProviderToAttach {
        assert(!itemURL.path.contains("PluginKitPlugin")) // This is a particular case, but we know the loading won't work in that case
        let fileType: UTType = Self.determineFileType(at: itemURL)
        let filename = (itemURL as NSURL).lastPathComponent ?? "File"
        let loadedItemProviderToAttach = LoadedItemProviderToAttach(tempURL: itemURL, fileType: fileType, filename: filename)
        return loadedItemProviderToAttach
    }
    

    func load(_ itemURLs: [URL]) -> [LoadedItemProviderToAttach] {
        return itemURLs.map { self.load($0) }
    }

    
    func load(_ itemProviders: [NSItemProvider], source: ItemProviderProviderSource, progressProvider: ((Progress) -> Void)?) async throws -> [LoadedItemProvider] {
        let loadedItemProviders = try await withThrowingTaskGroup(of: [LoadedItemProvider].self, returning: [LoadedItemProvider].self) { taskGroup in
            for itemProvider in itemProviders {
                taskGroup.addTask {
                    let loadedItemProviders = try await self.load(itemProvider, source: source, progressProvider: nil)
                    return loadedItemProviders
                }
            }
            var loadedItemProviders: [LoadedItemProvider] = []
            for try await value in taskGroup {
                loadedItemProviders.append(contentsOf: value)
            }
            return loadedItemProviders
        }
        return loadedItemProviders
    }
    
    
    enum ItemProviderProviderSource {
        case dragAndDrop
        case paste
        case shareExtension
        case none
        case photoPicker
    }
    

    /// Loads one (or several) `LoadedItemProvider` for the given `NSItemProvider`.
    ///
    /// One case where several `LoadedItemProvider` instances are returned for the same `NSItemProvider` is when the item has a registered `UTType.appleLinkpresentationMetadata`.
    /// In that case, we return an URL to paste in the composition view, as well as a file URL containing an `ObvLinkMetadata` to add as an attachment to the draft.
    func load(_ itemProvider: NSItemProvider, source: ItemProviderProviderSource, progressProvider: ((Progress) -> Void)?) async throws -> [LoadedItemProvider] {
        
        let typesOfNSItemProvider = Self.filterContentTypes(registeredBy: itemProvider)
        guard let contentTypeToLoad = Self.determineBestUTTypeToLoad(from: typesOfNSItemProvider) else {
            Self.logger.fault("Could not find an appropriate UTType to load")
            throw ObvError.couldNotFindAppropriateUTTypeToLoad
        }
        
        Self.logger.info("Content type to load is: \(contentTypeToLoad.debugDescription, privacy: .public)")

        switch contentTypeToLoad {
            
        case .folder:
            
            Self.logger.info("Type identifier to load conforms to UTType.folder")
            
            // Occurs when a folder is shared, e.g., by droping a folder in the discussion under macOS.
            // Since obvLoadFileRepresentation() returns a file in a fresh temporary directory, we can safely create the zip file there.

            let folderURL = try await itemProvider.obvLoadFileRepresentation(for: contentTypeToLoad)
            let urlOfDestinationZipFile = folderURL.appendingPathExtension(UTType.zip.preferredFilenameExtension ?? "zip")
            try await FileManager.default.obvZipDirectory(at: folderURL, urlOfDestinationZipFile: urlOfDestinationZipFile)
            let loadedItemProviderToAttach = LoadedItemProviderToAttach(tempURL: urlOfDestinationZipFile, fileType: .zip, filename: urlOfDestinationZipFile.lastPathComponent)
            return [.toAttach(loadedItemProviderToAttach)]

        case .webInternetLocation:
            
            Self.logger.info("Type identifier to load conforms to UTType.webInternetLocation")

            if itemProvider.canLoadObject(ofClass: URL.self) {
                // Occurs when:
                // - performing a drag of a website URL from the URL bar of Safari, then a drop in the discussion view (Chrome has a distinct behaviour)
                let url = try await itemProvider.obvLoadObject(ofClass: URL.self, progressProvider: progressProvider)
                let loadedItemProviderToPaste = LoadedItemProviderToPaste.url(content: url)
                return [.toPaste(loadedItemProviderToPaste)]
            }
            
            if itemProvider.canLoadObject(ofClass: String.self) {
                let text = try await itemProvider.obvLoadObject(ofClass: String.self, progressProvider: progressProvider)
                let loadedItemProviderToPaste = LoadedItemProviderToPaste.text(content: text)
                return [.toPaste(loadedItemProviderToPaste)]
            }
            
            assertionFailure()
            throw ObvError.couldNotLoadObject
            
        case contentTypeToLoad where contentTypeToLoad.conforms(to: .vCard):
            
            // Occurs when:
            // - sharing a contact from the Contacts app
            // - droping a vcard from the Contacts app under macOS

            Self.logger.info("Type identifier to load conforms to UTType.vCard")

            let urlOfVcfFile = try await itemProvider.obvLoadObjectAsVCFFile(progressProvider: progressProvider)
            
            let loadedItemProviderToAttach = LoadedItemProviderToAttach(tempURL: urlOfVcfFile, fileType: .vCard, filename: urlOfVcfFile.lastPathComponent)
            return [.toAttach(loadedItemProviderToAttach)]
            
        case let contentTypeToLoad where contentTypeToLoad.conforms(to: .fileURL):
            
            // Occurs when:
            // - sharing a pdf file from the Files App
            // - sharing a .txt file from the Files App on iOS
            // - performing a copy of a file under the macOS Finder, and a paste in the composition view

            Self.logger.info("Type identifier to load conforms to UTType.fileURL")

            let tempURL = try await itemProvider.obvLoadItemToTemporaryFileForTypeFileURL(logger: Self.logger)

            let fileType = (try? tempURL.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? contentTypeToLoad
            
            if fileType == .folder {

                // Occurs when sharing a folder from the Files app under iOS
                
                let urlOfDestinationZipFile = tempURL.appendingPathExtension(UTType.zip.preferredFilenameExtension ?? "zip")
                try await FileManager.default.obvZipDirectory(at: tempURL, urlOfDestinationZipFile: urlOfDestinationZipFile)
                try? FileManager.default.removeItem(at: tempURL)
                let loadedItemProviderToAttach = LoadedItemProviderToAttach(tempURL: urlOfDestinationZipFile, fileType: .zip, filename: urlOfDestinationZipFile.lastPathComponent)
                return [.toAttach(loadedItemProviderToAttach)]

            } else {

                let loadedItemProviderToAttach = LoadedItemProviderToAttach(tempURL: tempURL, fileType: fileType, filename: tempURL.lastPathComponent)
                return [.toAttach(loadedItemProviderToAttach)]

            }
            
        case let contentTypeToLoad where contentTypeToLoad.conforms(to: .appleLinkpresentationMetadata):
            
            Self.logger.info("Type identifier to load conforms to UTType.appleLinkpresentationMetadata")
            
            let urlOfLPLinkMetadata = try await itemProvider.obvLoadFileRepresentation(for: .appleLinkpresentationMetadata)
            let dataOfLPLinkMetadata = try Data(contentsOf: urlOfLPLinkMetadata)
            
            if let lpLinkMetadata = try NSKeyedUnarchiver.unarchivedObject(ofClass: LPLinkMetadata.self, from: dataOfLPLinkMetadata), let originalURL = lpLinkMetadata.originalURL {
                
                var loadedItemProviders: [LoadedItemProvider] = [.toPaste(.url(content: originalURL))]
                
                // Try to attach an ObvLinkMetadata. We don't fail if this does not succeed.
                do {
                    let obvLinkMetadata = await ObvLinkMetadata.from(linkMetadata: lpLinkMetadata)
                    let result = try obvLinkMetadata.saveToTemporaryFile()
                    let loadedItemProviderToAttach = LoadedItemProviderToAttach(tempURL: result.tempURL, fileType: .olvidLinkPreview, filename: result.filename)
                    loadedItemProviders.append(.toAttach(loadedItemProviderToAttach))
                } catch {
                    Self.logger.error("Could not attach an ObviouslyLinkMetadata: \(error). We only return the url") // Continue anyway
                }
                
                return loadedItemProviders
                
            }

            assertionFailure()
            throw ObvError.couldNotLoadObject


        case let contentTypeToLoad where contentTypeToLoad.conforms(to: .text):
            
            Self.logger.info("Type identifier to load conforms to UTType.text")

            let registeredTypeIdentifiers = itemProvider.registeredTypeIdentifiers(fileOptions: NSItemProviderFileOptions(rawValue: 0))
                .compactMap({ UTType($0) })
            let isTextFileDroppedFromFinder = registeredTypeIdentifiers.contains(.appleFinderNode)
            let isTextFilePastedFromFilesApp = registeredTypeIdentifiers.contains(.appleFilesAppFile)

            let attachAsFile: Bool
            if isTextFileDroppedFromFinder || isTextFilePastedFromFilesApp {
                attachAsFile = true
            } else {
                switch source {
                case .dragAndDrop:
                    // This is mandatory to make things work under iPad, where the NSItemProvider alone does not allow to distinguish
                    // between "text" and "text file".
                    attachAsFile = true
                case .paste:
                    attachAsFile = false
                case .shareExtension:
                    attachAsFile = false
                case .none:
                    assertionFailure("In case of text, we should always specify a context")
                    attachAsFile = false
                case .photoPicker:
                    assertionFailure("Unexpected in case of text")
                    attachAsFile = true
                }
            }
            
            if attachAsFile {
                
                // Occurs when:
                // - performing a drop of a text file in the discussion view under macOS
                // - performing a copy of a text file in the Files App under iOS, then pasting in the composition view
                // - performing a drop of a text file in the discussion view from the Files App under iPadOS (in that case, setting a break point before the call to obvLoadFileRepresentation seems to break execution)
                
                let tempURL = try await itemProvider.obvLoadFileRepresentation(for: .text)

                let fileType = (try? tempURL.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? .text

                let loadedItemProviderToAttach = LoadedItemProviderToAttach(tempURL: tempURL, fileType: fileType, filename: tempURL.lastPathComponent)
                return [.toAttach(loadedItemProviderToAttach)]

            } else {
                
                if itemProvider.canLoadObject(ofClass: String.self), let text = try? await itemProvider.obvLoadObject(ofClass: String.self, progressProvider: progressProvider) {
                    // Occurs when:
                    // - selecting text in Safari under iOS/macOS, then pasting the text in the compose view
                    let loadedItemProviderToPaste = LoadedItemProviderToPaste.text(content: text)
                    return [.toPaste(loadedItemProviderToPaste)]
                }
                
                let item = try await itemProvider.obvLoadItem(forType: .text)

                if let text = item as? String {
                    // Occurs when:
                    // - selecting text in Safari, then sharing the text
                    let loadedItemProviderToPaste = LoadedItemProviderToPaste.text(content: text)
                    return [.toPaste(loadedItemProviderToPaste)]
                }
                
            }
            
            assertionFailure()
            throw ObvError.couldNotLoadObject
            
        case let contentTypeToLoad where contentTypeToLoad.conforms(to: .url):
                        
            // Occurs when:
            // - force-press on a link, then choose share

            Self.logger.info("Type identifier to load conforms to UTType.url")
            
            if itemProvider.canLoadObject(ofClass: URL.self), let url = try? await itemProvider.obvLoadObject(ofClass: URL.self, progressProvider: progressProvider) {
                // Occurs when:
                // - under iPad, tap on share under Safari, copy, then paste in the composition view.
                let loadedItemProviderToPaste = LoadedItemProviderToPaste.url(content: url)
                return [.toPaste(loadedItemProviderToPaste)]
            }

            if let url = try? await itemProvider.obvLoadItem(forType: .url) as? URL {
                // Occurs when sharing:
                // - a website from Safari (not a Web Archive)
                let loadedItemProviderToPaste = LoadedItemProviderToPaste.url(content: url)
                return [.toPaste(loadedItemProviderToPaste)]
            }
            
            if let url = try? await itemProvider.obvLoadObject(ofClass: NSURL.self, progressProvider: progressProvider) as? URL {
                // Occurs when:
                // - performing a drop of an URL in the discussion view under macOS, when dragged from the URL bar of Chrome (Safari has a distinct behaviour)
                let loadedItemProviderToPaste = LoadedItemProviderToPaste.url(content: url)
                return [.toPaste(loadedItemProviderToPaste)]
            }
            
            assertionFailure()
            throw ObvError.couldNotLoadObject

        case let contentTypeToLoad where contentTypeToLoad == .image:
            
            Self.logger.info("Type identifier to load is UTType.image")

            // Note that we do not check whether the uti "conforms" to UTType.image.
            // This would be the case of jpeg and png images, which we want to load "as is" (i.e., using the loadFileRepresentation API)

            let (tempURL, contentTypeOfFile) = try await itemProvider.obvLoadItemToTemporaryFileForTypeImage()
            
            let loadedItemProviderToAttach = LoadedItemProviderToAttach(tempURL: tempURL, fileType: contentTypeOfFile, filename: tempURL.lastPathComponent)
            return [.toAttach(loadedItemProviderToAttach)]

        case let contentTypeToLoad where contentTypeToLoad == .olvidLinkPreview:
            
            Self.logger.info("Type identifier to load is UTType.olvidLinkPreview")

            let result = try await itemProvider.obvLoadItemToTemporaryFileForTypeOlvidLinkPreview(logger: Self.logger)
            
            let loadedItemProviderToAttach = LoadedItemProviderToAttach(tempURL: result.url, fileType: contentTypeToLoad, filename: result.filename)
            return [.toAttach(loadedItemProviderToAttach)]

        default:

            // Occurs when:
            // - sharing a Web Archive from Safari (not a website URL)
            // - sharing a Web site exported to pdf from Safari
            // - sharing a jpeg file from the Photos app
            // - importing a photo from the Photo picker in the composition view

            Self.logger.info("Type identifier requires to load a file representation")

            do {
                
                let tempURL = try await itemProvider.obvLoadFileRepresentation(for: contentTypeToLoad)
                
                let fileType = (try? tempURL.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? contentTypeToLoad
                
                let loadedItemProviderToAttach = LoadedItemProviderToAttach(tempURL: tempURL, fileType: fileType, filename: tempURL.lastPathComponent)
                return [.toAttach(loadedItemProviderToAttach)]
                
            } catch {
                
                Self.logger.error("Could not load file representation: \(error)")
                
            }
            
            do {
                
                if let data = try await itemProvider.obvLoadItem(forType: .data) as? Data {
                    let emptyTempDir = try FileManager.default.createEmptyTemporaryDirectoryForLoadedNSItemProviders()
                    let filename: String
                    if let suggestedName = itemProvider.suggestedName {
                        filename = suggestedName
                    } else {
                        let fileExtension = contentTypeToLoad.preferredFilenameExtension ?? "data"
                        filename = ["file", fileExtension].joined(separator: ".")
                    }
                    let tempURL = emptyTempDir.appendingPathComponent(filename)
                    try data.write(to: tempURL)

                    let fileType = (try? tempURL.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? contentTypeToLoad

                    let loadedItemProviderToAttach = LoadedItemProviderToAttach(tempURL: tempURL, fileType: fileType, filename: tempURL.lastPathComponent)
                    return [.toAttach(loadedItemProviderToAttach)]

                }

            } catch {
                
                Self.logger.error("Could not load item as Data: \(error)")

            }

            assertionFailure()
            throw ObvError.couldNotLoadObject

        }
        
    }
    
    
    /// When this helper loads an NSItemProvider, it creates a temporary directory to store the loaded file.
    /// After the file is moved (e.g., when creating an attachment for a draft), the temporary directory becomes empty.
    /// This method cleans up such empty directories during the bootstrap process.
    nonisolated
    static func requestDeletionOfObsoleteDirectoriesForLoadedNSItemProviders() {
        Task {
            do {
                try FileManager.default.deleteEmptyTemporaryDirectoriesForLoadedNSItemProviders()
                Self.logger.info("Obsolete directories for loaded NSItemProviders were deleted")
            } catch {
                Self.logger.fault("Obsolete directories for loaded NSItemProviders could not be deleted: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    
    enum ObvError: Error {
        case couldNotFindAppropriateUTTypeToLoad
        case couldNotLoadObject
        case couldNotLoadVCard
        case pickerURLIsNil
        case itemIsNotUIImage
        case couldParseUIImage
        case itemIsNotObvLinkMetadata
        case fileRepresentationURLIsNil
    }
    
    
    private static func determineFileType(at url: URL) -> UTType {
        if (url as NSURL).pathExtension == UTType.olvidBackup.preferredFilenameExtension {
            return .olvidBackup
        } else if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type
        } else {
            return .data
        }
    }

}


// MARK: - NSItemProvider extension for loading data representations

fileprivate extension NSItemProvider {
    
    /// Trivial wrapper around the ``NSItemProvider.loadDataRepresentation(for:completionHandler:)`` method since it is only available under iOS 16
    func obvLoadDataRepresentation(for contentType: UTType, completionHandler: @escaping @Sendable (Data?, (Error)?) -> Void) -> Progress {
        if #available(iOS 16, *) {
            return loadDataRepresentation(for: contentType, completionHandler: completionHandler)
        } else {
            return loadDataRepresentation(forTypeIdentifier: contentType.identifier, completionHandler: completionHandler)
        }
    }

}


// MARK: - NSItemProvider extension for loading file representation

fileprivate extension NSItemProvider {
    
    /// Asynchronous wrapper around the ``NSItemProvider.loadFileRepresentation(forTypeIdentifier typeIdentifier: String, completionHandler: @escaping @Sendable (URL?, (any Error)?) -> Void)`` method.
    /// - Parameter contentType: The content type to load.
    /// - Returns: A temporary URL to the loaded fyle.
    ///
    /// The wrapped method writes a copy of the file’s data to a temporary file, which the system deletes when the completion handler returns. For this reason, this method
    /// copies the provided temporary file to another temporary file.
    func obvLoadFileRepresentation(for contentType: UTType) async throws -> URL {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, any Error>) in
            self.loadFileRepresentation(forTypeIdentifier: contentType.identifier) { (url, error) in
                do {
                    if let error {
                        throw error
                    } else {
                        guard let url else {
                            throw LoadItemProviderHelper.ObvError.fileRepresentationURLIsNil
                        }
                        let filename = url.lastPathComponent
                        let emptyTempDir = try FileManager.default.createEmptyTemporaryDirectoryForLoadedNSItemProviders()
                        let tempURL = emptyTempDir.appendingPathComponent(filename)
                        try FileManager.default.copyItem(at: url, to: tempURL)
                        return continuation.resume(returning: tempURL)
                    }
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }

    
}


// MARK: - NSItemProvider extension for loading items

fileprivate extension NSItemProvider {
    
    /// Simple wrapper around ``loadItem(forTypeIdentifier:options:)`` making it possible to use a `UTType` instead of a type identifier.
    func obvLoadItem(forType type: UTType, options: [AnyHashable : Any]? = nil) async throws -> any NSSecureCoding {
        try await self.loadItem(forTypeIdentifier: type.identifier, options: options)
    }

    
    /// Simple wrapper around ``loadItem(forTypeIdentifier:options:completionHandler:)`` making it possible to use a `UTType` instead of a type identifier.
    func obvLoadItem(forType type: UTType, options: [AnyHashable : Any]? = nil, completionHandler: NSItemProvider.CompletionHandler? = nil) {
        self.loadItem(forTypeIdentifier: type.identifier, options: options, completionHandler: completionHandler)
    }

    
    /// In case `self` conforms to `UTType.fileURL`, this method returns an URL to a file (in a temporary directory) which is a copy of the file
    /// referenced by `self`.
    func obvLoadItemToTemporaryFileForTypeFileURL(logger: Logger) async throws -> URL  {
        // First, try to resolve a URL from the item and copy it directly.
        // This works in most cases (e.g., Files app, macOS Finder paste), but may fail when the source
        // app's sandbox prevents direct access (e.g., when pasting a photo copied from Messages).
        do {
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, any Error>) in
                self.obvLoadItem(forType: .fileURL) { (item, error) in
                    do {
                        if let error {
                            throw error
                        } else {
                            let pickerURL: URL
                            if let url = item as? URL {
                                pickerURL = url
                            } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                                // Occurs when performing a copy of a file in the macOS Finder, and a paste in the composition view
                                pickerURL = url
                            } else {
                                throw LoadItemProviderHelper.ObvError.pickerURLIsNil
                            }
                            let filename = pickerURL.lastPathComponent
                            let emptyTempDir = try FileManager.default.createEmptyTemporaryDirectoryForLoadedNSItemProviders()
                            let tempURL = emptyTempDir.appendingPathComponent(filename)
                            try FileManager.default.copyItem(at: pickerURL, to: tempURL)
                            return continuation.resume(returning: tempURL)
                        }
                    } catch {
                        return continuation.resume(throwing: error)
                    }
                }
            }
        } catch {
            // The direct copy failed (e.g., the source URL is in another app's sandbox and is not accessible).
            // Fall back to loadFileRepresentation, which the system uses to safely copy the file into a
            // temporary location we can access.
            logger.info("obvLoadItemToTemporaryFileForTypeFileURL: direct copy failed (\(error.localizedDescription, privacy: .public)), falling back to loadFileRepresentation")
            return try await self.obvLoadFileRepresentation(for: .fileURL)
        }
    }
    
    
    /// In case `self` is a `UTType.image`, this method returns an URL to a file (in a temporary directory) which is
    /// either an png or a jpeg version of the image.
    /// - Returns: The (temporary) URL of the png or jpeg file, and the content type of the fyle (which is either `.png` or `.jpeg`)
    func obvLoadItemToTemporaryFileForTypeImage() async throws -> (tempURL: URL, contentTypeOfFile: UTType) {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(tempURL: URL, contentTypeOfFile: UTType), any Error>) in
            self.obvLoadItem(forType: .image) { (item, error) in
                do {
                    if let error {
                        throw error
                    } else {
                        guard let image = item as? UIImage else {
                            throw LoadItemProviderHelper.ObvError.itemIsNotUIImage
                        }
                        let filename: String
                        let data: Data
                        let contentTypeOfFile: UTType
                        if let pngData = image.pngData() {
                            filename = "image.png"
                            data = pngData
                            contentTypeOfFile = .png
                        } else if let jpegData = image.jpegData(compressionQuality: 1.0) {
                            filename = "image.jpeg"
                            data = jpegData
                            contentTypeOfFile = .jpeg
                        } else {
                            throw LoadItemProviderHelper.ObvError.couldParseUIImage
                        }
                        let emptyTempDir = try FileManager.default.createEmptyTemporaryDirectoryForLoadedNSItemProviders()
                        let tempURL = emptyTempDir.appendingPathComponent(filename)
                        try data.write(to: tempURL)
                        return continuation.resume(returning: (tempURL, contentTypeOfFile))
                    }
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
    
    
    func obvLoadItemToTemporaryFileForTypeOlvidLinkPreview(logger: Logger) async throws -> (url: URL, filename: String) {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(url: URL, filename: String), any Error>) in
            self.obvLoadItem(forType: .olvidLinkPreview) { (item, error) in
                do {
                    if let error {
                        throw error
                    } else {
                        guard let metadata = item as? ObvLinkMetadata else {
                            assertionFailure()
                            throw LoadItemProviderHelper.ObvError.itemIsNotObvLinkMetadata
                        }
                        let (tempURL, filename) = try metadata.saveToTemporaryFile()
                        return continuation.resume(returning: (tempURL, filename))
                    }
                } catch {
                    logger.fault("Could not load item to temporary file for type .olvidLinkPreview: \(error)")
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
    
}


fileprivate extension ObvLinkMetadata {
    
    func saveToTemporaryFile() throws -> (tempURL: URL, filename: String) {
        let filename: String = self.url?.absoluteString ?? UUID().uuidString
        let emptyTempDir = try FileManager.default.createEmptyTemporaryDirectoryForLoadedNSItemProviders()
        let tempURL = emptyTempDir.appendingPathComponent(UUID().uuidString)
        let data: Data = try self.obvEncode().rawData
        try data.write(to: tempURL)
        return (tempURL, filename)
    }

}


// MARK: - NSItemProvider extension for loading objects

fileprivate extension NSItemProvider {

    /// Simple asynchronous wrapper around `loadObject<T>(ofClass: T.Type, completionHandler: @escaping @Sendable (T?, (any Error)?) -> Void)`.
    /// - Parameters:
    ///   - aClass: The class to load.
    ///   - progressProvider: If specified, this block is called as soon as a progress is available.
    /// - Returns: The loaded object.
    func obvLoadObject<T>(ofClass aClass: T.Type, progressProvider: ((Progress) -> Void)?) async throws -> T where T : _ObjectiveCBridgeable, T._ObjectiveCType : NSItemProviderReading {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, any Error>) in
            let progress = self.loadObject(ofClass: aClass) { (item, error) in
                if let error {
                    return continuation.resume(throwing: error)
                } else {
                    guard let item else {
                        assertionFailure()
                        return continuation.resume(throwing: LoadItemProviderHelper.ObvError.couldNotLoadObject)
                    }
                    return continuation.resume(returning: item)
                }
            }
            progressProvider?(progress)
        }
    }

    
    /// Simple asynchronous wrapper around `loadObject(ofClass aClass: any NSItemProviderReading.Type, completionHandler: @escaping @Sendable ((any NSItemProviderReading)?, (any Error)?)`.
    /// - Parameters:
    ///   - aClass: The class to load.
    ///   - progressProvider: If specified, this block is called as soon as a progress is available.
    /// - Returns: The loaded object.
    func obvLoadObject(ofClass objectClass: any NSItemProviderReading.Type, progressProvider: ((Progress) -> Void)?) async throws -> any NSItemProviderReading {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<any NSItemProviderReading, any Error>) in
            let progress = self.loadObject(ofClass: objectClass) { (item, error) in
                if let error {
                    return continuation.resume(throwing: error)
                } else {
                    guard let item else {
                        assertionFailure()
                        return continuation.resume(throwing: LoadItemProviderHelper.ObvError.couldNotLoadObject)
                    }
                    return continuation.resume(returning: item)
                }
            }
            progressProvider?(progress)
        }
    }

    
    /// In case `self` conforms to `UTType.vCard`, this methods return an URL to a `.vcf` file (in a temporary directory) that contains the `.vcard` information.
    func obvLoadObjectAsVCFFile(progressProvider: ((Progress) -> Void)?) async throws -> URL {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, any Error>) in
            let progress = self.obvLoadDataRepresentation(for: .vCard, completionHandler: { (data, error) in
                do {
                    if let error {
                        throw error
                    } else {
                        guard let data else {
                            assertionFailure()
                            throw LoadItemProviderHelper.ObvError.couldNotLoadObject
                        }
                        let cnContacts = try CNContactVCardSerialization.contacts(with: data)
                        assert(cnContacts.count == 1)
                        guard let contact = cnContacts.first else {
                            throw LoadItemProviderHelper.ObvError.couldNotLoadVCard
                        }
                        let contactName = [contact.givenName, contact.familyName].joined(separator: "-")
                        let filename = [contactName, "vcf"].joined(separator: ".")
                        let tempURL = ObvUICoreDataConstants.ContainerURL.forTempFiles.appendingPathComponent(filename)
                        let contactData = try CNContactVCardSerialization.data(with: [contact])
                        try contactData.write(to: tempURL)
                        return continuation.resume(returning: tempURL)
                    }
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            })
            progressProvider?(progress)
        }
    }
    
}


// MARK: - FileManager extension

fileprivate extension FileManager {
    
    private var pathOfTemporaryDirectoryURLForLoadedItemsProviders: URL { ObvUICoreDataConstants.ContainerURL.forTempFiles.appendingPathComponent("LoadedNSItemProviders") }
    
    func createEmptyTemporaryDirectoryForLoadedNSItemProviders() throws -> URL {
        let temporaryDirectoryName = UUID().uuidString
        let temporaryDirectoryURLWithName = pathOfTemporaryDirectoryURLForLoadedItemsProviders.appendingPathComponent(temporaryDirectoryName)
        try self.createDirectory(at: temporaryDirectoryURLWithName, withIntermediateDirectories: true, attributes: nil)
        return temporaryDirectoryURLWithName
    }
 
    func deleteEmptyTemporaryDirectoriesForLoadedNSItemProviders() throws {
        let contents = try self.contentsOfDirectory(at: pathOfTemporaryDirectoryURLForLoadedItemsProviders,
                                                    includingPropertiesForKeys: [URLResourceKey.isDirectoryKey],
                                                    options: [])
        for content in contents {
            var isDirectory: ObjCBool = false
            if self.fileExists(atPath: content.path, isDirectory: &isDirectory), isDirectory.boolValue {
                // content is a directory
                if try self.contentsOfDirectory(at: content, includingPropertiesForKeys: nil, options: []).isEmpty {
                    // content is an empty directory
                    try self.removeItem(at: content)
                }
            }
        }
    }
    
}


// MARK: - Other extensions

fileprivate struct UTI {
    
    struct Bitmoji {
        static let avatarID = "com.bitmoji.metadata.avatarID"
        static let packID = "com.bitmoji.metadata.packID"
        static let comicID = "com.bitmoji.metadata.comicID"
    }
    
    struct Apple {
        static let groupActivitiesActivity = "com.apple.group-activities.activity"
    }
    
}


fileprivate extension UTType {
    
    static var groupActivitiesActivity: UTType? {
        .init("com.apple.group-activities.activity")
    }
    
    struct Bitmoji {
        static var avatarID: UTType? {
            .init("com.bitmoji.metadata.avatarID")
        }
        static var packID: UTType? {
            .init("com.bitmoji.metadata.packID")
        }
        static var comicID: UTType? {
            .init("com.bitmoji.metadata.comicID")
        }
    }
    
    
    static var appleFilesAppFile: UTType {
        .init(importedAs: "com.apple.DocumentManager.FINode.File") // Imported type in Info.plist
    }

    static var appleFinderNode: UTType {
        .init(importedAs: "com.apple.finder.node") // Imported type in Info.plist
    }
    
    static var appleLinkpresentationMetadata: UTType {
        .init(importedAs: "com.apple.linkpresentation.metadata") // Imported type in Info.plist
    }
    
}
