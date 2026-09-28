public enum MetricCounter {
    public static func unsignedValue(fromSigned32 value: Int32) -> UInt64 {
        UInt64(UInt32(bitPattern: value))
    }
}
