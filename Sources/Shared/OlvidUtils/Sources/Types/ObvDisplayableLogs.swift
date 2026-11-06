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


public actor ObvDisplayableLogs {

    private var displayableLogsAreEnabled = false
    private var containerURLForDisplayableLogs: URL?

    /// The nonisolated API turns each call into an event, and a single task handles the events on the actor in the order of the calls.
    private nonisolated let events: AsyncStream<Event>.Continuation

    public static let shared: ObvDisplayableLogs = {
        let (stream, continuation) = AsyncStream.makeStream(of: Event.self)
        let logs = ObvDisplayableLogs(events: continuation)
        Task {
            for await event in stream {
                await logs.handle(event)
            }
        }
        return logs
    }()

    private init(events: AsyncStream<Event>.Continuation) {
        self.events = events
    }

    // MARK: - Public API

    nonisolated
    public func doEnableRunningLogs(_ value: Bool) {
        events.yield(.enableRunningLogs(value))
    }


    nonisolated
    public func setContainerURLForDisplayableLogs(to url: URL) {
        events.yield(.setContainerURL(url))
    }


    /// The line carries the time of this call, not the time at which it is written.
    nonisolated
    public func log(_ string: String) {
        events.yield(.log(string, date: Date()))
    }

    
    public func getAvailableLogs() throws -> [NSURL] {
        guard let containerURLForDisplayableLogs else {
            throw ObvError.containerURLForDisplayableLogsIsNil
        }
        let fm = FileManager.default
        let logs = try fm.contentsOfDirectory(atPath: containerURLForDisplayableLogs.path)
            .sorted()
            .reversed()
            .map({ $0 as String })
            .map({ containerURLForDisplayableLogs.appendingPathComponent($0) as NSURL })
        return logs
    }

    
    public func getSizeOfLog(_ log: NSURL) throws -> Int64? {
        guard let path = log.path else { assertionFailure(); return nil }
        guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: path) else { assertionFailure(); return nil }
        return fileAttributes[FileAttributeKey.size] as? Int64
    }
    
    
    public func deleteLogsOlderThan(date: Date) throws {
        let fm = FileManager.default
        let logs = try getAvailableLogs()
        for log in logs {
            guard let logDate = dateFromLog(log) else { continue }
            if logDate < date {
                guard let path = log.path else { assertionFailure(); continue }
                guard fm.fileExists(atPath: path) else { assertionFailure(); continue }
                try? fm.removeItem(at: log as URL)
            }
        }
    }

    
    // MARK: - Private API
    
    private let dateFormatterForFilename: DateFormatter = {
        let df = DateFormatter()
        df.timeStyle = .none
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()
    
    
    private let dateFormatterForLog: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss:SSSSZZZZZ"
        return df
    }()
    

    private func handle(_ event: Event) {
        switch event {
        case .enableRunningLogs(let value):
            displayableLogsAreEnabled = value
        case .setContainerURL(let url):
            assert(containerURLForDisplayableLogs == nil || containerURLForDisplayableLogs == url, "In practice, we expect to set this value exactly once")
            containerURLForDisplayableLogs = url
        case .log(let string, let date):
            append(string, date: date)
        }
    }


    /// The app and the notification service extension write to the same file. Each line is appended with a single `write` on a descriptor opened with
    /// `O_APPEND`, so that two processes cannot write at the same offset.
    private func append(_ string: String, date: Date) {
        guard displayableLogsAreEnabled, let containerURLForDisplayableLogs else { return }
        let day = dateFormatterForFilename.string(from: date)
        let path = containerURLForDisplayableLogs.appendingPathComponent("\(day)-olvid.log", isDirectory: false).path
        var text = dateFormatterForLog.string(from: date) + " - " + string + "\n"
        // The process that creates the day's file starts it with the day.
        var fileDescriptor = open(path, O_WRONLY | O_APPEND | O_CREAT | O_EXCL, 0o644)
        if fileDescriptor >= 0 {
            text = day + "\n" + text
        } else {
            guard errno == EEXIST else { return }
            fileDescriptor = open(path, O_WRONLY | O_APPEND)
            guard fileDescriptor >= 0 else { return }
        }
        defer { close(fileDescriptor) }
        let data = Data(text.utf8)
        _ = data.withUnsafeBytes { bytes in
            Darwin.write(fileDescriptor, bytes.baseAddress, bytes.count)
        }
    }


    private func dateFromLog(_ log: NSURL) -> Date? {
        guard let dateAsString = log.lastPathComponent?.replacingOccurrences(of: "-olvid.log", with: "") else { assertionFailure(); return nil }
        return dateFormatterForFilename.date(from: dateAsString)
    }

    
    enum ObvError: Error {
        case containerURLForDisplayableLogsIsNil
    }


    private enum Event: Sendable {
        case enableRunningLogs(Bool)
        case setContainerURL(URL)
        case log(String, date: Date)
    }
}
