// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ginji001
// Mac 版の設定ウインドウ。Windows 版の設定画面・「定型文...」の画面に当たるもの。
// 入力メニューの「設定…」から開く。変えるとすぐ config.json / snippets.json に書き、入力中の欄にも読み直させる。

import Cocoa

final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate {
    static let shared = SettingsWindowController()

    private struct Toggle { let key: String; let title: String; let note: String; let defaultValue: Bool }

    /// Mac 版で効く項目だけ (Windows の Keyboard モード・トレイ専用の項目は出さない)。
    private let toggles: [Toggle] = [
        Toggle(key: "LiveConversion", title: "ライブ変換", note: "Space を押さなくても、打ったそばから漢字に変換して表示します。", defaultValue: true),
        Toggle(key: "TabConversion", title: "Tab で変換", note: "入力中に Tab を押しても変換を始めます。変換中は Tab / Shift+Tab で候補を選びます。", defaultValue: true),
        Toggle(key: "ContinueAfterConversion", title: "変換したあとに続けて打っても確定しない", note: "Space で変換したあと続けて打っても、変換した部分を確定せずに残します。", defaultValue: false),
        Toggle(key: "AutoCorrectAfterCommit", title: "確定後も文脈に合わせて直す", note: "英語とも日本語とも読める語を、次の語で判定がはっきりしたら確定し直します。", defaultValue: true),
        Toggle(key: "JapanesePunctuationAfterEnglish", title: "英字の後ろの , . も句読点にする", note: "IME. → IME。 キャレットの前が英語のときと tetr.io のような語は半角のまま。", defaultValue: false),
        Toggle(key: "SpaceAroundEnglish", title: "英単語の前後に半角スペース", note: "今日はGitHubにpush → 今日は GitHub に push", defaultValue: false),
        Toggle(key: "SigilWordsDirect", title: "/ $ @ で始まる語はそのまま入力", note: "先頭か空白の直後の /command・$skill・@ファイル名 は、空白まで変換しません。", defaultValue: true),
        Toggle(key: "TranslationCandidates", title: "英訳の候補", note: "変換の候補の後ろに英訳も出します (複雑な → complex)。", defaultValue: true),
        Toggle(key: "ShowCandidateMeanings", title: "候補の意味を表示", note: "同じ候補で少し止まると、候補の一覧に意味を出します。", defaultValue: true),
        Toggle(key: "CorrectTypos", title: "打ち間違いを直す", note: "onegaishimsu → お願いします、teh → the", defaultValue: true),
        Toggle(key: "SlashAsMiddleDot", title: "/ キーで中黒「・」", note: "かなの後ろの / を「・」にします。", defaultValue: false),
        Toggle(key: "LearningEnabled", title: "ユーザー学習を使う", note: "選んだ候補・判定を覚えて、次から先に出します。", defaultValue: true),
    ]
    private let levels: [(String, String)] = [("Aggressive", "積極的"), ("Balanced", "標準"), ("Conservative", "慎重"), ("Manual", "手動 (提案のみ)")]
    private let punctuations: [(String, String)] = [("Japanese", "、。"), ("FullWidthCommaPeriod", "，．"), ("FullWidthCommaKuten", "，。"), ("ToutenFullWidthPeriod", "、．")]

    private var checkboxes: [String: NSButton] = [:]
    private let levelPopup = NSPopUpButton()
    private let punctuationPopup = NSPopUpButton()
    private let markField = NSTextField()
    private let tabView = NSTabView()

    // 定型文
    private var snippets: [(name: String, text: String)] = []
    private let table = NSTableView()
    private let textView = NSTextView()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Meltype の設定"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(tab: Int = 0) {
        reload()
        tabView.selectTabViewItem(at: tab)
        window?.center()
        window?.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - 画面を作る

    private func build() {
        tabView.translatesAutoresizingMaskIntoConstraints = false
        let general = NSTabViewItem(identifier: "general")
        general.label = "一般"
        general.view = buildGeneral()
        let snippetItem = NSTabViewItem(identifier: "snippets")
        snippetItem.label = "定型文"
        snippetItem.view = buildSnippets()
        tabView.addTabViewItem(general)
        tabView.addTabViewItem(snippetItem)
        let content = NSView()
        content.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            tabView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            tabView.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            tabView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
        window?.contentView = content
    }

    private func label(_ text: String, small: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        if small {
            field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            field.textColor = .secondaryLabelColor
        }
        return field
    }

    private func buildGeneral() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

        func row(_ title: String, _ control: NSView) -> NSView {
            let r = NSStackView(views: [label(title), control])
            r.orientation = .horizontal
            r.spacing = 8
            return r
        }
        levelPopup.addItems(withTitles: levels.map(\.1))
        levelPopup.target = self
        levelPopup.action = #selector(levelChanged(_:))
        stack.addArrangedSubview(row("英語・日本語の自動判定:", levelPopup))
        punctuationPopup.addItems(withTitles: punctuations.map(\.1))
        punctuationPopup.target = self
        punctuationPopup.action = #selector(punctuationChanged(_:))
        stack.addArrangedSubview(row("句読点:", punctuationPopup))
        stack.setCustomSpacing(12, after: stack.arrangedSubviews.last!)

        for toggle in toggles {
            let box = NSButton(checkboxWithTitle: toggle.title, target: self, action: #selector(toggleChanged(_:)))
            box.identifier = NSUserInterfaceItemIdentifier(toggle.key)
            checkboxes[toggle.key] = box
            stack.addArrangedSubview(box)
            let note = label(toggle.note, small: true)
            note.preferredMaxLayoutWidth = 480
            let indent = NSView()
            indent.widthAnchor.constraint(equalToConstant: 18).isActive = true
            let noteRow = NSStackView(views: [indent, note])
            noteRow.orientation = .horizontal
            noteRow.spacing = 0
            stack.addArrangedSubview(noteRow)
            stack.setCustomSpacing(10, after: noteRow)
        }

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let flipped = FlippedView()
        flipped.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: flipped.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: flipped.trailingAnchor),
            stack.topAnchor.constraint(equalTo: flipped.topAnchor),
            stack.bottomAnchor.constraint(equalTo: flipped.bottomAnchor),
        ])
        flipped.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = flipped
        flipped.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        return scroll
    }

    private func buildSnippets() -> NSView {
        let view = NSView()
        let help = label("「;名前」と打って Space か Tab を押すと、登録した文に置き換えます。置き換えた直後に Esc で、打った ;名前 に戻します。名前は半角の英数字・記号 (空白と ; 以外)。", small: true)
        let markLabel = label("記号:")
        markField.stringValue = ";"
        markField.target = self
        markField.action = #selector(markChanged(_:))
        markField.widthAnchor.constraint(equalToConstant: 40).isActive = true

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "名前"
        nameColumn.width = 140
        let textColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("text"))
        textColumn.title = "文 (1 行目)"
        table.addTableColumn(nameColumn)
        table.addTableColumn(textColumn)
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        let tableScroll = NSScrollView()
        tableScroll.documentView = table
        tableScroll.hasVerticalScroller = true
        tableScroll.borderType = .bezelBorder

        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.delegate = self
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        let textScroll = NSScrollView()
        textScroll.documentView = textView
        textScroll.hasVerticalScroller = true
        textScroll.borderType = .bezelBorder
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true

        let add = NSButton(title: "追加", target: self, action: #selector(addSnippet(_:)))
        let remove = NSButton(title: "削除", target: self, action: #selector(removeSnippet(_:)))
        let rename = NSButton(title: "名前を変える…", target: self, action: #selector(renameSnippet(_:)))
        let buttons = NSStackView(views: [add, remove, rename, NSView(), markLabel, markField])
        buttons.orientation = .horizontal

        for sub in [help, tableScroll, textScroll, buttons] as [NSView] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(sub)
        }
        NSLayoutConstraint.activate([
            help.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            help.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            help.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            tableScroll.topAnchor.constraint(equalTo: help.bottomAnchor, constant: 8),
            tableScroll.leadingAnchor.constraint(equalTo: help.leadingAnchor),
            tableScroll.trailingAnchor.constraint(equalTo: help.trailingAnchor),
            tableScroll.heightAnchor.constraint(equalToConstant: 170),
            textScroll.topAnchor.constraint(equalTo: tableScroll.bottomAnchor, constant: 8),
            textScroll.leadingAnchor.constraint(equalTo: help.leadingAnchor),
            textScroll.trailingAnchor.constraint(equalTo: help.trailingAnchor),
            buttons.topAnchor.constraint(equalTo: textScroll.bottomAnchor, constant: 8),
            buttons.leadingAnchor.constraint(equalTo: help.leadingAnchor),
            buttons.trailingAnchor.constraint(equalTo: help.trailingAnchor),
            buttons.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])
        return view
    }

    // MARK: - 読み込み・保存

    private func reload() {
        let config = MacSettings.load()
        for toggle in toggles {
            checkboxes[toggle.key]?.state = MacSettings.bool(toggle.key, default: toggle.defaultValue, in: config) ? .on : .off
        }
        let level = MacSettings.string("DetectionLevel", default: "Balanced", in: config)
        levelPopup.selectItem(at: levels.firstIndex { $0.0 == level } ?? 1)
        let punctuation = MacSettings.string("Punctuation", default: "Japanese", in: config)
        punctuationPopup.selectItem(at: punctuations.firstIndex { $0.0 == punctuation } ?? 0)
        markField.stringValue = MacSettings.string("SnippetMark", default: ";", in: config)
        snippets = MacSnippets.load().sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        table.reloadData()
        selectSnippet(snippets.isEmpty ? -1 : 0)
    }

    private func save(_ changes: [String: Any]) {
        do { try MacSettings.save(changes) } catch { alert("設定を保存できませんでした", error.localizedDescription) }
    }

    private func saveSnippets() {
        do {
            try MacSnippets.save(Dictionary(snippets.map { ($0.name, $0.text) }, uniquingKeysWith: { $1 }))
            MacSettings.notifyChanged()
        } catch { alert("定型文を保存できませんでした", error.localizedDescription) }
    }

    private func alert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }

    @objc private func toggleChanged(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        save([key: sender.state == .on])
    }

    @objc private func levelChanged(_ sender: NSPopUpButton) {
        save(["DetectionLevel": levels[max(0, sender.indexOfSelectedItem)].0])
    }

    @objc private func punctuationChanged(_ sender: NSPopUpButton) {
        save(["Punctuation": punctuations[max(0, sender.indexOfSelectedItem)].0])
    }

    @objc private func markChanged(_ sender: NSTextField) {
        let mark = sender.stringValue.trimmingCharacters(in: .whitespaces)
        guard mark.count <= 1 else { sender.stringValue = MacSettings.string("SnippetMark", default: ";", in: MacSettings.load()); NSSound.beep(); return }
        save(["SnippetMark": mark])
    }

    // MARK: - 定型文の一覧

    func numberOfRows(in tableView: NSTableView) -> Int { snippets.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingTail
        let item = snippets[row]
        field.stringValue = tableColumn?.identifier.rawValue == "name" ? item.name : (item.text.components(separatedBy: "\n").first ?? "")
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) { selectSnippet(table.selectedRow) }

    private func selectSnippet(_ row: Int) {
        if row >= 0 && row < snippets.count {
            if table.selectedRow != row { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
            textView.string = snippets[row].text
            textView.isEditable = true
        } else {
            textView.string = ""
            textView.isEditable = false
        }
    }

    func textDidEndEditing(_ notification: Notification) { commitText() }

    func windowWillClose(_ notification: Notification) {
        commitText()
        window?.makeFirstResponder(nil)
    }

    private func commitText() {
        let row = table.selectedRow
        guard row >= 0 && row < snippets.count, snippets[row].text != textView.string else { return }
        if textView.string.isEmpty { return }
        snippets[row].text = textView.string
        table.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0..<2))
        saveSnippets()
    }

    private func askName(_ title: String, initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "半角の英数字・記号で (空白と ; は使えません)。例: sig"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "キャンセル")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard MacSnippets.isValidName(name) else { NSSound.beep(); return nil }
        return name
    }

    @objc private func addSnippet(_ sender: Any?) {
        commitText()
        guard let name = askName("定型文の名前", initial: "") else { return }
        if let index = snippets.firstIndex(where: { $0.name == name }) { selectSnippet(index); return }
        snippets.append((name, name))
        snippets.sort { $0.name < $1.name }
        table.reloadData()
        let index = snippets.firstIndex { $0.name == name } ?? 0
        selectSnippet(index)
        saveSnippets()
        window?.makeFirstResponder(textView)
        textView.selectAll(nil)
    }

    @objc private func removeSnippet(_ sender: Any?) {
        let row = table.selectedRow
        guard row >= 0 && row < snippets.count else { return }
        snippets.remove(at: row)
        table.reloadData()
        selectSnippet(min(row, snippets.count - 1))
        saveSnippets()
    }

    @objc private func renameSnippet(_ sender: Any?) {
        commitText()
        let row = table.selectedRow
        guard row >= 0 && row < snippets.count, let name = askName("新しい名前", initial: snippets[row].name),
              !snippets.contains(where: { $0.name == name }) else { return }
        snippets[row].name = name
        snippets.sort { $0.name < $1.name }
        table.reloadData()
        selectSnippet(snippets.firstIndex { $0.name == name } ?? 0)
        saveSnippets()
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
