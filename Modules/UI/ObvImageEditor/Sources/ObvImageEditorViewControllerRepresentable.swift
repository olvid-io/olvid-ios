/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import UIKit

/// Allows to use the ``ObvImageEditorViewController`` in a SwiftUI view
public struct ObvImageEditorViewControllerRepresentable: UIViewControllerRepresentable {
    
    public let originalImage: UIImage
    public let showZoomButtons: Bool
    public let maxReturnedImageSize: (width: Int, height: Int) // In pixels
    private let delegate: Delegate
    fileprivate let completion: (UIImage?) -> Void
    
    public init(originalImage: UIImage, showZoomButtons: Bool, maxReturnedImageSize: (width: Int, height: Int), completion: @escaping (UIImage?) -> Void) {
        self.originalImage = originalImage
        self.showZoomButtons = showZoomButtons
        self.maxReturnedImageSize = maxReturnedImageSize
        self.completion = completion
        self.delegate = Delegate()
        self.delegate.view = self
    }
    
    public func makeUIViewController(context: Context) -> ObvImageEditorViewController {
        ObvImageEditorViewController(
            originalImage: originalImage,
            showZoomButtons: showZoomButtons,
            maxReturnedImageSize: maxReturnedImageSize,
            delegate: delegate)
    }
    
    public func updateUIViewController(_ imageEditor: ObvImageEditorViewController, context: UIViewControllerRepresentableContext<ObvImageEditorViewControllerRepresentable>) {}

}


private final class Delegate: ObvImageEditorViewControllerDelegate {
    
    deinit {
        debugPrint("deinit Delegate: ObvImageEditorViewControllerDelegate")
    }
    
    fileprivate var view: ObvImageEditorViewControllerRepresentable?
    
    @MainActor
    func userCancelledImageEdition(_ imageEditor: ObvImageEditorViewController) async {
        view?.completion(nil)
    }
    
    @MainActor
    func userConfirmedImageEdition(_ imageEditor: ObvImageEditorViewController, image: UIImage) async {
        view?.completion(image)
    }
    
}
