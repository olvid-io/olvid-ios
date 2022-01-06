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
import PDFKit

class PdfViewController: UIViewController {

    static let nibName = "PdfViewController"
    
    // Interface
    
    let pdfDocument: PDFDocument
    let fileName: String

    // Views
    
    @IBOutlet weak var pdfView: PDFView!
    @IBOutlet weak var pdfThumbnailView: PDFThumbnailView!
    
    // Constraints
    
    @IBOutlet weak var pdfThumbnailViewHeightConstraint: NSLayoutConstraint!
    
    // Delegate
    
    weak var delegate: PdfViewControllerDelegate?
    
    // Initializers
    
    init(with pdfDocument: PDFDocument, fileName: String) {
        self.pdfDocument = pdfDocument
        self.fileName = fileName
        super.init(nibName: PdfViewController.nibName, bundle: nil)
        
        let exportButton = UIBarButtonItem(barButtonSystemItem: .action,
                                           target: self,
                                           action: #selector(exportPdfFileToDocument))
        self.navigationItem.setRightBarButton(exportButton, animated: false)

        if pdfDocument.documentAttributes?[PDFDocumentAttribute.titleAttribute] == nil {
            self.title = fileName
        }
    }
    
    @objc func exportPdfFileToDocument() {
        delegate?.userWantsToExportPDFDocument()
    }
    
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {

        pdfView.displayMode = .singlePageContinuous
        pdfView.autoScales = true
        pdfView.document = pdfDocument
        pdfView.displayDirection = .vertical

        pdfThumbnailView.thumbnailSize = CGSize(width: pdfThumbnailViewHeightConstraint.constant,
                                                height: pdfThumbnailViewHeightConstraint.constant)
        pdfThumbnailView.layoutMode = .horizontal
        pdfThumbnailView.pdfView = pdfView
        
        setTitleFromPdfDocumentTitleAttribute()
    }
    
    private func setTitleFromPdfDocumentTitleAttribute() {
        guard let attributes = pdfDocument.documentAttributes else { return }
        guard let pdfTitle = attributes[PDFDocumentAttribute.titleAttribute] as? String else { return }
        self.title = pdfTitle
    }
}
