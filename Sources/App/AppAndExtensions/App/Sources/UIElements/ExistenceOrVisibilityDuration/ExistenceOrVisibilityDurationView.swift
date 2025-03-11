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

import Foundation
import SwiftUI


/// View used when setting the general existence or visibility settings, or the existence or visibility settings of a specific discussion.
struct ExistenceOrVisibilityDurationView: View {
    
    @Binding var timeInverval: TimeInterval?
    
    var body: some View {
        Form {
            List {
                ForEach(DurationOption.allCases) { durationOption in
                    HStack {
                        Text(verbatim: TimeInterval.formatForExistenceOrVisibilityDuration(timeInterval: durationOption.timeInterval, unitsStyle: .full))
                        Spacer()
                        Image(systemIcon: .checkmark)
                            .opacity(durationOption.timeInterval == timeInverval ? 1.0 : 0.0)
                            .foregroundStyle(Color(UIColor.systemGreen))
                    }
                    .contentShape(Rectangle()) // This makes it possible to have an "on tap" gesture that also works when the Spacer is tapped
                    .onTapGesture {
                        withAnimation {
                            timeInverval = durationOption.timeInterval
                        }
                    }
                }
            }
        }
    }
}


/// View used in the sheet shown in a discussion when the user wants to set custom read-once, visibility, or existence parameters on a specific message sent.
struct ExistenceOrVisibilityDurationPicker<Label: View>: View {

    @Binding var timeInverval: TimeInterval?
    private let availableDurationOptions: [DurationOption]
    private let label: () -> Label

    init(timeInverval: Binding<TimeInterval?>, maxTimeInterval: TimeInterval?, @ViewBuilder label: @escaping () -> Label) {
        self.label = label
        self._timeInverval = timeInverval
        availableDurationOptions = DurationOption.allCases.filter {
            guard let maxTimeInterval else { return true }
            guard let timeInterval = $0.timeInterval else { return true }
            return timeInterval <= maxTimeInterval
        }
        durationOption = Self.getDurationOption(from: timeInverval.wrappedValue)
    }
    
    
    private static func getDurationOption(from timeInterval: TimeInterval?) -> DurationOption {
        guard let timeInterval else { return .none }
        if let durationOption = DurationOption(rawValue: Int(timeInterval)) {
            return durationOption
        } else {
            assertionFailure()
            return .none
        }
    }
    
    
    @State private var durationOption: DurationOption
    
    var body: some View {
        Picker(selection: $durationOption, content: {
            ForEach(availableDurationOptions) { durationOption in
                Text(verbatim: TimeInterval.formatForExistenceOrVisibilityDuration(timeInterval: durationOption.timeInterval, unitsStyle: .full))
            }
        }, label: label)
        .onChange(of: durationOption, perform: {
            timeInverval = $0.timeInterval
        })
        .onChange(of: timeInverval) { newValue in
            // Allow for an external reset
            let newDurationOption = Self.getDurationOption(from: newValue)
            durationOption = newDurationOption
        }
    }
    
}


fileprivate enum DurationOption: Int, Identifiable, CaseIterable {

    case none = 0
    case fiveSeconds = 5
    case tenSeconds = 10
    case thirtySeconds = 30
    case oneMinute = 60
    case fiveMinutes = 300
    case thirtyMinutes = 1_800
    case oneHour = 3_600
    case sixHour = 21_600
    case twelveHours = 43_200
    case oneDay = 86_400
    case sevenDays = 604_800
    case thirtyDays = 2_592_000
    case ninetyDays = 7_776_000
    case oneHundredAndHeightyDays = 15_552_000
    case oneYear = 31_536_000
    case threeYears = 94_608_000
    case fiveYears = 157_766_400 // not 157_680_000, so as to make sure the date formatter shows 5 year

    var id: Self { self }

    public var timeInterval: TimeInterval? {
        switch self {
        case .none: return nil
        default: return TimeInterval(self.rawValue)
        }
    }

    // Returns self.timeInterval <= other
    public func le(_ other: TimeInterval?) -> Bool {
        guard let other = other else { return true }
        guard let timeInterval = timeInterval else { return false }
        return timeInterval <= other
    }
    
}
