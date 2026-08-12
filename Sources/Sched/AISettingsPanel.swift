import AppKit

@MainActor
final class AISettingsPanelController: NSViewController, NSTextFieldDelegate {
    private let providerPopup = NSPopUpButton()
    private let keyField = NSSecureTextField()
    private let endpointField = NSTextField()
    private let modelField = NSTextField()
    private let packetRequestField = SchedGlassTextView(placeholder: "What do you need help with?", height: 92)
    private let presetPopup = NSPopUpButton()
    private let includeRemindersCheck = NSButton(checkboxWithTitle: "Reminders", target: nil, action: nil)
    private let includeTimersCheck = NSButton(checkboxWithTitle: "Timers", target: nil, action: nil)
    private let includeLimitsCheck = NSButton(checkboxWithTitle: "App limits", target: nil, action: nil)
    private let includeWorkspaceCheck = NSButton(checkboxWithTitle: "Open apps", target: nil, action: nil)
    private let attachmentLabel = NSTextField(wrappingLabelWithString: "No files attached")
    private let resultView = SchedGlassTextView(placeholder: "The provider response appears here.", height: 112)
    private let status = NSTextField(wrappingLabelWithString: "AI is optional. Sched does not contact a model in the background.")
    private let startServerButton = SchedGhostButton("Start server", action: #selector(startServer), target: nil)
    private let stopServerButton = SchedGhostButton("Stop server", action: #selector(stopServer), target: nil)
    private let stopOnQuitCheck = NSButton(
        checkboxWithTitle: "Stop a local server that Sched started when Sched quits",
        target: nil,
        action: nil
    )

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear

        let title = NSTextField(labelWithString: "AI")
        title.font = SchedDesign.display(28)
        SchedDesign.label(title)
        let subtitle = NSTextField(wrappingLabelWithString: "A small head start: identify your provider, check a local or hosted endpoint, and make a packet you can hand to any model.")
        subtitle.font = SchedDesign.body(14)
        subtitle.maximumNumberOfLines = 2
        SchedDesign.label(subtitle, color: SchedDesign.inkMuted)

        providerPopup.addItems(withTitles: AIProvider.allCases.map(\.label))
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged)
        schedStyleSelector(providerPopup)

        configureTextField(keyField, placeholder: "Paste a key, or use an environment variable")
        configureTextField(endpointField, placeholder: "https://… or http://127.0.0.1:11434")
        configureTextField(modelField, placeholder: "Optional model name")
        endpointField.delegate = self
        modelField.delegate = self

        let detect = SchedPrimaryButton("Detect", action: #selector(detectProvider), target: self)
        let saveKey = SchedGhostButton("Save key", action: #selector(saveKey), target: self)
        let forgetKey = SchedGhostButton("Forget key", action: #selector(forgetKey), target: self)
        let test = SchedGhostButton("Test connection", action: #selector(testConnection), target: self)
        let keyButtons = NSStackView(views: [saveKey, forgetKey])
        keyButtons.orientation = .horizontal
        keyButtons.spacing = 8
        let connectionButtons = NSStackView(views: [detect, test])
        connectionButtons.orientation = .horizontal
        connectionButtons.spacing = 8

        stopOnQuitCheck.target = self
        stopOnQuitCheck.action = #selector(stopOnQuitChanged)
        stopOnQuitCheck.font = SchedDesign.body(12)
        stopOnQuitCheck.appearance = SchedDesign.windowAppearance
        startServerButton.target = self
        stopServerButton.target = self
        let serverButtons = NSStackView(views: [startServerButton, stopServerButton])
        serverButtons.orientation = .horizontal
        serverButtons.spacing = 8

        status.font = SchedDesign.body(12)
        status.maximumNumberOfLines = 3
        SchedDesign.label(status, color: SchedDesign.inkMuted)

        let connectionCard = makeCard(
            title: "Connection",
            detail: "Keys are read from standard environment variables or stored in your macOS Keychain.",
            views: [
                formRow("Provider", providerPopup),
                formRow("API key", keyField),
                trailingRow(keyButtons),
                formRow("Endpoint", endpointField),
                formRow("Model", modelField),
                trailingRow(connectionButtons),
                status,
            ]
        )

        let serverNote = NSTextField(wrappingLabelWithString: "Server controls appear for Ollama and LM Studio. There is no polling: Sched checks only when you ask it to. It will never terminate an Ollama process it did not start.")
        serverNote.font = SchedDesign.body(12)
        serverNote.maximumNumberOfLines = 3
        SchedDesign.label(serverNote, color: SchedDesign.inkMuted)
        let serverCard = makeCard(
            title: "Local server",
            detail: "Start on demand; stop when you are finished to release memory and GPU resources.",
            views: [serverNote, serverButtons, stopOnQuitCheck]
        )

        let packetNote = NSTextField(wrappingLabelWithString: "Exports README.md, request.md, and sched-context.json. API keys and Keychain data are never included.")
        packetNote.font = SchedDesign.body(12)
        packetNote.maximumNumberOfLines = 2
        SchedDesign.label(packetNote, color: SchedDesign.inkMuted)
        [includeRemindersCheck, includeTimersCheck, includeLimitsCheck, includeWorkspaceCheck].forEach {
            $0.state = .on
            $0.font = SchedDesign.body(12)
            $0.appearance = SchedDesign.windowAppearance
        }
        let contextChecks = NSStackView(views: [includeRemindersCheck, includeTimersCheck, includeLimitsCheck, includeWorkspaceCheck])
        contextChecks.orientation = .horizontal
        contextChecks.spacing = 12
        let addFiles = SchedGhostButton("Add files…", action: #selector(addFiles), target: self)
        let clearFiles = SchedGhostButton("Clear", action: #selector(clearFiles), target: self)
        let filesRow = NSStackView(views: [addFiles, clearFiles, attachmentLabel])
        filesRow.orientation = .horizontal
        filesRow.alignment = .centerY
        filesRow.spacing = 8
        attachmentLabel.font = SchedDesign.caption(11)
        attachmentLabel.lineBreakMode = .byTruncatingTail
        SchedDesign.label(attachmentLabel, color: SchedDesign.inkMuted)
        attachmentLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        resultView.textView.isEditable = false
        resultView.textView.isSelectable = true
        resultView.textView.textColor = SchedDesign.ink
        let send = SchedPrimaryButton("Send", action: #selector(sendToProvider), target: self)
        let copy = SchedGhostButton("Copy prompt", action: #selector(copyPrompt), target: self)
        let preview = SchedGhostButton("Preview", action: #selector(previewPrompt), target: self)
        let createPacket = SchedGhostButton("Export…", action: #selector(createPacket), target: self)
        let packetActions = NSStackView(views: [send, copy, preview, createPacket])
        packetActions.orientation = .horizontal
        packetActions.spacing = 8
        presetPopup.target = self
        presetPopup.action = #selector(presetChanged)
        schedStyleSelector(presetPopup)
        let savePreset = SchedGhostButton("Save packet…", action: #selector(savePreset), target: self)
        let deletePreset = SchedGhostButton("Delete", action: #selector(deletePreset), target: self)
        let presetRow = NSStackView(views: [presetPopup, savePreset, deletePreset])
        presetRow.orientation = .horizontal
        presetRow.spacing = 8
        presetPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        presetPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        let packetCard = makeCard(
            title: "Ask about this schedule",
            detail: "Save reusable packet briefs, choose their context, add supporting files, then send them to your provider or take them elsewhere.",
            views: [presetRow, packetRequestField, contextChecks, filesRow, packetActions, resultView, packetNote]
        )

        let stack = NSStackView(views: [title, subtitle, connectionCard, serverCard, packetCard])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.setCustomSpacing(4, after: title)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let document = SchedFlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        let scroll = NSScrollView()
        schedConfigureScroll(scroll)
        scroll.documentView = document
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 2),
            document.bottomAnchor.constraint(equalTo: stack.bottomAnchor, constant: 18),
            title.widthAnchor.constraint(equalTo: stack.widthAnchor),
            subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
            connectionCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            serverCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            packetCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        loadSettings()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if obj.object as? NSTextField === endpointField {
            applyEndpointDetection()
        }
        saveSettings()
    }

    private func loadSettings() {
        let settings = ScheduleStore.shared.store.aiSettings
        providerPopup.selectItem(at: AIProvider.allCases.firstIndex(of: settings.provider) ?? 0)
        endpointField.stringValue = settings.endpoint
        modelField.stringValue = settings.model
        stopOnQuitCheck.state = settings.stopOwnedServerOnQuit ? .on : .off
        refreshProviderUI()
        refreshKeyStatus()
        refreshAttachmentLabel()
        refreshPresets()
    }

    private func selectedProvider() -> AIProvider {
        AIProvider.allCases[max(0, providerPopup.indexOfSelectedItem)]
    }

    private func effectiveProvider() -> AIProvider {
        let selected = selectedProvider()
        if selected != .automatic { return selected }
        return AIProviderDetector.detect(endpoint: endpointField.stringValue, keyHint: keyField.stringValue)?.provider ?? .openAI
    }

    private func configureTextField(_ field: NSTextField, placeholder: String) {
        field.placeholderString = placeholder
        field.font = SchedDesign.body(13)
        field.textColor = SchedDesign.ink
        field.appearance = SchedDesign.windowAppearance
        field.controlSize = .large
        field.translatesAutoresizingMaskIntoConstraints = false
        field.heightAnchor.constraint(equalToConstant: 34).isActive = true
    }

    private func formRow(_ label: String, _ control: NSView) -> NSView {
        let caption = schedFieldLabel(label)
        caption.translatesAutoresizingMaskIntoConstraints = false
        caption.widthAnchor.constraint(equalToConstant: 78).isActive = true
        control.translatesAutoresizingMaskIntoConstraints = false
        let row = NSStackView(views: [caption, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        return row
    }

    private func trailingRow(_ view: NSView) -> NSView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(equalToConstant: 90).isActive = true
        let row = NSStackView(views: [spacer, view])
        row.orientation = .horizontal
        row.spacing = 0
        return row
    }

    private func makeCard(title: String, detail: String, views: [NSView]) -> NSView {
        let surface = SchedGlassSurface(cornerRadius: 18, tint: NSColor.white.withAlphaComponent(0.10))
        let heading = NSTextField(labelWithString: title)
        heading.font = SchedDesign.title(17)
        SchedDesign.label(heading)
        let subheading = NSTextField(wrappingLabelWithString: detail)
        subheading.font = SchedDesign.body(12)
        subheading.maximumNumberOfLines = 2
        SchedDesign.label(subheading, color: SchedDesign.inkMuted)
        let stack = NSStackView(views: [heading, subheading] + views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(3, after: heading)
        stack.setCustomSpacing(14, after: subheading)
        stack.translatesAutoresizingMaskIntoConstraints = false
        surface.innerContentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: surface.innerContentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: surface.innerContentView.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: surface.innerContentView.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: surface.innerContentView.bottomAnchor, constant: -16),
            heading.widthAnchor.constraint(equalTo: stack.widthAnchor),
            subheading.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        for view in views where view is NSTextField {
            view.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true
        }
        return surface
    }

    private func refreshProviderUI() {
        let provider = selectedProvider()
        let isLocal = provider.isLocal || (provider == .automatic && AIProviderDetector.provider(forEndpoint: endpointField.stringValue)?.isLocal == true)
        startServerButton.isHidden = !isLocal
        stopServerButton.isHidden = !isLocal
        stopOnQuitCheck.isHidden = !isLocal
        keyField.isEnabled = !isLocal || provider == .lmStudio
    }

    private func refreshKeyStatus(prefix: String? = nil) {
        let provider = effectiveProvider()
        if let variable = provider.environmentKeys.first(where: { !(ProcessInfo.processInfo.environment[$0] ?? "").isEmpty }) {
            status.stringValue = "Detected \(provider.label) from \(variable). The value stays in your environment."
        } else if AIKeychainStore.key(for: provider) != nil {
            status.stringValue = "A \(provider.label) key is saved in macOS Keychain."
        } else if provider.isLocal {
            status.stringValue = "\(provider.label) usually works without a key. Test the endpoint when the server is running."
        } else {
            status.stringValue = prefix ?? "No key detected for \(provider.label)."
        }
    }

    private func keyForConnection(_ provider: AIProvider) -> String? {
        let typed = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        for variable in provider.environmentKeys {
            if let value = ProcessInfo.processInfo.environment[variable], !value.isEmpty { return value }
        }
        return AIKeychainStore.key(for: provider)
    }

    private var attachments: [URL] = []

    private func packetOptions() -> AIPacketOptions {
        AIPacketOptions(
            includeReminders: includeRemindersCheck.state == .on,
            includeTimers: includeTimersCheck.state == .on,
            includeAppLimits: includeLimitsCheck.state == .on,
            includeWorkspace: includeWorkspaceCheck.state == .on
        )
    }

    private func prompt() throws -> String {
        try AIPacketBuilder.prompt(
            store: ScheduleStore.shared.store,
            request: packetRequestField.textView.string,
            options: packetOptions(),
            attachments: attachments
        )
    }

    private func refreshAttachmentLabel() {
        if attachments.isEmpty {
            attachmentLabel.stringValue = "No files attached"
        } else if attachments.count == 1 {
            attachmentLabel.stringValue = attachments[0].lastPathComponent
        } else {
            attachmentLabel.stringValue = "\(attachments.count) files attached"
        }
    }

    private func refreshPresets(select id: UUID? = nil) {
        presetPopup.removeAllItems()
        presetPopup.addItem(withTitle: "Unsaved packet")
        presetPopup.lastItem?.representedObject = nil
        for preset in ScheduleStore.shared.store.aiPacketPresets {
            presetPopup.addItem(withTitle: preset.name)
            presetPopup.lastItem?.representedObject = preset.id.uuidString
        }
        if let id,
           let index = presetPopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == id.uuidString }) {
            presetPopup.selectItem(at: index)
        } else {
            presetPopup.selectItem(at: 0)
        }
    }

    private func apply(_ preset: SchedAIPacketPreset) {
        packetRequestField.textView.string = preset.request
        includeRemindersCheck.state = preset.includeReminders ? .on : .off
        includeTimersCheck.state = preset.includeTimers ? .on : .off
        includeLimitsCheck.state = preset.includeAppLimits ? .on : .off
        includeWorkspaceCheck.state = preset.includeWorkspace ? .on : .off
        attachments.removeAll()
        refreshAttachmentLabel()
        status.stringValue = "Loaded \(preset.name). Add files only for this send."
    }

    private func saveSettings() {
        var store = ScheduleStore.shared.store
        store.aiSettings = SchedAISettings(
            provider: selectedProvider(),
            endpoint: endpointField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            model: modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            stopOwnedServerOnQuit: stopOnQuitCheck.state == .on
        )
        ScheduleStore.shared.replaceStore(store)
    }

    private func applyEndpointDetection() {
        guard let provider = AIProviderDetector.provider(forEndpoint: endpointField.stringValue) else { return }
        providerPopup.selectItem(at: AIProvider.allCases.firstIndex(of: provider) ?? 0)
        refreshProviderUI()
        status.stringValue = "Endpoint looks like \(provider.label)."
    }

    @objc private func providerChanged() {
        let provider = selectedProvider()
        let current = endpointField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty || AIProvider.allCases.contains(where: { $0.defaultEndpoint == current }) {
            endpointField.stringValue = provider.defaultEndpoint
        }
        keyField.stringValue = ""
        refreshProviderUI()
        refreshKeyStatus()
        saveSettings()
    }

    @objc private func detectProvider() {
        if let detection = AIProviderDetector.detect(endpoint: endpointField.stringValue, keyHint: keyField.stringValue) {
            providerPopup.selectItem(at: AIProvider.allCases.firstIndex(of: detection.provider) ?? 0)
            if endpointField.stringValue.isEmpty { endpointField.stringValue = detection.provider.defaultEndpoint }
            refreshProviderUI()
            status.stringValue = "Detected \(detection.provider.label) from \(detection.reason)."
            saveSettings()
            return
        }
        status.stringValue = "Checking the two common local endpoints once…"
        Task { [weak self] in
            async let ollama = AIConnectionTester.test(provider: .ollama, endpoint: AIProvider.ollama.defaultEndpoint, key: nil)
            async let studio = AIConnectionTester.test(provider: .lmStudio, endpoint: AIProvider.lmStudio.defaultEndpoint, key: nil)
            let results = await (ollama, studio)
            guard let self else { return }
            if results.0.hasPrefix("Connected") {
                self.providerPopup.selectItem(at: AIProvider.allCases.firstIndex(of: .ollama) ?? 0)
                self.endpointField.stringValue = AIProvider.ollama.defaultEndpoint
                self.status.stringValue = results.0
            } else if results.1.hasPrefix("Connected") {
                self.providerPopup.selectItem(at: AIProvider.allCases.firstIndex(of: .lmStudio) ?? 0)
                self.endpointField.stringValue = AIProvider.lmStudio.defaultEndpoint
                self.status.stringValue = results.1
            } else {
                self.status.stringValue = "No provider key or local server was detected. Choose one manually."
            }
            self.refreshProviderUI()
            self.saveSettings()
        }
    }

    @objc private func saveKey() {
        let key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            refreshKeyStatus(prefix: "Paste a key before saving.")
            return
        }
        let provider = effectiveProvider()
        guard provider != .automatic, provider != .ollama else {
            status.stringValue = "Choose the provider that issued this key."
            return
        }
        if AIKeychainStore.save(key, for: provider) {
            keyField.stringValue = ""
            status.stringValue = "Saved the \(provider.label) key in macOS Keychain."
        } else {
            status.stringValue = "macOS Keychain did not accept the key."
        }
    }

    @objc private func forgetKey() {
        let provider = effectiveProvider()
        AIKeychainStore.remove(for: provider)
        keyField.stringValue = ""
        status.stringValue = "Removed the saved \(provider.label) key from Keychain. Environment variables were not changed."
    }

    @objc private func testConnection() {
        saveSettings()
        let provider = effectiveProvider()
        let endpoint = endpointField.stringValue.isEmpty ? provider.defaultEndpoint : endpointField.stringValue
        status.stringValue = "Connecting once to \(provider.label)…"
        let key = keyForConnection(provider)
        Task { [weak self] in
            let result = await AIConnectionTester.test(provider: provider, endpoint: endpoint, key: key)
            self?.status.stringValue = result
        }
    }

    @objc private func startServer() {
        let provider = effectiveProvider()
        status.stringValue = AILocalServerController.shared.start(provider)
    }

    @objc private func stopServer() {
        let provider = effectiveProvider()
        status.stringValue = AILocalServerController.shared.stop(provider)
    }

    @objc private func stopOnQuitChanged() { saveSettings() }

    @objc private func addFiles() {
        let panel = NSOpenPanel()
        panel.title = "Add context files"
        panel.prompt = "Add"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let existing = Set(attachments.map(\.standardizedFileURL))
        attachments.append(contentsOf: panel.urls.filter { !existing.contains($0.standardizedFileURL) })
        refreshAttachmentLabel()
    }

    @objc private func clearFiles() {
        attachments.removeAll()
        refreshAttachmentLabel()
    }

    @objc private func presetChanged() {
        guard let raw = presetPopup.selectedItem?.representedObject as? String,
              let id = UUID(uuidString: raw),
              let preset = ScheduleStore.shared.store.aiPacketPresets.first(where: { $0.id == id }) else { return }
        apply(preset)
    }

    @objc private func savePreset() {
        let alert = NSAlert()
        alert.messageText = "Save Packet"
        alert.informativeText = "Name this reusable brief. Attached files remain one-time, so they are never silently resent."
        let name = NSTextField(string: "")
        name.placeholderString = "Packet name"
        name.frame = NSRect(x: 0, y: 0, width: 250, height: 24)
        alert.accessoryView = name
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let cleanName = SchedTextLimits.clean(name.stringValue, limit: 80)
        guard !cleanName.isEmpty else { NSSound.beep(); return }
        let preset = SchedAIPacketPreset(
            name: cleanName,
            request: SchedTextLimits.clean(packetRequestField.textView.string, limit: SchedTextLimits.note),
            includeReminders: includeRemindersCheck.state == .on,
            includeTimers: includeTimersCheck.state == .on,
            includeAppLimits: includeLimitsCheck.state == .on,
            includeWorkspace: includeWorkspaceCheck.state == .on
        )
        var store = ScheduleStore.shared.store
        store.aiPacketPresets.append(preset)
        ScheduleStore.shared.replaceStore(store)
        refreshPresets(select: preset.id)
        status.stringValue = "Saved \(preset.name)."
    }

    @objc private func deletePreset() {
        guard let raw = presetPopup.selectedItem?.representedObject as? String,
              let id = UUID(uuidString: raw) else { return }
        var store = ScheduleStore.shared.store
        guard let preset = store.aiPacketPresets.first(where: { $0.id == id }) else { return }
        store.aiPacketPresets.removeAll { $0.id == id }
        ScheduleStore.shared.replaceStore(store)
        refreshPresets()
        status.stringValue = "Deleted \(preset.name)."
    }

    @objc private func previewPrompt() {
        do {
            resultView.textView.string = try prompt()
            status.stringValue = "Showing the exact text that Send will provide."
        } catch {
            status.stringValue = "Could not prepare context: \(error.localizedDescription)"
        }
    }

    @objc private func copyPrompt() {
        do {
            let text = try prompt()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            status.stringValue = "Copied the request and selected context."
        } catch {
            status.stringValue = "Could not copy context: \(error.localizedDescription)"
        }
    }

    @objc private func sendToProvider() {
        saveSettings()
        let provider = effectiveProvider()
        let endpoint = endpointField.stringValue.isEmpty ? provider.defaultEndpoint : endpointField.stringValue
        let model = modelField.stringValue
        let key = keyForConnection(provider)
        do {
            let preparedPrompt = try prompt()
            status.stringValue = "Sending once to \(provider.label)…"
            resultView.textView.string = ""
            Task { [weak self] in
                do {
                    let reply = try await AIConversationClient.send(
                        provider: provider,
                        endpoint: endpoint,
                        model: model,
                        key: key,
                        prompt: preparedPrompt
                    )
                    self?.resultView.textView.string = reply
                    self?.status.stringValue = "Received a response from \(provider.label)."
                } catch {
                    self?.status.stringValue = "Could not send: \(error.localizedDescription)"
                }
            }
        } catch {
            status.stringValue = "Could not prepare context: \(error.localizedDescription)"
        }
    }

    @objc private func createPacket() {
        saveSettings()
        let panel = NSOpenPanel()
        panel.title = "Choose where to create the AI packet"
        panel.prompt = "Create Packet"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        do {
            let folder = try AIPacketBuilder.export(
                store: ScheduleStore.shared.store,
                request: packetRequestField.textView.string,
                options: packetOptions(),
                attachments: attachments,
                parent: parent
            )
            status.stringValue = "Created \(folder.lastPathComponent)."
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } catch {
            status.stringValue = "The packet could not be created: \(error.localizedDescription)"
        }
    }
}
