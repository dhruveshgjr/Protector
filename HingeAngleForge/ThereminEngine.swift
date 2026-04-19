import Foundation
import CoreMIDI
import AVFoundation
import Accelerate

final class ThereminEngine: ObservableObject {

    @Published var isMidiActive: Bool = false
    @Published var isSynthActive: Bool = false
    @Published var currentFrequency: Double = 0.0
    @Published var currentNote: String = "--"
    @Published var midiClient: MIDIClientRef = 0
    @Published var midiSource: MIDIEndpointRef = 0
    @Published var spectrumData: [Float] = Array(repeating: 0, count: 64)

    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var sampleRate: Double = 44100.0

    private var phase: Double = 0.0
    private var targetFrequency: Double = 220.0
    private var currentAmplitude: Float = 0.0
    private var targetAmplitude: Float = 0.0
    private var vibratoDepth: Double = 0.0
    private var vibratoRate: Double = 5.0
    private var vibratoPhase: Double = 0.0

    private var lastPitchBend: Int = 8192
    private var lastModulation: Int = 0
    private let midiChannel: UInt8 = 0

    private let minAngle: Double = 0.0
    private let maxAngle: Double = 130.0
    private let minFrequency: Double = 110.0
    private let maxFrequency: Double = 880.0

    private let amplitudeAttack: Float = 0.05
    private let amplitudeRelease: Float = 0.02

    deinit {
        stopMIDI()
        stopSynth()
    }

    func startMIDI() -> Bool {
        guard midiClient == 0 else { return true }

        let clientName = "HingeAngleForge" as CFString
        var client: MIDIClientRef = 0
        let status = MIDIClientCreate(clientName, nil, nil, &client)

        guard status == noErr else {
            print("❌ MIDI Client Create Failed: \(status)")
            return false
        }

        midiClient = client

        let sourceName = "HingeAngleForge Lid Controller" as CFString
        var source: MIDIEndpointRef = 0
        let createStatus = MIDISourceCreate(midiClient, sourceName, &source)

        guard createStatus == noErr else {
            print("❌ MIDI Source Create Failed: \(createStatus)")
            MIDIClientDispose(midiClient)
            midiClient = 0
            return false
        }

        midiSource = source
        isMidiActive = true
        print("✅ MIDI Source Created: 'HingeAngleForge Lid Controller'")
        print("🎹 Visible in DAWs as MIDI input device")

        sendAllNotesOff()

        return true
    }

    func stopMIDI() {
        guard midiClient != 0 else { return }

        sendAllNotesOff()
        MIDIEndpointDispose(midiSource)
        MIDIClientDispose(midiClient)

        midiSource = 0
        midiClient = 0
        isMidiActive = false
        print("⏹️ MIDI stopped")
    }

    private func sendMIDI(bytes: [UInt8]) {
        guard midiSource != 0 else { return }

        var packetList = MIDIPacketList()
        var packet = MIDIPacket()

        packet.timeStamp = mach_absolute_time()
        packet.length = UInt16(bytes.count)

        bytes.withUnsafeBytes { rawPtr in
            withUnsafeMutableBytes(of: &packet.data) { destPtr in
                destPtr.copyMemory(from: rawPtr)
            }
        }

        packetList.numPackets = 1
        packetList.packet = packet

        MIDIReceived(midiSource, &packetList)
    }

    func sendPitchBend(_ value: Int) {
        let clamped = max(0, min(16383, value))
        guard clamped != lastPitchBend else { return }

        let lsb = UInt8(clamped & 0x7F)
        let msb = UInt8((clamped >> 7) & 0x7F)

        sendMIDI(bytes: [0xE0 | midiChannel, lsb, msb])
        lastPitchBend = clamped
    }

    func sendModulation(_ value: Int) {
        let clamped = max(0, min(127, value))
        guard clamped != lastModulation else { return }

        sendMIDI(bytes: [0xB0 | midiChannel, 0x01, UInt8(clamped)])
        lastModulation = clamped
    }

    func sendNoteOn(note: UInt8, velocity: UInt8) {
        sendMIDI(bytes: [0x90 | midiChannel, note, velocity])
    }

    func sendNoteOff(note: UInt8) {
        sendMIDI(bytes: [0x80 | midiChannel, note, 0])
    }

    func sendAllNotesOff() {
        sendMIDI(bytes: [0xB0 | midiChannel, 0x7B, 0x00])
    }

    func startSynth() throws {
        if engine != nil {
            stopSynth()
        }

        engine = AVAudioEngine()
        guard let engine = engine else {
            throw NSError(domain: "ThereminEngine", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to create engine"])
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList in
            guard let self = self else { return 0 }
            return self.renderSynth(frameCount: frameCount, audioBufferList: audioBufferList)
        }

        engine.attach(sourceNode!)
        engine.connect(sourceNode!, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.5

        try engine.start()

        print("🔊 Theremin synth started")

        Task { @MainActor in
            self.isSynthActive = true
        }
    }

    func stopSynth() {
        engine?.stop()
        engine = nil
        sourceNode = nil

        Task { @MainActor in
            self.isSynthActive = false
        }

        print("⏹️ Synth stopped")
    }

    private func renderSynth(frameCount: UInt32, audioBufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)

        for frame in 0..<Int(frameCount) {
            if currentAmplitude < targetAmplitude {
                currentAmplitude = min(targetAmplitude, currentAmplitude + amplitudeAttack)
            } else {
                currentAmplitude = max(targetAmplitude, currentAmplitude - amplitudeRelease)
            }

            let vibratoOffset = vibratoDepth * sin(vibratoPhase)
            vibratoPhase += vibratoRate * 2.0 * .pi / sampleRate
            if vibratoPhase > 2.0 * .pi {
                vibratoPhase -= 2.0 * .pi
            }

            let freq = targetFrequency * (1.0 + vibratoOffset)

            let sample = sin(phase) * Double(currentAmplitude)
            phase += freq * 2.0 * .pi / sampleRate
            if phase > 2.0 * .pi {
                phase -= 2.0 * .pi
            }

            for buffer in ablPointer {
                if let floatData = buffer.mData?.bindMemory(to: Float.self, capacity: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size) {
                    floatData[frame] = Float(sample)
                }
            }
        }

        updateSpectrum(amplitude: currentAmplitude, frequency: targetFrequency)

        return noErr
    }

    private func updateSpectrum(amplitude: Float, frequency: Double) {
        let clampedFreq = max(20.0, min(frequency, sampleRate / 2.0 - 100.0))
        let binFloat: Double = clampedFreq / (sampleRate / 2.0)
        let fundamentalBin: Int = max(0, min(Int(binFloat * 64.0), 63))

        var newData: [Float] = Array(repeating: 0, count: 64)
        for i in 0..<64 {
            let dist: Double = abs(Double(i) - Double(fundamentalBin))
            let exponent: Double = -dist * 0.3
            let expVal: Float = Float(exp(exponent))
            let harmonic: Float = expVal * amplitude
            let noise: Float = Float.random(in: 0...0.05) * amplitude
            newData[i] = harmonic + noise
        }

        Task { @MainActor in
            self.spectrumData = newData
        }
    }

    func updateAngle(_ angle: Double, velocity: Double) {
        let clampedAngle = max(minAngle, min(angle, maxAngle))

        let ratio = (clampedAngle - minAngle) / (maxAngle - minAngle)
        let frequency = minFrequency * pow(maxFrequency / minFrequency, ratio)

        targetFrequency = frequency

        currentNote = frequencyToNoteName(frequency)

        let pitchBend = Int(ratio * 16383.0)
        sendPitchBend(pitchBend)

        let absVelocity = abs(velocity)
        let modulation = Int(min(127.0, absVelocity * 2.0))
        sendModulation(modulation)

        vibratoDepth = min(0.02, absVelocity * 0.0005)

        if absVelocity > 0.5 {
            targetAmplitude = min(0.8, Float(absVelocity / 50.0))
        } else {
            targetAmplitude = 0.3
        }

        Task { @MainActor in
            self.currentFrequency = frequency
            self.currentNote = frequencyToNoteName(frequency)
        }
    }

    private func frequencyToNoteName(_ freq: Double) -> String {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let midiNote = 69 + 12 * log2(freq / 440.0)
        let roundedNote = Int(round(midiNote))
        let noteIndex = roundedNote % 12
        let octave = roundedNote / 12 - 1
        return "\(noteNames[(noteIndex + 12) % 12])\(octave)"
    }

    func toggleSynth() {
        if isSynthActive {
            stopSynth()
        } else {
            try? startSynth()
        }
    }
}