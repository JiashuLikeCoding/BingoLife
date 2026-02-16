//
//  Models.swift
//  Life Bingo
//
//  Created by Jason Li on 2026-02-02.
//

import Foundation

enum AppLanguage: String, CaseIterable, Codable {
    case zhTW = "zh-Hant"
    case en = "en"

    var displayName: String {
        switch self {
        case .zhTW: return "繁體中文"
        case .en: return "English"
        }
    }
}

struct BingoCell: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var isDone: Bool
    /// Which habit/goal this task belongs to (also used as key in habitGuides).
    var goal: String? = nil
    /// When this BingoCell is generated from a HabitGuideStep, this points to that step.
    /// For Habit-driven boards we typically set this equal to `id`.
    var habitStepId: UUID? = nil
}

struct BingoBoard: Codable, Hashable {
    var size: Int
    var cells: [BingoCell]
    /// Indices of `BingoRules.lineIndices(size:)` that have already been rewarded.
    var rewardedLineIds: [Int]
    /// Whether the full-board reward has been claimed for the current board.
    var fullRewarded: Bool
    /// Lifetime count of fully-completed boards.
    var completedFullBoards: Int
}

extension BingoBoard {
    var isFullBoardComplete: Bool {
        !cells.isEmpty && cells.allSatisfy { $0.isDone }
    }

    /// Updates `rewardedLineIds` / `fullRewarded` / `completedFullBoards` and returns newly completed line count + full-board completion.
    mutating func applyBingoProgress() -> (newLines: Int, didCompleteFullBoard: Bool) {
        let lines = BingoRules.lineIndices(size: size)
        var newlyCompletedLines: [Int] = []

        for (lineIndex, indices) in lines.enumerated() {
            guard !rewardedLineIds.contains(lineIndex) else { continue }
            let isLineDone = indices.allSatisfy { idx in
                cells.indices.contains(idx) ? cells[idx].isDone : false
            }
            if isLineDone {
                newlyCompletedLines.append(lineIndex)
            }
        }

        if !newlyCompletedLines.isEmpty {
            rewardedLineIds.append(contentsOf: newlyCompletedLines)
        }

        let didCompleteFullBoard: Bool
        if isFullBoardComplete, !fullRewarded {
            fullRewarded = true
            completedFullBoards += 1
            didCompleteFullBoard = true
        } else {
            didCompleteFullBoard = false
        }

        return (newlyCompletedLines.count, didCompleteFullBoard)
    }
}

enum RewardCategory: String, Codable, CaseIterable {
    case reduceHabit = "減少習慣"
    case purchase = "想買的東西"
}

struct RewardItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var detail: String
    var cost: Int
    var category: RewardCategory
    var createdAt: Date
    var redeemedAt: Date?

    var isRedeemed: Bool {
        redeemedAt != nil
    }
}

struct GoodDeed: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    let note: String
    let coin: Int
    let duration: TimeInterval?
    let source: GoodDeedSource

    init(id: UUID = UUID(), date: Date = Date(), note: String, coin: Int, duration: TimeInterval?, source: GoodDeedSource) {
        self.id = id
        self.date = date
        self.note = note
        self.coin = coin
        self.duration = duration
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case note
        case coin
        case duration
        case source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        note = try container.decode(String.self, forKey: .note)
        coin = try container.decode(Int.self, forKey: .coin)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        source = try container.decodeIfPresent(GoodDeedSource.self, forKey: .source) ?? .postRecord
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(note, forKey: .note)
        try container.encode(coin, forKey: .coin)
        try container.encode(duration, forKey: .duration)
        try container.encode(source, forKey: .source)
    }
}

enum GoodDeedSource: String, Codable, Hashable {
    case preTimer = "pre_timer"
    case postRecord = "post_record"
}

struct GratitudeEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let dateKey: String
    var items: [String]
    var bonusClaimed: Bool
}

struct HabitGuide: Codable, Hashable {
    var goal: String
    /// What "mastery" looks like for this habit (clear, observable definition).
    var masteryDefinition: String
    /// Key frictions/resistances that tend to block progress.
    var frictions: [String]
    /// The ordered method route (0 → mastery). Must be concrete actions, not abstract slogans.
    var methodRoute: [String]
    /// 5-stage habit map: Seed(0) → Sprout(1) → Leaf(2) → Bloom(3) → Rooted(4)
    var stages: [HabitStageGuide]
    var updatedAt: Date

    init(
        goal: String,
        masteryDefinition: String = "",
        frictions: [String] = [],
        methodRoute: [String] = [],
        stages: [HabitStageGuide],
        updatedAt: Date
    ) {
        self.goal = goal
        self.masteryDefinition = masteryDefinition
        self.frictions = frictions
        self.methodRoute = methodRoute
        self.stages = stages
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case goal
        case masteryDefinition
        case frictions
        case methodRoute
        case stages
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        goal = try container.decode(String.self, forKey: .goal)
        masteryDefinition = try container.decodeIfPresent(String.self, forKey: .masteryDefinition) ?? ""
        frictions = try container.decodeIfPresent([String].self, forKey: .frictions) ?? []
        methodRoute = try container.decodeIfPresent([String].self, forKey: .methodRoute) ?? []
        stages = try container.decode([HabitStageGuide].self, forKey: .stages)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

struct HabitStageGuide: Codable, Hashable {
    var stage: Int
    var steps: [HabitGuideStep]
}

struct HabitGuideStep: Identifiable, Codable, Hashable {
    let id: UUID
    /// Stable step identifier for mapping Bingo tasks ↔ habit map (e.g. S1,S2... P1... L1... B1... R1...).
    var stepId: String
    var title: String
    var duration: String
    var fallback: String
    var category: String

    /// How many Bingo tasks (for this step) must be completed before the step is considered completed.
    /// Range: 1...3. Defaults to 1 for backward compatibility.
    var requiredBingoCount: Int
    /// Progress counter: how many Bingo tasks linked to this step have been completed.
    /// Defaults to 0 for backward compatibility.
    var completedBingoCount: Int

    var isCompleted: Bool

    /// Bingo tasks available for this day/step. These are generated by AI and used to populate the daily Bingo board.
    var bingoTasks: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case stepId
        case title
        case duration
        case fallback
        case category
        case requiredBingoCount
        case completedBingoCount
        case isCompleted
        case bingoTasks
    }

    init(
        id: UUID,
        stepId: String,
        title: String,
        duration: String,
        fallback: String,
        category: String,
        requiredBingoCount: Int = 1,
        completedBingoCount: Int = 0,
        isCompleted: Bool,
        bingoTasks: [String]
    ) {
        self.id = id
        self.stepId = stepId
        self.title = title
        self.duration = duration
        self.fallback = fallback
        self.category = category
        self.requiredBingoCount = max(1, min(3, requiredBingoCount))
        self.completedBingoCount = max(0, completedBingoCount)
        self.isCompleted = isCompleted
        self.bingoTasks = bingoTasks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        stepId = try container.decodeIfPresent(String.self, forKey: .stepId) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        duration = try container.decodeIfPresent(String.self, forKey: .duration) ?? ""
        fallback = try container.decodeIfPresent(String.self, forKey: .fallback) ?? ""
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        let req = try container.decodeIfPresent(Int.self, forKey: .requiredBingoCount) ?? 1
        requiredBingoCount = max(1, min(3, req))
        completedBingoCount = max(0, try container.decodeIfPresent(Int.self, forKey: .completedBingoCount) ?? 0)
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        bingoTasks = try container.decodeIfPresent([String].self, forKey: .bingoTasks) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(stepId, forKey: .stepId)
        try container.encode(title, forKey: .title)
        try container.encode(duration, forKey: .duration)
        try container.encode(fallback, forKey: .fallback)
        try container.encode(category, forKey: .category)
        try container.encode(requiredBingoCount, forKey: .requiredBingoCount)
        try container.encode(completedBingoCount, forKey: .completedBingoCount)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encode(bingoTasks, forKey: .bingoTasks)
    }
}

enum DifficultyMode: String, Codable {
    case initial
    case protect
    case easeUp
    case keep
    case gentleUp
    case slightUp
    case microUp
}

struct DailyCheckin: Codable, Hashable {
    let dateKey: String
    let moodScore: Int
    let motivationScore: Int
    let difficultyScore: Int

    enum CodingKeys: String, CodingKey {
        case dateKey
        case moodScore
        case motivationScore
        case difficultyScore
        case mood
        case motivation
        case difficulty
    }

    init(dateKey: String, moodScore: Int, motivationScore: Int, difficultyScore: Int) {
        self.dateKey = dateKey
        self.moodScore = moodScore
        self.motivationScore = motivationScore
        self.difficultyScore = difficultyScore
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dateKey = try container.decode(String.self, forKey: .dateKey)
        if let moodScore = try container.decodeIfPresent(Int.self, forKey: .moodScore),
           let motivationScore = try container.decodeIfPresent(Int.self, forKey: .motivationScore),
           let difficultyScore = try container.decodeIfPresent(Int.self, forKey: .difficultyScore) {
            self.moodScore = max(0, min(100, moodScore))
            self.motivationScore = max(0, min(100, motivationScore))
            self.difficultyScore = max(0, min(100, difficultyScore))
        } else {
            let moodText = try container.decodeIfPresent(String.self, forKey: .mood) ?? "普通"
            let motivationText = try container.decodeIfPresent(String.self, forKey: .motivation) ?? "普通"
            let difficultyText = try container.decodeIfPresent(String.self, forKey: .difficulty) ?? "適中"
            self.moodScore = DailyCheckin.mapMoodScore(from: moodText)
            self.motivationScore = DailyCheckin.mapMotivationScore(from: motivationText)
            self.difficultyScore = DailyCheckin.mapDifficultyScore(from: difficultyText)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dateKey, forKey: .dateKey)
        try container.encode(moodScore, forKey: .moodScore)
        try container.encode(motivationScore, forKey: .motivationScore)
        try container.encode(difficultyScore, forKey: .difficultyScore)
    }

    private static func mapMoodScore(from text: String) -> Int {
        if text.contains("很低") { return 20 }
        if text.contains("不錯") { return 80 }
        return 50
    }

    private static func mapMotivationScore(from text: String) -> Int {
        if text.contains("很低") { return 20 }
        if text.contains("很高") { return 80 }
        return 50
    }

    private static func mapDifficultyScore(from text: String) -> Int {
        if text.contains("容易") { return 20 }
        if text.contains("困難") { return 80 }
        return 50
    }
}

struct StorageModel: Codable {
    var board: BingoBoard
    var habit: String
    var motivation: String
    var themeKey: String
    var language: String
    var goals: [String]
    var priorityGoals: [String]
    var goalSubgoals: [String: [String]]
    var habitGuides: [String: HabitGuide]
    var taskPool: [BingoCell]
    var rewardItems: [RewardItem]
    var blockedTopics: [String]
    var dailyKey: String
    var firstUseDateKey: String
    var hasOnboarded: Bool
    var hasGeneratedFirstBoard: Bool
    var dailyCheckin: DailyCheckin?
    var coins: Int
    var totalCoinsEarned: Int
    var skipTickets: Int
    var goodDeeds: [GoodDeed]
    var gratitudeEntries: [GratitudeEntry]
    var boardSizePreference: Int
    /// Last 3 "換一換" boards (titles only), for similarity avoidance.
    var shuffleHistory: [[String]]

    init(
        board: BingoBoard,
        habit: String,
        motivation: String,
        themeKey: String = ThemeKey.sage.rawValue,
        language: String = AppLanguage.zhTW.rawValue,
        goals: [String] = [],
        priorityGoals: [String] = [],
        goalSubgoals: [String: [String]] = [:],
        habitGuides: [String: HabitGuide] = [:],
        taskPool: [BingoCell] = [],
        rewardItems: [RewardItem] = [],
        blockedTopics: [String] = [],
        dailyKey: String = DateKey.today(),
        firstUseDateKey: String = DateKey.today(),
        hasOnboarded: Bool = false,
        hasGeneratedFirstBoard: Bool = false,
        dailyCheckin: DailyCheckin? = nil,
        coins: Int,
        totalCoinsEarned: Int,
        skipTickets: Int,
        goodDeeds: [GoodDeed],
        gratitudeEntries: [GratitudeEntry],
        boardSizePreference: Int,
        shuffleHistory: [[String]] = []
    ) {
        self.board = board
        self.habit = habit
        self.motivation = motivation
        self.themeKey = themeKey
        self.language = language
        self.goals = goals
        self.priorityGoals = priorityGoals
        self.goalSubgoals = goalSubgoals
        self.habitGuides = habitGuides
        self.taskPool = taskPool
        self.rewardItems = rewardItems
        self.blockedTopics = blockedTopics
        self.dailyKey = dailyKey
        self.firstUseDateKey = firstUseDateKey
        self.hasOnboarded = hasOnboarded
        self.hasGeneratedFirstBoard = hasGeneratedFirstBoard
        self.dailyCheckin = dailyCheckin
        self.coins = coins
        self.totalCoinsEarned = totalCoinsEarned
        self.skipTickets = skipTickets
        self.goodDeeds = goodDeeds
        self.gratitudeEntries = gratitudeEntries
        self.boardSizePreference = boardSizePreference
        self.shuffleHistory = shuffleHistory
    }

    enum CodingKeys: String, CodingKey {
        case board
        case habit
        case motivation
        case themeKey
        case language
        case goals
        case priorityGoals
        case goalSubgoals
        case habitGuides
        case taskPool
        case rewardItems
        case blockedTopics
        case dailyKey
        case firstUseDateKey
        case hasOnboarded
        case hasGeneratedFirstBoard
        case dailyCheckin
        case coins
        case totalCoinsEarned
        case skipTickets
        case goodDeeds
        case gratitudeEntries
        case boardSizePreference
        case shuffleHistory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        board = try container.decode(BingoBoard.self, forKey: .board)
        habit = try container.decode(String.self, forKey: .habit)
        motivation = try container.decode(String.self, forKey: .motivation)
        themeKey = try container.decodeIfPresent(String.self, forKey: .themeKey) ?? ThemeKey.sage.rawValue
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? AppLanguage.zhTW.rawValue
        goals = try container.decodeIfPresent([String].self, forKey: .goals) ?? []
        priorityGoals = try container.decodeIfPresent([String].self, forKey: .priorityGoals) ?? []
        goalSubgoals = try container.decodeIfPresent([String: [String]].self, forKey: .goalSubgoals) ?? [:]
        habitGuides = try container.decodeIfPresent([String: HabitGuide].self, forKey: .habitGuides) ?? [:]
        taskPool = try container.decodeIfPresent([BingoCell].self, forKey: .taskPool) ?? []
        rewardItems = try container.decodeIfPresent([RewardItem].self, forKey: .rewardItems) ?? []
        blockedTopics = try container.decodeIfPresent([String].self, forKey: .blockedTopics) ?? []
        dailyKey = try container.decodeIfPresent(String.self, forKey: .dailyKey) ?? DateKey.today()
        firstUseDateKey = try container.decodeIfPresent(String.self, forKey: .firstUseDateKey) ?? dailyKey
        hasOnboarded = try container.decodeIfPresent(Bool.self, forKey: .hasOnboarded) ?? false
        hasGeneratedFirstBoard = try container.decodeIfPresent(Bool.self, forKey: .hasGeneratedFirstBoard) ?? false
        dailyCheckin = try container.decodeIfPresent(DailyCheckin.self, forKey: .dailyCheckin)
        coins = try container.decode(Int.self, forKey: .coins)
        totalCoinsEarned = try container.decode(Int.self, forKey: .totalCoinsEarned)
        skipTickets = try container.decode(Int.self, forKey: .skipTickets)
        goodDeeds = try container.decode([GoodDeed].self, forKey: .goodDeeds)
        gratitudeEntries = try container.decode([GratitudeEntry].self, forKey: .gratitudeEntries)
        boardSizePreference = try container.decode(Int.self, forKey: .boardSizePreference)
        shuffleHistory = try container.decodeIfPresent([[String]].self, forKey: .shuffleHistory) ?? []
    }
}

enum BingoRules {
    static func lineIndices(size: Int) -> [[Int]] {
        var lines: [[Int]] = []
        for row in 0..<size {
            let start = row * size
            lines.append(Array(start..<(start + size)))
        }
        for col in 0..<size {
            var line: [Int] = []
            for row in 0..<size {
                line.append(row * size + col)
            }
            lines.append(line)
        }
        var diag1: [Int] = []
        var diag2: [Int] = []
        for i in 0..<size {
            diag1.append(i * size + i)
            diag2.append(i * size + (size - 1 - i))
        }
        lines.append(diag1)
        lines.append(diag2)
        return lines
    }
}

enum DateKey {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    static func today() -> String {
        formatter.string(from: Date())
    }

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func dateTimeString(from date: Date) -> String {
        dateTimeFormatter.string(from: date)
    }
}
