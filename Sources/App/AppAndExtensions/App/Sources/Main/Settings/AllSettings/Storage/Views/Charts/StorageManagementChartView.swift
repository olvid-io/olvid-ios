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

import SwiftUI
import Charts

@available(iOS 17.0, *)
struct StorageManagementChartView<Model: StorageManagementChartViewModelProtocol>: View {
    
    var model: Model
    
    init(model: Model) {
        self.model = model
    }
    
    var body: some View {
//        let _ = Self._printChanges() // Use to print changes to observable
        VStack(alignment: .leading, spacing: 0.0) {
            HStack(alignment: .firstTextBaseline, spacing: 4.0) {
                Text(model.formattedTotalBytes)
                    .font(.title)
                    .fontWeight(.semibold)
                Text("STORAGE_USED")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            
            Chart(model.storageCharts, id: \.name) { item in
                Plot {
                    BarMark(
                        x: .value("Value", item.value)
                    )
                    .foregroundStyle(by: .value("Name", item.name))
                }
            }
            .chartPlotStyle { plotArea in
                plotArea
                    .frame(height: 20.0)
                    .cornerRadius(8)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(range: .plotDimension(endPadding: -10))
            .chartLegend(position: .bottom, spacing: 10)
//            .chartForegroundStyleScale(range: model.chartForegroundStyleScale)
            .padding(.top, 12.0)
        }
    }
}
