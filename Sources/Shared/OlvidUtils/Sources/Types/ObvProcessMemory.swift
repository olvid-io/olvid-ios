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

import Foundation
import Darwin
import os


/// What this process is charged for, and how much of its allowance is left.
///
/// Two **different questions** — say which one you are asking:
///
/// - ``footprint()`` is what the kernel charges us, the number jetsam compares against a limit.
/// - ``available()`` is what is left of *this process's* limit. It needs no hardcoded figure and is honest on a device whose limit is not what we assumed.
///
/// **They do not cost the same**: `os_proc_available_memory()`'s documentation offers `task_info` as the detailed alternative and warns that it "is an
/// expensive call, whereas this function is much more efficient". So the cheap one is asked repeatedly and the expensive one only at the ends of a run.
/// Both are public API; what needs privileges is asking about *another* process.
///
/// Written for the background task that drains the engine's inbox, which must stop itself before jetsam does: a deliberate stop leaves the work resumable.
///
/// **`os_proc_available_memory()` is unavailable on native macOS**, and this file deliberately does not hide that behind a `#if` — every target here is
/// iPhone/iPad, the Mac build being Catalyst, and a conditional would answer a silent nought, which ``available()`` explains is the one dangerous answer. A
/// native AppKit port should meet a compile error and decide then.
///
/// `PreviewMemory`, in the share extension, asks the same two questions of the same APIs and is left alone deliberately. When somebody has an hour: it could
/// forward to these, and its reading of a nought from `os_proc_available_memory()` is the wrong way round.
public enum ObvProcessMemory {

    /// Our physical footprint, in bytes — the quantity jetsam measures. Zero if the kernel declines to answer.
    ///
    /// `phys_footprint` rather than `resident_size`: resident size counts pages shared with other processes and clean pages the kernel can take back at
    /// will, so it is both larger and less relevant than what we are billed for.
    public static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let outcome = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard outcome == KERN_SUCCESS else { return 0 }
        return info.phys_footprint
    }


    /// How many bytes this process may still allocate before it is killed.
    ///
    /// **A zero has two documented meanings and they are opposites**, which is the whole reason this returns a case rather than a number. Apple: the
    /// function returns 0 "if the calling process isn't an app, or if the process has already exceeded its memory limit". So on a simulator, which is not a
    /// memory-limited process, a zero means *no information*; in an app on a device it means *you are already over*. Reported as a number, the two would
    /// read identically and a caller acting on it would do the opposite of the right thing in one of the two cases.
    ///
    /// Apple also says of the value: "Use the returned value as advisory information only and don't cache it."
    public static func available() -> Allowance {
        let bytes = os_proc_available_memory()
        return bytes > 0 ? .bytesRemaining(bytes) : .zeroWhichIsAmbiguous
    }


    /// What is left of this process's memory limit, or that we cannot tell.
    public enum Allowance: Equatable {

        case bytesRemaining(Int)

        /// `os_proc_available_memory()` answered nought, which means either that this process has no memory limit or that it has already exceeded the one it
        /// has. Nothing in the API distinguishes them, so a caller that must act on it has to establish which it is by other means — see
        /// ``ObvProcessMemory/Allowance/provesTheProcessIsMemoryLimited``.
        case zeroWhichIsAmbiguous

        /// Whether this reading proves the process **is** memory-limited — which is what lets a later ambiguous nought be trusted to mean *already over the
        /// limit*.
        ///
        /// A positive reading proves it, and a process does not stop being memory-limited. So a caller need only remember whether it has ever seen one:
        /// until it has, a nought cannot be told from a process with no limit at all — a simulator — and treating that as *out of room* would stand down
        /// whatever depends on it, on precisely the machine where such things are usually tested.
        ///
        /// **A property of one reading rather than a question asked of every reading so far**, which is what this was: an array was accumulated for the
        /// lifetime of a run, one element per round, only to be rescanned for the same answer each time. A caller keeps a `Bool`, and `||`s this into it.
        public var provesTheProcessIsMemoryLimited: Bool {
            bytes != nil
        }

        public var bytes: Int? {
            switch self {
            case .bytesRemaining(let bytes): return bytes
            case .zeroWhichIsAmbiguous: return nil
            }
        }

        public var descriptionForLogs: String {
            switch self {
            case .bytesRemaining(let bytes): return ObvProcessMemory.megabytes(UInt64(bytes))
            case .zeroWhichIsAmbiguous: return "0(ambiguous)"
            }
        }

    }


    /// The pair of them, formatted for a log line: `footprint=54.3MB available=61.7MB`.
    ///
    /// Always both, and always in the same order, so a column can be read down a log without parsing. Note that this asks the expensive question — fine at
    /// the ends of a run, not inside a loop.
    public static func description() -> String {
        "footprint=\(megabytes(footprint())) available=\(available().descriptionForLogs)"
    }


    /// Bytes as megabytes to one decimal, without a space, so a log line stays one field per column.
    public static func megabytes(_ bytes: UInt64) -> String {
        String(format: "%.1fMB", Double(bytes) / (1024 * 1024))
    }

}
