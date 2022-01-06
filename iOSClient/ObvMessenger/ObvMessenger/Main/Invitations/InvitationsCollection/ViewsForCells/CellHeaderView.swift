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

final class CellHeaderView: UIView {

    static let nibName = "CellHeaderView"
    
    var title = "" { didSet { setTitleViewText(); setCircledText() } }
    var subtitle = "" { didSet { setSubtitleViewText() } }
    var details = "" { didSet { setDetailsTextViewText() } }
    var date: Date? { didSet { setDateLabelText() } }
    var identityColors: (background: UIColor, text: UIColor)? { didSet { setIdentityColors() } }

    // Views
    
    @IBOutlet weak var circlePlaceholder: UIView! { didSet { circlePlaceholder.backgroundColor = .clear }}
    @IBOutlet weak var titleLabel: UILabel! { didSet { titleLabel.textColor = AppTheme.shared.colorScheme.label } }
    @IBOutlet weak var subtitleLabel: UILabel! { didSet { subtitleLabel?.textColor = AppTheme.shared.colorScheme.secondaryLabel } }
    @IBOutlet weak var detailsLabel: UILabel! { didSet { detailsLabel?.textColor = AppTheme.shared.colorScheme.secondaryLabel } }
    @IBOutlet weak var dateLabel: UILabel! { didSet { dateLabel?.textColor = AppTheme.shared.colorScheme.tertiaryLabel } }
    @IBOutlet weak var titleStackView: UIStackView!
    private var chipsStack: UIStackView? = nil
    
    // Subviews set in awakeFromNib

    var circledInitials: CircledInitials!
    var leadingTextAnchor: NSLayoutXAxisAnchor!

    let dateFormater: DateFormatter = {
        let df = DateFormatter()
        df.doesRelativeDateFormatting = true
        df.dateStyle = .short
        df.timeStyle = .short
        df.locale = Locale.current
        return df
    }()

    
    func addChip(withText text: String) {
        let obvChipView = ObvChipLabel()
        obvChipView.chipColor = appTheme.colorScheme.systemFill
        obvChipView.text = text
        obvChipView.textColor = ObvChipLabel.defaultTextColor
        if let chipsStack = self.chipsStack {
            chipsStack.addArrangedSubview(obvChipView)
        } else {
            self.chipsStack = UIStackView(arrangedSubviews: [obvChipView])
            self.chipsStack?.spacing = 4
            if let titleStackView = self.titleStackView {
                titleStackView.addArrangedSubview(self.chipsStack!)
            }
        }
    }
    
    
    func prepareForReuse() {
        if let chipsStack = self.chipsStack {
            titleStackView.removeArrangedSubview(chipsStack)
            chipsStack.removeFromSuperview()
            self.setNeedsDisplay()
        }
        self.chipsStack = nil
    }
}

// MARK: - awakeFromNib

extension CellHeaderView {

    override func awakeFromNib() {
        super.awakeFromNib()
        translatesAutoresizingMaskIntoConstraints = false
        leadingTextAnchor = titleLabel.leadingAnchor
        instantiateAndPlaceCircledInitials()
        
        if let chipsStack = self.chipsStack {
            titleStackView.addArrangedSubview(chipsStack)
        }
    }

    private func instantiateAndPlaceCircledInitials() {
        
        circledInitials = (Bundle.main.loadNibNamed(CircledInitials.nibName, owner: nil, options: nil)!.first as! CircledInitials)
        circlePlaceholder.addSubview(circledInitials)
        circledInitials.topAnchor.constraint(equalTo: circlePlaceholder.topAnchor).isActive = true
        circledInitials.bottomAnchor.constraint(equalTo: circlePlaceholder.bottomAnchor).isActive = true
        circledInitials.leadingAnchor.constraint(equalTo: circlePlaceholder.leadingAnchor).isActive = true
        circledInitials.trailingAnchor.constraint(equalTo: circlePlaceholder.trailingAnchor).isActive = true

    }
 
}

// MARK: - Setting the view's texts and sizes

extension CellHeaderView {
        
    private func setTitleViewText() {
        titleLabel.text = title
    }
    
    private func setSubtitleViewText() {
        subtitleLabel.text = subtitle
    }
    
    private func setDetailsTextViewText() {
        detailsLabel.text = details
    }
    
    private func setDateLabelText() {
        if let date = date {
            dateLabel.text = dateFormater.string(from: date)
        }
    }
    
}

// MARK: - Drawing the circle

extension CellHeaderView {
    
    private func setCircledText() {
        circledInitials.showCircledText(from: title)
    }
    
    private func setIdentityColors() {
        circledInitials.identityColors = identityColors
    }

}
