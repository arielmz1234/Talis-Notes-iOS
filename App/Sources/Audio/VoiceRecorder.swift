import AVFoundation
import Observation
import TaliCore

/// A finished recording: its file in the audio folder, length and sound wave.
struct Recorded: Equatable {
  var file: String
  var durationMs: Int64
  var wave: [Int]
}

/// Records and plays voice memos (Android's `VoiceRecorder`): one recording and one playback at a
/// time; the levels while recording and where playback is are observed by the memo views.
@MainActor @Observable
final class VoiceRecorder {
  static let sampleSeconds = 0.05
  private static let minMs: Int64 = 500

  private(set) var recording = false
  /// How loud the recording has been, one reading per [sampleSeconds] (0..1), for the live wave.
  private(set) var levels: [Float] = []
  private(set) var elapsedMs: Int64 = 0

  /// The memo playing or paused, or nil.
  private(set) var current: String?
  private(set) var playing = false
  /// How far into [current] playback is, 0..1.
  private(set) var progress: Float = 0
  private(set) var positionMs: Int64 = 0

  @ObservationIgnored private var recorder: AVAudioRecorder?
  @ObservationIgnored private var file: URL?
  @ObservationIgnored private var startedAt = Date()
  @ObservationIgnored private var sampling: Timer?
  @ObservationIgnored private var player: AVAudioPlayer?
  @ObservationIgnored private var ticking: Timer?
  @ObservationIgnored private let finished = Finished()

  var dir: URL { AppFiles.folders.audio }

  /// Starts recording; false if the microphone couldn't be opened.
  func start() -> Bool {
    if recording { return true }
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothA2DP])
      try session.setActive(true)
    } catch {
      return false
    }
    let out = dir.appendingPathComponent("memo-\(UUID().uuidString.lowercased()).m4a")
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96_000,
    ]
    guard let r = try? AVAudioRecorder(url: out, settings: settings) else { return false }
    r.isMeteringEnabled = true
    guard r.record() else {
      try? FileManager.default.removeItem(at: out)
      return false
    }
    stopPlayback()
    recorder = r
    file = out
    startedAt = Date()
    levels = []
    elapsedMs = 0
    recording = true
    sampling = Timer.scheduledTimer(withTimeInterval: Self.sampleSeconds, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.sample() }
    }
    return true
  }

  private func sample() {
    guard let r = recorder, recording else { return }
    r.updateMeters()
    levels.append(Self.level(decibels: r.peakPower(forChannel: 0)))
    elapsedMs = Int64(Date().timeIntervalSince(startedAt) * 1000)
  }

  /// Stops and keeps the recording; nil if there was nothing worth keeping (under half a second).
  func stop() -> Recorded? {
    guard let r = recorder else { return nil }
    let out = file
    let duration = Int64(Date().timeIntervalSince(startedAt) * 1000)
    endRecording()
    r.stop()
    guard let out, duration >= Self.minMs, FileManager.default.fileExists(atPath: out.path) else {
      if let out { try? FileManager.default.removeItem(at: out) }
      return nil
    }
    return Recorded(file: out.lastPathComponent, durationMs: duration, wave: MemoRow.waveOf(levels))
  }

  /// Stops and throws the recording away.
  func cancel() {
    guard let r = recorder else { return }
    endRecording()
    r.stop()
    r.deleteRecording()
  }

  private func endRecording() {
    recording = false
    sampling?.invalidate()
    sampling = nil
    recorder = nil
    file = nil
  }

  // MARK: Playback

  /// Plays [memo] (from where it was paused if it's the current one); false if it can't be read.
  @discardableResult
  func play(_ memo: MemoRow) -> Bool {
    if recording { return false }
    if current == memo.id, let p = player {
      if progress >= 0.999 { p.currentTime = 0 }
      guard p.play() else { return false }
      playing = true
      tick()
      return true
    }
    stopPlayback()
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    try? AVAudioSession.sharedInstance().setActive(true)
    guard let p = try? AVAudioPlayer(contentsOf: dir.appendingPathComponent(memo.file)) else { return false }
    finished.onEnd = { [weak self] in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.playing = false
        self.progress = 1
        self.positionMs = Int64((self.player?.duration ?? 0) * 1000)
      }
    }
    p.delegate = finished
    guard p.play() else { return false }
    player = p
    current = memo.id
    playing = true
    progress = 0
    positionMs = 0
    tick()
    return true
  }

  func pause() {
    player?.pause()
    playing = false
  }

  /// Jumps to [fraction] of the memo playing (or paused).
  func seek(_ fraction: Float) {
    guard let p = player, p.duration > 0 else { return }
    let to = Double(min(max(fraction, 0), 1)) * p.duration
    p.currentTime = to
    positionMs = Int64(to * 1000)
    progress = Float(to / p.duration)
  }

  func stopPlayback() {
    ticking?.invalidate()
    ticking = nil
    player?.stop()
    player = nil
    current = nil
    playing = false
    progress = 0
    positionMs = 0
  }

  /// Follows playback about once a frame while it plays.
  private func tick() {
    ticking?.invalidate()
    ticking = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.playing, let p = self.player else {
          self?.ticking?.invalidate()
          return
        }
        if p.duration > 0 {
          self.positionMs = Int64(p.currentTime * 1000)
          self.progress = Float(min(max(p.currentTime / p.duration, 0), 1))
        }
      }
    }
  }

  /// Stops everything; a recording going on is kept and returned.
  func release() -> Recorded? {
    let kept = recording ? stop() : nil
    stopPlayback()
    return kept
  }

  /// A microphone reading as a loudness that looks right as a bar (0..1): Android's curve over its
  /// 0..32767 amplitude, here from the meter's decibels.
  static func level(decibels: Float) -> Float {
    let amp = 32767 * powf(10, min(decibels, 0) / 20)
    return min(max(logf(1 + amp / 200) / logf(1 + 32767 / 200), 0), 1)
  }

  private final class Finished: NSObject, AVAudioPlayerDelegate {
    nonisolated(unsafe) var onEnd: () -> Void = {}
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { onEnd() }
  }
}
