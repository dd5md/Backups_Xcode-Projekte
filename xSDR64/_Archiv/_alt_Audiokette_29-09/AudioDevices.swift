//
//  AudioDevices.swift
//  xSDR64 – aus xHost64 übernommen (Stand 29.09.2026, Commit 919f4a2)
//
//  Kleine Helfer rund um CoreAudio – die "Sprache", in der macOS über Audio-Geräte redet.
//

import CoreAudio
import Foundation

/// Ein Audio-Gerät, wie macOS es kennt (z.B. Fireface UCX II)
struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID        // interne Nummer (kann sich nach Neustart ändern)
    let uid: String              // feste Kennung – die merken wir uns
    let name: String
    let inputChannels: Int
    let outputChannels: Int
}

enum AudioDevices {

    /// Alle Geräte mit mindestens einem Ein- oder Ausgang
    static func all() -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            let ins = channelCount(id, scope: kAudioDevicePropertyScopeInput)
            let outs = channelCount(id, scope: kAudioDevicePropertyScopeOutput)
            guard ins + outs > 0 else { return nil }
            return AudioDevice(id: id,
                               uid: string(id, kAudioDevicePropertyDeviceUID) ?? "\(id)",
                               name: string(id, kAudioObjectPropertyName) ?? "Gerät \(id)",
                               inputChannels: ins,
                               outputChannels: outs)
        }
    }

    /// Anzahl Kanäle in einer Richtung (Eingang oder Ausgang)
    static func channelCount(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                   alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    /// Name eines Kanals, wie das Gerät ihn meldet (z.B. "Analog 5"). Kanal ab 1 gezählt.
    static func channelName(_ id: AudioDeviceID, scope: AudioObjectPropertyScope, channel: Int) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyElementName,
            mScope: scope,
            mElement: UInt32(channel))
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr,
              let value = name?.takeRetainedValue() as String?,
              !value.isEmpty else { return nil }
        return value
    }

    /// Text-Eigenschaft eines Geräts lesen (Name, UID)
    static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    /// Ganzzahl-Eigenschaft lesen (Latenz, Sicherheitsabstand …)
    static func uint32(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector,
                       scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return value
    }

    /// Welche der üblichen Sampleraten kann das Gerät?
    static func sampleRates(_ id: AudioDeviceID) -> [Double] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return [48_000] }
        var ranges = [AudioValueRange](repeating: AudioValueRange(),
                                       count: Int(size) / MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &ranges) == noErr else { return [48_000] }
        let common: [Double] = [44_100, 48_000, 88_200, 96_000, 176_400, 192_000]
        let possible = common.filter { rate in
            ranges.contains { $0.mMinimum <= rate && rate <= $0.mMaximum }
        }
        return possible.isEmpty ? [48_000] : possible
    }

    /// Samplerate direkt am Gerät einstellen
    static func setSampleRate(_ id: AudioDeviceID, _ rate: Double) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value = Float64(rate)
        AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float64>.size), &value)
    }

    /// Puffergröße direkt am Gerät einstellen
    static func setBufferSize(_ id: AudioDeviceID, frames: UInt32) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value = frames
        AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    /// Ungefähre Gesamtverzögerung Eingang → Ausgang in Millisekunden:
    /// Gerätelatenz + Sicherheitsabstand (je Richtung) + 2 × Puffer
    static func roundTripLatencyMS(_ id: AudioDeviceID, buffer: UInt32, rate: Double) -> Double {
        let input = uint32(id, kAudioDevicePropertyLatency, scope: kAudioDevicePropertyScopeInput)
                  + uint32(id, kAudioDevicePropertySafetyOffset, scope: kAudioDevicePropertyScopeInput)
        let output = uint32(id, kAudioDevicePropertyLatency, scope: kAudioDevicePropertyScopeOutput)
                   + uint32(id, kAudioDevicePropertySafetyOffset, scope: kAudioDevicePropertyScopeOutput)
        let frames = Double(input) + Double(output) + 2 * Double(buffer)
        return rate > 0 ? frames / rate * 1000 : 0
    }
}
