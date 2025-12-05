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


struct ObvSearchable: ViewModifier {
    
    //nonisolated public func searchable(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: Text? = nil) -> some View

    let text: Binding<String>
    let isPresented: Binding<Bool>
    let placement: SearchFieldPlacement
    let prompt: Text?
    
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .searchable(text: text, isPresented: isPresented, placement: placement, prompt: prompt)
        } else {
            content
                .searchable(text: text, placement: placement, prompt: prompt)
        }
    }
    
}

extension View {
    
    /// Wrapper around Apple's `func searchable(text: Binding<String>, isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic, prompt: Text? = nil)` API, which is only available on iOS 17+.
    public func searchableOniOS17(text: Binding<String>, isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic, prompt: Text? = nil) -> some View {
        self.modifier(ObvSearchable(text: text, isPresented: isPresented, placement: placement, prompt: prompt))
    }
    
}
