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
import ObvUICoreData
import CoreData

@available(iOS 17.0, *)
@Observable
final class StorageManagerRouter {
    
    enum Route: Hashable, Identifiable {
        case root(model: StorageManagementViewModel)
        case fileList(title: String, model: StorageManagementFileListViewModel)
        
        var id: Self {
            return self
        }
    }
    
    enum NavigationType {
        case push
        case sheet
        case fullScreenCover
    }
    
    var path: NavigationPath = NavigationPath()
    var presentingSheet: Route?
    var presentingFullScreenCover: Route?
    var isPresented: Binding<Route?>
    
    init(isPresented: Binding<Route?> = .constant(nil)) {
        self.isPresented = isPresented
    }
    
    private func rootView(with model: StorageManagementViewModel, type: NavigationType) -> some View {
        model.router = router(navigationType: type)
        return StorageManagementView(model: model)
    }
    
    private func fileListView(with model: StorageManagementFileListViewModel, type: NavigationType) -> some View {
        model.router = router(navigationType: type)
        return StorageManagementFileListView(model: model)
    }
    
    @ViewBuilder func view(for route: Route, type: NavigationType = .push) -> some View {
        switch route {
        case .root(let model):
            rootView(with: model, type: type)
        case .fileList(title: let title, model: let model):
            fileListView(with: model, type: type).navigationTitle(title)
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
        } else if presentingSheet != nil {
            self.presentingSheet = nil
        } else if presentingFullScreenCover != nil {
            self.presentingFullScreenCover = nil
        } else if isPresented.wrappedValue != nil {
            isPresented.wrappedValue = nil
        } else {
            hasNavigated = false
        }
        
        return hasNavigated
    }
    
    func presentSheet(_ route: Route) {
        self.presentingSheet = route
    }
    
    func presentFullScreen(_ route: Route) {
        self.presentingFullScreenCover = route
    }
    
    func router(navigationType: NavigationType) -> StorageManagerRouter {
        switch navigationType {
        case .push:
            return self
        case .sheet:
            return StorageManagerRouter(
                isPresented: Binding(
                    get: { self.presentingSheet },
                    set: { self.presentingSheet = $0 }
                )
            )
        case .fullScreenCover:
            return StorageManagerRouter(
                isPresented: Binding(
                    get: { self.presentingFullScreenCover },
                    set: { self.presentingFullScreenCover = $0 }
                )
            )
        }
    }
}
