/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import Combine
import ObvUICoreData


/// This view is shown on top of the keyboard when the users performs a search in the single discussion view.
@MainActor
final class SingleDiscussionSearchView: UIInputView {

    private let stack = UIStackView()
    private let label = UILabel()
    private let upButton = UIButton(type: .system)
    private let downButton = UIButton(type: .system)
    private let backgroundBlurVisualEffect = UIBlurEffect(style: .regular)
    private lazy var backgroundVisualEffectView = UIVisualEffectView(effect: backgroundBlurVisualEffect)
    let mainContentView = UIView()
    private var cancellables = [AnyCancellable]()

    @Published private var currentSearchResults: [TypeSafeManagedObjectID<PersistedMessage>]?
    @Published private(set) var searchResultToScrollTo: TypeSafeManagedObjectID<PersistedMessage>?

    /// Publishes the latest frame of the main content view. This is used by the new single discussion view controller to adapt the insets of the collection view of messages.
    @Published private(set) var mainContentViewFrame: CGRect = .zero

    deinit {
        cancellables.forEach({ $0.cancel() })
    }
    
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateMainContentViewFramePublisher()
    }

    
    /// Called from ``func layoutSubviews()``
    private func updateMainContentViewFramePublisher() {
        if let superview {
            let mainContentViewBounds = mainContentView.bounds
            let newMainContentViewFrame = superview.convert(mainContentViewBounds, from: mainContentView)
            if self.mainContentViewFrame != newMainContentViewFrame {
                self.mainContentViewFrame = newMainContentViewFrame
            }
        }
    }

    func setResultsPublisher<T: Publisher<[TypeSafeManagedObjectID<PersistedMessage>]?, Never>>(resultsPublisher: T) {
        cancellables.forEach({ $0.cancel() })
        continuouslyUpdateLabel()
        resultsPublisher
            .receive(on: OperationQueue.main)
            .sink { [weak self] results in
                guard let self else { return }
                if self.currentSearchResults != results {
                    self.currentSearchResults = results
                }
                if self.searchResultToScrollTo != results?.last {
                    self.searchResultToScrollTo = results?.last
                }
            }
            .store(in: &cancellables)
    }
    
    
    private func continuouslyUpdateLabel() {
        $searchResultToScrollTo
            .receive(on: OperationQueue.main)
            .sink { [weak self] messageObjectID in
                guard let self else { return }
                if let messageObjectID, let numberOfIndexes = currentSearchResults?.count, let currentIndex = currentSearchResults?.firstIndex(of: messageObjectID) {
                    label.text = String.localizedStringWithFormat(NSLocalizedString("RESULT_NUMBER_%d_OF_%d", comment: ""), numberOfIndexes - currentIndex, numberOfIndexes)
                } else if currentSearchResults?.isEmpty == true {
                    label.text = NSLocalizedString("SEARCH_RETURNED_NO_RESULT", comment: "")
                } else {
                    label.text = nil
                }
            }
            .store(in: &cancellables)
        $currentSearchResults
            .receive(on: OperationQueue.main)
            .sink { [weak self] results in
                guard let self else { return }
                if let results {
                    if results.isEmpty {
                        label.text = NSLocalizedString("SEARCH_RETURNED_NO_RESULT", comment: "")
                    } else {
                        label.text = String.localizedStringWithFormat(NSLocalizedString("RESULT_NUMBER_%d_OF_%d", comment: ""), 1, results.count)
                    }
                } else {
                    label.text = nil
                }
            }
            .store(in: &cancellables)
    }

    
    @objc private func upButtonTapped() {
        findNext(upButton)
    }

    
    @objc private func downButtonTapped() {
        findPrevious(downButton)
    }
    
    
    /// This method is either called because the user tapped/clicked on the "up" button, or because she type the default keyboard shortcut for "Find next".
    ///
    /// Note that when the user types the default keyboard shortcut, it is the ``MainFlowViewController.findNext(_:)`` that gets called by the system. We manually call
    /// the ``MainFlowViewController.findNext(_:)`` method, which calls this method.
    override func findNext(_ sender: Any?) {
        guard let searchResultToScrollTo, let currentSearchResults else { return }
        guard let currentIndex = currentSearchResults.firstIndex(of: searchResultToScrollTo) else { return }
        let nextIndex = (currentIndex - 1)%currentSearchResults.count
        self.searchResultToScrollTo = currentSearchResults[nextIndex >= 0 ? nextIndex : nextIndex + currentSearchResults.count]
    }

    
    /// This method is either called because the user tapped/clicked on the "up" button, or because she type the default keyboard shortcut for "Find previous".
    ///
    /// Note that when the user types the default keyboard shortcut, it is the ``MainFlowViewController.findPrevious(_:)`` that gets called by the system. We manually call
    /// the ``MainFlowViewController.findPrevious(_:)`` method, which calls this method.
    override func findPrevious(_ sender: Any?) {
        guard let searchResultToScrollTo, let currentSearchResults else { return }
        guard let currentIndex = currentSearchResults.firstIndex(of: searchResultToScrollTo) else { return }
        let nextIndex = (currentIndex + 1)%currentSearchResults.count
        self.searchResultToScrollTo = currentSearchResults[nextIndex >= 0 ? nextIndex : nextIndex + currentSearchResults.count]
    }

    
    override init(frame: CGRect, inputViewStyle: UIInputView.Style) {
        super.init(frame: frame, inputViewStyle: inputViewStyle)
        
        self.backgroundColor = .clear
        
        self.addSubview(backgroundVisualEffectView)
        backgroundVisualEffectView.translatesAutoresizingMaskIntoConstraints = false
        backgroundVisualEffectView.contentView.isUserInteractionEnabled = false

        self.addSubview(mainContentView)
        mainContentView.translatesAutoresizingMaskIntoConstraints = false
        mainContentView.isUserInteractionEnabled = true
        mainContentView.backgroundColor = .clear
        
        mainContentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.backgroundColor = .clear
        stack.alignment = .center
        
        stack.addArrangedSubview(label)
        label.backgroundColor = .clear
        label.text = "Test of test"
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel

        stack.addArrangedSubview(upButton)
        upButton.translatesAutoresizingMaskIntoConstraints = false
        upButton.setImage(.init(systemIcon: .chevronUp), for: .normal)
        upButton.backgroundColor = .clear
        upButton.addTarget(self, action: #selector(upButtonTapped), for: .touchUpInside)

        stack.addArrangedSubview(downButton)
        downButton.translatesAutoresizingMaskIntoConstraints = false
        downButton.setImage(.init(systemIcon: .chevronDown), for: .normal)
        downButton.backgroundColor = .clear
        downButton.addTarget(self, action: #selector(downButtonTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            
            backgroundVisualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundVisualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundVisualEffectView.topAnchor.constraint(equalTo: topAnchor),
            backgroundVisualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            // The mainContentView bottom anchor is constrained to the view.keyboardLayoutGuide.topAnchor
            mainContentView.topAnchor.constraint(equalTo: self.topAnchor),
            mainContentView.trailingAnchor.constraint(equalTo: self.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            mainContentView.leadingAnchor.constraint(equalTo: self.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            
            stack.topAnchor.constraint(equalTo: mainContentView.topAnchor),
            stack.trailingAnchor.constraint(equalTo: mainContentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: mainContentView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: mainContentView.leadingAnchor),
            
            stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            
            downButton.widthAnchor.constraint(equalTo: downButton.heightAnchor, multiplier: 1.0),
            downButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            upButton.widthAnchor.constraint(equalTo: upButton.heightAnchor, multiplier: 1.0),
            upButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
