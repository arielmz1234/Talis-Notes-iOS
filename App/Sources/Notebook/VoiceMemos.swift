import AVFoundation
import Observation
import SwiftUI
import TaliCore

/// The memo button, the bar it opens into, and the recording bar (Android's sizes, in points).
enum MemoSize {
  static let button: CGFloat = 48
  static let bar: CGFloat = 260
  static let gap: CGFloat = 12
  static let recorder: CGFloat = 404
  static let recorderHeight: CGFloat = 56
  /// Between two memos beside a page.
  static let spacing: CGFloat = button + 22
  static let open = 0.26
  static let close = 0.18
}

/// A notebook's voice memos (Android's memo parts of `NotebookViewModel`): the memos beside its
/// pages, the recording and the draft waiting to be added, which one is open, and where the page is
/// on screen. Adding, moving, naming and deleting are undo steps with the rest of the notebook.
@MainActor @Observable
final class MemoModel {
  let voice = VoiceRecorder()
  private(set) var memos: [MemoRow] = []
  var openMemo: String?
  /// Where the memo being recorded will sit if she adds it.
  private(set) var recordingAt: Pt?
  /// A finished recording not yet on the page: listen, delete or add.
  private(set) var draft: Recorded?
  /// The memo just added from a recording: it pops in.
  var justAdded: String?
  /// How the page sits on screen, updated as it scrolls and zooms.
  private(set) var placement = MemoPlacement(zoom: 1, origin: .zero, screen: Pt(1, 1), pages: nil, pageCount: 1, topClearance: 104)
  /// The mic button's frame (global), so the recording bar hangs below it.
  var micFrame: CGRect = .zero

  @ObservationIgnored weak var bridge: CanvasBridge?
  @ObservationIgnored private var notebookId = ""
  @ObservationIgnored private var db: NotesDb?
  @ObservationIgnored private lazy var edge = EdgeScroller(.memo) { [weak self] in self?.bridge?.coordinator }

  static let draftId = "draft"

  var draftMemo: MemoRow? { draft.map { MemoRow(id: Self.draftId, z: 0, file: $0.file, at: .zero, durationMs: $0.durationMs, wave: $0.wave, created: 0) } }

  func load(_ db: NotesDb, notebook: String) {
    self.db = db
    notebookId = notebook
    memos = ((try? db.items(of: notebook)) ?? []).compactMap(MemoRow.init)
  }

  /// The pages were laid out again (one deleted, moved or copied, or that undone): the memos are
  /// read again, each beside the page it went with.
  func pagesRearranged() {
    guard let db else { return }
    memos = ((try? db.items(of: notebookId)) ?? []).compactMap(MemoRow.init)
    let here = Set(memos.map(\.id))
    if let open = openMemo, !here.contains(open) { openMemo = nil }
    if let playing = voice.current, playing != Self.draftId, !here.contains(playing) { voice.stopPlayback() }
  }

  /// The page moved under the memos: they follow it.
  func cameraMoved() {
    guard let c = bridge?.coordinator, let canvas = c.canvas else { return }
    let z = Float(canvas.zoomScale)
    placement = MemoPlacement(
      zoom: z, origin: Pt(Float(-canvas.contentOffset.x), Float(-canvas.contentOffset.y)), screen: Pt(Float(canvas.bounds.width), Float(canvas.bounds.height)),
      pages: c.paged ? c.layout : nil, pageCount: c.pageCount, topClearance: Float(c.parent.topClearance))
  }

  /// Every button's centre this frame, spread so none overlap however far she zooms out.
  func centres() -> [String: Pt] {
    let r = Float(MemoSize.button / 2)
    return MemoRow.spread(memos.map { ($0.id, placement.centre($0, radius: r, gap: Float(MemoSize.gap))) }, spacing: Float(MemoSize.spacing), size: Float(MemoSize.button))
  }

  // MARK: Recording

  /// The mic: pressed while recording, it stops; otherwise it starts a memo beside the page on screen.
  func mic(hint: @escaping (String) -> Void) {
    if voice.recording {
      stopMemo(hint: hint)
      return
    }
    Task {
      if await AVAudioApplication.requestRecordPermission() { startMemo(hint: hint) } else { hint(L("to_record_voice_memos_allow_the")) }
    }
  }

  private func startMemo(hint: (String) -> Void) {
    guard !voice.recording else { return }
    cameraMoved()
    discardDraft()
    guard voice.start() else {
      hint(L("the_microphone_couldn_t_start_try"))
      return
    }
    openMemo = nil
    recordingAt = placement.newSpot(memos, spacing: Float(MemoSize.spacing))
  }

  /// Done recording: it waits as a draft to be listened to, deleted or added.
  func stopMemo(hint: (String) -> Void) {
    guard let r = voice.stop() else {
      recordingAt = nil
      hint(L("too_short_to_keep"))
      return
    }
    draft = r
  }

  /// Puts the draft beside the page (an undo step).
  func keepDraft() {
    guard let r = draft, let at = recordingAt, let c = bridge?.coordinator else { return }
    if voice.current == Self.draftId { voice.stopPlayback() }
    draft = nil
    recordingAt = nil
    let memo = MemoRow(id: newId(), z: c.nextZ(), file: r.file, at: at, durationMs: r.durationMs, wave: r.wave, created: nowMillis())
    justAdded = memo.id
    change(from: nil, to: memo)
  }

  /// Throws away the recording going on, or the draft.
  func discardDraft() {
    if voice.recording { voice.cancel() }
    if voice.current == Self.draftId { voice.stopPlayback() }
    if let d = draft { try? FileManager.default.removeItem(at: voice.dir.appendingPathComponent(d.file)) }
    draft = nil
    recordingAt = nil
  }

  /// Leaving the notebook or the app never loses a recording: one going on, or one not yet added,
  /// goes beside the page. One playing pauses.
  func leave() {
    if voice.recording { stopMemo(hint: { _ in }) }
    keepDraft()
    voice.pause()
  }

  // MARK: Changes

  func rename(_ id: String, _ title: String) {
    guard let old = memos.first(where: { $0.id == id }) else { return }
    let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard old.title != t else { return }
    var m = old
    m.title = t
    change(from: old, to: m)
  }

  func move(_ moved: MemoRow) {
    guard let old = memos.first(where: { $0.id == moved.id }), old != moved else { return }
    change(from: old, to: moved)
  }

  /// Deletes a memo (undo brings it back; the recording itself is kept).
  func delete(_ id: String, hint: (String) -> Void) {
    guard let m = memos.first(where: { $0.id == id }) else { return }
    if voice.current == id { voice.stopPlayback() }
    if openMemo == id { openMemo = nil }
    change(from: m, to: nil)
    hint(L("voice_memo_deleted_undo_brings_it"))
  }

  /// One undo step from [old] to [new] (nil: not there).
  private func change(from old: MemoRow?, to new: MemoRow?) {
    apply(old: old, new: new)
    let undo = bridge?.coordinator?.canvas?.undoManager
    undo?.registerUndo(withTarget: self) { m in
      MainActor.assumeIsolated { m.change(from: new, to: old) }
    }
    bridge?.coordinator?.reportUndo()
  }

  private func apply(old: MemoRow?, new: MemoRow?) {
    if let old {
      memos.removeAll { $0.id == old.id }
      if new?.id != old.id { try? db?.removeItem(old.id) }
    }
    if let new {
      memos.append(new)
      do { try db?.put(new.itemRow, in: notebookId) } catch { CrashNote.log("saving a memo: \(error)") }
    }
    bridge?.coordinator?.touch()
  }

  /// A memo carried at [at] (in the canvas's visible area), or nil when let go: resting near an edge scrolls the page.
  func carry(_ at: CGPoint?) { edge.carry(at) }
}

func memoClock(_ ms: Int64) -> String {
  let s = max(ms / 1000, 0)
  return L("n_n_4", s / 60, String(format: "%02d", s % 60))
}

// MARK: The mic

/// The toolbar's mic (Android's Voice tool): blue while recording; pressed again, it stops.
struct MicButton: View {
  var memos: MemoModel
  var onTap: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    let on = memos.voice.recording
    Button(action: onTap) {
      Image(systemName: "mic").font(.system(size: 19)).foregroundStyle(on ? c.blue : c.ink)
        .frame(width: 44, height: 44)
        .background(RoundedRectangle(cornerRadius: 14).fill(on ? c.blueSoft : .clear))
    }
    .buttonStyle(PressStyle(scale: 0.9))
    .background(GeometryReader { g in Color.clear.onAppear { memos.micFrame = g.frame(in: .global) }.onChange(of: g.frame(in: .global)) { _, f in memos.micFrame = f } })
    .accessibilityLabel(on ? L("voice_memo") : L("record_a_voice_memo"))
    .accessibilityIdentifier("tool-voice")
  }
}

// MARK: Memos beside the page

/// The notebook's voice memos over the canvas (Android's `VoiceMemoLayer`): a round button for each
/// beside its page, following the page as it scrolls and zooms. A tap opens it into a bar to play it;
/// holding one picks it up to move it to the other side or up and down.
struct MemoLayer: View {
  var memos: MemoModel
  var hint: (String) -> Void

  var body: some View {
    GeometryReader { geo in
      let centres = memos.centres()
      ZStack(alignment: .topLeading) {
        ForEach(memos.memos) { m in
          MemoBubble(memo: m, home: centres[m.id] ?? Pt(-10_000, -10_000), width: geo.size.width, memos: memos, hint: hint)
        }
      }
      .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
    }
  }
}

private struct MemoBubble: View {
  var memo: MemoRow
  var home: Pt
  var width: CGFloat
  var memos: MemoModel
  var hint: (String) -> Void
  @Environment(\.tali) private var c
  @State private var shown = false
  @State private var popping = false
  @State private var burstStart: Date?
  @State private var drag: CGPoint?
  @State private var dragX: CGFloat = 0
  @State private var dragSide: Int?
  @State private var leaving: Date?
  @State private var editing = false

  private var open: Bool { memos.openMemo == memo.id }
  private var size: CGFloat { MemoSize.button }
  private var full: CGFloat { min(MemoSize.bar, width - 2 * MemoSize.gap) }

  var body: some View {
    let centre = drag.map { CGPoint(x: dragX, y: $0.y) } ?? CGPoint(x: CGFloat(home.x), y: CGFloat(home.y))
    let toLeft = centre.x - size / 2 + full > width - MemoSize.gap
    let w = open ? full : size
    let left = toLeft ? centre.x + size / 2 - w : centre.x - size / 2
    let lift: CGFloat = drag != nil ? 1 : 0
    ZStack(alignment: .topLeading) {
      if let start = burstStart { Sparks(start: start).position(centre) }
      bar(toLeft: toLeft)
        .frame(width: w, height: size)
        .cloudSurface(radius: size / 2, crown: .none, shadowDepth: 4 + 6 * lift)
        .clipShape(RoundedRectangle(cornerRadius: size / 2))
        .scaleEffect((shown ? 1 : (popping ? 0.5 : 0.9)) * (1 + 0.1 * lift))
        .opacity(shown ? 1 : 0)
        .opacity(leaving == nil ? 1 : 0)
        .offset(y: leaving == nil ? 0 : -10)
        .blur(radius: leaving == nil ? 0 : 4)
        .overlay { if let leaving { PuffPlayer(start: leaving, duration: PuffTiming.leave, vivid: true) } }
        .position(x: left + w / 2, y: centre.y)
      if open, leaving == nil {
        MemoTitle(title: memo.title, editing: $editing) { memos.rename(memo.id, $0) }
          .fixedSize()
          .offset(x: (toLeft ? centre.x + size / 2 - full : centre.x - size / 2) + 10, y: titleY(centre))
          .transition(.opacity)
      } else if !memo.title.isEmpty, drag == nil {
        Text(memo.title).font(TaliType.labelSmall).foregroundStyle(c.inkMuted.opacity(0.7)).lineLimit(1)
          .frame(maxWidth: 96)
          .padding(.horizontal, 6).padding(.vertical, 1)
          .background(RoundedRectangle(cornerRadius: 8).fill(c.surface.opacity(0.6)))
          .fixedSize()
          .position(x: centre.x, y: centre.y + size / 2 + 12)
      }
    }
    .animation(Ease.outStrong(duration: open ? MemoSize.open : MemoSize.close), value: open)
    .onAppear {
      popping = memos.justAdded == memo.id
      if popping {
        memos.justAdded = nil
        burstStart = Date()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.48)) { shown = true }
      } else {
        withAnimation(Ease.outStrong(duration: MemoSize.open)) { shown = true }
      }
    }
    .onChange(of: open) { _, o in if !o { editing = false } }
  }

  private func titleY(_ centre: CGPoint) -> CGFloat {
    let top = centre.y - size / 2
    let above = top - 28 - 6
    return above >= CGFloat(memos.placement.topClearance) - 40 ? above : top + size + 6
  }

  @ViewBuilder private func bar(toLeft: Bool) -> some View {
    ZStack(alignment: toLeft ? .trailing : .leading) {
      if open {
        PlayRow(memo: memo, voice: memos.voice, width: full, height: size) {
          Button {
            withAnimation(.easeOut(duration: 0.22)) { leaving = Date() }
            DispatchQueue.main.asyncAfter(deadline: .now() + PuffTiming.leave) { memos.delete(memo.id, hint: hint) }
          } label: {
            Image(systemName: "trash").font(.system(size: 17)).foregroundStyle(c.inkFaint).frame(width: 36, height: 36)
          }
          .buttonStyle(PressStyle(scale: 0.9))
          .accessibilityLabel(L("delete_voice_memo"))
        }
        .frame(width: full, height: size)
        .transition(.opacity.animation(.easeOut(duration: 0.14).delay(open ? 0.1 : 0)))
      } else {
        face
          .frame(width: size, height: size)
          .contentShape(Circle())
          .onTapGesture { memos.openMemo = memo.id }
          .gesture(carryGesture)
          .accessibilityElement()
          .accessibilityLabel(L("open_voice_memo"))
          .accessibilityAddTraits(.isButton)
          .accessibilityIdentifier("memo-\(memo.title.isEmpty ? memo.id : memo.title)")
      }
    }
  }

  /// The button's face: a sound-wave glyph, with a ring showing how far it has played.
  private var face: some View {
    ZStack {
      if memos.voice.current == memo.id {
        Circle().stroke(c.accent.opacity(0.18), lineWidth: 2.5).frame(width: size - 8, height: size - 8)
        Circle().trim(from: 0, to: CGFloat(memos.voice.progress)).stroke(c.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
          .rotationEffect(.degrees(-90)).frame(width: size - 8, height: size - 8)
      }
      Image(systemName: "waveform").font(.system(size: 19, weight: .medium)).foregroundStyle(c.accent)
    }
  }

  /// Held, it lifts; carried, it keeps its margin beside the paper and glides across when the
  /// finger crosses the page's middle; let go, it lands there (Android's `memoDrop`).
  private var carryGesture: some Gesture {
    LongPressGesture(minimumDuration: 0.4)
      .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
      .onChanged { value in
        guard case .second(true, let d) = value else { return }
        let start = CGPoint(x: CGFloat(home.x), y: CGFloat(home.y))
        if drag == nil {
          UIImpactFeedbackGenerator(style: .medium).impactOccurred()
          memos.openMemo = nil
          dragX = start.x
          dragSide = memo.side
        }
        let p = CGPoint(x: start.x + (d?.translation.width ?? 0), y: start.y + (d?.translation.height ?? 0))
        withAnimation(Ease.outStrong(duration: 0.16)) { drag = p }
        memos.carry(p)
        let spot = memos.placement.drop(memo, at: Pt(Float(p.x), Float(p.y)))
        let x = CGFloat(memos.placement.centre(spot, radius: Float(size / 2), gap: Float(MemoSize.gap)).x)
        if spot.side != dragSide {
          dragSide = spot.side
          withAnimation(Ease.outStrong(duration: 0.22)) { dragX = x }
        } else {
          dragX = x
        }
      }
      .onEnded { value in
        memos.carry(nil)
        if case .second(true, let d) = value, let d {
          let start = CGPoint(x: CGFloat(home.x), y: CGFloat(home.y))
          let p = Pt(Float(start.x + d.translation.width), Float(start.y + d.translation.height))
          memos.move(memos.placement.drop(memo, at: p))
        }
        withAnimation(Ease.outStrong(duration: 0.22)) { drag = nil }
      }
  }
}

/// The pop's ring and six sparks spreading out from a memo just added.
private struct Sparks: View {
  var start: Date
  @Environment(\.tali) private var c

  var body: some View {
    TimelineView(.animation) { tl in
      let p = min(tl.date.timeIntervalSince(start) / 0.56, 1)
      let k = CGFloat(Ease.outStrong(p))
      Canvas { ctx, size in
        guard k < 1 else { return }
        let r0 = MemoSize.button / 2
        let o = CGPoint(x: size.width / 2, y: size.height / 2)
        let r = r0 * (1 + 0.75 * k)
        ctx.stroke(Path(ellipseIn: CGRect(x: o.x - r, y: o.y - r, width: 2 * r, height: 2 * r)), with: .color(c.accent.opacity(0.45 * (1 - k))), lineWidth: 2 * (1 - k) + 0.5)
        for i in 0..<6 {
          let a = CGFloat(i) * .pi / 3 + 0.35
          let d = r0 * (1.05 + 0.95 * k)
          let s = 2.6 * (1 - k * 0.7)
          let at = CGPoint(x: o.x + d * cos(a), y: o.y + d * sin(a))
          ctx.fill(Path(ellipseIn: CGRect(x: at.x - s, y: at.y - s, width: 2 * s, height: 2 * s)), with: .color(c.accent.opacity(0.8 * (1 - k))))
        }
      }
    }
    .frame(width: MemoSize.button * 2.4, height: MemoSize.button * 2.4)
    .allowsHitTesting(false)
  }
}

/// A memo's title on a small frosted chip, or a small pencil to give it one; a tap edits it there.
private struct MemoTitle: View {
  var title: String
  @Binding var editing: Bool
  var onDone: (String) -> Void
  @Environment(\.tali) private var c
  @State private var text = ""
  @FocusState private var focused: Bool

  var body: some View {
    Group {
      if editing {
        TextField(L("name_this_memo"), text: $text)
          .font(TaliType.labelLarge).foregroundStyle(c.ink)
          .focused($focused)
          .submitLabel(.done)
          .onSubmit { finish() }
          .frame(minWidth: 120, maxWidth: 220)
          .onAppear {
            text = title
            focused = true
          }
          .onChange(of: focused) { _, f in if !f { finish() } }
      } else if title.isEmpty {
        Image(systemName: "pencil").font(.system(size: 13)).foregroundStyle(c.inkFaint).frame(width: 20, height: 18)
      } else {
        Text(title).font(TaliType.labelLarge).foregroundStyle(c.ink.opacity(0.85)).lineLimit(1).frame(maxWidth: 220, alignment: .leading)
      }
    }
    .padding(.horizontal, 10).padding(.vertical, 4)
    .background(RoundedRectangle(cornerRadius: 12).fill(c.surface.opacity(0.72)))
    .contentShape(Rectangle())
    .onTapGesture { if !editing { editing = true } }
    .accessibilityIdentifier("memo-title")
  }

  private func finish() {
    guard editing else { return }
    editing = false
    onDone(text)
  }
}

/// Play / pause, the wave (tap or drag along it to jump), the time, then [trailing] buttons.
private struct PlayRow<Trailing: View>: View {
  var memo: MemoRow
  var voice: VoiceRecorder
  var width: CGFloat
  var height: CGFloat
  @ViewBuilder var trailing: Trailing
  @Environment(\.tali) private var c

  var body: some View {
    let here = voice.current == memo.id
    let playing = here && voice.playing
    HStack(spacing: 0) {
      Button {
        if playing { voice.pause() } else { voice.play(memo) }
      } label: {
        Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 17)).foregroundStyle(.white)
          .frame(width: 36, height: 36).background(Circle().fill(c.accent))
      }
      .buttonStyle(PressStyle(scale: 0.9))
      .accessibilityLabel(playing ? L("pause") : L("play"))
      .accessibilityIdentifier("memo-play")
      Spacer().frame(width: 10)
      GeometryReader { g in
        Wave(levels: memo.wave.map { Float($0) / 100 }, played: here ? voice.progress : 0, alive: playing, live: false)
          .contentShape(Rectangle())
          .gesture(
            DragGesture(minimumDistance: 0).onChanged { v in
              if voice.current != memo.id { voice.play(memo) }
              voice.seek(Float(v.location.x / max(g.size.width, 1)))
            })
      }
      .frame(height: 30)
      Spacer().frame(width: 10)
      Text(here ? L("n_n_3", memoClock(voice.positionMs), memoClock(memo.durationMs)) : memoClock(memo.durationMs))
        .font(TaliType.labelMedium.monospacedDigit()).foregroundStyle(c.inkMuted).lineLimit(1).fixedSize()
      trailing
    }
    .padding(.horizontal, 6)
    .frame(width: width, height: height)
  }
}

/// The sound wave: round-capped bars, the played part in the accent; around the playhead they sway
/// gently while it plays. A recording's bars are its latest readings, the newest at the right.
private struct Wave: View {
  var levels: [Float]
  var played: Float
  var alive: Bool
  var live: Bool
  @Environment(\.tali) private var c

  var body: some View {
    TimelineView(.animation(paused: !alive)) { tl in
      let time = tl.date.timeIntervalSinceReferenceDate
      Canvas { ctx, size in
        let bw: CGFloat = 3, step = bw + 2.5
        let n = max(Int((size.width + 2.5) / step), 1)
        let values: [Float] =
          live
          ? (0..<n).map { i in let k = levels.count - n + i; return k >= 0 && k < levels.count ? levels[k] : 0 }
          : (0..<n).map { i in levels.isEmpty ? 0 : levels[min(max(i * levels.count / n, 0), levels.count - 1)] }
        let head = CGFloat(played) * CGFloat(n)
        let mid = size.height / 2
        for (i, v) in values.enumerated() {
          let near = min(max(1 - abs(CGFloat(i) - head) / 4, 0), 1)
          let sway = alive ? 1 + 0.35 * near * CGFloat(sin(time * 2 * .pi * 1.8 + Double(i) * 0.9)) : 1
          let h = min(max(bw + (size.height - bw) * CGFloat(v) * sway, bw), size.height)
          let x = CGFloat(i) * step + bw / 2
          var p = Path()
          p.move(to: CGPoint(x: x, y: mid - h / 2 + bw / 2))
          p.addLine(to: CGPoint(x: x, y: mid + h / 2 - bw / 2))
          let color = live || CGFloat(i) < head ? c.accent : c.accent.opacity(0.28)
          ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: bw, lineCap: .round))
        }
      }
    }
  }
}

// MARK: Recording

/// Recording, just below the mic (Android's `RecorderPanel`): the live wave, the time, Done and
/// delete. Done makes a draft to listen to, delete or Add, which pops in beside the page.
struct RecorderPanel: View {
  var memos: MemoModel
  var hint: (String) -> Void
  @Environment(\.tali) private var c
  @State private var leaving: Date?

  var body: some View {
    GeometryReader { geo in
      let present = memos.recordingAt != nil
      let frame = geo.frame(in: .global)
      let width = max(min(MemoSize.recorder, geo.size.width - 32), 200)
      let mic = memos.micFrame
      let cx = mic == .zero ? geo.size.width / 2 : mic.midX - frame.minX
      let top = (mic == .zero ? 80 : mic.maxY - frame.minY) + 18
      let x = min(max(cx - width / 2, 16), max(16, geo.size.width - width - 16))
      ZStack {
        if present {
          panel(width: width)
            .frame(width: width, height: MemoSize.recorderHeight)
            .cloudSurface(radius: MemoSize.recorderHeight / 2, crown: .none, shadowDepth: 6)
            .clipShape(RoundedRectangle(cornerRadius: MemoSize.recorderHeight / 2))
            .opacity(leaving == nil ? 1 : 0)
            .overlay { if let leaving { PuffPlayer(start: leaving, duration: PuffTiming.leave, vivid: true) } }
            .transition(
              .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top)).combined(with: .offset(y: -14))
                  .animation(Ease.outStrong(duration: MemoSize.open)),
                removal: .opacity.combined(with: .scale(scale: 0.94, anchor: .top)).animation(Ease.outStrong(duration: MemoSize.close))))
        }
      }
      .frame(width: width, height: MemoSize.recorderHeight)
      .offset(x: x, y: top)
      .onChange(of: present) { _, p in if p { leaving = nil } }
    }
  }

  @ViewBuilder private func panel(width: CGFloat) -> some View {
    let trash = Button {
      if memos.voice.recording { memos.voice.cancel() }
      memos.voice.stopPlayback()
      withAnimation(.easeOut(duration: 0.22)) { leaving = Date() }
      DispatchQueue.main.asyncAfter(deadline: .now() + PuffTiming.leave) { memos.discardDraft() }
    } label: {
      Image(systemName: "trash").font(.system(size: 17)).foregroundStyle(c.inkFaint).frame(width: 36, height: 36)
    }
    .buttonStyle(PressStyle(scale: 0.9))
    .accessibilityLabel(L("delete_the_recording"))
    if let draft = memos.draftMemo, !memos.voice.recording {
      PlayRow(memo: draft, voice: memos.voice, width: width, height: MemoSize.recorderHeight) {
        trash
        Spacer().frame(width: 4)
        Button { withAnimation(Ease.outStrong(duration: MemoSize.close)) { memos.keepDraft() } } label: {
          HStack(spacing: 6) {
            Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold))
            Text(L("add")).font(TaliType.labelLarge)
          }
          .foregroundStyle(.white).padding(.horizontal, 14).frame(height: 38)
          .background(Capsule().fill(c.accent))
        }
        .buttonStyle(PressStyle(scale: 0.95))
        .accessibilityLabel(L("add_to_the_page"))
        .accessibilityIdentifier("memo-add")
      }
      .transition(.opacity.animation(.easeOut(duration: 0.2).delay(0.06)))
    } else {
      RecordingRow(voice: memos.voice, width: width) {
        withAnimation(.easeOut(duration: 0.2)) { memos.stopMemo(hint: hint) }
      } trash: {
        trash
      }
    }
  }
}

private struct RecordingRow<Trash: View>: View {
  var voice: VoiceRecorder
  var width: CGFloat
  var onDone: () -> Void
  @ViewBuilder var trash: Trash
  @Environment(\.tali) private var c

  var body: some View {
    HStack(spacing: 0) {
      ZStack {
        TimelineView(.animation) { tl in
          let pulse = CGFloat(tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.1) / 1.1)
          Circle().fill(c.danger.opacity(0.28 * (1 - pulse))).frame(width: 40 * (0.78 + 0.4 * pulse), height: 40 * (0.78 + 0.4 * pulse))
        }
        Button(action: onDone) {
          Image(systemName: "stop.fill").font(.system(size: 15)).foregroundStyle(.white).frame(width: 34, height: 34).background(Circle().fill(c.danger))
        }
        .buttonStyle(PressStyle(scale: 0.9))
        .accessibilityLabel(L("done_recording"))
        .accessibilityIdentifier("memo-done")
      }
      .frame(width: 40, height: 40)
      Spacer().frame(width: 10)
      Wave(levels: voice.levels, played: 1, alive: false, live: true).frame(height: 30)
      Spacer().frame(width: 10)
      Text(memoClock(voice.elapsedMs)).font(TaliType.labelMedium.monospacedDigit()).foregroundStyle(c.danger).lineLimit(1).fixedSize()
      Spacer().frame(width: 4)
      trash
    }
    .padding(.horizontal, 8)
    .frame(width: width, height: MemoSize.recorderHeight)
  }
}
