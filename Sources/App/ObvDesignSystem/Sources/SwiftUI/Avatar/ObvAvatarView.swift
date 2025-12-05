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

import SwiftUI
import CoreData
import ObvSystemIcon
import ObvTypes



// MARK: - View's model and style

public struct ObvAvatarViewModel: Sendable, Hashable, Equatable {
    
    let characterOrIcon: CharacterOrIcon
    let colors: Colors
    public let photoURL: URL?
    let showGreenShield: Bool // Not all `ObvAvatarStyle` use this value
    
    public init(characterOrIcon: CharacterOrIcon, colors: Colors, photoURL: URL?, showGreenShield: Bool = false) {
        self.characterOrIcon = characterOrIcon
        self.colors = colors
        self.photoURL = photoURL
        self.showGreenShield = showGreenShield
    }

    public enum CharacterOrIcon: Sendable, Hashable, Equatable {
        case character(Character)
        case icon(SystemIcon)
    }
    
    public struct Colors: Sendable, Hashable, Equatable {
        let foreground: UIColor
        let background: UIColor
        public init(foreground: UIColor, background: UIColor) {
            self.foreground = foreground
            self.background = background
        }
    }
        
}


public enum ObvAvatarStyle {
    case map
    case circle
    case squircle
    case iconOnly
    case topBar
    func imageSizeForAvatarSize(avatarSize: ObvAvatarSize) -> ObvAvatarSize {
        switch self {
        case .map:
            return .custom(frameSize: .init(width: avatarSize.frameSize.width - ObvAvatarMapStyleView.padding, height: avatarSize.frameSize.height - ObvAvatarMapStyleView.padding))
        case .circle:
            return avatarSize
        case .squircle:
            return avatarSize
        case .iconOnly:
            return avatarSize
        case .topBar:
            return avatarSize
        }
    }
}



// MARK: - Data Source

@MainActor
public protocol ObvAvatarViewDataSource: AnyObject {
    func fetchAvatar(_ view: ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage?
    func fetchAvatarFromCache(_ view: ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage?
    // The following to data source methods make it possible to use a `ObvAvatarViewDataSource` on legacy view that do not use the ObvAvatarView
    // but that still require to fetch an avatar
    func fetchAvatarForLegacyViews(photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage?
    func fetchAvatarFromCacheForLegacyViews(photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage?
}


public extension ObvAvatarViewDataSource {
    
    func fetchAvatarForLegacyViews(photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return nil
    }
    
    func fetchAvatarFromCacheForLegacyViews(photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }
    
}


// MARK: - ObvAvatarView (Main view)

/// As of 2025-05-13, this is the preferred view to display an avatar. For now, the only style available is intented to be used on maps.
public struct ObvAvatarView: View {

    let model: ObvAvatarViewModel
    let style: ObvAvatarStyle
    let size: ObvAvatarSize
    let dataSource: ObvAvatarViewDataSource?
    let showGreenShieldIfAppropriate: Bool // Must be set to true for the model.showGreenShield to be considered.
    
    public init(model: ObvAvatarViewModel, style: ObvAvatarStyle, size: ObvAvatarSize, dataSource: ObvAvatarViewDataSource?, showGreenShieldIfAppropriate: Bool = false) {
        self.model = model
        self.style = style
        self.size = size
        self.dataSource = dataSource
        self.showGreenShieldIfAppropriate = showGreenShieldIfAppropriate
    }
    
    @State private var photo: (url: URL, image: UIImage?)?
    
    
    var photoFromCache: (url: URL, image: UIImage)? {
        guard let photoURL = model.photoURL else { return nil }
        guard let image = dataSource?.fetchAvatarFromCache(self, photoURL: photoURL, avatarSize: size) else { return nil }
        return (photoURL, image)
    }
    
    
    private func onTask() async {
        await updatePhotoIfRequired(photoURL: model.photoURL)
    }
    
    private func updatePhotoIfRequired(photoURL: URL?) async {
        guard let dataSource else { return }
        guard self.photo?.url != photoURL else { return }
        guard let photoURL else {
            withAnimation {
                self.photo = nil
            }
            return
        }
        self.photo = (photoURL, nil)
        do {
            let imageSize = style.imageSizeForAvatarSize(avatarSize: size)
            let image = try await dataSource.fetchAvatar(self, photoURL: photoURL, avatarSize: imageSize)
            guard self.photo?.url == photoURL else { return } // The fetched photo is outdated
            withAnimation {
                self.photo = (photoURL, image)
            }
        } catch {
            // This can happen when dismissing the view controller showing the avatar
            //assertionFailure(error.localizedDescription)
        }
    }
    
    public var body: some View {
        switch style {
        case .map:
            ObvAvatarMapStyleView(model: model, size: size, photo: photoFromCache ?? photo)
                .task { await onTask() }
                .onChange(of: model.photoURL) { newValue in
                    Task { await updatePhotoIfRequired(photoURL: newValue) }
                }
        case .circle:
            ObvAvatarCircleStyleView(model: model, size: size, photo: photoFromCache ?? photo, showGreenShieldIfAppropriate: showGreenShieldIfAppropriate)
                .task { await onTask() }
                .onChange(of: model.photoURL) { newValue in
                    Task { await updatePhotoIfRequired(photoURL: newValue) }
                }
        case .squircle:
            ObvAvatarSquircleStyleView(model: model, size: size, photo: photoFromCache ?? photo)
                .task { await onTask() }
                .onChange(of: model.photoURL) { newValue in
                    Task { await updatePhotoIfRequired(photoURL: newValue) }
                }
        case .iconOnly:
            ObvAvatarIconOnlyStyleView(model: model, size: size)
        case .topBar:
            ObvAvatarForTopBar(model: model, size: size, photo: photoFromCache ?? photo)
                .task { await onTask() }
                .onChange(of: model.photoURL) { newValue in
                    Task { await updatePhotoIfRequired(photoURL: newValue) }
                }
        }
    }
    
}


private struct ObvAvatarForTopBar: View {
    
    let model: ObvAvatarViewModel
    let size: ObvAvatarSize
    let photo: (url: URL, image: UIImage?)?

    private var characterSize: CGFloat {
        0.5 * size.frameSize.height
    }
    
    private var iconSize: CGFloat {
        0.3 * size.frameSize.height
    }
    
    var body: some View {
        ZStack(alignment: .center) {
            Circle()
                .foregroundColor(Color(model.colors.background))
            switch model.characterOrIcon {
            case .character(let character):
                Text(verbatim: "\(character)")
                    .font(.system(size: characterSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(model.colors.foreground))
            case .icon(let systemIcon):
                Image(systemIcon: systemIcon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(Color(model.colors.foreground))
            }
            if let photo, let uiImage = photo.image {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            }
        }
        .clipShape(Circle())
        .frame(width: size.frameSize.width, height: size.frameSize.height)
    }

}


private struct ObvAvatarIconOnlyStyleView: View {
    
    let model: ObvAvatarViewModel
    let size: ObvAvatarSize

    private var characterSize: CGFloat {
        0.7 * size.frameSize.height
    }
    
    private var iconSize: CGFloat {
        0.3 * size.frameSize.height
    }
    
    var body: some View {
        ZStack(alignment: .center) {
            switch model.characterOrIcon {
            case .character(let character):
                Text(verbatim: "\(character)")
                    .font(.system(size: characterSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(model.colors.foreground))
            case .icon(let systemIcon):
                Image(systemIcon: systemIcon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(Color(model.colors.foreground))
            }
        }
        .frame(width: size.frameSize.width)
    }
    
}


private struct ObvAvatarCircleStyleView: View {
    
    let model: ObvAvatarViewModel
    let size: ObvAvatarSize
    let photo: (url: URL, image: UIImage?)?
    let showGreenShieldIfAppropriate: Bool

    private var characterSize: CGFloat {
        0.6 * size.frameSize.height
    }
    
    private var iconSize: CGFloat {
        0.3 * size.frameSize.height
    }
    
    private var greenShieldWidth: CGFloat {
        size.frameSize.width / 2.9
    }
    
    private var greeShieldOffset: CGSize {
        let value: CGFloat = size.frameSize.width / 16
        return .init(width: value, height: -value)
    }

    var body: some View {
        ZStack(alignment: .center) {
            Circle()
                .foregroundColor(Color(model.colors.background))
            switch model.characterOrIcon {
            case .character(let character):
                Text(verbatim: "\(character)")
                    .font(.system(size: characterSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(model.colors.foreground))
            case .icon(let systemIcon):
                Image(systemIcon: systemIcon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(Color(model.colors.foreground))
            }
            if let photo, let uiImage = photo.image {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            }
        }
        .clipShape(Circle())
        .frame(width: size.frameSize.width, height: size.frameSize.height)
        .overlay(alignment: .topTrailing) {
            if model.showGreenShield && showGreenShieldIfAppropriate {
                GreenShieldView(greenShieldWidth: greenShieldWidth)
                    .offset(greeShieldOffset)
            }
        }
    }
    
}

private struct ObvAvatarSquircleStyleView: View {
    
    let model: ObvAvatarViewModel
    let size: ObvAvatarSize
    let photo: (url: URL, image: UIImage?)?

    private var characterSize: CGFloat {
        0.7 * size.frameSize.height
    }
    
    private var iconSize: CGFloat {
        0.3 * size.frameSize.height
    }
    
    var body: some View {
        ZStack(alignment: .center) {
            SquircleShape()
                .foregroundColor(Color(model.colors.background))
            switch model.characterOrIcon {
            case .character(let character):
                Text(verbatim: "\(character)")
                    .font(.system(size: characterSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(model.colors.foreground))
            case .icon(let systemIcon):
                Image(systemIcon: systemIcon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(Color(model.colors.foreground))
            }
            if let photo, let uiImage = photo.image {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            }
        }
        .clipShape(SquircleShape())
        .frame(width: size.frameSize.width, height: size.frameSize.height)
    }
    
}


private struct ObvAvatarMapStyleView: View {

    let model: ObvAvatarViewModel
    let size: ObvAvatarSize
    let photo: (url: URL, image: UIImage?)?

    static let padding: CGFloat = 4.0
    
    private var characterSize: CGFloat {
        0.7 * (size.frameSize.height - 2.0 * Self.padding)
    }
    
    var body: some View {
        ZStack(alignment: .center) {
            Circle()
                .foregroundColor(.white)
            ZStack(alignment: .center) {
                Circle()
                    .foregroundColor(Color(model.colors.background))
                switch model.characterOrIcon {
                case .character(let character):
                    Text(verbatim: "\(character)")
                        .font(.system(size: characterSize, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(model.colors.foreground))
                case .icon(let systemIcon):
                    Image(systemIcon: systemIcon)
                        .font(.system(size: characterSize, weight: .semibold))
                        .foregroundStyle(Color(model.colors.foreground))
                }
                if let photo, let uiImage = photo.image {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                }
            }
            .clipShape(Circle())
            .frame(width: size.frameSize.width - Self.padding, height: size.frameSize.height - Self.padding)
        }
        .frame(width: size.frameSize.width, height: size.frameSize.height)
    }
    
}



private struct GreenShieldView: View {
    
    let greenShieldWidth: CGFloat
    
    var body: some View {
        ZStack {
            Image(systemIcon: .shieldFill)
                .foregroundStyle(.white)
                .font(.system(size: greenShieldWidth-2))
            Image(systemIcon: .checkmarkShieldFill)
                .font(.system(size: greenShieldWidth))
                .foregroundStyle(.green)
        }
    }
}



#if DEBUG

private final class DataSourceForPreviews: ObvAvatarViewDataSource {
    
    private var count: Double = 0
    
    func fetchAvatar(_ view: ObvAvatarView, photoURL: URL, avatarSize: ObvAvatarSize) async throws -> UIImage? {
        count += 0.3
        try await Task.sleep(seconds: count)
        return UIImage.sampleData(url: photoURL)
    }

    func fetchAvatarFromCache(_ view: ObvAvatarView, photoURL: URL, avatarSize: ObvAvatarSize) -> UIImage? {
        //return nil // We don't simulate cache
         return UIImage.sampleData(url: photoURL)
    }
    
    func fetchAvatarForLegacyViews(photoURL: URL, avatarSize: ObvAvatarSize) async throws -> UIImage? {
        count += 0.3
        try await Task.sleep(seconds: count)
        return UIImage.sampleData(url: photoURL)
    }
    
    func fetchAvatarFromCacheForLegacyViews(photoURL: URL, avatarSize: ObvAvatarSize) -> UIImage? {
        //return nil // We don't simulate cache
         return UIImage.sampleData(url: photoURL)
    }
    
}

@MainActor
private let dataSourceForPreviews = DataSourceForPreviews()

@available(iOS 16.0, *)
#Preview("Map") {
    ZStack {
        Color(.black)
            .ignoresSafeArea()
        Grid {
            GridRow {
                ObvAvatarView(model: ObvAvatarViewModel.sampleDatas[0],
                              style: .map,
                              size: .normal,
                              dataSource: dataSourceForPreviews)
                ObvAvatarView(model: ObvAvatarViewModel.sampleDatas[0],
                              style: .map,
                              size: .large,
                              dataSource: dataSourceForPreviews)
                ObvAvatarView(model: ObvAvatarViewModel.sampleDatas[0],
                              style: .map,
                              size: .xLarge,
                              dataSource: dataSourceForPreviews)
            }
            GridRow {
                ObvAvatarView(model: ObvAvatarViewModel.sampleDatas[1],
                              style: .map,
                              size: .normal,
                              dataSource: dataSourceForPreviews)
                ObvAvatarView(model: ObvAvatarViewModel.sampleDatas[1],
                              style: .map,
                              size: .large,
                              dataSource: dataSourceForPreviews)
                ObvAvatarView(model: ObvAvatarViewModel.sampleDatas[1],
                              style: .map,
                              size: .xLarge,
                              dataSource: dataSourceForPreviews)
            }
        }
    }
}


@available(iOS 16.0, *)
#Preview("Circle") {
    ZStack {
        Color(.black)
            .ignoresSafeArea()
        Grid {
            GridRow {
                ObvAvatarView(model: ObvAvatarViewModel.sampleDatas[0],
                              style: .circle,
                              size: .small,
                              dataSource: dataSourceForPreviews)
                ObvAvatarView(model: ObvAvatarViewModel.sampleDatas[0],
                              style: .circle,
                              size: .normal,
                              dataSource: dataSourceForPreviews)
                ObvAvatarView(model: ObvAvatarViewModel.sampleDatas[0],
                              style: .circle,
                              size: .large,
                              dataSource: dataSourceForPreviews)
                ObvAvatarView(model: ObvAvatarViewModel.sampleDatas[0],
                              style: .circle,
                              size: .xLarge,
                              dataSource: dataSourceForPreviews)
            }
            GridRow {
                ObvAvatarView(model: ObvAvatarViewModel.sampleDatas[1],
                              style: .circle,
                              size: .small,
                              dataSource: dataSourceForPreviews)
                ObvAvatarView(model: ObvAvatarViewModel.sampleDatas[1],
                              style: .circle,
                              size: .normal,
                              dataSource: dataSourceForPreviews)
                ObvAvatarView(model: ObvAvatarViewModel.sampleDatas[1],
                              style: .circle,
                              size: .large,
                              dataSource: dataSourceForPreviews)
                ObvAvatarView(model: ObvAvatarViewModel.sampleDatas[1],
                              style: .circle,
                              size: .xLarge,
                              dataSource: dataSourceForPreviews)
            }
        }
    }
}

@available(iOS 16.0, *)
#Preview("Squircle") {
    ZStack {
        Color(.black)
            .ignoresSafeArea()
        Grid {
            GridRow {
                ObvAvatarView(model: ObvAvatarViewModel.sampleDatas[0],
                              style: .squircle,
                              size: .normal,
                              dataSource: dataSourceForPreviews)
                ObvAvatarView(model: ObvAvatarViewModel.sampleDatas[0],
                              style: .squircle,
                              size: .large,
                              dataSource: dataSourceForPreviews)
                ObvAvatarView(model: ObvAvatarViewModel.sampleDatas[0],
                              style: .squircle,
                              size: .xLarge,
                              dataSource: dataSourceForPreviews)
            }
            GridRow {
                ObvAvatarView(model: ObvAvatarViewModel.sampleDatas[1],
                              style: .squircle,
                              size: .normal,
                              dataSource: dataSourceForPreviews)
                ObvAvatarView(model: ObvAvatarViewModel.sampleDatas[1],
                              style: .squircle,
                              size: .large,
                              dataSource: dataSourceForPreviews)
                ObvAvatarView(model: ObvAvatarViewModel.sampleDatas[1],
                              style: .squircle,
                              size: .xLarge,
                              dataSource: dataSourceForPreviews)
            }
        }
    }
}

@available(iOS 16.0, *)
#Preview("Icon") {
    ZStack {
        Color(.black)
            .ignoresSafeArea()
        Grid {
            GridRow {
                ObvAvatarView(model: ObvAvatarViewModel.sampleDatas[1],
                              style: .iconOnly,
                              size: .normal,
                              dataSource: dataSourceForPreviews)
                .background(Rectangle().foregroundStyle(.red))
                ObvAvatarView(model: ObvAvatarViewModel.sampleDatas[1],
                              style: .iconOnly,
                              size: .large,
                              dataSource: dataSourceForPreviews)
                .background(Rectangle().foregroundStyle(.red))
                ObvAvatarView(model: ObvAvatarViewModel.sampleDatas[1],
                              style: .iconOnly,
                              size: .xLarge,
                              dataSource: dataSourceForPreviews)
                .background(Rectangle().foregroundStyle(.red))
            }
        }
    }
}


#endif
