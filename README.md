# HingeAngleForge 🔥

**Real-time MacBook lid angle protractor with a cyber/hacker aesthetic — built with pure Swift + IOKit, no Xcode required.**

![macOS](https://img.shields.io/badge/macOS-12.0+-black?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-5.7+-F05138?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-00CC66)

## 📐 What It Does

Reads the **real-time lid hinge angle** from your MacBook's internal HID sensor (`VID 0x05AC, PID 0x8104`) and displays it as a glowing neon protractor with raw hex telemetry.

- **0.01° precision** via centidegree decoding (ReportID 7)
- **250ms polling** for smooth real-time updates
- **Zero dependencies** — pure Swift + IOKit + SwiftUI
- **No Xcode required** — builds with `swiftc` + `codesign`

## 🖥 Compatibility

| Model | Status |
|---|---|
| MacBook Pro 16" 2019 (16,1) | ✅ Verified |
| MacBook Pro with Touch Bar | ✅ Expected |
| MacBook Air (2018+) | ⚠️ Untested |
| Apple Silicon Macs | ⚠️ Untested (should work) |

> The app targets the internal USB HID device with Product ID `0x8104`. If your Mac has this sensor, it will work.

## 🚀 Quick Start

```bash
# Clone
git clone https://github.com/YOUR_USERNAME/HingeAngleForge.git
cd HingeAngleForge/HingeAngleForge

# Build
chmod +x build_native.sh
./build_native.sh

# Run
open ./build/HingeAngleForge.app
```

### ⚠️ First Launch — Input Monitoring Permission

macOS requires Input Monitoring access for HID sensor reading:

1. Go to **System Settings → Privacy & Security → Input Monitoring**
2. Click **"+"** and navigate to `build/HingeAngleForge.app`
3. Toggle it **ON**
4. **Quit and relaunch** the app

## 🏗 Architecture

```
HingeAngleForge/
├── LidAngleMonitor.swift   # IOKit HID raw report decoder
├── ContentView.swift       # SwiftUI cyber protractor UI
├── HingeAngleApp.swift     # App entry point
├── Info.plist              # Bundle metadata
├── App.entitlements        # Security capabilities
└── build_native.sh         # Zero-Xcode build script
```

### Decoded Apple Lid Sensor Protocol (PID 0x8104)

| ReportID | Bytes | Bits | Range | Usage |
|---|---|---|---|---|
| 1 | 3 | 9 | 0-360 | Integer angle (degrees) |
| **7** | **5** | **50** | **0-36000** | **Centidegrees** (÷100) |
| 2 | 2 | 8 | -1..0 | Connection state |
| 3 | 6 | 32 | 0..2B | Timestamp |
| 4 | 2 | 8 | 0-3 | Orientation mode |
| 5 | 2 | 8 | 0-2 | Sensor state |

### Why Raw Reports?

Apple's `0x8104` sensor uses a **proprietary HID report format** — all elements report `UsagePage=0, Usage=0` at the element level. The standard `IOHIDManagerRegisterInputValueCallback` returns zeros. We use `IOHIDDeviceRegisterInputReportCallback` + `IOHIDDeviceGetReport` to read raw bytes and decode them ourselves.

## 📸 Screenshot

The UI features:
- Neon green protractor arc with angular gradient
- Animated needle tracking lid angle
- CRT-style scanline overlay
- Pulsing status LEDs
- Raw hex telemetry dump
- Real-time debug log

## 🔧 Build Requirements

- macOS 12.0+
- Swift 5.7+ (Xcode Command Line Tools)
- `codesign` (included with macOS)

```bash
# Install Xcode CLI tools if needed
xcode-select --install
```

## 📜 License

MIT — see [LICENSE](LICENSE)
