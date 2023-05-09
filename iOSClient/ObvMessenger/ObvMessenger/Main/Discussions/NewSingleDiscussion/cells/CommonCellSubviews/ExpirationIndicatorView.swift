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


final class ExpirationIndicatorView: UIView {
    
    enum Side {
        case leading
        case trailing
    }
    
    func configure(readingRequiresUserAction: Bool, readOnce: Bool, scheduledVisibilityDestructionDate: Date?, scheduledExistenceDestructionDate: Date?) {
        self.readingRequiresUserAction = readingRequiresUserAction
        self.readOnce = readOnce
        let now = Date()
        let shouldConsiderScheduledVisibilityDestructionDate = scheduledVisibilityDestructionDate != nil && scheduledVisibilityDestructionDate! > now
        self.scheduledVisibilityDestructionDate = shouldConsiderScheduledVisibilityDestructionDate ? scheduledVisibilityDestructionDate : nil
        let shouldConsiderScheduledExistenceDestructionDate = scheduledExistenceDestructionDate != nil && scheduledExistenceDestructionDate! > now
        self.scheduledExistenceDestructionDate = shouldConsiderScheduledExistenceDestructionDate ? scheduledExistenceDestructionDate : nil
        guard shouldShow else {
            hide()
            return
        }
        configureTextColor()
        configureImage()
        refreshCellCountdown()
        show()
    }
    
    
    func hide() {
        label.text = " "
        imageView.image = nil
        imageView.isHidden = true
        label.isHidden = true
    }
    
    
    private func show() {
        imageView.isHidden = false
    }
    
    
    private var shouldShow: Bool {
        if readingRequiresUserAction {
            return scheduledExistenceDestructionDate != nil
        } else {
            return readOnce || scheduledVisibilityDestructionDate != nil || scheduledExistenceDestructionDate != nil
        }
    }
    
    
    private func configureTextColor() {
        assert(shouldShow)
        let color: UIColor
        if readOnce {
            color = .red
        } else {
            guard let scheduledDestructionDate = Date.minOrNil(scheduledVisibilityDestructionDate, scheduledExistenceDestructionDate) else { assertionFailure(); return }
            let timeIntervalUntilDestruction = max(0, scheduledDestructionDate.timeIntervalSinceNow)
            if timeIntervalUntilDestruction <= MessageCellConstants.TimeIntervalForMessageDestruction.limitForRed {
                color = .red
            } else if timeIntervalUntilDestruction <= MessageCellConstants.TimeIntervalForMessageDestruction.limitForYellow {
                color = .systemOrange
            } else if timeIntervalUntilDestruction <= MessageCellConstants.TimeIntervalForMessageDestruction.limitForDarkGray {
                color = .label
            } else {
                color = .secondaryLabel
            }
        }
        label.textColor = color
        imageView.tintColor = color
    }

    
    private func configureImage() {
        assert(shouldShow)
        let imageSystemIcon: SystemIcon?
        if readOnce && !readingRequiresUserAction {
            imageSystemIcon = .flameFill
        } else {
            switch (scheduledVisibilityDestructionDate, scheduledExistenceDestructionDate) {
            case (nil, nil):
                imageSystemIcon = nil
            case (nil, .some):
                imageSystemIcon = .timer
            case (.some, nil):
                imageSystemIcon = .eyes
            case (.some(let v), .some(let e)):
                imageSystemIcon = (v < e) ? .eyes : .timer
            }
        }
        guard let imageSystemIcon = imageSystemIcon else { imageView.image = nil; return }
        let configuration = UIImage.SymbolConfiguration(pointSize: fontSize)
        let image = UIImage(systemIcon: imageSystemIcon, withConfiguration: configuration)
        imageView.image = image
    }
    

    func refreshCellCountdown() {
        guard shouldShow else { hide(); return }
        configureTextColor()
        let timeIntervalUntilDestruction: TimeInterval?
        switch (scheduledVisibilityDestructionDate, scheduledExistenceDestructionDate) {
        case (nil, nil):
            timeIntervalUntilDestruction = nil
        case (nil, .some(let date)), (.some(let date), nil):
            timeIntervalUntilDestruction = max(0, date.timeIntervalSinceNow)
        case (.some(let v), .some(let e)):
            timeIntervalUntilDestruction = max(0, min(v.timeIntervalSinceNow, e.timeIntervalSinceNow))
        }
        if let timeIntervalUntilDestruction = timeIntervalUntilDestruction {
            self.text = durationFormatter.string(from: timeIntervalUntilDestruction)
        } else {
            self.text = nil
        }
    }
    
    
    private var text: String? {
        get { label.text }
        set {
            label.isHidden = (newValue == nil)
            widthContraint?.isActive = (newValue != nil)
            label.text = newValue
        }
    }
    
    private let imageView = UIImageView()
    private let label = UILabel()
    private let fontSize = CGFloat(12)
    private var widthContraint: NSLayoutConstraint?
    private let durationFormatter = DurationFormatter()
    
    private var readingRequiresUserAction = false
    private var readOnce = false
    private var scheduledVisibilityDestructionDate: Date?
    private var scheduledExistenceDestructionDate: Date?

    init() {
        super.init(frame: .zero)
        setupInternalViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }


    private func setupInternalViews() {
        
        addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true

        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: fontSize)
        label.isHidden = true
        label.textAlignment = .center

        NSLayoutConstraint.activate([
            self.heightAnchor.constraint(equalToConstant: MessageCellConstants.expirationIndicatorViewHeight),
            imageView.topAnchor.constraint(equalTo: self.topAnchor),
            imageView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: label.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            label.leadingAnchor.constraint(equalTo: self.leadingAnchor),
        ])

        // This constraint is activated when there is a non nil text.
        // This prevents animation glitches when the timer changes value.
        // The constant is an heuristic.
        widthContraint = self.widthAnchor.constraint(greaterThanOrEqualToConstant: fontSize*2.5)
    }
    
}


private extension Date {
    
    static func minOrNil(_ t1: Date?, _ t2: Date?) -> Date? {
        switch (t1, t2) {
        case (nil, nil):
            return nil
        case (.some(let t), nil), (nil, .some(let t)):
            return t
        case (.some(let t1), .some(let t2)):
            return min(t1, t2)
        }
    }
    
}
