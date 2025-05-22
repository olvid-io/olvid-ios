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
    let photoURL: URL?
    
    public init(characterOrIcon: CharacterOrIcon, colors: Colors, photoURL: URL?) {
        self.characterOrIcon = characterOrIcon
        self.colors = colors
        self.photoURL = photoURL
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
    func imageSizeForAvatarSize(avatarSize: ObvAvatarSize) -> ObvAvatarSize {
        switch self {
        case .map:
            return .custom(frameSize: .init(width: avatarSize.frameSize.width - ObvAvatarMapStyleView.padding, height: avatarSize.frameSize.height - ObvAvatarMapStyleView.padding))
        }
    }
}



// MARK: - Data Source

@MainActor
public protocol ObvAvatarViewDataSource: AnyObject {
    func fetchAvatar(photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage?
}



// MARK: - ObvAvatarView (Main view)

/// As of 2025-05-13, this is the preferred view to display an avatar. For now, the only style available is intented to be used on maps.
public struct ObvAvatarView: View {

    let model: ObvAvatarViewModel
    let style: ObvAvatarStyle
    let size: ObvAvatarSize
    let dataSource: ObvAvatarViewDataSource
    
    public init(model: ObvAvatarViewModel, style: ObvAvatarStyle, size: ObvAvatarSize, dataSource: ObvAvatarViewDataSource) {
        self.model = model
        self.style = style
        self.size = size
        self.dataSource = dataSource
    }
    
    @State private var photo: (url: URL, image: UIImage?)?
    
    private func onTask() async {
        await updatePhotoIfRequired(photoURL: model.photoURL)
    }
    
    private func updatePhotoIfRequired(photoURL: URL?) async {
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
            let image = try await dataSource.fetchAvatar(photoURL: photoURL, avatarSize: imageSize)
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
            ObvAvatarMapStyleView(model: model, size: size, photo: $photo)
                .task { await onTask() }
                .onChange(of: model.photoURL) { newValue in
                    Task { await updatePhotoIfRequired(photoURL: newValue) }
                }
        }
    }
    
}



private struct ObvAvatarMapStyleView: View {

    let model: ObvAvatarViewModel
    let size: ObvAvatarSize
    @Binding var photo: (url: URL, image: UIImage?)?

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




#if DEBUG

private extension UIImage {
    
    @MainActor
    static var sampleDatas: [UIImage] = [
        UIImage(named: "ObvDesignSystemAvatar00", in: ObvDesignSystemResources.bundle, compatibleWith: nil)!,
        UIImage(named: "ObvDesignSystemAvatar01", in: ObvDesignSystemResources.bundle, compatibleWith: nil)!,
        UIImage(named: "ObvDesignSystemAvatar02", in: ObvDesignSystemResources.bundle, compatibleWith: nil)!,
        UIImage(named: "ObvDesignSystemAvatar03", in: ObvDesignSystemResources.bundle, compatibleWith: nil)!,
        UIImage(named: "ObvDesignSystemAvatar04", in: ObvDesignSystemResources.bundle, compatibleWith: nil)!,
        UIImage(named: "ObvDesignSystemAvatar05", in: ObvDesignSystemResources.bundle, compatibleWith: nil)!,
        UIImage(named: "ObvDesignSystemAvatar06", in: ObvDesignSystemResources.bundle, compatibleWith: nil)!,
    ]
    
    @MainActor
    static func sampleData(url: URL) -> UIImage? {
        switch url {
        case URL.sampleDatas[0]:
            return UIImage.sampleDatas[0]
        case URL.sampleDatas[1]:
            return UIImage.sampleDatas[0]
        case URL.sampleDatas[2]:
            return UIImage.sampleDatas[0]
        case URL.sampleDatas[3]:
            return UIImage.sampleDatas[0]
        case URL.sampleDatas[4]:
            return UIImage.sampleDatas[0]
        case URL.sampleDatas[5]:
            return UIImage.sampleDatas[0]
        default:
            return nil
        }
    }

}


private extension ObvAvatarViewModel.Colors {
    
    @MainActor
    static var sampleDatas: [Self] = [
        .init(foreground: .systemBlue,
              background: .systemRed),
        .init(foreground: .systemPink,
              background: .systemCyan),
    ]
    
}


private extension URL {
    
    @MainActor
    static var sampleDatas: [Self] = [
        URL(string: "https://olvid.io/avatar00.png")!,
        URL(string: "https://olvid.io/avatar01.png")!,
        URL(string: "https://olvid.io/avatar02.png")!,
        URL(string: "https://olvid.io/avatar03.png")!,
        URL(string: "https://olvid.io/avatar04.png")!,
        URL(string: "https://olvid.io/avatar05.png")!,
    ]
    
}


private extension ObvAvatarViewModel {
    
    @MainActor
    static var sampleDatas: [Self] = [
        .init(characterOrIcon: .character("A"),
              colors: Colors.sampleDatas[0],
              photoURL: URL.sampleDatas[0]),
        .init(characterOrIcon: .icon(.person),
              colors: Colors.sampleDatas[0],
              photoURL: URL.sampleDatas[0]),
    ]
    
}


private final class DataSourceForPreviews: ObvAvatarViewDataSource {
    
    private var count: Double = 0
    
    func fetchAvatar(photoURL: URL, avatarSize: ObvAvatarSize) async throws -> UIImage? {
        count += 0.3
        try await Task.sleep(seconds: count)
        return UIImage.sampleData(url: photoURL)
    }
    
}

@MainActor
private let dataSourceForPreviews = DataSourceForPreviews()

@available(iOS 16.0, *)
#Preview {
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

#endif
