import Foundation

@MainActor
final class MetricsSampler {
    typealias Reader = @Sendable (NetworkCounterTotals?) -> RawMetricsSample
    typealias Interfaces = @Sendable () -> [String: NetworkInterfaceCounters]?

    private let queue = DispatchQueue(label: "com.macpulse.metrics", qos: .utility)
    private let read: Reader
    private let interfaces: Interfaces
    private let interval: TimeInterval
    private var timer: DispatchSourceTimer?
    private var generation: UInt64 = 0

    init(interval: TimeInterval = 1,
         read: @escaping Reader = { SystemMetricsReader().read(networkCounters: $0) },
         interfaces: @escaping Interfaces = { SystemMetricsReader().readNetworkInterfaces() }) {
        precondition(interval.isFinite && interval > 0)
        self.interval = interval
        self.read = read
        self.interfaces = interfaces
    }

    func start(deliver: @escaping @MainActor (MetricsSnapshot, [String: NetworkInterfaceCounters], Date) -> Void) {
        guard timer == nil else { return }
        generation &+= 1
        let token = generation
        let worker = SamplingWorker(read: read, interfaces: interfaces)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(150))
        timer.setEventHandler { [weak self] in
            let result = worker.sample()
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.timer != nil else { return }
                deliver(result.0, result.1, result.2)
            }
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        generation &+= 1
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }

    deinit { timer?.cancel() }
}

// The worker is created per start and accessed exclusively by the serial
// sampling queue. Snapshot and interface totals travel in one delivery.
private final class SamplingWorker: @unchecked Sendable {
    let read: MetricsSampler.Reader
    let interfaces: MetricsSampler.Interfaces
    var calculator = MetricsCalculator()
    var network = NetworkCounterAccumulator()
    var previousDate: Date?

    init(read: @escaping MetricsSampler.Reader, interfaces: @escaping MetricsSampler.Interfaces) {
        self.read = read
        self.interfaces = interfaces
    }

    func sample() -> (MetricsSnapshot, [String: NetworkInterfaceCounters], Date) {
        let date = Date()
        if let previousDate, !(0...5).contains(date.timeIntervalSince(previousDate)) {
            calculator = MetricsCalculator()
            _ = network.update([:])
        }
        previousDate = date
        let counters = interfaces()
        let totals: NetworkCounterTotals?
        if let counters {
            totals = network.update(counters)
        } else {
            _ = network.update([:])
            totals = nil
        }
        let snapshot = calculator.update(read(totals))
        return (snapshot, network.runtimeTotalsByInterface(), date)
    }
}
