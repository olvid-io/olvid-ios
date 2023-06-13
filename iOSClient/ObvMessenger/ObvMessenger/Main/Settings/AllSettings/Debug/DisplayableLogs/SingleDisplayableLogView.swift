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
import QuickLook
import ObvUICoreData

struct SingleDisplayableLogView: UIViewControllerRepresentable {
    
    typealias UIViewControllerType = QLPreviewController

    private let internalDataSource: InternalDataSource
    
    init(logURL: NSURL?) {
        self.internalDataSource = InternalDataSource(logURL: logURL)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let vc = QLPreviewController()
        vc.dataSource = internalDataSource
        return vc
    }
    
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        debugPrint("updateUIViewController")
    }

    // QLPreviewControllerDataSource
    
    final class InternalDataSource: QLPreviewControllerDataSource {
        
        private let logURL: NSURL?
        private var tempURL: NSURL?
        
        init(logURL: NSURL?) {
            self.logURL = logURL
        }

        // When the number of item is requested, we try to create a temporary URL and to copy the log to that URL.
        // If this succeeds, we have a log to show. Otherwise, we return 0 here.
        // We create a temporary URL instead of showing the logURL directely to prevent certain side effects of the QLPreviewController (that seems to create files in the directory of the file shown).
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            guard let logURL, let filename = logURL.lastPathComponent else { return 0 }
            if tempURL != nil {
                return 1
            } else {
                let tempURL = ObvUICoreDataConstants.ContainerURL.forTempFiles.appendingPathComponent(filename)
                do {
                    try? FileManager.default.removeItem(at: tempURL)
                    try FileManager.default.copyItem(at: logURL as URL, to: tempURL)
                } catch {
                    assertionFailure()
                    return 0
                }
                self.tempURL = tempURL as NSURL
                return 1
            }
        }
        
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            return tempURL!
        }

    }
        
}
