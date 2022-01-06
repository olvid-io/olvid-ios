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

final class LinkViewPlaceHolderView: UIView {

    private let stackView = UIStackView()
    let label = UILabel()
    let spinner: UIActivityIndicatorView
    
    var link: URL? {
        didSet {
            guard let link = self.link else {
                label.text = nil
                return
            }
            var components = URLComponents()
            components.host = link.host
            components.scheme = link.scheme
            label.text = components.url?.absoluteString
        }
    }
    
    override init(frame: CGRect) {
        
        if #available(iOS 13, *) {
            spinner = UIActivityIndicatorView(style: .medium)
        } else {
            spinner = UIActivityIndicatorView(style: .gray)
        }
        
        super.init(frame: frame)
        
        resetBackgroundColor()
        layer.cornerRadius = 8.0
        
        stackView.accessibilityIdentifier = "stackView"
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.backgroundColor = .blue
        stackView.alignment = .center
        stackView.spacing = 8.0
        
        spinner.accessibilityIdentifier = "spinner"
        stackView.addArrangedSubview(spinner)
        spinner.startAnimating()
        
        label.accessibilityIdentifier = "label"
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        stackView.addArrangedSubview(label)
        
        self.addSubview(stackView)
        
        setupConstraints()
    }
    
    func resetBackgroundColor() {
        backgroundColor = UIColor.white.withAlphaComponent(0.5)
    }
    
    
    private func setupConstraints() {
        let constraints = [
            stackView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            stackView.widthAnchor.constraint(equalTo: self.widthAnchor, multiplier: 0.8)
        ]
        NSLayoutConstraint.activate(constraints)
    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
