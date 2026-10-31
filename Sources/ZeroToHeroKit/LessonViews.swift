// The lesson screens: lessons with code (instructions beside an editor, tests and a console), and reading lessons with
// quizzes and checklists.
import SwiftUI

struct LessonView: View {
    let lesson: Lesson
    var body: some View {
        if lesson.hasCode { CodeLessonView(lesson: lesson) } else { ReadingLessonView(lesson: lesson) }
    }
}

// MARK: - parts every lesson shares

struct LessonHeader: View {
    @Environment(AppModel.self) private var model
    let lesson: Lesson
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let place = model.course.module(of: lesson.id) {
                Text("\(place.chapter.title)  ›  \(place.module.title)").font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                KindBadge(kind: lesson.type)
                Text(lesson.title).font(.largeTitle.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                if model.progress.isDone(lesson.id) {
                    Label("Done", systemImage: "checkmark.circle.fill").labelStyle(.iconOnly).foregroundStyle(Color.asSea).font(.title2)
                        .accessibilityLabel("Done")
                }
            }
            Text("About \(lesson.minutes) minutes").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct KindBadge: View {
    let kind: Lesson.Kind
    var tint: Color {
        switch kind {
        case .quiz: .asGold
        case .lab, .project, .workshop: .asSea
        case .xcode: .secondary
        case .lesson: .secondary
        }
    }
    var body: some View {
        Text(kind.label.uppercased())
            .font(.caption2.weight(.bold)).tracking(0.8)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(tint.opacity(0.16), in: .capsule)
            .foregroundStyle(tint == .secondary ? Color.primary.opacity(0.7) : tint)
    }
}

struct LessonFooter: View {
    @Environment(AppModel.self) private var model
    let lesson: Lesson
    var body: some View {
        let n = model.course.neighbours(of: lesson.id)
        HStack {
            if let previous = n.previous {
                Button { model.open(previous) } label: { Label(previous.title, systemImage: "chevron.left") }.buttonStyle(.borderless)
            }
            Spacer()
            if let next = n.next {
                Button { model.open(next) } label: { Label(next.title, systemImage: "chevron.right").labelStyle(TrailingIcon()) }
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(.top, 20)
    }
}

struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.title; configuration.icon }
    }
}

// MARK: - lessons with code

struct CodeLessonView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("editorFontSize") private var fontSize = 14.0
    let lesson: Lesson
    @State private var code = ""
    @State private var result: RunResult?
    @State private var running = false
    @State private var problem: String?
    @State private var hintsShown = 0
    @State private var showingCode = false   // iPhone: which half is on screen
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        Group {
            #if os(macOS)
            HSplitView {
                instructions.frame(minWidth: 320, idealWidth: 460)
                workspace.frame(minWidth: 380)
            }
            #else
            if sizeClass == .regular {
                // iPad: the lesson and the code side by side, like the Mac
                HStack(spacing: 0) {
                    instructions.frame(maxWidth: .infinity)
                    Divider()
                    workspace.frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    Picker("Show", selection: $showingCode) {
                        Text("Lesson").tag(false)
                        Text("Code").tag(true)
                    }
                    .pickerStyle(.segmented).padding()
                    if showingCode { workspace } else { instructions }
                }
            }
            #endif
        }
        .onAppear {
            code = model.progress.code(for: lesson)
            if Screenshots.on {
                showingCode = true
                Task {
                    while model.runner == nil { try? await Task.sleep(for: .milliseconds(200)) }
                    run()
                }
            }
        }
        .onChange(of: code) { _, new in model.progress.setCode(new, for: lesson.id) }
        .focusedSceneValue(\.runAction, RunAction(run: run))
        .focusedSceneValue(\.resetAction, ResetAction(reset: reset))
    }

    var instructions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LessonHeader(lesson: lesson)
                BlocksView(blocks: lesson.description)
                if !lesson.instructions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your task").font(.title3.weight(.semibold))
                        BlocksView(blocks: lesson.instructions)
                    }
                    .padding(16)
                    .background(Color.asSea.opacity(0.08), in: .rect(cornerRadius: 14))
                }
                TestsList(tests: lesson.tests, results: result?.tests)
                if !lesson.hints.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(0..<hintsShown, id: \.self) { i in
                            Label { Text(markdown(lesson.hints[i])) } icon: { Image(systemName: "lightbulb").foregroundStyle(Color.asGold) }
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.asGold.opacity(0.12), in: .rect(cornerRadius: 12))
                        }
                        if hintsShown < lesson.hints.count {
                            Button("Get a hint", systemImage: "lightbulb") { withAnimation { hintsShown += 1 } }.buttonStyle(.borderless)
                        }
                    }
                }
                LessonFooter(lesson: lesson)
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    var workspace: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("main.swift").font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Button("Reset", action: reset).buttonStyle(.borderless)
                Button(action: run) {
                    if running { ProgressView().controlSize(.small) } else { Label("Run", systemImage: "play.fill") }
                }
                .buttonStyle(.glassProminent)
                .tint(Color.asSea)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(running)
                .help("Run your code and check it (⌘↩)")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.editorBackground)
            .environment(\.colorScheme, .dark)
            CodeEditor(text: $code, errorLines: Set(result?.errors.compactMap(\.line) ?? []), fontSize: fontSize)
            ConsoleView(result: result, running: running, problem: problem, onLine: { _ in })
                .frame(minHeight: 140, idealHeight: 220)
            if result?.passed == true, let next = model.course.neighbours(of: lesson.id).next {
                HStack {
                    Label("Every test passes. Lesson done.", systemImage: "checkmark.seal.fill").foregroundStyle(Color.asPass).fontWeight(.semibold)
                    Spacer()
                    Button("Next: \(next.title)") { model.open(next) }.buttonStyle(.glassProminent)
                }
                .padding(12)
                .background(Color.editorBackground)
                .environment(\.colorScheme, .dark)
            }
        }
    }

    func run() {
        guard !running else { return }
        guard let runner = model.runner else {
            problem = {
                if case .unavailable(let why) = model.runnerState { return why }
                return "Still looking for the Swift compiler. Try again in a moment."
            }()
            return
        }
        running = true; problem = nil
        let lesson = lesson, code = code
        Task {
            do {
                let r = try await runner.check(lesson, code: code)
                result = r
                if r.passed {
                    model.progress.complete(lesson.id)
                    model.say("Lesson done")
                }
            } catch {
                problem = error.localizedDescription
            }
            running = false
        }
    }

    func reset() {
        code = lesson.seed ?? ""
        model.progress.resetCode(for: lesson.id)
        result = nil
    }
}

struct TestsList: View {
    let tests: [LessonTest]
    let results: [RunResult.TestResult]?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tests").font(.title3.weight(.semibold))
            ForEach(Array(tests.enumerated()), id: \.offset) { i, test in
                let passed = results.map { i < $0.count && $0[i].passed }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: passed == nil ? "circle" : passed! ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(passed == nil ? Color.secondary : passed! ? Color.asSea : Color.asAlert)
                    Text(markdown(test.text)).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(passed == nil ? "Not run yet" : passed! ? "Passed" : "Failed")
            }
        }
    }
}

struct ConsoleView: View {
    let result: RunResult?
    let running: Bool
    let problem: String?
    let onLine: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CONSOLE").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    content
                }
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        }
        .background(Color(hex: 0x0a1418))
        .foregroundStyle(Color.editorText)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder var content: some View {
        if let problem {
            Text(problem).foregroundStyle(Color(hex: 0xff9b85))
        } else if running {
            Text("Compiling and running your code…").foregroundStyle(.secondary)
        } else if let r = result {
            if !r.compiled {
                Text(r.timedOut ? "Compiling took too long." : "Your code did not compile:").foregroundStyle(Color(hex: 0xff9b85))
                ForEach(r.errors, id: \.self) { e in
                    Text((e.line.map { "line \($0): " } ?? "") + e.message).foregroundStyle(Color(hex: 0xff9b85))
                }
            } else {
                if !r.output.isEmpty { Text(r.output) }
                if r.timedOut { Text("Your program ran for too long and was stopped. Is there a loop that never ends?").foregroundStyle(Color(hex: 0xff9b85)) }
                else if r.crashed { Text("Your program crashed: \(r.crashReason)").foregroundStyle(Color(hex: 0xff9b85)) }
                if r.output.isEmpty && !r.timedOut && !r.crashed { Text("(Nothing was printed.)").foregroundStyle(.secondary) }
                if r.passed { Text("Every test passes.").foregroundStyle(Color.asPass).padding(.top, 6) }
            }
        } else {
            Text("Press Run (⌘↩) to check your code.").foregroundStyle(.secondary)
        }
    }
}

// MARK: - reading lessons, quizzes and checklists

struct ReadingLessonView: View {
    @Environment(AppModel.self) private var model
    let lesson: Lesson

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LessonHeader(lesson: lesson)
                BlocksView(blocks: lesson.description)
                if !lesson.instructions.isEmpty { BlocksView(blocks: lesson.instructions) }
                if !lesson.checklist.isEmpty { ChecklistView(lesson: lesson) }
                if !lesson.questions.isEmpty { QuizView(lesson: lesson) }
                if lesson.checklist.isEmpty && lesson.questions.isEmpty && !model.progress.isDone(lesson.id) {
                    Button("Mark as read") { model.progress.complete(lesson.id) }.buttonStyle(.glassProminent)
                }
                LessonFooter(lesson: lesson)
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

struct ChecklistView: View {
    @Environment(AppModel.self) private var model
    let lesson: Lesson

    var allTicked: Bool { model.progress.ticks(for: lesson.id).count == lesson.checklist.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(lesson.type == .project ? "Your project" : "On your Mac", systemImage: "checklist").font(.title3.weight(.semibold))
            ForEach(Array(lesson.checklist.enumerated()), id: \.offset) { i, item in
                Toggle(isOn: Binding(get: { model.progress.ticks(for: lesson.id).contains(i) || model.progress.isDone(lesson.id) },
                                     set: { _ in model.progress.toggle(tick: i, for: lesson.id) })) {
                    Text(markdown(item)).fixedSize(horizontal: false, vertical: true)
                }
                #if os(macOS)
                .toggleStyle(.checkbox)
                #endif
            }
            if lesson.questions.isEmpty && !model.progress.isDone(lesson.id) {
                Button("Mark as done") { model.progress.complete(lesson.id); model.say("Lesson done") }
                    .buttonStyle(.glassProminent).disabled(!allTicked)
            } else if !lesson.questions.isEmpty && !model.progress.isDone(lesson.id) {
                Text("Tick these off, then answer the questions below to finish.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 18))
    }
}

struct QuizView: View {
    @Environment(AppModel.self) private var model
    let lesson: Lesson
    @State private var picks: [Int: Int] = [:]
    @State private var checked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(lesson.type == .quiz ? "Questions" : "Check your understanding").font(.title3.weight(.semibold))
            ForEach(Array(lesson.questions.enumerated()), id: \.offset) { qi, q in
                VStack(alignment: .leading, spacing: 8) {
                    Text(markdown("\(qi + 1). " + q.question)).font(.headline).fixedSize(horizontal: false, vertical: true)
                    if !q.detail.isEmpty { BlocksView(blocks: q.detail) }
                    ForEach(Array(q.answers.enumerated()), id: \.offset) { ai, answer in
                        Button { picks[qi] = ai; checked = false } label: {
                            HStack(spacing: 10) {
                                Image(systemName: picks[qi] == ai ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(picks[qi] == ai ? Color.asSea : .secondary)
                                Text(markdown(answer.text)).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .contentShape(.rect)
                            .background(background(qi, ai), in: .rect(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(picks[qi] == ai ? .isSelected : [])
                    }
                    if checked, let pick = picks[qi] {
                        let right = q.answers[pick].correct
                        Text(markdown((right ? "**Right.** " : "**Not quite.** ") + q.why))
                            .foregroundStyle(right ? Color.asSea : Color.asAlert).font(.callout)
                    }
                }
            }
            HStack {
                Button(model.progress.isDone(lesson.id) ? "Check again" : "Check my answers", action: check)
                    .buttonStyle(.glassProminent).disabled(picks.count < lesson.questions.count)
                if checked, allRight { Label("All right.", systemImage: "checkmark.seal.fill").foregroundStyle(Color.asPass) }
            }
        }
        .padding(20)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 18))
    }

    var allRight: Bool {
        lesson.questions.indices.allSatisfy { i in picks[i].map { lesson.questions[i].answers[$0].correct } ?? false }
    }

    func background(_ qi: Int, _ ai: Int) -> Color {
        guard checked, picks[qi] == ai else { return Color.primary.opacity(0.04) }
        return lesson.questions[qi].answers[ai].correct ? Color.asSea.opacity(0.15) : Color.asAlert.opacity(0.15)
    }

    func check() {
        checked = true
        guard allRight else { model.say("Have another look at the ones marked."); return }
        if !lesson.checklist.isEmpty && model.progress.ticks(for: lesson.id).count < lesson.checklist.count && !model.progress.isDone(lesson.id) {
            model.say("All right. Tick off the checklist too.")
            return
        }
        model.progress.complete(lesson.id)
        model.say("Lesson done")
    }
}

// MARK: - menu commands reach the lesson on screen

struct RunAction { let run: () -> Void }
struct ResetAction { let reset: () -> Void }

struct RunActionKey: FocusedValueKey { typealias Value = RunAction }
struct ResetActionKey: FocusedValueKey { typealias Value = ResetAction }

extension FocusedValues {
    var runAction: RunAction? {
        get { self[RunActionKey.self] }
        set { self[RunActionKey.self] = newValue }
    }
    var resetAction: ResetAction? {
        get { self[ResetActionKey.self] }
        set { self[ResetActionKey.self] = newValue }
    }
}
