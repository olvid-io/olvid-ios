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
import ObvEngine
import ObvTypes

class LargeOlvidCardViewController: UIViewController {

    static let nibName = "LargeOlvidCardViewController"
    
    private let identityDetails: ObvIdentityDetails
    private let genericIdentity: ObvGenericIdentity
    
    // Views
    
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var subtitleLabel: UILabel!
    @IBOutlet weak var coverView: UIView!
    @IBOutlet weak var tempView: UIView!
    @IBOutlet weak var viewForActivityIndicator: UIView!
    @IBOutlet weak var stackView: UIStackView!
    @IBOutlet weak var containerViewForQRCodeImageView: UIView!
    
    init(publishedIdentityDetails: ObvIdentityDetails, genericIdentity: ObvGenericIdentity) {
        self.identityDetails = publishedIdentityDetails
        self.genericIdentity = genericIdentity
        super.init(nibName: LargeOlvidCardViewController.nibName, bundle: nil)
        if #available(iOS 13, *) {
            modalPresentationStyle = .automatic
        } else {
            modalPresentationStyle = .overFullScreen
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @IBAction func dismissButtonTapped(_ sender: Any) {
        self.dismiss(animated: true)
    }
}


extension LargeOlvidCardViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .clear
        coverView.backgroundColor = AppTheme.shared.colorScheme.systemBackground
        coverView.layer.cornerRadius = 8.0
        coverView.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMinXMinYCorner]
        titleLabel.textColor = AppTheme.shared.colorScheme.label
        subtitleLabel.textColor = AppTheme.shared.colorScheme.secondaryLabel
        let activityIndicator = DotsActivityIndicatorView()
        viewForActivityIndicator.addSubview(activityIndicator)
        viewForActivityIndicator.pinAllSidesToSides(of: activityIndicator)
        activityIndicator.startAnimating()
        
        self.titleLabel.text = identityDetails.coreDetails.getDisplayNameWithStyle(.firstNameThenLastName)
        self.subtitleLabel.text = identityDetails.coreDetails.getDisplayNameWithStyle(.positionAtCompany)
        
        if ObvMessengerConstants.developmentMode {
            let buttonCopyIdentity = ObvButton()
            buttonCopyIdentity.setTitle("Copy Identity", for: .normal)
            buttonCopyIdentity.addTarget(self, action: #selector(buttonCopyIdentityPressed), for: .touchUpInside)
            stackView.addArrangedSubview(buttonCopyIdentity)
        }
        
        containerViewForQRCodeImageView.backgroundColor = .white
        
        addQRCode()
    }
 
    @objc
    private func buttonCopyIdentityPressed() {
        UIPasteboard.general.string = genericIdentity.getObvURLIdentity().urlRepresentation.absoluteString
    }

    private func addQRCode() {
        
        let animator = UIViewPropertyAnimator(duration: 0.2, curve: .linear)
        let imageViewBounds = self.imageView.bounds
        
        DispatchQueue(label: "QRCodeGeneration").async { [weak self] in

            let urlRepresentation = self?.genericIdentity.getObvURLIdentity().urlRepresentation
            
            if let qrCode = urlRepresentation?.generateQRCode() {
                
                // Set the size of the QR code
                let transform = CGAffineTransform(scaleX: imageViewBounds.width / qrCode.extent.width,
                                                  y: imageViewBounds.height / qrCode.extent.height)
                let ciImage = qrCode.transformed(by: transform)
                
                DispatchQueue.main.async { [weak self] in
                    self?.imageView.image = UIImage(ciImage: ciImage)
                    self?.imageView.isHidden = false
                    animator.addAnimations {
                        self?.tempView.alpha = 0.0
                    }
                    animator.startAnimation()
                }
                
            }
            
        }
        
        
    }

}
