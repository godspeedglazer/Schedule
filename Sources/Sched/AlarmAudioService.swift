import AppKit
import AVFoundation
import Foundation

@MainActor
final class AlarmAudioService {
    static let shared = AlarmAudioService()
    nonisolated static let maximumManagedSoundDuration: TimeInterval = 5

    private var systemPlayers: [UUID: NSSound] = [:]
    private var filePlayers: [UUID: AVAudioPlayer] = [:]
    private var previewSystemSound: NSSound?
    private var previewFilePlayer: AVAudioPlayer?

    private let fallbackSystemSounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink",
    ]

    private init() {}

    func availableSystemSounds() -> [AlarmSound] {
        var names = Set(fallbackSystemSounds)
        let fm = FileManager.default
        let folders = [
            URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true),
            URL(fileURLWithPath: "/Library/Sounds", isDirectory: true),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds", isDirectory: true),
        ]
        let extensions = Set(["aiff", "aif", "wav", "caf", "m4a", "mp3"])
        for folder in folders {
            guard let files = try? fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for file in files where extensions.contains(file.pathExtension.lowercased()) {
                names.insert(file.deletingPathExtension().lastPathComponent)
            }
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { .system(name: $0) }
    }

    func availableImportedSounds() -> [AlarmSound] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: ScheduleStore.soundsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return files
            .filter { !$0.hasDirectoryPath }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map { .imported(fileName: $0.lastPathComponent) }
    }

    func allSelectableSounds() -> [AlarmSound] {
        availableSystemSounds() + availableImportedSounds()
    }

    func resolvedURL(for sound: AlarmSound) -> URL? {
        switch sound {
        case .none, .system:
            return nil
        case .imported(let fileName):
            return ScheduleStore.soundsDirectory.appendingPathComponent(fileName)
        case .externalFile(let path):
            return URL(fileURLWithPath: path)
        }
    }

    func duration(of sound: AlarmSound) -> TimeInterval? {
        guard let url = resolvedURL(for: sound),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        return player.duration
    }

    func importShortSound(from sourceURL: URL) throws -> AlarmSound {
        let player = try AVAudioPlayer(contentsOf: sourceURL)
        guard player.duration <= Self.maximumManagedSoundDuration else {
            throw AlarmAudioError.soundTooLong(player.duration)
        }

        let fm = FileManager.default
        try fm.createDirectory(at: ScheduleStore.soundsDirectory, withIntermediateDirectories: true)
        let destination = uniqueDestination(for: sourceURL)
        try fm.copyItem(at: sourceURL, to: destination)
        return .imported(fileName: destination.lastPathComponent)
    }

    func linkExternalAudio(from url: URL) throws -> AlarmSound {
        _ = try AVAudioPlayer(contentsOf: url)
        return .externalFile(path: url.standardizedFileURL.path)
    }

    func removeImportedSound(_ sound: AlarmSound) throws {
        guard case .imported(let fileName) = sound else { return }
        let url = ScheduleStore.soundsDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func preview(_ sound: AlarmSound, volume: Double? = nil) {
        stopPreview()
        let level = Float(min(1, max(0, volume ?? ScheduleStore.shared.store.soundVolume)))
        switch sound {
        case .none:
            return
        case .system(let name):
            let sound = configuredSystemSound(named: name, volume: level, loops: false)
            sound?.play()
            previewSystemSound = sound

        case .imported, .externalFile:
            guard let url = resolvedURL(for: sound), let player = try? AVAudioPlayer(contentsOf: url) else {
                let fallback = configuredSystemSound(named: "Glass", volume: level, loops: false)
                fallback?.play()
                previewSystemSound = fallback
                return
            }
            player.volume = level
            player.numberOfLoops = 0
            player.prepareToPlay()
            player.play()
            previewFilePlayer = player
        }
    }

    func play(for alarm: SchedAlarm) {
        guard ScheduleStore.shared.store.playSoundOnAlert else { return }
        stop(alarmID: alarm.id)

        let preferences = ScheduleStore.shared.store
        let choice = alarm.sound ?? preferences.defaultSound
        let level = Float(min(1, max(0, preferences.soundVolume)))
        let shouldRepeat = preferences.repeatSoundOnAlert

        switch choice {
        case .none:
            return
        case .system(let name):
            guard let sound = configuredSystemSound(named: name, volume: level, loops: shouldRepeat) else { return }
            sound.play()
            systemPlayers[alarm.id] = sound

        case .imported, .externalFile:
            guard let url = resolvedURL(for: choice), let player = try? AVAudioPlayer(contentsOf: url) else {
                guard let fallback = configuredSystemSound(named: "Glass", volume: level, loops: shouldRepeat) else { return }
                fallback.play()
                systemPlayers[alarm.id] = fallback
                return
            }
            player.volume = level
            player.numberOfLoops = shouldRepeat ? -1 : 0
            player.prepareToPlay()
            player.play()
            filePlayers[alarm.id] = player
        }
    }

    func stop(alarmID: UUID) {
        systemPlayers.removeValue(forKey: alarmID)?.stop()
        filePlayers.removeValue(forKey: alarmID)?.stop()
    }

    func stopAll() {
        for player in systemPlayers.values { player.stop() }
        for player in filePlayers.values { player.stop() }
        systemPlayers.removeAll()
        filePlayers.removeAll()
        stopPreview()
    }

    private func stopPreview() {
        previewSystemSound?.stop()
        previewSystemSound = nil
        previewFilePlayer?.stop()
        previewFilePlayer = nil
    }

    private func configuredSystemSound(named name: String, volume: Float, loops: Bool) -> NSSound? {
        let sound = NSSound(named: NSSound.Name(name)) ?? NSSound(named: NSSound.Name("Glass"))
        sound?.volume = volume
        sound?.loops = loops
        return sound
    }

    private func uniqueDestination(for sourceURL: URL) -> URL {
        let fm = FileManager.default
        let originalStem = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        var candidate = ScheduleStore.soundsDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        var counter = 2
        while fm.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(originalStem) \(counter)" : "\(originalStem) \(counter).\(ext)"
            candidate = ScheduleStore.soundsDirectory.appendingPathComponent(name)
            counter += 1
        }
        return candidate
    }
}

enum AlarmAudioError: LocalizedError {
    case soundTooLong(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .soundTooLong(let duration):
            return String(
                format: "Imported alert sounds must be %.0f seconds or shorter. This file is %.1f seconds. Use linked looping audio for longer files.",
                AlarmAudioService.maximumManagedSoundDuration,
                duration
            )
        }
    }
}
