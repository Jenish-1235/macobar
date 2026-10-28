import Foundation

/// Totals across every scenario run.
struct BenchSummary: Sendable {
    /// Scenarios that passed.
    let passedCount: Int
    /// Scenarios run.
    let count: Int
    /// The middle scenario time in seconds; 0 when none ran.
    let medianSeconds: Double
    /// All scenario times added up, in seconds.
    let totalSeconds: Double

    /// Totals for `results`.
    init(results: [ScenarioResult]) {
        let times = results.map(\.seconds).sorted()
        passedCount = results.count { $0.passed }
        count = results.count
        totalSeconds = times.reduce(0, +)
        medianSeconds = switch times.count {
        case 0: 0
        case let count where count.isMultiple(of: 2): (times[count / 2 - 1] + times[count / 2]) / 2
        case let count: times[count / 2]
        }
    }

    /// Share of scenarios that passed, from 0 to 100.
    var passRate: Int {
        count == 0 ? 0 : Int((Double(passedCount) / Double(count) * 100).rounded())
    }

    /// The printed summary, e.g. `Passed 12 of 16 (75%). Median 3.1s, total 52.4s.`
    var line: String {
        String(format: "Passed %ld of %ld (%ld%%). Median %.1fs, total %.1fs.", passedCount, count, passRate, medianSeconds, totalSeconds)
    }
}
