import IOKit
import Foundation

/// Reader for the System Management Controller, the source of real chip
/// temperatures and fan speeds on the Mac. Uses the AppleSMC user client —
/// the same interface stats utilities use; read-only, nothing leaves the Mac.
final class SMCReader {
    static let shared = SMCReader()
    private var connection: io_connect_t = 0
    private var opened = false
    private let mutex = NSLock()
    /// False when the kernel refuses SMC commands (macOS 26+ blocks unsigned
    /// apps) — the UI reports sensor access as unavailable instead of "—".
    private(set) var readable = false

    private enum Command {
        static let open: UInt32 = 0
        static let close: UInt32 = 1
        static let readBytes: UInt8 = 5
        static let readKeyInfo: UInt8 = 9
    }
    private let smcSelector: UInt32 = 2

    private init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var connect: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connect) == KERN_SUCCESS else { return }
        connection = connect
        var outputCount: UInt32 = 0
        opened = IOConnectCallScalarMethod(connection, Command.open, nil, 0, nil, &outputCount) == KERN_SUCCESS
    }
    deinit { close() }
    func close() {
        guard opened else { return }
        var outputCount: UInt32 = 0
        IOConnectCallScalarMethod(connection, Command.close, nil, 0, nil, &outputCount)
        IOServiceClose(connection)
        connection = 0
        opened = false
    }

    // Wire structures, mirroring the AppleSMC user client layout exactly.
    private struct SMCVersion {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: (UInt8, UInt8) = (0, 0)
        var release: UInt16 = 0
    }
    private struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }
    private struct SMCKeyInfoData {
        var dataSize: IOByteCount = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }
    private struct SMCParamStruct {
        var key: UInt32 = 0
        var vers = SMCVersion()
        var plimit = SMCPLimitData()
        var keyInfo = SMCKeyInfoData()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
        ) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private func keyCode(_ key: String) -> UInt32 {
        let characters = Array(key.utf8.prefix(4))
        var value: UInt32 = 0
        for index in 0..<4 {
            value |= index < characters.count ? UInt32(characters[index]) << (24 - index * 8) : UInt32(0x20) << (24 - index * 8)
        }
        return value
    }

    private struct KeyReading {
        var type: UInt32
        var bytes: [UInt8]
    }

    private func read(key: String) -> KeyReading? {
        guard opened else { return nil }
        mutex.lock()
        defer { mutex.unlock() }
        var input = SMCParamStruct()
        input.key = keyCode(key)
        input.data8 = Command.readKeyInfo
        var output = SMCParamStruct()
        var inputSize = MemoryLayout<SMCParamStruct>.stride
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let status = IOConnectCallStructMethod(connection, smcSelector, &input, inputSize, &output, &outputSize)
        guard status == KERN_SUCCESS, output.result == KERN_SUCCESS else { return nil }
        readable = true
        let info = output.keyInfo
        guard info.dataSize > 0 else { return nil }

        var secondInput = SMCParamStruct()
        secondInput.key = keyCode(key)
        secondInput.keyInfo = info
        secondInput.data8 = Command.readBytes
        var secondOutput = SMCParamStruct()
        inputSize = MemoryLayout<SMCParamStruct>.stride
        outputSize = MemoryLayout<SMCParamStruct>.stride
        guard IOConnectCallStructMethod(connection, smcSelector, &secondInput, inputSize, &secondOutput, &outputSize) == KERN_SUCCESS,
              secondOutput.result == KERN_SUCCESS else { return nil }
        let tuple = secondOutput.bytes
        return KeyReading(type: info.dataType, bytes: withUnsafeBytes(of: tuple) { Array($0) })
    }

    private func decodeValue(_ reading: KeyReading) -> Double? {
        let bytes = reading.bytes
        switch reading.type {
        case 0x73703738: // "sp78" — signed 8.8 fixed point (temperatures)
            guard bytes.count >= 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case 0x66706532: // "fpe2" — fixed point / 256 (fan rpm)
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 256
        case 0x666C7420: // "flt "
            guard bytes.count >= 4 else { return nil }
            return Double(Float(bitPattern: UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24))
        case 0x75693820: // "ui8 "
            return Double(bytes.first ?? 0)
        case 0x75693332: // "ui32"
            guard bytes.count >= 4 else { return nil }
            return Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
        default:
            return nil
        }
    }

    // MARK: - Public helpers

    func temperature(forKey key: String) -> Double? {
        guard let reading = read(key: key), let value = decodeValue(reading), value > -20, value < 150 else { return nil }
        return value
    }

    func firstTemperature(keys: [String]) -> Double? {
        keys.lazy.compactMap { self.temperature(forKey: $0) }.first
    }

    func fanCount() -> Int {
        guard let reading = read(key: "FNum"), let value = decodeValue(reading) else { return 0 }
        return Int(value)
    }

    func fanRPM(index: Int) -> Double? {
        temperature(forKey: "F\(index)Ac")
    }

    /// The chip sensor differs per machine; probe the known keys in order.
    static let chipKeys = ["Tp01", "Tp09", "Tp05", "Tp04", "Tp0B", "Tp0D", "TpXT", "TC0P", "TC0D", "TC0E"]
    static let storageKeys = ["HdTe", "HddTe", "SnTh", "SDS1"]
}
