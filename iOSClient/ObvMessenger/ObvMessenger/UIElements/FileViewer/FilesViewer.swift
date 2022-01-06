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

import UIKit
import MobileCoreServices
import PDFKit
import AVKit
import os.log
import QuickLook
 

final class FilesViewer: NSObject {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))
    
    /// Empty when using the initialiser using hard links
    let shownFyleMessageJoins: [FyleMessageJoinWithStatus]
    private var hardLinksToFyles: [HardLinkToFyle?]
    
    weak var delegate: QLPreviewControllerDelegate?
    
    var cellIndexPath: IndexPath?
    
    private let preventSharing: Bool
    
    // These two variables are set when the tryToShowFile(...) is called.
    private var indexToShow: Int?
    weak private var viewController: UIViewController?
    
    private var previewControllerIsShown = false
    
    // MARK: - Initializers
    
    init(_ fyleMessageJoins: [FyleMessageJoinWithStatus], preventSharing: Bool) throws {
        
        self.shownFyleMessageJoins = fyleMessageJoins
        self.preventSharing = preventSharing
        
        self.hardLinksToFyles = [HardLinkToFyle?](repeating: nil, count: fyleMessageJoins.count)
        super.init()

        for (index, fyleMessageJoin) in fyleMessageJoins.enumerated() {
            
            let completionHandler = { [weak self] (hardLinkToFyle: HardLinkToFyle) in
                self?.hardLinksToFyles[index] = hardLinkToFyle
                DispatchQueue.main.async {
                    self?.tryToPresentQLPreviewController()
                }
            }

            if let fyleElement = fyleMessageJoin.fyleElement {
                ObvMessengerInternalNotification.requestHardLinkToFyle(fyleElement: fyleElement, completionHandler: completionHandler).postOnDispatchQueue()
            }
            
        }

    }
    
    init(hardLinksToFyles: [HardLinkToFyle], preventSharing: Bool) {
        self.shownFyleMessageJoins = []
        self.preventSharing = preventSharing
        self.hardLinksToFyles = hardLinksToFyles
    }
    
    
    // MARK: - Other methods
    
    func tryToShowFile(atIndex index: Int, within viewController: UIViewController) {
        self.indexToShow = index
        self.viewController = viewController
        tryToPresentQLPreviewController()
    }
    
    
    private func tryToPresentQLPreviewController() {

        // We check whether showing the QLPreviewController was already requested
        guard let indexToShow = self.indexToShow, let viewController = self.viewController else { return }

        // We check that all the hardlinks are ready
        guard !self.hardLinksToFyles.contains(nil) else { return }

        // We check that we are not already showing the QLPreviewController
        guard !previewControllerIsShown else { return }
        previewControllerIsShown = true
        
        // If we reach this point, we are ready to show the QLPreviewController
        let previewController = CustomQLPreviewController()
        previewController.preventSharing = self.preventSharing
        previewController.dataSource = self
        previewController.delegate = self.delegate
        previewController.currentPreviewItemIndex = indexToShow
        viewController.navigationController?.present(previewController, animated: true, completion: nil)

    }
}


// MARK: - QLPreviewControllerDataSource

extension FilesViewer: QLPreviewControllerDataSource {
    
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return self.hardLinksToFyles.count
    }
    
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return self.hardLinksToFyles[index]!
    }
    
}


final class CustomQLPreviewController: QLPreviewController {
    
    var preventSharing = false
        
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if preventSharing {
            self.hideToolBar()
            self.hideShareButtonFromNavigationBar()
        }
    }
    
    /// This is used when `preventSharing` is `true` to hide all bottom toolbar since they contain a sharing
    /// button when more than one items are previewed.
    private func hideToolBar() {
        let allToolbars = self.view.deepSearchAllSubview(ofClass: UIToolbar.self)
        for toolbar in allToolbars {
            toolbar.isHidden = true
        }
    }
    

    /// This is used when `preventSharing` is `true` to hide all top right navigation button since one is shown
    /// when one item are previewed.
    private func hideShareButtonFromNavigationBar() {
        let allNavigationBars = self.view.deepSearchAllSubview(ofClass: UINavigationBar.self)
        for nav in allNavigationBars {
            nav.topItem?.rightBarButtonItem?.isEnabled = false
            nav.topItem?.rightBarButtonItems?.forEach { $0.isEnabled = false }
        }
    }
    
}
