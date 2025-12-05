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
import CoreData
import ObvDesignSystem
import ObvTypes
import ObvUICoreData


/// In practice, the getUserDataNow() delegate method can be implemented by forwarding the call to the engine.
/// The `performBackgroundTask` method can be obtained with ObvStack.shared.performBackgroundTask in the app.
public protocol ObvAvatarViewAppDataSourceDelegate: AnyObject, Sendable {
    func getUserDataNow(ownedCryptoId: ObvCryptoId, encodedServerKeyAndLabel: Data?) async throws -> Data?
    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void)
}


@MainActor
public final class ObvAvatarViewAppDataSource {
    
    private weak var delegate: ObvAvatarViewAppDataSourceDelegate?
    private lazy var avatarHelper = AvatarHelper(delegate: delegate)
    private lazy var synchronousAvatarCache = SynchronousAvatarCache()

    public init(delegate: ObvAvatarViewAppDataSourceDelegate) {
        self.delegate = delegate
    }
    
}


extension ObvAvatarViewAppDataSource {
    
    public func fetchAvatarImage(profileCryptoId: ObvTypes.ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        do {
            let image = try await self.avatarHelper.fetchAvatarImage(ownedCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, size: frameSize)
            return image
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                return nil
            } else {
                assertionFailure()
                return nil
            }
        }
    }

    
    func fetchAvatarFromCache(localPhotoURL: URL, avatarSize: ObvAvatarSize) -> UIImage? {
        return synchronousAvatarCache.fetchAvatarImage(localPhotoURL: localPhotoURL, size: avatarSize)
    }
    
    
    public func fetchAvatarImage(localPhotoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        if let image = synchronousAvatarCache.fetchAvatarImage(localPhotoURL: localPhotoURL, size: avatarSize) {
            return image
        }
        guard let image = try await self.avatarHelper.fetchAvatarImage(localPhotoURL: localPhotoURL, size: avatarSize) else { return nil }
        synchronousAvatarCache.setAvatarImageInCache(localPhotoURL: localPhotoURL, size: avatarSize, image: image)
        return image
    }

}


extension ObvAvatarViewAppDataSource: ObvAvatarViewDataSource {
    
    public func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return try await self.fetchAvatarImage(localPhotoURL: photoURL, avatarSize: avatarSize)
    }
    
    public func fetchAvatarFromCache(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return fetchAvatarFromCache(localPhotoURL: photoURL, avatarSize: avatarSize)
    }
    
    public func fetchAvatarForLegacyViews(photoURL: URL, avatarSize: ObvAvatarSize) async throws -> UIImage? {
        return try await self.fetchAvatarImage(localPhotoURL: photoURL, avatarSize: avatarSize)
    }
    
    public func fetchAvatarFromCacheForLegacyViews(photoURL: URL, avatarSize: ObvAvatarSize) -> UIImage? {
        return fetchAvatarFromCache(localPhotoURL: photoURL, avatarSize: avatarSize)
    }
    
}





// MARK: - AvatarHelper

private actor AvatarHelper {
    
    weak var delegate: ObvAvatarViewAppDataSourceDelegate?
    
    init(delegate: ObvAvatarViewAppDataSourceDelegate?) {
        self.delegate = delegate
    }
    
    private var cache = NSCache<NSData, UIImage>()
    
    private var cacheOfLocalImages = NSCache<NSURL, UIImage>()
    
    func fetchAvatarImage(ownedCryptoId: ObvTypes.ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, size: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        
        let frameSizeInPixels = await size.frameSizeInPixels
        
        // Try to fetch the image from the local app database
        if let image = try await fetchAvatarImageOfPersistedObvOwnedIdentity(ownedCryptoId: ownedCryptoId) {
            let thumbnail = image.preparingThumbnail(of: frameSizeInPixels)
            return thumbnail
        }
        
        if let image = cache.object(forKey: ownedCryptoId.getIdentity() as NSData) {
            let thumbnail = image.preparingThumbnail(of: frameSizeInPixels)
            return thumbnail
        }

        // Forward the request to the engine, so as to fetch the image from the server
        if let imageData = try await delegate.getUserDataNow(ownedCryptoId: ownedCryptoId, encodedServerKeyAndLabel: encodedPhotoServerKeyAndLabel), let image = UIImage(data: imageData) {
            self.cache.setObject(image, forKey: ownedCryptoId.getIdentity() as NSData, cost: imageData.count)
            let thumbnail = image.preparingThumbnail(of: frameSizeInPixels)
            return thumbnail
        }
                
        return nil
        
    }
    
    /// Appropriate function to call to fetch an avatar image (for an owned identity, a contact, a group member, a group, ...), when the local URL of the photo is known.
    func fetchAvatarImage(localPhotoURL: URL, size: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        
        let image: UIImage
        
        if let cachedImage = cacheOfLocalImages.object(forKey: localPhotoURL as NSURL) {
            image = cachedImage
        } else {
            let data = try Data(contentsOf: localPhotoURL)
            guard let imageFromDisk = UIImage(data: data) else { return nil }
            cacheOfLocalImages.setObject(imageFromDisk, forKey: localPhotoURL as NSURL, cost: data.count)
            image = imageFromDisk
        }
        
        let frameSizeInPixels = await size.frameSizeInPixels
        let thumbnail = image.preparingThumbnail(of: frameSizeInPixels)
        return thumbnail
        
    }
    

    /// Helper function for `fetchAvatarImage(_:ownedCryptoId:)`. It allows to fetch an return an avatar photo for the owned identity asynchronously.
    private func fetchAvatarImageOfPersistedObvOwnedIdentity(ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> UIImage? {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage?, any Error>) in
            delegate.performBackgroundTask { context in
                do {
                    guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: context) else {
                        return continuation.resume(returning: nil)
                    }
                    guard let photoURL = ownedIdentity.photoURL else {
                        return continuation.resume(returning: nil)
                    }
                    let data = try Data(contentsOf: photoURL)
                    let image = UIImage(data: data)
                    return continuation.resume(returning: image)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }

    enum ObvError: Error {
        case delegateIsNil
    }
    
}


// MARK: - SynchronousAvatarCache

/// This cache allows the calling view controller to obtain a cached image (if it exists) in a synchronous way on the main thread.
@MainActor
private final class SynchronousAvatarCache {

    /// See https://medium.com/anysuggestion/how-to-use-custom-type-as-a-key-for-nscache-9bdbee02a8f1
    /// for a great explanation on why we need to subclass `NSObject` and to override `hash` and `isEqual`.
    private final class Key: NSObject {
        let localPhotoURL: URL
        let size: ObvDesignSystem.ObvAvatarSize
        init(localPhotoURL: URL, size: ObvDesignSystem.ObvAvatarSize) {
            self.localPhotoURL = localPhotoURL
            self.size = size
            super.init()
        }
        override var hash: Int {
            // Note that calling size.hashValue crashes under iOS15, 16, and 17
            return localPhotoURL.hashValue ^ Int(size.frameSize.width) ^ Int(size.frameSize.height)
        }
        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? Key else {
                return false
            }
            return self.localPhotoURL == other.localPhotoURL && self.size == other.size
        }
    }
    
    private var cacheOfLocalImages = NSCache<Key, UIImage>()
    
    func fetchAvatarImage(localPhotoURL: URL, size: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        let key = Key(localPhotoURL: localPhotoURL, size: size)
        return self.cacheOfLocalImages.object(forKey: key)
    }
    
    func setAvatarImageInCache(localPhotoURL: URL, size: ObvDesignSystem.ObvAvatarSize, image: UIImage) {
        let key = Key(localPhotoURL: localPhotoURL, size: size)
        self.cacheOfLocalImages.setObject(image, forKey: key)
    }
    
}
