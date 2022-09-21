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


/// This `UICollectionViewCell` subclass is used when the collection view tries to refresh a cell for a message that was just deleted.
///
/// In that case, the message is not available, making it impossible for the collection view to properly configure the message cell.
/// We used to return `nil` in that case, which is a bad strategy since this crashes the entire app. Instead, we now return an `InvisibleCell` that is very likely
/// to be deleted by the collection view soon after it is displayed.
@available(iOS 14.0, *)
final class InvisibleCell: UICollectionViewCell {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    
    override func updateConfiguration(using state: UICellConfigurationState) {
        let content = InvisibleCellCustomContentConfiguration().updated(for: state)
        self.contentConfiguration = content
    }
 

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let newSize = systemLayoutSizeFitting(
            layoutAttributes.frame.size,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel)
        var newFrame = layoutAttributes.frame
        newFrame.size = newSize
        // We *must* create new layout attributes, otherwise, if the computed frame happens to be identical to the default one, the `shouldInvalidateLayout` method of the collection view layout is not called.
        let newLayoutAttributes = UICollectionViewLayoutAttributes(forCellWith: layoutAttributes.indexPath)
        newLayoutAttributes.frame = newFrame
        return newLayoutAttributes
    }

}


@available(iOS 14.0, *)
fileprivate struct InvisibleCellCustomContentConfiguration: UIContentConfiguration, Hashable {
    
    func makeContentView() -> UIView & UIContentView {
        return InvisibleCellContentView(configuration: self)
    }
    
    func updated(for state: UIConfigurationState) -> InvisibleCellCustomContentConfiguration {
        return self
    }
    
}


@available(iOS 14.0, *)
fileprivate final class InvisibleCellContentView: UIView, UIContentView {
    
    var configuration: UIContentConfiguration
    
    init(configuration: InvisibleCellCustomContentConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)
        setupInternalViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupInternalViews() {
        backgroundColor = .clear
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 0),
            heightAnchor.constraint(equalToConstant: 0),
        ])
    }
}
