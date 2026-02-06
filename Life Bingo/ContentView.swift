//
//  ContentView.swift
//  Life Bingo
//
//  Created by Jason Li on 2026-02-02.
//

import SwiftUI
import Combine
import UIKit

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var tabSelection: MainTab = .bingo

    var body: some View {
        TabView(selection: $tabSelection) {
            GoodDeedView()
                .tabItem {
                    Label(L10n.t("我很棒", appState.language), systemImage: "hands.sparkles")
                }
                .tag(MainTab.good)

            GratitudeView()
                .tabItem {
                    Label(L10n.t("感恩", appState.language), systemImage: "heart")
                }
                .tag(MainTab.gratitude)

            BingoView()
                .tabItem {
                    Label(L10n.t("Bingo", appState.language), systemImage: "square.grid.3x3")
                }
                .tag(MainTab.bingo)

            NavigationStack {
                GoalView()
            }
                .tabItem {
                    Label(L10n.t("記錄", appState.language), systemImage: "list.bullet.rectangle")
                }
                .tag(MainTab.record)

            RewardsView()
                .tabItem {
                    Label(L10n.t("獎勵", appState.language), systemImage: "gift")
                }
                .tag(MainTab.rewards)
        }
        .tint(Theme.accent)
        .environment(\.appLanguage, appState.language)
        .fullScreenCover(isPresented: Binding(get: {
            !appState.hasOnboarded
        }, set: { _ in })) {
            OnboardingView()
        }
        .fullScreenCover(isPresented: Binding(get: {
            appState.needsDailyCheckin
        }, set: { _ in })) {
            DailyCheckinView()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}

enum MainTab: Int {
    case good
    case gratitude
    case bingo
    case record
    case rewards
}

struct BingoView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.appLanguage) private var appLanguage
    @State private var showSettings = false
    @State private var flipStates: [Bool] = []
    @State private var isFlipping = false
    @State private var flipTask: Task<Void, Never>? = nil

    var body: some View {
        NavigationStack {
            AppBackground {
                VStack(spacing: 14) {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.t("我能做到", appLanguage))
                                .font(Theme.Fonts.caption())
                                .foregroundStyle(Theme.textSecondary)
                            Text(appState.goalSummary)
                                .font(Theme.Fonts.headline(20))
                                .fontWeight(.semibold)
                            NavigationLink {
                                GoalView()
                            } label: {
                                Text(L10n.t("管理目標", appLanguage))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        StatusBadgeView()
                            .padding(10)
                    }

                    HStack {
                        Text(L10n.t("保持節奏，讓心慢慢穩定。", appLanguage))
                            .font(Theme.Fonts.caption())
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Button(L10n.t("換一換", appLanguage)) {
                            appState.refreshBoardByUser()
                        }
                        .font(Theme.Fonts.caption())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.surfaceAlt)
                        .clipShape(Capsule())
                        .foregroundStyle(Theme.textSecondary)
                        .disabled(appState.isGeneratingTasks)
                        .opacity(appState.isGeneratingTasks ? 0 : 1)
                        .overlay {
                            if appState.isGeneratingTasks {
                                ProgressView()
                                    .tint(Theme.textSecondary)
                            }
                        }
                    }

                    LazyVGrid(columns: gridColumns, spacing: 10) {
                        ForEach(Array(appState.board.cells.enumerated()), id: \.element.id) { index, cell in
                            FlipCard(isFaceUp: flipStates.indices.contains(index) ? flipStates[index] : true) {
                                BingoCellView(cell: cell)
                            } back: {
                                BlankBingoCellView()
                            }
                            .allowsHitTesting(!appState.isGeneratingTasks && !isFlipping && (flipStates.indices.contains(index) ? flipStates[index] : true))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
            .navigationTitle(L10n.t("Bingo", appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear {
            syncFlipStates(faceUp: !appState.isGeneratingTasks)
        }
        .onChange(of: appState.isGeneratingTasks) { _, isGenerating in
            animateFlip(toFaceUp: !isGenerating)
        }
        .onChange(of: appState.board.cells.map(\.id)) { _, _ in
            syncFlipStates(faceUp: !appState.isGeneratingTasks)
        }
        .alert("完整 Bingo!", isPresented: $appState.showFullBoardReward) {
            Button("太棒了") {
                appState.showFullBoardReward = false
            }
        } message: {
            Text("獲得 1 張任務豁免券")
        }
        .alert("ChatGPT 生成失敗", isPresented: Binding(get: {
            appState.aiErrorMessage != nil
        }, set: { _ in
            appState.aiErrorMessage = nil
        })) {
            Button("知道了") {
                appState.aiErrorMessage = nil
            }
        } message: {
            Text(appState.aiErrorMessage ?? "請稍後再試")
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: appState.board.size)
    }

    private var completedCells: Int {
        appState.board.cells.filter { $0.isDone }.count
    }

    private func syncFlipStates(faceUp: Bool) {
        let count = appState.board.cells.count
        if flipStates.count != count {
            flipStates = Array(repeating: faceUp, count: count)
        } else if !faceUp {
            flipStates = Array(repeating: false, count: count)
        }
    }

    private func animateFlip(toFaceUp faceUp: Bool) {
        flipTask?.cancel()
        syncFlipStates(faceUp: !faceUp)
        isFlipping = true
        let indices = Array(flipStates.indices)
        flipTask = Task {
            for index in indices {
                try? await Task.sleep(nanoseconds: 280_000_000)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 1.12)) {
                        if flipStates.indices.contains(index) {
                            flipStates[index] = faceUp
                        }
                    }
                }
            }
            await MainActor.run {
                isFlipping = false
            }
        }
    }
}

struct BingoCellView: View {
    @EnvironmentObject var appState: AppState
    let cell: BingoCell
    @State private var showAction = false

    var body: some View {
        Button {
            if showAction {
                return
            }
            appState.toggleCell(cell)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(cell.isDone ? Theme.accentSoft : Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                Text(cell.title)
                    .font(Theme.Fonts.caption())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(cell.isDone ? Theme.accent : Theme.textPrimary)
                    .padding(8)
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0.5) {
            showAction = true
        }
        .overlay {
            if showAction {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.surfaceAlt.opacity(0.95))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Theme.border, lineWidth: 1)
                        )
                    VStack(spacing: 8) {
                        if !cell.isDone && appState.skipTickets > 0 {
                            actionButton(title: "使用豁免", filled: true) {
                                appState.useSkip(on: cell)
                                showAction = false
                            }
                        }
                        actionButton(title: "不感興趣", filled: false) {
                            appState.blockTask(cell)
                            showAction = false
                        }
                    }
                    .padding(10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay(alignment: .topTrailing) {
            if showAction {
                Button {
                    showAction = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textSecondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .topTrailing) {
            if cell.isDone {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
                    .padding(6)
            }
        }
    }

    private func actionButton(title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Fonts.caption())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .background(filled ? Theme.accent : Theme.surface)
        .foregroundStyle(filled ? .white : Theme.textPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(filled ? Color.clear : Theme.border, lineWidth: 1)
        )
        .buttonStyle(.plain)
    }
}

struct BlankBingoCellView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Theme.border, lineWidth: 1)
                )
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct FlipCard<Front: View, Back: View>: View {
    let isFaceUp: Bool
    let front: Front
    let back: Back

    init(isFaceUp: Bool, @ViewBuilder front: () -> Front, @ViewBuilder back: () -> Back) {
        self.isFaceUp = isFaceUp
        self.front = front()
        self.back = back()
    }

    var body: some View {
        ZStack {
            front
                .opacity(isFaceUp ? 1 : 0)
                .rotation3DEffect(.degrees(isFaceUp ? 0 : 180), axis: (x: 0, y: 1, z: 0))
            back
                .opacity(isFaceUp ? 0 : 1)
                .rotation3DEffect(.degrees(isFaceUp ? -180 : 0), axis: (x: 0, y: 1, z: 0))
        }
    }
}

private enum DeleteTarget: Identifiable {
    case goal(String)
    case subgoal(goal: String, index: Int)

    var id: String {
        switch self {
        case .goal(let goal):
            return "goal:\(goal)"
        case .subgoal(let goal, let index):
            return "subgoal:\(goal):\(index)"
        }
    }
}

struct GoalView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.appLanguage) private var appLanguage
    @State private var goals: [String] = []
    @State private var newGoal: String = ""
    @State private var showAddField = false
    @State private var isEditing = false
    @State private var goalEdits: [String] = []
    @State private var expandedGoals: Set<String> = []
    @State private var subgoalInputs: [String: String] = [:]
    @State private var showSubgoalInput: Set<String> = []
    @State private var habitGuideResetToken = 0
    @State private var isGeneratingGuide = false
    @State private var deleteTarget: DeleteTarget?
    @State private var showSettings = false

    var body: some View {
        AppBackground {
            ScrollView {
                VStack(spacing: 18) {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(L10n.t("你的習慣", appLanguage))
                                    .font(Theme.Fonts.headline(20))
                                    .fontWeight(.semibold)
                                Spacer()
                                StatusBadgeView()
                                Button {
                                    toggleEditMode()
                                } label: {
                                    Image(systemName: isEditing ? "checkmark" : "pencil")
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .buttonStyle(.plain)
                            }

                            if goals.isEmpty {
                                EmptyStatePanel(
                                    systemImage: "leaf",
                                    title: "尚無目標",
                                    message: "新增一個你想完成的小目標。"
                                )
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(goals.indices, id: \.self) { index in
                                        let goal = goals[index]
                                        HabitRow(
                                            title: goal,
                                            editableTitle: Binding(
                                                get: { goalEdits.indices.contains(index) ? goalEdits[index] : goal },
                                                set: { newValue in
                                                    if goalEdits.indices.contains(index) {
                                                        goalEdits[index] = newValue
                                                    }
                                                }
                                            ),
                                            isEditing: isEditing,
                                            resetToken: habitGuideResetToken,
                                            stage: appState.stageForGoal(goal),
                                            isPriority: appState.priorityGoals.contains(goal),
                                            completedCount: completedCount(for: goal),
                                            progressLevel: progressLevel(for: goal),
                                            isExpanded: expandedGoals.contains(goal),
                                            subgoals: appState.goalSubgoals[goal] ?? [],
                                            inputText: Binding(
                                                get: { subgoalInputs[goal] ?? "" },
                                                set: { subgoalInputs[goal] = $0 }
                                            ),
                                            isAddingSubgoal: showSubgoalInput.contains(goal),
                                            habitGuide: appState.habitGuides[goal],
                                            currentStage: appState.stageForGoal(goal),
                                            onToggleExpand: {
                                                toggleExpand(for: goal)
                                                appState.requestHabitGuide(for: goal)
                                            },
                                            onTogglePriority: {
                                                appState.togglePriorityGoal(goal)
                                            },
                                            onToggleAddSubgoal: {
                                                toggleAddSubgoal(for: goal)
                                            },
                                            onSaveSubgoal: {
                                                let text = subgoalInputs[goal] ?? ""
                                                appState.addSubgoal(for: goal, text: text)
                                                subgoalInputs[goal] = ""
                                                showSubgoalInput.remove(goal)
                                            },
                                            onUpdateSubgoal: { subIndex, text in
                                                appState.updateSubgoal(for: goal, at: subIndex, text: text)
                                            },
                                            onDeleteSubgoal: { subIndex in
                                                deleteTarget = .subgoal(goal: goal, index: subIndex)
                                            },
                                            onDeleteGoal: {
                                                deleteTarget = .goal(goal)
                                            }
                                        )
                                    }
                                }
                            }

                            if showAddField {
                                VStack(spacing: 10) {
                                    TextField("例如：早睡、運動、閱讀", text: $newGoal)
                                        .themedField()
                                    HStack(spacing: 8) {
                                        Button("添加") {
                                            let trimmed = newGoal.trimmingCharacters(in: .whitespacesAndNewlines)
                                            guard !trimmed.isEmpty else { return }
                                            if !goals.contains(trimmed) {
                                                goals.append(trimmed)
                                                commitGoals()
                                            }
                                            newGoal = ""
                                            showAddField = false
                                        }
                                        .buttonStyle(PrimaryButtonStyle())
                                        Button("取消") {
                                            newGoal = ""
                                            showAddField = false
                                        }
                                        .buttonStyle(SecondaryButtonStyle())
                                    }
                                }
                            } else {
                                if expandedGoals.isEmpty {
                                    Button(L10n.t("添加習慣", appLanguage)) {
                                        showAddField = true
                                    }
                                    .buttonStyle(PrimaryButtonStyle())
                                } else {
                                    Button(L10n.t("添加小目標", appLanguage)) {
                                        if let goal = expandedGoals.first {
                                            showSubgoalInput.insert(goal)
                                        }
                                    }
                                    .buttonStyle(PrimaryButtonStyle())
                                }
                            }
                        }
                    }
                    
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { dismissEditors() }
            )
        }
        .navigationTitle(L10n.t("習慣", appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            goals = appState.goals
            goalEdits = goals
        }
        .onChange(of: appState.goals) { _, newValue in
            goals = newValue
            if !isEditing {
                goalEdits = goals
            }
        }
        .onDisappear {
            expandedGoals.removeAll()
            showSubgoalInput.removeAll()
            dismissEditors()
            habitGuideResetToken += 1
        }
        .alert("確認刪除？", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("取消", role: .cancel) {}
            Button("刪除", role: .destructive) {
                guard let deleteTarget else { return }
                switch deleteTarget {
                case .goal(let goal):
                    deleteGoal(goal)
                case .subgoal(let goal, let index):
                    appState.removeSubgoal(for: goal, at: index)
                }
                self.deleteTarget = nil
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    private func commitGoals() {
        appState.updateGoal(habit: goals.joined(separator: "\n"), motivation: appState.motivation)
        goals = appState.goals
    }

    private func toggleExpand(for goal: String) {
        if expandedGoals.contains(goal) {
            expandedGoals.remove(goal)
            showSubgoalInput.remove(goal)
        } else {
            expandedGoals = [goal]
        }
    }

    private func toggleEditMode() {
        if isEditing {
            commitGoalEdits()
        } else {
            goalEdits = goals
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditing.toggle()
        }
    }

    private func commitGoalEdits() {
        guard goalEdits.count == goals.count else {
            goalEdits = goals
            return
        }
        let originalGoals = goals
        for (index, old) in originalGoals.enumerated() {
            let newValue = goalEdits[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newValue.isEmpty else { continue }
            if newValue != old {
                renameGoal(old, to: newValue)
            }
        }
        goals = appState.goals
        goalEdits = goals
    }

    private func toggleAddSubgoal(for goal: String) {
        if showSubgoalInput.contains(goal) {
            showSubgoalInput.remove(goal)
        } else {
            showSubgoalInput.insert(goal)
        }
    }

    private func deleteGoal(_ goal: String) {
        appState.removeGoal(goal)
        goals = appState.goals
        if isEditing {
            goalEdits = goals
        }
        expandedGoals.remove(goal)
        showSubgoalInput.remove(goal)
        subgoalInputs.removeValue(forKey: goal)
    }

    private func renameGoal(_ goal: String, to newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appState.renameGoal(from: goal, to: trimmed)
        goals = appState.goals
        if expandedGoals.contains(goal) {
            expandedGoals.remove(goal)
            expandedGoals.insert(trimmed)
        }
        if showSubgoalInput.contains(goal) {
            showSubgoalInput.remove(goal)
            showSubgoalInput.insert(trimmed)
        }
        if let input = subgoalInputs.removeValue(forKey: goal) {
            subgoalInputs[trimmed] = input
        }
    }

    private func dismissEditors() {
        if isEditing {
            commitGoalEdits()
            isEditing = false
        }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func completedCount(for goal: String) -> Int {
        appState.taskPool.filter { $0.goal == goal && $0.isDone }.count
    }

    private func progressLevel(for goal: String) -> Int {
        min(5, max(1, appState.stageForGoal(goal) + 1))
    }
}

struct RecordView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.appLanguage) private var appLanguage
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            AppBackground {
                ScrollView {
                    VStack(spacing: 18) {
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("我的目標")
                                    .font(Theme.Fonts.caption())
                                    .foregroundStyle(Theme.textSecondary)
                                Text(appState.goalSummary)
                                    .font(Theme.Fonts.headline(20))
                                    .fontWeight(.semibold)
                                ProgressView(value: Double(completedCells), total: Double(max(appState.board.cells.count, 1)))
                                    .tint(Theme.accent)
                                Text("完成 \(completedCells) / \(appState.board.cells.count) 格")
                                    .font(Theme.Fonts.caption())
                                    .foregroundStyle(Theme.textSecondary)
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                    MetricTile(title: "Bingo 線", value: "\(appState.board.rewardedLineIds.count)", systemImage: "line.diagonal")
                                    MetricTile(title: "完成整張", value: "\(appState.board.completedFullBoards)", systemImage: "square.grid.3x3.fill")
                                }
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            StatusBadgeView()
                                .padding(10)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(L10n.t("記錄", appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    private var completedCells: Int {
        appState.board.cells.filter { $0.isDone }.count
    }
}

struct GoodDeedView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.appLanguage) private var appLanguage
    @State private var note = ""
    @State private var showSettings = false
    @State private var showDatePicker = false
    @State private var selectedDate: Date? = nil
    @State private var calendarMonth = Date()
    @State private var rangeStart: Date? = nil
    @State private var rangeEnd: Date? = nil
    @State private var dateFilterMode: DateFilterMode = .single
    @FocusState private var isNoteFocused: Bool

    var body: some View {
        NavigationStack {
            AppBackground {
                ScrollView {
                    VStack(spacing: 18) {
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("我很棒，因為我")
                                    .font(Theme.Fonts.caption())
                                    .foregroundStyle(Theme.textSecondary)
                                TextField("例如：今天拒絕滑手機 30 分鐘", text: $note)
                                    .themedField()
                                    .focused($isNoteFocused)
                                Button(L10n.t("保存", appLanguage)) {
                                    let noteText = note.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !noteText.isEmpty else { return }
                                    appState.addGoodDeed(note: noteText, duration: nil, source: .postRecord)
                                    note = ""
                                    isNoteFocused = false
                                }
                                .buttonStyle(PrimaryButtonStyle())
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            StatusBadgeView()
                                .padding(10)
                        }

                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Text("最新記錄")
                                        .font(Theme.Fonts.caption())
                                        .foregroundStyle(Theme.textSecondary)
                                    Spacer()
                                    if dateFilterMode == .range, let start = rangeStart, let end = rangeEnd {
                                        Text("\(DateKey.string(from: start)) ~ \(DateKey.string(from: end))")
                                            .font(Theme.Fonts.caption())
                                            .foregroundStyle(Theme.textSecondary)
                                    } else if dateFilterMode == .range, let start = rangeStart {
                                        Text(DateKey.string(from: start))
                                            .font(Theme.Fonts.caption())
                                            .foregroundStyle(Theme.textSecondary)
                                    } else if let selectedDate {
                                        Text(DateKey.string(from: selectedDate))
                                            .font(Theme.Fonts.caption())
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                    Button {
                                        calendarMonth = selectedDate ?? Date()
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            showDatePicker.toggle()
                                        }
                                    } label: {
                                        Image(systemName: "calendar")
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Theme.textSecondary)
                                }

                                if showDatePicker {
                                    VStack(spacing: 12) {
                                        HStack(spacing: 8) {
                                            FilterModeButton(title: "單日", isSelected: dateFilterMode == .single) {
                                                dateFilterMode = .single
                                                rangeStart = nil
                                                rangeEnd = nil
                                            }
                                            FilterModeButton(title: "區間", isSelected: dateFilterMode == .range) {
                                                dateFilterMode = .range
                                                selectedDate = nil
                                            }
                                            Spacer()
                                            Button("今天") {
                                                let today = Date()
                                                calendarMonth = today
                                                dateFilterMode = .single
                                                selectedDate = today
                                                rangeStart = nil
                                                rangeEnd = nil
                                            }
                                            .font(Theme.Fonts.caption())
                                            .foregroundStyle(Theme.textSecondary)
                                            .buttonStyle(.plain)
                                        }

                                        CalendarPickerView(
                                            month: calendarMonth,
                                            selectedDate: selectedDate,
                                            rangeStart: rangeStart,
                                            rangeEnd: rangeEnd,
                                            recordDateKeys: recordDateKeys,
                                            onSelect: { pickedDate in
                                                handleDateSelection(pickedDate)
                                            },
                                            onPrev: {
                                                calendarMonth = Calendar.current.date(byAdding: .month, value: -1, to: calendarMonth) ?? calendarMonth
                                            },
                                            onNext: {
                                                calendarMonth = Calendar.current.date(byAdding: .month, value: 1, to: calendarMonth) ?? calendarMonth
                                            }
                                        )
                                        HStack(spacing: 12) {
                                            Button("清除篩選") {
                                                selectedDate = nil
                                                rangeStart = nil
                                                rangeEnd = nil
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    showDatePicker = false
                                                }
                                            }
                                            .buttonStyle(SecondaryButtonStyle())
                                            Button("完成") {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    showDatePicker = false
                                                }
                                            }
                                            .buttonStyle(PrimaryButtonStyle())
                                        }
                                    }
                                }

                                if filteredDeeds.isEmpty {
                                    EmptyStatePanel(
                                        systemImage: "leaf",
                                        title: "尚無記錄",
                                        message: selectedDate == nil ? "先從一件小事開始。" : "這天沒有記錄。"
                                    )
                                } else {
                                    ScrollView(.vertical, showsIndicators: true) {
                                        VStack(spacing: 10) {
                                            ForEach(filteredDeeds) { deed in
                                                RecordItem(title: deed.note, subtitle: DateKey.dateTimeString(from: deed.date))
                                            }
                                        }
                                        .padding(.vertical, 2)
                                    }
                                    .frame(maxHeight: 240)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(L10n.t("我很棒", appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    private var filteredDeeds: [GoodDeed] {
        let all = appState.goodDeeds
        if dateFilterMode == .range, let start = rangeStart, let end = rangeEnd {
            let startDay = Calendar.current.startOfDay(for: start)
            let endDay = Calendar.current.startOfDay(for: end)
            return all.filter { deed in
                let day = Calendar.current.startOfDay(for: deed.date)
                return day >= startDay && day <= endDay
            }
        }
        if dateFilterMode == .range, let start = rangeStart {
            let key = DateKey.string(from: start)
            return all.filter { DateKey.string(from: $0.date) == key }
        }
        guard let selectedDate else { return all }
        let key = DateKey.string(from: selectedDate)
        return all.filter { DateKey.string(from: $0.date) == key }
    }

    private var recordDateKeys: Set<String> {
        Set(appState.goodDeeds.map { DateKey.string(from: $0.date) })
    }

    private func handleDateSelection(_ date: Date) {
        switch dateFilterMode {
        case .single:
            selectedDate = date
            rangeStart = nil
            rangeEnd = nil
        case .range:
            selectedDate = nil
            if rangeStart == nil || rangeEnd != nil {
                rangeStart = date
                rangeEnd = nil
            } else if let start = rangeStart {
                if date < start {
                    rangeEnd = start
                    rangeStart = date
                } else {
                    rangeEnd = date
                }
            }
        }
    }
}

enum DateFilterMode {
    case single
    case range
}

struct FilterModeButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Fonts.caption())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Theme.accent : Theme.surfaceAlt)
                .foregroundStyle(isSelected ? .white : Theme.textPrimary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct CalendarPickerView: View {
    let month: Date
    let selectedDate: Date?
    let rangeStart: Date?
    let rangeEnd: Date?
    let recordDateKeys: Set<String>
    let onSelect: (Date) -> Void
    let onPrev: () -> Void
    let onNext: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: onPrev) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(monthTitle)
                    .font(Theme.Fonts.caption())
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button(action: onNext) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(Theme.Fonts.caption(10))
                        .foregroundStyle(Theme.textSecondary)
                }

                ForEach(dayCells, id: \.id) { cell in
                    if let date = cell.date, let number = cell.number {
                        Button {
                            onSelect(date)
                        } label: {
                            VStack(spacing: 4) {
                                Text("\(number)")
                                    .font(Theme.Fonts.caption())
                                    .foregroundStyle(cell.isSelected ? .white : Theme.textPrimary)
                                Circle()
                                    .fill(Theme.accent)
                                    .frame(width: 4, height: 4)
                                    .opacity(cell.hasRecord ? 1 : 0)
                            }
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(cell.isSelected ? Theme.accent : (cell.isInRange ? Theme.accentSoft : Color.clear))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(cell.isToday ? Theme.accentSoft : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear
                            .frame(minHeight: 34)
                    }
                }
            }
        }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: month)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let firstIndex = max(0, calendar.firstWeekday - 1)
        return Array(symbols[firstIndex...] + symbols[..<firstIndex])
    }

    private var dayCells: [CalendarDayCell] {
        guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let range = calendar.range(of: .day, in: .month, for: startOfMonth) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        let leadingSpaces = (firstWeekday - calendar.firstWeekday + 7) % 7
        let todayKey = DateKey.today()
        let selectedKey = selectedDate.map { DateKey.string(from: $0) }
        let rangeStartKey = rangeStart.map { DateKey.string(from: $0) }
        let rangeEndKey = rangeEnd.map { DateKey.string(from: $0) }

        var cells: [CalendarDayCell] = []
        for _ in 0..<leadingSpaces {
            cells.append(CalendarDayCell(date: nil, number: nil, isSelected: false, isToday: false, hasRecord: false, isInRange: false))
        }

        for day in range {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) else { continue }
            let key = DateKey.string(from: date)
            let inRange: Bool
            if let startKey = rangeStartKey, let endKey = rangeEndKey {
                inRange = key >= startKey && key <= endKey
            } else {
                inRange = false
            }
            let isSelected = key == selectedKey || key == rangeStartKey || key == rangeEndKey
            cells.append(CalendarDayCell(
                date: date,
                number: day,
                isSelected: isSelected,
                isToday: key == todayKey,
                hasRecord: recordDateKeys.contains(key),
                isInRange: inRange
            ))
        }
        return cells
    }
}

struct CalendarDayCell: Identifiable {
    let id = UUID()
    let date: Date?
    let number: Int?
    let isSelected: Bool
    let isToday: Bool
    let hasRecord: Bool
    let isInRange: Bool
}

struct HabitRow: View {
    let title: String
    let editableTitle: Binding<String>
    let isEditing: Bool
    let resetToken: Int
    let stage: Int
    let isPriority: Bool
    let completedCount: Int
    let progressLevel: Int
    let isExpanded: Bool
    let subgoals: [String]
    @Binding var inputText: String
    let isAddingSubgoal: Bool
    let habitGuide: HabitGuide?
    let currentStage: Int
    let onToggleExpand: () -> Void
    let onTogglePriority: () -> Void
    let onToggleAddSubgoal: () -> Void
    let onSaveSubgoal: () -> Void
    let onUpdateSubgoal: (Int, String) -> Void
    let onDeleteSubgoal: (Int) -> Void
    let onDeleteGoal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 4) {
                    if isEditing {
                        TextField("習慣名稱", text: editableTitle)
                            .font(Theme.Fonts.body())
                            .foregroundStyle(Theme.textPrimary)
                    } else {
                        Text(title)
                            .font(Theme.Fonts.body())
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Text("累積完成 \(completedCount) 格")
                        .font(Theme.Fonts.caption())
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                if isEditing {
                    Button(role: .destructive, action: onDeleteGoal) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .contentShape(Rectangle())

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                        .foregroundStyle(Theme.border)

                    HabitSubgoalSection(
                        subgoals: subgoals,
                        inputText: $inputText,
                        isAdding: isAddingSubgoal,
                        isEditing: isEditing,
                        onToggleAdd: onToggleAddSubgoal,
                        onSave: onSaveSubgoal,
                        onUpdate: onUpdateSubgoal,
                        onDelete: onDeleteSubgoal
                    )

                    HabitGuideSection(
                        guide: habitGuide,
                        currentStage: currentStage,
                        resetToken: resetToken
                    )
                }
            }
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}

struct HabitStageBadge: View {
    let stage: Int

    private var label: String {
        switch stage {
        case 0: return "種子"
        case 1: return "發芽"
        case 2: return "長葉"
        case 3: return "開花"
        case 4: return "扎根"
        default: return "扎根"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.accentSoft)
                .frame(width: 6, height: 6)
            Text(label)
                .font(Theme.Fonts.caption(11))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Theme.surfaceAlt.opacity(0.6))
        .clipShape(Capsule())
    }
}

struct HabitProgressDots: View {
    let level: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { index in
                Circle()
                    .fill(index < level ? Theme.accent : Theme.surfaceAlt)
                    .frame(width: 6, height: 6)
            }
        }
    }
}

struct HabitSubgoalSection: View {
    let subgoals: [String]
    @Binding var inputText: String
    let isAdding: Bool
    let isEditing: Bool
    let onToggleAdd: () -> Void
    let onSave: () -> Void
    let onUpdate: (Int, String) -> Void
    let onDelete: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("小目標")
                    .font(Theme.Fonts.body())
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button(action: onToggleAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            if !subgoals.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(subgoals.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .top, spacing: 10) {
                            ZStack(alignment: .top) {
                                Circle()
                                    .fill(Theme.accentSoft)
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 6)
                            }
                            .frame(width: 12)
                            if isEditing {
                                TextField("小目標", text: Binding(
                                    get: { item },
                                    set: { newValue in onUpdate(index, newValue) }
                                ))
                                .font(Theme.Fonts.body())
                                .foregroundStyle(Theme.textPrimary)
                            } else {
                                Text(item)
                                    .font(Theme.Fonts.body())
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            if isEditing {
                                Button(role: .destructive) {
                                    onDelete(index)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if isAdding {
                TextField("寫下一個小方向（可留空）", text: $inputText)
                    .font(Theme.Fonts.body())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.surfaceAlt.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.border.opacity(0.8), lineWidth: 1)
                    )
                    .submitLabel(.done)
                    .onSubmit { onSave() }
            } else if subgoals.isEmpty {
                Text("尚未設定")
                    .font(Theme.Fonts.body())
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

struct HabitGuideSection: View {
    let guide: HabitGuide?
    let currentStage: Int
    let resetToken: Int
    @State private var expandedStages: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("習慣地圖")
                .font(Theme.Fonts.body())
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textPrimary)

            if let guide {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(guide.stages.enumerated()), id: \.element.stage) { index, stage in
                        HabitGuideStageView(
                            stage: stage,
                            isCurrent: stage.stage == currentStage,
                            isExpanded: expandedStages.contains(stage.stage),
                            isFirst: index == 0,
                            isLast: index == guide.stages.count - 1,
                            onToggle: { toggleStage(stage.stage) }
                        )
                    }
                }
            } else {
                Text("正在整理這條路徑…")
                    .font(Theme.Fonts.body())
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .onChange(of: resetToken) { _, _ in
            collapseAll()
        }
    }

    private func toggleStage(_ stage: Int) {
        if expandedStages.contains(stage) {
            expandedStages.remove(stage)
        } else {
            expandedStages = [stage]
        }
    }
    
    private func collapseAll() {
        expandedStages.removeAll()
    }
}

struct HabitGuideStageView: View {
    let stage: HabitStageGuide
    let isCurrent: Bool
    let isExpanded: Bool
    let isFirst: Bool
    let isLast: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HabitPathMarker(isCurrent: isCurrent, isFirst: isFirst, isLast: isLast)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    HabitStageLabel(stage: stage.stage)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { onToggle() }

                if isExpanded {
                    VStack(spacing: 6) {
                        ForEach(stage.steps) { step in
                            HabitGuideStepItem(step: step)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

struct HabitPathMarker: View {
    let isCurrent: Bool
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Theme.border.opacity(0.5))
                .frame(width: 1)
                .frame(maxHeight: .infinity)
                .opacity(isFirst && isLast ? 0 : 1)

            Circle()
                .fill(Theme.accentSoft)
                .frame(width: 6, height: 6)
                .padding(.top, 4)
        }
        .frame(width: 12)
        .overlay(alignment: .top) {
            if isFirst {
                Rectangle()
                    .fill(Theme.backgroundTop)
                    .frame(width: 1, height: 6)
            }
        }
        .overlay(alignment: .bottom) {
            if isLast {
                Rectangle()
                    .fill(Theme.backgroundTop)
                    .frame(width: 1, height: 6)
            }
        }
    }
}

struct HabitStageLabel: View {
    let stage: Int

    private var label: String {
        switch stage {
        case 0: return "種子"
        case 1: return "發芽"
        case 2: return "長葉"
        case 3: return "開花"
        case 4: return "扎根"
        default: return "扎根"
        }
    }

    var body: some View {
        Text(label)
            .font(Theme.Fonts.body())
            .foregroundStyle(Theme.textPrimary)
    }
}

struct HabitGuideStepItem: View {
    let step: HabitGuideStep

    var body: some View {
        let cleanTitle = step.title.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "  ", with: " ")
        let cleanFallback = step.fallback.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "  ", with: " ")
        let combinedLine = "\(cleanTitle)（或者 \(cleanFallback)）"

        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(combinedLine)
                    .font(Theme.Fonts.body())
                    .foregroundStyle(step.isCompleted ? Theme.textSecondary : Theme.textPrimary)
                    .strikethrough(step.isCompleted, color: Theme.textSecondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                Text("時間 \(step.duration)")
                    .font(Theme.Fonts.caption(12))
                    .foregroundStyle(Theme.textSecondary)

                if !step.bingoTasks.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bingo 任務")
                            .font(Theme.Fonts.caption(11))
                            .foregroundStyle(Theme.textSecondary)
                        ForEach(Array(step.bingoTasks.prefix(5)), id: \.self) { task in
                            Text("• \(task)")
                                .font(Theme.Fonts.caption())
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

struct SwipeDeleteContainer<Content: View>: View {
    let onDelete: () -> Void
    var cornerRadius: CGFloat = 16
    var actionWidth: CGFloat = 72
    var edgeOnly: Bool = false
    var edgeWidth: CGFloat = 44
    let content: Content

    @State private var showConfirm = false
    @State private var dragOffset: CGFloat = 0
    @State private var isOpen = false
    @State private var isHorizontalDrag = false
    @State private var dragStartOffset: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    init(
        onDelete: @escaping () -> Void,
        cornerRadius: CGFloat = 16,
        actionWidth: CGFloat = 72,
        edgeOnly: Bool = false,
        edgeWidth: CGFloat = 44,
        @ViewBuilder content: () -> Content
    ) {
        self.onDelete = onDelete
        self.cornerRadius = cornerRadius
        self.actionWidth = actionWidth
        self.edgeOnly = edgeOnly
        self.edgeWidth = edgeWidth
        self.content = content()
    }

    var body: some View {
        let reveal = min(1, max(0, -dragOffset / actionWidth))
        ZStack(alignment: .trailing) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, reveal * 20)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(alignment: .trailing) {
                    Button(role: .destructive) {
                        showConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.red.opacity(0.7))
                            .frame(width: 20, height: 20)
                    }
                    .padding(.trailing, 8)
                    .opacity(reveal)
                    .allowsHitTesting(reveal > 0.2)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            let dx = value.translation.width
                            let dy = value.translation.height
                            if !isHorizontalDrag {
                                if edgeOnly, containerWidth > 0 {
                                    let edgeStart = max(0, containerWidth - edgeWidth)
                                    if value.startLocation.x < edgeStart {
                                        return
                                    }
                                }
                                if abs(dx) > max(20, abs(dy) * 1.8) {
                                    isHorizontalDrag = true
                                    dragStartOffset = dragOffset
                                } else {
                                    return
                                }
                            }

                            let proposed = dragStartOffset + dx
                            dragOffset = min(0, max(proposed, -actionWidth))
                        }
                        .onEnded { _ in
                            if isHorizontalDrag {
                                if -dragOffset > actionWidth * 0.4 {
                                    open()
                                } else {
                                    close()
                                }
                            }
                            isHorizontalDrag = false
                        }
                )
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { containerWidth = proxy.size.width }
                            .onChange(of: proxy.size.width) { _, newValue in
                                containerWidth = newValue
                            }
                    }
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .simultaneousGesture(
            TapGesture().onEnded {
                if isOpen { close() }
            }
        )
        .alert("確定要刪除？", isPresented: $showConfirm) {
            Button("取消", role: .cancel) { }
            Button("刪除", role: .destructive) {
                close()
                onDelete()
            }
        }
    }

    private func open() {
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.85, blendDuration: 0.12)) {
            dragOffset = -actionWidth
            isOpen = true
        }
    }

    private func close() {
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.85, blendDuration: 0.12)) {
            dragOffset = 0
            isOpen = false
        }
    }
}


struct GratitudeView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.appLanguage) private var appLanguage
    @State private var entryText = ""
    @FocusState private var isEntryFocused: Bool
    @State private var showSettings = false
    @State private var showDatePicker = false
    @State private var selectedDate: Date? = nil
    @State private var calendarMonth = Date()
    @State private var rangeStart: Date? = nil
    @State private var rangeEnd: Date? = nil
    @State private var dateFilterMode: DateFilterMode = .single

    var body: some View {
        NavigationStack {
            AppBackground {
                ScrollView {
                    VStack(spacing: 18) {
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("我感恩今天，因為")
                                    .font(Theme.Fonts.caption())
                                    .foregroundStyle(Theme.textSecondary)
                                TextField("例如：今天心情平靜", text: $entryText)
                                    .themedField()
                                    .focused($isEntryFocused)
                                Button(L10n.t("感謝", appLanguage)) {
                                    appState.addGratitudeItem(entryText)
                                    entryText = ""
                                    isEntryFocused = false
                                }
                                .buttonStyle(PrimaryButtonStyle())
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            StatusBadgeView()
                                .padding(10)
                        }

                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Text("感恩紀錄")
                                        .font(Theme.Fonts.caption())
                                        .foregroundStyle(Theme.textSecondary)
                                    Spacer()
                                    if dateFilterMode == .range, let start = rangeStart, let end = rangeEnd {
                                        Text("\(DateKey.string(from: start)) ~ \(DateKey.string(from: end))")
                                            .font(Theme.Fonts.caption())
                                            .foregroundStyle(Theme.textSecondary)
                                    } else if dateFilterMode == .range, let start = rangeStart {
                                        Text(DateKey.string(from: start))
                                            .font(Theme.Fonts.caption())
                                            .foregroundStyle(Theme.textSecondary)
                                    } else if let selectedDate {
                                        Text(DateKey.string(from: selectedDate))
                                            .font(Theme.Fonts.caption())
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                    Button {
                                        calendarMonth = selectedDate ?? Date()
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            showDatePicker.toggle()
                                        }
                                    } label: {
                                        Image(systemName: "calendar")
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Theme.textSecondary)
                                }

                                if showDatePicker {
                                    VStack(spacing: 12) {
                                        HStack(spacing: 8) {
                                            FilterModeButton(title: "單日", isSelected: dateFilterMode == .single) {
                                                dateFilterMode = .single
                                                rangeStart = nil
                                                rangeEnd = nil
                                            }
                                            FilterModeButton(title: "區間", isSelected: dateFilterMode == .range) {
                                                dateFilterMode = .range
                                                selectedDate = nil
                                            }
                                            Spacer()
                                            Button("今天") {
                                                let today = Date()
                                                calendarMonth = today
                                                dateFilterMode = .single
                                                selectedDate = today
                                                rangeStart = nil
                                                rangeEnd = nil
                                            }
                                            .font(Theme.Fonts.caption())
                                            .foregroundStyle(Theme.textSecondary)
                                            .buttonStyle(.plain)
                                        }

                                        CalendarPickerView(
                                            month: calendarMonth,
                                            selectedDate: selectedDate,
                                            rangeStart: rangeStart,
                                            rangeEnd: rangeEnd,
                                            recordDateKeys: gratitudeDateKeys,
                                            onSelect: { pickedDate in
                                                handleDateSelection(pickedDate)
                                            },
                                            onPrev: {
                                                calendarMonth = Calendar.current.date(byAdding: .month, value: -1, to: calendarMonth) ?? calendarMonth
                                            },
                                            onNext: {
                                                calendarMonth = Calendar.current.date(byAdding: .month, value: 1, to: calendarMonth) ?? calendarMonth
                                            }
                                        )

                                        HStack(spacing: 12) {
                                            Button("清除篩選") {
                                                selectedDate = nil
                                                rangeStart = nil
                                                rangeEnd = nil
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    showDatePicker = false
                                                }
                                            }
                                            .buttonStyle(SecondaryButtonStyle())
                                            Button("完成") {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    showDatePicker = false
                                                }
                                            }
                                            .buttonStyle(PrimaryButtonStyle())
                                        }
                                    }
                                }

                                if filteredEntries.isEmpty {
                                    EmptyStatePanel(
                                        systemImage: "heart.text.square",
                                        title: "還沒有紀錄",
                                        message: selectedDate == nil && rangeStart == nil ? "每天寫下三件感恩的事。" : "這個區間沒有記錄。"
                                    )
                                } else {
                                    ScrollView(.vertical, showsIndicators: true) {
                                        VStack(spacing: 10) {
                                            ForEach(filteredEntries) { entry in
                                                RecordItem(
                                                    title: entry.items.joined(separator: "、"),
                                                    subtitle: entry.dateKey
                                                )
                                            }
                                        }
                                        .padding(.vertical, 2)
                                    }
                                    .frame(maxHeight: 240)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(L10n.t("感恩", appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .buttonStyle(.plain)
                }
            }
        }
        .alert("感恩完成!", isPresented: $appState.showGratitudeBonus) {
            Button("知道了") {
                appState.showGratitudeBonus = false
            }
        } message: {
            Text("完成三件感恩 +1 coin")
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    private var todayEntry: GratitudeEntry? {
        appState.gratitudeEntries.first { $0.dateKey == DateKey.today() }
    }

    private var todayCount: Int {
        todayEntry?.items.count ?? 0
    }

    private var filteredEntries: [GratitudeEntry] {
        let all = appState.gratitudeEntries
        if dateFilterMode == .range, let start = rangeStart, let end = rangeEnd {
            let startKey = DateKey.string(from: start)
            let endKey = DateKey.string(from: end)
            return all.filter { $0.dateKey >= startKey && $0.dateKey <= endKey }
        }
        if dateFilterMode == .range, let start = rangeStart {
            let key = DateKey.string(from: start)
            return all.filter { $0.dateKey == key }
        }
        guard let selectedDate else { return all }
        let key = DateKey.string(from: selectedDate)
        return all.filter { $0.dateKey == key }
    }

    private var gratitudeDateKeys: Set<String> {
        Set(appState.gratitudeEntries.map { $0.dateKey })
    }

    private func handleDateSelection(_ date: Date) {
        switch dateFilterMode {
        case .single:
            selectedDate = date
            rangeStart = nil
            rangeEnd = nil
        case .range:
            selectedDate = nil
            if rangeStart == nil || rangeEnd != nil {
                rangeStart = date
                rangeEnd = nil
            } else if let start = rangeStart {
                if date < start {
                    rangeEnd = start
                    rangeStart = date
                } else {
                    rangeEnd = date
                }
            }
        }
    }
}

struct UpgradeView: View {
    @EnvironmentObject var appState: AppState

    private let levels: [LevelInfo] = [
        LevelInfo(name: "淨身賭狗", minCoins: 0, description: "空空如也，從今天開始養成"),
        LevelInfo(name: "平凡人", minCoins: 20, description: "開始有一些小裝飾"),
        LevelInfo(name: "小康", minCoins: 50, description: "房間變得溫暖舒適"),
        LevelInfo(name: "中產", minCoins: 100, description: "空間更大更精緻"),
        LevelInfo(name: "帝王", minCoins: 200, description: "豪華到閃閃發亮")
    ]

    var body: some View {
        AppBackground {
            ScrollView {
                VStack(spacing: 18) {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("等級")
                                .font(Theme.Fonts.caption())
                                .foregroundStyle(Theme.textSecondary)
                            Text("當前：\(currentLevel.name)")
                                .font(Theme.Fonts.headline(20))
                                .fontWeight(.semibold)
                            Text(currentLevel.description)
                                .font(Theme.Fonts.body())
                                .foregroundStyle(Theme.textSecondary)
                            if let next = nextLevel {
                                ProgressView(value: progress, total: 1)
                                    .tint(Theme.accent)
                                Text("距離 \(next.name) 還差 \(max(next.minCoins - appState.totalCoinsEarned, 0)) coin")
                                    .font(Theme.Fonts.caption())
                                    .foregroundStyle(Theme.textSecondary)
                            } else {
                                Text("已達最高等級")
                                    .font(Theme.Fonts.caption())
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }

                    Card {
                        VStack(spacing: 12) {
                            Text("空間展示")
                                .font(Theme.Fonts.caption())
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(roomGradient)
                                .frame(height: 180)
                                .overlay(
                                    Text(currentLevel.name)
                                        .font(Theme.Fonts.headline(20))
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                            Button("抽盲盒裝飾（即將推出）") {}
                                .buttonStyle(SecondaryButtonStyle())
                                .disabled(true)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
    }

    private var currentLevel: LevelInfo {
        levels.last { appState.totalCoinsEarned >= $0.minCoins } ?? levels[0]
    }

    private var nextLevel: LevelInfo? {
        guard let index = levels.firstIndex(where: { $0.name == currentLevel.name }) else {
            return nil
        }
        let nextIndex = index + 1
        return nextIndex < levels.count ? levels[nextIndex] : nil
    }

    private var progress: Double {
        guard let next = nextLevel else { return 1 }
        let span = Double(next.minCoins - currentLevel.minCoins)
        if span == 0 { return 1 }
        let earned = Double(appState.totalCoinsEarned - currentLevel.minCoins)
        return min(max(earned / span, 0), 1)
    }

    private var roomGradient: LinearGradient {
        switch currentLevel.name {
        case "平凡人":
            return LinearGradient(colors: [Theme.accentSoft, Theme.accent], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "小康":
            return LinearGradient(colors: [Theme.gold.opacity(0.6), Theme.accentSoft], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "中產":
            return LinearGradient(colors: [Theme.accent, Theme.gold.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "帝王":
            return LinearGradient(colors: [Theme.gold, Color.black.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            return LinearGradient(colors: [Theme.surfaceAlt, Theme.accentSoft], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

struct LevelInfo: Hashable {
    let name: String
    let minCoins: Int
    let description: String
}

struct DailyCheckinView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.appLanguage) private var appLanguage
    @State private var moodScore: Double = 50
    @State private var motivationScore: Double = 50
    @State private var difficultyScore: Double = 50

    var body: some View {
        NavigationStack {
            AppBackground {
                ScrollView {
                    VStack(spacing: 18) {
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("今天的狀態")
                                    .font(Theme.Fonts.headline(20))
                                    .fontWeight(.semibold)
                                Text("幫我了解你今天的感受，讓任務更適合你。")
                                    .font(Theme.Fonts.caption())
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }

                        Card {
                            VStack(alignment: .leading, spacing: 16) {
                                CheckinQuestion(title: "今天心情") {
                                    CheckinSlider(
                                        leftLabel: "低落 😔",
                                        rightLabel: "很高興 ☺️",
                                        value: $moodScore
                                    )
                                }
                                CheckinQuestion(title: "今天動機") {
                                    CheckinSlider(
                                        leftLabel: "低 🧎",
                                        rightLabel: "高 💃",
                                        value: $motivationScore
                                    )
                                }
                                CheckinQuestion(title: "昨天 Bingo 的整體感受") {
                                    CheckinSlider(
                                        leftLabel: "容易 😎",
                                        rightLabel: "困難 🙂‍↕️",
                                        value: $difficultyScore
                                    )
                                }
                            }
                        }

                        Button("開始") {
                            appState.saveDailyCheckin(
                                moodScore: Int(moodScore),
                                motivationScore: Int(motivationScore),
                                difficultyScore: Int(difficultyScore)
                            )
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(L10n.t("今日狀態", appLanguage))
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(true)
    }
}

struct CheckinQuestion<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.Fonts.caption())
                .foregroundStyle(Theme.textSecondary)
            content
        }
    }
}

struct CheckinSlider: View {
    let leftLabel: String
    let rightLabel: String
    @Binding var value: Double

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(leftLabel)
                    .font(Theme.Fonts.caption())
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(rightLabel)
                    .font(Theme.Fonts.caption())
                    .foregroundStyle(Theme.textSecondary)
            }
            Slider(value: $value, in: 0...100, step: 1)
                .tint(Theme.accent)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.appLanguage) private var appLanguage
    @State private var apiKey = ""
    @State private var model = ""
    @State private var showKey = false

    var body: some View {
        NavigationStack {
            AppBackground {
                ScrollView {
                    VStack(spacing: 18) {
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(L10n.t("外觀與語言", appLanguage))
                                    .font(Theme.Fonts.caption())
                                    .foregroundStyle(Theme.textSecondary)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text(L10n.t("語言", appLanguage))
                                        .font(Theme.Fonts.caption())
                                        .foregroundStyle(Theme.textSecondary)
                                    HStack(spacing: 8) {
                                        ForEach(AppLanguage.allCases, id: \.self) { lang in
                                            Button {
                                                appState.language = lang
                                            } label: {
                                                Text(lang.displayName)
                                                    .font(Theme.Fonts.caption())
                                                    .foregroundStyle(appState.language == lang ? .white : Theme.textPrimary)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 6)
                                                    .background(appState.language == lang ? Theme.accent : Theme.surfaceAlt)
                                                    .clipShape(Capsule())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text(L10n.t("配色", appLanguage))
                                        .font(Theme.Fonts.caption())
                                        .foregroundStyle(Theme.textSecondary)
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                                        ForEach(ThemeKey.allCases, id: \.self) { key in
                                            let palette = ThemePalette.palette(for: key)
                                            Button {
                                                appState.themeKey = key
                                            } label: {
                                                VStack(spacing: 6) {
                                                    ZStack {
                                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                            .fill(palette.surfaceAlt)
                                                        Circle()
                                                            .fill(palette.accent)
                                                            .frame(width: 14, height: 14)
                                                    }
                                                    .frame(height: 28)
                                                    Text(key.displayName)
                                                        .font(Theme.Fonts.caption(11))
                                                        .foregroundStyle(appState.themeKey == key ? Theme.accent : Theme.textSecondary)
                                                }
                                                .padding(6)
                                                .frame(maxWidth: .infinity)
                                                .background(appState.themeKey == key ? Theme.accentSoft.opacity(0.45) : Color.clear)
                                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                        .stroke(appState.themeKey == key ? Theme.accent : Theme.border, lineWidth: 1)
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }

                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(L10n.t("ChatGPT 設定", appLanguage))
                                    .font(Theme.Fonts.caption())
                                    .foregroundStyle(Theme.textSecondary)
                                if showKey {
                                    TextField(L10n.t("輸入 API Key", appLanguage), text: $apiKey)
                                        .themedField()
                                } else {
                                    SecureField(L10n.t("輸入 API Key", appLanguage), text: $apiKey)
                                        .themedField()
                                }
                                Button(showKey ? L10n.t("隱藏金鑰", appLanguage) : L10n.t("顯示金鑰", appLanguage)) {
                                    showKey.toggle()
                                }
                                .buttonStyle(SecondaryButtonStyle())

                                TextField(L10n.t("模型（預設 gpt-4o-mini）", appLanguage), text: $model)
                                    .themedField()

                                Button(L10n.t("保存", appLanguage)) {
                                    appState.updateOpenAISettings(apiKey: apiKey, model: model)
                                }
                                .buttonStyle(PrimaryButtonStyle())

                                Button(L10n.t("🔄 重新生成所有習慣地圖", appLanguage)) {
                                    // Regenerate support first (always local, meaningful).
                                    appState.forceRegenerateGuideLocally(for: "自愛支持")
                                    // Then regenerate all user goals (use AI for meaningful 21-day guides).
                                    for goal in appState.goals {
                                        appState.requestHabitGuide(for: goal)
                                    }
                                }
                                .buttonStyle(SecondaryButtonStyle())

                            }
                        }

                        Card {
                            Text("建議正式版改用伺服器代理，避免在 App 內保存金鑰。")
                                .font(Theme.Fonts.caption())
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(L10n.t("設定", appLanguage))
        }
        .onAppear {
            apiKey = appState.openAIKey
            model = appState.openAIModel
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.appLanguage) private var appLanguage
    @State private var goalsText = ""
    @State private var apiKey = ""
    @State private var showKey = false
    private let features: [IntroFeature] = [
        IntroFeature(icon: "square.grid.3x3", title: "Bingo 任務", detail: "AI 依你的目標生成 3x3 任務，都是 30 分鐘內可完成的小行動。"),
        IntroFeature(icon: "arrow.triangle.2.circlepath", title: "換一換", detail: "每次換一換都重新請 AI 生成，會避開上次與已完成任務。"),
        IntroFeature(icon: "hands.sparkles", title: "我很棒", detail: "記錄做得好的小事，累積 coin，提醒自己正在前進。"),
        IntroFeature(icon: "heart", title: "感恩", detail: "寫下今天值得感謝的一件事，讓情緒回到穩定。"),
        IntroFeature(icon: "leaf", title: "習慣地圖", detail: "用地圖/足跡看到自己的節奏，不比較、不逼迫。"),
        IntroFeature(icon: "gift", title: "獎勵自己", detail: "用 coin 兌換延後滿足的獎勵，讓好事慢慢發生。")
    ]
    private let flowSteps: [String] = [
        "設定你想好好生活的目標",
        "每天完成 0–9 格都算成功",
        "長按不感興趣可避開類似任務",
        "長按未完成格子可使用豁免"
    ]

    var body: some View {
        NavigationStack {
            AppBackground {
                ScrollView {
                    VStack(spacing: 18) {
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(L10n.t("開始之前", appLanguage))
                                    .font(Theme.Fonts.headline(20))
                                    .fontWeight(.semibold)
                                Text("這是一個讓你「慢慢開始」的 App。先感覺到安全，再慢慢往前。")
                                    .font(Theme.Fonts.body())
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }

                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("你會在這裡做什麼")
                                    .font(Theme.Fonts.body())
                                    .fontWeight(.semibold)
                                VStack(spacing: 10) {
                                    ForEach(features) { feature in
                                        IntroFeatureRow(feature: feature)
                                    }
                                }
                            }
                        }

                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("使用流程")
                                    .font(Theme.Fonts.body())
                                    .fontWeight(.semibold)
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(Array(flowSteps.enumerated()), id: \.offset) { index, step in
                                        HStack(alignment: .top, spacing: 10) {
                                            Text("\(index + 1)")
                                                .font(Theme.Fonts.caption())
                                                .foregroundStyle(.white)
                                                .frame(width: 20, height: 20)
                                                .background(Theme.accent)
                                                .clipShape(Circle())
                                            Text(step)
                                                .font(Theme.Fonts.body())
                                                .foregroundStyle(Theme.textPrimary)
                                        }
                                    }
                                }
                            }
                        }

                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("資料與隱私")
                                    .font(Theme.Fonts.body())
                                    .fontWeight(.semibold)
                                Text("所有資料先保存在本機，你可以隨時刪除或修改。")
                                    .font(Theme.Fonts.body())
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }

                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(L10n.t("你的目標", appLanguage))
                                    .font(Theme.Fonts.caption())
                                    .foregroundStyle(Theme.textSecondary)
                                TextField("例如：早睡、運動、閱讀", text: $goalsText)
                                    .themedField()
                            }
                        }

                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(L10n.t("ChatGPT API Key", appLanguage))
                                    .font(Theme.Fonts.caption())
                                    .foregroundStyle(Theme.textSecondary)
                                if showKey {
                                    TextField(L10n.t("輸入 API Key", appLanguage), text: $apiKey)
                                        .themedField()
                                } else {
                                    SecureField(L10n.t("輸入 API Key", appLanguage), text: $apiKey)
                                        .themedField()
                                }
                                Text("這個金鑰只用來生成你的 Bingo 任務。")
                                    .font(Theme.Fonts.body())
                                    .foregroundStyle(Theme.textSecondary)
                                Button(showKey ? L10n.t("隱藏金鑰", appLanguage) : L10n.t("顯示金鑰", appLanguage)) {
                                    showKey.toggle()
                                }
                                .buttonStyle(SecondaryButtonStyle())
                            }
                        }

                        Button(L10n.t("開始", appLanguage)) {
                            appState.completeOnboarding(goalText: goalsText, apiKey: apiKey)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(goalsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                  apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(L10n.t("歡迎", appLanguage))
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(true)
    }
}

struct IntroFeature: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
}

struct IntroFeatureRow: View {
    let feature: IntroFeature

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: feature.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(Theme.surfaceAlt)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(Theme.Fonts.body())
                    .fontWeight(.semibold)
                Text(feature.detail)
                    .font(Theme.Fonts.body())
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    var systemImage: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28, height: 28)
                    .background(Theme.surfaceAlt)
                    .clipShape(Circle())
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.Fonts.caption())
                    .foregroundStyle(Theme.textSecondary)
                Text(value)
                    .font(Theme.Fonts.body())
                    .fontWeight(.semibold)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surfaceAlt)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct RecordItem: View {
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Theme.accentSoft)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.Fonts.body())
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.Fonts.caption())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

struct EmptyStatePanel: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(Theme.surfaceAlt)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.Fonts.body())
                    .fontWeight(.semibold)
                Text(message)
                    .font(Theme.Fonts.caption())
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surfaceAlt.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct GeneratingView: View {
    @State private var rotate = false

    var body: some View {
        AppBackground {
            VStack(spacing: 16) {
                Card {
                    VStack(spacing: 14) {
                        Text("正在生成 Bingo")
                            .font(Theme.Fonts.headline(20))
                            .fontWeight(.semibold)
                        Text("請稍候片刻，任務即將完成。")
                            .font(Theme.Fonts.caption())
                            .foregroundStyle(Theme.textSecondary)
                        Circle()
                            .trim(from: 0.2, to: 0.9)
                            .stroke(
                                Theme.accent,
                                style: StrokeStyle(lineWidth: 6, lineCap: .round)
                            )
                            .frame(width: 72, height: 72)
                            .rotationEffect(.degrees(rotate ? 360 : 0))
                            .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: rotate)
                    }
                    .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 32)
        }
        .interactiveDismissDisabled(true)
        .onAppear {
            rotate = true
        }
        .onDisappear {
            rotate = false
        }
    }
}
