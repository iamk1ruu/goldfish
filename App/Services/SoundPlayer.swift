import AVFoundation
import SwiftUI
import UIKit
import GoldfishCore

/// The app's sounds. The files are 8-bit WAVs made by `tools/sound/build-sfx.mjs`.
///
/// Nothing here sounds like a failure buzzer. A Mix-up is a curious wobble, a Gap is a bubble and a
/// wrong Your Turn answer only turns the card over.
enum SoundCue: String, CaseIterable {
    /// Finn got a question right, or you did.
    case correct
    /// Finn picked the wrong option from a sentence in your lesson.
    case mixUp = "mixup"
    /// Your lesson didn't cover it.
    case gap
    /// An option chosen.
    case select
    /// A card turned over.
    case flip
    /// Finn got every question in a quiz.
    case cheer
    /// A concept reached Mastered.
    case mastered
    /// The first teaching of the day lit the fire.
    case fire
    /// A teach-off or friend request sent.
    case send

    var haptic: Haptic {
        switch self {
        case .correct, .cheer, .mastered, .fire: return .success
        case .select, .flip, .send: return .tap
        case .mixUp, .gap: return .soft
        }
    }

    enum Haptic {
        case success, tap, soft
    }
}

/// Plays the cues. Uses the ambient audio category, so the silent switch mutes it and music keeps playing.
@MainActor
final class SoundPlayer {
    private var players: [SoundCue: AVAudioPlayer] = [:]
    private var sessionReady = false
    private let tap = UIImpactFeedbackGenerator(style: .light)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let notify = UINotificationFeedbackGenerator()

    func play(_ cue: SoundCue, sound: Bool, haptic: Bool) {
        if sound, let player = player(for: cue) {
            player.currentTime = 0
            player.play()
        }
        if haptic {
            switch cue.haptic {
            case .success: notify.notificationOccurred(.success)
            case .tap: tap.impactOccurred()
            case .soft: soft.impactOccurred()
            }
        }
    }

    private func player(for cue: SoundCue) -> AVAudioPlayer? {
        if let player = players[cue] {
            return player
        }
        if !sessionReady {
            sessionReady = true
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        guard let url = Bundle.main.url(forResource: cue.rawValue, withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url)
        else { return nil }
        player.volume = 0.7
        player.prepareToPlay()
        players[cue] = player
        return player
    }
}

extension AppModel {
    /// Plays a cue if the student has sounds or haptics on. Screenshot mode stays silent.
    func cue(_ cue: SoundCue) {
        guard !launch.screenshotMode else { return }
        sounds.play(cue, sound: data.preferences.sounds, haptic: data.preferences.haptics)
    }
}

/// Plays a sound for each fish answer as it arrives. Answers from the cache arrive together,
/// so only the newest one sounds.
private struct VerdictSounds: ViewModifier {
    @Environment(AppModel.self) private var model
    let session: QuizSession

    func body(content: Content) -> some View {
        content.onChange(of: session.answers.count) { old, new in
            guard new > old, let answer = session.answers.last, !answer.cached else { return }
            switch answer.verdict {
            case .correct: model.cue(.correct)
            case .mixUp: model.cue(.mixUp)
            case .gap: model.cue(.gap)
            }
        }
    }
}

extension View {
    func verdictSounds(session: QuizSession) -> some View {
        modifier(VerdictSounds(session: session))
    }
}
