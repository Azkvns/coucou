import SwiftUI

struct PipelinesPane: View {
    @ObservedObject var pipelines: PipelineStore
    @Binding var wantsKeyboard: Bool

    @State private var expandedCards: Set<UUID> = []

    private var runner: PipelineRunner { pipelines.selectedRunner }
    private var isRunning: Bool { runner.isActive }
    private var cards: [PipelineCard] { pipelines.selected?.cards ?? [] }

    var body: some View {
        VStack(spacing: 6) {
            toolbar
            runBar
            cardList
        }
        .padding(.top, 2)
        .onChange(of: runner.activeCardID) { _, active in
            if let active { expandedCards.insert(active) }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(pipelines.pipelines) { pipeline in
                    Button {
                        pipelines.selectPipeline(pipeline.id)
                    } label: {
                        if pipelines.selected?.id == pipeline.id {
                            Label(pipeline.name, systemImage: "checkmark")
                        } else {
                            Text(pipeline.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(pipelines.selected?.name ?? localized("Pipelines"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .disabled(isRunning)

            Spacer(minLength: 0)

            Button { pipelines.addPipeline() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
            }
            .buttonStyle(.plain)
            .pointerStyle(.default)
            .disabled(isRunning)
            .help(localized("Add Pipeline"))

            Button { pipelines.deleteSelectedPipeline() } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(pipelines.canDeleteSelectedPipeline ? Theme.secondary : Theme.tertiary)
            }
            .buttonStyle(.plain)
            .pointerStyle(.default)
            .disabled(!pipelines.canDeleteSelectedPipeline)
            .help(localized("Delete Pipeline"))
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.surface)
        )
    }

    // MARK: - Run bar

    private var runBar: some View {
        HStack(spacing: 8) {
            Button { pipelines.runSelectedPipeline() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text(localized("Run Pipeline"))
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(canRunPipeline ? Color.green : Theme.tertiary)
            }
            .buttonStyle(.plain)
            .pointerStyle(.default)
            .disabled(!canRunPipeline)

            Button { pipelines.stopSelected() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text(localized("Stop"))
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(isRunning ? Color.red.opacity(0.85) : Theme.tertiary)
            }
            .buttonStyle(.plain)
            .pointerStyle(.default)
            .disabled(!isRunning)

            Spacer(minLength: 0)

            Button { pipelines.addCard() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                    Text(localized("Add Step"))
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(isRunning ? Theme.tertiary : Theme.secondary)
            }
            .buttonStyle(.plain)
            .pointerStyle(.default)
            .disabled(isRunning)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.surface)
        )
    }

    private var canRunPipeline: Bool {
        !isRunning && cards.contains {
            !$0.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    // MARK: - Cards

    @ViewBuilder
    private var cardList: some View {
        if cards.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Theme.tertiary)
                Text(localized("Nothing here yet — add a step"))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 3) {
                        ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                            PipelineCardRow(
                                card: card,
                                index: index,
                                pipelines: pipelines,
                                runner: runner,
                                isExpanded: expandedCards.contains(card.id),
                                wantsKeyboard: $wantsKeyboard,
                                onToggleExpand: { toggleExpand(card.id) },
                                onScrollTo: { proxy.scrollTo(card.id, anchor: .bottom) }
                            )
                            .id(card.id)
                        }
                    }
                    .padding(.bottom, 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func toggleExpand(_ id: UUID) {
        if expandedCards.contains(id) {
            expandedCards.remove(id)
        } else {
            expandedCards.insert(id)
        }
    }
}

// MARK: - Card row

private struct PipelineCardRow: View {
    let card: PipelineCard
    let index: Int
    @ObservedObject var pipelines: PipelineStore
    @ObservedObject var runner: PipelineRunner
    let isExpanded: Bool
    @Binding var wantsKeyboard: Bool
    let onToggleExpand: () -> Void
    let onScrollTo: () -> Void

    @State private var name: String = ""
    @State private var command: String = ""
    @FocusState private var focused: Field?

    private enum Field { case name, command }

    private var output: PipelineOutput { runner.outputs[card.id] ?? PipelineOutput() }
    private var isRunning: Bool { runner.isActive }
    private var isActiveStep: Bool { runner.activeCardID == card.id }
    private var awaitingDecision: Bool {
        if case .awaitingDecision(let stepIndex, _) = runner.phase {
            return stepIndex == index
        }
        return false
    }

    private var canRunCard: Bool {
        !isRunning && !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isRunning ? Theme.tertiary : Theme.secondary)
                    .frame(width: 12)

                TextField(localized("Name"), text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .tint(Theme.secondary)
                    .frame(width: 72)
                    .disabled(isRunning)
                    .focused($focused, equals: .name)
                    .onChange(of: name) { _, value in
                        pipelines.updateCard(card.id, name: value, command: command)
                    }

                TextField(localized("Command"), text: $command)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white)
                    .tint(Theme.secondary)
                    .disabled(isRunning)
                    .focused($focused, equals: .command)
                    .onChange(of: command) { _, value in
                        pipelines.updateCard(card.id, name: name, command: value)
                    }

                statusIcon

                Button { pipelines.runCard(card.id) } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(canRunCard ? Color.green : Theme.tertiary)
                }
                .buttonStyle(.plain)
                .pointerStyle(.default)
                .disabled(!canRunCard)

                Button { onToggleExpand() } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)
                .pointerStyle(.default)

                Button { pipelines.deleteCard(card.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isRunning ? Theme.tertiary : Theme.secondary)
                }
                .buttonStyle(.plain)
                .pointerStyle(.default)
                .disabled(isRunning)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isActiveStep ? Theme.surfaceHover : Theme.surface)
            )

            if awaitingDecision {
                errorBanner
            }

            if isExpanded, hasOutput {
                outputView
            }
        }
        .onAppear {
            name = card.name
            command = card.command
        }
        .onChange(of: card.name) { _, value in
            if name != value { name = value }
        }
        .onChange(of: card.command) { _, value in
            if command != value { command = value }
        }
        .onChange(of: focused) { _, field in
            if field != nil { wantsKeyboard = true }
        }
        .dropDestination(for: String.self) { items, _ in
            guard !isRunning,
                  let dropped = items.first,
                  let uuid = UUID(uuidString: dropped),
                  uuid != card.id else { return false }
            pipelines.moveCard(uuid, to: index)
            return true
        }
        .draggable(card.id.uuidString)
        .onChange(of: output.stdout) { _, _ in scrollIfActive() }
        .onChange(of: output.stderr) { _, _ in scrollIfActive() }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if output.isRunning || isActiveStep {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 12, height: 12)
        } else if let code = output.exitCode {
            Image(systemName: code == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(code == 0 ? Color.green : Color.red.opacity(0.85))
                .frame(width: 12)
        } else {
            Color.clear.frame(width: 12, height: 12)
        }
    }

    private var errorBanner: some View {
        HStack(spacing: 8) {
            Text(localized("Step failed (exit %d)", Int(output.exitCode ?? 1)))
                .font(.system(size: 10))
                .foregroundStyle(Color.red.opacity(0.85))
                .lineLimit(1)
            Spacer(minLength: 0)
            Button { pipelines.continueAfterError() } label: {
                Text(localized("Continue"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .pointerStyle(.default)
            Button { pipelines.abortAfterError() } label: {
                Text(localized("Stop"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.85))
            }
            .buttonStyle(.plain)
            .pointerStyle(.default)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.red.opacity(0.12))
        )
    }

    private var hasOutput: Bool {
        !output.stdout.isEmpty || !output.stderr.isEmpty || output.isRunning
    }

    private var outputView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                if !output.stdout.isEmpty {
                    Text(output.stdout)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !output.stderr.isEmpty {
                    Text(output.stderr)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color.red.opacity(0.85))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(6)
        }
        .frame(maxHeight: 72)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.35))
        )
    }

    private func scrollIfActive() {
        guard isActiveStep, isExpanded else { return }
        onScrollTo()
    }
}

// MARK: - Header counter

struct PipelinesCounter: View {
    @ObservedObject var pipelines: PipelineStore

    var body: some View {
        if pipelines.activeRunCount > 0 {
            Text(localized("Running"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.green.opacity(0.85))
        } else if let count = pipelines.selected?.cards.count, count > 0 {
            Text("\(count)")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.tertiary)
        }
    }
}
