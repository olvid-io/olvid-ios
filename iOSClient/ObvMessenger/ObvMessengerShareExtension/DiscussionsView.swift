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


protocol DiscussionsHostingViewControllerDelegate: AnyObject {
    func setSelectedDiscussions(to: [PersistedDiscussion]) async throws
}


// MARK: - DiscussionViewModel

final class DiscussionViewModel: NSObject, ObservableObject {

    @Published var selected: Bool
    let profilePicture: UIImage?
    let discussionUI: PersistedDiscussionUI

    static let circleDiameter = 40.0

    init(discussionUI: PersistedDiscussionUI, selected: Bool) {
        self.discussionUI = discussionUI
        self.selected = selected

        if let photoURL = discussionUI.photoURL {
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
                let selectedDiscussion = model.selectedDiscussions.map { $0.discussionUI }
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
            return DiscussionsListView(ownedCryptoId: ownedCryptoId, discussionsViewModel: model)
        } else {
            return DiscussionsScrollingView(discussionModels: model.discussions)
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
        return model.discussionUI.identityColors
    }

    private var systemImage: CircledInitialsIcon {
        if model.discussionUI.isLocked {
            return .lockFill
        } else {
            return model.discussionUI.isGroupDiscussion ? .person3Fill : .person
        }
    }

    private var profilePicture: UIImage? {
        guard let photoURL = model.discussionUI.photoURL else { return nil }
        return UIImage(contentsOfFile: photoURL.path)
    }

    private var circledTextView: Text? {
        guard !model.discussionUI.isLocked else { return nil }
        let title = model.discussionUI.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let char = title.first {
            return Text(String(char))
        } else {
            return nil
        }
    }

    private var pictureViewInner: some View {
        ProfilePictureView(profilePicture: model.profilePicture,
                           circleBackgroundColor: identityColors?.background,
                           circleTextColor: identityColors?.text,
                           circledTextView: circledTextView,
                           systemImage: systemImage,
                           showGreenShield: model.discussionUI.showGreenShield,
                           showRedShield: model.discussionUI.showRedShield,
                           customCircleDiameter: DiscussionViewModel.circleDiameter)
    }

    var body: some View {
        HStack {
            pictureViewInner
            TextView(titlePart1: model.discussionUI.title,
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
