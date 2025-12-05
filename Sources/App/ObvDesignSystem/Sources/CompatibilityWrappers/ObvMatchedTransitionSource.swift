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



extension View {
    
    /// Identifies this view as the source of a navigation transition, such
    /// as a zoom transition.
    ///
    /// - Parameters:
    ///   - id: The identifier, often derived from the identifier of
    ///     the data being displayed by the view.
    ///   - namespace: The namespace in which defines the `id`. New
    ///     namespaces are created by adding an ``Namespace`` variable
    ///     to a ``View`` type and reading its value in the view's body
    ///     method.
    nonisolated public func matchedTransitionSourceOnIOS18(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            return self.matchedTransitionSource(id: id, in: namespace)
        } else {
            return self
        }
    }
    
    
    /// Sets the navigation transition style for this view.
    ///
    /// Add this modifier to a view that appears within a
    /// ``NavigationStack`` or a sheet, outside of any containers such as
    /// ``VStack``.
    ///
    ///     struct ContentView: View {
    ///         @Namespace private var namespace
    ///         var body: some View {
    ///             NavigationStack {
    ///                 NavigationLink {
    ///                     DetailView()
    ///                         .navigationTransition(.zoom(sourceID: "world", in: namespace))
    ///                 } label: {
    ///                     Image(systemName: "globe")
    ///                         .matchedTransitionSource(id: "world", in: namespace)
    ///                 }
    ///             }
    ///         }
    ///     }
    ///
    nonisolated public func navigationZoomTransitionOnIOS18(id: some Hashable, in namespace: Namespace.ID) -> some View {
        #if targetEnvironment(macCatalyst)
        return self
        #else
        if #available(iOS 18.0, *) {
            return self.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            return self
        }
        #endif
    }

}
