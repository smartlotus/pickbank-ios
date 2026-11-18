import PickBankCore
import SwiftUI

public struct PixelPetSpriteView: View {
    public let species: PetSpecies
    public let satiety: Int
    public let action: PixelPetRoamingAction
    public let facingLeft: Bool
    public let animated: Bool

    @State private var stepIndex = 0

    public init(
        species: PetSpecies,
        satiety: Int,
        action: PixelPetRoamingAction = .idle,
        facingLeft: Bool = false,
        animated: Bool = true
    ) {
        self.species = species
        self.satiety = satiety
        self.action = action
        self.facingLeft = facingLeft
        self.animated = animated
    }

    public var body: some View {
        let clip = PixelPetRoamingClip.clip(for: action, satiety: satiety)
        let frameNum = clip.frameIndices[stepIndex % max(1, clip.frameIndices.count)]
        let fileName = String(format: "pet_%@_%02d.png", species.resourceKey, frameNum)
        let showShadow = species != .fish && !(12...17).contains(frameNum)

        ZStack(alignment: .bottom) {
            if showShadow {
                Ellipse()
                    .fill(Color(hex: 0x3A2418, alpha: 0.22))
                    .frame(width: 44, height: 8)
                    .padding(.bottom, 6)
            }
            if let img = PickBankBundle.loadPetImage(subdirectory: "roaming", fileName: fileName) {
                Image(platformImage: img)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(x: facingLeft ? -1 : 1, y: 1)
                    .opacity(satiety <= 0 ? 0.55 : (satiety <= 20 ? 0.8 : 1.0))
            }
        }
        .task(id: "\(species.rawValue)-\(action.rawValue)-\(animated)") {
            stepIndex = 0
            guard animated, clip.frameIndices.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(clip.frameDurationMs))
                stepIndex &+= 1
            }
        }
    }
}

public struct PetEncounterOverlayView: View {
    public let event: LivingEncounterEvent
    public let leadPet: PetProfile
    public let companionPet: PetProfile?
    public let onTapPet: (String) -> Void
    public let onOpenHabitat: () -> Void
    public let onComplete: () -> Void

    @Environment(\.sumPalette) private var palette
    @State private var travelProgress: Double = 0
    @State private var touched = false

    public init(
        event: LivingEncounterEvent,
        leadPet: PetProfile,
        companionPet: PetProfile? = nil,
        onTapPet: @escaping (String) -> Void,
        onOpenHabitat: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        self.event = event
        self.leadPet = leadPet
        self.companionPet = companionPet
        self.onTapPet = onTapPet
        self.onOpenHabitat = onOpenHabitat
        self.onComplete = onComplete
    }

    public var body: some View {
        GeometryReader { geo in
            let isMoving = event.kind == .runAcross || travelProgress < 0.22 || travelProgress > 0.78
            let action: PixelPetRoamingAction = touched ? .happy : (isMoving ? .walk : .idle)
            let travel: Double = {
                if event.kind == .runAcross {
                    return travelProgress * 1.30 - 0.15
                }
                if travelProgress < 0.22 { return travelProgress / 0.22 }
                if travelProgress > 0.78 { return max(0, (1.0 - travelProgress) / 0.22) }
                return 1.0
            }()

            let xFrac: Double = {
                if event.kind == .runAcross {
                    return event.fromLeft ? travel : 1.0 - travel
                }
                let anchor = event.kind == .peek ? 0.08 : 0.18
                return event.fromLeft ? (-0.12 + (anchor + 0.12) * travel) : (1.12 - (anchor + 0.12) * travel)
            }()

            let xPos = geo.size.width * CGFloat(xFrac)
            let yPos: CGFloat = event.kind == .peek ? 76 : 158

            ZStack(alignment: .topLeading) {
                if event.kind == .waterWindow {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(hex: 0x2F9EBB, alpha: 0.34))
                        .overlay {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                        }
                        .frame(width: 82, height: 82)
                        .position(x: xPos, y: yPos)
                }

                VStack(spacing: 4) {
                    if touched {
                        Text("+1 ♥")
                            .font(SumFont.mono(11, weight: .bold))
                            .foregroundStyle(palette.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .pickbankLiquidGlass(in: Capsule(), tint: palette.surfaceElevated)
                            .transition(.scale.combined(with: .opacity))
                    }

                    PixelPetSpriteView(
                        species: event.species,
                        satiety: leadPet.satiety,
                        action: action,
                        facingLeft: !event.fromLeft
                    )
                    .frame(width: 72, height: 72)
                    .onTapGesture {
                        if !touched {
                            withAnimation(MotionTokens.springInteractive) { touched = true }
                            onTapPet(leadPet.id)
                        } else {
                            onOpenHabitat()
                        }
                    }
                }
                .position(x: xPos, y: yPos)

                if let companion = companionPet,
                   let compSpecies = event.companionSpecies {
                    PixelPetSpriteView(
                        species: compSpecies,
                        satiety: companion.satiety,
                        action: isMoving ? .walk : .idle,
                        facingLeft: !event.fromLeft
                    )
                    .frame(width: 58, height: 58)
                    .position(x: xPos + (event.fromLeft ? -62 : 62), y: yPos + 10)
                    .onTapGesture {
                        onTapPet(companion.id)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(true)
        }
        .task(id: event.id) {
            travelProgress = 0
            withAnimation(.linear(duration: event.durationSeconds)) {
                travelProgress = 1.0
            }
            try? await Task.sleep(for: .seconds(event.durationSeconds + (touched ? 1.1 : 0.35)))
            onComplete()
        }
    }
}
