// The app's shared state: the course, progress, the selected lesson, and the code runner (the Mac's own compiler on
// macOS; Asteria Learn's server on iPhone).
import Foundation
import Observation

/// Checks a learner's code against a lesson's tests.
protocol CodeRunner: Sendable {
    func check(_ lesson: Lesson, code: String) async throws -> RunResult
}

@Observable
final class AppModel {
    enum RunnerState {
        case looking
        case ready(String)          // a description, like "Swift 6.4 on this Mac"
        case unavailable(String)    // why, and what to do
    }

    let course: Course
    let progress: ProgressStore
    var selection: Lesson.ID?
    var runnerState: RunnerState = .looking
    @ObservationIgnored var runner: CodeRunner?
    /// A short-lived notice, like "Lesson done".
    var notice: String?

    init(course: Course, progress: ProgressStore = ProgressStore()) {
        self.course = course
        self.progress = progress
        self.selection = progress.lastLesson
    }

    var selectedLesson: Lesson? { selection.flatMap(course.lesson) }

    /// The first lesson not yet done, for "Continue".
    var nextLesson: Lesson? { course.lessons.first { !progress.isDone($0.id) } }

    func open(_ lesson: Lesson?) {
        selection = lesson?.id
        if let lesson { progress.visit(lesson.id) }
    }

    func go(by step: Int) {
        guard let current = selectedLesson else { open(nextLesson ?? course.lessons.first); return }
        let n = course.neighbours(of: current.id)
        if let target = step < 0 ? n.previous : n.next { open(target) }
    }

    func say(_ text: String) {
        notice = text
        Task {
            try? await Task.sleep(for: .seconds(3))
            if notice == text { notice = nil }
        }
    }
}
