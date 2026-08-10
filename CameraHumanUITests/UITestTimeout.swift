import Foundation

/// Shared wait ceiling for UI tests.
///
/// GitHub-hosted runners are slower and far more variable than a local machine:
/// the same `VisualRegressionTests` run took 22s on CI one time and 48s the
/// next, and the 5s waits that pass locally time out in the slow case
/// (`bugs.md` §12). These waits return as soon as the element appears, so a
/// generous ceiling costs nothing when the machine is fast — it only decides
/// how long a genuinely stuck test takes to fail.
enum UITestTimeout {
    static let standard: TimeInterval = 15
}
