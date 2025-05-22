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



@MainActor
public protocol ObvAvatarLegacyViewModel: AnyObject, ObservableObject {
    var displayedLetter: Character { get }
    var displayedImage: UIImage? { get }
    var colors: (foreground: UIColor, background: UIColor) { get }
    var size: ObvAvatarSize { get }
    var showGreenShield: Bool { get }
    func setDisplayedImage(to image: UIImage)
}

public protocol ObvAvatarLegacyViewActions {
    @MainActor func fetchAvatarImageOfSize(_ size: ObvAvatarSize) async -> UIImage?
}

/// If possible, use `ObvAvatarView` instead.
public struct ObvAvatarLegacyView<Model: ObvAvatarLegacyViewModel>: View {
    
    @ObservedObject var model: Model
    let actions: ObvAvatarLegacyViewActions
    
    public init(model: Model, actions: ObvAvatarLegacyViewActions) {
        self.model = model
        self.actions = actions
    }
    
    private var fontSize: CGFloat {
        switch model.size {
        case .normal:
            return 20.0
        case .large:
            return 40.0
        case .xLarge:
            return 60.0
        case .custom(frameSize: let frameSize):
            return min(frameSize.width, frameSize.height)
        }
    }
    
    private var roundedCornersSize: CGSize {
        switch model.size {
        case .normal:
            return CGSize(width: 12, height: 12)
        case .large:
            return CGSize(width: 24, height: 24)
        case .xLarge:
            return CGSize(width: 36, height: 36)
        case .custom(frameSize: let frameSize):
            let multiplier: CGFloat = 0.6
            return CGSize(width: multiplier * frameSize.width, height: multiplier * frameSize.height)
        }
    }
    
    private var greenShieldFontSize: CGFloat {
        switch model.size {
        case .normal:
            return 16
        case .large:
            return 32
        case .xLarge:
            return 48
        case .custom(frameSize: let frameSize):
            return 0.8 * min(frameSize.width, frameSize.height)
        }
    }
    
    private var greenShieldOffset: CGSize {
        switch model.size {
        case .normal:
            return .init(width: 6, height: -6)
        case .large:
            return .init(width: 12, height: -12)
        case .xLarge:
            return .init(width: 18, height: -18)
        case .custom(frameSize: let frameSize):
            return .init(width: 0.3 * frameSize.width, height: -0.3 * frameSize.height)
        }
    }
    
    public var body: some View {
        ZStack {
            
            Text(verbatim: "\(model.displayedLetter)")
                .font(.system(size: fontSize, weight: .medium, design: .rounded))
                .foregroundStyle(Color(model.colors.foreground))
                .opacity(model.displayedImage == nil ? 1.0 : 0.0)
            
            if let uiImage = model.displayedImage {
                Image(uiImage: uiImage)
                    .resizable()
            }
            
        }
        .frame(width: model.size.frameSize.width, height: model.size.frameSize.height)
        .background(Color(model.colors.background))
        .clipShape(RoundedRectangle(cornerSize: roundedCornersSize))
        .overlay {
            RoundedRectangle(cornerSize: roundedCornersSize)
                .stroke()
                .foregroundStyle(Color.primary.opacity(0.1))
        }
        .overlay(alignment: .topTrailing, content: {
            if model.showGreenShield {
                Image(systemIcon: .checkmarkShieldFill)
                    .renderingMode(.original)
                    .font(.system(size: greenShieldFontSize))
                    .foregroundStyle(Color(UIColor.systemGreen))
                    .offset(greenShieldOffset)
            }
        })
        .task {
            guard let image = await actions.fetchAvatarImageOfSize(model.size) else { return }
            model.setDisplayedImage(to: image)
        }
    }
}









// MARK: - Previews

@MainActor
private final class ModelForPreviews: ObvAvatarLegacyViewModel, ObservableObject {
        
    let displayedLetter: Character
    let colors: (foreground: UIColor, background: UIColor)
    @Published private(set) var displayedImage: UIImage?
    let size: ObvAvatarSize
    let showGreenShield: Bool
    
    init(displayedLetter: Character, size: ObvAvatarSize, showGreenShield: Bool) {
        self.displayedLetter = displayedLetter
        self.colors = (.white, .blue)
        self.displayedImage = nil
        self.size = size
        self.showGreenShield = showGreenShield
    }
    
    func setDisplayedImage(to image: UIImage) {
        withAnimation {
            self.displayedImage = image
        }
    }

}


private final class ActionsForPreviews: ObvAvatarLegacyViewActions {
    
    func fetchAvatarImageOfSize(_ size: ObvAvatarSize) async -> UIImage? {
        let uiImage = UIImage(named: "avatar01", in: ObvDesignSystemResources.bundle, compatibleWith: nil)
        try! await Task.sleep(seconds: 3)
        return uiImage
    }
    
    
}


#Preview("Normal size") {
    ObvAvatarLegacyView(model: ModelForPreviews(displayedLetter: "A", size: .normal, showGreenShield: false), actions: ActionsForPreviews())
}

#Preview("Large size") {
    ObvAvatarLegacyView(model: ModelForPreviews(displayedLetter: "A", size: .large, showGreenShield: false), actions: ActionsForPreviews())
}

#Preview("xLarge size") {
    ObvAvatarLegacyView(model: ModelForPreviews(displayedLetter: "A", size: .xLarge, showGreenShield: false), actions: ActionsForPreviews())
}

#Preview("Normal size with shield") {
    ObvAvatarLegacyView(model: ModelForPreviews(displayedLetter: "A", size: .normal, showGreenShield: true), actions: ActionsForPreviews())
}

#Preview("Large size with shield") {
    ObvAvatarLegacyView(model: ModelForPreviews(displayedLetter: "A", size: .large, showGreenShield: true), actions: ActionsForPreviews())
}

#Preview("xLarge size with shield") {
    ObvAvatarLegacyView(model: ModelForPreviews(displayedLetter: "A", size: .xLarge, showGreenShield: true), actions: ActionsForPreviews())
}
