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
    private var retired = NetworkInterfaceCounters(receivedBytes: 0, sentBytes: 0)

    public init() {}

    public mutating func update(_ current: [String: NetworkInterfaceCounters]) -> NetworkCounterTotals? {
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

            state.total = NetworkInterfaceCounters(
                receivedBytes: state.total.receivedBytes &+ delta(from: state.raw.receivedBytes, to: counters.receivedBytes),
                sentBytes: state.total.sentBytes &+ delta(from: state.raw.sentBytes, to: counters.sentBytes)
            )
            state.raw = counters
            states[name] = state
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
        return NetworkCounterTotals(receivedBytes: totalReceived, sentBytes: totalSent)
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
