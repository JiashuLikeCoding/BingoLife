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
    /// Last 3 "換一換" boards (titles only), for similarity avoidance.
    @Published var shuffleHistory: [[String]]

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
        self.shuffleHistory = []

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
            shuffleHistory = decoded.shuffleHistory
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
            boardSizePreference: boardSizePreference,
            shuffleHistory: shuffleHistory
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

        // Ensure support guide exists (local).
        ensureSupportHabitGuide()
        // For user goals: do not create local templates; request AI generation if missing.
        for goal in goals {
            if habitGuides[goal] == nil {
                requestHabitGuide(for: goal, forceRegenerate: true)
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

        // Request guides for newly-added goals (without overwriting existing)
        let added = Set(newGoals).subtracting(oldGoals)
        for goal in added {
            requestHabitGuide(for: goal, forceRegenerate: false)
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

    func requestHabitGuide(for goal: String, forceRegenerate: Bool = false) {
        // Support goal can remain local (non-user-entered), to keep the app usable without AI.
        if goal == supportGoalKey {
            if habitGuides[goal] == nil || forceRegenerate {
                habitGuides[goal] = Self.localHabitGuide(for: goal)
                save()
            }
            return
        }

        // If not forcing regeneration and guide already exists, skip AI call.
        if !forceRegenerate, habitGuides[goal] != nil {
            return
        }

        let apiKey = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if apiKey.isEmpty {
            aiErrorMessage = "未設定 OpenAI API Key，無法為『\(goal)』生成習慣地圖。"
            return
        }

        Task {
            do {
                let client = OpenAIClient(apiKey: apiKey, model: openAIModel)

                // 1st attempt
                do {
                    let guide = try await client.generateHabitGuide(goal: goal)
                    await MainActor.run {
                        self.habitGuides[goal] = guide
                        self.aiErrorMessage = nil
                        self.save()
                        self.refreshBoardByUser()
                    }
                    return
                } catch {
                    // 2nd attempt (AI-only self-fix): retry once for better success rate.
                    // Keep the user-visible error only if retry also fails.
                    let firstError = error.localizedDescription
                    do {
                        let guide = try await client.generateHabitGuide(goal: "\(goal)\n\n【修正指示】你上一個輸出不合規：\(firstError)。請修正後重新輸出完整 JSON，並確保符合規則。")
                        await MainActor.run {
                            self.habitGuides[goal] = guide
                            self.aiErrorMessage = nil
                            self.save()
                            self.refreshBoardByUser()
                        }
                        return
                    } catch {
                        await MainActor.run {
                            // Do NOT overwrite an existing guide with local templates.
                            self.aiErrorMessage = "AI 習慣地圖生成失敗（已保留原本內容）：\(error.localizedDescription)"
                            self.save()
                        }
                    }
                }
            }
        }
    }

    func forceRegenerateGuideLocally(for goal: String) {
        // Keep local regeneration only for the internal support goal.
        guard goal == supportGoalKey else {
            aiErrorMessage = "此版本已停用本地習慣地圖模板（僅保留自愛支持）。"
            return
        }
        habitGuides[goal] = Self.localHabitGuide(for: goal)
        save()
        refreshBoardByUser()
    }
    
    /// Manually trigger AI regeneration for a specific goal (user-initiated)
    func regenerateGuideWithAI(for goal: String) {
        requestHabitGuide(for: goal, forceRegenerate: true)
    }

    private func ensureSupportHabitGuide() {
        if habitGuides[supportGoalKey] == nil {
            habitGuides[supportGoalKey] = Self.localHabitGuide(for: supportGoalKey)
        }
    }

    // MARK: - Bingo board generation

    func refreshBoardByUser(useAI: Bool = false) {
        Task { await regenerateBoardCells(useAI: useAI) }
    }

    private func regenerateBoardCells(useAI: Bool) async {
        guard !isGeneratingTasks else { return }
        isGeneratingTasks = true
        defer { isGeneratingTasks = false }

        ensureSupportHabitGuide()
        // For user-entered goals, we do NOT auto-create local habit maps.
        // If a guide is missing, we trigger AI generation and keep the current board as-is.
        let missing = goals.filter { habitGuides[$0] == nil }
        if !missing.isEmpty {
            for g in missing {
                requestHabitGuide(for: g, forceRegenerate: false)
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

        var habitCandidates: [BingoCell] = []
        var supportCandidates: [BingoCell] = []

        func normalized(_ s: String) -> String {
            s.lowercased()
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "，", with: "")
                .replacingOccurrences(of: "。", with: "")
                .replacingOccurrences(of: "、", with: "")
                .replacingOccurrences(of: "！", with: "")
                .replacingOccurrences(of: "？", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func bigrams(_ s: String) -> Set<String> {
            let chars = Array(s)
            guard chars.count >= 2 else { return [] }
            var set: Set<String> = []
            for i in 0..<(chars.count - 1) {
                set.insert(String(chars[i]) + String(chars[i + 1]))
            }
            return set
        }

        func isSimilar(_ a: String, _ b: String) -> Bool {
            let na = normalized(a)
            let nb = normalized(b)
            if na.isEmpty || nb.isEmpty { return false }
            if na == nb { return true }
            if na.count >= 4, nb.count >= 4, (na.contains(nb) || nb.contains(na)) { return true }
            let ba = bigrams(na)
            let bb = bigrams(nb)
            guard !ba.isEmpty, !bb.isEmpty else { return false }
            let inter = ba.intersection(bb).count
            let union = ba.union(bb).count
            let j = Double(inter) / Double(max(1, union))
            return j >= 0.55
        }

        func isSimilarToAny(_ title: String, _ others: [String]) -> Bool {
            others.contains { isSimilar(title, $0) }
        }

        let recentTitles = shuffleHistory.flatMap { $0 }

        if useAI {
            let apiKey = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !apiKey.isEmpty {
                do {
                    let total = max(1, board.cells.count)
                    let done = board.cells.filter { $0.isDone }.count
                    let completionRate = Double(done) / Double(total)
                    let completedLines = board.rewardedLineIds.count
                    let completedFullBoards = board.completedFullBoards

                    let aiTasks = try await OpenAIClient(apiKey: apiKey, model: openAIModel)
                        .generateTasks(
                            habit: goals.joined(separator: "、"),
                            motivation: motivation,
                            size: board.size,
                            completionRate: completionRate,
                            completedLines: completedLines,
                            completedFullBoards: completedFullBoards
                        )

                    // Filter blocked / vague / duplicates / similar-to-last-3-shuffles
                    let filtered = aiTasks
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .filter { task in
                            guard !usedTitles.contains(task) else { return false }
                            let isBlockedTopic = blockedTopics.contains { topic in
                                let tt = topic.trimmingCharacters(in: .whitespacesAndNewlines)
                                return !tt.isEmpty && task.contains(tt)
                            }
                            guard !isBlockedTopic else { return false }
                            if task.contains("再做一次") || task.contains("放在一起") || task.contains("目標物件") || task.contains("打開手機") || task.contains("開始第一個動作") || task.contains("放在顯眼位置") {
                                return false
                            }
                            // Similarity check against last 3 shuffles
                            if recentTitles.contains(where: { isSimilar(task, $0) }) {
                                return false
                            }
                            return true
                        }

                    var seen = Set<String>()
                    for t in filtered {
                        if seen.contains(t) { continue }
                        seen.insert(t)
                        habitCandidates.append(BingoCell(id: UUID(), title: t, isDone: false, goal: "__AI_HABIT__", habitStepId: nil))
                    }
                } catch {
                    await MainActor.run {
                        self.aiErrorMessage = "AI 生成失敗：\(error.localizedDescription)"
                    }
                }
            }
        }

        // Build non-habit (support) candidates from local habit maps.
        // NOTE: buildCandidateCells includes the support goal (its goal is nil), so we can reuse it.
        let mixed = buildCandidateCells(excludingTitles: usedTitles)

        // Support candidates (goal == nil) should also avoid similarity to last 3 shuffles.
        supportCandidates = mixed
            .filter { $0.goal == nil }
            .filter { !isSimilarToAny($0.title, recentTitles) }

        // If we didn't get enough habit candidates from AI, fall back to local habit candidates.
        if habitCandidates.isEmpty {
            habitCandidates = mixed
                .filter { $0.goal != nil }
                .filter { !isSimilarToAny($0.title, recentTitles) }
        }

        func popCandidateMatching(
            _ candidates: inout [BingoCell],
            existingTitles: [String],
            predicate: (BingoCell) -> Bool
        ) -> BingoCell? {
            var index = 0
            while index < candidates.count {
                let c = candidates[index]
                if isSimilarToAny(c.title, existingTitles) || !predicate(c) {
                    index += 1
                    continue
                }
                candidates.remove(at: index)
                return c
            }
            return nil
        }

        var habitRelatedCount = board.cells.filter { $0.goal != nil }.count

        for idx in replaceIndices {
            let existingTitles = board.cells
                .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            // Rule: at most 4 habit-related tasks (goal != nil)
            let wantHabit = habitRelatedCount < 4
            if wantHabit, let next = popCandidateMatching(&habitCandidates, existingTitles: existingTitles, predicate: { $0.goal != nil }) {
                board.cells[idx] = next
                habitRelatedCount += 1
                taskPool.append(next)
                continue
            }

            if let next = popCandidateMatching(&supportCandidates, existingTitles: existingTitles, predicate: { $0.goal == nil }) {
                board.cells[idx] = next
                taskPool.append(next)
                continue
            }

            // Last resort
            board.cells[idx] = fallbackRestCell(existingTitles: existingTitles, recentTitles: recentTitles, isSimilar: isSimilar)
        }

        // Record shuffle history (last 3 boards) only for AI-driven refresh
        if useAI {
            let titles = board.cells.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if !titles.isEmpty {
                shuffleHistory.append(titles)
                if shuffleHistory.count > 3 {
                    shuffleHistory = Array(shuffleHistory.suffix(3))
                }
            }
        }

        save()
    }

    private func fallbackRestCell(
        existingTitles: [String],
        recentTitles: [String],
        isSimilar: (String, String) -> Bool
    ) -> BingoCell {
        // A pool of distinct, concrete micro-rest / support tasks.
        // Must avoid similarity with current board + last 3 shuffles.
        let pool: [String] = [
            "喝一口水",
            "伸展 30 秒",
            "看窗外 30 秒",
            "深呼吸 3 次",
            "走動 1 分鐘",
            "整理桌面 30 秒",
            "洗手並擦乾",
            "把手機放遠 5 分鐘",
            "聽一段音樂 1 分鐘",
            "寫下現在的感受（3 個字）",
            "回想昨天一步（1 句）"
        ]

        func ok(_ t: String) -> Bool {
            let all = existingTitles + recentTitles
            return !all.contains(where: { isSimilar(t, $0) })
        }

        if let title = pool.first(where: ok) {
            return BingoCell(id: UUID(), title: title, isDone: false)
        }

        // Absolute last resort: still keep it explicit and unique-ish.
        return BingoCell(id: UUID(), title: "喝水 10 秒", isDone: false)
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

        func isTooVagueTask(_ text: String) -> Bool {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return true }

            // Hard blacklist for non-actionable / ambiguous placeholders
            let banned: [String] = [
                "再做一次",
                "放在一起",
                "走向目標物件",
                "目標物件",
                "嘗試看看",
                "完成它",
                "開始第一個動作",
                "打開手機",
                "看現在幾點",
                "確認開啟",
                "回想做了什麼",
                "感受進步",
                "放在顯眼位置",
                "形成習慣",
                "自然融入生活",
                "做有挑戰的",
                "想一個新方法",
                "想一個新做法"
            ]
            if banned.contains(where: { trimmed == $0 || trimmed.contains($0) }) {
                return true
            }

            // Too short usually becomes vague in Chinese UI
            if trimmed.count <= 3 { return true }

            // Guard against time selection without specifying what for
            if trimmed.contains("選定明天") && trimmed.contains("時間") && !trimmed.contains("例如") {
                return true
            }

            return false
        }

        let goalOrder = goals + [supportGoalKey]
        for goal in goalOrder {
            guard let guide = habitGuides[goal] else { continue }
            let steps = allowedSteps(for: goal, guide: guide)
            for step in steps {
                let options = step.bingoTasks.map { $0.text }.filter { !isBlocked($0) && !isTooVagueTask($0) }
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

        // Progress Habit Map step completion based on required bingo count.
        if let goal = cell.goal, let stepUUID = cell.habitStepId {
            incrementStepProgress(goal: goal, stepUUID: stepUUID)
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

    private func incrementStepProgress(goal: String, stepUUID: UUID) {
        guard var guide = habitGuides[goal] else { return }
        var didChange = false

        for stageIndex in guide.stages.indices {
            for stepIndex in guide.stages[stageIndex].steps.indices {
                if guide.stages[stageIndex].steps[stepIndex].id == stepUUID {
                    var step = guide.stages[stageIndex].steps[stepIndex]
                    if step.isCompleted { continue }

                    step.completedBingoCount += 1
                    if step.completedBingoCount >= step.requiredBingoCount {
                        step.isCompleted = true
                    }
                    guide.stages[stageIndex].steps[stepIndex] = step
                    didChange = true
                }
            }
        }

        if didChange {
            guide.updatedAt = Date()
            habitGuides[goal] = guide
            save()
        }
    }

    func useSkip(on cell: BingoCell) {
        guard skipTickets > 0 else { return }
        guard let idx = board.cells.firstIndex(where: { $0.id == cell.id }) else { return }
        guard !board.cells[idx].isDone else { return }

        skipTickets -= 1

        let usedTitles = Set(board.cells.map { $0.title })
        var candidates = buildCandidateCells(excludingTitles: usedTitles)

        if let next = popCandidate(&candidates, excludingTitles: usedTitles.union([cell.title])) {
            // Validate that goal reference is valid before assigning
            if let goal = next.goal, habitGuides[goal] == nil {
                // Goal doesn't exist, clear it
                board.cells[idx] = BingoCell(id: UUID(), title: next.title, isDone: false, goal: nil, habitStepId: nil)
            } else {
                board.cells[idx] = next
            }
            taskPool.append(board.cells[idx])
        } else {
            let existingTitles = board.cells
                .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let recentTitles: [String] = shuffleHistory.flatMap { $0 }
            board.cells[idx] = fallbackRestCell(existingTitles: existingTitles, recentTitles: recentTitles, isSimilar: { a, b in
                let na = a.lowercased().replacingOccurrences(of: " ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                let nb = b.lowercased().replacingOccurrences(of: " ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                return na == nb || (!na.isEmpty && !nb.isEmpty && (na.contains(nb) || nb.contains(na)))
            })
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
        // Only generate guides for goals that don't have one yet
        for goal in goals {
            if habitGuides[goal] == nil {
                requestHabitGuide(for: goal, forceRegenerate: false)
            }
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
            (0, "種子"), (1, "發芽"), (2, "長葉"), (3, "開花"), (4, "扎根")
        ]
        let goalLower = goal.lowercased()
        var stageGuides: [HabitStageGuide] = []
        
        // Exercise goal
        if goalLower.contains("運動") || goalLower.contains("健身") || goalLower.contains("exercise") {
            let exerciseSteps: [(title: String, bingoTasks: [String])] = [
                ("選定明日運動時間", ["打開日曆app", "選定明天一個具體時間", "設定鬧鐘"]),
                ("把運動服放在床邊", ["打開衣櫃", "拿出運動褲", "放在床邊椅子上"]),
                ("把運動鞋放門口", ["找出運動鞋", "放在入門處", "確保容易看到"]),
                ("下載運動 App 並打開", ["打開 App Store", "搜尋免費運動App", "下載並打開首頁"]),
                ("選定第一個運動影片", ["打開 YouTube", "搜尋 5 分鐘運動", "收藏一個影片"]),
                ("穿好運動襪", ["拿出運動襪", "坐下穿上", "站起來確認舒適"]),
                ("做 3 下深蹲", ["雙腳與肩同寬", "慢慢蹲下 3 次", "站直"]),
                ("做 5 下深蹲", ["回憶昨天姿勢", "完成 5 次深蹲", "給自己微笑"]),
                ("出門走 3 分鐘", ["穿好鞋子", "開門走出去", "慢走 3 分鐘"]),
                ("出門走 5 分鐘", ["走出家門", "選擇一條路線", "散步 5 分鐘"]),
                ("快走 3 分鐘", ["熱身站姿", "加快腳步", "維持 3 分鐘"]),
                ("快走 5 分鐘", ["回憶昨天路線", "完成 5 分鐘快走", "回家喝水"]),
                ("運動 3 分鐘", ["做原地踏步", "舉手伸展", "完成 3 分鐘"]),
                ("運動 5 分鐘", ["熱身 30 秒", "做簡易運動", "收操 30 秒"]),
                ("運動 10 分鐘", ["跟著影片做", "完成 10 分鐘", "記錄今天表現"]),
                ("運動 15 分鐘", ["熱身 2 分鐘", "加強訓練", "拉伸 3 分鐘"]),
                ("運動 20 分鐘", ["完整熱身", "主要訓練", "緩和運動"]),
                ("運動 25 分鐘", ["熱身 3 分鐘", "訓練 18 分鐘", "緩和 4 分鐘"]),
                ("運動 30 分鐘", ["準備好裝備", "完成 30 分鐘運動", "記錄並稱讚自己"]),
                ("維持運動習慣", ["回顧這週進步", "設定下週目標", "給自己擁抱"]),
                ("中斷後回來", ["原諒自己一次", "明天重新開始", "做 1 分鐘就好"]),
                ("慶祝完成 21 天", ["完成最後一天", "給自己大讚", "決定下一步目標"]),
                ("設定長期計劃", ["每週目標 3 天", "選定具體時間", "準備好裝備"]),
                ("鞏固為習慣", ["不需提醒就能做", "自然融入生活", "對自己沒有苛責"])
            ]
            for stageIndex in 0..<5 {
                var builtSteps: [HabitGuideStep] = []
                let startIdx = stageIndex * 5
                for i in 0..<5 {
                    let idx = startIdx + i
                    if idx < exerciseSteps.count {
                        let task = exerciseSteps[idx]
                        let prefix = ["S","P","L","B","R"][stageIndex]
                        let sid = "\(prefix)\(i+1)"
                        let tasks = task.bingoTasks.enumerated().map { j, t in
                            BingoTask(taskId: "\(sid)-T\(j + 1)", mapsToStep: sid, text: t, durationSec: 45, observable: "完成：\(t)", successProbability: 0.75)
                        }
                        builtSteps.append(HabitGuideStep(id: UUID(), stepId: sid, title: task.title, duration: i < 2 ? "30 秒" : (i < 4 ? "1-3 分鐘" : "3-5 分鐘"), fallback: i == 0 ? "只選定時間，不設鬧鐘" : (i == 1 ? "只把衣服拿出來" : "只做 30 秒"), category: stages[stageIndex].name, requiredBingoCount: 1, completedBingoCount: 0, isCompleted: false, bingoTasks: tasks))
                    }
                }
                stageGuides.append(HabitStageGuide(stage: stageIndex, steps: builtSteps))
            }
        }
        // Sleep goal
        else if goalLower.contains("睡") || goalLower.contains("早睡") || goalLower.contains("sleep") {
            let sleepSteps: [(title: String, bingoTasks: [String])] = [
                ("選定今晚就寢時間", ["看現在幾點", "倒推 8 小時", "寫下就寢時間"]),
                ("設定睡前提醒", ["打開手機鬧鐘", "設就寢前 30 分鐘提醒", "設定鈴聲"]),
                ("準備睡前環境", ["調暗房間燈", "關閉主要光源", "開小夜燈"]),
                ("把手機放客廳", ["充好手機電", "拿手機去客廳", "不再帶進房間"]),
                ("睡前儀式：刷牙洗臉", ["走進浴室", "刷牙 2 分鐘", "用温水洗臉"]),
                ("睡前儀式：換睡衣", ["找出睡衣", "換上舒適衣物", "躺上床"]),
                ("躺上床就閉眼", ["躺好姿勢", "閉上眼睛", "深呼吸 3 次"]),
                ("11 點上床", ["鬧鐘設 10:45", "開始準備", "10:55 躺上床"]),
                ("10:30 上床", ["提早結束活動", "放松心情", "10:20 躺上床"]),
                ("10 點上床", ["倒推準備時間", "9 點開始準備", "10 點入睡"]),
                ("睡前不滑手機", ["手機放客廳", "拿本書翻", "自然想睡"]),
                ("記錄睡眠時間", ["看現在時間", "記錄上床時間", "觀察睡眠長度"]),
                ("改善睡眠環境", ["調暗燈光", "調整房間溫度", "減少噪音"]),
                ("午睡不超過 30 分鐘", ["設鬧鐘 25 分鐘", "醒來後起身", "曬太陽恢復精神"]),
                ("連續早睡 3 天", ["回顧這 3 天", "稱讚自己", "繼續保持"]),
                ("建立固定睡眠時間", ["固定上床時間", "固定起床時間", "讓身體記憶"]),
                ("中斷後回來", ["原諒自己一次", "今晚重新開始", "躺上床就好"]),
                ("慶祝完成 21 天", ["完成最後一天", "給自己大讚", "決定下一步"]),
                ("鞏固為習慣", ["不需提醒就能睡", "自然入睡", "對自己沒有苛責"])
            ]
            for stageIndex in 0..<5 {
                var builtSteps: [HabitGuideStep] = []
                let startIdx = stageIndex * 5
                for i in 0..<5 {
                    let idx = startIdx + i
                    if idx < sleepSteps.count {
                        let task = sleepSteps[idx]
                        let prefix = ["S","P","L","B","R"][stageIndex]
                        let sid = "\(prefix)\(i+1)"
                        let tasks = task.bingoTasks.enumerated().map { j, t in
                            BingoTask(taskId: "\(sid)-T\(j + 1)", mapsToStep: sid, text: t, durationSec: 45, observable: "完成：\(t)", successProbability: 0.75)
                        }
                        builtSteps.append(HabitGuideStep(id: UUID(), stepId: sid, title: task.title, duration: i < 2 ? "1 分鐘" : (i < 4 ? "3-5 分鐘" : "5-10 分鐘"), fallback: i == 0 ? "只寫下時間，不設鬧鐘" : (i == 1 ? "只把鬧鐘設好" : "只躺上床"), category: stages[stageIndex].name, requiredBingoCount: 1, completedBingoCount: 0, isCompleted: false, bingoTasks: tasks))
                    }
                }
                stageGuides.append(HabitStageGuide(stage: stageIndex, steps: builtSteps))
            }
        }
        // Hydration goal
        else if goalLower.contains("喝水") || goalLower.contains("drink") {
            let waterSteps: [(title: String, bingoTasks: [String])] = [
                ("買一個水壺", ["去商店或網購", "選一個喜歡的顏色", "帶回家"]),
                ("把水壺放桌上", ["清洗水壺", "裝滿水", "放在電腦旁"]),
                ("設定喝水提醒", ["打開手機", "設每 2 小時提醒", "確認開啟"]),
                ("喝第一杯水", ["起床後", "倒一杯水", "一口氣喝完"]),
                ("飯前喝一杯水", ["走到廚房", "倒一杯水", "先喝再吃飯"]),
                ("帶水出門", ["出門前裝滿水", "放進背包", "隨時補充"]),
                ("記錄喝水量", ["看喝了幾杯", "寫下杯數", "設定今日目標"]),
                ("提醒自己喝水", ["手機設鬧鐘", "貼便利貼", "想到就喝"]),
                ("喝溫水", ["用熱水器", "調到溫水", "慢慢喝完"]),
                ("取代含糖飲料", ["想喝飲料時", "改喝白開水", "省錢又健康"]),
                ("運動後喝水", ["帶水去運動", "運動後補充", "適量飲用"]),
                ("養成喝水習慣", ["每天追蹤", "持續一週", "稱讚自己"]),
                ("中斷後回來", ["原諒自己一次", "現在喝一杯", "重新開始"]),
                ("慶祝完成 21 天", ["完成最後一天", "給自己大讚", "決定下一步"]),
                ("鞏固為習慣", ["不需提醒就能喝", "自然融入生活", "身體更有水分"])
            ]
            for stageIndex in 0..<5 {
                var builtSteps: [HabitGuideStep] = []
                let startIdx = stageIndex * 5
                for i in 0..<5 {
                    let idx = startIdx + i
                    if idx < waterSteps.count {
                        let task = waterSteps[idx]
                        let prefix = ["S","P","L","B","R"][stageIndex]
                        let sid = "\(prefix)\(i+1)"
                        let tasks = task.bingoTasks.enumerated().map { j, t in
                            BingoTask(taskId: "\(sid)-T\(j + 1)", mapsToStep: sid, text: t, durationSec: 45, observable: "完成：\(t)", successProbability: 0.75)
                        }
                        builtSteps.append(HabitGuideStep(id: UUID(), stepId: sid, title: task.title, duration: "30 秒", fallback: i == 0 ? "只把水壺拿出來" : "只喝一口水", category: stages[stageIndex].name, requiredBingoCount: 1, completedBingoCount: 0, isCompleted: false, bingoTasks: tasks))
                    }
                }
                stageGuides.append(HabitStageGuide(stage: stageIndex, steps: builtSteps))
            }
        }
        // Generic fallback
        else {
            let genericSteps: [(title: String, bingoTasks: [String])] = [
                ("選定明日執行時間", ["打開手機日曆", "選定明天 1 個具體時間（例如 19:00）", "把事件命名為「\(goal)」"]),
                ("準備好所需工具", ["想一下要做 \(goal) 需要什麼", "把其中 1 樣放到桌面上（看得見）", "把其餘先放在同一個位置"]),
                ("設提醒", ["打開手機鬧鐘", "設定明天提醒（寫上 \(goal)）", "確認提醒已開啟"]),
                ("做第一個小行動", ["站起來", "走到要開始 \(goal) 的物件旁（例如書/水杯/鞋）", "做 30 秒的最小動作"]),
                ("記錄今天完成", ["回想剛剛做了什麼", "寫下 1 句具體紀錄", "對自己說「我有開始」"]),
                ("重複昨天的行動", ["回想昨天做的最小步驟", "重做同一個最小步驟（30 秒）", "結束後喝一口水"]),
                ("加一點點量", ["比昨天多做一點", "完成它", "稱讚自己"]),
                ("換個方式做", ["想一個新方法", "嘗試看看", "記錄效果"]),
                ("記錄這一刻", ["花 30 秒記錄", "看看昨天記錄", "給自己肯定"]),
                ("維持連續做", ["今天也做到", "回顧這週", "為明天訂目標"]),
                ("突破小關卡", ["做有挑戰的", "完成後稱讚", "記住這感覺"]),
                ("嘗試新方法", ["想一個新做法", "執行看看", "觀察效果"]),
                ("增加信心", ["完成小任務", "告訴自己可以", "感受自信"]),
                ("獎勵自己", ["做一件開心的事", "享受這一刻", "感謝努力"]),
                ("建立系統", ["固定時間執行", "形成習慣", "持續累積"]),
                ("追蹤進步", ["記錄完成日", "看看累積", "持續前進"]),
                ("慶祝里程碑", ["完成一個階段", "給自己大讚", "期待下一關"]),
                ("中斷後回來", ["原諒自己一次", "明天重新開始", "做最小版本"]),
                ("鞏固為習慣", ["不需提醒就能做", "自然融入生活", "對自己沒有苛責"]),
                ("慶祝完成 21 天", ["完成最後一天", "給自己大讚", "決定下一步"])
            ]
            for stageIndex in 0..<5 {
                var builtSteps: [HabitGuideStep] = []
                let startIdx = stageIndex * 5
                for i in 0..<5 {
                    let idx = startIdx + i
                    if idx < genericSteps.count {
                        let task = genericSteps[idx]
                        let prefix = ["S","P","L","B","R"][stageIndex]
                        let sid = "\(prefix)\(i+1)"
                        let tasks = task.bingoTasks.enumerated().map { j, t in
                            BingoTask(taskId: "\(sid)-T\(j + 1)", mapsToStep: sid, text: t, durationSec: 45, observable: "完成：\(t)", successProbability: 0.75)
                        }
                        builtSteps.append(HabitGuideStep(id: UUID(), stepId: sid, title: task.title, duration: i < 2 ? "30 秒" : (i < 4 ? "1 分鐘" : "2 分鐘"), fallback: "只做 15 秒", category: stages[stageIndex].name, requiredBingoCount: 1, completedBingoCount: 0, isCompleted: false, bingoTasks: tasks))
                    }
                }
                stageGuides.append(HabitStageGuide(stage: stageIndex, steps: builtSteps))
            }
        }

        let mastery: String
        let frictions: [String]
        if goalLower.contains("運動") {
            mastery = "能夠在想到要做時，直接去做，不再需要『心理準備』；偶爾忘記後能在 24 小時內自己回來，不需要別人提醒。"
            frictions = ["想到要換運動服，就覺得麻煩", "坐在沙發上後，就不想動", "不知道第一步要做什麼"]
        } else if goalLower.contains("睡") {
            mastery = "能在預定時間自然入睡，偶爾失眠後能在下一晚自己調整回來，對自己的睡眠沒有苛責。"
            frictions = ["躺上床後不想睡", "想滑手機", "腦袋停不下來"]
        } else if goalLower.contains("喝水") {
            mastery = "口渴時會直接倒水喝，不需要提醒；身體自然養成喝水節奏。"
            frictions = ["忙起來忘記喝水", "覺得白開水沒味道", "出門忘記帶水"]
        } else {
            mastery = "能在想到要做時，直接去做，不再需要心理掙扎；偶爾中斷後能在 24 小時內自己回來。"
            frictions = ["覺得麻煩", "動機下降", "環境干擾"]
        }
        return HabitGuide(goal: goal, masteryDefinition: mastery, frictions: frictions, methodRoute: [], stages: stageGuides, updatedAt: Date())
    }
}
