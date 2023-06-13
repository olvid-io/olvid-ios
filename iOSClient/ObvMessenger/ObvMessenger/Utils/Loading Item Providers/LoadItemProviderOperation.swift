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
import MobileCoreServices
import os.log
import UIKit
import Contacts
import OlvidUtils
import ObvUI
import ObvUICoreData


/// This operation takes an `itemProvider` and loads it.
///
/// This operation performs the following actions:
/// - It first choose the most appropriate UTI to load. In the "worst" case, we choose the first UTI returned by `registeredTypeIdentifiers`
/// - Then it loads a file representation and copy this file to a temporary location `tempURL`
/// - It keeps track of the UTI and of the file name so as to return an appropriate `loadedFileRepresentation`.
final class LoadItemProviderOperation: OperationWithSpecificReasonForCancel<LoadItemProviderOperationReasonForCancel>, OperationProvidingLoadedItemProvider {
    
    private let preferredUTIs = [kUTTypeFileURL, kUTTypeJPEG, kUTTypePNG, kUTTypeMPEG4, kUTTypeMP3, kUTTypeQuickTimeMovie].map({ $0 as String })
    private let ignoredUTIs = [UTI.Bitmoji.avatarID, UTI.Bitmoji.comicID, UTI.Bitmoji.packID, UTI.Apple.groupActivitiesActivity]

    private let itemProviderOrItemURL: ItemProviderOrItemURL
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "LoadItemProviderOperation")

    // Called iff a progress is available for tracking the loading progress
    private let progressAvailable: (Progress) -> Void
    
    convenience init(itemURL: URL, progressAvailable: @escaping (Progress) -> Void) {
        self.init(itemProviderOrItemURL: .itemURL(url: itemURL), progressAvailable: progressAvailable)
    }
    
    convenience init(itemProvider: NSItemProvider, progressAvailable: @escaping (Progress) -> Void) {
        self.init(itemProviderOrItemURL: .itemProvider(itemProvider: itemProvider), progressAvailable: progressAvailable)
    }
    
    init(itemProviderOrItemURL: ItemProviderOrItemURL, progressAvailable: @escaping (Progress) -> Void) {
        self.itemProviderOrItemURL = itemProviderOrItemURL
        self.progressAvailable = progressAvailable
        super.init()
    }
    
    private var _isFinished = false {
        willSet { willChangeValue(for: \.isFinished) }
        didSet { didChangeValue(for: \.isFinished) }
    }
    override var isFinished: Bool { _isFinished }

    override func cancel(withReason reason: LoadItemProviderOperationReasonForCancel) {
        assert(self.reasonForCancel == nil)
        self.reasonForCancel = reason
        self.cancel()
        _isFinished = true
    }

    private(set) var loadedItemProvider: LoadedItemProvider?

    override func main() {
        
        switch itemProviderOrItemURL {
        case .itemProvider(itemProvider: let itemProvider):
            process(itemProvider)
        case .itemURL(url: let url):
            process(url)
        }
    }
    
    // Available in certain cases, depending on the "load" method used
    private var operationProgress: Progress?
    
    private func process(_ itemURL: URL) {
        assert(!itemURL.path.contains("PluginKitPlugin")) // This is a particular case, but we know the loading won't work in that case
        let uti = ObvUTIUtils.utiOfFile(atURL: itemURL) ?? String(kUTTypeData)
        let filename = (itemURL as NSURL).lastPathComponent ?? "File"
        loadedItemProvider = .file(tempURL: itemURL, uti: uti, filename: filename)
        _isFinished = true
        return
    }
    
    
    private func process(_ itemProvider: NSItemProvider) {

        // Find the most appropriate UTI to load
        
        let availableTypeIdentifiers = itemProvider.registeredTypeIdentifiers(fileOptions: NSItemProviderFileOptions(rawValue: 0))
        os_log("Available type identifiers of the attachment: %{public}@", log: log, type: .info, availableTypeIdentifiers.debugDescription)
        guard !availableTypeIdentifiers.isEmpty else { assertionFailure(); return cancel(withReason: .itemHasNoRegisteredTypeIdentifier) }
        
        let filteredTypeIdentifiers = availableTypeIdentifiers.filter({ !ignoredUTIs.contains($0) })
        guard !filteredTypeIdentifiers.isEmpty else {
            os_log("No acceptable UTI was found, we do not load any item provider", log: log, type: .info)
            _isFinished = true
            return
        }

        let availablePreferredUTIs = preferredUTIs.filter({ filteredTypeIdentifiers.contains($0) })
        let utiToLoad: String
        if !availablePreferredUTIs.isEmpty {
            // This is the easy case, where the file provider does provide an UTI we "prefer"
            utiToLoad = preferredUTIs.first(where: { availablePreferredUTIs.contains($0) })!
        } else {
            // There is no "preferred" UTI available. We simply take the first UTI available
            assert(filteredTypeIdentifiers.count == 1, "We should have a special rule and include one of the UTIs in the list of preferred UTIs")
            utiToLoad = filteredTypeIdentifiers.first!
        }

        assert(itemProvider.hasItemConformingToTypeIdentifier(utiToLoad))
        
        // We have found an appropriate UTI for the item provider
        // We can load it
        
        os_log("Type identifier to load is: %{public}@", log: log, type: .info, utiToLoad)

        var progress: Progress?
        
        if utiToLoad.utiConformsTo(kUTTypeVCard) {
        
            os_log("Type identifier to load conforms to kUTTypeVCard", log: log, type: .info)

            progress = itemProvider.loadDataRepresentation(forTypeIdentifier: String(kUTTypeVCard), completionHandler: { [weak self] (data, error) in
                guard error == nil else {
                    if let progress = self?.operationProgress, progress.isCancelled {
                        // The user cancelled the file loading, there is nothing left to do
                        self?._isFinished = true
                        return
                    } else {
                        self?.cancel(withReason: .loadFileRepresentationFailed(error: error!))
                        return
                    }
                }
                guard let data = data, let cnContacts = try? CNContactVCardSerialization.contacts(with: data) else {
                    self?.cancel(withReason: .couldNotLoadVCard)
                    return
                }
                assert(cnContacts.count == 1)
                guard let contact = cnContacts.first else {
                    self?.cancel(withReason: .couldNotLoadVCard)
                    return
                }
                let contactName = [contact.givenName, contact.familyName].joined(separator: "-")
                let filename = [contactName, "vcf"].joined(separator: ".")
                let tempURL = ObvUICoreDataConstants.ContainerURL.forTempFiles.appendingPathComponent(filename)
                do {
                    let contactData = try CNContactVCardSerialization.data(with: [contact])
                    try contactData.write(to: tempURL)
                } catch {
                    self?.cancel(withReason: .couldNotCopyItem(error: error))
                    return
                }
                self?.loadedItemProvider = .file(tempURL: tempURL, uti: utiToLoad, filename: filename)
                self?._isFinished = true
                return
            })
            
        } else if utiToLoad.utiConformsTo(kUTTypeText) {
            
            os_log("Type identifier to load conforms to kUTTypeText", log: log, type: .info)

            itemProvider.loadItem(forTypeIdentifier: String(kUTTypeText)) { [weak self] (item, error) in
                guard error == nil else {
                    self?.cancel(withReason: .loadFileRepresentationFailed(error: error!))
                    return
                }
                if let text = item as? String {
                    self?.loadedItemProvider = .text(content: text)
                    self?._isFinished = true
                    return
                } else if let url = item as? URL {
                    let filename = url.lastPathComponent
                    let tempURL = ObvUICoreDataConstants.ContainerURL.forTempFiles.appendingPathComponent(UUID().uuidString)
                    do {
                        try FileManager.default.copyItem(at: url, to: tempURL)
                    } catch {
                        self?.cancel(withReason: .couldNotCopyItem(error: error))
                        return
                    }
                    self?.loadedItemProvider = .file(tempURL: tempURL, uti: String(kUTTypeText), filename: filename)
                    self?._isFinished = true
                    return
                } else {
                    self?.cancel(withReason: .couldNotLoadString)
                    return
                }
            }
                   
        } else if utiToLoad.utiConformsTo(kUTTypeFileURL) {
            
            os_log("Type identifier to load conforms to kUTTypeFileURL", log: log, type: .info)

            itemProvider.loadItem(forTypeIdentifier: String(kUTTypeFileURL)) { [weak self] (item, error) in
                guard error == nil else {
                    self?.cancel(withReason: .loadFileRepresentationFailed(error: error!))
                    return
                }
                guard let pickerURL = item as? URL else {
                    self?.cancel(withReason: .pickerURLIsNil)
                    return
                }
                let filename = pickerURL.lastPathComponent
                let tempURL = ObvUICoreDataConstants.ContainerURL.forTempFiles.appendingPathComponent(UUID().uuidString)
                do {
                    try FileManager.default.copyItem(at: pickerURL, to: tempURL)
                } catch {
                    self?.cancel(withReason: .couldNotCopyItem(error: error))
                    return
                }
                let utiForFile = ObvUTIUtils.utiOfFile(atURL: pickerURL) ?? utiToLoad
                self?.loadedItemProvider = .file(tempURL: tempURL, uti: utiForFile, filename: filename)
                self?._isFinished = true
                return

            }
            
        } else if utiToLoad.utiConformsTo(kUTTypeURL) {
            
            os_log("Type identifier to load conforms to kUTTypeURL", log: log, type: .info)

            itemProvider.loadItem(forTypeIdentifier: String(kUTTypeURL)) { [weak self] (item, error) in
                guard error == nil else {
                    self?.cancel(withReason: .loadFileRepresentationFailed(error: error!))
                    return
                }
                guard let url = item as? URL else {
                    self?.cancel(withReason: .couldNotLoadURL)
                    return
                }
                self?.loadedItemProvider = .url(content: url)
                self?._isFinished = true
                return
            }
            
        } else if utiToLoad == String(kUTTypeImage) {

            os_log("Type identifier to load is kUTTypeImage", log: log, type: .info)

            // Note that we do not check whether the uti "conforms" to kUTTypeImage. This would be the case of jpeg and png images, which we want to load "as is"
            
            itemProvider.loadItem(forTypeIdentifier: String(kUTTypeImage)) { [weak self] (item, error) in
                guard error == nil else {
                    self?.cancel(withReason: .loadFileRepresentationFailed(error: error!))
                    return
                }
                guard let image = item as? UIImage else {
                    assertionFailure()
                    self?.cancel(withReason: .noneOfTheItemTypeIdentifiersCouldBeLoaded(itemTypeIdentifiers: availableTypeIdentifiers))
                    return
                }
                let filename: String
                let data: Data
                let utiForFile: String
                if let pngData = image.pngData() {
                    filename = "image.png"
                    data = pngData
                    utiForFile = kUTTypePNG as String
                } else if let jpegData = image.jpegData(compressionQuality: 1.0) {
                    filename = "image.jpeg"
                    data = jpegData
                    utiForFile = kUTTypeJPEG as String
                } else {
                    self?.cancel(withReason: .noneOfTheItemTypeIdentifiersCouldBeLoaded(itemTypeIdentifiers: availableTypeIdentifiers))
                    return
                }
                let tempURL = ObvUICoreDataConstants.ContainerURL.forTempFiles.appendingPathComponent(UUID().uuidString)

                // If we reach this point, we were able to load png or jpeg data
                do {
                    try data.write(to: tempURL)
                } catch {
                    self?.cancel(withReason: .couldNotCopyItem(error: error))
                    return
                }
                self?.loadedItemProvider = .file(tempURL: tempURL, uti: utiForFile, filename: filename)
                self?._isFinished = true
                return

            }
            
        } else {
            
            os_log("Type identifier requires to load a file representation", log: log, type: .info)
            let log = self.log
            progress = itemProvider.loadFileRepresentation(forTypeIdentifier: utiToLoad) { [weak self] (url, error) in
                os_log("Within the completion handler of loadFileRepresentation", log: log, type: .info)
                guard error == nil else {
                    os_log("The loadFileRepresentation completion returned an error: %{public}@", log: log, type: .info, String(describing: error?.localizedDescription))
                    if let progress = self?.operationProgress, progress.isCancelled {
                        // The user cancelled the file loading, there is nothing left to do
                        self?._isFinished = true
                        return
                    } else {
                        self?.cancel(withReason: .loadFileRepresentationFailed(error: error!))
                        return
                    }
                }
                guard let pickerURL = url else {
                    self?.cancel(withReason: .pickerURLIsNil)
                    return
                }
                let filename = pickerURL.lastPathComponent
                let tempURL = ObvUICoreDataConstants.ContainerURL.forTempFiles.appendingPathComponent(UUID().uuidString)
                do {
                    try FileManager.default.copyItem(at: pickerURL, to: tempURL)
                } catch {
                    self?.cancel(withReason: .couldNotCopyItem(error: error))
                    return
                }
                self?.loadedItemProvider = .file(tempURL: tempURL, uti: utiToLoad, filename: filename)
                self?._isFinished = true
                return
            }

        }
        
        // If a progress is available at this point, we call the appropriate callback.
        // This typically allows not give a progress to the CompositionViewFreezeManager
        if let progress = progress {
            operationProgress = progress
            progressAvailable(progress)
        }

    }
    
}


enum ItemProviderOrItemURL {
    case itemProvider(itemProvider: NSItemProvider)
    case itemURL(url: URL)
}


enum LoadedItemProvider {
    case file(tempURL: URL, uti: String, filename: String)
    case text(content: String)
    case url(content: URL)
}


fileprivate extension String {
    func utiConformsTo(_ otherUTI: CFString) -> Bool {
        UTTypeConformsTo(self as CFString, otherUTI)
    }
}


enum LoadItemProviderOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case noneOfTheItemTypeIdentifiersCouldBeLoaded(itemTypeIdentifiers: [String])
    case loadFileRepresentationFailed(error: Error)
    case pickerURLIsNil
    case itemHasNoRegisteredTypeIdentifier
    case couldNotCopyItem(error: Error)
    case couldNotLoadString
    case couldNotLoadURL
    case couldNotLoadVCard

    var logType: OSLogType {
        return .fault
    }
    
    var errorDescription: String? {
        switch self {
        case .noneOfTheItemTypeIdentifiersCouldBeLoaded(itemTypeIdentifiers: let itemTypeIdentifiers):
            return "None of the item type identifiers could be loaded: \(itemTypeIdentifiers.debugDescription)"
        case .loadFileRepresentationFailed(error: let error):
            return "Failed to load representation: \(error.localizedDescription)"
        case .pickerURLIsNil:
            return "Picker URL is nil, which is unexpected"
        case .couldNotCopyItem(error: let error):
            return "Could not copy item: \(error.localizedDescription)"
        case .itemHasNoRegisteredTypeIdentifier:
            return "The item provides no registered type identifier"
        case .couldNotLoadString:
            return "Could not load String"
        case .couldNotLoadURL:
            return "Could not load URL"
        case .couldNotLoadVCard:
            return "Could not load VCard"
        }
    }
}


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
