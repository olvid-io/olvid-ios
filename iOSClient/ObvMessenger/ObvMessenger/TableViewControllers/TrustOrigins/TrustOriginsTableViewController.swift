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


class TrustOriginsTableViewController: UITableViewController {

    private let trustOrigins: [ObvTrustOrigin]
    
    private let dateFormater: DateFormatter = {
        let df = DateFormatter()
        df.doesRelativeDateFormatting = true
        df.dateStyle = .medium
        df.timeStyle = .medium
        df.locale = Locale.current
        return df
    }()
    
    var cellBackgroundColor: UIColor?
    
    // Other variables
    
    private var kvObservations = [NSKeyValueObservation]()
    private var tableViewHeightAnchorConstraint: NSLayoutConstraint?

    // Initializers
    
    init(trustOrigins: [ObvTrustOrigin]) {
        self.trustOrigins = trustOrigins
        super.init(style: .plain)
    }
    
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


// MARK: - View Controller Lifecycle

extension TrustOriginsTableViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()

        registerTableViewCell()
        configureTheTableView()
        tableView.reloadData()

    }
    
    
    private func configureTheTableView() {
        self.clearsSelectionOnViewWillAppear = true
        self.tableView?.allowsSelection = false
        self.tableView?.refreshControl = nil
        self.tableView?.rowHeight = UITableView.automaticDimension
        self.tableView?.estimatedRowHeight = UITableView.automaticDimension
    }

    
    private func registerTableViewCell() {
        let nib = UINib(nibName: ObvSimpleTableViewCell.nibName, bundle: nil)
        self.tableView?.register(nib, forCellReuseIdentifier: ObvSimpleTableViewCell.identifier)
    }

}


// MARK: - Table view data source

extension TrustOriginsTableViewController {
    
    // MARK: - Table view data source

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return trustOrigins.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ObvSimpleTableViewCell.identifier, for: indexPath) as! ObvSimpleTableViewCell
        
        if let cellBackgroundColor = self.cellBackgroundColor {
            cell.backgroundColor = cellBackgroundColor
        }
        
        let trustOrigin = self.trustOrigins[indexPath.row]
        
        switch trustOrigin {
        case .direct(timestamp: let timestamp):
            cell.titleLabel.text = Strings.TrustOrigin.direct
            cell.subtitleLabel.text = dateFormater.string(from: timestamp)
        case .introduction(timestamp: let timestamp, mediator: let mediator):
            if let mediator = mediator {
                cell.titleLabel.text = Strings.TrustOrigin.mediator(mediator.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full))
            } else {
                cell.titleLabel.text = Strings.TrustOrigin.mediatorDeleted
            }
            cell.subtitleLabel.text = dateFormater.string(from: timestamp)
        case .group(timestamp: let timestamp, groupOwner: _):
            cell.titleLabel.text = Strings.TrustOrigin.group
            cell.subtitleLabel.text = dateFormater.string(from: timestamp)
        case .keycloak(timestamp: let timestamp, keycloakServer: let keycloakServer):
            cell.titleLabel.text = Strings.TrustOrigin.keycloak(keycloakServer.relativeString)
            cell.subtitleLabel.text = dateFormater.string(from: timestamp)
        }
        return cell
    }


}


// MARK: - Other methods

extension TrustOriginsTableViewController {
    
    func constraintHeightToContentHeight(blockOnNewHeight: @escaping (CGFloat) -> Void) {
        self.tableView.isScrollEnabled = false
        self.view.layoutIfNeeded()
        let kvObservation = self.tableView.observe(\.contentSize) { [weak self] (object, change) in
            guard let _self = self else { return }
            _self.tableViewHeightAnchorConstraint?.isActive = false
            _self.tableViewHeightAnchorConstraint = _self.view.heightAnchor.constraint(equalToConstant: _self.tableView.contentSize.height)
            _self.tableViewHeightAnchorConstraint?.isActive = true
            blockOnNewHeight(_self.tableView.contentSize.height)
            _self.view.layoutIfNeeded()
        }
        kvObservations.append(kvObservation)
    }

}
