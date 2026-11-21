//
//  StammtischNoise.swift
//  german-ai-flashcards
//
//  The optional background noise under the tutor's voice in Stammtisch mode (roadmap item 8, FSI
//  lesson 10: "coping with background noise"). Soft brown noise with a slow swell, generated on the
//  fly, so there is no recording to bundle. Plays only while the tutor speaks, so it never reaches
//  the microphone.
//

import AVFoundation
import Foundation

@MainActor
final class StammtischNoise {
    static let shared = StammtischNoise()

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var running = false

    /// Quiet enough to be under the voice, loud enough to make listening work.
    var volume: Float = 0.12

    func start() {
        guard !running else { return }
        if source == nil {
            let rate = engine.outputNode.inputFormat(forBus: 0).sampleRate
            let format = AVAudioFormat(standardFormatWithSampleRate: rate > 0 ? rate : 44_100, channels: 1)!
            let node = Self.makeNoiseNode(format: format)
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            source = node
        }
        engine.mainMixerNode.outputVolume = volume
        do {
            try engine.start()
            running = true
        } catch {
            running = false
        }
    }

    /// Built outside the main actor: the render block runs on the audio thread.
    private nonisolated static func makeNoiseNode(format: AVAudioFormat) -> AVAudioSourceNode {
        let state = NoiseState(rate: format.sampleRate)
        return AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            for frame in 0..<Int(frameCount) {
                let sample = state.next()
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
                }
            }
            return noErr
        }
    }

    func stop() {
        guard running else { return }
        engine.pause()
        running = false
    }
}

/// The generator's running state, touched only by the audio thread.
private nonisolated final class NoiseState: @unchecked Sendable {
    private var brown: Float = 0
    private var phase: Double = 0
    private let rate: Double

    init(rate: Double) { self.rate = rate > 0 ? rate : 44_100 }

    func next() -> Float {
        // Brown noise: integrated white noise, leaking back toward zero.
        brown = (brown + Float.random(in: -1...1) * 0.02) * 0.998
        // A slow swell, like a room's murmur rising and falling.
        phase += 0.35 / rate
        let swell = Float(0.75 + 0.25 * sin(2 * .pi * phase))
        return brown * 3.5 * swell
    }
}
