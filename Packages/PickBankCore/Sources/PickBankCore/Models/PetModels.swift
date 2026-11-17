import Foundation

public enum PetSpecies: String, Codable, Sendable, CaseIterable, Hashable {
    case cat = "CAT"
    case dog = "DOG"
    case lamb = "LAMB"
    case fish = "FISH"
    case calf = "CALF"
    case horse = "HORSE"
    case panda = "PANDA"
    case rabbit = "RABBIT"

    public var zhName: String {
        switch self {
        case .cat: return "小猫"
        case .dog: return "小狗"
        case .lamb: return "小羊"
        case .fish: return "小鱼"
        case .calf: return "小牛"
        case .horse: return "小马"
        case .panda: return "熊猫"
        case .rabbit: return "小兔"
        }
    }

    public var enName: String {
        switch self {
        case .cat: return "Cat"
        case .dog: return "Dog"
        case .lamb: return "Lamb"
        case .fish: return "Fish"
        case .calf: return "Calf"
        case .horse: return "Horse"
        case .panda: return "Panda"
        case .rabbit: return "Rabbit"
        }
    }

    public var resourceKey: String { rawValue.lowercased() }

    public var habitatTitleZh: String {
        switch self {
        case .cat: return "暖灯客厅"
        case .dog: return "向阳庭院"
        case .lamb: return "云朵草坡"
        case .fish: return "珊瑚水境"
        case .calf: return "木质谷仓"
        case .horse: return "微风牧场"
        case .panda: return "翠竹小院"
        case .rabbit: return "花圃木洞"
        }
    }

    public static func customSpeciesString(definitionId: String) -> String {
        "CUSTOM_\(definitionId)"
    }

    public static func customDefinitionId(from speciesString: String) -> String? {
        guard speciesString.hasPrefix("CUSTOM_") else { return nil }
        let suffix = String(speciesString.dropFirst("CUSTOM_".count))
        return suffix.isEmpty ? nil : suffix
    }
}

public enum PetBudgetMode: String, Codable, Sendable, CaseIterable, Hashable {
    case daily = "DAILY"
    case monthly = "MONTHLY"
}

public enum LifecycleStage: String, Codable, Sendable, CaseIterable, Hashable {
    case infant = "INFANT"
    case young = "YOUNG"
    case prime = "PRIME"
    case middleAged = "MIDDLE_AGED"
    case senior = "SENIOR"

    public var zhLabel: String {
        switch self {
        case .infant: return "幼崽"
        case .young: return "青年"
        case .prime: return "壮年"
        case .middleAged: return "中年"
        case .senior: return "老年"
        }
    }

    public var enLabel: String {
        switch self {
        case .infant: return "Infant"
        case .young: return "Young"
        case .prime: return "Prime"
        case .middleAged: return "Middle-Aged"
        case .senior: return "Senior"
        }
    }
}

public enum VitalState: String, Codable, Sendable, CaseIterable, Hashable {
    case alive = "ALIVE"
    case ill = "ILL"
    case deceased = "DECEASED"
}

public enum SatietyBand: String, Codable, Sendable, CaseIterable, Hashable {
    case weak = "WEAK"
    case hungry = "HUNGRY"
    case normal = "NORMAL"
    case full = "FULL"

    public static func from(satiety: Int) -> SatietyBand {
        switch satiety {
        case ...0: return .weak
        case 1...20: return .hungry
        case 21...79: return .normal
        default: return .full
        }
    }
}

public enum CircadianPhase: String, Codable, Sendable, CaseIterable, Hashable {
    case dawn = "DAWN"
    case day = "DAY"
    case dusk = "DUSK"
    case night = "NIGHT"
    case lateNight = "LATE_NIGHT"

    public static func from(hour: Int) -> CircadianPhase {
        switch hour {
        case 5...7: return .dawn
        case 8...16: return .day
        case 17...20: return .dusk
        case 21...23, 0...1: return .night
        default: return .lateNight
        }
    }

    public var visualPeriod: HabitatVisualPeriod {
        switch self {
        case .dawn, .day: return .day
        case .dusk, .night, .lateNight: return .night
        }
    }
}

public enum HabitatVisualPeriod: String, Codable, Sendable, CaseIterable, Hashable {
    case day = "DAY"
    case night = "NIGHT"
}

public struct PetModuleSettings: Codable, Sendable, Hashable {
    public var isEnabled: Bool
    public var budgetMode: PetBudgetMode
    public var budgetAmountCents: Int64
    public var animationsEnabled: Bool
    public var followRealCircadian: Bool
    public var globalEncountersEnabled: Bool
    public var lastSettledDateKey: String?
    public var overspendStreak: Int
    public var updatedAt: Int64

    public init(
        isEnabled: Bool = false,
        budgetMode: PetBudgetMode = .daily,
        budgetAmountCents: Int64 = 12000,
        animationsEnabled: Bool = true,
        followRealCircadian: Bool = true,
        globalEncountersEnabled: Bool = true,
        lastSettledDateKey: String? = nil,
        overspendStreak: Int = 0,
        updatedAt: Int64 = PickBankClock.nowMs()
    ) {
        self.isEnabled = isEnabled
        self.budgetMode = budgetMode
        self.budgetAmountCents = budgetAmountCents
        self.animationsEnabled = animationsEnabled
        self.followRealCircadian = followRealCircadian
        self.globalEncountersEnabled = globalEncountersEnabled
        self.lastSettledDateKey = lastSettledDateKey
        self.overspendStreak = overspendStreak
        self.updatedAt = updatedAt
    }
}

public struct PetProfile: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var species: String
    public var name: String
    public var growth: Int
    public var affection: Int
    public var satiety: Int
    public var adoptOrder: Int
    public var createdAt: Int64
    public var updatedAt: Int64

    public init(
        id: String = UUID().uuidString,
        species: String,
        name: String,
        growth: Int = 0,
        affection: Int = 0,
        satiety: Int = 70,
        adoptOrder: Int = 0,
        createdAt: Int64 = PickBankClock.nowMs(),
        updatedAt: Int64 = PickBankClock.nowMs()
    ) {
        self.id = id
        self.species = species
        self.name = name
        self.growth = growth
        self.affection = affection
        self.satiety = satiety
        self.adoptOrder = adoptOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var builtInSpecies: PetSpecies? { PetSpecies(rawValue: species) }
    public var customDefinitionId: String? { PetSpecies.customDefinitionId(from: species) }
}

public struct PetEnergyWallet: Codable, Sendable, Hashable {
    public var availableEnergy: Int
    public var lifetimeEarnedEnergy: Int
    public var updatedAt: Int64

    public init(
        availableEnergy: Int = 0,
        lifetimeEarnedEnergy: Int = 0,
        updatedAt: Int64 = PickBankClock.nowMs()
    ) {
        self.availableEnergy = availableEnergy
        self.lifetimeEarnedEnergy = lifetimeEarnedEnergy
        self.updatedAt = updatedAt
    }
}

public struct PetDailySettlement: Identifiable, Codable, Sendable, Hashable {
    public var id: String { dateKey }
    public var dateKey: String
    public var budgetCents: Int64
    public var expenseCents: Int64
    public var incomeCents: Int64
    public var savingEnergy: Int
    public var incomeEnergy: Int
    public var satietyLoss: Int
    public var overspendStreak: Int
    public var settledAt: Int64

    public init(
        dateKey: String,
        budgetCents: Int64,
        expenseCents: Int64,
        incomeCents: Int64,
        savingEnergy: Int,
        incomeEnergy: Int,
        satietyLoss: Int,
        overspendStreak: Int,
        settledAt: Int64 = PickBankClock.nowMs()
    ) {
        self.dateKey = dateKey
        self.budgetCents = budgetCents
        self.expenseCents = expenseCents
        self.incomeCents = incomeCents
        self.savingEnergy = savingEnergy
        self.incomeEnergy = incomeEnergy
        self.satietyLoss = satietyLoss
        self.overspendStreak = overspendStreak
        self.settledAt = settledAt
    }
}

public struct PetDailyInteraction: Codable, Sendable, Hashable {
    public var petId: String
    public var dateKey: String
    public var interactionCount: Int

    public init(petId: String, dateKey: String, interactionCount: Int) {
        self.petId = petId
        self.dateKey = dateKey
        self.interactionCount = interactionCount
    }
}

public struct PetLifecycleTimeline: Identifiable, Codable, Sendable, Hashable {
    public var id: String { petId }
    public var petId: String
    public var species: String
    public var timelineId: String
    public var timelineVersion: Int
    public var birthDateKey: String
    public var adoptionDateKey: String
    public var youngDateKey: String
    public var primeDateKey: String
    public var middleAgedDateKey: String
    public var seniorDateKey: String
    public var illnessStartDateKey: String
    public var deathDateKey: String
    public var lastEvaluatedDateKey: String
    public var memorialAcknowledgedAt: Int64?

    public init(
        petId: String,
        species: String,
        timelineId: String,
        timelineVersion: Int = 1,
        birthDateKey: String,
        adoptionDateKey: String,
        youngDateKey: String,
        primeDateKey: String,
        middleAgedDateKey: String,
        seniorDateKey: String,
        illnessStartDateKey: String,
        deathDateKey: String,
        lastEvaluatedDateKey: String,
        memorialAcknowledgedAt: Int64? = nil
    ) {
        self.petId = petId
        self.species = species
        self.timelineId = timelineId
        self.timelineVersion = timelineVersion
        self.birthDateKey = birthDateKey
        self.adoptionDateKey = adoptionDateKey
        self.youngDateKey = youngDateKey
        self.primeDateKey = primeDateKey
        self.middleAgedDateKey = middleAgedDateKey
        self.seniorDateKey = seniorDateKey
        self.illnessStartDateKey = illnessStartDateKey
        self.deathDateKey = deathDateKey
        self.lastEvaluatedDateKey = lastEvaluatedDateKey
        self.memorialAcknowledgedAt = memorialAcknowledgedAt
    }
}

public struct PetLifecycleSnapshot: Codable, Sendable, Hashable {
    public var petId: String
    public var evaluatedDateKey: String
    public var ageDays: Int
    public var stage: LifecycleStage
    public var vitalState: VitalState
    public var nextStageDateKey: String?
    public var daysUntilNextStage: Int?
    public var memorialAcknowledged: Bool
}

public struct PetReleaseRecord: Identifiable, Codable, Sendable, Hashable {
    public var id: String { petId }
    public var petId: String
    public var petName: String
    public var species: String
    public var adoptionDays: Int
    public var growthAtRelease: Int
    public var affectionAtRelease: Int
    public var releasedAt: Int64
    public var releaseDateKey: String

    public init(
        petId: String,
        petName: String,
        species: String,
        adoptionDays: Int,
        growthAtRelease: Int,
        affectionAtRelease: Int,
        releasedAt: Int64 = PickBankClock.nowMs(),
        releaseDateKey: String = PickBankClock.dateKey()
    ) {
        self.petId = petId
        self.petName = petName
        self.species = species
        self.adoptionDays = adoptionDays
        self.growthAtRelease = growthAtRelease
        self.affectionAtRelease = affectionAtRelease
        self.releasedAt = releasedAt
        self.releaseDateKey = releaseDateKey
    }
}

public struct PetSlotState: Codable, Sendable, Hashable {
    public var unlockedSlots: Int
    public var qualifiedPetIds: Set<String>

    public init(unlockedSlots: Int = 1, qualifiedPetIds: Set<String> = []) {
        self.unlockedSlots = max(1, unlockedSlots)
        self.qualifiedPetIds = qualifiedPetIds
    }
}

public struct CustomPetActionDefinition: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var label: String
    public var role: String
    public var fps: Int
    public var frameFileNames: [String]
    public var videoFileName: String?

    public init(
        id: String = UUID().uuidString,
        label: String,
        role: String = "IDLE",
        fps: Int = 6,
        frameFileNames: [String] = [],
        videoFileName: String? = nil
    ) {
        self.id = id
        self.label = label
        self.role = role
        self.fps = min(30, max(1, fps))
        self.frameFileNames = frameFileNames
        self.videoFileName = videoFileName
    }
}

public struct CustomPetDefinition: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var scalePercent: Int
    public var sceneImageFileName: String?
    public var actions: [CustomPetActionDefinition]
    public var createdAt: Int64

    public init(
        id: String = UUID().uuidString,
        name: String,
        scalePercent: Int = 36,
        sceneImageFileName: String? = nil,
        actions: [CustomPetActionDefinition] = [],
        createdAt: Int64 = PickBankClock.nowMs()
    ) {
        self.id = id
        self.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
        self.scalePercent = min(80, max(20, scalePercent))
        self.sceneImageFileName = sceneImageFileName
        self.actions = actions
        self.createdAt = createdAt
    }
}

public struct PetStateBundle: Codable, Sendable, Hashable {
    public var settings: PetModuleSettings
    public var profiles: [PetProfile]
    public var wallet: PetEnergyWallet
    public var settlements: [PetDailySettlement]
    public var interactions: [PetDailyInteraction]
    public var timelines: [PetLifecycleTimeline]
    public var releasedRecords: [PetReleaseRecord]
    public var slotState: PetSlotState
    public var customPets: [CustomPetDefinition]

    public init(
        settings: PetModuleSettings = PetModuleSettings(),
        profiles: [PetProfile] = [],
        wallet: PetEnergyWallet = PetEnergyWallet(),
        settlements: [PetDailySettlement] = [],
        interactions: [PetDailyInteraction] = [],
        timelines: [PetLifecycleTimeline] = [],
        releasedRecords: [PetReleaseRecord] = [],
        slotState: PetSlotState = PetSlotState(),
        customPets: [CustomPetDefinition] = []
    ) {
        self.settings = settings
        self.profiles = profiles
        self.wallet = wallet
        self.settlements = settlements
        self.interactions = interactions
        self.timelines = timelines
        self.releasedRecords = releasedRecords
        self.slotState = slotState
        self.customPets = customPets
    }
}
