// What the learner has done: finished lessons, their code for each exercise, ticked checklist items, and where they
// were. Saved as JSON in Application Support, a moment after each change.
import Foundation
import Observation

@Observable
final class ProgressStore {
    nonisolated struct Saved: Codable {
        var done: [String: Date] = [:]
        var code: [String: String] = [:]
        var ticks: [String: Set<Int>] = [:]
        var last: String?
    }

    private(set) var saved = Saved()
    @ObservationIgnored private let file: URL
    @ObservationIgnored private var pending: Task<Void, Never>?

    init(file: URL? = nil) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Swift Zero to Hero")
        self.file = file ?? dir.appending(path: "progress.json")
        if let data = try? Data(contentsOf: self.file), let s = try? JSONDecoder.iso.decode(Saved.self, from: data) { saved = s }
    }

    func isDone(_ id: String) -> Bool { saved.done[id] != nil }
    func code(for lesson: Lesson) -> String { saved.code[lesson.id] ?? lesson.seed ?? "" }
    func ticks(for id: String) -> Set<Int> { saved.ticks[id] ?? [] }
    var lastLesson: String? { saved.last }

    func complete(_ id: String) { saved.done[id] = saved.done[id] ?? .now; save() }
    func setCode(_ code: String, for id: String) { saved.code[id] = code; save() }
    func resetCode(for id: String) { saved.code[id] = nil; save() }
    func toggle(tick: Int, for id: String) {
        var t = saved.ticks[id] ?? []
        if t.contains(tick) { t.remove(tick) } else { t.insert(tick) }
        saved.ticks[id] = t
        save()
    }
    func visit(_ id: String) { if saved.last != id { saved.last = id; save() } }
    func resetAll() { saved = Saved(); save() }

    func count(in lessons: [Lesson]) -> Int { lessons.filter { isDone($0.id) }.count }

    private func save() {
        pending?.cancel()
        let snapshot = saved, file = file
        pending = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await Self.write(snapshot, to: file)
        }
    }

    @concurrent
    private static func write(_ snapshot: Saved, to file: URL) async {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder.iso.encode(snapshot) { try? data.write(to: file, options: .atomic) }
    }
}

nonisolated extension JSONDecoder {
    static var iso: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}

nonisolated extension JSONEncoder {
    static var iso: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = .sortedKeys; return e }
}
