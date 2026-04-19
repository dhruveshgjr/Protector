import SwiftUI

extension LidAngleMonitor.AppMode {
    var displayName: String {
        switch self {
        case .protractor: return "PROTRACTOR"
        case .vinyl: return "CLAMSHELL_DJ"
        case .theremin: return "THEREMIN"
        }
    }
}

struct ContentView: View {
    @StateObject private var monitor = LidAngleMonitor()

    @State private var selectedMode: LidAngleMonitor.AppMode = .protractor

    private let bgBlack = Color.black
    private let neonGreen = Color(red: 0.0, green: 1.0, blue: 0.4)
    private let neonRed = Color(red: 1.0, green: 0.1, blue: 0.2)
    private let gridGray = Color(white: 0.15)
    private let neonCyan = Color(red: 0.0, green: 0.9, blue: 1.0)

    @State private var pulseAnimation = false
    @State private var scanlineOffset: CGFloat = 0

    var body: some View {
        ZStack {
            bgBlack.edgesIgnoringSafeArea(.all)

            GeometryReader { geo in
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, neonGreen.opacity(0.03), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 80)
                    .offset(y: scanlineOffset)
                    .onAppear {
                        withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                            scanlineOffset = geo.size.height
                        }
                    }
            }
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                headerBar

                Divider()
                    .background(neonGreen.opacity(0.3))

                modeSelector

                if selectedMode == .theremin {
                    thereminPanel
                }

                protractorView
                    .padding(.vertical, 12)

                Divider()
                    .background(neonGreen.opacity(0.3))

                telemetryPanel
            }
        }
    }

    private var headerBar: some View {
        HStack {
            Circle()
                .fill(monitor.currentAngle > 0 ? neonGreen : neonRed)
                .frame(width: 6, height: 6)
                .shadow(color: monitor.currentAngle > 0 ? neonGreen : neonRed, radius: 6)
                .opacity(pulseAnimation ? 0.4 : 1.0)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever()) {
                        pulseAnimation = true
                    }
                }

            Text("DARKFORGE-X")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(neonGreen)

            Text("//")
                .foregroundColor(gridGray)
                .font(.system(size: 13, design: .monospaced))

            Text("HINGE_TELEMETRY")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(neonGreen.opacity(0.6))

            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(neonRed)
                    .frame(width: 5, height: 5)
                    .shadow(color: neonRed, radius: 3)
                    .opacity(pulseAnimation ? 0.3 : 1.0)
                Text("LIVE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(neonRed)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(gridGray.opacity(0.4))
    }

    private var modeSelector: some View {
        HStack(spacing: 4) {
            ForEach([LidAngleMonitor.AppMode.protractor, .vinyl, .theremin], id: \.self) { mode in
                Button(action: {
                    selectedMode = mode
                    monitor.setMode(mode)
                }) {
                    Text(mode.displayName)
                        .font(.system(size: 10, weight: selectedMode == mode ? .bold : .regular, design: .monospaced))
                        .foregroundColor(selectedMode == mode ? neonGreen : .gray)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(selectedMode == mode ? neonGreen.opacity(0.15) : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(selectedMode == mode ? neonGreen.opacity(0.5) : Color.clear, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var thereminPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("THEREMIN_MODE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(neonCyan)

                Spacer()

                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(monitor.thereminEngine?.isMidiActive == true ? neonGreen : neonRed)
                            .frame(width: 6, height: 6)
                        Text("MIDI")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.gray)
                    }

                    Button(action: {
                        monitor.thereminEngine?.toggleSynth()
                    }) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(monitor.thereminEngine?.isSynthActive == true ? neonGreen : neonRed)
                                .frame(width: 6, height: 6)
                            Text("SYNTH")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                VStack(alignment: .leading) {
                    Text(monitor.thereminEngine?.currentNote ?? "--")
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundColor(neonGreen)

                    Text(String(format: "%.1f Hz", monitor.thereminEngine?.currentFrequency ?? 0))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(neonGreen.opacity(0.6))
                }

                Spacer()

                SpectrumView(data: monitor.thereminEngine?.spectrumData ?? [])
                    .frame(width: 150, height: 50)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text("PITCH_BEND")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.gray)
                    Text("0–16383")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(neonCyan)
                }

                VStack(alignment: .leading) {
                    Text("MODULATION")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.gray)
                    Text("CC1")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(neonCyan)
                }

                Spacer()

                Text("DAW: HingeAngleForge")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(neonGreen.opacity(0.7))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(gridGray.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(neonCyan.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
    }

    private var protractorView: some View {
        ZStack {
            ProtractorArc(angle: 360)
                .stroke(gridGray.opacity(0.5), style: StrokeStyle(lineWidth: 22, lineCap: .round))

            ForEach(0..<13) { i in
                let tickAngle = Double(i) * 30.0
                let isMajor = i % 3 == 0
                TickMark(angle: tickAngle, isMajor: isMajor, color: neonGreen)
            }

            ProtractorArc(angle: CGFloat(monitor.currentAngle))
                .stroke(
                    AngularGradient(
                        colors: [neonCyan, neonGreen, neonGreen],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(Double(monitor.currentAngle) - 90)
                    ),
                    style: StrokeStyle(lineWidth: 22, lineCap: .round)
                )
                .shadow(color: neonGreen.opacity(0.6), radius: 12)
                .animation(.easeInOut(duration: 0.3), value: monitor.currentAngle)

            NeedleLine(angle: CGFloat(monitor.currentAngle))
                .stroke(neonCyan, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .shadow(color: neonCyan, radius: 4)
                .animation(.easeInOut(duration: 0.3), value: monitor.currentAngle)

            VStack(spacing: 2) {
                Text("\(monitor.currentAngle)°")
                    .font(.system(size: 56, weight: .heavy, design: .monospaced))
                    .foregroundColor(neonGreen)
                    .shadow(color: neonGreen.opacity(0.8), radius: 10)
                    .animation(.easeInOut(duration: 0.15), value: monitor.currentAngle)

                Text("DEGREES")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(neonGreen.opacity(0.4))
                    .kerning(4)

                Rectangle()
                    .fill(neonGreen.opacity(0.3))
                    .frame(width: 60, height: 1)
                    .padding(.top, 4)

                Text("LID_ANGLE_SENSOR")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.gray)
                    .padding(.top, 2)
            }
        }
        .frame(width: 280, height: 280)
    }

    private var telemetryPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("SYS_LOG")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(neonGreen.opacity(0.5))
                Text("//")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(gridGray)
                Text("RAW_HEX_DUMP")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(neonGreen.opacity(0.3))
                Spacer()
            }

            Text(monitor.rawHexLog.isEmpty ? "> WAITING_FOR_INTERRUPT..." : "> \(monitor.rawHexLog)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(monitor.rawHexLog.isEmpty ? neonGreen.opacity(0.3) : neonGreen)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(gridGray.opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(neonGreen.opacity(0.1), lineWidth: 1)
                        )
                )

            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
                Text(monitor.sensorStatus)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.8))
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(monitor.debugLog.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(line.contains("⭐") ? neonCyan : neonGreen.opacity(0.6))
                                .id(idx)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(neonGreen.opacity(0.15), lineWidth: 1)
                        )
                )
                .onChange(of: monitor.debugLog.count) { _ in
                    if let last = monitor.debugLog.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }
}

struct ProtractorArc: Shape {
    var angle: CGFloat

    var animatableData: CGFloat {
        get { angle }
        set { angle = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - 14

        path.addArc(center: center,
                    radius: radius,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(Double(angle) - 90),
                    clockwise: false)
        return path
    }
}

struct NeedleLine: Shape {
    var angle: CGFloat

    var animatableData: CGFloat {
        get { angle }
        set { angle = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let innerRadius: CGFloat = 50
        let outerRadius = min(rect.width, rect.height) / 2 - 6

        let radians = (Double(angle) - 90) * .pi / 180
        let startPoint = CGPoint(
            x: center.x + innerRadius * CGFloat(cos(radians)),
            y: center.y + innerRadius * CGFloat(sin(radians))
        )
        let endPoint = CGPoint(
            x: center.x + outerRadius * CGFloat(cos(radians)),
            y: center.y + outerRadius * CGFloat(sin(radians))
        )

        path.move(to: startPoint)
        path.addLine(to: endPoint)
        return path
    }
}

struct TickMark: View {
    let angle: Double
    let isMajor: Bool
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2 - 14
            let tickLength: CGFloat = isMajor ? 12 : 6
            let radians = (angle - 90) * .pi / 180

            let outerPoint = CGPoint(
                x: center.x + radius * CGFloat(cos(radians)),
                y: center.y + radius * CGFloat(sin(radians))
            )
            let innerPoint = CGPoint(
                x: center.x + (radius - tickLength) * CGFloat(cos(radians)),
                y: center.y + (radius - tickLength) * CGFloat(sin(radians))
            )

            Path { path in
                path.move(to: outerPoint)
                path.addLine(to: innerPoint)
            }
            .stroke(color.opacity(isMajor ? 0.5 : 0.2), lineWidth: isMajor ? 2 : 1)
        }
    }
}

struct SpectrumView: View {
    let data: [Float]

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(0..<min(data.count, 64), id: \.self) { i in
                    let height = max(0, min(CGFloat(data[i]), 1.0)) * geo.size.height
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0, green: 1, blue: 0.4), Color(red: 0, green: 0.8, blue: 1)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: max(1, geo.size.width / CGFloat(min(data.count, 64)) - 1))
                        .frame(height: height)
                }
            }
        }
    }
}