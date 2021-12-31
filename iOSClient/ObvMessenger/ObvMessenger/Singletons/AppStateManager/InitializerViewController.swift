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
import OlvidUtils
import CoreDataStack

final class InitializerViewController: UIViewController {
    
    private var activityIndicatorView: UIActivityIndicatorView!
    private let exportRunningLogButton = UIButton()
    private var progressView: UIProgressView?
    private var observationTokens = [NSObjectProtocol]()

    var runningLog: RunningLogError?
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        if view?.window?.isKeyWindow == true {
            return .lightContent
        } else {
            return .default
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        if #available(iOS 13, *) {
            activityIndicatorView = UIActivityIndicatorView(style: .large)
        } else {
            activityIndicatorView = UIActivityIndicatorView(style: .whiteLarge)
        }
        
        let launchScreenStoryBoard = UIStoryboard(name: "LaunchScreen", bundle: nil)
        guard let launchViewController = launchScreenStoryBoard.instantiateInitialViewController() else { assertionFailure(); return }
        self.view.addSubview(launchViewController.view)
        self.view.pinAllSidesToSides(of: launchViewController.view)
        
        activityIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(3)) { [weak self] in
            self?.activityIndicatorView.startAnimating()
        }
        self.view.addSubview(activityIndicatorView)
        
        exportRunningLogButton.translatesAutoresizingMaskIntoConstraints = false
        exportRunningLogButton.setImage(UIImage.makeSystemImage(systemName: ObvSystemIcon.squareAndArrowUp.systemName, size: 30.0), for: .normal)
        exportRunningLogButton.addTarget(self, action: #selector(exportRunningLogButtonTapped), for: .touchUpInside)
        exportRunningLogButton.alpha = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(20)) { [weak self] in
            UIView.animate(withDuration: 0.3) {
                self?.exportRunningLogButton.alpha = 1
            }
        }
        self.view.addSubview(exportRunningLogButton)

        setupConstraints()
        observeDatabaseMigrationNotifications()
    }
    
    
    private func observeDatabaseMigrationNotifications() {
        observationTokens.append(DataMigrationManagerNotification.observeMigrationManagerWillMigrateStore(queue: .main) { [weak self] migrationProgress, storeName in
            self?.createOrUpdateProgressView(migrationProgress: migrationProgress)
        })
    }
    
    
    private func createOrUpdateProgressView(migrationProgress: Progress) {
        if progressView == nil {
            progressView = UIProgressView(progressViewStyle: .default)
            progressView!.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(progressView!)
            let constraints = [
                self.view.centerXAnchor.constraint(equalTo: progressView!.centerXAnchor),
                self.view.centerYAnchor.constraint(equalTo: progressView!.centerYAnchor, constant: -32),
                progressView!.widthAnchor.constraint(equalTo: self.view.widthAnchor, multiplier: 0.5),
            ]
            NSLayoutConstraint.activate(constraints)
        }
        progressView?.observedProgress = migrationProgress
    }
        
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        presentedViewController?.dismiss(animated: true)
    }
    
    private func setupConstraints() {
        let constraints = [
            self.view.centerXAnchor.constraint(equalTo: activityIndicatorView.centerXAnchor),
            self.view.centerYAnchor.constraint(equalTo: activityIndicatorView.centerYAnchor),
            self.view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: exportRunningLogButton.trailingAnchor, constant: 16),
            self.view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: exportRunningLogButton.bottomAnchor, constant: 16),
        ]
        NSLayoutConstraint.activate(constraints)
    }
 
    
    @objc private func exportRunningLogButtonTapped() {
        guard let runningLog = self.runningLog else { assertionFailure(); return }
        let vc = InitializationFailureViewController()
        vc.error = runningLog
        vc.category = .initializationTakesTooLong
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }
    
}
