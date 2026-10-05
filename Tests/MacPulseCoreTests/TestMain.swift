import Foundation

private var failures = 0

func expect(_ condition: @autoclosure () -> Bool, _ description: String) {
    if condition() {
        print("PASS: \(description)")
    } else {
        failures += 1
        fputs("FAIL: \(description)\n", stderr)
    }
}

func expectNear(_ actual: Double?, _ expected: Double, _ description: String) {
    guard let actual else {
        failures += 1
        fputs("FAIL: \(description) (missing value)\n", stderr)
        return
    }
    expect(abs(actual - expected) < 0.001, description)
}

func finishTests() -> Never {
    if failures == 0 {
        print("All tests passed.")
        exit(EXIT_SUCCESS)
    }
    fputs("\(failures) test(s) failed.\n", stderr)
    exit(EXIT_FAILURE)
}
