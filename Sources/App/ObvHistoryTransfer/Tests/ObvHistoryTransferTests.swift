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

import XCTest
@testable import ObvHistoryTransfer
import ObvAppTypes

final class ObvHistoryTransferTests: XCTestCase {
    
    func testJsonRangesByThreadJsonEncoding() {
        
        var ranges = [UUID: [ClosedRange<Int>]]()
        ranges[.sampleDatas[0]] = [0...2, 5...7]
        ranges[.sampleDatas[1]] = [0...1]
        
        let jsonRangesByThread = JsonRangesByThread(ranges: ranges)
        
        do {
            
            let jsonEncoder = JSONEncoder()
            let jsonData = try jsonEncoder.encode(jsonRangesByThread)
            
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
            let prettyData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted,.withoutEscapingSlashes,.sortedKeys])
            let prettyPrintedString =  NSString(data: prettyData, encoding: String.Encoding.utf8.rawValue)
            print(prettyPrintedString!)
            
            let decoder = JSONDecoder()
            let decodedRangesByThread = try decoder.decode(JsonRangesByThread.self, from: jsonData)
            
            XCTAssertEqual(jsonRangesByThread, decodedRangesByThread)
            
        } catch {
            XCTAssertTrue(false, error.localizedDescription)
        }
        
    }
    
    func testSrcDiscussionRangesJsonEncoding() {
        
        do {
            let srcDiscussionRanges = try SrcDiscussionRanges(
                discussionTitle: "The discussion title",
                discussionIdentifier: .sampleData[0],
                messageIdentifiers: ObvMessageAppIdentifier.sampleData)
            
            let jsonEncoder = JSONEncoder()
            let jsonData = try jsonEncoder.encode(srcDiscussionRanges)
            
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
            let prettyData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted,.withoutEscapingSlashes,.sortedKeys])
            let prettyPrintedString =  NSString(data: prettyData, encoding: String.Encoding.utf8.rawValue)
            print(prettyPrintedString!)
            
            let decoder = JSONDecoder()
            let decodedSrcDiscussionRanges = try decoder.decode(SrcDiscussionRanges.self, from: jsonData)

            XCTAssertEqual(srcDiscussionRanges, decodedSrcDiscussionRanges)
            
        } catch {
            XCTAssertTrue(false, error.localizedDescription)
        }
        
    }
    
}
