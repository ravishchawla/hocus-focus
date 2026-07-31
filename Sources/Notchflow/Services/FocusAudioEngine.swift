import AVFoundation
import Combine
import Foundation

enum FocusPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case calm
    case rain
    case study
    case jazz
    case cozy
    case loFi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .calm: "Calm"
        case .rain: "Rain"
        case .study: "Study"
        case .jazz: "Jazz"
        case .cozy: "Cozy"
        case .loFi: "Lo-Fi"
        }
    }

    var subtitle: String {
        switch self {
        case .calm: "Soft air and warm, drifting tones"
        case .rain: "Steady rainfall with distant droplets"
        case .study: "Grounded brown noise and a quiet pulse"
        case .jazz: "Late-night chords with brushed rhythm"
        case .cozy: "Fireplace crackle and warm room tone"
        case .loFi: "Dusty beats, vinyl texture, mellow chords"
        }
    }

    var systemImage: String {
        switch self {
        case .calm: "leaf.fill"
        case .rain: "cloud.rain.fill"
        case .study: "book.closed.fill"
        case .jazz: "music.note"
        case .cozy: "flame.fill"
        case .loFi: "headphones"
        }
    }

    fileprivate var dspIndex: Int {
        switch self {
        case .calm: 0
        case .rain: 1
        case .study: 2
        case .jazz: 3
        case .cozy: 4
        case .loFi: 5
        }
    }
}

@MainActor
final class FocusAudioEngine: ObservableObject {
    @Published private(set) var activePreset: FocusPreset
    @Published private(set) var isPlaying = false
    @Published var volume: Float {
        didSet {
            let sanitized = volume.isFinite ? min(max(volume, 0), 1) : Self.defaultVolume
            if sanitized != volume {
                volume = sanitized
            }
            dspState?.setVolume(sanitized)
        }
    }
    @Published private(set) var lastError: String?

    private static let defaultVolume: Float = 0.45
    private static let idleDelayNanoseconds: UInt64 = 320_000_000

    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var dspState: ProceduralDSPState?
    private var idleStopTask: Task<Void, Never>?

    init() {
        activePreset = .calm
        volume = Self.defaultVolume
        lastError = nil
    }

    deinit {
        idleStopTask?.cancel()
        dspState?.setPlaying(false)
        engine?.stop()
    }

    func select(_ preset: FocusPreset) {
        guard activePreset != preset else { return }
        activePreset = preset
        dspState?.setPreset(index: preset.dspIndex)
    }

    func toggle() {
        isPlaying ? stop() : play()
    }

    func play() {
        guard !isPlaying else { return }

        idleStopTask?.cancel()
        idleStopTask = nil
        lastError = nil

        do {
            prepareEngineIfNeeded()
            guard let engine, let dspState else { return }
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
            dspState.setPlaying(true)
            isPlaying = true
        } catch {
            dspState?.setPlaying(false)
            isPlaying = false
            lastError = "Focus audio could not start: \(error.localizedDescription)"
        }
    }

    func stop() {
        guard isPlaying else { return }

        dspState?.setPlaying(false)
        isPlaying = false
        idleStopTask?.cancel()
        idleStopTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.idleDelayNanoseconds)
            } catch {
                return
            }

            guard let self, !self.isPlaying else { return }
            self.engine?.pause()
            self.idleStopTask = nil
        }
    }

    private func prepareEngineIfNeeded() {
        guard engine == nil else { return }

        let audioEngine = AVAudioEngine()
        let hardwareFormat = audioEngine.outputNode.inputFormat(forBus: 0)
        let sampleRate = hardwareFormat.sampleRate.isFinite && hardwareFormat.sampleRate > 0
            ? hardwareFormat.sampleRate
            : 48_000
        guard let renderFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        ) else {
            lastError = "Focus audio could not create an output format."
            return
        }
        let state = ProceduralDSPState(
            sampleRate: sampleRate,
            presetIndex: activePreset.dspIndex,
            volume: volume
        )
        let renderBlock: AVAudioSourceNodeRenderBlock = {
            isSilence,
            _,
            frameCount,
            audioBufferList
            in
            isSilence.pointee = false
            state.render(
                frameCount: frameCount,
                audioBufferList: UnsafeMutableAudioBufferListPointer(audioBufferList)
            )
            return noErr
        }
        let node = AVAudioSourceNode(format: renderFormat, renderBlock: renderBlock)

        audioEngine.attach(node)
        audioEngine.connect(node, to: audioEngine.mainMixerNode, format: renderFormat)
        audioEngine.mainMixerNode.outputVolume = 1
        engine = audioEngine
        sourceNode = node
        dspState = state
    }
}

private final class ProceduralDSPState: @unchecked Sendable {
    private static let presetCount = 6

    private struct Controls: Sendable {
        var presetIndex: Int
        var volume: Float
        var isPlaying: Bool
    }

    private struct StereoSample {
        var left: Float
        var right: Float
    }

    private struct Oscillator {
        var phase: Float = 0

        mutating func sine(frequency: Float, inverseSampleRate: Float) -> Float {
            phase += max(frequency, 0) * inverseSampleRate
            if phase >= 1 { phase -= 1 }
            return sin(phase * 2 * .pi)
        }

        mutating func triangle(frequency: Float, inverseSampleRate: Float) -> Float {
            phase += max(frequency, 0) * inverseSampleRate
            if phase >= 1 { phase -= 1 }
            return 1 - 4 * abs(phase - 0.5)
        }
    }

    private struct NoiseGenerator {
        var state: UInt32

        mutating func bipolar() -> Float {
            state ^= state << 13
            state ^= state >> 17
            state ^= state << 5
            return Float(state & 0x00FF_FFFF) / 8_388_608 - 1
        }

        mutating func unit() -> Float {
            (bipolar() + 1) * 0.5
        }
    }

    private let inverseSampleRate: Float
    private let gainSmoothing: Float
    private let presetSmoothing: Float
    private let controlsLock = NSLock()
    private var sharedControls: Controls

    // This copy, all oscillator/filter state, and the weights are touched only by
    // AVAudioEngine's serialized render callback.
    private var renderControls: Controls
    private var currentGain: Float = 0
    private var weights: [Float]

    private var calmNoise = NoiseGenerator(state: 0x0C41_9A31)
    private var calmAir: Float = 0
    private var calmTone = Oscillator(phase: 0.17)
    private var calmUpper = Oscillator(phase: 0.63)
    private var calmBreath = Oscillator(phase: 0.42)
    private var calmPan = Oscillator(phase: 0.81)

    private var rainNoise = NoiseGenerator(state: 0x71A4_31E5)
    private var rainLeftBody: Float = 0
    private var rainRightBody: Float = 0
    private var rainDropEnvelope: Float = 0
    private var rainDropPan: Float = 0
    private var rainDropFrequency: Float = 1_450
    private var rainDrop = Oscillator(phase: 0.28)

    private var studyNoise = NoiseGenerator(state: 0x57D0_10B1)
    private var studyBrownLeft: Float = 0
    private var studyBrownRight: Float = 0
    private var studyTone = Oscillator(phase: 0.34)
    private var studyPulse = Oscillator(phase: 0.74)

    private var jazzNoise = NoiseGenerator(state: 0x4A22_9C87)
    private var jazzRoot = Oscillator(phase: 0.05)
    private var jazzThird = Oscillator(phase: 0.29)
    private var jazzFifth = Oscillator(phase: 0.51)
    private var jazzSeventh = Oscillator(phase: 0.78)
    private var jazzBass = Oscillator(phase: 0.12)
    private var jazzChordPhase: Float = 0
    private var jazzChordIndex = 0
    private var jazzBeatPhase: Float = 0
    private var jazzBrushEnvelope: Float = 0
    private var jazzBrushFilter: Float = 0

    private var cozyNoise = NoiseGenerator(state: 0xC02A_7E15)
    private var cozyRoomLeft: Float = 0
    private var cozyRoomRight: Float = 0
    private var cozyCrackleEnvelope: Float = 0
    private var cozyCracklePan: Float = 0
    private var cozyHum = Oscillator(phase: 0.48)

    private var loFiNoise = NoiseGenerator(state: 0x10F1_5EED)
    private var loFiRoot = Oscillator(phase: 0.07)
    private var loFiThird = Oscillator(phase: 0.36)
    private var loFiFifth = Oscillator(phase: 0.66)
    private var loFiKick = Oscillator(phase: 0)
    private var loFiWow = Oscillator(phase: 0.21)
    private var loFiBeatPhase: Float = 0
    private var loFiBeatIndex = 0
    private var loFiChordIndex = 0
    private var loFiKickEnvelope: Float = 0
    private var loFiSnareEnvelope: Float = 0
    private var loFiCrackleEnvelope: Float = 0
    private var loFiVinylFilter: Float = 0

    init(sampleRate: Double, presetIndex: Int, volume: Float) {
        inverseSampleRate = 1 / Float(sampleRate)
        gainSmoothing = Float(1 - exp(-1 / (sampleRate * 0.026)))
        presetSmoothing = Float(1 - exp(-1 / (sampleRate * 0.14)))

        let controls = Controls(
            presetIndex: presetIndex,
            volume: volume,
            isPlaying: false
        )
        sharedControls = controls
        renderControls = controls
        weights = Array(repeating: 0, count: Self.presetCount)
        weights[presetIndex] = 1
    }

    func setPreset(index: Int) {
        controlsLock.lock()
        sharedControls.presetIndex = min(max(index, 0), Self.presetCount - 1)
        controlsLock.unlock()
    }

    func setVolume(_ volume: Float) {
        controlsLock.lock()
        sharedControls.volume = min(max(volume, 0), 1)
        controlsLock.unlock()
    }

    func setPlaying(_ isPlaying: Bool) {
        controlsLock.lock()
        sharedControls.isPlaying = isPlaying
        controlsLock.unlock()
    }

    func render(
        frameCount: AVAudioFrameCount,
        audioBufferList: UnsafeMutableAudioBufferListPointer
    ) {
        guard frameCount > 0, !audioBufferList.isEmpty else { return }

        // Never wait on the main thread from the real-time callback. A missed
        // control update is picked up one render quantum later.
        if controlsLock.try() {
            renderControls = sharedControls
            controlsLock.unlock()
        }

        let requestedPreset = renderControls.presetIndex
        let requestedGain = renderControls.isPlaying ? renderControls.volume * 0.16 : 0
        let frames = Int(frameCount)

        for frame in 0..<frames {
            currentGain += (requestedGain - currentGain) * gainSmoothing

            var mixedLeft: Float = 0
            var mixedRight: Float = 0

            for presetIndex in weights.indices {
                let target: Float = presetIndex == requestedPreset ? 1 : 0
                weights[presetIndex] += (target - weights[presetIndex]) * presetSmoothing

                let weight = weights[presetIndex]
                if weight > 0.0001 || target > 0 {
                    let sample = renderPreset(index: presetIndex)
                    mixedLeft += sample.left * weight
                    mixedRight += sample.right * weight
                }
            }

            let left = min(max(mixedLeft * currentGain, -1), 1)
            let right = min(max(mixedRight * currentGain, -1), 1)
            write(
                left: left,
                right: right,
                frame: frame,
                audioBufferList: audioBufferList
            )
        }
    }

    private func write(
        left: Float,
        right: Float,
        frame: Int,
        audioBufferList: UnsafeMutableAudioBufferListPointer
    ) {
        var outputChannel = 0
        for bufferIndex in audioBufferList.indices {
            let buffer = audioBufferList[bufferIndex]
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                outputChannel += Int(buffer.mNumberChannels)
                continue
            }

            let channelCount = Int(buffer.mNumberChannels)
            for channel in 0..<channelCount {
                data[frame * channelCount + channel] = outputChannel.isMultiple(of: 2)
                    ? left
                    : right
                outputChannel += 1
            }
        }
    }

    private func renderPreset(index: Int) -> StereoSample {
        switch index {
        case 0: renderCalm()
        case 1: renderRain()
        case 2: renderStudy()
        case 3: renderJazz()
        case 4: renderCozy()
        default: renderLoFi()
        }
    }

    private func renderCalm() -> StereoSample {
        let white = calmNoise.bipolar()
        calmAir += (white - calmAir) * 0.004

        let breath = calmBreath.sine(frequency: 0.072, inverseSampleRate: inverseSampleRate)
        let pan = calmPan.sine(frequency: 0.029, inverseSampleRate: inverseSampleRate)
        let fundamental = calmTone.sine(
            frequency: 110 + breath * 1.8,
            inverseSampleRate: inverseSampleRate
        )
        let upper = calmUpper.sine(
            frequency: 164.81 + breath * 1.1,
            inverseSampleRate: inverseSampleRate
        )
        let air = calmAir * 3.3 * (0.88 + breath * 0.12)
        let bed = air * 0.36 + fundamental * 0.13 + upper * 0.075

        return StereoSample(
            left: bed * (1 - pan * 0.09),
            right: bed * (1 + pan * 0.09)
        )
    }

    private func renderRain() -> StereoSample {
        let whiteLeft = rainNoise.bipolar()
        let whiteRight = rainNoise.bipolar()
        rainLeftBody += (whiteLeft - rainLeftBody) * 0.13
        rainRightBody += (whiteRight - rainRightBody) * 0.13

        rainDropEnvelope *= 0.99905
        if rainNoise.unit() > 0.999985 {
            rainDropEnvelope = 0.7 + rainNoise.unit() * 0.3
            rainDropFrequency = 1_050 + rainNoise.unit() * 1_250
            rainDropPan = rainNoise.bipolar() * 0.75
        }
        let drop = rainDrop.sine(
            frequency: rainDropFrequency,
            inverseSampleRate: inverseSampleRate
        ) * rainDropEnvelope * 0.22

        let left = rainLeftBody * 0.82 + (whiteLeft - rainLeftBody) * 0.17
        let right = rainRightBody * 0.82 + (whiteRight - rainRightBody) * 0.17
        return StereoSample(
            left: left + drop * (1 - rainDropPan),
            right: right + drop * (1 + rainDropPan)
        )
    }

    private func renderStudy() -> StereoSample {
        let whiteLeft = studyNoise.bipolar()
        let whiteRight = studyNoise.bipolar()
        studyBrownLeft += (whiteLeft - studyBrownLeft) * 0.0018
        studyBrownRight += (whiteRight - studyBrownRight) * 0.0018

        let pulse = studyPulse.sine(frequency: 0.105, inverseSampleRate: inverseSampleRate)
        let tone = studyTone.sine(
            frequency: 73.42 + pulse * 0.45,
            inverseSampleRate: inverseSampleRate
        ) * (0.065 + pulse * 0.008)

        return StereoSample(
            left: studyBrownLeft * 4.1 + tone,
            right: studyBrownRight * 4.1 + tone * 0.96
        )
    }

    private func renderJazz() -> StereoSample {
        jazzChordPhase += 0.125 * inverseSampleRate
        if jazzChordPhase >= 1 {
            jazzChordPhase -= 1
            jazzChordIndex = (jazzChordIndex + 1) % 4
        }

        jazzBeatPhase += 1.2 * inverseSampleRate
        if jazzBeatPhase >= 1 {
            jazzBeatPhase -= 1
            jazzBrushEnvelope = jazzBeatPhase < 0.01 ? 0.72 : 0.52
        }
        jazzBrushEnvelope *= 0.9984

        let frequencies: (Float, Float, Float, Float)
        switch jazzChordIndex {
        case 0: frequencies = (130.81, 164.81, 196.00, 246.94)
        case 1: frequencies = (110.00, 130.81, 164.81, 196.00)
        case 2: frequencies = (146.83, 174.61, 220.00, 261.63)
        default: frequencies = (98.00, 123.47, 146.83, 174.61)
        }

        let root = jazzRoot.sine(frequency: frequencies.0, inverseSampleRate: inverseSampleRate)
        let third = jazzThird.sine(frequency: frequencies.1, inverseSampleRate: inverseSampleRate)
        let fifth = jazzFifth.sine(frequency: frequencies.2, inverseSampleRate: inverseSampleRate)
        let seventh = jazzSeventh.sine(frequency: frequencies.3, inverseSampleRate: inverseSampleRate)
        let bass = jazzBass.sine(frequency: frequencies.0 * 0.5, inverseSampleRate: inverseSampleRate)

        let brushNoise = jazzNoise.bipolar()
        jazzBrushFilter += (brushNoise - jazzBrushFilter) * 0.22
        let brush = (brushNoise - jazzBrushFilter) * jazzBrushEnvelope * 0.13
        let chordLeft = root * 0.11 + third * 0.075 + fifth * 0.085 + seventh * 0.065
        let chordRight = root * 0.085 + third * 0.095 + fifth * 0.07 + seventh * 0.085

        return StereoSample(
            left: chordLeft + bass * 0.09 + brush * 0.85,
            right: chordRight + bass * 0.075 + brush
        )
    }

    private func renderCozy() -> StereoSample {
        let whiteLeft = cozyNoise.bipolar()
        let whiteRight = cozyNoise.bipolar()
        cozyRoomLeft += (whiteLeft - cozyRoomLeft) * 0.006
        cozyRoomRight += (whiteRight - cozyRoomRight) * 0.006

        cozyCrackleEnvelope *= 0.91
        if cozyNoise.unit() > 0.99972 {
            cozyCrackleEnvelope = 0.45 + cozyNoise.unit() * 0.55
            cozyCracklePan = cozyNoise.bipolar() * 0.8
        }
        let crackle = cozyNoise.bipolar() * cozyCrackleEnvelope * 0.38
        let hum = cozyHum.sine(frequency: 82.41, inverseSampleRate: inverseSampleRate) * 0.055

        return StereoSample(
            left: cozyRoomLeft * 2.7 + hum + crackle * (1 - cozyCracklePan),
            right: cozyRoomRight * 2.7 + hum * 0.93 + crackle * (1 + cozyCracklePan)
        )
    }

    private func renderLoFi() -> StereoSample {
        loFiBeatPhase += 1.25 * inverseSampleRate
        if loFiBeatPhase >= 1 {
            loFiBeatPhase -= 1
            loFiBeatIndex = (loFiBeatIndex + 1) % 4
            if loFiBeatIndex == 0 {
                loFiChordIndex = (loFiChordIndex + 1) % 4
            }
            if loFiBeatIndex.isMultiple(of: 2) {
                loFiKickEnvelope = 1
            } else {
                loFiSnareEnvelope = 0.8
            }
        }

        loFiKickEnvelope *= 0.99925
        loFiSnareEnvelope *= 0.9965
        loFiCrackleEnvelope *= 0.9
        if loFiNoise.unit() > 0.99982 {
            loFiCrackleEnvelope = 0.35 + loFiNoise.unit() * 0.5
        }

        let baseFrequency: Float
        switch loFiChordIndex {
        case 0: baseFrequency = 130.81
        case 1: baseFrequency = 110.00
        case 2: baseFrequency = 87.31
        default: baseFrequency = 98.00
        }

        let wow = loFiWow.sine(frequency: 0.17, inverseSampleRate: inverseSampleRate)
        let pitchScale = 1 + wow * 0.0035
        let root = loFiRoot.triangle(
            frequency: baseFrequency * pitchScale,
            inverseSampleRate: inverseSampleRate
        )
        let third = loFiThird.triangle(
            frequency: baseFrequency * 1.25 * pitchScale,
            inverseSampleRate: inverseSampleRate
        )
        let fifth = loFiFifth.triangle(
            frequency: baseFrequency * 1.5 * pitchScale,
            inverseSampleRate: inverseSampleRate
        )
        let chord = root * 0.14 + third * 0.09 + fifth * 0.075

        let kickFrequency = 43 + loFiKickEnvelope * 38
        let kick = loFiKick.sine(
            frequency: kickFrequency,
            inverseSampleRate: inverseSampleRate
        ) * loFiKickEnvelope * 0.22

        let vinyl = loFiNoise.bipolar()
        loFiVinylFilter += (vinyl - loFiVinylFilter) * 0.035
        let hiss = (vinyl - loFiVinylFilter) * 0.035
        let snare = vinyl * loFiSnareEnvelope * 0.09
        let crackle = loFiNoise.bipolar() * loFiCrackleEnvelope * 0.22

        return StereoSample(
            left: chord + kick + snare * 0.8 + hiss + crackle * 0.7,
            right: chord * 0.94 + kick + snare + hiss * 0.9 + crackle
        )
    }
}
