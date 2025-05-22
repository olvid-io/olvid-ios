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
import ObvSystemIcon

public enum CircleAndTitlesDisplayMode {
    case normal
    case small
    case header
}

public enum CircleAndTitlesEditionMode {
    case none
    case picture(update: (UIImage?) -> Void)
    case custom(icon: SystemIcon, action: () -> Void)
}

// Note from TB on 2022-08-04: we probably should be using CircledInitialsConfiguration here
public struct CircleAndTitlesView: View {

    public struct Model {
        
        public struct Content {
            let textViewModel: TextView.Model
            let profilePictureViewModelContent: ProfilePictureView.Model.Content
            
            public init(textViewModel: TextView.Model, profilePictureViewModelContent: ProfilePictureView.Model.Content) {
                self.textViewModel = textViewModel
                self.profilePictureViewModelContent = profilePictureViewModelContent
            }
            
            var displayNameForHeader: String {
                [textViewModel.titlePart1 ?? "", textViewModel.titlePart2 ?? ""]
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

        }
        
        let content: Content
        let colors: InitialCircleView.Model.Colors
        let alignment: VerticalAlignment
        let displayMode: CircleAndTitlesDisplayMode
        let editionMode: CircleAndTitlesEditionMode

        public init(content: Content, colors: InitialCircleView.Model.Colors, alignment: VerticalAlignment = .center, displayMode: CircleAndTitlesDisplayMode, editionMode: CircleAndTitlesEditionMode) {
            self.content = content
            self.colors = colors
            self.alignment = alignment
            self.displayMode = displayMode
            self.editionMode = editionMode
        }
        
        var circleDiameter: CGFloat {
            switch displayMode {
            case .small:
                return 40.0
            case .normal:
                return 60.0
            case .header:
                return 120.0
            }
        }
        
        static let circledCameraButtonViewSize: CGFloat = 20.0

        var profilePictureViewModel: ProfilePictureView.Model {
            .init(content: content.profilePictureViewModelContent,
                  colors: colors,
                  circleDiameter: circleDiameter)
        }
        
    }
    
    let model: Model

    @State private var profilePictureFullScreenIsPresented = false

    public init(model: Model) {
        self.model = model
    }
    
    private func profilePictureBinding(update: @escaping (UIImage?) -> Void) -> Binding<UIImage?> {
        .init {
            model.content.profilePictureViewModelContent.profilePicture
        } set: { image in
            update(image)
        }
    }

    
    private var pictureView: some View {
        ZStack {
            if case .header = model.displayMode {
                ProfilePictureView(model: model.profilePictureViewModel)
                    .onTapGesture {
                        guard model.content.profilePictureViewModelContent.profilePicture != nil else {
                            profilePictureFullScreenIsPresented = false
                            return
                        }
                        profilePictureFullScreenIsPresented.toggle()
                    }
                    .fullScreenCover(isPresented: $profilePictureFullScreenIsPresented) {
                        FullScreenProfilePictureView(photo: model.content.profilePictureViewModelContent.profilePicture)
                            .background(BackgroundBlurView()
                                .edgesIgnoringSafeArea(.all))
                    }
            } else {
                ProfilePictureView(model: model.profilePictureViewModel)
            }
            switch model.editionMode {
            case .none:
                EmptyView()
            case .picture(let update):
                CircledCameraButtonView(profilePicture: profilePictureBinding(update: update))
                    .offset(CGSize(width: Model.circledCameraButtonViewSize, height: Model.circledCameraButtonViewSize))
            case .custom(let icon, let action):
                Button(action: action) {
                    CircledSymbolView(systemIcon: icon)
                }
                .offset(CGSize(width: model.circleDiameter/3, height: model.circleDiameter/3))
            }
        }
    }

    
    public var body: some View {
        switch model.displayMode {
        case .normal, .small:
            HStack(alignment: model.alignment, spacing: 16) {
                pictureView
                TextView(model: model.content.textViewModel)
            }
        case .header:
            VStack(spacing: 8) {
                pictureView
                Text(model.content.displayNameForHeader)
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                if let subtitle = model.content.textViewModel.subtitle {
                    Text(subtitle)
                        .font(.system(.title2))
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
}

fileprivate struct FullScreenProfilePictureView: View {
    @Environment(\.presentationMode) var presentationMode
    let photo: UIImage?

    var body: some View {
        ZStack {
            Color.black
                .opacity(0.1)
                .edgesIgnoringSafeArea(.all)
            if let photo = photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onTapGesture {
            presentationMode.wrappedValue.dismiss()
        }
    }

}

struct BackgroundBlurView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let effect = UIBlurEffect(style: .regular)
        let view = UIVisualEffectView(effect: effect)
        DispatchQueue.main.async {
            view.superview?.superview?.backgroundColor = .clear
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
