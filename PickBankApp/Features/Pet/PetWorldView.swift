import AVKit
import PhotosUI
import PickBankCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public enum PetBundleImageLoader {
    public static func roomImage(species: PetSpecies, period: HabitatVisualPeriod) -> UIImage? {
        let name = "\(species.resourceKey)_\(period == .day ? "day" : "night")"
        if let url = Bundle.main.url(forResource: name, withExtension: "heic", subdirectory: "PetAssets/rooms"),
           let data = try? Data(contentsOf: url) {
            return UIImage(data: data)
        }
        return nil
    }

    public static func actorFrame(fileName: String) -> UIImage? {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        if let url = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "PetAssets/actors"),
           let data = try? Data(contentsOf: url) {
            return UIImage(data: data)
        }
        return nil
    }

    public static func portrait(species: PetSpecies, kind: String = "base") -> UIImage? {
        let name: String
        if kind == "base" && (species == .cat || species == .dog) {
            name = "\(species.resourceKey)_preview"
        } else {
            name = "\(species.resourceKey)_\(kind)"
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "PetAssets/portraits"),
           let data = try? Data(contentsOf: url) {
            return UIImage(data: data)
        }
        if let url = Bundle.main.url(forResource: "\(species.resourceKey)_base", withExtension: "png", subdirectory: "PetAssets/portraits"),
           let data = try? Data(contentsOf: url) {
            return UIImage(data: data)
        }
        return nil
    }
}

public struct PetWorldView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.sumPalette) private var palette

    @State private var showAdoptionSheet = false
    @State private var showWorkshopSheet = false
    @State private var showCompanionDrawer = false
    @State private var releaseConfirmTarget: PetProfile? = nil
    @State private var budgetAmountText = "120"
    @State private var petBudgetMode: PetBudgetMode = .daily
    @State private var showBudgetConfig = false

    public init(viewModel: AppViewModel) { self.viewModel = viewModel }

    public var body: some View {
        let petState = viewModel.snapshot.petState
        let selectedPet = petState.profiles.first(where: { $0.id == viewModel.selectedPetId })
            ?? viewModel.activePets.first
            ?? petState.profiles.first

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerRow(petState: petState)

                if let pet = selectedPet {
                    petHabitatCard(pet: pet, petState: petState)
                    petStatsAndActionsCard(pet: pet, petState: petState)
                } else {
                    emptyAdoptionCard(petState: petState)
                }

                companionRosterSection(petState: petState)
            }
            .padding(18)
        }
        .sheet(isPresented: $showAdoptionSheet) {
            PetAdoptionSheet(viewModel: viewModel)
                .environment(\.sumPalette, palette)
        }
        .sheet(isPresented: $showWorkshopSheet) {
            CustomPetWorkshopSheet(viewModel: viewModel)
                .environment(\.sumPalette, palette)
        }
        .sheet(isPresented: $showBudgetConfig) {
            NavigationStack {
                Form {
                    Picker("结算模式", selection: $petBudgetMode) {
                        Text("每日预算").tag(PetBudgetMode.daily)
                        Text("每月预算").tag(PetBudgetMode.monthly)
                    }
                    TextField("预算基准金额（元）", text: $budgetAmountText)
                        .keyboardType(.decimalPad)
                }
                .navigationTitle("伙伴能量预算设置")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { showBudgetConfig = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            guard let cents = MoneyFormatter.parseToCents(budgetAmountText), cents > 0 else { return }
                            Task {
                                var ps = viewModel.snapshot.petState
                                ps.settings.isEnabled = true
                                ps.settings.budgetMode = petBudgetMode
                                ps.settings.budgetAmountCents = cents
                                try? await viewModel.store.savePetState(ps)
                                showBudgetConfig = false
                                await viewModel.reloadAll()
                            }
                        }
                    }
                }
            }
        }
        .alert("确认永久放生至纪念档案？", isPresented: Binding(get: { releaseConfirmTarget != nil }, set: { if !$0 { releaseConfirmTarget = nil } })) {
            Button("取消", role: .cancel) { releaseConfirmTarget = nil }
            Button("放生纪念", role: .destructive) {
                if let target = releaseConfirmTarget {
                    viewModel.selectedPetId = target.id
                    releaseConfirmTarget = nil
                    Task { await viewModel.releaseSelectedPet() }
                }
            }
        } message: {
            Text("放生后伙伴将进入永久纪念档案，空出当前领养栏位，历史档案与回忆永远保留。")
        }
    }

    @ViewBuilder
    private func headerRow(petState: PetStateBundle) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("PIXEL HABITAT · 昼夜生态")
                    .font(SumFont.mono(11, weight: .semibold))
                    .foregroundStyle(palette.accent)
                Text("拾念像素伙伴")
                    .font(SumFont.heading(26, hermes: palette.isHermes))
                    .foregroundStyle(palette.textPrimary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button {
                    budgetAmountText = MoneyFormatter.formatPlainDecimal(cents: petState.settings.budgetAmountCents)
                    petBudgetMode = petState.settings.budgetMode
                    showBudgetConfig = true
                } label: {
                    Label("\(petState.wallet.availableEnergy) ⚡", systemImage: "bolt.fill")
                }
                .pickbankGlassButton(prominent: true, tint: palette.accent)

                Button { showWorkshopSheet = true } label: {
                    Image(systemName: "wand.and.rays")
                }
                .pickbankGlassButton()
            }
        }
    }

    @ViewBuilder
    private func petHabitatCard(pet: PetProfile, petState: PetStateBundle) -> some View {
        let isReleased = petState.releasedRecords.contains(where: { $0.petId == pet.id })
        let timeline = petState.timelines.first(where: { $0.petId == pet.id })
        let todayKey = PickBankClock.dateKey()
        let lifeSnap = timeline.map {
            if let rel = petState.releasedRecords.first(where: { $0.petId == pet.id }) {
                return PetLifecycleEngine.evaluateAt(timeline: $0, dateKey: rel.releaseDateKey)
            }
            return PetLifecycleEngine.evaluate(timeline: $0, todayKey: todayKey)
        }
        let hour = Calendar.current.component(.hour, from: Date())
        let realPeriod = CircadianPhase.from(hour: hour).visualPeriod
        let effectivePeriod = viewModel.petVisualOverride ?? realPeriod

        SumCard(cornerRadius: 24, highlightAccent: true) {
            VStack(spacing: 0) {
                // Full-width Habitat Canvas with homologous DAY/NIGHT room + crisp pixel actor
                ZStack(alignment: .topLeading) {
                    if let sp = pet.builtInSpecies {
                        BuiltInHabitatStageView(
                            species: sp,
                            period: effectivePeriod,
                            isDeceasedOrReleased: isReleased || lifeSnap?.vitalState == .deceased,
                            manifestEntry: viewModel.petManifest?.species[sp.resourceKey],
                            burstToken: viewModel.petHeartBurstToken
                        ) {
                            Task { await viewModel.interactSelectedPet() }
                        }
                    } else if let customId = pet.customDefinitionId,
                              let def = petState.customPets.first(where: { $0.id == customId }) {
                        CustomHabitatStageView(
                            definition: def,
                            customPetsDir: viewModel.store.customPetsDirectory,
                            isMemorial: isReleased || lifeSnap?.vitalState == .deceased
                        ) {
                            Task { await viewModel.interactSelectedPet() }
                        }
                    }

                    // Top floating Glass HUD inside habitat
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(pet.name)
                                    .font(SumFont.heading(18, hermes: palette.isHermes))
                                    .foregroundStyle(.white)
                                if let stage = lifeSnap?.stage {
                                    Text(isReleased ? "放生纪念" : (lifeSnap?.vitalState == .deceased ? "纪念档案" : stage.zhLabel))
                                        .font(SumFont.mono(10, weight: .bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(Color.black.opacity(0.55)))
                                        .foregroundStyle(palette.accent)
                                }
                            }
                            if let days = lifeSnap?.ageDays {
                                Text("陪伴第 \(days) 天 · \(effectivePeriod == .day ? "白昼" : "夜色")")
                                    .font(SumFont.mono(11))
                                    .foregroundStyle(Color.white.opacity(0.85))
                            }
                        }
                        Spacer()
                        Menu {
                            Button("跟随真实昼夜") { viewModel.petVisualOverride = nil }
                            Button("预览白昼场景") { viewModel.petVisualOverride = .day }
                            Button("预览夜晚场景") { viewModel.petVisualOverride = .night }
                        } label: {
                            Image(systemName: effectivePeriod == .day ? "sun.max.fill" : "moon.stars.fill")
                                .foregroundStyle(.white)
                                .padding(9)
                                .background(Circle().fill(Color.black.opacity(0.45)))
                        }
                    }
                    .padding(14)
                }
                .frame(height: 360)
                .clipped()
            }
        }
    }

    @ViewBuilder
    private func petStatsAndActionsCard(pet: PetProfile, petState: PetStateBundle) -> some View {
        let isReleased = petState.releasedRecords.contains(where: { $0.petId == pet.id })
        let tl = petState.timelines.first(where: { $0.petId == pet.id })
        let todayKey = PickBankClock.dateKey()
        let snap = tl.map { PetLifecycleEngine.evaluate(timeline: $0, todayKey: todayKey) }
        let blockReason = PetAdoptionPolicy.releaseBlockReason(
            profile: pet,
            timeline: tl,
            snapshot: snap,
            isReleased: isReleased,
            todayKey: todayKey
        )

        SumCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    statGauge(label: "饱腹", value: pet.satiety, maxVal: 100, color: palette.income)
                    statGauge(label: "好感", value: pet.affection, maxVal: 100, color: palette.expense)
                    statGauge(label: "成长值", value: pet.growth, maxVal: 200, color: palette.accent)
                }

                if !isReleased && snap?.vitalState != .deceased {
                    HStack(spacing: 10) {
                        Button {
                            Task { await viewModel.feedSelectedPet(energy: 15) }
                        } label: {
                            Label("投喂 (15⚡)", systemImage: "leaf.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .pickbankGlassButton(prominent: true, tint: palette.accent)

                        Button {
                            Task { await viewModel.interactSelectedPet() }
                        } label: {
                            Label("轻抚互动", systemImage: "heart.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .pickbankGlassButton()

                        Button {
                            if blockReason == nil {
                                releaseConfirmTarget = pet
                            } else if let blockReason {
                                viewModel.showToast(message: blockReason)
                            }
                        } label: {
                            Image(systemName: "bird.fill")
                        }
                        .pickbankGlassButton()
                    }
                } else {
                    Text(isReleased ? "已放生进入永久纪念档案，可随时回望陪伴点滴。" : "伙伴已进入永久纪念档案。")
                        .font(SumFont.body(13))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(16)
        }
    }

    private func statGauge(label: String, value: Int, maxVal: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(SumFont.body(11)).foregroundStyle(palette.textSecondary)
                Spacer()
                Text("\(value)").font(SumFont.mono(12, weight: .bold)).foregroundStyle(color)
            }
            ProgressView(value: min(1.0, Double(value) / Double(maxVal)))
                .tint(color)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func emptyAdoptionCard(petState: PetStateBundle) -> some View {
        SumCard(highlightAccent: true) {
            VStack(spacing: 14) {
                Text("领养你的第一只记账像素伙伴")
                    .font(SumFont.heading(20, hermes: palette.isHermes))
                    .foregroundStyle(palette.textPrimary)
                Text("每日守住预算即可把结余化作喂养能量，8 种像素生灵陪你经历幼崽到长大的真实日历旅程，也可在工坊导入你自己的像素/视频伙伴。")
                    .font(SumFont.body(13))
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button("前往领养") { showAdoptionSheet = true }
                        .pickbankGlassButton(prominent: true, tint: palette.accent)
                    Button("自定义工坊") { showWorkshopSheet = true }
                        .pickbankGlassButton()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }

    @ViewBuilder
    private func companionRosterSection(petState: PetStateBundle) -> some View {
        let activeCount = viewModel.activePets.count
        let unlocked = petState.slotState.unlockedSlots
        let canAdopt = activeCount < unlocked

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("伙伴档案与栏位（在养 \(activeCount) / \(unlocked) · 共 \(petState.profiles.count) 只）")
                    .font(SumFont.mono(11, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                if canAdopt {
                    Button("+ 领养新伙伴") { showAdoptionSheet = true }
                        .font(SumFont.body(13, weight: .bold))
                        .foregroundStyle(palette.accent)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(petState.profiles) { pet in
                        let sel = (viewModel.selectedPetId == pet.id)
                        let released = petState.releasedRecords.contains(where: { $0.petId == pet.id })
                        Button {
                            viewModel.selectedPetId = pet.id
                            Haptics.light()
                        } label: {
                            VStack(spacing: 6) {
                                if let sp = pet.builtInSpecies,
                                   let img = PetBundleImageLoader.portrait(species: sp) {
                                    Image(uiImage: img)
                                        .interpolation(.none)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 56, height: 56)
                                } else {
                                    Image(systemName: "sparkles.square.filled.on.square")
                                        .font(.title)
                                        .frame(width: 56, height: 56)
                                        .foregroundStyle(palette.accent)
                                }
                                Text(pet.name)
                                    .font(SumFont.body(13, weight: .semibold))
                                    .foregroundStyle(palette.textPrimary)
                                Text(released ? "纪念" : "饱腹 \(pet.satiety)%")
                                    .font(SumFont.mono(10))
                                    .foregroundStyle(released ? palette.transfer : palette.textSecondary)
                            }
                            .padding(12)
                            .background {
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(sel ? palette.surfaceElevated : palette.surface)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 18)
                                            .strokeBorder(sel ? palette.accent : palette.glassBorder, lineWidth: sel ? 1.5 : 0.7)
                                    }
                            }
                        }
                        .buttonStyle(SpringPressStyle())
                    }
                }
            }
        }
    }
}

private struct BuiltInHabitatStageView: View {
    let species: PetSpecies
    let period: HabitatVisualPeriod
    let isDeceasedOrReleased: Bool
    let manifestEntry: PetSpeciesManifestEntry?
    let burstToken: Int
    let onTapActor: () -> Void

    @State private var selectedSlotIdx = 0
    @State private var frameTick = 0
    @State private var showHeart = false

    var body: some View {
        GeometryReader { geo in
            let slots = manifestEntry?.slots ?? []
            let slot = slots.isEmpty ? nil : slots[selectedSlotIdx % slots.count]
            let frameName = slot?.frames[frameTick % max(1, slot?.frames.count ?? 1)]

            ZStack {
                if let roomImg = PetBundleImageLoader.roomImage(species: species, period: period) {
                    Image(uiImage: roomImg)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Color.black
                }

                if !isDeceasedOrReleased {
                    let anchorX = slot?.anchor.first ?? 0.5
                    let anchorY = (slot?.anchor.count ?? 0) > 1 ? (slot?.anchor[1] ?? 0.65) : 0.65
                    let sizeFrac = slot?.size ?? 0.25
                    let actorDim = max(geo.size.width, geo.size.height) * CGFloat(sizeFrac)

                    Group {
                        if let frameName, let img = PetBundleImageLoader.actorFrame(fileName: frameName) {
                            Image(uiImage: img)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                        } else if let portrait = PetBundleImageLoader.portrait(species: species) {
                            Image(uiImage: portrait)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                        }
                    }
                    .frame(width: actorDim, height: actorDim)
                    .position(x: geo.size.width * CGFloat(anchorX), y: geo.size.height * CGFloat(anchorY))
                    .onTapGesture {
                        onTapActor()
                        if slots.count > 1 { selectedSlotIdx = (selectedSlotIdx + 1) % slots.count }
                    }

                    if showHeart {
                        Image(systemName: "heart.fill")
                            .font(.title2)
                            .foregroundStyle(Color(hex: 0xFF8A9A))
                            .position(x: geo.size.width * CGFloat(anchorX), y: geo.size.height * CGFloat(anchorY) - actorDim * 0.48)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
        .task(id: species.rawValue) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(320))
                frameTick &+= 1
            }
        }
        .onChange(of: burstToken) { _, _ in
            withAnimation(.spring()) { showHeart = true }
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                withAnimation { showHeart = false }
            }
        }
    }
}

private struct CustomHabitatStageView: View {
    let definition: CustomPetDefinition
    let customPetsDir: URL
    let isMemorial: Bool
    let onTap: () -> Void

    @State private var activeActionIdx = 0
    @State private var frameIdx = 0

    var body: some View {
        let defDir = customPetsDir.appendingPathComponent(definition.id, isDirectory: true)
        let action = definition.actions.isEmpty ? nil : definition.actions[activeActionIdx % definition.actions.count]

        ZStack {
            if let bg = definition.sceneImageFileName,
               let data = try? Data(contentsOf: defDir.appendingPathComponent(bg)),
               let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Color.black
            }

            if !isMemorial, let action {
                if let videoName = action.videoFileName {
                    let videoURL = defDir.appendingPathComponent(videoName)
                    VideoPlayer(player: AVPlayer(url: videoURL))
                        .frame(width: 240, height: 240)
                } else if !action.frameFileNames.isEmpty {
                    let fname = action.frameFileNames[frameIdx % action.frameFileNames.count]
                    if let data = try? Data(contentsOf: defDir.appendingPathComponent(fname)),
                       let img = UIImage(data: data) {
                        Image(uiImage: img)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 220 * CGFloat(definition.scalePercent) / 40.0)
                            .onTapGesture {
                                onTap()
                                activeActionIdx = (activeActionIdx + 1) % max(1, definition.actions.count)
                            }
                    }
                }
            }
        }
        .task(id: "\(definition.id)-\(activeActionIdx)") {
            let fps = max(1, action?.fps ?? 6)
            let ns = UInt64(1_000_000_000 / fps)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: ns)
                frameIdx &+= 1
            }
        }
    }
}

private struct PetAdoptionSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.sumPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSpecies: PetSpecies = .cat
    @State private var petName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("选择内置像素伙伴（8 物种全包含）")
                        .font(SumFont.mono(12, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
                        ForEach(PetSpecies.allCases, id: \.self) { sp in
                            let sel = (selectedSpecies == sp)
                            Button {
                                selectedSpecies = sp
                                if petName.isEmpty { petName = sp.zhName }
                            } label: {
                                VStack(spacing: 6) {
                                    if let img = PetBundleImageLoader.portrait(species: sp) {
                                        Image(uiImage: img)
                                            .interpolation(.none)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 52, height: 52)
                                    }
                                    Text(sp.zhName)
                                        .font(SumFont.body(13, weight: .semibold))
                                        .foregroundStyle(sel ? palette.ink : palette.textPrimary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 16).fill(sel ? palette.accent : palette.surface))
                            }
                        }
                    }

                    TextField("为它起个名字（1–20 字符）", text: $petName)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(palette.surface))
                        .foregroundStyle(palette.textPrimary)

                    Button {
                        let name = petName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selectedSpecies.zhName : petName
                        Task {
                            await viewModel.adoptBuiltInPet(species: selectedSpecies, name: name)
                            dismiss()
                        }
                    } label: {
                        Text("确认领养")
                            .frame(maxWidth: .infinity)
                    }
                    .pickbankGlassButton(prominent: true, tint: palette.accent)
                }
                .padding(18)
            }
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("领养新伙伴")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }
}

private struct CustomPetWorkshopSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var scalePercent = 40.0
    @State private var selectedFrames: [PhotosPickerItem] = []
    @State private var selectedScene: PhotosPickerItem? = nil
    @State private var fps = 6
    @State private var statusText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("自定义像素/图片伙伴信息") {
                    TextField("伙伴名称（如：小星）", text: $name)
                    VStack(alignment: .leading) {
                        Text("画面比例：\(Int(scalePercent))%")
                        Slider(value: $scalePercent, in: 20...80, step: 2)
                    }
                    Stepper("动作帧率：\(fps) FPS", value: $fps, in: 1...30)
                }
                Section("导入素材（保存到本机私有目录）") {
                    PhotosPicker("选择动作帧图片（1–60 张）", selection: $selectedFrames, maxSelectionCount: 60, matching: .images)
                    PhotosPicker("可选：选择背景场景图片", selection: $selectedScene, matching: .images)
                    if !selectedFrames.isEmpty {
                        Text("已选 \(selectedFrames.count) 帧图片").font(.caption).foregroundStyle(.green)
                    }
                }
                if !statusText.isEmpty {
                    Text(statusText).font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button("保存并领养自定义伙伴") {
                        Task { await createAndAdoptCustomPet() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedFrames.isEmpty)
                }
            }
            .navigationTitle("自定义伙伴工坊")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
        }
    }

    private func createAndAdoptCustomPet() async {
        let defId = UUID().uuidString.prefix(8).lowercased()
        let defDir = viewModel.store.customPetsDirectory.appendingPathComponent(defId, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: defDir, withIntermediateDirectories: true)
            var frameFiles: [String] = []
            for (idx, item) in selectedFrames.enumerated() {
                if let data = try await item.loadTransferable(type: Data.self) {
                    let fname = String(format: "frame_%02d.png", idx)
                    try data.write(to: defDir.appendingPathComponent(fname))
                    frameFiles.append(fname)
                }
            }
            var sceneName: String? = nil
            if let sceneItem = selectedScene, let data = try await sceneItem.loadTransferable(type: Data.self) {
                sceneName = "scene.png"
                try data.write(to: defDir.appendingPathComponent("scene.png"))
            }
            let def = CustomPetDefinition(
                id: defId,
                name: name,
                scalePercent: Int(scalePercent),
                sceneImageFileName: sceneName,
                actions: [CustomPetActionDefinition(label: "日常动作", fps: fps, frameFileNames: frameFiles)]
            )
            var ps = try await viewModel.store.loadPetState()
            ps.customPets.append(def)
            try await viewModel.store.savePetState(ps)
            _ = try await viewModel.store.adoptPet(species: PetSpecies.customSpeciesString(definitionId: defId), name: name)
            await viewModel.reloadAll()
            dismiss()
        } catch {
            statusText = "创建失败：\(error.localizedDescription)"
        }
    }
}
