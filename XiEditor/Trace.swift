// Copyright 2018 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// A simple mechanism for logging trace events and outputting a file in
// Chrome tracing format

import Foundation

protocol Writeable {
    func write(_ data: Data)
}

/// Collect trace events so they can be output in Chrome tracing format.
class Trace {
    let mutex = UnfairLock()
    let BUF_SIZE = 100_000
    var buf: [TraceEntry]
    var n_entries = 0
    let mach_time_numer: UInt64
    let mach_time_denom: UInt64
    var enabled = false

    /// Shared instance, most uses should call this.
    static var shared = Trace()

    init() {
        buf = [TraceEntry](repeating: TraceEntry(), count: BUF_SIZE)
        var info = mach_timebase_info(numer: 0, denom: 0)
        mach_timebase_info(&info)
        mach_time_numer = UInt64(info.numer)
        // the 1000 is because mach time is ns, and chrome tracing time is us
        mach_time_denom = UInt64(info.denom) * 1000
    }
    
    func isEnabled() -> Bool {
        mutex.lock()
        defer {
            mutex.unlock()
        }
        return self.enabled
    }

    func setEnabled(_ enabled: Bool) {
        mutex.lock()
        defer {
            mutex.unlock()
        }
        self.enabled = enabled
        self.n_entries = 0
    }

    func trace(_ name: String, _ cat: TraceCategory, _ ph: TracePhase) {
        mutex.lock()
        defer {
            mutex.unlock()
        }

        if !self.enabled {
            return
        }
        let i = n_entries % BUF_SIZE
        buf[i].name = name
        buf[i].cat = cat
        buf[i].ph = ph
        buf[i].abstime = mach_absolute_time()
        pthread_threadid_np(nil, &buf[i].tid)
        n_entries += 1
    }

    func snapshot() -> [[String: AnyObject]] {
        mutex.lock()
        defer {
            mutex.unlock()
        }

        var result : [[String: AnyObject]] = []
        
        let pid = getpid()

        for entry_num in max(0, n_entries - BUF_SIZE) ..< n_entries {
            let i = entry_num % BUF_SIZE
            let ts = buf[i].abstime * mach_time_numer / mach_time_denom
            result.append([
                "name": buf[i].name as NSString,
                "cat": buf[i].cat.rawValue as NSString,
                "ph": buf[i].ph.rawValue as NSString,
                "pid": NSNumber(value: pid) as AnyObject,
                "tid": NSNumber(value: buf[i].tid) as AnyObject,
                "ts": NSNumber(value: ts) as AnyObject])
        }

        return result
    }
}

enum TraceCategory: String {
    case main
    case rpc
}

enum TracePhase: String {
    case begin = "B"
    case end = "E"
    case instant = "I"
}

struct TraceEntry {
    var name: String
    var cat: TraceCategory
    var ph: TracePhase
    var abstime: UInt64  // In mach_absolute_time format
    var tid: UInt64

    /// Create a default trace entry, contents don't matter as it's just preallocated
    init() {
        name = ""
        cat = .main
        ph = .instant
        abstime = mach_absolute_time()
        tid = 0
    }
}
