import PickBankCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct AdaptiveRootShell: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Namespace private var glassNavNamespace
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

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

            // Cross-screen pixel companion encounter overlay
            if let encounterPet = viewModel.activeEncounterPet, viewModel.selectedTab != .pet {
                PetEncounterBanner(pet: encounterPet) {
                    Task { await viewModel.interactSelectedPet() }
                    withAnimation(MotionTokens.springInteractive) {
                        viewModel.activeEncounterPet = nil
                    }
                } onVisit: {
                    viewModel.selectedPetId = encounterPet.id
                    viewModel.selectedTab = .pet
                    viewModel.activeEncounterPet = nil
                } onDismiss: {
                    withAnimation { viewModel.activeEncounterPet = nil }
                }
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
                    .padding(.bottom, sizeClass == .regular ? 24 : 92)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(MotionTokens.springInteractive, value: viewModel.toast?.id)
            }
        }
        .environment(\.sumPalette, palette)
        .preferredColorScheme(.dark)
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
    }

    @ViewBuilder
    private func iPhoneFloatingTabLayout(palette: SumPalette) -> some View {
        ZStack(alignment: .bottom) {
            destinationView(viewModel.selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 82)
                }

            // Floating Liquid Glass Capsule Bar
            PickBankGlassContainer(spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(RootDestination.allCases) { tab in
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
        }
    }

    @ViewBuilder
    private func iPadSplitLayout(palette: SumPalette) -> some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List {
                Section {
                    ForEach(RootDestination.allCases) { tab in
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
                        .hoverEffect(.lift)
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

private struct PetEncounterBanner: View {
    @Environment(\.sumPalette) private var palette
    let pet: PetProfile
    let onPet: () -> Void
    let onVisit: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                if let species = pet.builtInSpecies,
                   let img = PetBundleImageLoader.portrait(species: species, kind: "base") {
                    Image(uiImage: img)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 42, height: 42)
                } else {
                    Image(systemName: "pawprint.fill")
                        .font(.title2)
                        .foregroundStyle(palette.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(pet.name) 路过打招呼")
                        .font(SumFont.body(13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("好感 \(pet.affection) · 饱腹 \(pet.satiety)%")
                        .font(SumFont.mono(11))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Button("摸摸", action: onPet)
                    .pickbankGlassButton(prominent: true, tint: palette.accent)
                Button("家园", action: onVisit)
                    .pickbankGlassButton(prominent: false)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .pickbankLiquidGlass(in: RoundedRectangle(cornerRadius: 22), tint: palette.surfaceElevated)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

#if canImport(UIKit)
public struct ShareSheetBridge: UIViewControllerRepresentable {
    let items: [Any]
    public init(items: [Any]) { self.items = items }
    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
public struct ShareSheetBridge: View {
    let items: [Any]
    public init(items: [Any]) { self.items = items }
    public var body: some View { EmptyView() }
}
#endif
