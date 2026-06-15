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

import CoreData
import ObvUI
import ObvTypes
import OSLog
import SwiftUI
import ObvUICoreData
import ObvUIObvCircledInitials
import ObvDesignSystem
import ObvCircleAndTitlesView


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
        NewDiscussionsListView(ownedCryptoId: ownedCryptoId, restrictToActiveDiscussions: true, discussionsViewModel: model)
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
    
}
