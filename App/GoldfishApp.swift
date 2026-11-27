import SwiftUI
import GoldfishCore

@main
struct GoldfishApp: App {
    @State private var model: AppModel

    init() {
        AppFonts.register()
        let launch = LaunchOptions.current
        let firebaseReady = FirebaseSetup.configureIfPossible(skip: launch.screenshotMode)
        _model = State(initialValue: AppModel(launch: launch, firebaseReady: firebaseReady))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.accent)
                .font(.poppins(.body))
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    /// Finn swims in at launch. Skipped in screenshot mode so it never covers a scripted screenshot.
    @State private var showSplash = !LaunchOptions.current.screenshotMode

    var body: some View {
        @Bindable var model = model
        Group {
            if model.data.onboarded {
                // The system tab bar, so it gets Liquid Glass from iOS 26 on, and iOS 27's glass tint, with no
                // drawing of our own. Each tab keeps its own stack.
                TabView(selection: $model.tab) {
                    Tab("Today", systemImage: "house.fill", value: AppTab.today) {
                        stack(.today) { TodayView() }
                    }
                    Tab("Decks", systemImage: "rectangle.stack.fill", value: AppTab.decks) {
                        stack(.decks) { DecksView() }
                    }
                    Tab("Tutor", systemImage: "questionmark.bubble.fill", value: AppTab.tutor) {
                        stack(.tutor) { TutorView() }
                    }
                    Tab("Friends", systemImage: "person.2.fill", value: AppTab.friends) {
                        stack(.friends) { FriendsView() }
                    }
                    Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                        stack(.settings) { SettingsView() }
                    }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
            } else {
                OnboardingView()
            }
        }
        .overlay {
            if showSplash {
                SplashView()
                    .transition(.opacity)
            }
        }
        .task {
            await model.startup()
            guard showSplash else { return }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation(.easeOut(duration: 0.35)) {
                showSplash = false
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                model.enterBackground()
            }
        }
        .onChange(of: model.network.isOnline) { _, online in
            if online {
                Task { await model.flushPendingReports() }
            }
        }
    }

    /// A tab's navigation stack, bound to that tab's own path.
    private func stack<Root: View>(_ tab: AppTab, @ViewBuilder root: () -> Root) -> some View {
        NavigationStack(path: Binding(
            get: { model.paths[tab] ?? [] },
            set: { model.paths[tab] = $0 }
        )) {
            root()
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                }
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .chapter(let id): ChapterView(chapterID: id)
        case .teach(let id): TeachView(chapterID: id)
        case .quiz(let id, let kind): QuizView(chapterID: id, kind: kind)
        case .review(let id): MissReviewView(chapterID: id)
        case .yourTurn(let id): YourTurnView(scope: .chapterDue(id))
        case .chapterQuiz(let id): YourTurnView(scope: .chapterAll(id))
        case .deckQuiz(let id): YourTurnView(scope: .deck(id))
        case .finalExam(let id): FinalExamView(chapterID: id)
        case .report(let id): ReportCardView(chapterID: id)
        case .map(let id): MasteryMapView(chapterID: id)
        case .deck(let id): DeckView(deckID: id)
        case .settings: SettingsView()
        case .diagnostics: DiagnosticsView()
        case .teachOff(let id): TeachOffView(mode: .existing(challengeID: id))
        case .newTeachOff(let id): TeachOffView(mode: .new(chapterID: id))
        }
    }
}
