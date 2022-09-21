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
import OlvidUtils
import CoreDataStack

final class InitializerViewController: UIViewController {
    
    private var activityIndicatorView: UIActivityIndicatorView!
    private let exportRunningLogButton = UIButton()
    private var progressView: UIProgressView?
    private var observationTokens = [NSObjectProtocol]()

    override var preferredStatusBarStyle: UIStatusBarStyle {
        if view?.window?.isKeyWindow == true {
            return .lightContent
        } else {
            return .default
        }
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        activityIndicatorView = UIActivityIndicatorView(style: .large)
        
        let launchScreenStoryBoard = UIStoryboard(name: "LaunchScreen", bundle: nil)
        guard let launchViewController = launchScreenStoryBoard.instantiateInitialViewController() else { assertionFailure(); return }
        self.view.addSubview(launchViewController.view)
        launchViewController.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.pinAllSidesToSides(of: launchViewController.view)
        
        self.view.addSubview(activityIndicatorView)
        activityIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        activityIndicatorView.hidesWhenStopped = true
        activityIndicatorView.color = .white
        
        self.view.addSubview(exportRunningLogButton)
        exportRunningLogButton.translatesAutoresizingMaskIntoConstraints = false
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 30.0, weight: .bold)
        let image = UIImage(systemIcon: .squareAndArrowUp, withConfiguration: symbolConfiguration)
        exportRunningLogButton.setImage(image, for: .normal)
        exportRunningLogButton.addTarget(self, action: #selector(exportRunningLogButtonTapped), for: .touchUpInside)
        exportRunningLogButton.alpha = 0

        setupConstraints()
        
        observeDatabaseMigrationNotifications()
        showSpinnerAfterCertainTime()
        
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

    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        presentedViewController?.dismiss(animated: true)
    }

    
    // MARK: - Spinner and export logs
    
    private var neverShowActivityIndicator = false

    private func showSpinnerAfterCertainTime() {
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(45)) { [weak self] in
            guard let _self = self else { return }
            guard !_self.neverShowActivityIndicator else { return }
            UIView.animate(withDuration: 0.3) {
                self?.activityIndicatorView.startAnimating()
                self?.exportRunningLogButton.alpha = 1
            }
        }
    }
    
    
    /// If the app is initialized successfully, we don't need to show the spiner nor the export log button ever again.
    func appInitializationSucceeded() {
        neverShowActivityIndicator = true
        activityIndicatorView.stopAnimating()
        exportRunningLogButton.alpha = 0
        progressView?.isHidden = true
    }

    
    @objc private func exportRunningLogButtonTapped() {
        ObvMessengerInternalNotification.requestRunningLog { [weak self] runningLog in
            DispatchQueue.main.async {
                self?.showReceivedRunningLog(runningLog)
            }
        }
        .postOnDispatchQueue()
    }
    
    
    private func showReceivedRunningLog(_ runningLog: RunningLogError) {
        assert(Thread.isMainThread)
        let vc = InitializationFailureViewController()
        vc.error = runningLog
        vc.category = .initializationTakesTooLong
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }
    
    // MARK: - Progress bar for migrations

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
        progressView?.isHidden = false
        progressView?.observedProgress = migrationProgress
    }
         
}
