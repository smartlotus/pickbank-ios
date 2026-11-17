import Foundation

public enum AppThemeMode: String, Codable, Sendable, CaseIterable, Hashable {
    case classic = "CLASSIC"
    case hermes = "HERMES"

    public var zhLabel: String {
        switch self {
        case .classic: return "经典暖黑"
        case .hermes: return "Hermes 皇室蓝"
        }
    }

    public var enLabel: String {
        switch self {
        case .classic: return "Classic Warm Dark"
        case .hermes: return "Hermes Royal Blue"
        }
    }
}

public enum AppLanguage: String, Codable, Sendable, CaseIterable, Hashable {
    case zhHans = "zh"
    case en = "en"
}

public struct AiModelPreset: Identifiable, Codable, Sendable, Hashable {
    public var id: String { name }
    public var name: String
    public var baseUrl: String
    public var defaultModel: String

    public init(name: String, baseUrl: String, defaultModel: String) {
        self.name = name
        self.baseUrl = baseUrl
        self.defaultModel = defaultModel
    }

    public static let builtInPresets: [AiModelPreset] = [
        AiModelPreset(name: "DeepSeek", baseUrl: "https://api.deepseek.com", defaultModel: "deepseek-chat"),
        AiModelPreset(name: "OpenAI", baseUrl: "https://api.openai.com", defaultModel: "gpt-4o-mini"),
        AiModelPreset(name: "Kimi (Moonshot)", baseUrl: "https://api.moonshot.cn", defaultModel: "moonshot-v1-8k"),
        AiModelPreset(name: "通义千问 (DashScope)", baseUrl: "https://dashscope.aliyuncs.com/compatible-mode", defaultModel: "qwen-plus"),
        AiModelPreset(name: "智谱 AI", baseUrl: "https://open.bigmodel.cn/api/paas/v4", defaultModel: "glm-4-flash")
    ]
}

public struct AiPromptPreset: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var prompt: String
    public var builtIn: Bool

    public init(id: String = UUID().uuidString, name: String, prompt: String, builtIn: Bool = false) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.builtIn = builtIn
    }

    public static let defaultPresets: [AiPromptPreset] = [
        AiPromptPreset(
            id: "default",
            name: "全景财务教练",
            prompt: "请基于我提供的统计周期收支总额、分类占比与明细，给出克制、具体、可执行的消费节奏建议和预算提醒。",
            builtIn: true
        ),
        AiPromptPreset(
            id: "saving",
            name: "极简攒钱体检",
            prompt: "帮我识别本周期非必要支出与高频小额消耗，量化可节省空间，并给出下周控预算行动清单。",
            builtIn: true
        )
    ]
}

public struct AppPreferences: Codable, Sendable, Hashable {
    public var themeMode: AppThemeMode
    public var language: AppLanguage
    public var selectedAiProviderName: String
    public var customAiBaseUrl: String
    public var aiModelId: String
    public var selectedPromptPresetId: String
    public var promptPresets: [AiPromptPreset]
    public var lastSyncedSignature: String?

    public init(
        themeMode: AppThemeMode = .classic,
        language: AppLanguage = .zhHans,
        selectedAiProviderName: String = "DeepSeek",
        customAiBaseUrl: String = "https://api.deepseek.com",
        aiModelId: String = "deepseek-chat",
        selectedPromptPresetId: String = "default",
        promptPresets: [AiPromptPreset] = AiPromptPreset.defaultPresets,
        lastSyncedSignature: String? = nil
    ) {
        self.themeMode = themeMode
        self.language = language
        self.selectedAiProviderName = selectedAiProviderName
        self.customAiBaseUrl = customAiBaseUrl
        self.aiModelId = aiModelId
        self.selectedPromptPresetId = selectedPromptPresetId
        self.promptPresets = promptPresets
        self.lastSyncedSignature = lastSyncedSignature
    }
}
