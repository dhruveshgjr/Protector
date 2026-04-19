import Foundation
import IOKit.hid

/// LidAngleMonitor: Production-grade IOKit HID interface for Apple Lid Angle Sensor.
///
/// Device: VID 0x05AC, PID 0x8104 (MacBookPro16,1 and similar)
///
/// Decoded Report Protocol:
///   ReportID 1 (3 bytes): [RID] [angle_low] [angle_high_bit]
///     → 9-bit angle = byte[1] | ((byte[2] & 0x01) << 8), range 0-360°
///     → Element: UP=0x20 U=0x47F (Sensor: Hinge Angle), 9 bits, [0..360]
///
///   ReportID 7 (5 bytes): [RID] [lo] [hi] [0x00] [0x00]
///     → 16-bit centidegrees = byte[1] | (byte[2] << 8), range 0-36000
///     → Element: UP=0x20 U=0x545, 50 bits, [0..36000]
///     → Divide by 100 for degrees with 2 decimal precision
///
///   ReportID 2: Sensor connection state (-1 or 0)
///   ReportID 3: Timestamp / counter (32 bits)
///   ReportID 4: Orientation mode (0-3)
///   ReportID 5: Sensor state (0-2)
///   ReportID 8: Unknown flag (0-2)
final class LidAngleMonitor: ObservableObject {

    enum AppMode {
        case protractor
        case vinyl
        case theremin
    }

    @Published var currentAngle: Int = 0
    @Published var preciseAngle: Double = 0.0
    @Published var sensorStatus: String = "Initializing HID Manager..."
    @Published var rawHexLog: String = ""
    @Published var debugLog: [String] = []

    @Published var thereminEngine: ThereminEngine?
    @Published var currentMode: AppMode = .protractor

    @Published var angleVelocity: Double = 0.0
    private var lastAngleTime: TimeInterval = 0.0
    private var lastAngleForVelocity: Double = 0.0

    private var hidManager: IOHIDManager?
    private var matchedDevice: IOHIDDevice?
    private var isRunning = false
    private var pollTimer: Timer?

    private var reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 256)
    private let reportBufferSize = 256

    private let targetVendorID: Int = 0x05AC
    private let targetProductID: Int = 0x8104

    init() {
        reportBuffer.initialize(repeating: 0, count: reportBufferSize)
        setupHIDManager()
        Task {
            let engine = ThereminEngine()
            _ = engine.startMIDI()
            await MainActor.run {
                self.thereminEngine = engine
                self.log("🎹 ThereminEngine initialized | MIDI source active")
            }
        }
    }

    deinit {
        stop()
        thereminEngine?.stopMIDI()
        thereminEngine?.stopSynth()
        reportBuffer.deallocate()
    }

    func setMode(_ mode: AppMode) {
        currentMode = mode
        log("🔄 Mode switched to: \(mode)")

        switch mode {
        case .theremin:
            try? thereminEngine?.startSynth()
        case .vinyl:
            thereminEngine?.stopSynth()
        case .protractor:
            thereminEngine?.stopSynth()
        }
    }

    private func log(_ msg: String) {
        let ts = Date().formatted(date: .omitted, time: .standard)
        let entry = "[\(ts)] \(msg)"
        DispatchQueue.main.async {
            self.debugLog.append(entry)
            if self.debugLog.count > 60 {
                self.debugLog.removeFirst()
            }
        }
    }

    private func setupHIDManager() {
        guard !isRunning else { return }

        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = hidManager else {
            sensorStatus = "❌ Failed to create IOHIDManager"
            return
        }

        let matchingDict: [String: Any] = [
            kIOHIDVendorIDKey as String: targetVendorID,
            kIOHIDProductIDKey as String: targetProductID
        ]
        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.deviceMatchedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.deviceRemovedCallback, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnSuccess {
            sensorStatus = "✅ HID Manager Open. Scanning..."
            isRunning = true
            log("HID Manager opened ✅")
        } else {
            sensorStatus = "❌ Open Failed: \(String(format: "0x%08X", result))"
            log("HID Manager FAILED: \(result)")
        }
    }

    private static let deviceMatchedCallback: IOHIDDeviceCallback = { context, result, sender, device in
        guard let context = context else { return }
        let selfRef = Unmanaged<LidAngleMonitor>.fromOpaque(context).takeUnretainedValue()

        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "LidAngleSensor"
        selfRef.log("🔗 Device attached: \(name)")

        DispatchQueue.main.async {
            selfRef.matchedDevice = device
            selfRef.sensorStatus = "🔗 \(name) — reading raw reports"
        }

        IOHIDDeviceRegisterInputReportCallback(
            device,
            selfRef.reportBuffer,
            selfRef.reportBufferSize,
            LidAngleMonitor.rawReportCallback,
            context
        )

        selfRef.log("📡 Raw report callback active")

        selfRef.startPolling(device: device)
    }

    private static let deviceRemovedCallback: IOHIDDeviceCallback = { context, result, sender, device in
        guard let context = context else { return }
        let selfRef = Unmanaged<LidAngleMonitor>.fromOpaque(context).takeUnretainedValue()
        selfRef.log("⚠️ Device removed")
        DispatchQueue.main.async {
            selfRef.matchedDevice = nil
            selfRef.sensorStatus = "⚠️ Sensor disconnected"
            selfRef.pollTimer?.invalidate()
        }
    }

    private static let rawReportCallback: IOHIDReportCallback = { context, result, sender, reportType, reportID, report, reportLength in
        guard let context = context, reportType == kIOHIDReportTypeInput else { return }
        let selfRef = Unmanaged<LidAngleMonitor>.fromOpaque(context).takeUnretainedValue()
        selfRef.processReport(reportID: reportID, report: report, length: reportLength, source: "IRQ")
    }

    private func processReport(reportID: UInt32, report: UnsafePointer<UInt8>, length: Int, source: String) {
        switch reportID {
        case 1:
            guard length >= 2 else { return }
            let angleLow = Int(report[0])
            let angleHigh: Int
            if length >= 3 {
                angleHigh = Int(report[1]) & 0x01
            } else {
                angleHigh = 0
            }
            let angle = angleLow | (angleHigh << 8)

            DispatchQueue.main.async {
                self.currentAngle = angle
                self.sensorStatus = "📐 \(angle)° [\(source)]"
                self.rawHexLog = self.hexDump(report: report, length: length, prefix: "ID1")
            }

        case 7:
            guard length >= 3 else { return }
            let lo = report[0], hi = report[1]
            let centideg = Int(lo) | (Int(hi) << 8)
            let precise = Double(centideg) / 100.0
            let hex = String(format: "%02X %02X", lo, hi)

            let now = Date().timeIntervalSinceReferenceDate
            let deltaTime = max(0.001, now - lastAngleTime)
            let angleDelta = precise - lastAngleForVelocity
            let velocity = angleDelta / deltaTime
            lastAngleTime = now
            lastAngleForVelocity = precise

            DispatchQueue.main.async {
                self.preciseAngle = precise
                self.currentAngle = Int(precise.rounded())
                self.sensorStatus = "📐 \(Int(precise.rounded()))° [\(source)]"
                self.rawHexLog = "[\(Date().formatted(date: .omitted, time: .standard))] ID7: \(hex) → \(Int(precise.rounded()))°"
                self.angleVelocity = velocity

                if self.currentMode == .theremin {
                    self.thereminEngine?.updateAngle(precise, velocity: velocity)
                }
            }

        default:
            break
        }
    }

    private func hexDump(report: UnsafePointer<UInt8>, length: Int, prefix: String) -> String {
        var hex: [String] = []
        for i in 0..<min(length, 8) {
            hex.append(String(format: "%02X", report[i]))
        }
        let ts = Date().formatted(date: .omitted, time: .standard)
        return "[\(ts)] \(prefix): \(hex.joined(separator: " ")) | \(currentAngle)°"
    }

    private func startPolling(device: IOHIDDevice) {
        log("🔄 Polling started (250ms)")
        DispatchQueue.main.async {
            self.pollTimer?.invalidate()
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                self?.pollAngle(device: device)
            }
        }
    }

    private func pollAngle(device: IOHIDDevice) {
        var len1 = reportBufferSize
        let r1 = IOHIDDeviceGetReport(device, kIOHIDReportTypeInput, 1, reportBuffer, &len1)
        if r1 == kIOReturnSuccess && len1 >= 2 {
            processReport(reportID: 1, report: reportBuffer.advanced(by: 1), length: len1 - 1, source: "POLL")
        }

        var len7 = reportBufferSize
        let r7 = IOHIDDeviceGetReport(device, kIOHIDReportTypeInput, 7, reportBuffer, &len7)
        if r7 == kIOReturnSuccess && len7 >= 3 {
            processReport(reportID: 7, report: reportBuffer.advanced(by: 1), length: len7 - 1, source: "POLL")
        }
    }

    private func stop() {
        guard isRunning, let manager = hidManager else { return }
        pollTimer?.invalidate()
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        isRunning = false
        sensorStatus = "⏹️ Stopped"
    }
}