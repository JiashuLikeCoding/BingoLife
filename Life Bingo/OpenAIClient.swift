//
//  OpenAIClient.swift
//  Life Bingo
//
//  Created by Jason Li on 2026-02-02.
//

import Foundation

struct OpenAIClient {
    let apiKey: String
    let model: String

    func generateTasks(
        habit: String,
        motivation: String,
        size: Int,
        completionRate: Double,
        completedLines: Int,
        completedFullBoards: Int
    ) async throws -> [String] {
        let difficulty: String
        switch completionRate {
        case ..<0.4:
            difficulty = "簡單"
        case 0.4..<0.7:
            difficulty = "中等"
        default:
            difficulty = "進階"
        }

        let prompt = """
        你是習慣養成教練，請用繁體中文生成 Bingo 任務。
        請輸出 JSON，格式如下：
        { "tasks": ["任務1", "任務2", ...] }
        規則：
        - 需要 \(size * size) 條任務，長度 6-20 字
        - 任務要具體，可執行，正向
        - 任務不可包含「每天」「每日」「天天」等字樣
        - 符合使用者習慣：\(habit)
        - 動機：\(motivation)
        - 難度：\(difficulty)
        - 目前已完成 Bingo 線數：\(completedLines)
        - 累積完成整張：\(completedFullBoards)
        - 任務不可重複
        請只回傳 JSON。
        """

        let requestBody: [String: Any] = [
            "model": model,
            "input": [
                [
                    "role": "system",
                    "content": "You are a helpful assistant. Respond in JSON only."
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "text": [
                "format": [
                    "type": "json_object"
                ]
            ],
            "max_output_tokens": 700
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.network("無法取得回應")
        }
        if !(200...299).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "狀態碼 \(http.statusCode)"
            throw OpenAIError.server(message)
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        if let error = decoded.error {
            throw OpenAIError.server(error.message)
        }

        let text = decoded.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw OpenAIError.parse("回應內容為空")
        }

        guard let jsonData = text.data(using: .utf8) else {
            throw OpenAIError.parse("JSON 解析失敗")
        }
        let taskResponse = try JSONDecoder().decode(TaskResponse.self, from: jsonData)
        return taskResponse.tasks
    }

    func generateTaskPool(
        goals: [String],
        priorityGoals: [String],
        tasksPerGoal: Int,
        extraCount: Int,
        blockedTopics: [String],
        difficultyMode: DifficultyMode,
        goalSubgoals: [String: [String]],
        checkin: DailyCheckin?,
        isInitialBoard: Bool
    ) async throws -> TaskPoolResponse {
        let goalList = goals.isEmpty ? "（無）" : goals.map { "- \($0)" }.joined(separator: "\n")
        let priorityList = priorityGoals.isEmpty ? "（無）" : priorityGoals.map { "- \($0)" }.joined(separator: "\n")
        let blockedList = blockedTopics.isEmpty ? "（無）" : blockedTopics.map { "- \($0)" }.joined(separator: "\n")
        let subgoalList: String = {
            guard !goalSubgoals.isEmpty else { return "（無）" }
            return goalSubgoals
                .filter { !$0.value.isEmpty }
                .map { key, value in
                    let items = value.map { "- \($0)" }.joined(separator: "\n")
                    return "\(key):\n\(items)"
                }
                .joined(separator: "\n")
        }()
        let checkinText: String
        if let checkin {
            checkinText = "mood_score: \(checkin.moodScore), motivation_score: \(checkin.motivationScore), difficulty_score: \(checkin.difficultyScore)"
        } else {
            checkinText = "（今日尚未填寫）"
        }
        let modeRule: String
        switch difficultyMode {
        case .initial:
            modeRule = "模式：初始。任務必須極度容易（1-10 分鐘內），不需出門、不需花錢、不需社交、不需長時間專注、不需準備或收尾。"
        case .protect:
            modeRule = "模式：保護。任務僅限放鬆、自我照顧、情緒穩定、降低刺激；不需出門、不需社交；避免推進型語意。"
        case .easeUp:
            modeRule = "模式：降低。整體難度下降 10-20%，優先降低時間與專注深度。"
        case .keep:
            modeRule = "模式：維持。難度不變，只更新表達與新鮮感。"
        case .gentleUp:
            modeRule = "模式：小幅提升。僅上調一個維度 +15-20%（例如時間稍長或更接觸），不可同時增加多維度。"
        case .slightUp:
            modeRule = "模式：微升。僅上調一個維度 +10%（例如時間稍長或更接觸），不可同時增加多維度。"
        case .microUp:
            modeRule = "模式：超微升。只能新增一個很輕的維度，或僅 +10%（二擇一），不可同時增加多維度。"
        }
        let stageHint: String
        if isInitialBoard || difficultyMode == .protect {
            stageHint = "Stage 0-1（心理/低摩擦接觸）"
        } else if difficultyMode == .easeUp {
            stageHint = "回到 Stage 0-1"
        } else if difficultyMode == .keep {
            stageHint = "Stage 2（極短實作）"
        } else {
            stageHint = "Stage 1-2（低摩擦接觸 → 極短實作）"
        }
        let prompt = """
        你是溫和的任務設計師，目標是保護使用者動機與情緒。
        所有大型習慣必須視為長期行為路徑（Stage 0-4），不可跳級；只能給出當前 Stage 的最低阻力步驟。
        請輸出 JSON，格式如下：
        {
          "goalTasks": {
            "目標1": ["任務1","任務2","任務3"],
            "目標2": ["任務1","任務2","任務3"]
          },
          "extraTasks": ["任務A", "任務B", ...]
        }
        規則：
        - 每個目標產生 \(tasksPerGoal) 條任務
        - 另外產生 \(extraCount) 條任務（可為自我照顧、感受當下、情緒穩定類）
        - 任務長度 6-20 字，具體、可執行、溫和
        - 每條任務必須在 30 分鐘內完成（若為初始模式，請限制在 1-10 分鐘）
        - 任務不可包含「每天」「每日」「天天」等字樣
        - 任務不可重複
        - 任務主題需與「好好生活、感受當下、感受自然、減少焦慮、提升靈魂、感受活著」相關
        - 若有優先目標，所有任務中至少 50% 要與優先目標相關（可隱含但需明確相關）
        - 避免引發內疚、自責或比較的語氣
        - 難度只能依據 difficulty_score 判斷，禁止自行推測
        - \(modeRule)
        - 不要生成與以下主題相關的任務：
        \(blockedList)
        - 目標清單如下（請使用完全相同的目標文字作為 key）：
        \(goalList)
        - 小目標清單如下（若有，請優先使用小目標來生成任務，並與目標結合）：
        \(subgoalList)
        - 若某目標有小目標，該目標的任務請優先從小目標產生（不足再用大目標）
        - 優先目標如下：
        \(priorityList)
        - 今日狀態（僅供判斷）：
        \(checkinText)
        - 若 mood_score ≥ 50 且 motivation_score ≥ 50，目標相關任務比例約 70%，非目標約 30%
        - 當前 Stage 建議：
        \(stageHint)
        - 是否為首次生成：\(isInitialBoard ? "是" : "否")
        只回傳 JSON。
        """

        let requestBody: [String: Any] = [
            "model": model,
            "input": [
                [
                    "role": "system",
                    "content": "You are a helpful assistant. Respond in JSON only."
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "text": [
                "format": [
                    "type": "json_object"
                ]
            ],
            "max_output_tokens": 1200
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.network("無法取得回應")
        }
        if !(200...299).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "狀態碼 \(http.statusCode)"
            throw OpenAIError.server(message)
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        if let error = decoded.error {
            throw OpenAIError.server(error.message)
        }

        let text = decoded.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw OpenAIError.parse("回應內容為空")
        }

        guard let jsonData = text.data(using: .utf8) else {
            throw OpenAIError.parse("JSON 解析失敗")
        }
        return try JSONDecoder().decode(TaskPoolResponse.self, from: jsonData)
    }

    func estimateCoinCost(for text: String) async throws -> Int {
        let prompt = """
        請根據以下目標估算需要的 coin 數量（1-50 之間的整數）。
        規則：內容越耗時、越難堅持，coin 越高。
        只回傳 JSON，格式：
        { "coins": 12 }
        目標：\(text)
        """

        let requestBody: [String: Any] = [
            "model": model,
            "input": [
                [
                    "role": "system",
                    "content": "You are a helpful assistant. Respond in JSON only."
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "text": [
                "format": [
                    "type": "json_object"
                ]
            ],
            "max_output_tokens": 120
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.network("無法取得回應")
        }
        if !(200...299).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "狀態碼 \(http.statusCode)"
            throw OpenAIError.server(message)
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        if let error = decoded.error {
            throw OpenAIError.server(error.message)
        }

        let text = decoded.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw OpenAIError.parse("回應內容為空")
        }

        guard let jsonData = text.data(using: .utf8) else {
            throw OpenAIError.parse("JSON 解析失敗")
        }
        let coinResponse = try JSONDecoder().decode(CoinEstimateResponse.self, from: jsonData)
        return coinResponse.coins
    }

    func generateGoodDeedFeedback(note: String, duration: TimeInterval?, source: GoodDeedSource) async throws -> String {
        let durationText: String
        if let duration {
            let total = Int(duration)
            let hours = total / 3600
            let minutes = (total % 3600) / 60
            let seconds = total % 60
            durationText = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            durationText = "無"
        }
        let prompt = """
        你是溫和的自我肯定教練。請用繁體中文給出一句短回饋，肯定使用者剛剛完成的正向行為與專注時間。
        回饋需包含：
        - 肯定行為本身
        - 若提供專注時長，請溫和提及；若為「無」，不要提及時間
        禁止：
        - KPI、評分、排名、比較
        - 說教或命令語氣
        請輸出 JSON：
        { "message": "..." }
        使用者行為：\(note)
        專注時長：\(durationText)
        來源：\(source.rawValue)
        """

        let requestBody: [String: Any] = [
            "model": model,
            "input": [
                [
                    "role": "system",
                    "content": "You are a helpful assistant. Respond in JSON only."
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "text": [
                "format": [
                    "type": "json_object"
                ]
            ],
            "max_output_tokens": 200
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.network("無法取得回應")
        }
        if !(200...299).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "狀態碼 \(http.statusCode)"
            throw OpenAIError.server(message)
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        if let error = decoded.error {
            throw OpenAIError.server(error.message)
        }

        let text = decoded.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw OpenAIError.parse("回應內容為空")
        }

        guard let jsonData = text.data(using: .utf8) else {
            throw OpenAIError.parse("JSON 解析失敗")
        }

        struct FeedbackResponse: Decodable {
            let message: String
        }

        let responseObj = try JSONDecoder().decode(FeedbackResponse.self, from: jsonData)
        return responseObj.message
    }

    func generateHabitGuide(goal: String) async throws -> HabitGuide {
        let prompt = """
        你是習慣地圖（Habit Map）設計師。請為「\(goal)」生成一份 5 階段的 Habit Map：
        - Stage 0：種子（Seed）
        - Stage 1：發芽（Sprout）
        - Stage 2：長葉（Leaf）
        - Stage 3：開花（Bloom）
        - Stage 4：扎根（Rooted）

        你需要先定義「熟練/內化」的明確樣子，並列出這個目標最常見的阻力（frictions）。

        重要規則：
        - stages 必須包含 stage 0..4（共 5 個，不能缺）
        - **每個 stage 產生 5 個 steps（共 25 個 step）**
        - steps 需依「阻力由低到高」排序（同一 stage 內也要由低到高）
        - 每個 step 必須與「\(goal)」直接相關，禁止空泛語句
        - 每個 step 需包含：title / duration / fallback / category / bingoTasks
        - **每個 step 產生 5 個 bingoTasks**
          - bingoTasks 是這個 step 當下能做的「最小可執行動作」
          - 每條長度 6-15 字，具體、可直接執行
          - 不要包含「每天/每日/天天」等字樣
        - 嚴格禁止：
          - 與目標無關的通用放鬆/呼吸/肯定句
          - 「做一個很小的步驟」「開始行動」等廢話
          - 「準備」「嘗試」「試著」等模糊動作

        請輸出 JSON（只回傳 JSON，不要多任何字）：
        {
          "masteryDefinition": "...",
          "frictions": ["...", "..."],
          "stages": [
            {
              "stage": 0,
              "steps": [
                {
                  "title": "...",
                  "duration": "...",
                  "fallback": "...",
                  "category": "...",
                  "bingoTasks": ["...","...","...","...","..."]
                }
              ]
            }
          ]
        }
        """

        let requestBody: [String: Any] = [
            "model": model,
            "input": [
                [
                    "role": "system",
                    "content": "You are a helpful assistant. Respond in JSON only."
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "text": [
                "format": [
                    "type": "json_object"
                ]
            ],
            "max_output_tokens": 2000
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.network("無法取得回應")
        }
        if !(200...299).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "狀態碼 \(http.statusCode)"
            throw OpenAIError.server(message)
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        if let error = decoded.error {
            throw OpenAIError.server(error.message)
        }

        let text = decoded.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let jsonData = text.data(using: .utf8) else {
            throw OpenAIError.parse("回應內容為空")
        }
        let responseModel = try JSONDecoder().decode(HabitGuideResponse.self, from: jsonData)

        let masteryDefinition = (responseModel.masteryDefinition ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let frictions = (responseModel.frictions ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let stages = responseModel.stages
            .sorted { $0.stage < $1.stage }
            .map { stage -> HabitStageGuide in
                let steps = stage.steps.map { step -> HabitGuideStep in
                    let trimmedTitle = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedFallback = step.fallback.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedDuration = step.duration.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedCategory = step.category.trimmingCharacters(in: .whitespacesAndNewlines)

                    var tasks = (step.bingoTasks ?? [])
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }

                    if tasks.isEmpty {
                        // Best-effort local fallback: keep it goal-related and executable.
                        let base = [trimmedFallback, trimmedTitle]
                            .map { $0.replacingOccurrences(of: "\n", with: " ") }
                            .filter { !$0.isEmpty }
                        tasks = base
                    }

                    // Ensure we show at least 3 tasks in the map UI.
                    while tasks.count < 3 {
                        tasks.append("做 1 分鐘\(goal)")
                    }
                    if tasks.count > 5 {
                        tasks = Array(tasks.prefix(5))
                    }

                    return HabitGuideStep(
                        id: UUID(),
                        title: trimmedTitle,
                        duration: trimmedDuration,
                        fallback: trimmedFallback,
                        category: trimmedCategory,
                        isCompleted: false,
                        bingoTasks: tasks
                    )
                }
                return HabitStageGuide(stage: stage.stage, steps: steps)
            }

        return HabitGuide(
            goal: goal,
            masteryDefinition: masteryDefinition,
            frictions: frictions,
            stages: stages,
            updatedAt: Date()
        )
    }
}

struct HabitGuideResponse: Codable {
    var masteryDefinition: String?
    var frictions: [String]?
    var stages: [HabitGuideStageResponse]
}

struct HabitGuideStageResponse: Codable {
    var stage: Int
    var steps: [HabitGuideStepResponse]
}

struct HabitGuideStepResponse: Codable {
    var title: String
    var duration: String
    var fallback: String
    var category: String
    var bingoTasks: [String]?
}

struct OpenAIResponse: Decodable {
    struct OutputItem: Decodable {
        let type: String
        let content: [Content]?
    }

    struct Content: Decodable {
        let type: String
        let text: String?
    }

    struct APIError: Decodable {
        let message: String
    }

    let output: [OutputItem]?
    let error: APIError?

    var outputText: String {
        guard let output = output else { return "" }
        return output.compactMap { item in
            item.content?
                .filter { $0.type == "output_text" }
                .compactMap { $0.text }
                .joined(separator: "\n")
        }
        .joined(separator: "\n")
    }
}

struct TaskResponse: Decodable {
    let tasks: [String]
}

struct TaskPoolResponse: Decodable {
    let goalTasks: [String: [String]]
    let extraTasks: [String]
}

struct CoinEstimateResponse: Decodable {
    let coins: Int
}

enum OpenAIError: LocalizedError {
    case network(String)
    case server(String)
    case parse(String)

    var errorDescription: String? {
        switch self {
        case .network(let message):
            return message
        case .server(let message):
            return message
        case .parse(let message):
            return message
        }
    }
}
