import Foundation

enum DetailReading: Sendable {
    case processes([RawProcessSample], LoadAverage?)
    case volumes([VolumeSpace])
    case interfaces([InterfaceDetail])
}

enum DetailSample: Sendable {
    case processes(ProcessSummary, LoadAverage?)
    case volumes([VolumeSpace])
    case interfaces([InterfaceDetail])
}

@MainActor
final class DetailSampler {
    typealias Reader = @Sendable (MetricCategory) -> DetailReading

    private let queue = DispatchQueue(label: "com.macpulse.detail", qos: .utility)
    private let read: Reader
    private let interval: TimeInterval
    private var timer: DispatchSourceTimer?
    private var generation: UInt64 = 0

    init(interval: TimeInterval = 2, read: @escaping Reader = { DetailSampler.readSystem($0) }) {
        precondition(interval.isFinite && interval > 0)
        self.interval = interval
        self.read = read
    }

    func start(_ category: MetricCategory, deliver: @escaping @MainActor (DetailSample) -> Void) {
        stop()
        let token = generation
        let worker = DetailWorker(read: read)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(150))
        timer.setEventHandler { [weak self] in
            let result = worker.sample(category)
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.timer != nil else { return }
                deliver(result)
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

    deinit {
        timer?.cancel()
    }

    nonisolated private static func readSystem(_ category: MetricCategory) -> DetailReading {
        switch category {
        case .cpu, .memory:
            return .processes(ProcessSampler().read(), SystemDetailReader.loadAverage())
        case .disk:
            return .volumes(VolumeSpaceReader.read())
        case .network:
            return .interfaces(SystemMetricsReader().readInterfaceDetails())
        }
    }
}

// A fresh worker belongs to one sampling session and is used only by the
// serial detail queue; restarting always discards process CPU baselines.
private final class DetailWorker: @unchecked Sendable {
    let read: DetailSampler.Reader
    var table = ProcessTable()

    init(read: @escaping DetailSampler.Reader) {
        self.read = read
    }

    func sample(_ category: MetricCategory) -> DetailSample {
        switch read(category) {
        case let .processes(samples, load):
            return .processes(table.update(samples, at: ProcessInfo.processInfo.systemUptime), load)
        case let .volumes(volumes):
            return .volumes(volumes)
        case let .interfaces(interfaces):
            return .interfaces(interfaces)
        }
    }
}
