public struct NetworkInterfaceCounters: Sendable, Equatable {
    public let receivedBytes: UInt64
    public let sentBytes: UInt64

    public init(receivedBytes: UInt64, sentBytes: UInt64) {
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
    }
}

public struct NetworkCounterTotals: Sendable, Equatable {
    public let receivedBytes: UInt64
    public let sentBytes: UInt64
    /// True when some interface delta could not be classified (counter reset or
    /// an out-of-band 32-bit wrap). Those bytes are unknown, never measured idle.
    public let hasUncertainDelta: Bool

    public init(receivedBytes: UInt64, sentBytes: UInt64, hasUncertainDelta: Bool = false) {
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
        self.hasUncertainDelta = hasUncertainDelta
    }
}

public struct NetworkCounterAccumulator {
    private struct State {
        var raw: NetworkInterfaceCounters
        var total: NetworkInterfaceCounters
    }

    private var states: [String: State] = [:]
    private var retired = NetworkInterfaceCounters(receivedBytes: 0, sentBytes: 0)
    private var hasUncertainDelta = false

    public init() {}

    /// Runtime-accumulated deltas per interface currently being tracked.
    public func runtimeTotalsByInterface() -> [String: NetworkInterfaceCounters] {
        states.mapValues { $0.total }
    }

    public mutating func update(_ current: [String: NetworkInterfaceCounters]) -> NetworkCounterTotals? {
        hasUncertainDelta = false
        guard !current.isEmpty else {
            // Retire remaining states so their accumulated bytes survive a
            // temporary total interface loss.
            for state in states.values {
                retired = NetworkInterfaceCounters(
                    receivedBytes: retired.receivedBytes &+ state.total.receivedBytes,
                    sentBytes: retired.sentBytes &+ state.total.sentBytes
                )
            }
            states.removeAll(keepingCapacity: true)
            return nil
        }

        for (name, counters) in current {
            guard var state = states[name] else {
                states[name] = State(
                    raw: counters,
                    total: NetworkInterfaceCounters(receivedBytes: 0, sentBytes: 0)
                )
                continue
            }

            var uncertain = false
            var received = state.total.receivedBytes
            var sent = state.total.sentBytes
            if let delta = delta(from: state.raw.receivedBytes, to: counters.receivedBytes) {
                received = received &+ delta
            } else {
                uncertain = true
            }
            if let delta = delta(from: state.raw.sentBytes, to: counters.sentBytes) {
                sent = sent &+ delta
            } else {
                uncertain = true
            }
            state.total = NetworkInterfaceCounters(receivedBytes: received, sentBytes: sent)
            state.raw = counters
            states[name] = state
            hasUncertainDelta = hasUncertainDelta || uncertain
        }

        let departed = states.keys.filter { current[$0] == nil }
        for name in departed {
            guard let state = states.removeValue(forKey: name) else { continue }
            retired = NetworkInterfaceCounters(
                receivedBytes: retired.receivedBytes &+ state.total.receivedBytes,
                sentBytes: retired.sentBytes &+ state.total.sentBytes
            )
        }

        var totalReceived = retired.receivedBytes
        var totalSent = retired.sentBytes
        for state in states.values {
            totalReceived = totalReceived &+ state.total.receivedBytes
            totalSent = totalSent &+ state.total.sentBytes
        }
        return NetworkCounterTotals(
            receivedBytes: totalReceived,
            sentBytes: totalSent,
            hasUncertainDelta: hasUncertainDelta
        )
    }

    /// Classifiable deltas only. A decrement is either a counter reset or a
    /// wrap outside the confident window; both stay unknown instead of
    /// reporting a fabricated zero.
    private func delta(from old: UInt64, to new: UInt64) -> UInt64? {
        guard new < old else { return new - old }
        if old >= UInt64(UInt32.max) * 9 / 10,
           new <= UInt64(UInt32.max) / 10 {
            return UInt64(UInt32.max) - old + new + 1
        }
        return nil
    }
}
