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
  

import Foundation
import UIKit
import SwiftUI

private let kDiscussionsFilterCellHeight = CGFloat(86.5)

@available(iOS 16.0, *)
final class DiscussionsFilterCell: UICollectionViewListCell {
    
    private weak var delegate: ObvSegmentedControlTableViewCellDelegate?
    private var segmentImages: [UIImage] = []
    private var selectedSegmentIndex: Int = 0
    
    func configure(segmentImages: [UIImage], selectedSegmentIndex: Int, delegate: ObvSegmentedControlTableViewCellDelegate) {
        self.segmentImages = segmentImages
        self.selectedSegmentIndex = selectedSegmentIndex
        self.delegate = delegate
        setNeedsUpdateConfiguration()
    }
    
    override func updateConfiguration(using state: UICellConfigurationState) {
        contentConfiguration = UIHostingConfiguration {
            DiscussionsFilterCellContentView(selectedSegmentIndex: selectedSegmentIndex, segmentImages: segmentImages, delegate: delegate)
        }
        backgroundConfiguration = DiscussionsFilterCellBackgroundConfiguration.configuration(for: state)
    }
}


// MARK: - DiscussionCellBackgroundConfiguration
@available(iOS 16.0, *)
struct DiscussionsFilterCellBackgroundConfiguration {
    static func configuration(for state: UICellConfigurationState) -> UIBackgroundConfiguration {
        var background = UIBackgroundConfiguration.listPlainCell().updated(for: state)
        background.backgroundColorTransformer = UIConfigurationColorTransformer { _ in
            return .systemBackground
        }
        return background
    }
}

@available(iOS 16.0, *)
struct DiscussionsFilterCellContentView: View {
    @State var selectedSegmentIndex: Int
    let segmentImages: [UIImage]
    weak var delegate: ObvSegmentedControlTableViewCellDelegate?

    var body: some View {
        VStack {
            Picker(NSLocalizedString("DISCUSSIONS_FILTER_CELL_PICKER_TEXT", comment: ""), selection: $selectedSegmentIndex) {
                ForEach(segmentImages.indices, id: \.self) { (index: Int) in
                    Image(uiImage: segmentImages[index]).tag(index)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedSegmentIndex, perform: { delegate?.segmentedControlValueChanged(toIndex: $0) })
        }
    }
}
