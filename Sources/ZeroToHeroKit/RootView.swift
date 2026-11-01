// The main window: the course in a sidebar, and the lesson (or the course's home) beside it.
// On iPhone the sidebar and the lesson can't share the screen, so the course opens as a stack: home and the outline
// first, then a lesson. iPad keeps the sidebar and the lesson side by side, like the Mac.
import SwiftUI

public struct RootView: View {
    @Environment(AppModel.self) private var model
    public init() {}

    public var body: some View {
        course
            .overlay(alignment: .bottom) { notice }
            .animation(.spring(duration: 0.35), value: model.notice)
            .tint(Color.asSea)
    }

    @ViewBuilder private var course: some View {
        #if os(iOS)
        if compact { PhoneCourseScreen() } else { SplitCourseScreen() }
        #else
        SplitCourseScreen()
        #endif
    }

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var widthClass
    private var compact: Bool { widthClass == .compact }
    #endif

    @ViewBuilder private var notice: some View {
        if let notice = model.notice {
            Text(notice).fontWeight(.semibold).padding(.horizontal, 18).padding(.vertical, 10)
                .glassEffect().padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// iPad and Mac: the outline beside the open lesson. A lesson with no selection shows the course home.
struct SplitCourseScreen: View {
    @Environment(AppModel.self) private var model
    #if os(iOS)
    @State private var showSettings = false
    #endif

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            CourseSidebar()
                .navigationSplitViewColumnWidth(min: 240, ideal: 290, max: 380)
        } detail: {
            Group {
                if let lesson = model.selectedLesson {
                    LessonView(lesson: lesson).id(lesson.id)
                } else {
                    HomeView()
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button("Previous lesson", systemImage: "chevron.left") { model.go(by: -1) }
                        .disabled(model.selectedLesson.map { model.course.neighbours(of: $0.id).previous == nil } ?? true)
                        #if os(iOS)
                        .labelStyle(.iconOnly)
                        #endif
                    Button("Next lesson", systemImage: "chevron.right") { model.go(by: 1) }
                        .disabled(model.selectedLesson.map { model.course.neighbours(of: $0.id).next == nil } ?? false)
                        #if os(iOS)
                        .labelStyle(.iconOnly)
                        #endif
                }
                #if os(iOS)
                ToolbarItem(placement: .primaryAction) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                }
                #endif
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showSettings) { IOSSettingsView() }
        #endif
    }
}

#if os(iOS)
/// Where an iPhone push goes. The outline itself is the root of the stack.
private enum PhoneRoute: Hashable {
    case home
    case lesson(String)
}

struct PhoneCourseScreen: View {
    @Environment(AppModel.self) private var model
    @State private var path: [PhoneRoute] = []
    @State private var restored = false
    @State private var query = ""
    @State private var expanded: Set<String> = []
    @State private var showSettings = false

    private var search: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if search.isEmpty {
                    Section { phoneHeader }
                }
                if search.isEmpty || hasMatch {
                    outline
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Zero to Hero")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Find a lesson")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                }
            }
            .navigationDestination(for: PhoneRoute.self) { route in
                switch route {
                case .home:
                    HomeView()
                        .navigationTitle("Course")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { settingsButton }
                case .lesson(let id):
                    if let lesson = model.course.lesson(id) {
                        LessonView(lesson: lesson).id(lesson.id)
                            .navigationTitle(lesson.title)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItemGroup(placement: .topBarTrailing) {
                                    Button("Previous lesson", systemImage: "chevron.left") { model.go(by: -1) }
                                        .labelStyle(.iconOnly)
                                        .disabled(model.course.neighbours(of: lesson.id).previous == nil)
                                    Button("Next lesson", systemImage: "chevron.right") { model.go(by: 1) }
                                        .labelStyle(.iconOnly)
                                        .disabled(model.course.neighbours(of: lesson.id).next == nil)
                                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                                }
                            }
                    } else {
                        ContentUnavailableView("Lesson missing", systemImage: "book", description: Text("This lesson is no longer in the course."))
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) { IOSSettingsView() }
        .onAppear(perform: restore)
        .onChange(of: model.selection) { _, id in syncPath(to: id) }
        .onChange(of: path) { _, new in syncSelection(to: new) }
    }

    private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Settings", systemImage: "gearshape") { showSettings = true }
        }
    }

    private var phoneHeader: some View {
        let all = model.course.lessons
        let done = model.progress.count(in: all)
        return VStack(alignment: .leading, spacing: 12) {
            Text(model.course.versions.uppercased())
                .font(.caption.weight(.bold)).tracking(1.1).foregroundStyle(Color.asGold)
            Text("Swift: Zero to Hero").font(.display(32)).fixedSize(horizontal: false, vertical: true)
            ProgressView(value: Double(done), total: Double(max(all.count, 1))) {
                Text(done == 0 ? "\(all.count) lessons" : "\(done) of \(all.count) lessons done")
            }
            .tint(Color.asSea)
            if let next = model.nextLesson {
                Button { model.open(next) } label: {
                    Text(done == 0 ? "Start the course" : "Continue: \(next.title)")
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
            } else {
                Label("You finished the course.", systemImage: "star.fill").foregroundStyle(Color.asGold)
            }
            Button { path = [.home] } label: {
                Label("Course overview", systemImage: "book")
            }
            .buttonStyle(.borderless)
            RunnerStatus().font(.callout)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var outline: some View {
        ForEach(Array(model.course.chapters.enumerated()), id: \.offset) { ci, chapter in
            let modules = chapter.modules.filter { search.isEmpty || !matchingLessons(in: $0, search: search).isEmpty }
            if !modules.isEmpty {
                Section {
                    ForEach(modules) { module in
                        let lessons = matchingLessons(in: module, search: search)
                        DisclosureGroup(isExpanded: Binding(
                            get: { !search.isEmpty || expanded.contains(module.id) },
                            set: { open in
                                if open { expanded.insert(module.id) } else { expanded.remove(module.id) }
                            }
                        )) {
                            ForEach(lessons) { lesson in
                                Button { model.open(lesson) } label: {
                                    LessonRow(lesson: lesson)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                            }
                        } label: {
                            HStack {
                                Text(module.title).lineLimit(2)
                                Spacer()
                                Text("\(model.progress.count(in: module.lessons))/\(module.lessons.count)")
                                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("\(ci + 1). \(chapter.title)")
                }
            }
        }
    }

    private var hasMatch: Bool {
        model.course.chapters.contains { chapter in
            chapter.modules.contains { !matchingLessons(in: $0, search: search).isEmpty }
        }
    }

    private func restore() {
        guard !restored else { return }
        restored = true
        if let id = model.selection, expandedModule(for: id) {
            path = [.lesson(id)]
        }
    }

    @discardableResult private func expandedModule(for id: String) -> Bool {
        if let module = model.course.module(of: id)?.module { expanded.insert(module.id) }
        return true
    }

    private func syncPath(to id: String?) {
        guard restored else { return }
        let showing: String? = {
            if case .lesson(let current) = path.last { return current }
            return nil
        }()
        guard showing != id else { return }
        if let id {
            path = [.lesson(id)]
        } else if path.last != .home {
            path = []
        }
    }

    private func syncSelection(to new: [PhoneRoute]) {
        guard restored else { return }
        switch new.last {
        case .lesson(let id):
            guard model.selection != id, let lesson = model.course.lesson(id) else { return }
            model.open(lesson)
        case .home, nil:
            if model.selection != nil { model.open(nil) }
        }
    }
}
#endif

struct CourseSidebar: View {
    @Environment(AppModel.self) private var model
    @State private var expanded: Set<String> = []
    #if os(iOS)
    @State private var query = ""
    private var search: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    #else
    private var search: String { "" }
    #endif

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            Button { model.open(nil) } label: {
                Label { Text("Swift: Zero to Hero") } icon: { Image(systemName: "house").foregroundStyle(Color.asSea) }
            }
            .buttonStyle(.plain)
            if search.isEmpty || hasMatch {
                ForEach(Array(model.course.chapters.enumerated()), id: \.offset) { ci, chapter in
                    let modules = chapter.modules.filter { search.isEmpty || !matchingLessons(in: $0, search: search).isEmpty }
                    if !modules.isEmpty {
                        Section {
                            ForEach(modules) { module in
                                let lessons = matchingLessons(in: module, search: search)
                                DisclosureGroup(isExpanded: Binding(
                                    get: { !search.isEmpty || expanded.contains(module.id) },
                                    set: { open in if open { expanded.insert(module.id) } else { expanded.remove(module.id) } }
                                )) {
                                    ForEach(lessons) { lesson in
                                        LessonRow(lesson: lesson).tag(lesson.id)
                                    }
                                } label: {
                                    HStack {
                                        Text(module.title)
                                        Spacer()
                                        Text("\(model.progress.count(in: module.lessons))/\(module.lessons.count)")
                                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                    }
                                }
                            }
                        } header: {
                            Text("\(ci + 1). \(chapter.title)")
                        }
                    }
                }
            } else {
                #if os(iOS)
                ContentUnavailableView.search(text: query)
                #endif
            }
        }
        .listStyle(.sidebar)
        #if os(iOS)
        .navigationTitle("Zero to Hero")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Find a lesson")
        #endif
        .onAppear { if let id = model.selection, let m = model.course.module(of: id) { expanded.insert(m.module.id) } }
        .onChange(of: model.selection) { _, id in
            if let id, let m = model.course.module(of: id) { expanded.insert(m.module.id) }
        }
    }

    private var hasMatch: Bool {
        model.course.chapters.contains { chapter in
            chapter.modules.contains { !matchingLessons(in: $0, search: search).isEmpty }
        }
    }
}

fileprivate func matchingLessons(in module: Module, search: String) -> [Lesson] {
    let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
    if query.isEmpty || module.title.localizedStandardContains(query) { return module.lessons }
    return module.lessons.filter { $0.title.localizedStandardContains(query) }
}

struct LessonRow: View {
    @Environment(AppModel.self) private var model
    let lesson: Lesson
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: model.progress.isDone(lesson.id) ? "checkmark.circle.fill" : icon)
                .foregroundStyle(model.progress.isDone(lesson.id) ? Color.asSea : .secondary)
                .frame(width: 18)
            Text(lesson.title).lineLimit(2)
        }
        .accessibilityValue(model.progress.isDone(lesson.id) ? "Done" : "")
    }
    var icon: String {
        switch lesson.type {
        case .quiz: "questionmark.circle"
        case .xcode: "hammer"
        case .project: "star"
        case .lab: "flask"
        case .workshop: "wrench.and.screwdriver"
        case .lesson: lesson.hasCode ? "chevron.left.forwardslash.chevron.right" : "book"
        }
    }
}

struct HomeView: View {
    @Environment(AppModel.self) private var model
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var widthClass
    private var compact: Bool { widthClass == .compact }
    #else
    private var compact: Bool { false }
    #endif

    var body: some View {
        let all = model.course.lessons, done = model.progress.count(in: all)
        let chapterCount = model.course.chapters.count
        ScrollView {
            VStack(alignment: .leading, spacing: compact ? 16 : 22) {
                Text(model.course.versions.uppercased()).font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Color.asGold)
                Text("Swift: Zero to Hero").font(.display(compact ? 36 : 56)).fixedSize(horizontal: false, vertical: true)
                Text(model.course.subtitle).font(compact ? .body : .title3).foregroundStyle(.secondary)
                ProgressView(value: Double(done), total: Double(max(all.count, 1))) {
                    Text(done == 0 ? "\(all.count) lessons in \(chapterCount) chapters" : "\(done) of \(all.count) lessons done")
                }
                .tint(Color.asSea)
                .frame(maxWidth: 420)
                if let next = model.nextLesson {
                    Button { model.open(next) } label: {
                        Text(done == 0 ? "Start the course" : "Continue: \(next.title)")
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .frame(maxWidth: compact ? .infinity : 520, alignment: .leading)
                } else {
                    Label("You finished the course. Well done.", systemImage: "star.fill").foregroundStyle(Color.asGold)
                }
                RunnerStatus()
                Divider().padding(.vertical, 6)
                Text(markdown(model.course.summary)).font(.body).foregroundStyle(.secondary).frame(maxWidth: 640, alignment: .leading)
                if compact {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(model.course.chapters.enumerated()), id: \.offset) { i, chapter in
                            chapterRow(i, chapter)
                        }
                    }
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 14) {
                        ForEach(Array(model.course.chapters.enumerated()), id: \.offset) { i, chapter in
                            let lessons = chapter.modules.flatMap(\.lessons)
                            GridRow {
                                Text(String(format: "%02d", i + 1)).font(.display(22)).foregroundStyle(Color.asGold)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chapter.title).font(.headline)
                                    Text(chapter.summary).font(.callout).foregroundStyle(.secondary)
                                }
                                Text("\(model.progress.count(in: lessons))/\(lessons.count)").monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Text("Made by Asteria Technology. Open source.").font(.footnote).foregroundStyle(.tertiary).padding(.top, 12)
            }
            .padding(compact ? 20 : 40)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func chapterRow(_ index: Int, _ chapter: Chapter) -> some View {
        let lessons = chapter.modules.flatMap(\.lessons)
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(String(format: "%02d", index + 1)).font(.display(22)).foregroundStyle(Color.asGold).frame(width: 40, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.title).font(.headline)
                Text(chapter.summary).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("\(model.progress.count(in: lessons))/\(lessons.count)").monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

/// Whether exercises can run, and what to do if not.
struct RunnerStatus: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        switch model.runnerState {
        case .looking:
            Label {
                Text("Looking for the Swift compiler…").fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "hourglass")
            }
            .foregroundStyle(.secondary)
        case .ready(let what):
            Label {
                Text(what).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "checkmark.circle")
            }
            .foregroundStyle(.secondary)
        case .unavailable(let why):
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text(why).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .foregroundStyle(Color.asAlert)
                #if os(macOS)
                if Toolchain.inSandbox {
                    Button("Get Xcode from the App Store") { InstallTools.openXcode() }.buttonStyle(.glass)
                    Text("Xcode is free. When it is installed, open it once, then quit and reopen this app.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Button("Install the Command Line Tools") { InstallTools.start() }.buttonStyle(.glass)
                    Text("Apple's free installer opens. When it finishes, quit and reopen this app. Xcode works too.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                #endif
            }
            .padding(16)
            .background(Color.asAlert.opacity(0.08), in: .rect(cornerRadius: 14))
        }
    }
}

#if os(macOS)
enum InstallTools {
    static func start() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        p.arguments = ["--install"]
        try? p.run()
    }
    static func openXcode() {
        NSWorkspace.shared.open(URL(string: "macappstore://apps.apple.com/app/xcode/id497799835")!)
    }
}
#endif
