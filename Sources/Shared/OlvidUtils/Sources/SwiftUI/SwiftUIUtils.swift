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


extension View {

    @ViewBuilder
    public func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    public func apply<V: View>(@ViewBuilder _ block: (Self) -> V) -> V { block(self) }
    
}


extension View {
    
    @ViewBuilder
    public func isHidden(_ isHidden: Bool) -> some View {
        if isHidden {
            self.hidden()
        } else {
            self
        }
    }
    
}


public struct DottedCircle: View {
    let radius: CGFloat
    let pi = Double.pi
    let dotCount = 14
    let dotLength: CGFloat = 4
    let spaceLength: CGFloat

    public init(radius: CGFloat) {
        self.radius = radius
        let circumerence: CGFloat = CGFloat(2.0 * pi) * radius
        self.spaceLength = circumerence / CGFloat(dotCount) - dotLength
    }

    public var body: some View {
        Circle()
            .stroke(.gray, style: StrokeStyle(lineWidth: 2, lineCap: .butt, lineJoin: .miter, miterLimit: 0, dash: [dotLength, spaceLength], dashPhase: 0))
            .frame(width: radius * 2, height: radius * 2)
    }
}


public struct Positions: PreferenceKey {
    public static let defaultValue: [String: Anchor<CGPoint>] = [:]
    public static func reduce(value: inout [String: Anchor<CGPoint>], nextValue: () -> [String: Anchor<CGPoint>]) {
        value.merge(nextValue(), uniquingKeysWith: { current, _ in
            return current })
    }
}


public struct PositionReader: View {
    
    let tag: String
    
    public init(tag: String) {
        self.tag = tag
    }
    
    public var body: some View {
        Color.clear
            .anchorPreference(key: Positions.self, value: .center) { (anchor) in
                [tag: anchor]
            }
    }
    
}


extension Task where Success == Never, Failure == Never {
    public static func sleep(seconds: Double) async throws {
        let duration = UInt64(seconds * 1_000_000_000)
        try await Task.sleep(nanoseconds: duration)
    }
    public static func sleep(for timeInterval: TimeInterval) async throws {
        let duration = UInt64(timeInterval * 1_000_000_000)
        try await Task.sleep(nanoseconds: duration)
    }
    public static func sleep(milliseconds: Int) async throws {
        let duration = UInt64(milliseconds * 1_000_000)
        try await Task.sleep(nanoseconds: duration)
    }
}
