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

import UIKit
import QuickLook


@available(iOS 15.0, *)
final class DiscussionCacheManager: DiscussionCacheDelegate {
    
    private struct HardlinkAndSize: Hashable {
        let hardlink: HardLinkToFyle
        let size: CGSize
        func hash(into hasher: inout Hasher) {
            hasher.combine(hardlink)
            hasher.combine(size.width)
            hasher.combine(size.height)
        }
    }

    private var imageCache = [HardlinkAndSize: UIImage]()
    private var imageCacheCompletions = [HardlinkAndSize: [(Bool) -> Void]]()
    
    private var dataDetectedCache = [String: UIDataDetectorTypes]()
    private var dataDetectedCacheCompletions = [String: [(Bool) -> Void]]()
    
    private var linkCache = [String: [URL]]()

    private var hardlinksCache = [TypeSafeManagedObjectID<FyleMessageJoinWithStatus>: HardLinkToFyle]()
    private var hardlinksCacheCompletions = [TypeSafeManagedObjectID<PersistedMessage>: [(Bool) -> Void]]()
    
    private var replyToCache = [TypeSafeManagedObjectID<PersistedMessage>: ReplyToBubbleView.Configuration]()
    private var replyToCacheCompletions = [TypeSafeManagedObjectID<PersistedMessage>: [(Result<Void, Error>) -> Void]]()

    private var downsizedThumbnailCache = [TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>: UIImage]()
    private var downsizedThumbnailCacheCompletions = [TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>: [(Result<Void, Error>) -> Void]]()

    private let internalQueue = DispatchQueue(label: "DiscussionCacheManager internal queue")
    
    private let backgroundContext = ObvStack.shared.newBackgroundContext()
    
    private static func makeError(message: String) -> Error {
        NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message])
    }
    private func makeError(message: String) -> Error {
        DiscussionCacheManager.makeError(message: message)
    }

    func getCachedHardlinkForFyleMessageJoinWithStatus(with objectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>) -> HardLinkToFyle? {
        assert(Thread.isMainThread)
        return hardlinksCache[objectID]
    }
    
    
    func requestAllHardlinksForMessage(with objectID: TypeSafeManagedObjectID<PersistedMessage>, completionWhenHardlinksCached: @escaping ((Bool) -> Void)) {
        
        assert(Thread.isMainThread)
        
        guard let message = try? PersistedMessage.get(with: objectID, within: ObvStack.shared.viewContext) else {
            // Can happen if the message has just been deleted
            completionWhenHardlinksCached(false)
            return
        }
        
        // Create a list of joins/fyleElements for which we want to request hardlinks

        let joinObjectIDs: [TypeSafeManagedObjectID<FyleMessageJoinWithStatus>]
        let fyleElements: [FyleElement]
        do {
            var joins = [FyleMessageJoinWithStatus]()
            if let sentMessage = message as? PersistedMessageSent {
                joins.append(contentsOf: sentMessage.fyleMessageJoinWithStatuses as [FyleMessageJoinWithStatus])
            } else if let receivedMessage = message as? PersistedMessageReceived {
                joins.append(contentsOf: receivedMessage.fyleMessageJoinWithStatuses as [FyleMessageJoinWithStatus])
            } else {
                assertionFailure()
            }

            if let replyTo = try? message.getReplyTo(), let joinsFromReplyTo = replyTo.fyleMessageJoinWithStatus {
                joins.append(contentsOf: joinsFromReplyTo)
            }
            guard !joins.isEmpty else {
                completionWhenHardlinksCached(false)
                return
            }
            joinObjectIDs = joins.map({ $0.typedObjectID })
            fyleElements = joins.compactMap({ $0.fyleElement })
            guard fyleElements.count == joins.count else {
                // This can happen when a message is remotely wiped (e.g. when someone else did delete a message for all participants of a discussion)
                completionWhenHardlinksCached(false)
                return
            }
        }
        
        // Store the completion
        
        if var completions = hardlinksCacheCompletions[objectID] {
            completions.append(completionWhenHardlinksCached)
            hardlinksCacheCompletions[objectID] = completions
            return
        } else {
            hardlinksCacheCompletions[objectID] = [completionWhenHardlinksCached]
        }

        // Request hardlinks
        
        ObvMessengerInternalNotification.requestAllHardLinksToFyles(fyleElements: fyleElements) { hardlinks in
            DispatchQueue.main.async { [weak self] in
                var cellNeedsToUpdateItsConfiguration = false
                for (joinObjectID, hardlink) in zip(joinObjectIDs, hardlinks) {
                    if let cachedHardlink = self?.hardlinksCache[joinObjectID] {
                        if cachedHardlink != hardlink {
                            self?.hardlinksCache[joinObjectID] = hardlink
                            cellNeedsToUpdateItsConfiguration = true
                        }
                    } else {
                        self?.hardlinksCache[joinObjectID] = hardlink
                        cellNeedsToUpdateItsConfiguration = true
                    }
                }
                guard let completionsToCall = self?.hardlinksCacheCompletions.removeValue(forKey: objectID) else { return }
                for completionToCall in completionsToCall {
                    completionToCall(cellNeedsToUpdateItsConfiguration)
                }
            }
        }.postOnDispatchQueue()
        
    }

    func getCachedDataDetection(text: String) -> UIDataDetectorTypes? {
        return dataDetectedCache[text]
    }


    func requestDataDetection(text: String, completionWhenDataDetectionCached: @escaping ((Bool) -> Void)) {
        
        assert(Thread.isMainThread)
        
        if let dataDetected = getCachedDataDetection(text: text) {
            completionWhenDataDetectionCached(!dataDetected.isEmpty)
            return
        }
        
        if var completions = dataDetectedCacheCompletions[text] {
            completions.append(completionWhenDataDetectionCached)
            dataDetectedCacheCompletions[text] = completions
            return
        } else {
            dataDetectedCacheCompletions[text] = [completionWhenDataDetectionCached]
            internalQueue.async {
                let dataDetected = text.containsDetectableData()
                DispatchQueue.main.async { [weak self] in
                    guard let _self = self else { return }
                    assert(_self.dataDetectedCache[text] == nil)
                    _self.dataDetectedCache[text] = dataDetected
                    guard let completions = _self.dataDetectedCacheCompletions.removeValue(forKey: text) else { assertionFailure(); return }
                    for completion in completions {
                        completion(!dataDetected.isEmpty)
                    }
                }
            }
        }
        
    }
    

    func getFirstHttpsURL(text: String) -> URL? {
        if let urls = linkCache[text] {
            return urls.first
        } else {
            let urls = text.getHttpsURLs()
            linkCache[text] = urls
            return urls.first
        }
    }

    
    func getCachedImageForHardlink(hardlink: HardLinkToFyle, size: CGSize) -> UIImage? {
        return imageCache[HardlinkAndSize(hardlink: hardlink, size: size)]
    }
    
    
    /// The completion handler returns `true` in case of success, `false` otherwise
    func requestImageForHardlink(hardlink: HardLinkToFyle, size: CGSize, completionWhenImageCached: @escaping ((Bool) -> Void)) {
        let hardlinkAndSize = HardlinkAndSize(hardlink: hardlink, size: size)
        assert(imageCache[hardlinkAndSize] == nil)
        guard let url = hardlink.hardlinkURL else { assertionFailure(); return }
        assert(FileManager.default.fileExists(atPath: url.path))
        let scale = UIScreen.main.scale
        let request = QLThumbnailGenerator.Request(fileAt: url,
                                                   size: size,
                                                   scale: scale,
                                                   representationTypes: .thumbnail)
        let generator = QLThumbnailGenerator.shared
        if var completions = imageCacheCompletions[hardlinkAndSize] {
            completions.append(completionWhenImageCached)
            imageCacheCompletions[hardlinkAndSize] = completions
        } else {
            imageCacheCompletions[hardlinkAndSize] = [completionWhenImageCached]
            generator.generateRepresentations(for: request) { thumbnail, type, error in
                if thumbnail == nil || error != nil {
                    // This happens, e.g., when an attachment was cancelled by the server
                    DispatchQueue.main.async { [weak self] in
                        guard let _self = self else { return }
                        guard let completions = _self.imageCacheCompletions.removeValue(forKey: hardlinkAndSize) else { assertionFailure(); return }
                        for completion in completions {
                            completion(false)
                        }
                    }
                } else {
                    DispatchQueue.main.async { [weak self] in
                        guard let _self = self else { return }
                        _self.imageCache[hardlinkAndSize] = thumbnail!.uiImage
                        guard let completions = _self.imageCacheCompletions.removeValue(forKey: hardlinkAndSize) else { assertionFailure(); return }
                        for completion in completions {
                            completion(true)
                        }
                    }
                }
            }
        }
    }

    
    // MARK: - Reply-to

    
    func getCachedReplyToBubbleViewConfiguration(message: PersistedMessage) -> ReplyToBubbleView.Configuration? {
        assert(Thread.isMainThread)
        return replyToCache[message.typedObjectID]
    }
        
    
    func requestReplyToBubbleViewConfiguration(message: PersistedMessage, completion completionConfigCached: @escaping (Result<Void, Error>) -> Void) {
        assert(Thread.isMainThread)
        guard let messageContext = message.managedObjectContext, messageContext == ObvStack.shared.viewContext, message.hasReplyTo else {
            assertionFailure()
            completionConfigCached(.failure(makeError(message: "Inappropriate reply to request")))
            return
        }
        let messageObjectID = message.typedObjectID
        
        // Store the completion
        
        if var completions = replyToCacheCompletions[messageObjectID] {
            completions.append(completionConfigCached)
            replyToCacheCompletions[messageObjectID] = completions
            return
        } else {
            replyToCacheCompletions[messageObjectID] = [completionConfigCached]
        }

        let backgroundContext = self.backgroundContext
        backgroundContext.perform { [weak self] in
            
            guard let _self = self else {
                assertionFailure()
                completionConfigCached(.failure(DiscussionCacheManager.makeError(message: "Internal error")))
                return
            }
            
            let replyTo: PersistedMessage
            do {
                let message = try PersistedMessage.get(with: messageObjectID, within: backgroundContext)
                guard message != nil else { throw _self.makeError(message: "Could not find message" )}
                guard let _replyTo = try? message!.getReplyTo() else {
                    let config = ReplyToBubbleView.Configuration.messageWasDeleted
                    _self.requestReplyToBubbleViewConfigurationSucceeded(messageObjectID: messageObjectID, configToCache: config)
                    return
                }
                replyTo = _replyTo
            } catch {
                _self.requestReplyToBubbleViewConfigurationFailed(messageObjectID: messageObjectID, errorMessage: error.localizedDescription)
                return
            }
            
            let replyToObjectID = replyTo.typedObjectID
            
            // We got the reply-to message and we have enough informations to compute a first version of the configuration (without hardlink nor thumbnail). We do so now.

            var config: ReplyToBubbleView.Configuration
            do {
                
                let name: String
                let nameColor: UIColor
                let lineColor: UIColor
                let bodyColor: UIColor
                let bubbleColor: UIColor
                let appTheme = AppTheme.shared

                if let received = replyTo as? PersistedMessageReceived {
                    
                    if let contact = received.contactIdentity {
                        name = NewSingleDiscussionViewController.Strings.replyingTo(contact.customOrFullDisplayName)
                        nameColor = contact.cryptoId.colors.text
                        lineColor = contact.cryptoId.colors.text
                    } else {
                        name = NewSingleDiscussionViewController.Strings.replyingToContact
                        nameColor = .white
                        lineColor = .systemFill
                    }
                    
                    bodyColor = UIColor.secondaryLabel
                    bubbleColor = appTheme.colorScheme.newReceivedCellReplyToBackground

                } else if replyTo is PersistedMessageSent {
                    
                    name = NSLocalizedString("REPLYING_TO_YOU", comment: "")
                    nameColor = .white
                    lineColor = appTheme.colorScheme.adaptiveOlvidBlueReversed
                    bodyColor = UIColor.secondaryLabel.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
                    bubbleColor = appTheme.colorScheme.adaptiveOlvidBlue

                } else {
                    DispatchQueue.main.async {
                        completionConfigCached(.failure(_self.makeError(message: "Unexpected message type")))
                    }
                    return
                }
                
                config = ReplyToBubbleView.Configuration.loaded(
                    messageObjectID: replyToObjectID,
                    body: replyTo.textBody,
                    bodyColor: bodyColor,
                    name: name,
                    nameColor: nameColor,
                    lineColor: lineColor,
                    bubbleColor: bubbleColor,
                    hardlink: nil,
                    thumbnail: nil)

            }
            
            // If we reach this point, we have a first candidate for the configuration.
            // We still need to check whether we can "augment" this configuration with a hardlink and a thumbnail. If we can't, we cache this config and return.
            
            if let receivedMessage = replyTo as? PersistedMessageReceived, receivedMessage.readingRequiresUserAction {
                // In case the message still requires user action to be read, we do not compute a hardlink nor an image for this reply-to
                self?.requestReplyToBubbleViewConfigurationSucceeded(messageObjectID: messageObjectID, configToCache: config)
                return
            }
            
            _self.getAppropriateHardlinkForJoinsOfReplyTo(replyTo) { hardlink in
                
                guard let hardlink = hardlink else {
                    // We could not find a hardlink, we return the current config
                    _self.requestReplyToBubbleViewConfigurationSucceeded(messageObjectID: messageObjectID, configToCache: config)
                    return
                }
                
                // If we reach this point, we can augment the configuration using the hardlink found. We can then look for a thumbnail.
                config = config.replaceHardLink(with: hardlink)
                
                let size = CGSize(width: MessageCellConstants.replyToImageSize, height: MessageCellConstants.replyToImageSize)
                _self.getAppropriateThumbnailForHardlink(hardlink: hardlink, size: size) { image in
                    
                    guard let image = image else {
                        // We could not get an image corresponding to the hardlink. We return the current config.
                        _self.requestReplyToBubbleViewConfigurationSucceeded(messageObjectID: messageObjectID, configToCache: config)
                        return
                    }
                    
                    // If we reach this point, we can augment the configuration using the image found. We then return.
                    config = config.replaceThumbnail(with: image)
                    _self.requestReplyToBubbleViewConfigurationSucceeded(messageObjectID: messageObjectID, configToCache: config)
                    return

                }
                
            }
            
        }
    }

    
    private func requestReplyToBubbleViewConfigurationFailed(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, errorMessage: String) {
        assert(!Thread.isMainThread)
        DispatchQueue.main.async { [weak self] in
            guard let _self = self else { return }
            guard let completions = _self.replyToCacheCompletions.removeValue(forKey: messageObjectID) else { assertionFailure(); return }
            for completion in completions {
                completion(.failure(_self.makeError(message: errorMessage)))
            }
        }
    }
    
    
    private func requestReplyToBubbleViewConfigurationSucceeded(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, configToCache: ReplyToBubbleView.Configuration) {
        DispatchQueue.main.async { [weak self] in
            guard let _self = self else { return }
            _self.replyToCache[messageObjectID] = configToCache
            guard let completions = _self.replyToCacheCompletions.removeValue(forKey: messageObjectID) else { assertionFailure(); return }
            for completion in completions {
                completion(.success(()))
            }
        }
    }
    
    
    /// This method is used while computing the configuration of a reply to. When a reply to is found, we first look for an appropriate hardlink to augment its configuration (using this
    /// method). If one is found, we compute a thumbnail (using another method).
    private func getAppropriateHardlinkForJoinsOfReplyTo(_ replyTo: PersistedMessage, completion: @escaping (HardLinkToFyle?) -> Void) {
        assert(!Thread.isMainThread)
        
        let replyToObjectID = replyTo.typedObjectID
        
        guard let fyleMessageJoinWithStatus = replyTo.fyleMessageJoinWithStatus, !fyleMessageJoinWithStatus.isEmpty else {
            completion(nil)
            return
        }
        
        let joinObjectIDs = fyleMessageJoinWithStatus.map({ $0.typedObjectID })
        assert(!joinObjectIDs.isEmpty)

        DispatchQueue.main.async { [weak self] in
            guard let _self = self else {
                completion(nil)
                return
            }
            for joinObjectID in joinObjectIDs {
                if let hardlink = _self.getCachedHardlinkForFyleMessageJoinWithStatus(with: joinObjectID), hardlink.hardlinkURL != nil {
                    completion(hardlink)
                    return
                }
            }
            // If we reach this point, we could not find an appropriate cached hardlink. We request the first one.
            _self.requestAllHardlinksForMessage(with: replyToObjectID) { hardlinkFound in
                if hardlinkFound {
                    _self.internalQueue.async {
                        replyTo.managedObjectContext?.performAndWait {
                            _self.getAppropriateHardlinkForJoinsOfReplyTo(replyTo, completion: completion)
                        }
                    }
                } else {
                    completion(nil)
                }
            }
        }
    }


    /// This method is used while computing the configuration of a reply to. When a reply to is found, we first look for an appropriate hardlink to augment its configuration (using
    /// getAppropriateHardlinkForJoinsOfReplyTo(...), then look for an image using this method.
    private func getAppropriateThumbnailForHardlink(hardlink: HardLinkToFyle, size: CGSize, completion: @escaping (UIImage?) -> Void) {
        assert(Thread.isMainThread)
        if let image = getCachedImageForHardlink(hardlink: hardlink, size: size) {
            completion(image)
            return
        }
        // If we reach this point, we must request an image
        requestImageForHardlink(hardlink: hardlink, size: size) { [weak self] success in
            if success {
                self?.getAppropriateThumbnailForHardlink(hardlink: hardlink, size: size, completion: completion)
            } else {
                completion(nil)
            }
        }
    }

    
    // MARK: - Downsized thumbnails
    
    func getCachedDownsizedThumbnail(objectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) -> UIImage? {
        return downsizedThumbnailCache[objectID]
    }
    
    
    func removeCachedDownsizedThumbnail(objectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) {
        _ = downsizedThumbnailCache.removeValue(forKey: objectID)
    }
    
    
    func requestDownsizedThumbnail(objectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>, data: Data, completionWhenImageCached: @escaping ((Result<Void, Error>) -> Void)) {

        assert(Thread.isMainThread)
        
        // Store the completion
        
        if var completions = downsizedThumbnailCacheCompletions[objectID] {
            completions.append(completionWhenImageCached)
            downsizedThumbnailCacheCompletions[objectID] = completions
            return
        } else {
            downsizedThumbnailCacheCompletions[objectID] = [completionWhenImageCached]
        }

        // Request the downsized image
        
        internalQueue.async { [weak self] in
            guard let image = UIImage(data: data) else {
                self?.requestDownsizedThumbnailFailed(objectID: objectID, errorMessage: "Could not turn data into an UIImage")
                return
            }
            self?.requestDownsizedThumbnailFailedSucceeded(objectID: objectID, imageToCache: image)
        }
    }

    private func requestDownsizedThumbnailFailed(objectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>, errorMessage: String) {
        assert(!Thread.isMainThread)
        DispatchQueue.main.async { [weak self] in
            guard let _self = self else { return }
            guard let completions = _self.downsizedThumbnailCacheCompletions.removeValue(forKey: objectID) else { assertionFailure(); return }
            for completion in completions {
                completion(.failure(_self.makeError(message: errorMessage)))
            }
        }
    }

    
    private func requestDownsizedThumbnailFailedSucceeded(objectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>, imageToCache: UIImage) {
        assert(!Thread.isMainThread)
        DispatchQueue.main.async { [weak self] in
            guard let _self = self else { return }
            _self.downsizedThumbnailCache[objectID] = imageToCache
            guard let completions = _self.downsizedThumbnailCacheCompletions.removeValue(forKey: objectID) else { assertionFailure(); return }
            for completion in completions {
                completion(.success(()))
            }
        }
    }

    
}


// MARK: - Helpers

private extension String {
    
    func containsDetectableData() -> UIDataDetectorTypes {
        assert(!Thread.isMainThread)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.allTypes.rawValue) else { assertionFailure(); return [] }
        let range = NSRange(location: 0, length: self.utf16.count)
        let matches = detector.matches(in: self, options: [], range: range)
        let detectedTypes = matches.map({ $0.resultType })
        var uiDataDetectorTypes: UIDataDetectorTypes = []
        for detectedType in detectedTypes {
            let uiDetectorType = detectedType.equivalentUIDataDetectorType
            if uiDetectorType == .all {
                return .all
            } else if !uiDataDetectorTypes.contains(uiDetectorType) {
                uiDataDetectorTypes.insert(uiDetectorType)
            }
        }
        return uiDataDetectorTypes
    }
    
    func getHttpsURLs() -> [URL] {
        guard self.lowercased().contains("https") else { return [] }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { assertionFailure(); return [] }
        let range = NSRange(location: 0, length: self.utf16.count)
        let matches = detector.matches(in: self, options: [], range: range)
        guard !matches.isEmpty else { return [] }
        let httpsURLs: [URL] = matches.compactMap { (match) -> URL? in
            guard let rangeOfMatch = Range(match.range, in: self) else { return nil }
            let url = URL(string: String(self[rangeOfMatch]))
            return url?.scheme?.lowercased() == "https" ? url : nil
        }
        return httpsURLs
    }
    
}


fileprivate extension NSTextCheckingResult.CheckingType {
        
    // Best effort to map self to UIDataDetectorTypes
    var equivalentUIDataDetectorType: UIDataDetectorTypes {
        switch self {
        case .phoneNumber:
            return .phoneNumber
        case .link:
            return .link
        case .address:
            return .address
        default:
            return .all
        }
    }
    
}
