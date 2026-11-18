import AVFoundation
import AVKit
import PickBankCore
import SwiftUI
import UniformTypeIdentifiers

/// PickBank Pixel Companion Habitat (Faithful Android `PetScreen` + `LivingSceneRenderer` + `CustomPetStage` port).
public struct PetWorldView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.sumPalette) private var palette

    @State private var hudIdle = HabitatHudIdleState()
    @State private var showCompanionSheet = false
    @State private var showSettingsSheet = false
    @State private var showCustomWorkshop = false

    @State private var previewSlotId: String? = nil
    @State private var previewStageOverride: LifecycleStage? = nil
    @State private var pinCustomActionId: String? = nil

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    private var selectedPet: PetProfile? {
        if let id = viewModel.selectedPetId,
           let match = viewModel.activePets.first(where: { $0.id == id }) {
            return match
        }
        return viewModel.activePets.first
    }

    private var currentPeriod: HabitatVisualPeriod {
        if let overridePeriod = viewModel.petVisualOverride {
            return overridePeriod
        }
        let hour = Calendar.current.component(.hour, from: Date())
        return CircadianPhase.from(hour: hour).visualPeriod
    }

    public var body: some View {
        let petState = viewModel.snapshot.petState

        ZStack {
            if !petState.settings.isEnabled {
                petDisabledOnboarding
            } else if let pet = selectedPet {
                activeHabitatScreen(pet: pet, petState: petState)
            } else {
                emptyHabitatView
            }
        }
        .onChange(of: hudIdle.visibility) { _, newVis in
            withAnimation(.easeInOut(duration: 0.28)) {
                viewModel.isPetHabitatImmersiveHidden = (newVis == .hidden)
            }
        }
        .task(id: "hud-idle-\(hudIdle.activityEpoch)-\(petState.settings.isEnabled)-\(selectedPet?.id ?? "none")") {
            guard petState.settings.isEnabled, selectedPet != nil else {
                hudIdle = HabitatHudIdleState()
                viewModel.isPetHabitatImmersiveHidden = false
                return
            }
            try? await Task.sleep(for: .seconds(HabitatHudIdleState.idleTimeoutSeconds))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.32)) {
                hudIdle = hudIdle.onTimeout()
            }
        }
        .onDisappear {
            viewModel.isPetHabitatImmersiveHidden = false
        }
        .sheet(isPresented: $showCompanionSheet) {
            PetCompanionSheet(
                viewModel: viewModel,
                onOpenWorkshop: {
                    showCompanionSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        showCustomWorkshop = true
                    }
                }
            )
        }
        .sheet(isPresented: $showSettingsSheet) {
            PetSettingsSheet(
                viewModel: viewModel,
                selectedPet: selectedPet,
                previewSlotId: $previewSlotId,
                previewStageOverride: $previewStageOverride
            )
        }
        .sheet(isPresented: $showCustomWorkshop) {
            CustomPetWorkshopSheet(viewModel: viewModel)
        }
    }

    private func registerHudActivity() {
        withAnimation(.easeOut(duration: 0.22)) {
            hudIdle = hudIdle.onVisibleActivity()
        }
    }

    private func activeHabitatScreen(pet: PetProfile, petState: PetStateBundle) -> some View {
        let timeline = petState.timelines.first(where: { $0.petId == pet.id })
        let todayKey = PickBankClock.dateKey()
        let lifecycleSnap = timeline.map { PetLifecycleEngine.evaluate(timeline: $0, todayKey: todayKey) }
        let animationsOn = petState.settings.animationsEnabled && !petState.settings.behaviorPreferences.reduceMotion
        let period = currentPeriod

        return ZStack {
            // Full-screen edge-to-edge living room / custom stage
            Group {
                if let species = pet.builtInSpecies,
                   let entry = viewModel.petManifest?.entry(for: species) {
                    LivingSceneRendererView(
                        pet: pet,
                        entry: entry,
                        stage: previewStageOverride ?? lifecycleSnap?.stage ?? .infant,
                        vitalState: lifecycleSnap?.vitalState ?? .alive,
                        period: period,
                        animationsEnabled: animationsOn,
                        preferredSlotId: previewSlotId,
                        heartBurstToken: viewModel.petHeartBurstToken,
                        onStageTap: {
                            let res = hudIdle.onWakeTouch()
                            withAnimation(.easeOut(duration: 0.22)) {
                                hudIdle = res.state
                            }
                            if !res.consumed {
                                Task { await viewModel.interactPet(id: pet.id) }
                            }
                        }
                    )
                } else if let defId = pet.customDefinitionId,
                          let def = petState.customPets.first(where: { $0.id == defId }) {
                    CustomHabitatStageView(
                        viewModel: viewModel,
                        pet: pet,
                        definition: def,
                        animationsEnabled: animationsOn,
                        pinnedActionId: $pinCustomActionId,
                        heartBurstToken: viewModel.petHeartBurstToken,
                        onStageTap: {
                            let res = hudIdle.onWakeTouch()
                            withAnimation(.easeOut(duration: 0.22)) {
                                hudIdle = res.state
                            }
                            if !res.consumed {
                                Task { await viewModel.interactPet(id: pet.id) }
                            }
                        }
                    )
                } else {
                    Color.black.ignoresSafeArea()
                }
            }
            .ignoresSafeArea()

            // Floating HUD overlays (auto-hide after 5s via HabitatHudIdleState)
            VStack(spacing: 0) {
                PetWorldHeader(
                    viewModel: viewModel,
                    pet: pet,
                    lifecycle: lifecycleSnap,
                    effectiveStage: previewStageOverride ?? lifecycleSnap?.stage ?? .infant,
                    period: period,
                    energy: petState.wallet.availableEnergy,
                    onCyclePeriod: {
                        registerHudActivity()
                        if viewModel.petVisualOverride == nil {
                            viewModel.petVisualOverride = (period == .day ? .night : .day)
                        } else if viewModel.petVisualOverride == .day {
                            viewModel.petVisualOverride = .night
                        } else {
                            viewModel.petVisualOverride = nil
                        }
                    },
                    onOpenCompanions: {
                        registerHudActivity()
                        showCompanionSheet = true
                    },
                    onOpenSettings: {
                        registerHudActivity()
                        showSettingsSheet = true
                    }
                )
                .padding(.horizontal, 16)
                .padding(.top, 10)

                if let banner = viewModel.pendingMilestoneBanner {
                    milestoneBannerView(banner: banner)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                Spacer()

                PetWorldHud(
                    pet: pet,
                    energy: petState.wallet.availableEnergy,
                    isCustomPet: pet.customDefinitionId != nil,
                    customActions: pet.customDefinitionId.flatMap { cid in
                        petState.customPets.first(where: { $0.id == cid })?.actions
                    } ?? [],
                    pinnedActionId: $pinCustomActionId,
                    onFeed: { amount in
                        registerHudActivity()
                        Task { await viewModel.feedPet(id: pet.id, energy: amount) }
                    },
                    onInteract: {
                        registerHudActivity()
                        Task { await viewModel.interactPet(id: pet.id) }
                    },
                    onOpenCompanions: {
                        registerHudActivity()
                        showCompanionSheet = true
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 86)
            }
            .opacity(hudIdle.visibility == .hidden ? 0 : 1)
            .offset(y: hudIdle.visibility == .hidden ? 18 : 0)
            .allowsHitTesting(hudIdle.visibility == .visible)
            .animation(.easeInOut(duration: 0.28), value: hudIdle.visibility)
        }
    }

    private func milestoneBannerView(banner: PetMilestoneBanner) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title)
                    .font(SumFont.body(13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(banner.detail)
                    .font(SumFont.body(11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("知道了") {
                registerHudActivity()
                Task { await viewModel.acknowledgePendingMilestone() }
            }
            .font(SumFont.body(11, weight: .semibold))
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(palette.accent, in: Capsule())
        }
        .padding(12)
        .pickbankLiquidGlass(in: RoundedRectangle(cornerRadius: 18), tint: palette.surfaceElevated.opacity(0.9))
    }

    private var emptyHabitatView: some View {
        VStack(spacing: 18) {
            Spacer()
            SumCard(cornerRadius: 24, highlightAccent: true) {
                VStack(spacing: 14) {
                    Image(systemName: "pawprint.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(palette.accent)
                    Text("拾念像素伙伴家园")
                        .font(SumFont.heading(22, hermes: palette.isHermes))
                        .foregroundStyle(palette.textPrimary)
                    Text("守住每日预算即可在夜间结算获得⚡能量，领养 8 种官方像素动物或导入自己的多动作/视频伙伴。")
                        .font(SumFont.body(13))
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 12) {
                        Button("领养首位伙伴") {
                            showCompanionSheet = true
                        }
                        .pickbankGlassButton(prominent: true, tint: palette.accent)

                        Button("创意工坊") {
                            showCustomWorkshop = true
                        }
                        .pickbankGlassButton(prominent: false)
                    }
                }
                .padding(24)
            }
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    private var petDisabledOnboarding: some View {
        VStack(spacing: 18) {
            Spacer()
            SumCard(cornerRadius: 24, highlightAccent: true) {
                VStack(spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 44))
                        .foregroundStyle(palette.accent)
                    Text("伙伴家园已暂停显示")
                        .font(SumFont.heading(20, hermes: palette.isHermes))
                        .foregroundStyle(palette.textPrimary)
                    Text("开启后可在记账保存时触发跨屏像素偶遇，并使用 8 个昼夜小屋、五阶段真实生命周期与本地自定义伙伴工坊。")
                        .font(SumFont.body(13))
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("开启像素伙伴") {
                        Task { await viewModel.setPetModuleEnabled(true) }
                    }
                    .pickbankGlassButton(prominent: true, tint: palette.accent)
                }
                .padding(24)
            }
            .padding(.horizontal, 24)
            Spacer()
        }
    }
}

// MARK: - Living Scene Renderer (All 8 Species × 39 Slots × 5 Stages × Day/Night Rooms & Stage Patches)

private struct LivingSceneRendererView: View {
    let pet: PetProfile
    let entry: PetSpeciesManifestEntry
    let stage: LifecycleStage
    let vitalState: VitalState
    let period: HabitatVisualPeriod
    let animationsEnabled: Bool
    let preferredSlotId: String?
    let heartBurstToken: Int
    let onStageTap: () -> Void

    @State private var currentSlot: PetSlotManifestEntry? = nil
    @State private var recentSlotIds: [String] = []
    @State private var seqIndex = 0
    @State private var floatingHearts: [UUID] = []

    private var roomImage: PlatformImage? {
        let file = (period == .day) ? entry.dayRoom : entry.nightRoom
        return PickBankBundle.loadPetImage(subdirectory: "rooms", fileName: file)
    }

    private var circadianPhase: CircadianPhase {
        let hour = Calendar.current.component(.hour, from: Date())
        return period == .day
            ? ((hour >= 6 && hour < 19) ? CircadianPhase.from(hour: hour) : .day)
            : ((hour >= 19 || hour < 6) ? CircadianPhase.from(hour: hour) : .night)
    }

    var body: some View {
        GeometryReader { geo in
            let containerW = Double(geo.size.width)
            let containerH = Double(geo.size.height)
            let proj = SceneProjectionResult.project(
                containerWidth: containerW,
                containerHeight: containerH,
                authoredWidth: entry.authoredWidth,
                authoredHeight: entry.authoredHeight
            )

            ZStack(alignment: .topLeading) {
                Color.black

                if let bg = roomImage {
                    Image(platformImage: bg)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: proj.projectedWidth, height: proj.projectedHeight)
                        .offset(x: proj.cropOriginX, y: proj.cropOriginY)
                }

                if let slot = currentSlot {
                    let rect = proj.actorFrameRect(
                        anchorXFraction: slot.anchorX,
                        anchorYFraction: slot.anchorY,
                        actorSizeFraction: slot.size,
                        localCanvasWidth: slot.canvasWidth,
                        localCanvasHeight: slot.canvasHeight
                    )
                    let frames = slot.frames(for: stage, period: period)
                    let seq = slot.sequence.isEmpty ? Array(0..<max(1, frames.count)) : slot.sequence
                    let activeFrameIdx = seq[seqIndex % max(1, seq.count)]
                    let frameFile = (activeFrameIdx < frames.count) ? frames[activeFrameIdx] : frames.first

                    if let patchFile = slot.cleanupPatch(for: stage, period: period),
                       !patchFile.isEmpty,
                       let patchImg = PickBankBundle.loadPetImage(subdirectory: "stage_patches", fileName: patchFile) {
                        Image(platformImage: patchImg)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.x, y: rect.y)
                            .id("patch-\(slot.id)-\(period.rawValue)")
                    }

                    if let frameFile {
                        let subdir: String = (stage == .infant)
                            ? (period == .day ? "fixed_infant_day" : "fixed_infant_night")
                            : "stages"
                        if let actorImg = PickBankBundle.loadPetImage(subdirectory: subdir, fileName: frameFile) {
                            Image(platformImage: actorImg)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: rect.width, height: rect.height)
                                .offset(x: rect.x, y: rect.y)
                                .opacity(pet.satiety <= 0 ? 0.65 : 1.0)
                                .id("actor-\(slot.id)-\(stage.rawValue)-\(period.rawValue)")
                                .transition(.opacity)
                        }
                    }

                    // Tap heart burst anchored near pet
                    ForEach(floatingHearts, id: \.self) { _ in
                        FloatingHeartView()
                            .position(x: rect.x + rect.width * 0.5, y: max(80, rect.y + rect.height * 0.18))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture {
                onStageTap()
            }
        }
        .onChange(of: heartBurstToken) { _, _ in
            spawnHeart()
        }
        .onChange(of: preferredSlotId) { _, _ in
            pickNextSlot(immediate: true)
        }
        .task(id: "slot-rotation-\(pet.id)-\(entry.speciesKey)-\(vitalState.rawValue)-\(period.rawValue)-\(preferredSlotId ?? "auto")") {
            pickNextSlot(immediate: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(16))
                guard !Task.isCancelled else { break }
                if preferredSlotId == nil {
                    pickNextSlot(immediate: false)
                }
            }
        }
        .task(id: "frame-loop-\(currentSlot?.id ?? "none")-\(stage.rawValue)-\(period.rawValue)-\(animationsEnabled)") {
            seqIndex = 0
            guard animationsEnabled, let slot = currentSlot else { return }
            let seq = slot.sequence.isEmpty ? Array(0..<max(1, slot.frames(for: stage, period: period).count)) : slot.sequence
            guard seq.count > 1 else { return }
            let durations = slot.frameDurationsMs
            while !Task.isCancelled {
                let idx = seqIndex % seq.count
                let ms = idx < durations.count ? max(70, durations[idx]) : 160
                try? await Task.sleep(for: .milliseconds(ms))
                guard !Task.isCancelled else { break }
                seqIndex &+= 1
            }
        }
    }

    private func pickNextSlot(immediate: Bool) {
        guard let next = LivingSceneStateMachine.chooseSlot(
            from: entry,
            vitalState: vitalState,
            satiety: pet.satiety,
            phase: circadianPhase,
            recentSlotIds: recentSlotIds,
            preferredSlotId: preferredSlotId
        ) else { return }

        if immediate {
            currentSlot = next
            seqIndex = 0
        } else {
            withAnimation(.easeInOut(duration: 0.36)) {
                currentSlot = next
                seqIndex = 0
            }
        }
        recentSlotIds = ([next.id] + recentSlotIds.filter { $0 != next.id }).prefix(4).map { $0 }
    }

    private func spawnHeart() {
        let id = UUID()
        floatingHearts.append(id)
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            floatingHearts.removeAll { $0 == id }
        }
    }
}

private struct FloatingHeartView: View {
    @State private var lift = false

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(Color(hex: 0xFF7B93))
            .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
            .offset(y: lift ? -46 : 0)
            .scaleEffect(lift ? 1.18 : 0.72)
            .opacity(lift ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 0.85)) {
                    lift = true
                }
            }
    }
}

// MARK: - Custom Pet Stage View (Multi-action role rotation + 1–30 fps frames OR AVPlayer loop)

private struct CustomHabitatStageView: View {
    @ObservedObject var viewModel: AppViewModel
    let pet: PetProfile
    let definition: CustomPetDefinition
    let animationsEnabled: Bool
    @Binding var pinnedActionId: String?
    let heartBurstToken: Int
    let onStageTap: () -> Void

    @State private var activeAction: CustomPetActionDefinition? = nil
    @State private var frameIndex = 0
    @State private var avPlayer: AVPlayer? = nil
    @State private var hearts: [UUID] = []

    private var desiredRole: CustomActionRole {
        let hour = Calendar.current.component(.hour, from: Date())
        let phase = CircadianPhase.from(hour: hour)
        if pet.satiety <= 25 { return .eat }
        if phase == .night || phase == .lateNight { return .rest }
        return .play
    }

    private func chooseAction() -> CustomPetActionDefinition? {
        if let pinnedActionId,
           let pinned = definition.actions.first(where: { $0.id == pinnedActionId }) {
            return pinned
        }
        let preferred = definition.actions.filter { $0.role == desiredRole.rawValue }
        if !preferred.isEmpty {
            return preferred.randomElement()
        }
        return definition.actions.first
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.black

                if let bgFile = definition.sceneImageFileName,
                   let data = try? Data(contentsOf: viewModel.customPetMediaURL(definitionId: definition.id, fileName: bgFile)),
                   let img = PlatformImage(data: data) {
                    Image(platformImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }

                let actorWidth = Double(geo.size.width) * Double(max(40, min(180, definition.scalePercent))) / 180.0
                let posX = Double(geo.size.width) * definition.anchorXFraction
                let posY = Double(geo.size.height) * definition.anchorYFraction

                if let action = activeAction {
                    Group {
                        if let videoFile = action.videoFileName, !videoFile.isEmpty, let player = avPlayer {
                            VideoPlayer(player: player)
                                .frame(width: actorWidth, height: actorWidth)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .allowsHitTesting(false)
                        } else if !action.frameFileNames.isEmpty {
                            let safeIdx = frameIndex % action.frameFileNames.count
                            let file = action.frameFileNames[safeIdx]
                            if let data = try? Data(contentsOf: viewModel.customPetMediaURL(definitionId: definition.id, fileName: file)),
                               let img = PlatformImage(data: data) {
                                Image(platformImage: img)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: actorWidth, height: actorWidth)
                            }
                        }
                    }
                    .position(x: posX, y: posY - actorWidth * 0.45)

                    ForEach(hearts, id: \.self) { _ in
                        FloatingHeartView()
                            .position(x: posX, y: max(80, posY - actorWidth * 0.9))
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onStageTap()
            }
        }
        .onChange(of: heartBurstToken) { _, _ in
            let id = UUID()
            hearts.append(id)
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                hearts.removeAll { $0 == id }
            }
        }
        .onChange(of: pinnedActionId) { _, _ in
            refreshActionMedia(chooseAction())
        }
        .task(id: "custom-rotate-\(definition.id)-\(pinnedActionId ?? "auto")") {
            refreshActionMedia(chooseAction())
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled else { break }
                if pinnedActionId == nil {
                    refreshActionMedia(chooseAction())
                }
            }
        }
        .task(id: "custom-frames-\(activeAction?.id ?? "none")-\(animationsEnabled)") {
            frameIndex = 0
            guard animationsEnabled,
                  let action = activeAction,
                  action.videoFileName == nil,
                  action.frameFileNames.count > 1 else { return }
            let ms = max(33, 1000 / max(1, min(30, action.fps)))
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(ms))
                guard !Task.isCancelled else { break }
                frameIndex &+= 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            guard let item = note.object as? AVPlayerItem,
                  item == avPlayer?.currentItem else { return }
            avPlayer?.seek(to: .zero)
            avPlayer?.play()
        }
    }

    private func refreshActionMedia(_ next: CustomPetActionDefinition?) {
        activeAction = next
        frameIndex = 0
        avPlayer?.pause()
        if let videoFile = next?.videoFileName, !videoFile.isEmpty {
            let url = viewModel.customPetMediaURL(definitionId: definition.id, fileName: videoFile)
            let p = AVPlayer(url: url)
            p.isMuted = true
            p.play()
            avPlayer = p
        } else {
            avPlayer = nil
        }
    }
}

// MARK: - Floating Liquid Glass Header & HUD

private struct PetWorldHeader: View {
    @ObservedObject var viewModel: AppViewModel
    let pet: PetProfile
    let lifecycle: PetLifecycleSnapshot?
    let effectiveStage: LifecycleStage
    let period: HabitatVisualPeriod
    let energy: Int
    let onCyclePeriod: () -> Void
    let onOpenCompanions: () -> Void
    let onOpenSettings: () -> Void

    @Environment(\.sumPalette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(pet.name)
                        .font(SumFont.heading(16, hermes: palette.isHermes))
                        .foregroundStyle(palette.textPrimary)
                    Text("\(effectiveStage.zhLabel) · \(lifecycle?.ageDays ?? 0)天")
                        .font(SumFont.mono(10, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(palette.accent.opacity(0.16), in: Capsule())
                }
                if let species = pet.builtInSpecies,
                   let entry = viewModel.petManifest?.entry(for: species) {
                    Text("\(entry.homeLabel) · 饱食 \(pet.satiety)%")
                        .font(SumFont.body(11))
                        .foregroundStyle(palette.textSecondary)
                } else {
                    Text("自定义小家 · 饱食 \(pet.satiety)%")
                        .font(SumFont.body(11))
                        .foregroundStyle(palette.textSecondary)
                }
            }

            Spacer()

            Button(action: onCyclePeriod) {
                HStack(spacing: 4) {
                    Image(systemName: period == .day ? "sun.max.fill" : "moon.stars.fill")
                    Text(viewModel.petVisualOverride == nil ? "自动" : (period == .day ? "昼" : "夜"))
                }
                .font(SumFont.mono(11, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .pickbankLiquidGlass(in: Capsule(), tint: palette.surfaceElevated.opacity(0.8))
            }

            Text("⚡\(energy)")
                .font(SumFont.mono(12, weight: .bold))
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .pickbankLiquidGlass(in: Capsule(), tint: palette.surfaceElevated.opacity(0.8))

            Button(action: onOpenCompanions) {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 34, height: 34)
                    .pickbankLiquidGlass(in: Circle(), tint: palette.surfaceElevated.opacity(0.8))
            }

            Button(action: onOpenSettings) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 34, height: 34)
                    .pickbankLiquidGlass(in: Circle(), tint: palette.surfaceElevated.opacity(0.8))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .pickbankLiquidGlass(in: RoundedRectangle(cornerRadius: 22), tint: palette.surface.opacity(0.76))
    }
}

private struct PetWorldHud: View {
    let pet: PetProfile
    let energy: Int
    let isCustomPet: Bool
    let customActions: [CustomPetActionDefinition]
    @Binding var pinnedActionId: String?
    let onFeed: (Int) -> Void
    let onInteract: () -> Void
    let onOpenCompanions: () -> Void

    @Environment(\.sumPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isCustomPet && !customActions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Button {
                            pinnedActionId = nil
                        } label: {
                            Text("自动轮换")
                                .font(SumFont.body(11, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .foregroundStyle(pinnedActionId == nil ? palette.ink : palette.textPrimary)
                                .background(
                                    pinnedActionId == nil ? palette.accent : palette.surfaceElevated.opacity(0.85),
                                    in: Capsule()
                                )
                        }
                        ForEach(customActions) { act in
                            Button {
                                pinnedActionId = (pinnedActionId == act.id) ? nil : act.id
                            } label: {
                                Text("\(act.label)")
                                    .font(SumFont.body(11, weight: .semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .foregroundStyle(pinnedActionId == act.id ? palette.ink : palette.textPrimary)
                                    .background(
                                        pinnedActionId == act.id ? palette.accent : palette.surfaceElevated.opacity(0.85),
                                        in: Capsule()
                                    )
                            }
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                miniMeter(title: "饱食", value: "\(pet.satiety)%", color: pet.satiety <= 20 ? palette.expense : palette.income)
                miniMeter(title: "好感", value: "\(pet.affection)", color: palette.accent)
                miniMeter(title: "成长", value: "\(pet.growth)", color: palette.transfer)
                Spacer()
            }

            HStack(spacing: 8) {
                Button {
                    onFeed(5)
                } label: {
                    Label("+5 ⚡", systemImage: "leaf.fill")
                        .font(SumFont.body(12, weight: .semibold))
                }
                .pickbankGlassButton(prominent: energy >= 5, tint: palette.income)
                .disabled(energy < 5)

                Button {
                    onFeed(15)
                } label: {
                    Label("+15 ⚡", systemImage: "flame.fill")
                        .font(SumFont.body(12, weight: .semibold))
                }
                .pickbankGlassButton(prominent: false)
                .disabled(energy < 15)

                Button(action: onInteract) {
                    Label("轻抚", systemImage: "heart.fill")
                        .font(SumFont.body(12, weight: .semibold))
                }
                .pickbankGlassButton(prominent: false)

                Spacer()

                Button(action: onOpenCompanions) {
                    Text("档案")
                        .font(SumFont.body(12, weight: .semibold))
                }
                .pickbankGlassButton(prominent: false)
            }
        }
        .padding(14)
        .pickbankLiquidGlass(in: RoundedRectangle(cornerRadius: 22), tint: palette.surface.opacity(0.82))
    }

    private func miniMeter(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title)
                .font(SumFont.body(11))
                .foregroundStyle(palette.textSecondary)
            Text(value)
                .font(SumFont.mono(12, weight: .bold))
                .foregroundStyle(palette.textPrimary)
        }
    }
}

// MARK: - Companion & Memorial Drawer Sheet

private struct PetCompanionSheet: View {
    @ObservedObject var viewModel: AppViewModel
    let onOpenWorkshop: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sumPalette) private var palette

    @State private var showMemorialSection = false
    @State private var renameTarget: PetProfile? = nil
    @State private var renameDraft = ""
    @State private var adoptTargetSpecies: PetSpecies? = nil
    @State private var adoptCustomTarget: CustomPetDefinition? = nil
    @State private var adoptNameDraft = ""
    @State private var releaseConfirmTarget: PetProfile? = nil
    @State private var releaseTypedName = ""

    private var petState: PetStateBundle { viewModel.snapshot.petState }
    private var todayKey: String { PickBankClock.dateKey() }

    private var currentPet: PetProfile? {
        if let id = viewModel.selectedPetId,
           let m = viewModel.activePets.first(where: { $0.id == id }) {
            return m
        }
        return viewModel.activePets.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    energyWalletCard
                    companionSwitcherSection

                    if showMemorialSection {
                        memorialArchiveSection
                    } else if let pet = currentPet {
                        PetProfileCard(
                            viewModel: viewModel,
                            pet: pet,
                            timeline: petState.timelines.first(where: { $0.petId == pet.id }),
                            todayKey: todayKey,
                            onStartRename: {
                                renameDraft = pet.name
                                renameTarget = pet
                            },
                            onStartRelease: {
                                releaseTypedName = ""
                                releaseConfirmTarget = pet
                            }
                        )
                    }

                    slotUnlockProgressAndAdoptionCard
                }
                .padding(16)
            }
            .navigationTitle("伙伴档案与栏位")
            .pickbankInlineNavBar()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("修改伙伴昵称 (1–20字)", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("输入新名字", text: $renameDraft)
                Button("取消", role: .cancel) { renameTarget = nil }
                Button("保存") {
                    if let target = renameTarget {
                        let cleaned = String(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
                        if !cleaned.isEmpty {
                            Task { await viewModel.renamePet(id: target.id, newName: cleaned) }
                        }
                    }
                    renameTarget = nil
                }
            }
            .alert("领养新伙伴", isPresented: Binding(
                get: { adoptTargetSpecies != nil || adoptCustomTarget != nil },
                set: {
                    if !$0 {
                        adoptTargetSpecies = nil
                        adoptCustomTarget = nil
                    }
                }
            )) {
                TextField("起一个好听的名字", text: $adoptNameDraft)
                Button("取消", role: .cancel) {
                    adoptTargetSpecies = nil
                    adoptCustomTarget = nil
                }
                Button("迎接回家") {
                    let cleanName = adoptNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let sp = adoptTargetSpecies {
                        Task { await viewModel.adoptBuiltInPet(species: sp, name: cleanName.isEmpty ? sp.zhName : cleanName) }
                    } else if let def = adoptCustomTarget {
                        Task { await viewModel.adoptCustomPet(definitionId: def.id, name: cleanName.isEmpty ? def.name : cleanName) }
                    }
                    adoptTargetSpecies = nil
                    adoptCustomTarget = nil
                }
            }
            .sheet(item: $releaseConfirmTarget) { target in
                NavigationStack {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("确认送「\(target.name)」回归自然？")
                            .font(SumFont.heading(20, hermes: palette.isHermes))
                        Text("放生后该伙伴将温柔离开当前小屋，其相伴天数、成长值与好感度会永久封存在「纪念档案」中，并且无法撤销。请输入它的名字以确认：")
                            .font(SumFont.body(13))
                            .foregroundStyle(.secondary)
                        TextField("输入「\(target.name)」确认放生", text: $releaseTypedName)
                            .textFieldStyle(.roundedBorder)
                        Button(role: .destructive) {
                            Task {
                                await viewModel.releasePet(id: target.id)
                                releaseConfirmTarget = nil
                            }
                        } label: {
                            Text("确认放生并封存纪念")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(releaseTypedName.trimmingCharacters(in: .whitespacesAndNewlines) != target.name)
                        Spacer()
                    }
                    .padding(20)
                    .navigationTitle("放生确认")
                    .pickbankInlineNavBar()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { releaseConfirmTarget = nil }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }

    private var energyWalletCard: some View {
        SumCard(cornerRadius: 20, highlightAccent: true) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("能量钱包与自定义工坊")
                        .font(SumFont.body(15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("可用 ⚡\(petState.wallet.availableEnergy) · 累计获得 \(petState.wallet.lifetimeEarnedEnergy) · 日预算 \(MoneyFormatter.formatYuan(cents: petState.settings.budgetAmountCents))")
                        .font(SumFont.mono(11))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Button("工坊") {
                    onOpenWorkshop()
                }
                .pickbankGlassButton(prominent: false)
            }
            .padding(14)
        }
    }

    private var companionSwitcherSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.activePets) { pet in
                    let isSel = !showMemorialSection && (pet.id == currentPet?.id)
                    Button {
                        showMemorialSection = false
                        viewModel.selectedPetId = pet.id
                    } label: {
                        HStack(spacing: 6) {
                            Text(pet.name)
                            Text("\(pet.satiety)%")
                                .font(SumFont.mono(10, weight: .bold))
                        }
                        .font(SumFont.body(13, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(isSel ? palette.ink : palette.textPrimary)
                        .background(isSel ? palette.accent : palette.surfaceElevated, in: Capsule())
                    }
                }

                Button {
                    withAnimation { showMemorialSection.toggle() }
                } label: {
                    Label("纪念档案 (\(viewModel.memorialPets.count))", systemImage: "archivebox.fill")
                        .font(SumFont.body(12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(showMemorialSection ? palette.ink : palette.textSecondary)
                        .background(showMemorialSection ? palette.accent : palette.surfaceElevated, in: Capsule())
                }
            }
        }
    }

    private var memorialArchiveSection: some View {
        SumCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("永久纪念档案 (已放生 / 已走完一生)")
                    .font(SumFont.body(14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                if viewModel.memorialPets.isEmpty {
                    Text("目前还没有封存纪念的伙伴。每一段认真陪伴都会被妥善记住。")
                        .font(SumFont.body(12))
                        .foregroundStyle(palette.textSecondary)
                } else {
                    ForEach(viewModel.memorialPets) { pet in
                        let rec = petState.releasedRecords.first(where: { $0.petId == pet.id })
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pet.name)
                                    .font(SumFont.body(14, weight: .bold))
                                    .foregroundStyle(palette.textPrimary)
                                if let rec {
                                    Text("已放生 · \(rec.releaseDateKey) · 相伴 \(rec.adoptionDays) 天 · 成长 \(rec.growthAtRelease) · 好感 \(rec.affectionAtRelease)")
                                        .font(SumFont.mono(10))
                                        .foregroundStyle(palette.textSecondary)
                                } else {
                                    Text("自然纪念 · 成长 \(pet.growth) · 好感 \(pet.affection)")
                                        .font(SumFont.mono(10))
                                        .foregroundStyle(palette.textSecondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "leaf.fill").foregroundStyle(palette.accent)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(14)
        }
    }

    private var slotUnlockProgressAndAdoptionCard: some View {
        let slotsUsed = viewModel.activePets.count
        let unlocked = petState.slotState.unlockedSlots
        let canAdoptMore = slotsUsed < unlocked
        let tlMap = Dictionary(uniqueKeysWithValues: petState.timelines.map { ($0.petId, $0) })

        let maxDays = viewModel.activePets.map { PetAdoptionPolicy.adoptionDays(profile: $0, timeline: tlMap[$0.id], todayKey: todayKey) }.max() ?? 0
        let maxAff = viewModel.activePets.map(\.affection).max() ?? 0
        let maxGrowth = viewModel.activePets.map(\.growth).max() ?? 0

        return SumCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("家园领养栏位 (\(slotsUsed)/\(unlocked))")
                        .font(SumFont.body(15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(canAdoptMore ? "可迎接新伙伴" : "继续陪伴解锁")
                        .font(SumFont.mono(11, weight: .semibold))
                        .foregroundStyle(canAdoptMore ? palette.income : palette.textSecondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("路线 A（时间羁绊）：陪伴 \(maxDays)/\(PetAdoptionPolicy.bondMinDays) 天 且 好感 \(maxAff)/\(PetAdoptionPolicy.bondMinAffection)")
                        .font(SumFont.mono(10))
                        .foregroundStyle(palette.textSecondary)
                    ProgressView(value: min(1.0, (Double(maxDays) / Double(PetAdoptionPolicy.bondMinDays) + Double(maxAff) / Double(PetAdoptionPolicy.bondMinAffection)) / 2.0))
                        .tint(palette.accent)

                    Text("路线 B（成长共鸣）：成长 \(maxGrowth)/\(PetAdoptionPolicy.growthMinGrowth) 且 好感 \(maxAff)/\(PetAdoptionPolicy.growthMinAffection)")
                        .font(SumFont.mono(10))
                        .foregroundStyle(palette.textSecondary)
                    ProgressView(value: min(1.0, (Double(maxGrowth) / Double(PetAdoptionPolicy.growthMinGrowth) + Double(maxAff) / Double(PetAdoptionPolicy.growthMinAffection)) / 2.0))
                        .tint(palette.income)
                }

                Text("官方 8 大像素物种")
                    .font(SumFont.body(13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(PetSpecies.allCases, id: \.self) { sp in
                        Button {
                            adoptNameDraft = sp.zhName
                            adoptTargetSpecies = sp
                        } label: {
                            HStack(spacing: 8) {
                                if let img = PickBankBundle.loadPetImage(subdirectory: "portraits", fileName: "\(sp.resourceKey)_base.png") {
                                    Image(platformImage: img)
                                        .interpolation(.none)
                                        .resizable()
                                        .frame(width: 28, height: 28)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(sp.zhName)
                                        .font(SumFont.body(12, weight: .semibold))
                                        .foregroundStyle(palette.textPrimary)
                                    Text(sp.habitatTitleZh)
                                        .font(SumFont.body(9))
                                        .foregroundStyle(palette.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(!canAdoptMore)
                        .opacity(canAdoptMore ? 1.0 : 0.48)
                    }
                }

                if !petState.customPets.isEmpty {
                    Text("我的自定义伙伴模板")
                        .font(SumFont.body(13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    ForEach(petState.customPets) { def in
                        Button {
                            adoptNameDraft = def.name
                            adoptCustomTarget = def
                        } label: {
                            HStack {
                                Text(def.name)
                                    .font(SumFont.body(13, weight: .semibold))
                                    .foregroundStyle(palette.textPrimary)
                                Text("· \(def.actions.count) 个动作")
                                    .font(SumFont.mono(11))
                                    .foregroundStyle(palette.textSecondary)
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(palette.accent)
                            }
                            .padding(10)
                            .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(!canAdoptMore)
                        .opacity(canAdoptMore ? 1.0 : 0.48)
                    }
                }
            }
            .padding(14)
        }
    }
}

private struct PetProfileCard: View {
    @ObservedObject var viewModel: AppViewModel
    let pet: PetProfile
    let timeline: PetLifecycleTimeline?
    let todayKey: String
    let onStartRename: () -> Void
    let onStartRelease: () -> Void

    @Environment(\.sumPalette) private var palette

    private var portraitImage: PlatformImage? {
        guard let sp = pet.builtInSpecies else { return nil }
        if (sp == .cat || sp == .dog),
           let preview = PickBankBundle.loadPetImage(subdirectory: "portraits", fileName: "\(sp.resourceKey)_preview.png") {
            return preview
        }
        return PickBankBundle.loadPetImage(subdirectory: "portraits", fileName: "\(sp.resourceKey)_base.png")
    }

    var body: some View {
        let snap = timeline.map { PetLifecycleEngine.evaluate(timeline: $0, todayKey: todayKey) }
        let blockReason = PetAdoptionPolicy.releaseBlockReason(
            profile: pet,
            timeline: timeline,
            snapshot: snap,
            isReleased: false,
            todayKey: todayKey
        )

        return SumCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    if let portrait = portraitImage {
                        Image(platformImage: portrait)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 72, height: 72)
                            .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: 16))
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(palette.surfaceElevated)
                            .frame(width: 72, height: 72)
                            .overlay { Image(systemName: "sparkles").foregroundStyle(palette.accent) }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(pet.name)
                                .font(SumFont.heading(18, hermes: palette.isHermes))
                                .foregroundStyle(palette.textPrimary)
                            Button(action: onStartRename) {
                                Image(systemName: "pencil")
                                    .font(.caption)
                                    .foregroundStyle(palette.accent)
                            }
                        }
                        if let snap {
                            Text("\(snap.stage.zhLabel) · 相伴第 \(snap.ageDays) 天 · \(snap.vitalState == .ill ? "休养中" : "状态良好")")
                                .font(SumFont.mono(11))
                                .foregroundStyle(snap.vitalState == .ill ? palette.expense : palette.textSecondary)
                            if let nextDays = snap.daysUntilNextStage {
                                Text("距下一生长阶段还有 \(nextDays) 天")
                                    .font(SumFont.body(11))
                                    .foregroundStyle(palette.textTertiary)
                            }
                        }
                    }
                    Spacer()
                }

                HStack(spacing: 8) {
                    Button("+5 投喂") { Task { await viewModel.feedPet(id: pet.id, energy: 5) } }
                        .pickbankGlassButton(prominent: false)
                    Button("+15 投喂") { Task { await viewModel.feedPet(id: pet.id, energy: 15) } }
                        .pickbankGlassButton(prominent: false)
                    Button("+30 饱餐") { Task { await viewModel.feedPet(id: pet.id, energy: 30) } }
                        .pickbankGlassButton(prominent: false)
                }

                Divider().overlay(palette.divider)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("放生至永久纪念档案")
                            .font(SumFont.body(12, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                        if let blockReason {
                            Text(blockReason)
                                .font(SumFont.body(11))
                                .foregroundStyle(palette.textSecondary)
                        } else {
                            Text("已满足放生条件，可温柔道别并永久封存档案。")
                                .font(SumFont.body(11))
                                .foregroundStyle(palette.income)
                        }
                    }
                    Spacer()
                    Button("放生") {
                        onStartRelease()
                    }
                    .font(SumFont.body(12, weight: .bold))
                    .foregroundStyle(blockReason == nil ? palette.expense : palette.textTertiary)
                    .disabled(blockReason != nil)
                }
            }
            .padding(14)
        }
    }
}

// MARK: - Pet Settings Sheet (Budget, Behavior, Visual Period / Slot / Stage Previewers)

private struct PetSettingsSheet: View {
    @ObservedObject var viewModel: AppViewModel
    let selectedPet: PetProfile?
    @Binding var previewSlotId: String?
    @Binding var previewStageOverride: LifecycleStage?
    @Environment(\.dismiss) private var dismiss

    @State private var budgetYuanDraft = ""
    @State private var showDisableConfirm = false

    private var settings: PetModuleSettings { viewModel.snapshot.petState.settings }

    private var selectedSpeciesEntry: PetSpeciesManifestEntry? {
        guard let sp = selectedPet?.builtInSpecies else { return nil }
        return viewModel.petManifest?.entry(for: sp)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("每日伙伴能量预算") {
                    Picker("预算来源", selection: Binding(
                        get: { settings.budgetMode },
                        set: { mode in
                            Task { await viewModel.updatePetSettings { $0.budgetMode = mode } }
                        }
                    )) {
                        Text("每日独立零花预算").tag(PetBudgetMode.daily)
                        Text("绑定全局月预算折算").tag(PetBudgetMode.monthly)
                    }
                    HStack {
                        Text("日预算金额 (¥)")
                        TextField("120", text: $budgetYuanDraft)
                            .pickbankDecimalKeyboard()
                            .multilineTextAlignment(.trailing)
                    }
                    Button("保存预算设置") {
                        if let cents = MoneyFormatter.parseToCents(budgetYuanDraft), cents > 0 {
                            Task {
                                await viewModel.updatePetSettings { $0.budgetAmountCents = cents }
                                viewModel.showToast(message: "伙伴日预算已更新")
                            }
                        }
                    }
                }

                Section("动效与偶遇行为") {
                    Toggle("启用栖息地像素动效", isOn: Binding(
                        get: { settings.animationsEnabled },
                        set: { v in Task { await viewModel.updatePetSettings { $0.animationsEnabled = v } } }
                    ))
                    Toggle("记账保存时跨屏像素偶遇", isOn: Binding(
                        get: { settings.globalEncountersEnabled },
                        set: { v in Task { await viewModel.updatePetSettings { $0.globalEncountersEnabled = v } } }
                    ))
                    Picker("偶遇频率", selection: Binding(
                        get: { settings.behaviorPreferences.frequency },
                        set: { v in Task { await viewModel.updatePetSettings { $0.behaviorPreferences.frequency = v } } }
                    )) {
                        ForEach(EncounterFrequency.allCases, id: \.self) { freq in
                            Text(freq.zhLabel).tag(freq)
                        }
                    }
                    Toggle("键盘展开时仍允许偶遇", isOn: Binding(
                        get: { settings.behaviorPreferences.allowWithKeyboard },
                        set: { v in Task { await viewModel.updatePetSettings { $0.behaviorPreferences.allowWithKeyboard = v } } }
                    ))
                    Toggle("双伙伴结伴偶遇", isOn: Binding(
                        get: { settings.behaviorPreferences.dualEncounters },
                        set: { v in Task { await viewModel.updatePetSettings { $0.behaviorPreferences.dualEncounters = v } } }
                    ))
                    Toggle("夜间安静模式 (不打扰)", isOn: Binding(
                        get: { settings.behaviorPreferences.quietAtNight },
                        set: { v in Task { await viewModel.updatePetSettings { $0.behaviorPreferences.quietAtNight = v } } }
                    ))
                    Toggle("轻触震动反馈", isOn: Binding(
                        get: { settings.behaviorPreferences.hapticsEnabled },
                        set: { v in Task { await viewModel.updatePetSettings { $0.behaviorPreferences.hapticsEnabled = v } } }
                    ))
                    Toggle("减弱动态效果", isOn: Binding(
                        get: { settings.behaviorPreferences.reduceMotion },
                        set: { v in Task { await viewModel.updatePetSettings { $0.behaviorPreferences.reduceMotion = v } } }
                    ))
                }

                Section("家园场景与生长阶段预览") {
                    Picker("昼夜视觉时段", selection: Binding(
                        get: { viewModel.petVisualOverride },
                        set: { viewModel.petVisualOverride = $0 }
                    )) {
                        Text("随真实昼夜自动切换").tag(Optional<HabitatVisualPeriod>.none)
                        Text("预览白昼小屋").tag(Optional<HabitatVisualPeriod>.some(.day))
                        Text("预览夜晚星空小屋").tag(Optional<HabitatVisualPeriod>.some(.night))
                    }

                    if let entry = selectedSpeciesEntry {
                        Picker("预览演出动作槽位 (\(entry.slots.count))", selection: $previewSlotId) {
                            Text("自然状态机自动轮播").tag(Optional<String>.none)
                            ForEach(entry.slots) { slot in
                                Text(slot.label).tag(Optional<String>.some(slot.id))
                            }
                        }

                        Picker("预览生命生长阶段", selection: $previewStageOverride) {
                            Text("跟随真实日历阶段").tag(Optional<LifecycleStage>.none)
                            ForEach(LifecycleStage.allCases, id: \.self) { st in
                                Text(st.zhLabel).tag(Optional<LifecycleStage>.some(st))
                            }
                        }
                    }
                }

                Section {
                    Button("暂时关闭伙伴模块", role: .destructive) {
                        showDisableConfirm = true
                    }
                }
            }
            .navigationTitle("伙伴设置与预览")
            .pickbankInlineNavBar()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                budgetYuanDraft = String(format: "%.0f", Double(settings.budgetAmountCents) / 100.0)
            }
            .alert("关闭像素伙伴？", isPresented: $showDisableConfirm) {
                Button("取消", role: .cancel) {}
                Button("确认关闭", role: .destructive) {
                    Task {
                        await viewModel.setPetModuleEnabled(false)
                        dismiss()
                    }
                }
            } message: {
                Text("已有伙伴与能量档案将安全保留在本地，随时可以在「数据中心」重新开启。")
            }
        }
    }
}

// MARK: - Multi-Action / Video Custom Pet Workshop Sheet

private struct DraftCustomAction: Identifiable {
    let id = UUID().uuidString
    var label: String
    var role: CustomActionRole
    var fps: Int = 8
    var pickedFrameURLs: [URL] = []
    var pickedVideoURL: URL? = nil
}

private enum WorkshopFilePickTarget: Identifiable {
    case sceneBackground
    case actionFrames(actionId: String)
    case actionVideo(actionId: String)

    var id: String {
        switch self {
        case .sceneBackground: return "scene"
        case .actionFrames(let aid): return "frames-\(aid)"
        case .actionVideo(let aid): return "video-\(aid)"
        }
    }

    var contentTypes: [UTType] {
        switch self {
        case .sceneBackground, .actionFrames: return [.image, .png]
        case .actionVideo: return [.movie, .mpeg4Movie, .quickTimeMovie]
        }
    }

    var allowsMultiple: Bool {
        if case .actionFrames = self { return true }
        return false
    }
}

private struct CustomPetWorkshopSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var scalePercent = 100
    @State private var anchorX: Double = 0.5
    @State private var anchorY: Double = 0.65
    @State private var sceneImageURL: URL? = nil
    @State private var draftActions: [DraftCustomAction] = [
        DraftCustomAction(label: "日常待机", role: .play, fps: 8)
    ]
    @State private var filePickTarget: WorkshopFilePickTarget? = nil

    private var adoptedDefinitionIds: Set<String> {
        Set(viewModel.snapshot.petState.profiles.compactMap(\.customDefinitionId))
    }

    private var validationErrors: [String] {
        buildCandidateDefinition(id: "preview").validationErrors()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基础外观与舞台定位") {
                    TextField("伙伴名称（如：像素小狐）", text: $name)
                    Stepper("缩放比例：\(scalePercent)%", value: $scalePercent, in: 40...180, step: 5)
                    VStack(alignment: .leading) {
                        Text(String(format: "水平锚点：%.0f%%", anchorX * 100)).font(.caption)
                        Slider(value: $anchorX, in: 0.15...0.85)
                    }
                    VStack(alignment: .leading) {
                        Text(String(format: "垂直锚点：%.0f%%", anchorY * 100)).font(.caption)
                        Slider(value: $anchorY, in: 0.25...0.95)
                    }
                    HStack {
                        Button(sceneImageURL == nil ? "选择小屋背景图（可选）" : "更换背景图") {
                            filePickTarget = .sceneBackground
                        }
                        Spacer()
                        Text(sceneImageURL?.lastPathComponent ?? "纯黑沉浸背景")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    ForEach($draftActions) { $act in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("动作名称", text: $act.label)
                                    .fontWeight(.semibold)
                                Picker("角色时段", selection: $act.role) {
                                    ForEach(CustomActionRole.allCases, id: \.self) { r in
                                        Text(r.zhLabel).tag(r)
                                    }
                                }
                                .labelsHidden()
                            }
                            Stepper("帧率：\(act.fps) FPS", value: $act.fps, in: 1...30)
                            HStack(spacing: 12) {
                                Button("选帧图 (\(act.pickedFrameURLs.count))") {
                                    filePickTarget = .actionFrames(actionId: act.id)
                                }
                                .buttonStyle(.bordered)
                                Button(act.pickedVideoURL == nil ? "或选循环视频" : "视频: \(act.pickedVideoURL!.lastPathComponent)") {
                                    filePickTarget = .actionVideo(actionId: act.id)
                                }
                                .buttonStyle(.bordered)
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }

                    Button {
                        draftActions.append(DraftCustomAction(label: "新动作 \(draftActions.count + 1)", role: .eat, fps: 8))
                    } label: {
                        Label("添加动作（吃东西 / 休息 / 陪伴）", systemImage: "plus.circle")
                    }
                } header: {
                    Text("多动作演出表 (图片序列或 MP4/MOV 视频)")
                }

                if !validationErrors.isEmpty {
                    Section("保存前检查") {
                        ForEach(validationErrors, id: \.self) { err in
                            Text("• \(err)").font(.caption).foregroundStyle(.orange)
                        }
                    }
                }

                Section {
                    Button("保存自定义伙伴模板") {
                        Task { await saveTemplate() }
                    }
                    .disabled(!validationErrors.isEmpty)
                }

                if !viewModel.snapshot.petState.customPets.isEmpty {
                    Section("已创建的自定义模板") {
                        ForEach(viewModel.snapshot.petState.customPets) { def in
                            let isAdopted = adoptedDefinitionIds.contains(def.id)
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(def.name).fontWeight(.semibold)
                                    Text("\(def.actions.count) 个动作 · 缩放 \(def.scalePercent)%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if isAdopted {
                                    Text("已领养锁定")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                } else {
                                    Button("删除", role: .destructive) {
                                        Task { await viewModel.deleteCustomPetDefinition(id: def.id) }
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("自定义伙伴工坊")
            .pickbankInlineNavBar()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: Binding(
                    get: { filePickTarget != nil },
                    set: { if !$0 { filePickTarget = nil } }
                ),
                allowedContentTypes: filePickTarget?.contentTypes ?? [.data],
                allowsMultipleSelection: filePickTarget?.allowsMultiple ?? false
            ) { result in
                defer { filePickTarget = nil }
                guard case .success(let urls) = result, let target = filePickTarget else { return }
                switch target {
                case .sceneBackground:
                    sceneImageURL = urls.first
                case .actionFrames(let aid):
                    if let idx = draftActions.firstIndex(where: { $0.id == aid }) {
                        draftActions[idx].pickedVideoURL = nil
                        draftActions[idx].pickedFrameURLs = urls
                    }
                case .actionVideo(let aid):
                    if let idx = draftActions.firstIndex(where: { $0.id == aid }) {
                        draftActions[idx].pickedFrameURLs = []
                        draftActions[idx].pickedVideoURL = urls.first
                    }
                }
            }
        }
    }

    private func buildCandidateDefinition(id: String) -> CustomPetDefinition {
        let actions: [CustomPetActionDefinition] = draftActions.enumerated().map { idx, d in
            let frames = d.pickedFrameURLs.enumerated().map { fi, url in
                let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
                return "act_\(idx)_frame_\(fi).\(ext)"
            }
            let video: String? = d.pickedVideoURL.map { url in
                let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
                return "act_\(idx)_video.\(ext)"
            }
            return CustomPetActionDefinition(
                id: d.id,
                label: d.label.trimmingCharacters(in: .whitespacesAndNewlines),
                role: d.role.rawValue,
                fps: d.fps,
                frameFileNames: frames,
                videoFileName: video
            )
        }
        let sceneFile = sceneImageURL.map { url in
            "scene.\(url.pathExtension.isEmpty ? "png" : url.pathExtension)"
        }
        return CustomPetDefinition(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            scalePercent: scalePercent,
            anchorXFraction: anchorX,
            anchorYFraction: anchorY,
            sceneImageFileName: sceneFile,
            actions: actions,
            createdAt: PickBankClock.nowMs()
        )
    }

    private func saveTemplate() async {
        let newId = "custom_\(UUID().uuidString.prefix(8).lowercased())"
        let def = buildCandidateDefinition(id: newId)
        var copies: [(sourceURL: URL, targetFileName: String)] = []
        if let sceneURL = sceneImageURL, let sceneName = def.sceneImageFileName {
            copies.append((sceneURL, sceneName))
        }
        for (idx, d) in draftActions.enumerated() {
            if let vUrl = d.pickedVideoURL, let vName = def.actions[idx].videoFileName {
                copies.append((vUrl, vName))
            }
            for (fi, fUrl) in d.pickedFrameURLs.enumerated() where fi < def.actions[idx].frameFileNames.count {
                copies.append((fUrl, def.actions[idx].frameFileNames[fi]))
            }
        }
        await viewModel.saveCustomPetDefinition(def, copiedFiles: copies)
        name = ""
        sceneImageURL = nil
        draftActions = [DraftCustomAction(label: "日常待机", role: .play, fps: 8)]
    }
}
