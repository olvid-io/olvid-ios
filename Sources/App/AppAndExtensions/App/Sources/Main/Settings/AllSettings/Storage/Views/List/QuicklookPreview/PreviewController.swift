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

import QuickLook
import SwiftUI

struct PreviewController: UIViewControllerRepresentable {
    
    let url: URL
    let urls: [URL]
    
    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        
        controller.currentPreviewItemIndex = urls.firstIndex(of: url) ?? 0
        
        let navigationController = UINavigationController(rootViewController: controller)
        return navigationController
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }
    
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
    
}

class Coordinator: QLPreviewControllerDataSource {
    let parent: PreviewController
    
    init(parent: PreviewController) {
        self.parent = parent
    }
    
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return parent.urls.count
    }
    
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return parent.urls[index] as NSURL
    }
    
}
