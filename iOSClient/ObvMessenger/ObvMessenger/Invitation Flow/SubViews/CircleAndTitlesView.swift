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
  

import SwiftUI

enum CircleAndTitlesDisplayMode {
    case normal
    case small
    case header(tapToFullscreen: Bool)
}

enum CircleAndTitlesEditionMode {
    case none
    case picture
    case nicknameAndPicture(action: () -> Void)
}

struct CircleAndTitlesView: View {

    private let titlePart1: String?
    private let titlePart2: String?
    private let subtitle: String?
    private let subsubtitle: String?
    private let circleBackgroundColor: UIColor?
    private let circleTextColor: UIColor?
    private let circledTextView: Text?
    private let systemImage: InitialCircleViewSystemImage
    @Binding var profilePicture: UIImage?
    @Binding var changed: Bool
    private let alignment: VerticalAlignment
    private let showGreenShield: Bool
    private let showRedShield: Bool
    private let displayMode: CircleAndTitlesDisplayMode
    private let editionMode: CircleAndTitlesEditionMode

    @State private var profilePictureFullScreenIsPresented = false

    init(titlePart1: String?, titlePart2: String?, subtitle: String?, subsubtitle: String?, circleBackgroundColor: UIColor?, circleTextColor: UIColor?, circledTextView: Text?, systemImage: InitialCircleViewSystemImage, profilePicture: Binding<UIImage?>, changed: Binding<Bool>, alignment: VerticalAlignment = .center, showGreenShield: Bool, showRedShield: Bool, editionMode: CircleAndTitlesEditionMode, displayMode: CircleAndTitlesDisplayMode) {
        self.titlePart1 = titlePart1
        self.titlePart2 = titlePart2
        self.subtitle = subtitle
        self.subsubtitle = subsubtitle
        self.circleBackgroundColor = circleBackgroundColor
        self.circleTextColor = circleTextColor
        self.circledTextView = circledTextView
        self.systemImage = systemImage
        self._profilePicture = profilePicture
        self._changed = changed
        self.alignment = alignment
        self.editionMode = editionMode
        self.displayMode = displayMode
        self.showGreenShield = showGreenShield
        self.showRedShield = showRedShield
    }

    private var circleDiameter: CGFloat {
        switch displayMode {
        case .small:
            return 40.0
        case .normal:
            return ProfilePictureView.circleDiameter
        case .header:
            return 120
        }
    }

    private var pictureViewInner: some View {
        ProfilePictureView(profilePicture: profilePicture, circleBackgroundColor: circleBackgroundColor, circleTextColor: circleTextColor, circledTextView: circledTextView, systemImage: systemImage, showGreenShield: showGreenShield, showRedShield: showRedShield, customCircleDiameter: circleDiameter)
    }

    private var pictureView: some View {
        ZStack {
            if #available(iOS 14.0, *) {
                pictureViewInner
                    .onTapGesture {
                        guard case .header(let tapToFullscreen) = displayMode else { return }
                        guard tapToFullscreen else { return }
                        guard profilePicture != nil else {
                            profilePictureFullScreenIsPresented = false
                            return
                        }
                        profilePictureFullScreenIsPresented.toggle()
                    }
                    .fullScreenCover(isPresented: $profilePictureFullScreenIsPresented) {
                        FullScreenProfilePictureView(photo: profilePicture)
                            .background(BackgroundBlurView()
                                            .edgesIgnoringSafeArea(.all))
                    }
            } else {
                pictureViewInner
            }
            switch editionMode {
            case .none:
                EmptyView()
            case .picture:
                CircledCameraButtonView(profilePicture: $profilePicture)
                    .offset(CGSize(width: ProfilePictureView.circleDiameter/3, height: ProfilePictureView.circleDiameter/3))
            case .nicknameAndPicture(let action):
                Button(action: action) {
                    CircledPencilView()
                }
                .offset(CGSize(width: circleDiameter/3, height: circleDiameter/3))
            }
        }
    }

    private var displayNameForHeader: String {
        let _titlePart1 = titlePart1 ?? ""
        let _titlePart2 = titlePart2 ?? ""
        return [_titlePart1, _titlePart2].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        switch displayMode {
        case .normal, .small:
            HStack(alignment: self.alignment, spacing: 16) {
                pictureView
                TextView(titlePart1: titlePart1,
                         titlePart2: titlePart2,
                         subtitle: subtitle,
                         subsubtitle: subsubtitle)
            }
        case .header:
            VStack(spacing: 8) {
                pictureView
                Text(displayNameForHeader)
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.semibold)
            }
        }
    }
}

fileprivate struct FullScreenProfilePictureView: View {
    @Environment(\.presentationMode) var presentationMode
    var photo: UIImage? // We use a binding here because this is what a SingleIdentity exposes

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
