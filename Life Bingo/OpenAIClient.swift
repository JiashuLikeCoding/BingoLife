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
        你是習慣地圖設計師。請為「\(goal)」生成一份 5 階段的 Habit Map。

        【第一：熟練定義（必須具體可觀察）】
        禁止：抽象描述如「自然地做」「成為生活一部份」「養成習慣」「持續執行」。
        必須：描述「做得到時，外在會出現什麼具體行為/徵兆」。
        範例（好）：
        - 「能夠在想到要做時，直接去做，不再需要『心理準備』」
        - 「偶爾忘記/中斷後，能在 24 小時內自己回來，不需要別人提醒」
        - 「做這件事時，心裡對自己沒有苛責聲音」

        【第二：阻力分析（必須具體）】
        禁止：「時間不夠」「懶」「不自律」這種標籤式描述。
        必須：具體描述「什麼情境/什麼東西/什麼想法」阻礙行動。
        範例（好）：
        - 「想到要換運動服，就覺得麻煩」（阻力：怕麻煩的感覺）
        - 「坐在沙發上後，就不想動」（阻力：舒適區的吸引力）
        - 「打開運動影片，看不懂要怎麼做」（阻力：不知道第一步）

        【第三：五階段與步驟（最重要）】
        必須包含 5 個 STAGE（stage=0..4）。
        每個 STAGE 的 steps 數量可以彈性（建議 3–8 步），但每個 stage 至少要有 1 步。

        **STEP 的規則（每一步都是一個具體行動）：**
        禁止：
        - 「培養觸發點」「建立儀式」「克服阻力」—— 這些是目標，不是行動
        - 「Day 1: ...」格式，直接寫行動
        - 必須是「做 XXX」「選定 XXX」「把 XXX 放好」「打開 XXX」
        範例（好）：
        - 「選定明日運動時間」
        - 「把運動服放在床邊」
        - 「下載並打開運動 App」
        - 「穿好運動襪」
        - 「做 3 下深蹲」

        **BINGO TASKS 的規則（比 step 更細的動作）：**
        每個 step 產生 bingoTasks（數量彈性，但至少 1 個；必須直接可執行）。
        禁止：「換心態」「給自己鼓勵」「深呼吸」——除非目標本身是情緒相關。
        範例（好）：
        - Step「選定明日運動時間」的 bingoTasks：
          - 「打開手機日曆」
          - 「選定明天一個具體時間」
          - 「設定鬧鐘提醒」

        【嚴格禁止（再次強調）】
        - 「做一個很小的步驟」「開始行動」「嘗試一下」—— 廢話
        - 「閉眼呼吸」「對自己說肯定句」—— 無關任務
        - 任何包含「每天」「每日」「天天」的句子

        【輸出 JSON 格式】
        {
          "masteryDefinition": "具體可觀察的熟練狀態（不要 KPI）",
          "frictions": ["具體阻力1", "具體阻力2", "具體阻力3"],
          "methodRoute": ["列點式順序方法 10-20 點（每點=可操作行為）"],
          "stages": [
            {
              "stage": 0,
              "stageName": "種子",
              "steps": [
                {
                  "stepId": "S1",
                  "title": "具體行動（做 XXX / 選定 XXX / 把 XXX 放好）",
                  "duration": "30 秒",
                  "fallback": "更小版本",
                  "category": "行為/環境/心理",
                  "bingoTasks": ["細動作1", "細動作2", "細動作3"]
                }
              ]
            }
          ]
        }

        【硬性輸出驗證（你必須滿足）】
        - methodRoute 至少 3 點（越完整越好），且每點是可操作行為（禁止抽象口號）。
        - stages 必須剛好 5 個（stage=0..4），每個 stage 至少 1 個 steps（可彈性）。
        - 每個 step 必須有 stepId，且 stepId 必須跟 stage 對應：
          - stage 0: S1..Sn
          - stage 1: P1..Pn
          - stage 2: L1..Ln
          - stage 3: B1..Bn
          - stage 4: R1..Rn
        - 每個 step 的 bingoTasks 至少 1 個，且全都是細動作（可直接做，不需要用戶再決定做咩）。

        只回傳 JSON，不要有任何其他文字。
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
        
        // Try to decode, if fails, throw to trigger fallback
        let responseModel: HabitGuideResponse
        do {
            responseModel = try JSONDecoder().decode(HabitGuideResponse.self, from: jsonData)
        } catch {
            // Log the raw response for debugging
            print("AI HabitGuide JSON parsing failed: \(error)")
            print("Raw response: \(text.prefix(500))")
            throw OpenAIError.parse("JSON 解析失敗：\(error.localizedDescription)")
        }

        let masteryDefinition = (responseModel.masteryDefinition ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let frictions = (responseModel.frictions ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let methodRoute = (responseModel.methodRoute ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Strict validation: no local fallback templates.
        try Self.validateHabitGuideResponse(goal: goal, masteryDefinition: masteryDefinition, frictions: frictions, methodRoute: methodRoute, response: responseModel)

        let stages = responseModel.stages
            .sorted { $0.stage < $1.stage }
            .map { stage -> HabitStageGuide in
                let steps = stage.steps.map { step -> HabitGuideStep in
                    let trimmedStepId = (step.stepId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedTitle = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedFallback = step.fallback.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedDuration = step.duration.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedCategory = (step.category ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                    let tasks = (step.bingoTasks ?? [])
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }

                    return HabitGuideStep(
                        id: UUID(),
                        stepId: trimmedStepId,
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
            methodRoute: methodRoute,
            stages: stages,
            updatedAt: Date()
        )
    }

    private static func validateHabitGuideResponse(
        goal: String,
        masteryDefinition: String,
        frictions: [String],
        methodRoute: [String],
        response: HabitGuideResponse
    ) throws {
        if masteryDefinition.isEmpty {
            throw OpenAIError.parse("缺少 masteryDefinition")
        }
        if frictions.count < 3 {
            throw OpenAIError.parse("frictions 少於 3 點")
        }
        if methodRoute.count < 3 {
            throw OpenAIError.parse("methodRoute 至少 3 點（目前：\(methodRoute.count)）")
        }

        let stages = response.stages
        let stageSet = Set(stages.map { $0.stage })
        if stageSet != Set([0, 1, 2, 3, 4]) {
            throw OpenAIError.parse("stages 必須包含 stage=0..4")
        }
        for s in stages {
            if s.steps.isEmpty {
                throw OpenAIError.parse("stage \(s.stage) steps 至少 1 個")
            }
            for step in s.steps {
                let sidRaw = (step.stepId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if sidRaw.isEmpty {
                    throw OpenAIError.parse("缺少 stepId")
                }
                let expectedPrefix: String = {
                    switch s.stage {
                    case 0: return "S"
                    case 1: return "P"
                    case 2: return "L"
                    case 3: return "B"
                    case 4: return "R"
                    default: return ""
                    }
                }()
                if !sidRaw.hasPrefix(expectedPrefix) {
                    throw OpenAIError.parse("stepId \(sidRaw) 與 stage \(s.stage) 不匹配")
                }
                // Optional: ensure stepId has a positive index after the prefix (e.g., S1, P3)
                let idxStr = String(sidRaw.dropFirst(expectedPrefix.count))
                if let idx = Int(idxStr), idx <= 0 {
                    throw OpenAIError.parse("stepId \(sidRaw) 序號必須 >= 1")
                }

                let title = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallback = step.fallback.trimmingCharacters(in: .whitespacesAndNewlines)
                if title.isEmpty || fallback.isEmpty {
                    throw OpenAIError.parse("step title/fallback 不可為空")
                }

                let tasks = (step.bingoTasks ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                if tasks.isEmpty {
                    throw OpenAIError.parse("step \(sidRaw) bingoTasks 至少 1 個")
                }
            }
        }

        // Basic hard bans
        let banned = ["每天", "每日", "天天", "培養觸發點", "建立儀式", "克服阻力", "開始行動", "嘗試一下", "做一個很小的步驟"]

        var allChunks: [String] = [masteryDefinition]
        allChunks.append(contentsOf: frictions)
        allChunks.append(contentsOf: methodRoute)
        for stage in stages {
            for step in stage.steps {
                var chunk = step.title + " " + step.fallback
                if let tasks = step.bingoTasks {
                    chunk += " " + tasks.joined(separator: " ")
                }
                allChunks.append(chunk)
            }
        }
        let allText = allChunks.joined(separator: "\n")
        for word in banned {
            if allText.contains(word) {
                throw OpenAIError.parse("輸出包含禁詞：\(word)")
            }
        }
    }
}

struct HabitGuideResponse: Codable {
    var masteryDefinition: String?
    var frictions: [String]?
    var methodRoute: [String]?
    var stages: [HabitGuideStageResponse]
}

struct HabitGuideStageResponse: Codable {
    var stage: Int
    var stageName: String?  // Accept both index and name
    var steps: [HabitGuideStepResponse]
}

struct HabitGuideStepResponse: Codable {
    var stepId: String?
    var title: String
    var duration: String
    var fallback: String
    var category: String?
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
