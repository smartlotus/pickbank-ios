import Foundation

public struct ScenePoint: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct SceneProjectionResult: Sendable, Hashable {
    public let projectedWidth: Double
    public let projectedHeight: Double
    public let cropOriginX: Double
    public let cropOriginY: Double

    public func actorFrameRect(
        anchorXFraction: Double,
        anchorYFraction: Double,
        actorSizeFraction: Double,
        localCanvasWidth: Double,
        localCanvasHeight: Double
    ) -> (x: Double, y: Double, width: Double, height: Double) {
        let safeW = max(1, localCanvasWidth)
        let localWidth = projectedWidth * actorSizeFraction
        let localHeight = localWidth * max(1, localCanvasHeight) / safeW
        let left = cropOriginX + projectedWidth * anchorXFraction - localWidth / 2.0
        let top = cropOriginY + projectedHeight * anchorYFraction - localHeight
        return (left, top, localWidth, localHeight)
    }

    public static func project(
        containerWidth: Double,
        containerHeight: Double,
        authoredWidth: Double,
        authoredHeight: Double
    ) -> SceneProjectionResult {
        guard containerWidth > 0, containerHeight > 0, authoredWidth > 0, authoredHeight > 0 else {
            return SceneProjectionResult(projectedWidth: containerWidth, projectedHeight: containerHeight, cropOriginX: 0, cropOriginY: 0)
        }
        let designAspect = authoredWidth / authoredHeight
        let containerAspect = containerWidth / containerHeight
        let projectedWidth = containerAspect < designAspect ? containerHeight * designAspect : containerWidth
        let projectedHeight = containerAspect < designAspect ? containerHeight : containerWidth / designAspect
        return SceneProjectionResult(
            projectedWidth: projectedWidth,
            projectedHeight: projectedHeight,
            cropOriginX: (containerWidth - projectedWidth) / 2.0,
            cropOriginY: (containerHeight - projectedHeight) / 2.0
        )
    }
}

public struct PetSlotManifestEntry: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let label: String
    public let role: String
    public let anchor: [Double]
    public let size: Double
    public let canvas: [Int]
    public let baseWeight: Int
    public let restLike: Bool
    public let allowedSatiety: [String]
    public let allowedPhases: [String]
    public let sequence: [Int]
    public let frameDurationsMs: [Int]
    public let representative: Int
    public let infantDayFrames: [String]
    public let infantNightFrames: [String]
    public let dayCleanupPatch: String
    public let nightCleanupPatch: String
    public let stageFrames: [String: [String]]

    public var anchorX: Double { anchor.first ?? 0.5 }
    public var anchorY: Double { anchor.count > 1 ? anchor[1] : 0.6 }
    public var canvasWidth: Double { Double(canvas.first ?? 256) }
    public var canvasHeight: Double { Double(canvas.count > 1 ? canvas[1] : 256) }

    public func frames(for stage: LifecycleStage, period: HabitatVisualPeriod) -> [String] {
        if stage == .infant {
            return period == .day ? infantDayFrames : infantNightFrames
        }
        return stageFrames[stage.rawValue] ?? stageFrames["YOUNG"] ?? infantDayFrames
    }

    public func cleanupPatch(for stage: LifecycleStage, period: HabitatVisualPeriod) -> String? {
        guard stage != .infant else { return nil }
        return period == .day ? dayCleanupPatch : nightCleanupPatch
    }
}

public struct PetSpeciesManifestEntry: Codable, Sendable, Hashable {
    public let speciesKey: String
    public let zhName: String
    public let enName: String
    public let homeLabel: String
    public let authoredCanvas: [Int]
    public let dayRoom: String
    public let nightRoom: String
    public let roamingPrefix: String
    public let slots: [PetSlotManifestEntry]

    public var authoredWidth: Double { Double(authoredCanvas.first ?? 941) }
    public var authoredHeight: Double { Double(authoredCanvas.count > 1 ? authoredCanvas[1] : 1672) }
}

public struct PetAssetManifest: Codable, Sendable, Hashable {
    public let version: Int
    public let species: [String: PetSpeciesManifestEntry]

    public func entry(for species: PetSpecies) -> PetSpeciesManifestEntry? {
        self.species[species.resourceKey] ?? self.species[species.rawValue]
    }
}

public enum LivingSceneStateMachine {
    public static func chooseSlot(
        from entry: PetSpeciesManifestEntry,
        vitalState: VitalState,
        satiety: Int,
        phase: CircadianPhase,
        recentSlotIds: [String],
        preferredSlotId: String? = nil
    ) -> PetSlotManifestEntry? {
        if let preferredSlotId, let fixed = entry.slots.first(where: { $0.id == preferredSlotId }) {
            return fixed
        }
        guard !entry.slots.isEmpty else { return nil }

        let satietyKey = SatietyBand.from(satiety: satiety).rawValue
        let phaseKey = phase.rawValue

        var candidates = entry.slots.filter {
            $0.allowedSatiety.contains(satietyKey) && $0.allowedPhases.contains(phaseKey)
        }
        if candidates.isEmpty { candidates = entry.slots }

        if vitalState == .ill || satiety <= 0 {
            let resting = candidates.filter(\.restLike)
            if !resting.isEmpty { candidates = resting }
        }

        let weighted: [(PetSlotManifestEntry, Int)] = candidates.map { slot in
            let penalty: Double
            if let idx = recentSlotIds.firstIndex(of: slot.id) {
                switch idx {
                case 0: penalty = 0.12
                case 1: penalty = 0.34
                case 2: penalty = 0.62
                default: penalty = 1.0
                }
            } else {
                penalty = 1.0
            }
            return (slot, max(1, Int((Double(slot.baseWeight) * penalty).rounded())))
        }
        let total = max(1, weighted.reduce(0) { $0 + $1.1 })
        var roll = Int.random(in: 0..<total)
        for (slot, w) in weighted {
            if roll < w { return slot }
            roll -= w
        }
        return candidates.first
    }
}

public enum HabitatHudVisibility: String, Sendable, Hashable {
    case visible
    case hidden
}

public struct HabitatHudIdleState: Sendable, Hashable {
    public var visibility: HabitatHudVisibility
    public var activityEpoch: Int64

    public static let idleTimeoutSeconds: TimeInterval = 5.0

    public init(visibility: HabitatHudVisibility = .visible, activityEpoch: Int64 = 0) {
        self.visibility = visibility
        self.activityEpoch = activityEpoch
    }

    public func onTimeout() -> HabitatHudIdleState {
        switch visibility {
        case .visible: return HabitatHudIdleState(visibility: .hidden, activityEpoch: activityEpoch)
        case .hidden: return self
        }
    }

    public func onVisibleActivity() -> HabitatHudIdleState {
        HabitatHudIdleState(visibility: .visible, activityEpoch: activityEpoch + 1)
    }

    public func onWakeTouch() -> (state: HabitatHudIdleState, consumed: Bool) {
        (onVisibleActivity(), visibility == .hidden)
    }
}

public enum PixelPetRoamingAction: String, Sendable, CaseIterable, Hashable {
    case idle
    case walk
    case eat
    case happy
    case peek
    case rest
}

public struct PixelPetRoamingClip: Sendable, Hashable {
    public let frameIndices: [Int]
    public let frameDurationMs: Int

    public static func clip(for action: PixelPetRoamingAction, satiety: Int) -> PixelPetRoamingClip {
        let start: Int
        let durationMs: Int
        switch (satiety, action) {
        case (...0, _), (_, .rest):
            start = 33
            durationMs = 420
        case (_, .eat):
            start = 18
            durationMs = 260
        case (_, .happy):
            start = 21
            durationMs = 210
        case (_, .peek):
            start = 24
            durationMs = 300
        case (_, .walk):
            start = 12
            durationMs = 200
        default:
            start = 0
            durationMs = 290
        }
        let clamped = min(33, max(0, start))
        return PixelPetRoamingClip(frameIndices: [clamped, clamped + 1, clamped + 2], frameDurationMs: durationMs)
    }
}

public enum LivingEncounterKind: String, Codable, Sendable, CaseIterable, Hashable {
    case runAcross = "RUN_ACROSS"
    case peek = "PEEK"
    case visit = "VISIT"
    case waterWindow = "WATER_WINDOW"
}

public struct LivingEncounterEvent: Identifiable, Sendable, Hashable {
    public let id: String
    public let petId: String
    public let species: PetSpecies
    public let kind: LivingEncounterKind
    public let fromLeft: Bool
    public let durationSeconds: Double
    public let companionPetId: String?
    public let companionSpecies: PetSpecies?

    public static func make(
        pet: PetProfile,
        companion: PetProfile? = nil,
        satiety: Int,
        randomUnit: Double = Double.random(in: 0..<1)
    ) -> LivingEncounterEvent? {
        guard let sp = pet.builtInSpecies, satiety > 0 else { return nil }
        let kind: LivingEncounterKind
        if sp == .fish {
            kind = .waterWindow
        } else if randomUnit < 0.34 {
            kind = .runAcross
        } else if randomUnit < 0.68 {
            kind = .peek
        } else {
            kind = .visit
        }
        let compSpecies = companion?.builtInSpecies
        let validCompanion: PetProfile? = (compSpecies != nil && (compSpecies != .fish || kind == .waterWindow)) ? companion : nil
        return LivingEncounterEvent(
            id: UUID().uuidString,
            petId: pet.id,
            species: sp,
            kind: kind,
            fromLeft: Bool.random(),
            durationSeconds: kind == .runAcross ? 6.2 : 5.4,
            companionPetId: validCompanion?.id,
            companionSpecies: validCompanion?.builtInSpecies
        )
    }
}
