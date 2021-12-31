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
import LocalAuthentication
import ObvEngine



final class PrivacyTableViewController: UITableViewController {

    let ownedCryptoId: ObvCryptoId
    
    private var titleForLocalAuthentication: String
    private var explanationForLocalAuthentication: String
    
    let dateComponentsFormatter: DateComponentsFormatter = {
        let df = DateComponentsFormatter()
        df.allowedUnits = [.hour, .minute, .second]
        df.unitsStyle = .full
        return df
    }()
    
    init(ownedCryptoId: ObvCryptoId) {
        self.ownedCryptoId = ownedCryptoId
        // Check for available authentication methods
        var error: NSError?
        let laContext = LAContext()
        // We first check whether Touch ID or Face ID is unavailable or not enrolled
        let userIsEnrolledWithBiometrics = laContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        if userIsEnrolledWithBiometrics {
            // Distinguish Touch ID from FaceID
            laContext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
            switch laContext.biometryType {
            case .none:
                self.titleForLocalAuthentication = Strings.loginWith.passcode
                self.explanationForLocalAuthentication = Strings.explanationLoginWith.passcode
            case .touchID:
                self.titleForLocalAuthentication = Strings.loginWith.touchID
                self.explanationForLocalAuthentication = Strings.explanationLoginWith.touchID
            case .faceID:
                self.titleForLocalAuthentication = Strings.loginWith.faceID
                self.explanationForLocalAuthentication = Strings.explanationLoginWith.faceID
            @unknown default:
                fatalError()
            }
        } else {
            self.titleForLocalAuthentication = Strings.loginWith.passcode
            self.explanationForLocalAuthentication = Strings.explanationLoginWith.passcode
        }
        super.init(style: .grouped)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = CommonString.Word.Privacy
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        ObvNewFeatures.PrivacySetting.markSeenByUser(to: true)
        ObvMessengerInternalNotification.badgesNeedToBeUpdated(ownedCryptoId: ownedCryptoId).postOnDispatchQueue()
    }
    
    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return ObvMessengerSettings.Privacy.lockScreen ? 3 : 2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return 1
        case 1:
            return 1
        case 2:
            return ObvMessengerSettings.Privacy.gracePeriods.count
        default:
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UITableViewCell
        switch indexPath.section {
        case 0:
            let _cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            _cell.textLabel?.text = Strings.notificationContentPrivacyStyle.title
            switch ObvMessengerSettings.Privacy.hideNotificationContent {
            case .no:
                _cell.detailTextLabel?.text = CommonString.Word.No
            case .partially:
                _cell.detailTextLabel?.text = CommonString.Word.Partially
            case .completely:
                _cell.detailTextLabel?.text = CommonString.Word.Completely
            }
            _cell.accessoryType = .disclosureIndicator
            cell = _cell
        case 1:
            switch indexPath.row {
            case 0:
                let _cell = ObvTitleAndSwitchTableViewCell(reuseIdentifier: "LockScreenCell")
                _cell.title = titleForLocalAuthentication
                _cell.switchIsOn = ObvMessengerSettings.Privacy.lockScreen
                _cell.blockOnSwitchValueChanged = { [weak self] (value) in self?.lockScreenChangedTo(value)  }
                cell = _cell
            default:
                assertionFailure()
                cell = UITableViewCell()
            }
        case 2:
            let _cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            let gracePeriod = ObvMessengerSettings.Privacy.gracePeriods[indexPath.row]
            if gracePeriod == 0 {
                _cell.textLabel?.text = CommonString.Word.Immediately
            } else {
                _cell.textLabel?.text = CommonString.Word.After + " " + dateComponentsFormatter.string(from: gracePeriod)!
            }
            if ObvMessengerSettings.Privacy.gracePeriods[indexPath.row] == ObvMessengerSettings.Privacy.lockScreenGracePeriod {
                _cell.accessoryType = .checkmark
            }
            cell = _cell
        default:
            cell = UITableViewCell()
        }
        cell.selectionStyle = .none
        return cell
    }

    
    private func lockScreenChangedTo(_ value: Bool) {
        guard ObvMessengerSettings.Privacy.lockScreen != value else { return }
        let laContext = LAContext()
        var error: NSError?
        laContext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        laContext.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: Strings.changingSettingRequiresAuthentication) { (success, error) in
            DispatchQueue.main.async { [weak self] in
                if success {
                    ObvMessengerSettings.Privacy.lockScreen = value
                    self?.tableView.reloadData()
                } else {
                    self?.tableView.reloadRows(at: [IndexPath(row: 0, section: 1)], with: .automatic)
                    if (error as NSError?)?.code == LAError.Code.passcodeNotSet.rawValue {
                        let alert = UIAlertController(title: CommonString.Word.Oups,
                                                      message: Strings.passcodeNotSetAlert.message,
                                                      preferredStyle: .alert)
                        let abortAction = UIAlertAction(title: CommonString.Word.Abort, style: .cancel, handler: nil)
                        alert.addAction(abortAction)
                        self?.present(alert, animated: true)
                    }
                }
            }
        }

    }
    
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch indexPath.section {
        case 0:
            guard indexPath.row == 0 else { return }
            let vc = NotificationContentPrivacyStyleChooserTableViewController()
            self.navigationController?.pushViewController(vc, animated: true)
        case 1:
            return
        case 2:
            ObvMessengerSettings.Privacy.lockScreenGracePeriod = ObvMessengerSettings.Privacy.gracePeriods[indexPath.row]
            tableView.reloadData()
        default:
            return
        }
    }
    
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return CommonString.Word.Notifications
        case 1:
            return Strings.screenLock
        default:
            return nil
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0:
            switch ObvMessengerSettings.Privacy.hideNotificationContent {
            case .no: return PrivacyTableViewController.Strings.notificationContentPrivacyStyle.explanation.whenNo
            case .partially: return PrivacyTableViewController.Strings.notificationContentPrivacyStyle.explanation.whenPartially
            case .completely: return PrivacyTableViewController.Strings.notificationContentPrivacyStyle.explanation.whenCompletely
            }
        case 1:
            return self.explanationForLocalAuthentication
        default:
            return nil
        }
    }
        
}
