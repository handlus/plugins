// 창 하나만 녹화 — 다른 창이 위에 겹쳐도 그 창 내용만 찍힌다 (ScreenCaptureKit)
// 사용: screcord screens                           모니터 목록 (이름 · 왼쪽 위 좌표 · 크기 · 배율) — 창 위치를 정할 때
//       screcord list                              크롬 창 목록 (번호 · 위치 · 제목)
//       screcord at:<x>,<y> <초> <출력.mp4>          창 왼쪽 위 좌표로 고른다 (chrome_javascript 의 screenX·screenY) ← 권장
//       screcord id:<번호> <초> <출력.mp4>           list 의 창 번호로 고른다
//       screcord <창 제목 일부> <초> <출력.mp4>       제목으로 고른다 (같은 제목이 둘이면 멈춘다)
import Foundation
import ScreenCaptureKit
import AVFoundation
import AppKit

let args = CommandLine.arguments
if args.count == 2 && args[1] == "screens" {
  // NSScreen 은 왼쪽 아래 원점 → AppleScript·System Events·screenX 가 쓰는 왼쪽 위 원점으로 바꾼다
  let mainH = NSScreen.screens.first?.frame.height ?? 0
  for s in NSScreen.screens {
    let f = s.frame
    print("\(s.localizedName)  at:\(Int(f.minX)),\(Int(mainH - f.maxY))  \(Int(f.width))x\(Int(f.height))  scale=\(Int(s.backingScaleFactor))")
  }
  exit(0)
}
let listOnly = args.count == 2 && args[1] == "list"
guard listOnly || (args.count == 4 && Double(args[2]) != nil) else {
  fputs("usage: screcord list | screcord <at:x,y | id:N | title-substring> <seconds> <out.mp4>\n", stderr); exit(64)
}
let selector = listOnly ? "" : args[1]
let seconds = listOnly ? 0 : Double(args[2])!
let outURL = URL(fileURLWithPath: listOnly ? "/dev/null" : args[3])
if !listOnly { try? FileManager.default.removeItem(at: outURL) }

final class Rec: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
  let done = DispatchSemaphore(value: 0)
  func recordingOutputDidStartRecording(_ r: SCRecordingOutput) {
    print("rec_started \(Int(Date().timeIntervalSince1970 * 1000))")
  }
  func recordingOutput(_ r: SCRecordingOutput, didFailWithError e: Error) {
    fputs("rec_failed \(e)\n", stderr); done.signal()
  }
  func recordingOutputDidFinishRecording(_ r: SCRecordingOutput) { done.signal() }
  func stream(_ s: SCStream, didStopWithError e: Error) { fputs("stream_stopped \(e)\n", stderr) }
}

// CLI 에서 ScreenCaptureKit 을 쓰려면 윈도 서버 연결을 먼저 연다 (없으면 CGS_REQUIRE_INIT 로 죽는다)
_ = NSApplication.shared
let rec = Rec()
Task {
  do {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
    let chrome = content.windows.filter { $0.owningApplication?.bundleIdentifier == "com.google.Chrome" && $0.frame.width > 200 && $0.frame.height > 200 }
    if listOnly {
      for w in chrome { print("id:\(w.windowID)  at:\(Int(w.frame.minX)),\(Int(w.frame.minY))  \(Int(w.frame.width))x\(Int(w.frame.height))  onScreen=\(w.isOnScreen)  pid=\(w.owningApplication?.processID ?? 0)  \(w.title ?? "")") }
      exit(0)
    }
    let cands: [SCWindow]
    if selector.hasPrefix("at:") {
      let xy = selector.dropFirst(3).split(separator: ",").compactMap { Double($0) }
      guard xy.count == 2 else { fputs("bad at:x,y\n", stderr); exit(64) }
      cands = chrome.filter { abs($0.frame.minX - xy[0]) < 1 && abs($0.frame.minY - xy[1]) < 1 }
    } else if selector.hasPrefix("id:"), let id = UInt32(selector.dropFirst(3)) {
      cands = chrome.filter { $0.windowID == id }
    } else {
      cands = chrome.filter { ($0.title ?? "").contains(selector) }
    }
    for w in cands { print("window \(w.windowID) \(w.frame) onScreen=\(w.isOnScreen) \(w.title ?? "")") }
    guard cands.count == 1, let win = cands.first else {
      fputs("expected exactly 1 window, got \(cands.count)\n", stderr); exit(2)
    }
    let filter = SCContentFilter(desktopIndependentWindow: win)
    let scale = CGFloat(filter.pointPixelScale)
    let cfg = SCStreamConfiguration()
    cfg.width = Int(win.frame.width * scale)
    cfg.height = Int(win.frame.height * scale)
    cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
    cfg.showsCursor = false
    cfg.queueDepth = 8
    print("size \(cfg.width)x\(cfg.height) scale=\(scale)")

    let stream = SCStream(filter: filter, configuration: cfg, delegate: rec)
    let rc = SCRecordingOutputConfiguration()
    rc.outputURL = outURL
    rc.videoCodecType = .h264
    rc.outputFileType = .mp4
    let ro = SCRecordingOutput(configuration: rc, delegate: rec)
    try stream.addRecordingOutput(ro)
    try await stream.startCapture()
    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    try await stream.stopCapture()
    // moov 가 다 써질 때까지 기다린다 — 먼저 나가면 파일이 잘린다
    let finished = await Task.detached { rec.done.wait(timeout: .now() + 15) == .success }.value
    if !finished { fputs("finish timeout\n", stderr); exit(3) }
    print("saved \(outURL.path)")
    exit(0)
  } catch {
    fputs("error \(error)\n", stderr); exit(1)
  }
}
// dispatchMain() 은 메인 스레드를 내보내 SCK 의 메뉴바 표시(NSWindow)가 죽는다 — 런루프로 붙잡는다
RunLoop.main.run()
