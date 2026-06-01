import SwiftUI
import AppKit

@main
struct DecisionReviewApp: App {
    @StateObject private var store = DecisionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 760, minHeight: 560)
                .task {
                    store.load()
                    if store.decisions.isEmpty {
                        store.seedSampleData()
                    }
                    CodexAIService.prewarm()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建决策") {
                    store.createDecision()
                }
                .keyboardShortcut("n")
            }
        }
    }
}

enum ReviewStatus: String, Codable, CaseIterable, Identifiable {
    case draft = "记录中"
    case pending = "待复盘"
    case reviewed = "已复盘"

    var id: String { rawValue }
}

enum Emotion: String, Codable, CaseIterable, Identifiable {
    case calm = "冷静"
    case anxious = "焦虑"
    case excited = "兴奋"
    case avoidant = "逃避"
    case lucky = "侥幸"

    var id: String { rawValue }
}

enum ErrorType: String, Codable, CaseIterable, Identifiable {
    case information = "信息不足"
    case optimism = "过度乐观"
    case emotion = "情绪驱动"
    case unclearGoal = "目标不清"
    case execution = "执行问题"
    case external = "外部变化"
    case none = "暂无归因"

    var id: String { rawValue }
}

struct Decision: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var quickNote: String? = ""
    var category: String? = "工作"
    var context: String
    var options: String
    var choice: String
    var reasoning: String
    var expectedResult: String
    var actualResult: String
    var lesson: String
    var analysisReport: String?
    var emotion: Emotion
    var errorType: ErrorType
    var confidence: Double
    var qualityScore: Int
    var createdAt: Date
    var reviewAt: Date
    var status: ReviewStatus

    var isDue: Bool {
        status != .reviewed && reviewAt <= Calendar.current.startOfDay(for: Date()).addingTimeInterval(24 * 60 * 60)
    }
}

struct Principle: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var sourceDecisionTitle: String
    var scene: String
    var createdAt = Date()
    var usageCount = 0
}

final class DecisionStore: ObservableObject {
    @Published var decisions: [Decision] = [] {
        didSet { save() }
    }
    @Published var principles: [Principle] = [] {
        didSet { save() }
    }
    @Published var selectedDecisionID: Decision.ID?
    @Published var selectedSection: SidebarSection = .today

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = base.appendingPathComponent("DecisionReview", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("store.json")
    }()

    var selectedDecision: Decision? {
        get { decisions.first(where: { $0.id == selectedDecisionID }) }
        set {
            guard let newValue, let index = decisions.firstIndex(where: { $0.id == newValue.id }) else { return }
            decisions[index] = newValue
        }
    }

    var todayDecisions: [Decision] {
        decisions.filter { Calendar.current.isDateInToday($0.createdAt) }
    }

    var pendingDecisions: [Decision] {
        decisions.filter { $0.status != .reviewed }.sorted { $0.reviewAt < $1.reviewAt }
    }

    var reviewedDecisions: [Decision] {
        decisions.filter { $0.status == .reviewed }
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let snapshot = try? JSONDecoder.app.decode(StoreSnapshot.self, from: data) else { return }
        decisions = snapshot.decisions
        principles = snapshot.principles
        selectedDecisionID = decisions.first?.id
    }

    func save() {
        let snapshot = StoreSnapshot(decisions: decisions, principles: principles)
        guard let data = try? JSONEncoder.app.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    func createDecision() {
        let item = Decision(
            title: "新的复盘事项",
            quickNote: "",
            category: "工作",
            context: "",
            options: "",
            choice: "",
            reasoning: "",
            expectedResult: "",
            actualResult: "",
            lesson: "",
            analysisReport: "",
            emotion: .calm,
            errorType: .none,
            confidence: 60,
            qualityScore: 3,
            createdAt: Date(),
            reviewAt: Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date(),
            status: .draft
        )
        decisions.insert(item, at: 0)
        selectedDecisionID = item.id
        selectedSection = .today
    }

    func markReviewed(_ decision: Decision) {
        guard let index = decisions.firstIndex(where: { $0.id == decision.id }) else { return }
        var updated = decision
        updated.status = .reviewed
        decisions[index] = updated
        addPrincipleIfNeeded(from: updated)
    }

    func deleteDecision(_ decision: Decision) {
        guard let index = decisions.firstIndex(where: { $0.id == decision.id }) else { return }
        decisions.remove(at: index)
        if decisions.isEmpty {
            selectedDecisionID = nil
        } else {
            selectedDecisionID = decisions[min(index, decisions.count - 1)].id
        }
    }

    func deletePrinciple(_ principle: Principle) {
        principles.removeAll { $0.id == principle.id }
    }

    func addPrincipleIfNeeded(from decision: Decision) {
        let text = decision.lesson.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !principles.contains(where: { $0.text == text }) else { return }
        principles.insert(
            Principle(
                text: text,
                sourceDecisionTitle: decision.title,
                scene: decision.errorType.rawValue
            ),
            at: 0
        )
    }

    func seedSampleData() {
        let now = Date()
        decisions = [
            Decision(
                title: "是否接下一个边界不清的新项目",
                quickNote: "对方催着启动一个新项目，但边界还没说清楚。我担心直接接下来后面会失控，所以想先问清交付范围。",
                category: "工作",
                context: "对方希望快速启动，但交付范围和验收标准还没明确。",
                options: "直接接下 / 拒绝 / 先确认边界再决定",
                choice: "先确认边界再决定",
                reasoning: "时间窗口紧，但需求不清会放大后续沟通成本。",
                expectedResult: "确认边界后再判断是否投入。",
                actualResult: "对方补充了验收口径，项目范围缩小。",
                lesson: "当我准备接新项目时，如果交付边界还不清楚，我应该先确认时间、责任和验收标准。",
                analysisReport: "本次复盘：这件事的关键不在于是否接项目，而在于启动前的边界确认。做得好的地方是没有被紧迫感直接带着走，先把交付范围和验收标准拉出来确认。后续可继续保留这个动作：凡是涉及时间投入、责任边界和验收结果的事项，先确认边界，再决定投入。",
                emotion: .calm,
                errorType: .none,
                confidence: 78,
                qualityScore: 4,
                createdAt: now,
                reviewAt: now,
                status: .reviewed
            ),
            Decision(
                title: "是否推迟晚上复盘",
                quickNote: "晚上很累，有两个选择没记录。我想明早补，但担心睡醒之后记不清。",
                category: "习惯",
                context: "当天已经很累，但有两个选择还没记录。",
                options: "今晚记录 / 明早补 / 放弃记录",
                choice: "明早补",
                reasoning: "担心疲劳状态下记录质量低。",
                expectedResult: "明早还能完整回忆。",
                actualResult: "",
                lesson: "",
                analysisReport: "",
                emotion: .avoidant,
                errorType: .none,
                confidence: 52,
                qualityScore: 3,
                createdAt: now,
                reviewAt: Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now,
                status: .pending
            )
        ]
        principles = [
            Principle(
                text: "当我准备接新项目时，如果交付边界还不清楚，我应该先确认时间、责任和验收标准。",
                sourceDecisionTitle: "是否接下一个边界不清的新项目",
                scene: "项目判断"
            )
        ]
        selectedDecisionID = decisions.first?.id
    }
}

private struct StoreSnapshot: Codable {
    var decisions: [Decision]
    var principles: [Principle]
}

private extension JSONEncoder {
    static var app: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var app: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case today = "今日"
    case pending = "待复盘"
    case report = "报告"
    case principles = "经验库"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .today: return "sun.max"
        case .pending: return "clock.badge.exclamationmark"
        case .report: return "doc.text.magnifyingglass"
        case .principles: return "sparkles"
        }
    }
}

enum AppPalette {
    static let ink = Color(red: 0.23, green: 0.17, blue: 0.10)
    static let brown = Color(red: 0.42, green: 0.28, blue: 0.12)
    static let amber = Color(red: 1.00, green: 0.76, blue: 0.27)
    static let amberDeep = Color(red: 0.94, green: 0.57, blue: 0.15)
    static let cream = Color(red: 1.00, green: 0.97, blue: 0.90)
    static let mint = Color(red: 0.60, green: 0.84, blue: 0.75)
}

struct RootView: View {
    @EnvironmentObject private var store: DecisionStore

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 920
            let isVeryCompact = proxy.size.width < 780
            let hidesList = false

            ZStack {
                Color.white
                .ignoresSafeArea()

                HStack(spacing: 0) {
                    SidebarView(isCompact: isCompact)
                        .frame(width: isCompact ? 76 : 210)

                    Divider().opacity(0.25)

                    switch store.selectedSection {
                    case .today, .pending:
                        DecisionWorkspaceView(isCompact: isCompact, isVeryCompact: isVeryCompact, hidesList: hidesList)
                    case .report:
                        ReportView(isCompact: isCompact)
                    case .principles:
                        PrinciplesView()
                    }
                }
                .background(Color.white)
            }
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var store: DecisionStore
    let isCompact: Bool

    var body: some View {
        VStack(alignment: isCompact ? .center : .leading, spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    DecisionLogoMark(size: 42)
                }
                .frame(width: 42, height: 42)

                if !isCompact {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("复盘")
                            .font(.system(size: 19, weight: .bold))
                        Text("每天一次复盘")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, isCompact ? 56 : 34)
            .padding(.horizontal, isCompact ? 0 : 18)

            VStack(spacing: 6) {
                ForEach(SidebarSection.allCases) { section in
                    Button {
                        store.selectedSection = section
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: section.icon)
                                .frame(width: 22)
                            if !isCompact {
                                Text(section.rawValue)
                                Spacer()
                                if section == .pending {
                                    CountBadge(count: store.pendingDecisions.count)
                                }
                            }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(store.selectedSection == section ? AppPalette.ink : .primary)
                        .padding(.horizontal, isCompact ? 0 : 14)
                        .frame(width: isCompact ? 46 : nil, height: 42)
                        .frame(maxWidth: isCompact ? 46 : .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(store.selectedSection == section ? AppPalette.amber : Color.white.opacity(0.0))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            if isCompact {
                CountBadge(count: store.todayDecisions.count)
                    .padding(.bottom, 18)
            } else {
                InsightCard(
                    title: "今日节奏",
                    value: "\(store.todayDecisions.count)",
                    subtitle: "个复盘事项已记录",
                    tint: AppPalette.amberDeep
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 20)
            }
        }
    }
}

struct DecisionWorkspaceView: View {
    @EnvironmentObject private var store: DecisionStore
    let isCompact: Bool
    let isVeryCompact: Bool
    let hidesList: Bool

    private var visibleDecisions: [Decision] {
        switch store.selectedSection {
        case .today: return store.todayDecisions
        case .pending: return store.pendingDecisions
        default: return store.todayDecisions
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            if !hidesList {
                VStack(alignment: .leading, spacing: 18) {
                    HeaderView(
                        title: store.selectedSection.rawValue,
                        subtitle: headerSubtitle,
                        buttonTitle: "记录一件事",
                        systemImage: "plus"
                    ) {
                        store.createDecision()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, isCompact ? 18 : 24)

                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(visibleDecisions) { decision in
                                DecisionRow(decision: decision, isSelected: decision.id == store.selectedDecisionID)
                                    .onTapGesture {
                                        store.selectedDecisionID = decision.id
                                    }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                }
                .frame(width: isVeryCompact ? 300 : (isCompact ? 330 : 390))
                .background(Color(red: 0.99, green: 0.98, blue: 0.95))

                Divider().opacity(0.25)
            }

            if hidesList {
                VStack(spacing: 0) {
                    CompactRecordBar(decisions: visibleDecisions)
                    Divider().opacity(0.20)
                    if let decision = store.selectedDecision {
                        DecisionDetailView(decision: decision, isCompact: true)
                    } else {
                        EmptyStateView()
                    }
                }
            } else {
                if let decision = store.selectedDecision {
                    DecisionDetailView(decision: decision, isCompact: isCompact)
                } else {
                    EmptyStateView()
                }
            }
        }
    }

    private var headerSubtitle: String {
        switch store.selectedSection {
        case .today: return "快速记录今天值得复盘的事项"
        case .pending: return "这些选择到了回填结果的时间"
        default: return "今天先记一件真正重要的事"
        }
    }
}

struct DecisionRow: View {
    let decision: Decision
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(decision.title)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(2)
                Spacer()
                StatusPill(text: decision.status.rawValue, color: statusColor)
            }

            Text(decision.choice.isEmpty ? "还没有填写最终选择" : decision.choice)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                SmallTag(text: decision.emotion.rawValue, color: Color(red: 0.45, green: 0.54, blue: 0.86))
                SmallTag(text: "置信度 \(Int(decision.confidence))", color: AppPalette.brown)
                Spacer()
                Text(decision.reviewAt, style: .date)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isSelected ? AppPalette.amber.opacity(0.92) : Color.white.opacity(0.74))
        )
        .foregroundStyle(AppPalette.ink)
        .shadow(color: AppPalette.brown.opacity(isSelected ? 0.16 : 0.06), radius: 18, x: 0, y: 10)
    }

    private var statusColor: Color {
        switch decision.status {
        case .draft: return .orange
        case .pending: return .pink
        case .reviewed: return .green
        }
    }
}

struct CompactRecordBar: View {
    @EnvironmentObject private var store: DecisionStore
    let decisions: [Decision]

    var body: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(decisions) { decision in
                    Button {
                        store.selectedDecisionID = decision.id
                    } label: {
                        Label(decision.title, systemImage: decision.id == store.selectedDecisionID ? "checkmark" : "circle")
                    }
                }
            } label: {
                Label(currentTitle, systemImage: "list.bullet")
                    .lineLimit(1)
            }
            .buttonStyle(SecondaryButtonStyle())

            Spacer()

            Button {
                store.createDecision()
            } label: {
                Label("记录一件事", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color(red: 0.99, green: 0.98, blue: 0.95))
    }

    private var currentTitle: String {
        decisions.first(where: { $0.id == store.selectedDecisionID })?.title ?? "选择记录"
    }
}

struct DecisionDetailView: View {
    @EnvironmentObject private var store: DecisionStore
    @State var decision: Decision
    @State private var isAIWorking = false
    @State private var aiMessage: String?
    let isCompact: Bool

    var body: some View {
        GeometryReader { proxy in
            let formCompact = isCompact || proxy.size.width < 820

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("今天这一件事")
                            .font(.system(size: formCompact ? 24 : 28, weight: .bold))
                        Text("记录事件、原因、结果和经验。")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        store.selectedDecision = decision
                    } label: {
                        Label("保存", systemImage: "checkmark")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }

                VStack(spacing: 18) {
                    FieldBlock(title: "先随手写") {
                        TextArea(
                            text: quickNoteBinding,
                            placeholder: "把脑子里的原话写在这里就行。例如：我今天又拖到很晚才处理这件事，导致后面很被动。也可以写一次选择、遗忘、沟通失误或执行偏差。",
                            minHeight: 94
                        )
                    }

                    HStack(spacing: 12) {
                        Button {
                            runAIOrganize()
                        } label: {
                            Label(isAIWorking ? "正在整理" : "AI 帮我整理", systemImage: "sparkles")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isAIWorking)

                        Button {
                            runAIRefine()
                        } label: {
                            Label("AI 润色复盘", systemImage: "text.bubble")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(isAIWorking)

                        Text("使用 Codex CLI · gpt-5.5")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)

                        Spacer()
                    }

                    if isAIWorking {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView()
                                .progressViewStyle(.linear)
                                .tint(AppPalette.amberDeep)
                            Text("正在分析你的随手记录，通常需要几十秒。")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let aiMessage {
                        Text(aiMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(aiMessage.contains("失败") ? .red : .secondary)
                    }

                    ResponsiveFields(isCompact: formCompact) {
                        FieldBlock(title: "复盘事项") {
                            TextField("例如：又拖到晚上才处理重要事项", text: $decision.title)
                                .textFieldStyle(.plain)
                                .font(.system(size: formCompact ? 19 : 24, weight: .bold))
                        }
                    } right: {
                        FieldBlock(title: "复盘类型") {
                            Picker("", selection: categoryBinding) {
                                ForEach(["决策", "拖延", "遗忘", "沟通", "执行", "习惯", "工作", "其他"], id: \.self) { item in
                                    Text(item).tag(item)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    FieldBlock(title: "事件背景") {
                        TextArea(text: $decision.context, placeholder: "当时发生了什么？有什么约束、时间压力、关键人或关键信息？", minHeight: 86)
                    }

                    ResponsiveFields(isCompact: formCompact) {
                        FieldBlock(title: "我的行动/选择") {
                            TextArea(text: $decision.choice, placeholder: "写你实际做了什么，或当时选择了什么。比如：一直拖着没处理，直到晚上才开始。", minHeight: 86)
                        }
                    } right: {
                        FieldBlock(title: "原因或触发点") {
                            TextArea(text: $decision.reasoning, placeholder: "写造成这个结果的原因。比如：低估耗时、怕麻烦、没设提醒、信息不清。", minHeight: 86)
                        }
                    }

                    FieldBlock(title: "当时的预期/影响判断") {
                        TextArea(text: $decision.expectedResult, placeholder: "当时以为会怎样？如果是拖延或遗忘，写你当时低估了什么影响。", minHeight: 82)
                    }

                    ControlPanel(decision: $decision, isCompact: formCompact)

                    FieldBlock(title: "实际结果") {
                        TextArea(text: $decision.actualResult, placeholder: "真实结果是什么？造成了什么后果？和当时预期相比哪里偏了？", minHeight: 92)
                    }

                    FieldBlock(title: "经验总结") {
                        TextArea(text: $decision.lesson, placeholder: "沉淀可执行经验：下次遇到类似情况，提前做什么、避免什么、设置什么提醒或检查点。", minHeight: 92)
                    }

                    FieldBlock(title: "完整分析报告") {
                        TextArea(text: analysisReportBinding, placeholder: "AI 会在这里生成完整复盘：事实经过、根因分析、影响评估、经验总结和后续行动。", minHeight: 160)
                    }
                }

                HStack(spacing: 12) {
                    Button(role: .destructive) {
                        store.deleteDecision(decision)
                    } label: {
                        Label("删除记录", systemImage: "trash")
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Spacer()

                    Button {
                        let generated = ReportEngine.singleReport(for: decision)
                        decision.analysisReport = generated
                        decision.lesson = decision.lesson.isEmpty ? ReportEngine.suggestLesson(for: decision) : decision.lesson
                        decision.actualResult = decision.actualResult.isEmpty ? "请补充实际发生的结果。" : decision.actualResult
                    } label: {
                        Label("生成完整复盘", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button {
                        store.markReviewed(decision)
                    } label: {
                        Label("标记已复盘", systemImage: "seal")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
                .padding(formCompact ? 20 : 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(.white.opacity(0.46))
        .onChange(of: store.selectedDecisionID) { _ in
            if let current = store.selectedDecision {
                decision = current
            }
        }
    }

    private var categoryBinding: Binding<String> {
        Binding(
            get: { decision.category ?? "工作" },
            set: { decision.category = $0 }
        )
    }

    private var quickNoteBinding: Binding<String> {
        Binding(
            get: { decision.quickNote ?? "" },
            set: { decision.quickNote = $0 }
        )
    }

    private var analysisReportBinding: Binding<String> {
        Binding(
            get: { decision.analysisReport ?? "" },
            set: { decision.analysisReport = $0 }
        )
    }

    private func runAIOrganize() {
        isAIWorking = true
        aiMessage = nil
        let input = decision
        Task {
            do {
                let result = try await CodexAIService.organize(input)
                await MainActor.run {
                    applyAIResult(result)
                    aiMessage = "已整理到下方字段，记得点保存。"
                    isAIWorking = false
                }
            } catch {
                await MainActor.run {
                    aiMessage = "AI 整理失败：\(error.localizedDescription)"
                    isAIWorking = false
                }
            }
        }
    }

    private func runAIRefine() {
        isAIWorking = true
        aiMessage = nil
        let input = decision
        Task {
            do {
                let result = try await CodexAIService.refine(input)
                await MainActor.run {
                    applyAIResult(result)
                    aiMessage = "已润色，记得点保存。"
                    isAIWorking = false
                }
            } catch {
                await MainActor.run {
                    aiMessage = "AI 润色失败：\(error.localizedDescription)"
                    isAIWorking = false
                }
            }
        }
    }

    private func applyAIResult(_ result: AIOrganizeResult) {
        if let title = result.title, !title.isEmpty { decision.title = title }
        if let category = result.category, !category.isEmpty { decision.category = category }
        if let context = result.context, !context.isEmpty { decision.context = context }
        if let choice = result.choice, !choice.isEmpty { decision.choice = choice }
        if let reasoning = result.reasoning, !reasoning.isEmpty { decision.reasoning = reasoning }
        if let expected = result.expectedResult, !expected.isEmpty { decision.expectedResult = expected }
        if let actual = result.actualResult, !actual.isEmpty { decision.actualResult = actual }
        if let lesson = result.lesson, !lesson.isEmpty { decision.lesson = lesson }
        if let report = result.analysisReport, !report.isEmpty { decision.analysisReport = report }
    }
}

struct ControlPanel: View {
    @Binding var decision: Decision
    let isCompact: Bool

    var body: some View {
        Group {
            if isCompact {
                VStack(alignment: .leading, spacing: 14) {
                    emotionColumn
                    HStack(alignment: .top, spacing: 14) {
                        errorColumn
                        confidenceColumn
                        scoreColumn
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 22) {
                    emotionColumn
                        .frame(width: 360, alignment: .leading)
                    Spacer(minLength: 12)
                    errorColumn
                        .frame(width: 150, alignment: .leading)
                    confidenceColumn
                        .frame(width: 110, alignment: .leading)
                    scoreColumn
                        .frame(width: 96, alignment: .leading)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.72)))
    }

    private var emotionColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            controlLabel("情绪状态")
            Picker("", selection: $decision.emotion) {
                ForEach(Emotion.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
        }
        .frame(maxWidth: isCompact ? .infinity : nil, alignment: .leading)
    }

    private var errorColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            controlLabel("错因归类")
            Picker("", selection: $decision.errorType) {
                ForEach(ErrorType.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .labelsHidden()
        }
        .frame(maxWidth: isCompact ? .infinity : nil, alignment: .leading)
    }

    private var confidenceColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            controlLabel("置信度 \(Int(decision.confidence))")
            Picker("", selection: confidenceBinding) {
                ForEach([20, 40, 60, 80, 100], id: \.self) { value in
                    Text("\(value)").tag(value)
                }
            }
            .labelsHidden()
        }
        .frame(maxWidth: isCompact ? .infinity : nil, alignment: .leading)
    }

    private var scoreColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            controlLabel("质量评分")
            Picker("", selection: $decision.qualityScore) {
                ForEach(1...5, id: \.self) { value in
                    Text("\(value) 分").tag(value)
                }
            }
            .labelsHidden()
        }
        .frame(maxWidth: isCompact ? .infinity : nil, alignment: .leading)
    }

    private func controlLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(height: 16, alignment: .bottomLeading)
    }

    private var confidenceBinding: Binding<Int> {
        Binding(
            get: { Int(decision.confidence) },
            set: { decision.confidence = Double($0) }
        )
    }
}

struct ReportView: View {
    @EnvironmentObject private var store: DecisionStore
    let isCompact: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HeaderView(
                    title: "复盘报告",
                    subtitle: "用结构化记录生成日/周/月复盘，先本地生成，后续可接大模型。",
                    buttonTitle: "复制 Markdown",
                    systemImage: "doc.on.doc"
                ) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ReportEngine.weeklyReport(decisions: store.decisions, principles: store.principles), forType: .string)
                }

                FlexStack(isVertical: isCompact, spacing: 14) {
                    InsightCard(title: "记录总数", value: "\(store.decisions.count)", subtitle: "个复盘事项", tint: AppPalette.brown)
                    InsightCard(title: "待复盘", value: "\(store.pendingDecisions.count)", subtitle: "个需要回填", tint: .pink)
                    InsightCard(title: "经验库", value: "\(store.principles.count)", subtitle: "条可复用经验", tint: .green)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("本周报告")
                        .font(.system(size: 22, weight: .bold))
                    Text(ReportEngine.weeklyReport(decisions: store.decisions, principles: store.principles))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(22)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.80)))
                }
            }
            .padding(28)
        }
    }
}

struct PrinciplesView: View {
    @EnvironmentObject private var store: DecisionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HeaderView(title: "经验库", subtitle: "把复盘结论沉淀成下次可直接参考的经验。", buttonTitle: "新增经验", systemImage: "plus") {
                    store.principles.insert(Principle(text: "当我遇到【场景】时，如果出现【信号】，我应该【行动】。", sourceDecisionTitle: "手动新增", scene: "通用"), at: 0)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)], spacing: 16) {
                    ForEach(store.principles) { principle in
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .center) {
                                Image(systemName: "quote.opening")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.orange)
                                Spacer()
                                Button(role: .destructive) {
                                    store.deletePrinciple(principle)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 13, weight: .bold))
                                        .frame(width: 28, height: 28)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .help("删除这条经验")
                            }
                            Text(principle.text)
                                .font(.system(size: 16, weight: .semibold))
                                .lineSpacing(4)
                            HStack {
                                SmallTag(text: principle.scene, color: .orange)
                                Spacer()
                                Text(principle.sourceDecisionTitle)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(18)
                        .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.76)))
                        .contextMenu {
                            Button(role: .destructive) {
                                store.deletePrinciple(principle)
                            } label: {
                                Label("删除经验", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
    }
}

struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HeaderView(title: "设置", subtitle: "第一版默认本地运行，后续可接 OpenAI、本地大模型或同步到 Obsidian。", buttonTitle: "保存设置", systemImage: "checkmark") {}

            VStack(alignment: .leading, spacing: 16) {
                SettingRow(icon: "brain", title: "AI 复盘引擎", value: "本地模板生成")
                SettingRow(icon: "bell", title: "到期提醒", value: "每天 21:30")
                SettingRow(icon: "folder", title: "数据存储", value: "~/Library/Application Support/DecisionReview")
                SettingRow(icon: "square.and.arrow.up", title: "导出格式", value: "Markdown / PDF")
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.76)))

            Spacer()
        }
        .padding(28)
    }
}

enum ReportEngine {
    static func weeklyReport(decisions: [Decision], principles: [Principle]) -> String {
        let reviewed = decisions.filter { $0.status == .reviewed }
        let pending = decisions.filter { $0.status != .reviewed }
        let topError = mostCommon(decisions.map(\.errorType.rawValue).filter { $0 != ErrorType.none.rawValue }) ?? "暂无明显集中问题"
        let topEmotion = mostCommon(decisions.map(\.emotion.rawValue)) ?? "暂无数据"
        let good = reviewed.max { $0.qualityScore < $1.qualityScore }?.title ?? "暂无"
        let weak = reviewed.min { $0.qualityScore < $1.qualityScore }?.title ?? "暂无"

        return """
        # 本周复盘报告

        ## 总体结论
        本周共记录 \(decisions.count) 个复盘事项，已复盘 \(reviewed.count) 个，待复盘 \(pending.count) 个。当前最需要关注的是【\(topError)】，最常出现的情绪状态是【\(topEmotion)】。

        ## 关键事项
        - 处理较好的事项：\(good)
        - 最需要复盘的事项：\(weak)
        - 到期未复盘：\(pending.map(\.title).prefix(3).joined(separator: "、"))

        ## 高频问题
        - 常见错因：\(topError)
        - 常见情绪：\(topEmotion)
        - 建议动作：做重大选择前，先写清楚预期结果、验证时间和退出条件。

        ## 本周新增经验
        \(principles.prefix(5).map { "- \($0.text)" }.joined(separator: "\n"))

        ## 下周提醒
        - 重要事项提前设置提醒和检查点。
        - 对拖延、遗忘、沟通失误和执行偏差做结果回填。
        - 每天只记录 1-3 个真正影响结果的事项。
        """
    }

    static func suggestLesson(for decision: Decision) -> String {
        let scene = decision.title.isEmpty ? "类似场景" : decision.title
        let signal = decision.errorType == .none ? "信息还不完整" : decision.errorType.rawValue
        return "当我遇到【\(scene)】时，如果出现【\(signal)】，我应该提前设定提醒、检查点和下一步动作。"
    }

    static func singleReport(for decision: Decision) -> String {
        """
        ## 事实经过
        \(decision.context.isEmpty ? "待补充事件背景。" : decision.context)

        ## 当时的行动或选择
        \(decision.choice.isEmpty ? "待补充当时采取的行动或选择。" : decision.choice)

        ## 原因分析
        \(decision.reasoning.isEmpty ? "待补充原因、触发点或当时依据。" : decision.reasoning)

        ## 预期与实际偏差
        - 当时预期：\(decision.expectedResult.isEmpty ? "待补充。" : decision.expectedResult)
        - 实际结果：\(decision.actualResult.isEmpty ? "待回填。" : decision.actualResult)

        ## 经验总结
        \(decision.lesson.isEmpty ? suggestLesson(for: decision) : decision.lesson)

        ## 后续动作
        下次遇到类似事项时，提前确认关键约束，设置提醒或检查点，并在结果出现后及时回填复盘。
        """
    }

    private static func mostCommon(_ values: [String]) -> String? {
        Dictionary(grouping: values, by: { $0 })
            .mapValues(\.count)
            .max { $0.value < $1.value }?
            .key
    }
}

struct AIOrganizeResult: Decodable {
    var title: String?
    var category: String?
    var context: String?
    var choice: String?
    var reasoning: String?
    var expectedResult: String?
    var actualResult: String?
    var lesson: String?
    var analysisReport: String?

    enum CodingKeys: String, CodingKey {
        case title
        case category
        case context
        case choice
        case reasoning
        case expectedResult = "expected_result"
        case actualResult = "actual_result"
        case lesson
        case analysisReport = "analysis_report"
    }
}

enum CodexAIService {
    private static let model = "gpt-5.5"
    private static var didPrewarm = false

    static func prewarm() {
        guard !didPrewarm else { return }
        didPrewarm = true
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
            process.arguments = [
                "codex",
                "-a",
                "never",
                "-s",
                "read-only",
                "exec",
                "--skip-git-repo-check",
                "--ignore-rules",
                "--ignore-user-config",
                "-m",
                model,
                "只输出 OK"
            ]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
        }
    }

    static func organize(_ decision: Decision) async throws -> AIOrganizeResult {
        try await runCodex(mode: "organize", decision: decision)
    }

    static func refine(_ decision: Decision) async throws -> AIOrganizeResult {
        try await runCodex(mode: "refine", decision: decision)
    }

    private static func runCodex(mode: String, decision: Decision) async throws -> AIOrganizeResult {
        let prompt = buildPrompt(mode: mode, decision: decision)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fupan-ai-\(UUID().uuidString).json")

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
                    process.arguments = [
                        "codex",
                        "-a",
                        "never",
                        "-s",
                        "read-only",
                        "exec",
                        "--skip-git-repo-check",
                        "--ignore-rules",
                        "--ignore-user-config",
                        "-m",
                        model,
                        "-o",
                        outputURL.path,
                        prompt
                    ]

                    let errorPipe = Pipe()
                    let outputPipe = Pipe()
                    process.standardInput = FileHandle.nullDevice
                    process.standardOutput = outputPipe
                    process.standardError = errorPipe
                    try process.run()
                    process.waitUntilExit()

                    guard process.terminationStatus == 0 else {
                        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                        let errorText = [stderr, stdout]
                            .joined(separator: "\n")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let message = friendlyError(from: errorText, status: process.terminationStatus)
                        throw NSError(domain: "CodexAI", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
                    }

                    let raw = try String(contentsOf: outputURL, encoding: .utf8)
                    let json = extractJSONObject(from: raw)
                    let data = Data(json.utf8)
                    let result = try JSONDecoder().decode(AIOrganizeResult.self, from: data)
                    try? FileManager.default.removeItem(at: outputURL)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func buildPrompt(mode: String, decision: Decision) -> String {
        let task = mode == "refine" ? "润色并补全已有复盘字段，生成完整分析报告" : "把随手记录整理成结构化复盘字段，并生成完整分析报告"
        return """
        你是 macOS 应用“复盘”的复盘分析助手。请\(task)。

        规则：
        - 只基于用户输入，不编造事实。
        - 输出必须是纯 JSON，不要 Markdown，不要解释。
        - 字段为空且无法判断时输出空字符串。
        - category 只能从：决策、拖延、遗忘、沟通、执行、习惯、工作、其他 中选择。
        - 复盘对象可以是决策，也可以是拖延、遗忘、沟通失误、执行偏差、习惯问题或工作事项。
        - lesson 要给出可执行经验，不要只写一句空泛建议。
        - analysis_report 要完整，包含：事实经过、关键原因、影响/后果、经验总结、下次行动。可以使用 Markdown 小标题。

        输出 JSON 结构：
        {
          "title": "",
          "category": "",
          "context": "",
          "choice": "",
          "reasoning": "",
          "expected_result": "",
          "actual_result": "",
          "lesson": "",
          "analysis_report": ""
        }

        用户输入：
        随手写：\(decision.quickNote ?? "")
        复盘事项：\(decision.title)
        复盘类型：\(decision.category ?? "")
        事件背景：\(decision.context)
        我的行动/选择：\(decision.choice)
        原因或触发点：\(decision.reasoning)
        当时的预期/影响判断：\(decision.expectedResult)
        实际结果：\(decision.actualResult)
        经验总结：\(decision.lesson)
        完整分析报告：\(decision.analysisReport ?? "")
        """
    }

    private static func extractJSONObject(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
            return trimmed
        }
        guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") else {
            return "{}"
        }
        return String(trimmed[start...end])
    }

    private static func friendlyError(from raw: String, status: Int32) -> String {
        if raw.contains("not supported") || raw.contains("Unknown model") || raw.contains("model is not supported") {
            return "\(model) 当前不可用。Codex CLI 返回模型不支持，请确认这个账号支持该模型，或改成可用模型名。"
        }
        if raw.contains("Reading additional input from stdin") {
            return "Codex CLI 正在等待输入，已改用空输入。请再试一次。"
        }
        if raw.contains("invalid_token") || raw.contains("invalid_grant") {
            return "Codex CLI 的某个插件登录失效。主流程已忽略用户规则，但如果仍失败，需要修复 Codex 插件登录状态。"
        }
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Codex CLI 退出码 \(status)。"
        }
        return raw
            .components(separatedBy: .newlines)
            .filter { !$0.contains("WARN") && !$0.contains("ERROR rmcp") && !$0.contains("failed to load skill") }
            .prefix(4)
            .joined(separator: "\n")
    }
}

struct HeaderView: View {
    let title: String
    let subtitle: String
    let buttonTitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 30, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: action) {
                Label(buttonTitle, systemImage: systemImage)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }
}

struct DecisionLogoMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27)
                .fill(
                LinearGradient(
                    colors: [
                        Color(red: 1.00, green: 0.78, blue: 0.27),
                        Color(red: 0.97, green: 0.58, blue: 0.18)
                    ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .fill(Color.white.opacity(0.92))
                .frame(width: size * 0.32, height: size * 0.32)
                .position(x: size * 0.32, y: size * 0.38)
            Circle()
                .fill(Color(red: 1.00, green: 0.50, blue: 0.58))
                .frame(width: size * 0.24, height: size * 0.24)
                .position(x: size * 0.64, y: size * 0.36)
            Circle()
                .fill(AppPalette.mint)
                .frame(width: size * 0.28, height: size * 0.28)
                .position(x: size * 0.60, y: size * 0.66)
            Path { path in
                path.move(to: CGPoint(x: size * 0.32, y: size * 0.38))
                path.addLine(to: CGPoint(x: size * 0.64, y: size * 0.36))
                path.addLine(to: CGPoint(x: size * 0.60, y: size * 0.66))
            }
            .stroke(AppPalette.ink, style: StrokeStyle(lineWidth: size * 0.045, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}

struct FieldBlock<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(AppPalette.ink)
            content
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white)
                        .shadow(color: AppPalette.brown.opacity(0.05), radius: 10, x: 0, y: 6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(red: 0.88, green: 0.86, blue: 0.80), lineWidth: 1)
                )
        }
    }
}

struct TextArea: View {
    @Binding var text: String
    let placeholder: String
    let minHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(placeholder)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.gray.opacity(0.58))
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .padding(.trailing, 8)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $text)
                .font(.system(size: 15))
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .padding(.top, 2)
                .padding(.leading, 0)
                .padding(.trailing, 2)
        }
        .frame(minHeight: minHeight)
    }
}

struct ResponsiveFields<Left: View, Right: View>: View {
    let isCompact: Bool
    @ViewBuilder let left: Left
    @ViewBuilder let right: Right

    var body: some View {
        if isCompact {
            VStack(alignment: .leading, spacing: 16) {
                left
                    .frame(maxWidth: .infinity, alignment: .leading)
                right
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                left
                    .frame(maxWidth: .infinity, alignment: .leading)
                right
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct FlexStack<Content: View>: View {
    let isVertical: Bool
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        if isVertical {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
        } else {
            HStack(alignment: .top, spacing: spacing) {
                content
            }
        }
    }
}

struct InsightCard: View {
    let title: String
    let value: String
    let subtitle: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(tint)
            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.72)))
    }
}

struct SettingRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .frame(width: 30, height: 30)
                .background(Circle().fill(AppPalette.amber))
                .foregroundStyle(AppPalette.ink)
            Text(title)
                .font(.system(size: 15, weight: .bold))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 42, weight: .bold))
            Text("选择一条决策开始编辑")
                .font(.system(size: 20, weight: .bold))
            Text("也可以按 Command + N 新建一条记录。")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(.pink.opacity(0.18)))
    }
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.16)))
            .foregroundStyle(color)
    }
}

struct SmallTag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 12).fill(configuration.isPressed ? AppPalette.amberDeep.opacity(0.72) : AppPalette.amber))
            .foregroundStyle(AppPalette.ink)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 12).fill(configuration.isPressed ? AppPalette.cream.opacity(0.70) : Color.white.opacity(0.86)))
            .foregroundStyle(AppPalette.ink)
    }
}
