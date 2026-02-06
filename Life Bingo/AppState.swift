//
//  AppState.swift
//  Life Bingo
//
//  Created by Jason Li on 2025-11-30.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    // MARK: - Core persisted state

    @Published var board: BingoBoard
    @Published var goals: [String]
    @Published var motivation: String

    @Published var themeKey: ThemeKey {
        didSet {
            Theme.apply(themeKey)
            save()
        }
    }

    @Published var language: AppLanguage {
        didSet {
            LanguageStore.code = language.rawValue
            save()
        }
    }

    @Published var priorityGoals: [String]
    @Published var goalSubgoals: [String: [String]]

    /// Habit Maps keyed by goal string.
    @Published var habitGuides: [String: HabitGuide]

    /// A historical pool of generated Bingo cells (used for stats & progress UI).
    @Published var taskPool: [BingoCell]

    @Published var rewardItems: [RewardItem]
    @Published var blockedTopics: [String]

    @Published var dailyCheckin: DailyCheckin?
    @Published var firstUseDateKey: String

    @Published var hasOnboarded: Bool
    @Published var hasGeneratedFirstBoard: Bool

    @Published var coins: Int
    @Published var totalCoinsEarned: Int
    @Published var skipTickets: Int

    @Published var goodDeeds: [GoodDeed]
    @Published var gratitudeEntries: [GratitudeEntry]

    @Published var boardSizePreference: Int

    // MARK: - UI state

    @Published var isGeneratingTasks: Bool = false
    @Published var showFullBoardReward: Bool = false
    @Published var justEarnedSkipTicket: Bool = false
    @Published var showGratitudeBonus: Bool = false
    @Published var aiErrorMessage: String? = nil

    // MARK: - OpenAI settings (persisted via OpenAIStore)

    @Published var openAIKey: String
    @Published var openAIModel: String

    // MARK: - Constants

    private let storageKey = "LifeBingo.state"
    private let supportGoalKey = "自愛支持"

    // MARK: - Init

    init() {
        // Defaults
        self.board = BingoBoard(size: 3, cells: [], rewardedLineIds: [], fullRewarded: false, completedFullBoards: 0)
        self.goals = []
        self.motivation = ""
        self.themeKey = .sage
        self.language = .zhTW
        self.priorityGoals = []
        self.goalSubgoals = [:]
        self.habitGuides = [:]
        self.taskPool = []
        self.rewardItems = []
        self.blockedTopics = []
        self.dailyCheckin = nil
        self.firstUseDateKey = DateKey.today()
        self.hasOnboarded = false
        self.hasGeneratedFirstBoard = false
        self.coins = 0
        self.totalCoinsEarned = 0
        self.skipTickets = 0
        self.goodDeeds = []
        self.gratitudeEntries = []
        self.boardSizePreference = 3

        self.openAIKey = OpenAIStore.apiKey
        self.openAIModel = OpenAIStore.model

        load()

        // Apply theme + language after loading.
        Theme.apply(themeKey)
        if let storedLang = LanguageStore.code, let parsed = AppLanguage(rawValue: storedLang) {
            language = parsed
        }

        ensureSupportHabitGuide()

        if board.cells.isEmpty {
            refreshBoardByUser()
        }
    }

    // MARK: - Computed

    var needsDailyCheckin: Bool {
        guard hasOnboarded else { return false }
        return dailyCheckin?.dateKey != DateKey.today()
    }

    var goalSummary: String {
        if goals.isEmpty {
            return language == .en ? "No goals yet" : "尚未設定目標"
        }
        return goals.joined(separator: "、")
    }

    // MARK: - Persistence

    func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            let decoded = try JSONDecoder().decode(StorageModel.self, from: data)
            board = decoded.board
            goals = decoded.goals
            motivation = decoded.motivation
            themeKey = ThemeKey(rawValue: decoded.themeKey) ?? .sage
            language = AppLanguage(rawValue: decoded.language) ?? .zhTW
            priorityGoals = decoded.priorityGoals
            goalSubgoals = decoded.goalSubgoals
            habitGuides = decoded.habitGuides
            taskPool = decoded.taskPool
            rewardItems = decoded.rewardItems
            blockedTopics = decoded.blockedTopics
            dailyCheckin = decoded.dailyCheckin
            firstUseDateKey = decoded.firstUseDateKey
            hasOnboarded = decoded.hasOnboarded
            hasGeneratedFirstBoard = decoded.hasGeneratedFirstBoard
            coins = decoded.coins
            totalCoinsEarned = decoded.totalCoinsEarned
            skipTickets = decoded.skipTickets
            goodDeeds = decoded.goodDeeds
            gratitudeEntries = decoded.gratitudeEntries
            boardSizePreference = decoded.boardSizePreference
        } catch {
            // If decoding fails, start fresh.
            aiErrorMessage = "資料讀取失敗，已重置：\(error.localizedDescription)"
        }
    }

    func save() {
        let state = StorageModel(
            board: board,
            habit: goals.joined(separator: "、"),
            motivation: motivation,
            themeKey: themeKey.rawValue,
            language: language.rawValue,
            goals: goals,
            priorityGoals: priorityGoals,
            goalSubgoals: goalSubgoals,
            habitGuides: habitGuides,
            taskPool: taskPool,
            rewardItems: rewardItems,
            blockedTopics: blockedTopics,
            dailyKey: DateKey.today(),
            firstUseDateKey: firstUseDateKey,
            hasOnboarded: hasOnboarded,
            hasGeneratedFirstBoard: hasGeneratedFirstBoard,
            dailyCheckin: dailyCheckin,
            coins: coins,
            totalCoinsEarned: totalCoinsEarned,
            skipTickets: skipTickets,
            goodDeeds: goodDeeds,
            gratitudeEntries: gratitudeEntries,
            boardSizePreference: boardSizePreference
        )

        do {
            let data = try JSONEncoder().encode(state)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            aiErrorMessage = "資料保存失敗：\(error.localizedDescription)"
        }
    }

    // MARK: - Goals

    func updateGoal(habit: String, motivation: String, shouldRefresh: Bool = true) {
        let newGoals = Self.parseGoals(from: habit)
        let oldGoals = Set(goals)

        goals = newGoals
        self.motivation = motivation

        // Cleanup priority goals
        priorityGoals = priorityGoals.filter { newGoals.contains($0) }

        // Ensure guides exist
        ensureSupportHabitGuide()
        for goal in goals {
            if habitGuides[goal] == nil {
                habitGuides[goal] = Self.localHabitGuide(for: goal)
                // If AI is configured, kick off generation.
                requestHabitGuide(for: goal)
            }
        }

        // Remove orphan data
        for key in habitGuides.keys where key != supportGoalKey {
            if !newGoals.contains(key) {
                habitGuides.removeValue(forKey: key)
            }
        }
        for key in goalSubgoals.keys {
            if !newGoals.contains(key) {
                goalSubgoals.removeValue(forKey: key)
            }
        }

        save()

        if shouldRefresh {
            refreshBoardByUser()
        }

        // Request guides for newly-added goals
        let added = Set(newGoals).subtracting(oldGoals)
        for goal in added {
            requestHabitGuide(for: goal)
        }
    }

    func removeGoal(_ goal: String) {
        goals.removeAll { $0 == goal }
        priorityGoals.removeAll { $0 == goal }
        goalSubgoals.removeValue(forKey: goal)
        habitGuides.removeValue(forKey: goal)

        // Remove tasks from pool so stats reflect current goals.
        taskPool.removeAll { $0.goal == goal }

        save()
        refreshBoardByUser()
    }

    func renameGoal(from old: String, to newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard old != trimmed else { return }
        guard !goals.contains(trimmed) else { return }

        if let idx = goals.firstIndex(of: old) {
            goals[idx] = trimmed
        }

        if priorityGoals.contains(old) {
            priorityGoals.removeAll { $0 == old }
            priorityGoals.append(trimmed)
        }

        if let subgoals = goalSubgoals.removeValue(forKey: old) {
            goalSubgoals[trimmed] = subgoals
        }

        if let guide = habitGuides.removeValue(forKey: old) {
            var updated = guide
            updated.goal = trimmed
            habitGuides[trimmed] = updated
        }

        // Update taskPool goal labels
        for i in taskPool.indices {
            if taskPool[i].goal == old {
                taskPool[i].goal = trimmed
            }
        }

        // Update board goal labels
        for i in board.cells.indices {
            if board.cells[i].goal == old {
                board.cells[i].goal = trimmed
            }
        }

        save()
        refreshBoardByUser()
    }

    func togglePriorityGoal(_ goal: String) {
        if priorityGoals.contains(goal) {
            priorityGoals.removeAll { $0 == goal }
        } else {
            priorityGoals.append(goal)
        }
        save()
    }

    func addSubgoal(for goal: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = goalSubgoals[goal] ?? []
        list.append(trimmed)
        goalSubgoals[goal] = list
        save()
    }

    func updateSubgoal(for goal: String, at index: Int, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = goalSubgoals[goal] ?? []
        guard list.indices.contains(index) else { return }
        list[index] = trimmed
        goalSubgoals[goal] = list
        save()
    }

    func removeSubgoal(for goal: String, at index: Int) {
        var list = goalSubgoals[goal] ?? []
        guard list.indices.contains(index) else { return }
        list.remove(at: index)
        goalSubgoals[goal] = list
        save()
    }

    // MARK: - Habit Map / Guide

    func stageForGoal(_ goal: String) -> Int {
        guard let guide = habitGuides[goal] else { return 0 }
        let sortedStages = guide.stages.sorted { $0.stage < $1.stage }
        for stage in sortedStages {
            if stage.steps.contains(where: { !$0.isCompleted }) {
                return stage.stage
            }
        }
        return sortedStages.last?.stage ?? 0
    }

    func requestHabitGuide(for goal: String) {
        if goal == supportGoalKey {
            habitGuides[goal] = Self.localHabitGuide(for: goal)
            save()
            return
        }

        // If no key, use local.
        let apiKey = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if apiKey.isEmpty {
            habitGuides[goal] = Self.localHabitGuide(for: goal)
            save()
            return
        }

        Task {
            do {
                let guide = try await OpenAIClient(apiKey: apiKey, model: openAIModel).generateHabitGuide(goal: goal)
                await MainActor.run {
                    self.habitGuides[goal] = guide
                    self.save()
                    self.refreshBoardByUser()
                }
            } catch {
                await MainActor.run {
                    self.aiErrorMessage = "AI 生成失敗：\(error.localizedDescription)"
                    self.habitGuides[goal] = Self.localHabitGuide(for: goal)
                    self.save()
                    self.refreshBoardByUser()
                }
            }
        }
    }

    func forceRegenerateGuideLocally(for goal: String) {
        habitGuides[goal] = Self.localHabitGuide(for: goal)
        save()
        refreshBoardByUser()
    }

    private func ensureSupportHabitGuide() {
        if habitGuides[supportGoalKey] == nil {
            habitGuides[supportGoalKey] = Self.localHabitGuide(for: supportGoalKey)
        }
    }

    // MARK: - Bingo board generation

    func refreshBoardByUser() {
        Task { await regenerateBoardCells() }
    }

    private func regenerateBoardCells() async {
        guard !isGeneratingTasks else { return }
        isGeneratingTasks = true
        defer { isGeneratingTasks = false }

        ensureSupportHabitGuide()
        for goal in goals {
            if habitGuides[goal] == nil {
                habitGuides[goal] = Self.localHabitGuide(for: goal)
            }
        }

        let size = max(3, board.size)
        let totalCount = size * size

        if board.size != size || board.cells.count != totalCount {
            board = BingoBoard(size: size, cells: Array(repeating: BingoCell(id: UUID(), title: "", isDone: false), count: totalCount), rewardedLineIds: [], fullRewarded: false, completedFullBoards: board.completedFullBoards)
        }

        // (removed unused indicesToReplace)

        // If all tasks are empty, treat as initial fill.
        let needsInitialFill = board.cells.allSatisfy { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        let replaceIndices: [Int]
        if needsInitialFill {
            replaceIndices = Array(board.cells.indices)
        } else {
            replaceIndices = board.cells.indices.filter { !board.cells[$0].isDone }
        }

        let usedTitles = Set(board.cells.map { $0.title })

        var candidates = buildCandidateCells(excludingTitles: usedTitles)

        for idx in replaceIndices {
            guard let next = popCandidate(&candidates, excludingTitles: Set(board.cells.map { $0.title })) else {
                board.cells[idx] = BingoCell(id: UUID(), title: "休息一下", isDone: false)
                continue
            }
            board.cells[idx] = next
            taskPool.append(next)
        }

        save()
    }

    private func buildCandidateCells(excludingTitles: Set<String>) -> [BingoCell] {
        var output: [BingoCell] = []

        func isBlocked(_ text: String) -> Bool {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return true }
            for topic in blockedTopics {
                let t = topic.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty, trimmed.contains(t) {
                    return true
                }
            }
            return false
        }

        let goalOrder = goals + [supportGoalKey]
        for goal in goalOrder {
            guard let guide = habitGuides[goal] else { continue }
            let steps = allowedSteps(for: goal, guide: guide)
            for step in steps {
                let options = step.bingoTasks.filter { !isBlocked($0) }
                guard let title = options.first(where: { !excludingTitles.contains($0) }) ?? options.randomElement() else { continue }
                let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanTitle.isEmpty else { continue }
                output.append(BingoCell(id: UUID(), title: cleanTitle, isDone: false, goal: goal == supportGoalKey ? nil : goal, habitStepId: step.id))
            }
        }

        return output.shuffled()
    }

    /// Steps are restricted to: current stage steps + (optionally) the next stage's lowest-resistance (first incomplete) step.
    private func allowedSteps(for goal: String, guide: HabitGuide) -> [HabitGuideStep] {
        let currentStage = stageForGoal(goal)
        let sortedStages = guide.stages.sorted { $0.stage < $1.stage }

        let currentSteps: [HabitGuideStep] = sortedStages.first(where: { $0.stage == currentStage })?.steps.filter { !$0.isCompleted } ?? []

        let nextStep: HabitGuideStep? = sortedStages.first(where: { $0.stage == currentStage + 1 })?.steps.first(where: { !$0.isCompleted })

        if let nextStep {
            return currentSteps + [nextStep]
        }
        return currentSteps
    }

    private func popCandidate(_ candidates: inout [BingoCell], excludingTitles: Set<String>) -> BingoCell? {
        while !candidates.isEmpty {
            let c = candidates.removeFirst()
            if excludingTitles.contains(c.title) { continue }
            return c
        }
        return nil
    }

    // MARK: - Bingo actions

    func toggleCell(_ cell: BingoCell) {
        guard let idx = board.cells.firstIndex(where: { $0.id == cell.id }) else { return }
        if board.cells[idx].isDone { return }

        board.cells[idx].isDone = true

        // Mirror into taskPool (history)
        if let poolIndex = taskPool.firstIndex(where: { $0.id == cell.id }) {
            taskPool[poolIndex].isDone = true
        }

        // Coins
        let earned = estimateCoins(for: cell.title)
        coins += earned
        totalCoinsEarned += earned

        // Mark Habit Map step complete.
        if let goal = cell.goal, let stepId = cell.habitStepId {
            markStepCompleted(goal: goal, stepId: stepId)
        }

        // Bingo progress + rewards
        let progress = board.applyBingoProgress()
        if progress.newLines > 0 {
            let bonus = progress.newLines * 5
            coins += bonus
            totalCoinsEarned += bonus
        }
        if progress.didCompleteFullBoard {
            // Full board bonus
            coins += 50
            totalCoinsEarned += 50
            showFullBoardReward = true

            if !hasGeneratedFirstBoard {
                hasGeneratedFirstBoard = true
                skipTickets += 1
                justEarnedSkipTicket = true
            }
        }

        save()
    }

    private func markStepCompleted(goal: String, stepId: UUID) {
        guard var guide = habitGuides[goal] else { return }
        for stageIndex in guide.stages.indices {
            for stepIndex in guide.stages[stageIndex].steps.indices {
                if guide.stages[stageIndex].steps[stepIndex].id == stepId {
                    guide.stages[stageIndex].steps[stepIndex].isCompleted = true
                }
            }
        }
        guide.updatedAt = Date()
        habitGuides[goal] = guide
    }

    func useSkip(on cell: BingoCell) {
        guard skipTickets > 0 else { return }
        guard let idx = board.cells.firstIndex(where: { $0.id == cell.id }) else { return }
        guard !board.cells[idx].isDone else { return }

        skipTickets -= 1

        let usedTitles = Set(board.cells.map { $0.title })
        var candidates = buildCandidateCells(excludingTitles: usedTitles)

        if let next = popCandidate(&candidates, excludingTitles: usedTitles.union([cell.title])) {
            board.cells[idx] = next
            taskPool.append(next)
        } else {
            board.cells[idx] = BingoCell(id: UUID(), title: "休息一下", isDone: false)
        }

        save()
    }

    func blockTask(_ cell: BingoCell) {
        let trimmed = cell.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !blockedTopics.contains(trimmed) {
            blockedTopics.append(trimmed)
        }
        save()
        refreshBoardByUser()
    }

    // MARK: - Check-in

    func saveDailyCheckin(moodScore: Int, motivationScore: Int, difficultyScore: Int) {
        dailyCheckin = DailyCheckin(
            dateKey: DateKey.today(),
            moodScore: max(0, min(100, moodScore)),
            motivationScore: max(0, min(100, motivationScore)),
            difficultyScore: max(0, min(100, difficultyScore))
        )
        save()
        refreshBoardByUser()
    }

    // MARK: - Rewards

    func addReward(title: String, detail: String, cost: Int, category: RewardCategory) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        rewardItems.append(RewardItem(id: UUID(), title: trimmed, detail: detail, cost: cost, category: category, createdAt: Date(), redeemedAt: nil))
        save()
    }

    /// Returns error message when failed, else nil.
    func redeemReward(_ item: RewardItem) -> String? {
        guard let idx = rewardItems.firstIndex(where: { $0.id == item.id }) else { return "找不到獎勵" }
        guard !rewardItems[idx].isRedeemed else { return "已兌換" }
        guard coins >= rewardItems[idx].cost else { return "coin 不足" }
        coins -= rewardItems[idx].cost
        rewardItems[idx].redeemedAt = Date()
        save()
        return nil
    }

    // MARK: - Good deeds

    func addGoodDeed(note: String, duration: TimeInterval?, source: GoodDeedSource) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let earned = max(1, estimateCoins(for: trimmed) / 2)
        goodDeeds.insert(GoodDeed(note: trimmed, coin: earned, duration: duration, source: source), at: 0)
        coins += earned
        totalCoinsEarned += earned
        save()
    }

    // MARK: - Gratitude

    func addGratitudeItem(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let today = DateKey.today()
        if let idx = gratitudeEntries.firstIndex(where: { $0.dateKey == today }) {
            if !gratitudeEntries[idx].items.contains(trimmed) {
                gratitudeEntries[idx].items.append(trimmed)
            }
        } else {
            gratitudeEntries.insert(GratitudeEntry(id: UUID(), dateKey: today, items: [trimmed], bonusClaimed: false), at: 0)
        }

        if let idx = gratitudeEntries.firstIndex(where: { $0.dateKey == today }) {
            if gratitudeEntries[idx].items.count >= 3 && !gratitudeEntries[idx].bonusClaimed {
                gratitudeEntries[idx].bonusClaimed = true
                coins += 1
                totalCoinsEarned += 1
                showGratitudeBonus = true
            }
        }

        save()
    }

    // MARK: - OpenAI settings

    func updateOpenAISettings(apiKey: String, model: String) {
        openAIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        openAIModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if openAIModel.isEmpty {
            openAIModel = "gpt-4o-mini"
        }
        OpenAIStore.apiKey = openAIKey
        OpenAIStore.model = openAIModel

        ensureSupportHabitGuide()
        for goal in goals {
            requestHabitGuide(for: goal)
        }

        save()
    }

    func completeOnboarding(goalText: String, apiKey: String, model: String = "") {
        if firstUseDateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            firstUseDateKey = DateKey.today()
        }

        updateOpenAISettings(apiKey: apiKey, model: model)
        hasOnboarded = true

        updateGoal(habit: goalText, motivation: motivation, shouldRefresh: true)
        save()
    }

    // MARK: - Helpers

    static func parseGoals(from habit: String) -> [String] {
        let separators = CharacterSet(charactersIn: "、,.，．,以及和與及\n")
        let components = habit.components(separatedBy: separators)
        return components.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func estimateCoins(for task: String) -> Int {
        // Light heuristic: keep it small and predictable.
        let len = task.trimmingCharacters(in: .whitespacesAndNewlines).count
        if len <= 6 { return 1 }
        if len <= 12 { return 2 }
        if len <= 18 { return 3 }
        return 4
    }

    // MARK: - Local Habit Map fallback

    private static func localHabitGuide(for goal: String) -> HabitGuide {
        let stages: [(stage: Int, name: String)] = [
            (0, "種子"),
            (1, "發芽"),
            (2, "長葉"),
            (3, "開花"),
            (4, "扎根")
        ]

        let mastery = "能在不需要提醒下穩定做到「\(goal)」，且遇到狀態低落時仍能用 fallback 維持最小版本。"
        let frictions = [
            "開始前覺得麻煩",
            "情緒/疲勞讓動機下降",
            "環境干擾（手機/雜事）"
        ]

        // Generate 5x5 steps with simple, goal-related structure.
        var stageGuides: [HabitStageGuide] = []
        for stage in stages {
            var steps: [HabitGuideStep] = []
            for i in 1...5 {
                let stepTitle = "\(stage.name) Step \(i)：\(goal) 的最小一步"
                let fallback = "只做 30 秒版本"
                let tasks = [
                    "做 30 秒\(goal)",
                    "做 1 分鐘\(goal)",
                    "做 2 分鐘\(goal)",
                    "把\(goal) 相關工具拿出來",
                    "記錄今天做了\(goal)"
                ]
                steps.append(
                    HabitGuideStep(
                        id: UUID(),
                        title: stepTitle,
                        duration: "1-5 分鐘",
                        fallback: fallback,
                        category: stage.name,
                        isCompleted: false,
                        bingoTasks: tasks
                    )
                )
            }
            stageGuides.append(HabitStageGuide(stage: stage.stage, steps: steps))
        }

        // Special: support goal gets more soothing tasks.
        if goal == "自愛支持" {
            let supportTasks: [String] = [
                "喝一口溫水",
                "站起來伸展 10 秒",
                "看向窗外 30 秒",
                "洗把臉",
                "整理桌面 1 分鐘"
            ]
            stageGuides = stages.map { stage in
                let steps: [HabitGuideStep] = (1...5).map { i in
                    HabitGuideStep(
                        id: UUID(),
                        title: "\(stage.name) Step \(i)：讓身心回到穩定",
                        duration: "1-3 分鐘",
                        fallback: "只做 10 秒",
                        category: stage.name,
                        isCompleted: false,
                        bingoTasks: supportTasks
                    )
                }
                return HabitStageGuide(stage: stage.stage, steps: steps)
            }
            return HabitGuide(goal: goal, masteryDefinition: "能在狀態波動時，仍能用小行動讓自己回到穩定。", frictions: ["太累", "太焦慮", "覺得無效"], stages: stageGuides, updatedAt: Date())
        }

        return HabitGuide(goal: goal, masteryDefinition: mastery, frictions: frictions, stages: stageGuides, updatedAt: Date())
    }
}
