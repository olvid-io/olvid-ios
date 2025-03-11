/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvUIObvCircledInitials
import ObvDesignSystem


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
                let scale = UIScreen.main.scale
                let size = CGSize(width: scale * Self.circleDiameter, height: scale * Self.circleDiameter)
                self.profilePicture = image?.preparingThumbnail(of: size)
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
            return AnyView(NewDiscussionsListView(ownedCryptoId: ownedCryptoId, restrictToActiveDiscussions: true, discussionsViewModel: model))
        } else {
            return AnyView(DiscussionsListView(ownedCryptoId: ownedCryptoId, discussionsViewModel: model))
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
        .listStyle(InsetGroupedListStyle())
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

    private var circledText: String? {
        let title = model.persistedDiscussion.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let char = title.first {
            return String(char)
        } else {
            return nil
        }
    }
    
    private var profilePictureViewModelContent: ProfilePictureView.Model.Content {
        .init(text: circledText,
              icon: systemImage,
              profilePicture: model.profilePicture,
              showGreenShield: (try? model.persistedDiscussion.showGreenShield) ?? false,
              showRedShield: (try? model.persistedDiscussion.showRedShield) ?? false)
    }
    
    private var initialCircleViewModelColors: InitialCircleView.Model.Colors {
        .init(background: identityColors?.background,
              foreground: identityColors?.text)
    }
    
    private var profilePictureViewModel: ProfilePictureView.Model {
        .init(content: profilePictureViewModelContent,
              colors: initialCircleViewModelColors,
              circleDiameter: 60.0)
    }
    
    private var textViewModel: TextView.Model {
        .init(titlePart1: model.persistedDiscussion.title,
              titlePart2: nil,
              subtitle: nil,
              subsubtitle: nil)
    }

    var body: some View {
        HStack {
            ProfilePictureView(model: profilePictureViewModel)
            TextView(model: textViewModel)
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
