/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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


extension View {

    /// Tapping this circled avatar, of diameter `circleDiameter`, loads a picture with `loadPicture` and shows it large over the whole screen, zooming out of the circle where the system allows it.
    ///
    /// The picture is loaded on tap rather than beforehand, as it is usually larger than the circle and seldom asked for. The reader closes it with the xmark,
    /// with Esc, or by tapping anywhere outside the picture. Tapping does nothing while `loadPicture` is nil.
    public func showsProfilePictureLargeWhenTapped(circleDiameter: CGFloat, loadPicture: (@MainActor () async -> CGImage?)?) -> some View {
        modifier(ShowsProfilePictureLargeWhenTapped(circleDiameter: circleDiameter, loadPicture: loadPicture))
    }

}


private struct ShowsProfilePictureLargeWhenTapped: ViewModifier {

    let circleDiameter: CGFloat
    let loadPicture: (@MainActor () async -> CGImage?)?

    /// Held by the cover, so that the picture stays while it is shown whatever becomes of the one in the circle.
    @State private var pictureShownLarge: PictureShownLarge?
    @State private var isLoading = false
    @Namespace private var namespace

    private static let transitionID = "profilePicture"

    func body(content: Content) -> some View {
        content
            .matchedTransitionSourceOnIOS18(id: Self.transitionID, in: namespace, cornerRadius: circleDiameter / 2)
            .onTapGesture {
                guard let loadPicture, !isLoading else { return }
                isLoading = true
                Task {
                    defer { isLoading = false }
                    guard let picture = await loadPicture() else { return }
                    pictureShownLarge = PictureShownLarge(picture: picture)
                }
            }
            // A modifier rather than a branch, so that the avatar keeps its identity when its picture arrives.
            .accessibilityHint(loadPicture == nil ? Text(verbatim: "") : Text("TAP_TO_SHOW_IMAGE"))
            .fullScreenCover(item: $pictureShownLarge) { shown in
                ProfilePictureShownLarge(picture: shown.picture)
                    .navigationZoomTransitionOnIOS18(id: Self.transitionID, in: namespace)
            }
    }

}


private struct PictureShownLarge: Identifiable {
    let id = UUID()
    let picture: CGImage
}


private struct ProfilePictureShownLarge: View {

    let picture: CGImage

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                // What is behind the picture closes it, a click beside the picture being the usual way out of a modal on a Mac.
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }
                // The scale does not matter, the picture being fitted to the screen.
                Image(decorative: picture, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .padding()
            }
            // Nothing else in this cover can hold focus, and without it Esc never reaches the xmark.
            .takesKeyboardFocusOnAppear()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ObvButtonWithCancelRole(action: { dismiss() })
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .modifier(MaterialBackground())
    }

}


/// Lets what the picture covers show through, blurred.
private struct MaterialBackground: ViewModifier {

    @Environment(\.colorScheme) private var colorScheme

    /// In dark mode a material alone reads grey, so a thinner one is darkened towards black.
    private var backdrop: some View {
        ZStack {
            if colorScheme == .dark {
                Rectangle().fill(.ultraThinMaterial)
                Color.black.opacity(0.6)
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
        .ignoresSafeArea()
    }

    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content
                .presentationBackground { backdrop }
        } else {
            content
                .background { backdrop }
        }
    }

}
