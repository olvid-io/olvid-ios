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



import CoreData
import ObvUI
import ObvTypes
import os.log
import SwiftUI
import ObvUICoreData
import UI_CircledInitialsView_CircledInitialsConfiguration

protocol DiscussionsHostingViewControllerDelegate: AnyObject {
    func setSelectedDiscussions(to: [PersistedDiscussion]) async throws
}


// MARK: - DiscussionViewModel

final class DiscussionViewModel: ObservableObject, Hashable {
    
    @Published var selected: Bool
    let profilePicture: UIImage?
    let persistedDiscussion: PersistedDiscussion
    let style: IdentityColorStyle

    static let circleDiameter = 40.0

    init(persistedDiscussion: PersistedDiscussion, selected: Bool, style: IdentityColorStyle) {
        self.persistedDiscussion = persistedDiscussion
        self.selected = selected
        self.style = style

        do {
            if let photoURL = try persistedDiscussion.displayPhotoURL {
                let image = UIImage(contentsOfFile: photoURL.path)
                if #available(iOS 15, *) {
                    let scale = UIScreen.main.scale
                    let size = CGSize(width: scale * Self.circleDiameter, height: scale * Self.circleDiameter)
                    self.profilePicture = image?.preparingThumbnail(of: size)
                } else {
                    self.profilePicture = nil
                }
            } else {
                self.profilePicture = nil
            }
        } catch {
            assertionFailure(error.localizedDescription)
            self.profilePicture = nil
        }
    }
}


// MARK: - DiscussionViewModel Hashable

extension DiscussionViewModel {
    static func == (lhs: DiscussionViewModel, rhs: DiscussionViewModel) -> Bool {
        return lhs.profilePicture === rhs.profilePicture
        && lhs.persistedDiscussion == rhs.persistedDiscussion
        && lhs.style == rhs.style
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(profilePicture)
        hasher.combine(persistedDiscussion)
        hasher.combine(style)
    }
}


// MARK: - DiscussionsViewModel

final class DiscussionsViewModel {
    
    private(set) var discussions: [DiscussionViewModel] = []
    
    var selectedDiscussions: [DiscussionViewModel] {
        return discussions.filter({ $0.selected })
    }

    weak var delegate: DiscussionsHostingViewControllerDelegate?

    init(discussions: [DiscussionViewModel]) {
        self.discussions = discussions
    }
}


// MARK: - DiscussionsView

struct DiscussionsView: View {
    
    var model: DiscussionsViewModel
    let ownedCryptoId: ObvCryptoId
    
    var body: some View {
        subView
            .onDisappear {
                let selectedDiscussion = model.selectedDiscussions.map { $0.persistedDiscussion }
                Task {
                    do {
                        try await  model.delegate?.setSelectedDiscussions(to: selectedDiscussion)
                    } catch {
                        os_log("onDisappear in DiscussionsView: %@", type: .error, error.localizedDescription)
                        assertionFailure(error.localizedDescription)
                    }
                }
            }
    }
    
    private var subView: some View {
        if #available(iOSApplicationExtension 16.0, *) {
            return AnyView(NewDiscussionsListView(ownedCryptoId: ownedCryptoId, discussionsViewModel: model))
        } else if #available(iOSApplicationExtension 15.0, *) {
            return AnyView(DiscussionsListView(ownedCryptoId: ownedCryptoId, discussionsViewModel: model))
        } else {
            return AnyView(DiscussionsScrollingView(discussionModels: model.discussions))
        }
    }
}


@available(iOS, introduced: 13.0, deprecated: 16.0, message: "This SwiftUI view is should be replaced by the DiscussionsListView")
fileprivate struct DiscussionsScrollingView: View {
    var discussionModels: [DiscussionViewModel]
    var body: some View {
        DiscussionsInnerView(discussionModels: discussionModels)
    }
}


@available(iOS, introduced: 13.0, deprecated: 16.0, message: "Used by DiscussionsScrollingView")
fileprivate struct DiscussionsInnerView: View {

    var discussionModels: [DiscussionViewModel]

    init(discussionModels: [DiscussionViewModel]) {
        self.discussionModels = discussionModels
    }

    var body: some View {
        List {
            ForEach(discussionModels, id: \.self) { discussionModel in
                DiscussionCellView(model: discussionModel)
            }
        }
        .obvListStyle()
    }
}


@available(iOS, introduced: 13.0, deprecated: 16.0, message: "Used by DiscussionsInnerView")
fileprivate struct DiscussionCellView: View {
    
    @ObservedObject var model: DiscussionViewModel

    private var identityColors: (background: UIColor, text: UIColor)? {
        return try? model.persistedDiscussion.identityColors(with: model.style)
    }

    private var systemImage: CircledInitialsIcon {
        do {
            switch try model.persistedDiscussion.kind {
            case .oneToOne:
                return .person
            case .groupV1, .groupV2:
                return .person3Fill
            }
        } catch {
            assertionFailure(error.localizedDescription)
            return .person
        }
    }

    private var profilePicture: UIImage? {
        do {
            guard let photoURL = try model.persistedDiscussion.displayPhotoURL else {
                return nil
            }
            return UIImage(contentsOfFile: photoURL.path)
        } catch {
            assertionFailure(error.localizedDescription)
            return nil
        }
    }

    private var circledTextView: Text? {
        let title = model.persistedDiscussion.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let char = title.first {
            return Text(String(char))
        } else {
            return nil
        }
    }

    private var pictureViewInner: some View {
        let showGreenShield = (try? model.persistedDiscussion.showGreenShield) ?? false
        let showRedShield = (try? model.persistedDiscussion.showRedShield) ?? false
        return ProfilePictureView(profilePicture: model.profilePicture,
                                  circleBackgroundColor: identityColors?.background,
                                  circleTextColor: identityColors?.text,
                                  circledTextView: circledTextView,
                                  systemImage: systemImage,
                                  showGreenShield: showGreenShield,
                                  showRedShield: showRedShield,
                                  customCircleDiameter: DiscussionViewModel.circleDiameter)
    }

    var body: some View {
        HStack {
            pictureViewInner
            TextView(titlePart1: model.persistedDiscussion.title,
                     titlePart2: nil,
                     subtitle: nil,
                     subsubtitle: nil)
            Spacer()
            Image(systemIcon: model.selected ? .checkmarkCircleFill : .circle)
                .font(Font.system(size: 24, weight: .regular, design: .default))
                .foregroundColor(model.selected ? Color(AppTheme.shared.colorScheme.olvidLight) : Color.gray)
                .padding(.leading)
        }
        .contentShape(Rectangle()) // This makes it possible to have an "on tap" gesture that also works when the Spacer is tapped
        .onTapGesture {
            model.selected.toggle()
        }
    }
}
