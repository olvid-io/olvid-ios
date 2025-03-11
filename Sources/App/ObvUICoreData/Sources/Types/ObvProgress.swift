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


/// An `ObvProgress` is a `Progress` that automatically computes the `estimatedTimeRemaining` and `throughput`
public final class ObvProgress: Progress, @unchecked Sendable {

    private let eta: ProgressETA

    public init(totalUnitCount unitCount: Int64) {
        self.eta = ProgressETA(totalUnitCount: unitCount)
        super.init(parent: nil)
        self.totalUnitCount = unitCount
    }
    
    func updateWithNewProgress(_ newProgress: Float) {
        self.completedUnitCount = Int64(Double(newProgress) * Double(self.totalUnitCount))
    }
    
    public override var completedUnitCount: Int64 {
        get {
            super.completedUnitCount
        }
        set {
            super.completedUnitCount = newValue
            Task {
                await refreshThroughputAndEstimatedTimeRemaining()
            }
        }
    }
    
    public func refreshThroughputAndEstimatedTimeRemaining() async {
        let updatedETA = await eta.getUpdatedETA(forCompletedUnitCount: completedUnitCount)
        self.throughput = updatedETA.throughput
        self.estimatedTimeRemaining = updatedETA.estimatedTimeRemaining
    }

}


// MARK: - ProgressETA

private actor ProgressETA {
    
    private let totalUnitCount: Int64
    
    // Internal constants
    private let sampleLimitTimeInterval: TimeInterval = 10 // Only keep samples received in the last 10 seconds
    private let sampleLimitNumber = 30

    private var samples = [(date: Date, completedUnitCount: Int64)]()
    private var throughput: Int = 0
    private var estimatedTimeRemaining: TimeInterval? // Nil while evaluating
    
    init(totalUnitCount: Int64) {
        self.totalUnitCount = totalUnitCount
    }
    
    func getUpdatedETA(forCompletedUnitCount completedUnitCount: Int64) -> (throughput: Int?, estimatedTimeRemaining: TimeInterval?) {
        samples.append((Date(), completedUnitCount))
        cleanSamples()
        refreshThroughput()
        refreshEstimatedTimeRemaining()
        return (throughput, estimatedTimeRemaining)
    }
    
    private func cleanSamples() {
        samples = samples.filter({ $0.date > Date(timeIntervalSinceNow: -sampleLimitTimeInterval) }).suffix(sampleLimitNumber)
    }

    private func refreshThroughput() {
        guard samples.count > 1 else {
            self.throughput = 0
            return
        }
        var throughputs = [Int]()
        for index in 0..<samples.count-1 {
            let startSample = samples[index]
            let endSample = samples[index+1]
            let completedUnitCount = max(0, endSample.completedUnitCount - startSample.completedUnitCount)
            let timeInterval = max(Double.leastNonzeroMagnitude, endSample.date.timeIntervalSince(startSample.date))
            throughputs.append(Int(Double(completedUnitCount) / timeInterval))
        }
        guard throughputs.count > 0 else { return }
        self.throughput = throughputs.reduce(0, +) / throughputs.count
    }

    private func refreshEstimatedTimeRemaining() {
        let throughputAsDouble = Double(throughput)
        guard let completedUnitCount = samples.last?.completedUnitCount, throughputAsDouble != 0 else {
            self.estimatedTimeRemaining = nil
            return
        }
        let remainingUnitCount = max(0, Int(self.totalUnitCount - completedUnitCount))
        self.estimatedTimeRemaining = Double(remainingUnitCount) / throughputAsDouble
    }

}
