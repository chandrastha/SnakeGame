import SwiftUI

// MARK: - PlayAreaCustomizeView

struct PlayAreaCustomizeView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = PlayAreaLayoutStore.shared

    /// Working draft — edited live as the user drags elements.
    /// Stored separately for portrait/landscape; only the current orientation is active.
    @State private var portraitDraft:  [HUDElement: HUDElementConfig] = [:]
    @State private var landscapeDraft: [HUDElement: HUDElementConfig] = [:]

    @State private var selectedElement: HUDElement? = nil
    @State private var showSaveAlert   = false
    @State private var showLayoutMenu  = false
    @State private var newLayoutName   = ""
    @State private var screenSize: CGSize = .zero

    private var isLandscape: Bool { screenSize.width > screenSize.height }

    // Current orientation's draft
    private var currentDraft: [HUDElement: HUDElementConfig] {
        get { isLandscape ? landscapeDraft : portraitDraft }
    }

    private func setDraft(_ cfg: HUDElementConfig, for el: HUDElement) {
        if isLandscape { landscapeDraft[el] = cfg } else { portraitDraft[el] = cfg }
    }

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                gameBackground

                // Tap-outside-to-deselect (below elements)
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { selectedElement = nil }

                // HUD element replicas
                ForEach(HUDElement.allCases, id: \.self) { element in
                    let cfg = currentDraft[element]
                        ?? PlayAreaLayoutStore.defaultConfig(for: element, isLandscape: isLandscape)

                    GameElementView(
                        element:    element,
                        config:     cfg,
                        screenSize: geo.size,
                        isSelected: selectedElement == element,
                        onSelect:   { selectedElement = element },
                        onMove: { newCfg in setDraft(newCfg, for: element) }
                    )
                }

                // Top toolbar
                topBar(safeTop: geo.safeAreaInsets.top)

                // Scale bar (joystick / boost only)
                if let el = selectedElement, el.supportsScale,
                   let cfg = currentDraft[el] {
                    scaleBar(element: el, config: cfg)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, geo.safeAreaInsets.bottom + 20)
                }
            }
            .onAppear {
                screenSize = geo.size
                if portraitDraft.isEmpty { populateDrafts(from: store.activeLayout) }
            }
            .onChange(of: geo.size) { newSize in
                let wasLandscape = screenSize.width > screenSize.height
                let nowLandscape = newSize.width > newSize.height
                screenSize = newSize
                // If the orientation just changed and the new orientation's draft is empty,
                // fill it from the active layout (so it shows something sensible).
                if wasLandscape != nowLandscape {
                    let draft = nowLandscape ? landscapeDraft : portraitDraft
                    if draft.isEmpty {
                        fillDraft(for: nowLandscape, from: store.activeLayout)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .alert("Save Layout", isPresented: $showSaveAlert) {
            TextField("Layout name", text: $newLayoutName)
            Button("Save") { saveAsNew() }
            Button("Cancel", role: .cancel) { newLayoutName = "" }
        } message: {
            Text("Enter a name for this layout.")
        }
        .confirmationDialog("Switch Layout", isPresented: $showLayoutMenu, titleVisibility: .visible) {
            ForEach(store.layouts) { layout in
                Button(store.activeLayout.id == layout.id ? "✓ \(layout.name)" : layout.name) {
                    populateDrafts(from: layout)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Background

    private var gameBackground: some View {
        ZStack {
            Color(red: 0.04, green: 0.06, blue: 0.10).ignoresSafeArea()
            Canvas { ctx, size in
                let spacing: CGFloat = 60
                var path = Path()
                stride(from: CGFloat(0), through: size.width, by: spacing).forEach { x in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                stride(from: CGFloat(0), through: size.height, by: spacing).forEach { y in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                ctx.stroke(path, with: .color(.white.opacity(0.03)), lineWidth: 1)
            }.ignoresSafeArea()
        }
    }

    // MARK: Top Toolbar

    private func topBar(safeTop: CGFloat) -> some View {
        HStack(spacing: 8) {
            // Layout picker
            Button { showLayoutMenu = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                    Text(store.activeLayout.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Orientation indicator
            HStack(spacing: 4) {
                Image(systemName: isLandscape ? "rectangle.landscape.rotate" : "iphone")
                    .font(.system(size: 11))
                Text(isLandscape ? "Landscape" : "Portrait")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Color.white.opacity(0.45))

            Spacer()

            // Reset
            Button {
                if let el = selectedElement { resetElement(el) } else { resetAll() }
            } label: {
                Text(selectedElement != nil ? "Reset" : "Reset All")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Save — behaviour depends on whether active layout is Default or user-named
            Button {
                if store.activeLayout.isDefault {
                    // Prompt for a name for the new layout
                    newLayoutName = ""
                    showSaveAlert = true
                } else {
                    // Update existing layout silently and dismiss
                    saveAndDismiss()
                }
            } label: {
                Text("Save")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color(red: 0.18, green: 0.72, blue: 0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Save As (always prompts)
            Button {
                newLayoutName = store.activeLayout.isDefault ? "" : store.activeLayout.name + " Copy"
                showSaveAlert = true
            } label: {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(9)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
            }

            // Close
            Button { saveAndDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(9)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, safeTop + 6)
        .padding(.bottom, 10)
        .background(
            LinearGradient(colors: [Color.black.opacity(0.55), Color.clear],
                           startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        )
    }

    // MARK: Scale Bar

    private func scaleBar(element: HUDElement, config: HUDElementConfig) -> some View {
        HStack(spacing: 14) {
            Text(element.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(element.tileColor)

            Text("Size")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.5))

            Button { changeScale(element, delta: -0.1) } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.white.opacity(0.75))
            }

            Text("\(String(format: "%.1f", config.scale))×")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white)
                .frame(width: 38)

            Button { changeScale(element, delta: 0.1) } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.white.opacity(0.75))
            }

            Slider(
                value: Binding(
                    get: { currentDraft[element]?.scale ?? 1.0 },
                    set: { val in
                        var cfg = currentDraft[element]
                            ?? PlayAreaLayoutStore.defaultConfig(for: element, isLandscape: isLandscape)
                        cfg.scale = val
                        setDraft(cfg, for: element)
                    }
                ),
                in: 0.5...2.0, step: 0.05
            )
            .tint(element.tileColor)
            .frame(width: 110)
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 24)
    }

    // MARK: Draft Management

    private func populateDrafts(from layout: PlayAreaLayout) {
        store.setActive(layout)
        selectedElement = nil
        // Portrait
        var p: [HUDElement: HUDElementConfig] = [:]
        for el in HUDElement.allCases {
            p[el] = layout.portraitElements[el.rawValue]
                ?? PlayAreaLayoutStore.defaultConfig(for: el, isLandscape: false)
        }
        portraitDraft = p
        // Landscape
        var l: [HUDElement: HUDElementConfig] = [:]
        for el in HUDElement.allCases {
            l[el] = layout.landscapeElements[el.rawValue]
                ?? layout.portraitElements[el.rawValue]    // fall back to portrait
                ?? PlayAreaLayoutStore.defaultConfig(for: el, isLandscape: true)
        }
        landscapeDraft = l
    }

    private func fillDraft(for landscape: Bool, from layout: PlayAreaLayout) {
        var draft: [HUDElement: HUDElementConfig] = [:]
        for el in HUDElement.allCases {
            draft[el] = layout.config(for: el, isLandscape: landscape)
                ?? PlayAreaLayoutStore.defaultConfig(for: el, isLandscape: landscape)
        }
        if landscape { landscapeDraft = draft } else { portraitDraft = draft }
    }

    private func resetElement(_ element: HUDElement) {
        setDraft(PlayAreaLayoutStore.defaultConfig(for: element, isLandscape: isLandscape), for: element)
    }

    private func resetAll() {
        for el in HUDElement.allCases {
            setDraft(PlayAreaLayoutStore.defaultConfig(for: el, isLandscape: isLandscape), for: el)
        }
    }

    private func changeScale(_ element: HUDElement, delta: CGFloat) {
        var cfg = currentDraft[element]
            ?? PlayAreaLayoutStore.defaultConfig(for: element, isLandscape: isLandscape)
        cfg.scale = max(0.5, min(2.0, (cfg.scale * 10 + delta * 10).rounded() / 10))
        setDraft(cfg, for: element)
    }

    // MARK: Save / Dismiss

    /// Updates the existing active layout (or creates "Custom" if active is Default), then dismisses.
    private func saveAndDismiss() {
        var updated = store.activeLayout
        applyDraftsTo(&updated)

        if updated.isDefault {
            // Only create a new layout if something actually changed from defaults
            let hasPortraitChanges = portraitDraft.contains { el, cfg in
                cfg != PlayAreaLayoutStore.defaultConfig(for: el, isLandscape: false)
            }
            let hasLandscapeChanges = landscapeDraft.contains { el, cfg in
                cfg != PlayAreaLayoutStore.defaultConfig(for: el, isLandscape: true)
            }
            if hasPortraitChanges || hasLandscapeChanges {
                updated = PlayAreaLayout(
                    id: UUID(), name: "Custom", createdAt: Date(),
                    portraitElements: draftDict(isLandscape: false),
                    landscapeElements: draftDict(isLandscape: true)
                )
                store.save(updated)
            }
        } else {
            store.save(updated)
        }
        store.setActive(updated)
        dismiss()
    }

    /// Prompts for a name, saves as a brand-new layout, then dismisses.
    private func saveAsNew() {
        let name = newLayoutName.trimmingCharacters(in: .whitespaces)
        let layout = PlayAreaLayout(
            id:               UUID(),
            name:             name.isEmpty ? "Custom \(store.layouts.count)" : name,
            createdAt:        Date(),
            portraitElements:  draftDict(isLandscape: false),
            landscapeElements: draftDict(isLandscape: true)
        )
        store.save(layout)
        store.setActive(layout)
        newLayoutName = ""
        dismiss()
    }

    private func applyDraftsTo(_ layout: inout PlayAreaLayout) {
        layout.portraitElements  = draftDict(isLandscape: false)
        layout.landscapeElements = draftDict(isLandscape: true)
    }

    /// Returns only elements that differ from defaults, keeping storage compact.
    private func draftDict(isLandscape: Bool) -> [String: HUDElementConfig] {
        let draft = isLandscape ? landscapeDraft : portraitDraft
        var dict: [String: HUDElementConfig] = [:]
        for el in HUDElement.allCases {
            guard let cfg = draft[el] else { continue }
            let def = PlayAreaLayoutStore.defaultConfig(for: el, isLandscape: isLandscape)
            if cfg != def { dict[el.rawValue] = cfg }
        }
        return dict
    }
}

// MARK: - GameElementView

private struct GameElementView: View {
    let element:    HUDElement
    let config:     HUDElementConfig
    let screenSize: CGSize
    let isSelected: Bool
    let onSelect:   () -> Void
    let onMove:     (HUDElementConfig) -> Void

    @GestureState private var dragStart: HUDElementConfig? = nil
    @GestureState private var magStart:  CGFloat? = nil

    // normalizedX/Y → UIKit screen coords (Y flipped: 0=bottom → bottom of screen)
    private var screenX: CGFloat { config.normalizedX * screenSize.width }
    private var screenY: CGFloat { (1.0 - config.normalizedY) * screenSize.height }

    var body: some View {
        replica
            .position(x: screenX, y: screenY)
            .gesture(dragGesture)
            .gesture(element.supportsScale ? pinchGesture : nil)
            .onTapGesture { onSelect() }
    }

    // MARK: Replica

    @ViewBuilder
    private var replica: some View {
        let userScale = element.supportsScale ? config.scale : 1.0
        ZStack {
            switch element {
            case .joystick:        joystickReplica(scale: userScale)
            case .boostButton:     boostReplica(scale: userScale)
            case .score:           scoreReplica
            case .combo:           comboReplica
            case .miniLeaderboard: leaderboardReplica
            case .leaderArrow:     leaderArrowReplica
            case .minimap:         minimapReplica
            case .pauseButton:     pauseReplica
            }
        }
        .overlay(selectionBorder)
        .scaleEffect(isSelected ? 1.04 : 1.0)
        .animation(.spring(response: 0.18, dampingFraction: 0.7), value: isSelected)
    }

    // ── Joystick ─────────────────────────────────────────────────────────────
    private func joystickReplica(scale: CGFloat) -> some View {
        let r = 65.0 * scale
        return ZStack {
            Circle()
                .fill(Color(red: 0.15, green: 0.30, blue: 0.20).opacity(0.18))
                .frame(width: r * 2, height: r * 2)
            Circle()
                .stroke(Color(red: 0.30, green: 0.85, blue: 0.45).opacity(0.35), lineWidth: 2)
                .frame(width: r * 2, height: r * 2)
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 1.5)
                .frame(width: r * 1.20, height: r * 1.20)
            Circle()
                .fill(Color(red: 0.25, green: 0.80, blue: 0.40).opacity(0.38))
                .overlay(Circle().stroke(Color(red: 0.40, green: 0.95, blue: 0.55).opacity(0.75), lineWidth: 2))
                .shadow(color: Color(red: 0.25, green: 0.80, blue: 0.40).opacity(0.5), radius: 6)
                .frame(width: 56 * scale, height: 56 * scale)
        }
    }

    // ── Boost ─────────────────────────────────────────────────────────────────
    private func boostReplica(scale: CGFloat) -> some View {
        let r = 54.0 * scale
        return ZStack {
            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: r * 2, height: r * 2)
            Circle()
                .stroke(Color.white.opacity(0.40), lineWidth: 1.5)
                .frame(width: r * 2, height: r * 2)
            Text("⚡").font(.system(size: 20 * scale))
        }
    }

    // ── Score ──────────────────────────────────────────────────────────────────
    private var scoreReplica: some View {
        ZStack {
            Text("000000")
                .font(.custom("Arial-BoldMT", fixedSize: 44))
                .foregroundStyle(Color.black.opacity(0.55))
                .offset(x: 2, y: -2)
            Text("000000")
                .font(.custom("Arial-BoldMT", fixedSize: 44))
                .foregroundStyle(Color.white)
        }
    }

    // ── Combo ──────────────────────────────────────────────────────────────────
    private var comboReplica: some View {
        Text("COMBO 3× ★★★")
            .font(.custom("Arial-BoldMT", fixedSize: 14))
            .foregroundStyle(Color(red: 0.10, green: 0.05, blue: 0.00))
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(width: 190, height: 34)
            .background(Color(red: 1.0, green: 0.75, blue: 0.0).opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // ── Leaderboard ────────────────────────────────────────────────────────────
    private var leaderboardReplica: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LEADERS")
                .font(.custom("Arial-BoldMT", fixedSize: 11))
                .foregroundStyle(Color.white.opacity(0.52))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 6).padding(.bottom, 4)
            ForEach(Array(zip(["You", "Bot2", "Bot3", "Bot4"], ["142", "98", "76", "55"])), id: \.0) { name, score in
                HStack(spacing: 0) {
                    Text(name == "You" ? "1. \(name)" : "\(["2","3","4"][["Bot2","Bot3","Bot4"].firstIndex(of: name)!]). \(name)")
                        .font(.custom("Arial-BoldMT", fixedSize: 13))
                        .foregroundStyle(name == "You" ? Color(red: 1, green: 0.85, blue: 0) : Color.white.opacity(0.70))
                    Spacer()
                    Text(score)
                        .font(.custom("Arial-BoldMT", fixedSize: 13))
                        .foregroundStyle(Color.white.opacity(0.70))
                }
                .padding(.horizontal, 8).frame(height: 20)
            }
        }
        .frame(width: 184)
        .padding(.bottom, 4)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.05, green: 0.08, blue: 0.15).opacity(0.50))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(red: 0.80, green: 0.92, blue: 1.0).opacity(0.18), lineWidth: 1))
        )
    }

    // ── Leader Arrow ───────────────────────────────────────────────────────────
    private var leaderArrowReplica: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.05, green: 0.08, blue: 0.15).opacity(0.42))
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(Color(red: 0.80, green: 0.92, blue: 1.0).opacity(0.24), lineWidth: 1.2))
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.18))
                    .shadow(color: Color(red: 1.0, green: 0.82, blue: 0.18).opacity(0.6), radius: 4)
            }
            Text("Leader 142")
                .font(.custom("Arial-BoldMT", fixedSize: 10))
                .foregroundStyle(Color.white.opacity(0.82))
        }
    }

    // ── Minimap ────────────────────────────────────────────────────────────────
    private var minimapReplica: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.07, green: 0.10, blue: 0.15).opacity(0.30))
                .frame(width: 118, height: 118)
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(red: 0.80, green: 0.92, blue: 1.0).opacity(0.22), lineWidth: 1.2))
            Rectangle()
                .fill(Color(red: 0.83, green: 0.92, blue: 0.96).opacity(0.10))
                .frame(width: 118, height: 0.8)
            Rectangle()
                .fill(Color(red: 0.83, green: 0.92, blue: 0.96).opacity(0.10))
                .frame(width: 0.8, height: 118)
            Circle()
                .fill(Color(red: 1.0, green: 0.9, blue: 0.1))
                .frame(width: 7, height: 7)
        }
    }

    // ── Pause ──────────────────────────────────────────────────────────────────
    private var pauseReplica: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.60))
                .frame(width: 44, height: 44)
            Text("⏸").font(.system(size: 22))
        }
    }

    // ── Selection border ───────────────────────────────────────────────────────
    @ViewBuilder
    private var selectionBorder: some View {
        if isSelected {
            let s = element.supportsScale ? config.scale : 1.0
            switch element {
            case .joystick:
                Circle().stroke(Color.white.opacity(0.9), lineWidth: 2.5)
                    .frame(width: 130 * s + 14, height: 130 * s + 14)
            case .boostButton:
                Circle().stroke(Color.white.opacity(0.9), lineWidth: 2.5)
                    .frame(width: 108 * s + 14, height: 108 * s + 14)
            case .score:
                RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.9), lineWidth: 2.5)
                    .frame(width: 208, height: 64)
            case .combo:
                RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.9), lineWidth: 2.5)
                    .frame(width: 202, height: 46)
            case .miniLeaderboard:
                RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.9), lineWidth: 2.5)
                    .frame(width: 196, height: 106)
            case .leaderArrow:
                RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.9), lineWidth: 2.5)
                    .frame(width: 76, height: 62)
            case .minimap:
                RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.9), lineWidth: 2.5)
                    .frame(width: 130, height: 130)
            case .pauseButton:
                RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.9), lineWidth: 2.5)
                    .frame(width: 56, height: 56)
            }
        }
    }

    // MARK: Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .updating($dragStart) { _, state, _ in
                if state == nil { state = config }
            }
            .onChanged { value in
                guard let start = dragStart,
                      screenSize.width > 0, screenSize.height > 0 else { return }
                onSelect()
                var updated = start
                updated.normalizedX = max(0.02, min(0.98, start.normalizedX + value.translation.width  / screenSize.width))
                updated.normalizedY = max(0.02, min(0.98, start.normalizedY - value.translation.height / screenSize.height))
                onMove(updated)
            }
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .updating($magStart) { _, state, _ in
                if state == nil { state = config.scale }
            }
            .onChanged { value in
                guard let start = magStart else { return }
                onSelect()
                var updated = config
                updated.scale = max(0.5, min(2.0, start * value))
                onMove(updated)
            }
    }
}
