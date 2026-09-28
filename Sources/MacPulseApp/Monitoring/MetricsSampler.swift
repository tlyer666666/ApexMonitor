import Foundation

final class MetricsSampler {
    private let queue = DispatchQueue(label: "com.macpulse.metrics", qos: .utility)
    private let reader = SystemMetricsReader()
    private var calculator = MetricsCalculator()
    private var networkAccumulator = NetworkCounterAccumulator()
    private var timer: DispatchSourceTimer?

    func start(deliver: @escaping @Sendable (MetricsSnapshot) -> Void) {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(150))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let counters = self.reader.readNetworkInterfaces()
            let totals = counters.flatMap { self.networkAccumulator.update($0) }
            let sample = self.reader.read(networkCounters: totals)
            let snapshot = self.calculator.update(sample)
            deliver(snapshot)
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }

    deinit {
        stop()
    }
}
