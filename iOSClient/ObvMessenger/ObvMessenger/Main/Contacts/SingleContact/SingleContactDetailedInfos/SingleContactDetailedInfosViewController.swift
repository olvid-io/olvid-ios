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
import ObvUI

class SingleContactDetailedInfosViewController: UIViewController {

    private let persistedObvContactIdentity: PersistedObvContactIdentity
    
    private let scrollView = UIScrollView()
    private let mainStackView = UIStackView()
    private let obvEngine: ObvEngine
    
    init(persistedObvContactIdentity: PersistedObvContactIdentity, obvEngine: ObvEngine) {
        self.persistedObvContactIdentity = persistedObvContactIdentity
        self.obvEngine = obvEngine
        super.init(nibName: nil, bundle: nil)
    }
    
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = AppTheme.shared.colorScheme.systemBackground
        scrollView.alwaysBounceHorizontal = false
        scrollView.isScrollEnabled = true
        self.view.addSubview(scrollView)
        
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        mainStackView.axis = .vertical
        mainStackView.alignment = .leading
        mainStackView.spacing = 8
        scrollView.addSubview(mainStackView)
        
        addTitleAndValueLabels(title: Strings.customDisplayName, value: persistedObvContactIdentity.customDisplayName ?? CommonString.Word.None)
        addTitleAndValueLabels(title: Strings.fullDisplayName, value: persistedObvContactIdentity.fullDisplayName)
        addTitleAndValueLabels(title: CommonString.Word.Identity, value: persistedObvContactIdentity.cryptoId.getIdentity().hexString())
        
        // Get the number of known devices for this contact
        if let ownedIdentity = persistedObvContactIdentity.ownedIdentity {
            let allContactDeviceIdentifiers: Set<Data>
            let contactDevicesIdentifiersWithChannel: Set<Data>
            let contactDeviceIdentifiersWithChannelCreation: Set<Data>
            do {
                allContactDeviceIdentifiers = try obvEngine.getContactDeviceIdentifiersOfContactIdentity(with: persistedObvContactIdentity.cryptoId, ofOwnedIdentityWith: ownedIdentity.cryptoId)
                let contactDevicesWithChannel = try obvEngine.getAllObliviousChannelsEstablishedWithContactIdentity(with: persistedObvContactIdentity.cryptoId, ofOwnedIdentyWith: ownedIdentity.cryptoId)
                contactDevicesIdentifiersWithChannel = Set(contactDevicesWithChannel.map({ $0.identifier }))
                contactDeviceIdentifiersWithChannelCreation = try obvEngine.getContactDeviceIdentifiersForWhichAChannelCreationProtocolExists(with: persistedObvContactIdentity.cryptoId, ofOwnedIdentityWith: ownedIdentity.cryptoId)
            } catch {
                assertionFailure()
                return
            }
            let values: [String] = allContactDeviceIdentifiers.map({
                let deviceName = String($0.hexString().prefix(16))
                let status: String
                if contactDevicesIdentifiersWithChannel.contains($0) {
                    status = "✔︎"
                } else if contactDeviceIdentifiersWithChannelCreation.contains($0) {
                    status = "⚙︎"
                } else {
                    status = "⨉"
                }
                return [status, deviceName].joined(separator: " ")
            })
            addTitleAndValuesLabels(title: CommonString.Word.Devices, values: values)
        }

        setupConstraints()
        
    }
    
    
    private func addTitleAndValueLabels(title: String, value: String) {
        let titleLabel = UILabel()
        titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        titleLabel.textColor = AppTheme.shared.colorScheme.label
        titleLabel.text = title
        mainStackView.addArrangedSubview(titleLabel)
        
        let valueLabel = UILabel()
        valueLabel.font = UIFont.preferredFont(forTextStyle: .body)
        valueLabel.numberOfLines = 0
        valueLabel.textColor = AppTheme.shared.colorScheme.secondaryLabel
        valueLabel.text = value
        mainStackView.addArrangedSubview(valueLabel)
    }
    
    private func addTitleAndValuesLabels(title: String, values: [String]) {
        let titleLabel = UILabel()
        titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        titleLabel.textColor = AppTheme.shared.colorScheme.label
        titleLabel.text = title
        mainStackView.addArrangedSubview(titleLabel)
        
        for value in values {
            let valueLabel = UILabel()
            valueLabel.font = UIFont.preferredFont(forTextStyle: .body)
            valueLabel.numberOfLines = 0
            valueLabel.textColor = AppTheme.shared.colorScheme.secondaryLabel
            valueLabel.text = value
            mainStackView.addArrangedSubview(valueLabel)
        }
    }

    
    
    private func setupConstraints() {
        
        let constraints = [
            scrollView.topAnchor.constraint(equalTo: self.view.topAnchor, constant: 0),
            scrollView.rightAnchor.constraint(equalTo: self.view.rightAnchor, constant: 0),
            scrollView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor, constant: 0),
            scrollView.leftAnchor.constraint(equalTo: self.view.leftAnchor, constant: 0),
            mainStackView.widthAnchor.constraint(equalTo: self.view.widthAnchor, constant: -32),
            mainStackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            mainStackView.rightAnchor.constraint(equalTo: scrollView.rightAnchor, constant: 16),
            mainStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 16),
            mainStackView.leftAnchor.constraint(equalTo: scrollView.leftAnchor, constant: 16),
        ]
        NSLayoutConstraint.activate(constraints)
        
    }

}

private extension SingleContactDetailedInfosViewController {
    
    private struct Strings {
        
        static let customDisplayName = NSLocalizedString("Custom Display Name", comment: "")
        static let fullDisplayName = NSLocalizedString("Full Display Name", comment: "")

    }

}
