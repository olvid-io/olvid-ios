/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvAppTypes

struct ComposeAudioRecorderView: View {
    
    @ObservedObject var audioRecorder = ObvAudioRecorder.shared
    
    private let durationFormatter = AudioDurationFormatter()
    
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2
    
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            GeometryReader { geometry in
                HStack(alignment: .center, spacing: barSpacing) {
                    let totalBars = Int(geometry.size.width / (barWidth + barSpacing))
                    let samples = Array(audioRecorder.liveWaveformSamples.suffix(totalBars))
                    
                    ForEach(Array(samples.enumerated()), id: \.offset) { idx, sample in
                        Rectangle()
                            .frame(width: barWidth, height: max(barWidth, 56.0 * CGFloat(sample)))
                            .cornerRadius(barWidth / 2.0)
                            .foregroundStyle(.red)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 60.0)
            .animation(.easeOut(duration: 0.15), value: audioRecorder.liveWaveformSamples)
            Spacer()
            Text(durationFormatter.string(from: audioRecorder.currentDuration) ?? "00:00")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }
}

class AudioDurationFormatter: Formatter {

    func string(from duration: Double) -> String? {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = [ .pad ]
        formatter.allowedUnits = [ .second, .minute ]

        return formatter.string(from: duration)
    }
}

