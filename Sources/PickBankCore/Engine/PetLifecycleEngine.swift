import Foundation

public struct TimelineOffsets: Sendable {
    public let youngDay: Int
    public let primeDay: Int
    public let middleAgedDay: Int
    public let seniorDay: Int
    public let illnessDay: Int
    public let deathDay: Int
}

public enum PetLifecycleEngine {
    public static let timelineVersion = 1

    private static let speciesProfiles: [PetSpecies: [TimelineOffsets]] = [
        .cat: variants(45, 105, 210, 300, 360, 12),
        .dog: variants(42, 96, 192, 276, 330, 12),
        .lamb: variants(38, 88, 174, 250, 300, 11),
        .fish: variants(30, 70, 140, 200, 240, 9),
        .calf: variants(43, 100, 200, 284, 340, 12),
        .horse: variants(52, 122, 244, 350, 420, 14),
        .panda: variants(48, 114, 228, 326, 390, 13),
        .rabbit: variants(34, 80, 158, 226, 270, 10)
    ]

    private static let customVariants = variants(90, 180, 360, 720, 3650, 30)

    private static func variants(_ y: Int, _ p: Int, _ m: Int, _ s: Int, _ d: Int, _ ill: Int) -> [TimelineOffsets] {
        [
            TimelineOffsets(youngDay: y, primeDay: p, middleAgedDay: m, seniorDay: s, illnessDay: d - ill, deathDay: d),
            TimelineOffsets(youngDay: y + 2, primeDay: p + 4, middleAgedDay: m + 8, seniorDay: s + 12, illnessDay: d + 15 - ill - 2, deathDay: d + 15),
            TimelineOffsets(youngDay: y + 4, primeDay: p + 8, middleAgedDay: m + 16, seniorDay: s + 24, illnessDay: d + 30 - ill - 4, deathDay: d + 30)
        ]
    }

    public static func createTimeline(
        petId: String,
        species: String,
        adoptionDate: Date = Date(),
        calendar: Calendar = .current
    ) -> PetLifecycleTimeline {
        let baseDate = calendar.startOfDay(for: adoptionDate)
        let available: [TimelineOffsets]
        if let builtIn = PetSpecies(rawValue: species), let list = speciesProfiles[builtIn] {
            available = list
        } else {
            available = customVariants
        }
        let hashValue = abs(petId.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
        let offsets = available[hashValue % available.count]

        func plusDays(_ days: Int) -> String {
            let dt = calendar.date(byAdding: .day, value: days, to: baseDate) ?? baseDate
            return PickBankClock.dateKey(for: dt, calendar: calendar)
        }

        let adoptKey = PickBankClock.dateKey(for: baseDate, calendar: calendar)
        return PetLifecycleTimeline(
            petId: petId,
            species: species,
            timelineId: "\(species.lowercased()).calendar.v\(timelineVersion)",
            timelineVersion: timelineVersion,
            birthDateKey: adoptKey,
            adoptionDateKey: adoptKey,
            youngDateKey: plusDays(offsets.youngDay),
            primeDateKey: plusDays(offsets.primeDay),
            middleAgedDateKey: plusDays(offsets.middleAgedDay),
            seniorDateKey: plusDays(offsets.seniorDay),
            illnessStartDateKey: plusDays(offsets.illnessDay),
            deathDateKey: plusDays(offsets.deathDay),
            lastEvaluatedDateKey: adoptKey,
            memorialAcknowledgedAt: nil
        )
    }

    /// Evaluates lifecycle monotonically: clock rollbacks never rejuvenate a pet.
    public static func evaluate(
        timeline: PetLifecycleTimeline,
        todayKey: String = PickBankClock.dateKey()
    ) -> PetLifecycleSnapshot {
        let effectiveKey = max(todayKey, max(timeline.lastEvaluatedDateKey, timeline.adoptionDateKey))
        return evaluateAt(timeline: timeline, dateKey: effectiveKey)
    }

    public static func evaluateAt(
        timeline: PetLifecycleTimeline,
        dateKey: String,
        calendar: Calendar = .current
    ) -> PetLifecycleSnapshot {
        let effective = max(dateKey, timeline.adoptionDateKey)

        let stage: LifecycleStage
        if effective >= timeline.seniorDateKey {
            stage = .senior
        } else if effective >= timeline.middleAgedDateKey {
            stage = .middleAged
        } else if effective >= timeline.primeDateKey {
            stage = .prime
        } else if effective >= timeline.youngDateKey {
            stage = .young
        } else {
            stage = .infant
        }

        let vital: VitalState
        if effective >= timeline.deathDateKey {
            vital = .deceased
        } else if effective >= timeline.illnessStartDateKey {
            vital = .ill
        } else {
            vital = .alive
        }

        let nextKey: String?
        switch stage {
        case .infant: nextKey = timeline.youngDateKey
        case .young: nextKey = timeline.primeDateKey
        case .prime: nextKey = timeline.middleAgedDateKey
        case .middleAged: nextKey = timeline.seniorDateKey
        case .senior: nextKey = nil
        }

        let birthDate = PickBankClock.parseDateKey(timeline.birthDateKey, calendar: calendar) ?? Date()
        let evalDate = PickBankClock.parseDateKey(effective, calendar: calendar) ?? Date()
        let ageDays = max(0, calendar.dateComponents([.day], from: birthDate, to: evalDate).day ?? 0)
        let daysUntilNext: Int? = nextKey.flatMap { nk in
            guard let nd = PickBankClock.parseDateKey(nk, calendar: calendar) else { return nil }
            return max(0, calendar.dateComponents([.day], from: evalDate, to: nd).day ?? 0)
        }

        return PetLifecycleSnapshot(
            petId: timeline.petId,
            evaluatedDateKey: effective,
            ageDays: ageDays,
            stage: stage,
            vitalState: vital,
            nextStageDateKey: nextKey,
            daysUntilNextStage: daysUntilNext,
            memorialAcknowledged: timeline.memorialAcknowledgedAt != nil
        )
    }
}

public struct PetAdoptionUnlockProgress: Sendable, Hashable {
    public var petId: String
    public var adoptionDays: Int
    public var bondQualified: Bool
    public var growthQualified: Bool
    public var slotQualified: Bool
    public var releaseEligible: Bool
    public var releaseBlockReason: String?
}

public enum PetAdoptionPolicy {
    public static let baseSlots = 1
    public static let maxUnlockedSlots = 999
    public static let bondMinDays = 30
    public static let bondMinAffection = 40
    public static let growthMinGrowth = 120
    public static let growthMinAffection = 30
    public static let maxDailyEnergy = 30
    public static let maxDailyAffectionInteractions = 3

    public static func adoptionDays(
        profile: PetProfile,
        timeline: PetLifecycleTimeline?,
        todayKey: String = PickBankClock.dateKey(),
        calendar: Calendar = .current
    ) -> Int {
        let adoptDate: Date
        if let timeline, let parsed = PickBankClock.parseDateKey(timeline.adoptionDateKey, calendar: calendar) {
            adoptDate = parsed
        } else {
            adoptDate = calendar.startOfDay(for: PickBankClock.date(fromMs: profile.createdAt))
        }
        let evalDate = PickBankClock.parseDateKey(todayKey, calendar: calendar) ?? calendar.startOfDay(for: Date())
        return max(0, calendar.dateComponents([.day], from: adoptDate, to: evalDate).day ?? 0)
    }

    public static func bondQualified(profile: PetProfile, timeline: PetLifecycleTimeline?, todayKey: String) -> Bool {
        adoptionDays(profile: profile, timeline: timeline, todayKey: todayKey) >= bondMinDays && profile.affection >= bondMinAffection
    }

    public static func growthQualified(profile: PetProfile) -> Bool {
        profile.growth >= growthMinGrowth && profile.affection >= growthMinAffection
    }

    public static func slotQualified(profile: PetProfile, timeline: PetLifecycleTimeline?, todayKey: String) -> Bool {
        bondQualified(profile: profile, timeline: timeline, todayKey: todayKey) || growthQualified(profile: profile)
    }

    public static func releaseBlockReason(
        profile: PetProfile,
        timeline: PetLifecycleTimeline?,
        snapshot: PetLifecycleSnapshot?,
        isReleased: Bool,
        todayKey: String
    ) -> String? {
        if isReleased { return "它已经放生，正在纪念档案中。" }
        guard let snapshot else { return "伙伴资料还在准备中，请稍后再试。" }
        switch snapshot.vitalState {
        case .deceased:
            return "已经离世的伙伴会进入纪念档案，无需再放生。"
        case .ill:
            return "它正在生病，需要照护；痊愈之后才能考虑放生。"
        case .alive:
            break
        }
        let days = adoptionDays(profile: profile, timeline: timeline, todayKey: todayKey)
        let bond = bondQualified(profile: profile, timeline: timeline, todayKey: todayKey)
        let growth = growthQualified(profile: profile)
        if !bond && !growth {
            if days < bondMinDays {
                return "至少要领养满 \(bondMinDays) 天且好感≥\(bondMinAffection)（当前 \(days) 天），或成长≥\(growthMinGrowth) 且好感≥\(growthMinAffection) 才可放生。"
            }
            return "放生需要好感达到 \(bondMinAffection)，或成长达到 \(growthMinGrowth) 且好感达到 \(growthMinAffection)。"
        }
        return nil
    }

    public static func computeDayEnergy(
        allowanceCents: Int64,
        expenseCents: Int64,
        incomeCents: Int64,
        priorOverspendStreak: Int
    ) -> (savingEnergy: Int, incomeEnergy: Int, satietyLoss: Int, nextStreak: Int, overspent: Bool) {
        let overspent = expenseCents > allowanceCents
        let savingEnergy: Int
        if overspent {
            savingEnergy = 0
        } else {
            let savedYuan = Int(max(0, allowanceCents - expenseCents) / 100)
            savingEnergy = min(maxDailyEnergy, savedYuan)
        }
        let incomeEnergy = min(maxDailyEnergy, Int(max(0, incomeCents) / 1000))
        let nextStreak = overspent ? (priorOverspendStreak + 1) : 0
        let satietyLoss: Int
        if !overspent {
            satietyLoss = 6
        } else if nextStreak == 1 {
            satietyLoss = 7
        } else if nextStreak == 2 {
            satietyLoss = 8
        } else {
            satietyLoss = 10
        }
        return (savingEnergy, incomeEnergy, satietyLoss, nextStreak, overspent)
    }
}
