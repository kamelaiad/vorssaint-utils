// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What the local Pomodoro app reports at `/api/live`: its phase, reading,
/// sticky note and today's numbers.
struct NotchPomodoroLive: Decodable, Equatable {
    struct Stats: Decodable, Equatable {
        var focusMinutes: Int
        var sessions: Int
        var binned: Int
        var longest: Int
    }

    var mode: String // idle, focus or break
    var running: Bool
    var phaseSeconds: Double
    var elapsedSeconds: Double
    var longBreak: Bool
    var cycle: Int
    var longEvery: Int
    var focusMinutes: Int
    var shortMinutes: Int
    var longMinutes: Int
    var note: String
    var task: String
    var lane: String
    var musicPlaying: Bool
    var musicTitle: String
    var stale: Bool
    var stats: Stats
}

/// Links the notch timer to the Pomodoro app on this Mac (localhost:4760).
/// The app stays the source of truth, because it owns the sticky note,
/// Todoist, the music and the reminders; the notch shows its clock and sends
/// its buttons back as commands. With the app closed nothing changes here.
final class NotchPomodoroLink: ObservableObject {
    static let shared = NotchPomodoroLink()
    private static let base = URL(string: "http://127.0.0.1:4760/")!
    @Published private(set) var live: NotchPomodoroLive?
    private var timer: Timer?

    private init() {}

    /// The app's page is open and has spoken in the last few seconds.
    var isConnected: Bool { live != nil }
    /// A focus or a break is under way in the app.
    var isActive: Bool { live.map { $0.mode != "idle" } ?? false }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        apply(nil)
    }

    /// Commands the app understands: toggle, skip, reset, start, bin, music, next.
    func send(_ action: String) {
        var request = URLRequest(url: Self.base.appendingPathComponent("api/command"),
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["action": action])
        URLSession.shared.dataTask(with: request) { [weak self] _, _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.poll() }
        }.resume()
    }

    private func poll() {
        let request = URLRequest(url: Self.base.appendingPathComponent("api/live"),
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2)
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            let next = ok ? data.flatMap { try? JSONDecoder().decode(NotchPomodoroLive.self, from: $0) } : nil
            DispatchQueue.main.async { self?.apply(next) }
        }.resume()
    }

    private func apply(_ next: NotchPomodoroLive?) {
        let usable = next.flatMap { $0.stale ? nil : $0 }
        let wasActive = isActive
        if usable != live { live = usable }
        if isActive || wasActive { NotchTimerService.shared.mirror(isActive ? live : nil) }
    }
}
