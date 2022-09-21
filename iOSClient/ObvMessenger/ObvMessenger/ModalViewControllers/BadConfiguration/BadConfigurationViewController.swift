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

class BadConfigurationViewController: UIViewController {

    private var timerForRepeatingConfigurationCheck: Timer?
    private let configChecker = DeviceConfigurationChecker()
    
    // Views
    
    @IBOutlet weak var badBackgroundRefreshStatusTitleLabel: UILabel!
    @IBOutlet weak var badBackgroundRefreshStatusExplanationLabel: UILabel!
    @IBOutlet weak var badBackgroundRefreshStatusButton: ObvButtonBorderless!
    @IBOutlet weak var problemTitleLabel: UILabel!
    @IBOutlet weak var solutionTitleLabel: UILabel!
    @IBOutlet weak var badBackgroundRefreshStatusSolution: UILabel!
    @IBOutlet weak var roundedRectView: ObvRoundedRectView!
    
}


// MARK: - View Controller lifecycle

extension BadConfigurationViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureViews()
        configureNavigationController()
        setTexts()
    }
    
    
    private func configureViews() {
        badBackgroundRefreshStatusTitleLabel.textColor = AppTheme.shared.colorScheme.label
        badBackgroundRefreshStatusExplanationLabel.textColor = AppTheme.shared.colorScheme.secondaryLabel
        problemTitleLabel.textColor = AppTheme.shared.colorScheme.label
        solutionTitleLabel.textColor = AppTheme.shared.colorScheme.label
        badBackgroundRefreshStatusSolution.textColor = AppTheme.shared.colorScheme.secondaryLabel
        roundedRectView.backgroundColor = AppTheme.shared.colorScheme.secondarySystemBackground
        view.backgroundColor = AppTheme.shared.colorScheme.systemBackground
    }
    
    private func configureNavigationController() {
        self.title = Strings.title
        navigationController?.navigationBar.prefersLargeTitles = true
        extendedLayoutIncludesOpaqueBars = true
    }
    
    private func setTexts() {
        badBackgroundRefreshStatusTitleLabel.text = Strings.badBackgroundRefreshStatus.title
        badBackgroundRefreshStatusExplanationLabel.text = Strings.badBackgroundRefreshStatus.explanation
        badBackgroundRefreshStatusButton.setTitle(Strings.badBackgroundRefreshStatus.buttonTitle, for: .normal)
        badBackgroundRefreshStatusSolution.text = Strings.badBackgroundRefreshStatus.solution
        problemTitleLabel.text = Strings.problemTitle
        solutionTitleLabel.text = Strings.solutionTitle
    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        timerForRepeatingConfigurationCheck = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            assert(Thread.isMainThread)
            if self?.configChecker.currentConfigurationIsValid(application: UIApplication.shared) == true {
                timer.invalidate()
                self?.dismiss(animated: true)
            }
        }
        
    }
    
}


// MARK: - Reacting to user inputs

extension BadConfigurationViewController {
    
    @IBAction func badBackgroundRefreshStatutButtonTapped(_ sender: Any) {
        
        if let appSettings = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(appSettings, options: [:])
        }

        
    }
    
}
