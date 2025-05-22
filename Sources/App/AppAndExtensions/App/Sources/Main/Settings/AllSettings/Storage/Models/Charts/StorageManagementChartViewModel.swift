/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import SwiftUI
import ObvUICoreData

@available(iOS 17.0, *)
@Observable
class StorageManagementChartViewModel: StorageManagementChartViewModelProtocol {
    
    private static let MAX_STORAGE_COUNT_IN_CHART: Int = 4
    
    private(set) var filesPerDiscussions: [PersistedDiscussion: [FyleMessageJoinWithStatus]]
    
    var formattedTotalBytes: String {
        let totalByteCount = filesPerDiscussions.values
            .compactMap { $0.reduce(0) { $0 + $1.totalByteCount } } // Transform from [[FyleMessageJoinWithStatus]] to [totalByteCount per discussion]
            .reduce(0, +) // from [totalByteCount per discussion] to totalByteCount for all discussions
        
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = .useAll
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        
        return formatter.string(fromByteCount: totalByteCount)
    }
    
    var storageCharts: [StorageChart] {
        
        let fullStorageCharts = filesPerDiscussions.compactMap { discussion, files in
            let totalByteCount = files.reduce(0) { $0 + $1.totalByteCount }
            return StorageChart(name: discussion.title, value: Int(totalByteCount))
        }.sorted { $0.value > $1.value }

        if fullStorageCharts.count > StorageManagementChartViewModel.MAX_STORAGE_COUNT_IN_CHART {
            let filteredStorageCharts = fullStorageCharts[0..<StorageManagementChartViewModel.MAX_STORAGE_COUNT_IN_CHART]
            
            let otherStorageChartsValue = fullStorageCharts.filter { !filteredStorageCharts.contains($0) }.reduce(0){ $0 + $1.value }

            return Array(filteredStorageCharts) + [StorageChart(name: NSLocalizedString("OTHER_STORAGE_CHART_LEGEND", comment: ""), value: otherStorageChartsValue)]
        } else {
            return fullStorageCharts
        }
        
    }
    
    var chartForegroundStyleScale: [Color] {
        
        let colors = [UIColor(red: 47.0/255.0, green: 101.0/255.0, blue: 245.0/255.0, alpha: 1.0),
                      UIColor(red: 86.0/255.0, green: 136.0/255.0, blue: 199.0/255.0, alpha: 1.0),
                      UIColor(red: 104.0/255.0, green: 159.0/255.0, blue: 214.0/255.0, alpha: 1.0),
                      UIColor(red: 131.0/255.0, green: 193.0/255.0, blue: 255.0/255.0, alpha: 1.0),
                      UIColor(red: 229.0/255.0, green: 252.0/255.0, blue: 255.0/255.0, alpha: 1.0)]
        
        let chartCount = storageCharts.count
        let step: CGFloat = 100.0 / CGFloat(chartCount - 1)
        
        var resultColors = [Color]()
        for index in 0..<chartCount {
            let percentage = step * CGFloat(index)
            
            resultColors.append(Color(uiColor: colors.intermediate(percentage: percentage)))
        }
        
        return resultColors
    }
    
    init(filesPerDiscussions: [PersistedDiscussion : [FyleMessageJoinWithStatus]]) {
        self.filesPerDiscussions = filesPerDiscussions
    }
}

fileprivate
extension Array where Element: UIColor {
    
    /// Method in order to find the intermediate color between two or more colors.
    /// Useful if we want to create an array of colors dynamically without to know the exact number of colors we have to generate.
    func intermediate(percentage: CGFloat) -> UIColor {
        let percentage = Swift.max(Swift.min(percentage, 100), 0) / 100
        switch percentage {
        case 0: return first ?? .clear
        case 1: return last ?? .clear
        default:
            let approxIndex = percentage / (1 / CGFloat(count - 1))
            let firstIndex = Int(approxIndex.rounded(.down))
            let secondIndex = Int(approxIndex.rounded(.up))
            let fallbackIndex = Int(approxIndex.rounded())
            
            let firstColor = self[firstIndex]
            let secondColor = self[secondIndex]
            let fallbackColor = self[fallbackIndex]
            
            var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            guard firstColor.getRed(&r1, green: &g1, blue: &b1, alpha: &a1) else { return fallbackColor }
            guard secondColor.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else { return fallbackColor }
            
            let intermediatePercentage = approxIndex - CGFloat(firstIndex)
            return UIColor(
                red: CGFloat(r1 + (r2 - r1) * intermediatePercentage),
                green: CGFloat(g1 + (g2 - g1) * intermediatePercentage),
                blue: CGFloat(b1 + (b2 - b1) * intermediatePercentage),
                alpha: CGFloat(a1 + (a2 - a1) * intermediatePercentage)
            )
        }
    }
    
}
