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

import Foundation
import SwiftUI
import CoreData
import ObvDesignSystem

@available(iOS 17.0, *)
@MainActor
@Observable
final class PollRouter {
    
    enum Route: Hashable, Identifiable {
        case root(pollIdentifier: PollIdentifier)
        case candidateInfos(title: String, pollCandidateIdentifier: PollCandidateIdentifier)
        
        var id: Self {
            return self
        }
    }
    
    var path: NavigationPath = NavigationPath()
    
    public let dataSource: any PollViewDataSourceProtocol
    let avatarViewDataSource: any ObvAvatarViewDataSource
    
    init(dataSource: any PollViewDataSourceProtocol, avatarViewDataSource: any ObvAvatarViewDataSource) {
        self.dataSource = dataSource
        self.avatarViewDataSource = avatarViewDataSource
    }
    
    private func rootView(pollIdentifier: PollIdentifier) -> some View {
        PollView(pollIdentifier: pollIdentifier,
                 router: self)
    }
    
    private func candidateInfosView(pollCandidateIdentifier: PollCandidateIdentifier) -> some View {
        PollCandidateView(pollCandidateIdentifier: pollCandidateIdentifier,
                          dataSource: dataSource,
                          avatarViewDataSource: avatarViewDataSource)
    }
    
    @ViewBuilder
    func view(for route: Route) -> some View {
        switch route {
        case .root(pollIdentifier: let pollIdentifier):
            rootView(pollIdentifier: pollIdentifier)
        case .candidateInfos(title: let title, pollCandidateIdentifier: let pollCandidateIdentifier):
            candidateInfosView(pollCandidateIdentifier: pollCandidateIdentifier).navigationTitle(title)
        }
    }
    
    // Used by views to navigate to another view
    func navigateTo(_ route: Route) {
        path.append(route)
    }
    
    // Pop to the root screen in our hierarchy
    func popToRoot() {
        path.removeLast(path.count)
    }
    
    @discardableResult
    func dismiss() -> Bool {
        var hasNavigated: Bool = true
        
        if !path.isEmpty {
            path.removeLast()
        } else {
            hasNavigated = false
        }
        
        return hasNavigated
    }
}
