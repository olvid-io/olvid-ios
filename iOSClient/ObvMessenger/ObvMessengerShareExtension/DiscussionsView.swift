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
import ObvTypes
import CoreData

protocol DiscussionsHostingViewControllerDelegate: AnyObject {
    func setSelectedDiscussions(to: [PersistedDiscussion])
}

final class DiscussionsHostingViewController: UIHostingController<DiscussionsView> {

    private let model: DiscussionsViewModel

    init(ownedIdentity: PersistedObvOwnedIdentity, selectedDiscussions: [PersistedDiscussion]) {
        self.model = DiscussionsViewModel(ownedIdentity: ownedIdentity, selectedDiscussions: selectedDiscussions)
        let view = DiscussionsView(model: model)

        super.init(rootView: view)
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var delegate: DiscussionsHostingViewControllerDelegate? {
        get { model.delegate }
        set { model.delegate = newValue }
    }


}

fileprivate class DiscussionViewModel: NSObject, ObservableObject {

    let discussionUI: PersistedDiscussionUI

    @Published var selected: Bool
    @Published var profilePicture: UIImage? = nil

    static let circleDiameter = 40.0

    init(discussionUI: PersistedDiscussionUI, selected: Bool) {
        self.discussionUI = discussionUI
        self.selected = selected
        self.profilePicture = nil
        super.init()
        if let photoURL = discussionUI.photoURL {
            let image = UIImage(contentsOfFile: photoURL.path)
            if #available(iOS 15, *) {
                let scale = UIScreen.main.scale
                let size = CGSize(width: scale * Self.circleDiameter, height: scale * Self.circleDiameter)
                self.profilePicture = image?.preparingThumbnail(of: size)
            }
        }
    }
}

class DiscussionsViewModel: NSObject, ObservableObject {
    private let ownedIdentityContext: NSManagedObjectContext?

    fileprivate var discussions: [DiscussionViewModel] = []

    var context: NSManagedObjectContext {
        guard let ownedIdentityContext = ownedIdentityContext else {
            assertionFailure()
            return ObvStack.shared.viewContext

        }
        return ownedIdentityContext
    }

    weak var delegate: DiscussionsHostingViewControllerDelegate?

    init(ownedIdentity: PersistedObvOwnedIdentity, selectedDiscussions: [PersistedDiscussion]) {
        let fetchRequest = PersistedDiscussion.getFetchRequestForAllActiveRecentDiscussionsForOwnedIdentity(with: ownedIdentity.cryptoId)
        self.ownedIdentityContext = ownedIdentity.managedObjectContext
        super.init()
        let discussions = (try? context.fetch(fetchRequest)) ?? []
        for discussion in discussions {
            assert(discussion.status == .active)
            guard discussion.status == .active else { continue }
            guard let discussionUI = discussion as? PersistedDiscussionUI else {
                assertionFailure(); continue
            }
            let discussionModel = DiscussionViewModel(discussionUI: discussionUI, selected: selectedDiscussions.contains(discussion))
            self.discussions += [discussionModel]
        }
    }
}

struct DiscussionsView: View {
    @ObservedObject var model: DiscussionsViewModel
    var body: some View {
        DiscussionsScrollingView(discussionModels: model.discussions)
            .onDisappear {
                let selectedDiscussion = model.discussions.filter { $0.selected }.map { $0.discussionUI }
                model.delegate?.setSelectedDiscussions(to: selectedDiscussion)
            }
    }
}

fileprivate struct DiscussionsScrollingView: View {
    var discussionModels: [DiscussionViewModel]
    var body: some View {
        DiscussionsInnerView(discussionModels: discussionModels)
    }

}

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
