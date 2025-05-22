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
import ObvAppCoreConstants

@available(iOS 17.0, *)
struct QuicklookPreviewModifier<Model: StorageManagementFileListViewModelProtocol>: ViewModifier {
    
    var model: Model
    
    
    @ViewBuilder
    func body(content: Content) -> some View {
        
        if ObvAppCoreConstants.targetEnvironmentIsMacCatalyst {
            content.modifier(QuicklookPreviewForCatalystModifier(model: model))
        } else {
            content.quickLookPreview(Binding(get: { self.model.quicklookURL }, set: { self.model.setQuicklookURL($0) }), in: model.quicklookURLs)
        }
    }
}

@available(iOS 17.0, *)
struct QuicklookPreviewForCatalystModifier<Model: StorageManagementFileListViewModelProtocol>: ViewModifier {
    var model: Model
    
    @State private var showingPreview = false
    
    func body(content: Content) -> some View {
        content
            .onChange(of: model.quicklookURL, { _, newValue in
                if newValue == nil {
                    self.showingPreview = false
                } else {
                    self.showingPreview = true
                }
            })
            .sheet(isPresented: $showingPreview, onDismiss: {
                model.setQuicklookURL(nil)
            }) {
                if let url = model.quicklookURL {
                    PreviewController(url: url, urls: model.quicklookURLs)
                }
            }
    }
}
