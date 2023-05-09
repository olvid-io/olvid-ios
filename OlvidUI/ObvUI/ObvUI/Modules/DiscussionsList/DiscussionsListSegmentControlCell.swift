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
final class DiscussionsListSegmentControlCell: UICollectionViewListCell {
    
    private weak var delegate: DiscussionsListSegmentControlCellDelegate?
    private var segmentImages: [UIImage] = []
    private var selectedSegmentIndex: Int = 0
    
    func configure(with viewModel: DiscussionsListSegmentControlCellViewModel) {
        self.segmentImages = viewModel.segmentImages
        self.selectedSegmentIndex = viewModel.selectedSegmentIndex
        self.delegate = viewModel.delegate
        setNeedsUpdateConfiguration()
    }
    
    override func updateConfiguration(using state: UICellConfigurationState) {
        contentConfiguration = UIHostingConfiguration {
            DiscussionsListSegmentControlCellContentView(selectedSegmentIndex: selectedSegmentIndex,
                                                         segmentImages: segmentImages,
                                                         pickerText: NSLocalizedString("DISCUSSIONS_FILTER_CELL_PICKER_TEXT", bundle: Bundle(for: Self.self), comment: ""),
                                                         delegate: delegate)
        }
        backgroundConfiguration = DiscussionsListSegmentControlCellBackgroundConfiguration.configuration(for: state)
    }
}


// MARK: - DiscussionCellBackgroundConfiguration
@available(iOS 16.0, *)
struct DiscussionsListSegmentControlCellBackgroundConfiguration {
    static func configuration(for state: UICellConfigurationState) -> UIBackgroundConfiguration {
        var background = UIBackgroundConfiguration.listPlainCell().updated(for: state)
        background.backgroundColorTransformer = UIConfigurationColorTransformer { _ in
            return .systemBackground
        }
        return background
    }
}

@available(iOS 16.0, *)
struct DiscussionsListSegmentControlCellContentView: View {
    @State var selectedSegmentIndex: Int
    let segmentImages: [UIImage]
    let pickerText: String
    weak var delegate: DiscussionsListSegmentControlCellDelegate?

    var body: some View {
        VStack {
            Picker(pickerText, selection: $selectedSegmentIndex) {
                ForEach(segmentImages.indices, id: \.self) { (index: Int) in
                    Image(uiImage: segmentImages[index]).tag(index)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedSegmentIndex, perform: { delegate?.segmentedControlValueChanged(toIndex: $0) })
        }
    }
}
