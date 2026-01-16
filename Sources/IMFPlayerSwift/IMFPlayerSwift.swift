import Foundation
import DBOPLWrapper

#if canImport(AVFoundation)
import AVFoundation
#endif

// MARK: - Little-endian helpers

@inline(__always)
func readLEUInt16(_ data: Data, _ offset: Int) -> UInt16 {
    let b0 = UInt16(data[offset])
    let b1 = UInt16(data[offset + 1])
    return b0 | (b1 << 8)
}

// MARK: - IMF parsing

struct IMFEvent {
    let reg: UInt8
    let value: UInt8
    let delayTicks: UInt16
}

enum IMFParser {
    /// Parses Type-0 and Type-1 IMF.
    /// - Type-1: first uint16 is byte length of payload following it.
    /// - Type-0: first uint16 is 0; payload is whole file.
    static func parse(url: URL) throws -> [IMFEvent] {
        let fileData = try Data(contentsOf: url)
        guard fileData.count >= 4 else {
            throw NSError(domain: "IMFPlayerSwift", code: 1, userInfo: [NSLocalizedDescriptionKey: "File too small to be IMF."])
        }

        let declaredSize = Int(readLEUInt16(fileData, 0))
        let payloadStart = 2
        let payload: Data

        if declaredSize == 0 {
            payload = fileData // Type-0: includes the leading size word as 0; we treat entire file as payload
        } else {
            let end = min(payloadStart + declaredSize, fileData.count)
            payload = fileData.subdata(in: payloadStart..<end)
        }

        // Events are 4 bytes: reg (1), value (1), delay (2)
        let count = payload.count / 4
        guard count > 0 else {
            throw NSError(domain: "IMFPlayerSwift", code: 2, userInfo: [NSLocalizedDescriptionKey: "No IMF events found."])
        }

        var events: [IMFEvent] = []
        events.reserveCapacity(count)

        var i = 0
        while i + 3 < payload.count {
            let reg = payload[i]
            let val = payload[i + 1]
            let delay = readLEUInt16(payload, i + 2)
            events.append(IMFEvent(reg: reg, value: val, delayTicks: delay))
            i += 4
        }

        return events
    }
}

// MARK: - Sequencer

final class IMFSequencer {
    private let events: [IMFEvent]
    private var index: Int = 0

    /// Tick counter (like alTimeCount in the C version).
    private var tickCount: UInt32 = 0

    /// Time at which the current event should fire.
    private var nextEventTick: UInt32 = 0

    init(events: [IMFEvent]) {
        self.events = events
        self.index = 0
        self.tickCount = 0
        self.nextEventTick = 0
    }

    func reset() {
        index = 0
        tickCount = 0
        nextEventTick = 0
    }

    /// Advance by one IMF tick; emits any events whose time is due.
    func advanceTick(apply: (_ reg: UInt8, _ value: UInt8) -> Void) {
        // Emit all events scheduled for now or earlier.
        while nextEventTick <= tickCount {
            let ev = events[index]
            apply(ev.reg, ev.value)

            // Schedule next event time relative to *current* tickCount, matching the original logic.
            nextEventTick = tickCount + UInt32(ev.delayTicks)

            index += 1
            if index >= events.count {
                // Loop like the original player.
                index = 0
                tickCount = 0
                nextEventTick = 0
                break
            }
        }

        tickCount &+= 1
    }
}

// MARK: - OPL wrapper

final class OPL {
    private var handle: OpaquePointer?

    init(sampleRate: Int) {
        self.handle = OpaquePointer(dbopl_create(Int32(sampleRate)))
    }

    deinit {
        if let h = handle { dbopl_destroy(UnsafeMutableRawPointer(h)) }
    }

    func write(reg: UInt8, value: UInt8) {
        guard let h = handle else { return }
        dbopl_write(UnsafeMutableRawPointer(h), reg, value)
    }

    func generate(frames: Int, into buffer: UnsafeMutablePointer<Int32>) {
        guard let h = handle else { return }
        dbopl_generate(UnsafeMutableRawPointer(h), Int32(frames), buffer)
    }
}

// MARK: - Audio engine

// MARK: - Player (macOS)

#if canImport(AVFoundation)
final class IMFPlayer {
    private let imfClockRate: Int
    private let mixerRate: Int

    private let sequencer: IMFSequencer
    private let opl: OPL

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode!

    private let samplesPerTick: Int
    private var samplesUntilTick: Int

    // Scratch buffer for mono Int32 from OPL.
    private var monoScratch: [Int32] = []

    init(events: [IMFEvent], imfClockRate: Int, mixerRate: Int) {
        self.imfClockRate = imfClockRate
        self.mixerRate = mixerRate
        self.samplesPerTick = max(1, mixerRate / imfClockRate)
        self.samplesUntilTick = self.samplesPerTick

        self.sequencer = IMFSequencer(events: events)
        self.opl = OPL(sampleRate: mixerRate)

        setupAudioGraph()
    }

    private func setupAudioGraph() {
        // Use Float32 stereo for simplicity.
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(mixerRate), channels: 2) else {
            fatalError("Unable to create audio format")
        }

        // Render callback: fill Float32 non-interleaved buffers.
        sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }

            let frames = Int(frameCount)
            if self.monoScratch.count < frames {
                self.monoScratch = Array(repeating: 0, count: frames)
            }

            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard abl.count >= 2 else { return noErr }

            let left = abl[0]
            let right = abl[1]

            let lptr = left.mData!.bindMemory(to: Float.self, capacity: frames)
            let rptr = right.mData!.bindMemory(to: Float.self, capacity: frames)

            var produced = 0
            while produced < frames {
                let run = min(frames - produced, self.samplesUntilTick)

                self.monoScratch.withUnsafeMutableBufferPointer { scratch in
                    self.opl.generate(frames: run, into: scratch.baseAddress!)

                    // Convert to float and duplicate to stereo.
                    // dbopl returns 32-bit ints roughly within 16-bit range.
                    for i in 0..<run {
                        var s = scratch[i]
                        if s > 32767 { s = 32767 }
                        if s < -32768 { s = -32768 }
                        let f = Float(s) / 32768.0
                        lptr[produced + i] = f
                        rptr[produced + i] = f
                    }
                }

                produced += run
                self.samplesUntilTick -= run

                if self.samplesUntilTick == 0 {
                    // One IMF tick elapsed.
                    self.sequencer.advanceTick { reg, value in
                        self.opl.write(reg: reg, value: value)
                    }
                    self.samplesUntilTick = self.samplesPerTick
                }
            }

            return noErr
        }

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
        } catch {
            fatalError("Failed to start AVAudioEngine: \(error)")
        }
    }

    func stop() {
        engine.stop()
    }
}

#else

/// Stub to keep the package buildable on non-Apple platforms.
/// On macOS, AVFoundation is used to stream samples to the system output.
final class IMFPlayer {
    init(events: [IMFEvent], imfClockRate: Int, mixerRate: Int) {
        fputs("This build of IMFPlayerSwift requires macOS (AVFoundation).\n", stderr)
        exit(1)
    }
    func stop() {}
}

#endif

// MARK: - CLI

func printUsage(_ exe: String) {
    print("Usage:")
    print("  \(exe) <imffile>")
    print("  \(exe) <imffile> <imf clock rate>")
    print("  \(exe) <imffile> <imf clock rate> <mixer sample rate>")
    print("\nAll rates are in Hz.")
    print("Defaults: <imf clock rate> = 560, <mixer sample rate> = 49716")
    print("\nExamples:")
    print("  \(exe) K4T01.imf")
    print("  \(exe) K4T01.imf 560")
    print("  \(exe) track01.wlf 700 44100")
    print("  \(exe) DUKINA.IMF 280")
}

let args = CommandLine.arguments
let exe = (args.first as NSString?)?.lastPathComponent ?? "IMFPlayerSwift"

guard args.count == 2 || args.count == 3 || args.count == 4 else {
    printUsage(exe)
    exit(1)
}

let filePath = args[1]
let imfClockRate = args.count >= 3 ? (Int(args[2]) ?? 560) : 560
let mixerRate = args.count >= 4 ? (Int(args[3]) ?? 49716) : 49716

let url = URL(fileURLWithPath: filePath)

guard FileManager.default.fileExists(atPath: url.path) else {
    fputs("File does not exist: \(url.path)\n", stderr)
    exit(2)
}

do {
    let events = try IMFParser.parse(url: url)

    print("Playing: \(url.lastPathComponent)")
    print("IMF clock rate: \(imfClockRate) Hz")
    print("Mixer rate: \(mixerRate) Hz")
    print("Press Enter to quit...")

    let player = IMFPlayer(events: events, imfClockRate: imfClockRate, mixerRate: mixerRate)
    _ = readLine()
    player.stop()
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(3)
}
