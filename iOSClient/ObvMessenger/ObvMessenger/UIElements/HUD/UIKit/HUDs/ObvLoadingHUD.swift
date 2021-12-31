/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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


final class ObvLoadingHUD: ObvHUDView {
    
    var progress: Progress? {
        get {
            progressView.observedProgress
        }
        set {
            progressView.observedProgress = newValue
            setNeedsLayout()
        }
    }
    
    private var tapToCancelLabel = UILabel()
    
    @objc func tapToCancelPerformed() {
        if isCancellable {
            progress?.cancel()
        }
    }
    
    private let activityIndicatorView: UIActivityIndicatorView = {
        if #available(iOS 13.0, *) {
            return UIActivityIndicatorView(style: .large)
        } else {
            return UIActivityIndicatorView(style: .whiteLarge)
        }
    }()
    private let progressView = UIProgressView(progressViewStyle: .default)
    
    override func layoutSubviews() {
        super.layoutSubviews()
                
        if activityIndicatorView.superview == nil {
            addSubview(activityIndicatorView)
            
            activityIndicatorView.translatesAutoresizingMaskIntoConstraints = false
            activityIndicatorView.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
            activityIndicatorView.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
            activityIndicatorView.startAnimating()
        }
        
        if progressView.superview == nil {
            addSubview(progressView)
            
            progressView.translatesAutoresizingMaskIntoConstraints = false
            progressView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 8).isActive = true
            progressView.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -8).isActive = true
            progressView.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -8).isActive = true
        }
        
        if tapToCancelLabel.superview == nil {
            
            tapToCancelLabel.text = NSLocalizedString("TAP_TO_CANCEL", comment: "")
            tapToCancelLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
            tapToCancelLabel.numberOfLines = 2
            tapToCancelLabel.textAlignment = .center
            if #available(iOS 13, *) {
                tapToCancelLabel.textColor = .secondaryLabel
            }
            
            addSubview(tapToCancelLabel)

            tapToCancelLabel.translatesAutoresizingMaskIntoConstraints = false
            tapToCancelLabel.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
            tapToCancelLabel.bottomAnchor.constraint(equalTo: progressView.topAnchor).isActive = true
            tapToCancelLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.9).isActive = true
        
            addGestureRecognizer(UITapGestureRecognizer.init(target: self, action: #selector(tapToCancelPerformed)))

        }
        
        progressView.isHidden = (progress == nil)
        tapToCancelLabel.isHidden = !isCancellable
        
    }
    
    private var isCancellable: Bool {
        progress != nil && progress!.isCancellable
    }
    
    public func animate() {
        activityIndicatorView.startAnimating()
    }
    
    
}
