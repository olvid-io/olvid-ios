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

import ObvUI
import UIKit
import ObvDesignSystem


final class OlvidAlertViewController: UIViewController {
    
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let primaryButton = UIButton(type: .system)
    private let secondaryButton = UIButton(type: .system)
    private let buttonsStack = UIStackView()
    private var primaryAction: (() -> Void)?
    private var secondaryAction: (() -> Void)?
    private let bubbleView = UIView()
    private let scrollView = UIScrollView()
    private let contentView = UIView()

    func configure(title: String, body: String, primaryActionTitle: String, primaryAction: @escaping () -> Void, secondaryActionTitle: String, secondaryAction: @escaping () -> Void) {
        self.titleLabel.text = title
        self.bodyLabel.text = body
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.primaryButton.setTitle(primaryActionTitle, for: .normal)
        self.secondaryButton.setTitle(secondaryActionTitle, for: .normal)
    }

    init() {
        super.init(nibName: nil, bundle: nil)
        setupInternalViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupInternalViews()
    }
    
    
    @objc func primaryButtonTapped() {
        primaryAction?()
    }


    @objc func secondaryButtonTapped() {
        secondaryAction?()
    }

    
    private func setupInternalViews() {
        
        view.backgroundColor = AppTheme.shared.colorScheme.systemBackground

        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.isScrollEnabled = true

        scrollView.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        titleLabel.textColor = AppTheme.shared.colorScheme.label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true

        contentView.addSubview(bubbleView)
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.backgroundColor = AppTheme.shared.colorScheme.tertiarySystemFill
        bubbleView.layer.cornerRadius = 16.0
                
        bubbleView.addSubview(bodyLabel)
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.font = UIFont.preferredFont(forTextStyle: .body)
        bodyLabel.textColor = AppTheme.shared.colorScheme.secondaryLabel
        bodyLabel.numberOfLines = 0
        bodyLabel.adjustsFontForContentSizeCategory = true

        contentView.addSubview(buttonsStack)
        buttonsStack.translatesAutoresizingMaskIntoConstraints = false
        buttonsStack.axis = .vertical
        buttonsStack.distribution = .fillEqually
        buttonsStack.spacing = 8.0
                
        buttonsStack.addArrangedSubview(primaryButton)
        do {
            var configuration = UIButton.Configuration.filled()
            configuration.buttonSize = .large
            configuration.cornerStyle = .large
            primaryButton.configuration = configuration
        }
        primaryButton.addTarget(self, action: #selector(primaryButtonTapped), for: .touchUpInside)

        buttonsStack.addArrangedSubview(secondaryButton)
        do {
            var configuration = UIButton.Configuration.gray()
            configuration.buttonSize = .large
            configuration.cornerStyle = .large
            secondaryButton.configuration = configuration
        }
        secondaryButton.addTarget(self, action: #selector(secondaryButtonTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
        
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.rightAnchor.constraint(equalTo: view.rightAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scrollView.leftAnchor.constraint(equalTo: view.leftAnchor),

            contentView.widthAnchor.constraint(equalTo: view.widthAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.rightAnchor.constraint(equalTo: scrollView.rightAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.leftAnchor.constraint(equalTo: scrollView.leftAnchor),

            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            titleLabel.bottomAnchor.constraint(equalTo: bubbleView.topAnchor, constant: -24),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),

            bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            bubbleView.bottomAnchor.constraint(equalTo: buttonsStack.topAnchor, constant: -24),
            bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),

            buttonsStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            buttonsStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            buttonsStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),

            bodyLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 12),
            bodyLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -16),
            bodyLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -12),
            bodyLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 16),

        ])
        
    }
    
    
}
