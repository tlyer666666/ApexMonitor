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

    public init(receivedBytes: UInt64, sentBytes: UInt64) {
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
    }
}

public struct NetworkCounterAccumulator {
    private struct State {
        var raw: NetworkInterfaceCounters
        var total: NetworkInterfaceCounters
    }

    private var states: [String: State] = [:]

    public init() {}

    public mutating func update(_ current: [String: NetworkInterfaceCounters]) -> NetworkCounterTotals? {
        guard !current.isEmpty else {
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

            state.total = NetworkInterfaceCounters(
                receivedBytes: state.total.receivedBytes &+ delta(from: state.raw.receivedBytes, to: counters.receivedBytes),
                sentBytes: state.total.sentBytes &+ delta(from: state.raw.sentBytes, to: counters.sentBytes)
            )
            state.raw = counters
            states[name] = state
        }

        for name in states.keys where current[name] == nil {
            states.removeValue(forKey: name)
        }

        let totals = states.values.reduce((received: UInt64(0), sent: UInt64(0))) { partial, state in
            (partial.received &+ state.total.receivedBytes, partial.sent &+ state.total.sentBytes)
        }
        return NetworkCounterTotals(receivedBytes: totals.received, sentBytes: totals.sent)
    }

    private func delta(from old: UInt64, to new: UInt64) -> UInt64 {
        guard new < old else { return new - old }
        if old <= UInt64(UInt32.max),
           new <= UInt64(UInt32.max) / 10,
           old >= UInt64(UInt32.max) * 9 / 10 {
            return UInt64(UInt32.max) - old + new + 1
        }
        return 0
    }
}
