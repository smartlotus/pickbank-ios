import PickBankCore
import SwiftUI

public struct AdaptiveRootShell: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Namespace private var glassNavNamespace
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var rippleRadiusScale: CGFloat = 0
    @State private var showThemeRipple = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let palette = viewModel.palette

        ZStack {
            palette.background.ignoresSafeArea()
            SumAmbientField(palette: palette)

            Group {
                if sizeClass == .regular {
                    iPadSplitLayout(palette: palette)
                } else {
                    iPhoneFloatingTabLayout(palette: palette)
                }
            }

            // Cross-screen pixel companion living encounter overlay (288-frame sprites matching Android PetEncounterHost)
            if let encounter = viewModel.activeLivingEncounter,
               let leadPet = viewModel.snapshot.petState.profiles.first(where: { $0.id == encounter.petId }),
               viewModel.selectedTab != .pet {
                let comp = encounter.companionPetId.flatMap { cid in
                    viewModel.snapshot.petState.profiles.first(where: { $0.id == cid })
                }
                PetEncounterOverlayView(
                    event: encounter,
                    leadPet: leadPet,
                    companionPet: comp,
                    onTapPet: { pid in Task { await viewModel.interactPet(id: pid) } },
                    onOpenHabitat: {
                        viewModel.selectedPetId = leadPet.id
                        viewModel.selectedTab = .pet
                        viewModel.activeLivingEncounter = nil
                    },
                    onComplete: {
                        withAnimation(.easeOut(duration: 0.25)) {
                            viewModel.activeLivingEncounter = nil
                        }
                    }
                )
            }

            // Circular Ink Reveal Ripple matching Android HermesThemeEffects
            if showThemeRipple {
                GeometryReader { geo in
                    let maxDim = max(geo.size.width, geo.size.height) * 2.4
                    Circle()
                        .fill(palette.accent.opacity(0.22))
                        .frame(width: maxDim * rippleRadiusScale, height: maxDim * rippleRadiusScale)
                        .position(x: geo.size.width * 0.85, y: 44)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            // Undo / Status Floating Glass Toast
            if let toast = viewModel.toast {
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        Text(toast.message)
                            .font(SumFont.body(13, weight: .medium))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(2)
                        if let tx = toast.deletedTransaction {
                            Button(viewModel.language == .zhHans ? "撤销" : "Undo") {
                                Task { await viewModel.undoDelete(tx) }
                            }
                            .font(SumFont.body(13, weight: .bold))
                            .foregroundStyle(palette.accent)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .pickbankLiquidGlass(in: Capsule(), tint: palette.surfaceElevated)
                    .padding(.bottom, sizeClass == .regular ? 24 : (viewModel.isPetHabitatImmersiveHidden ? 24 : 92))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(MotionTokens.springInteractive, value: viewModel.toast?.id)
            }
        }
        .environment(\.sumPalette, palette)
        .preferredColorScheme(.dark)
        .onChange(of: viewModel.themeRevealTrigger) { _, _ in
            rippleRadiusScale = 0.05
            showThemeRipple = true
            withAnimation(.easeOut(duration: 0.55)) {
                rippleRadiusScale = 1.0
            }
            Task {
                try? await Task.sleep(for: .milliseconds(560))
                showThemeRipple = false
            }
        }
        .onChange(of: viewModel.selectedTab) { _, newTab in
            if newTab != .pet {
                viewModel.isPetHabitatImmersiveHidden = false
            }
        }
        .sheet(isPresented: $viewModel.showManualSheet) {
            ManualEntrySheet(viewModel: viewModel)
                .environment(\.sumPalette, palette)
        }
        .sheet(isPresented: $viewModel.showBudgetSetup) {
            BudgetSetupSheet(viewModel: viewModel)
                .environment(\.sumPalette, palette)
        }
        .sheet(isPresented: $viewModel.showRecurringSetup) {
            RecurringRulesSheet(viewModel: viewModel)
                .environment(\.sumPalette, palette)
        }
        .sheet(item: $viewModel.exportShareItem) { item in
            ShareSheetBridge(items: [item.url])
        }
        .alert(
            viewModel.pendingMilestoneBanner?.title ?? "",
            isPresented: Binding(
                get: { viewModel.pendingMilestoneBanner != nil },
                set: { if !$0 { Task { await viewModel.acknowledgePendingMilestone() } } }
            )
        ) {
            Button("知道了") {
                Task { await viewModel.acknowledgePendingMilestone() }
            }
        } message: {
            Text(viewModel.pendingMilestoneBanner?.detail ?? "")
        }
    }

    @ViewBuilder
    private func iPhoneFloatingTabLayout(palette: SumPalette) -> some View {
        let hideBar = (viewModel.selectedTab == .pet && viewModel.isPetHabitatImmersiveHidden)
        ZStack(alignment: .bottom) {
            destinationView(viewModel.selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom) {
                    if viewModel.selectedTab != .pet {
                        Color.clear.frame(height: 82)
                    }
                }

            // Floating Liquid Glass Capsule Bar (smoothly hides during Pet Habitat immersive mode!)
            if !hideBar {
                PickBankGlassContainer(spacing: 14) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(viewModel.visibleTabs) { tab in
                                let selected = (viewModel.selectedTab == tab)
                                Button {
                                    Haptics.light()
                                    withAnimation(MotionTokens.springInteractive) {
                                        viewModel.selectedTab = tab
                                    }
                                } label: {
                                    VStack(spacing: 3) {
                                        Image(systemName: tab.sfSymbol)
                                            .font(.system(size: 16, weight: selected ? .bold : .medium))
                                            .scaleEffect(selected ? 1.08 : 1.0)
                                        Text(tab.title(language: viewModel.language))
                                            .font(.system(size: 10, weight: selected ? .semibold : .regular))
                                    }
                                    .foregroundStyle(selected ? (palette.isHermes ? palette.ink : palette.accent) : palette.textSecondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background {
                                        if selected {
                                            Capsule()
                                                .fill(palette.isHermes ? palette.accent : palette.accent.opacity(0.18))
                                                .pickbankGlassID("activeTabPill", in: glassNavNamespace)
                                        }
                                    }
                                }
                                .buttonStyle(SpringPressStyle())
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                    .pickbankLiquidGlass(in: Capsule(), tint: palette.isHermes ? palette.surface : nil)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(MotionTokens.springInteractive, value: hideBar)
    }

    @ViewBuilder
    private func iPadSplitLayout(palette: SumPalette) -> some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List {
                Section {
                    ForEach(viewModel.visibleTabs) { tab in
                        let selected = (viewModel.selectedTab == tab)
                        Button {
                            Haptics.light()
                            withAnimation(MotionTokens.springInteractive) {
                                viewModel.selectedTab = tab
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: tab.sfSymbol)
                                    .frame(width: 24)
                                    .foregroundStyle(selected ? palette.accent : palette.textSecondary)
                                Text(tab.title(language: viewModel.language))
                                    .font(SumFont.body(15, weight: selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? palette.textPrimary : palette.textSecondary)
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background {
                                if selected {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(palette.accent.opacity(0.16))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .pickbankHoverLift()
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PICKBANK")
                            .font(SumFont.mono(11, weight: .bold))
                            .foregroundStyle(palette.accent)
                        Text(viewModel.language == .zhHans ? "拾念记账 · 液态玻璃" : "PickBank Liquid Glass")
                            .font(SumFont.heading(18, hermes: palette.isHermes))
                            .foregroundStyle(palette.textPrimary)
                    }
                    .padding(.bottom, 8)
                }

                Section {
                    Button {
                        Task { await viewModel.toggleTheme() }
                    } label: {
                        Label(
                            palette.isHermes ? "切换经典暖黑" : "切换 Hermes 皇室蓝",
                            systemImage: "circle.lefthalf.filled"
                        )
                        .foregroundStyle(palette.textPrimary)
                    }
                    .listRowBackground(Color.clear)

                    Button {
                        viewModel.editingTransaction = nil
                        viewModel.showManualSheet = true
                    } label: {
                        Label(
                            viewModel.language == .zhHans ? "记一笔 (⌘N)" : "New Entry (⌘N)",
                            systemImage: "plus.circle.fill"
                        )
                        .foregroundStyle(palette.accent)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.backgroundElevated.opacity(0.9))
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            destinationView(viewModel.selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func destinationView(_ tab: RootDestination) -> some View {
        switch tab {
        case .home:
            HomeConsoleView(viewModel: viewModel)
        case .summary:
            SummaryStudioView(viewModel: viewModel)
        case .details:
            DetailsStreamView(viewModel: viewModel)
        case .ai:
            AiAdvisorView(viewModel: viewModel)
        case .categories:
            CategoryManagerView(viewModel: viewModel)
        case .pet:
            PetWorldView(viewModel: viewModel)
        case .dataCenter:
            DataSovereigntyCenterView(viewModel: viewModel)
        }
    }
}
