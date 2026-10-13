// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ginji001
// Mac 版の設定 (config.json) と定型文 (snippets.json) の読み書き。
// どちらも Windows 版と同じファイル・同じ形式 (キーは C# のプロパティ名、列挙型は名前) で、データフォルダーに置く。

import Foundation

enum MacSettings {
    static let changedNotification = Notification.Name("MeltypeUserDictionaryChanged")

    static let directory: String? = NativeCore.shared.dataDirectory
    static var configURL: URL? { directory.map { URL(fileURLWithPath: $0).appendingPathComponent("config.json") } }
    static var snippetsURL: URL? { directory.map { URL(fileURLWithPath: $0).appendingPathComponent("snippets.json") } }

    /// config.json の中身 (無い・読めないときは空)。
    static func load() -> [String: Any] {
        guard let url = configURL, let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any] else { return [:] }
        return object
    }

    /// 変えた項目だけを config.json に書き込む (ほかの項目・Windows 版の項目はそのまま残す)。
    static func save(_ changes: [String: Any]) throws {
        guard let url = configURL else { return }
        var object = load()
        for (key, value) in changes { object[key] = value }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
        notifyChanged()
    }

    /// 動いている入力欄すべてに、設定を読み直させる (セッションを作り直す)。
    static func notifyChanged() {
        DistributedNotificationCenter.default().postNotificationName(changedNotification, object: nil, userInfo: nil, deliverImmediately: true)
    }

    static func bool(_ key: String, default value: Bool, in object: [String: Any]) -> Bool {
        (object[key] as? Bool) ?? (object[key] as? NSNumber)?.boolValue ?? value
    }

    static func string(_ key: String, default value: String, in object: [String: Any]) -> String {
        (object[key] as? String) ?? value
    }
}

/// 定型文 (issue #290)。;名前 + Space / Tab で、登録した文に置き換える。
enum MacSnippets {
    private static var cache: (date: Date?, mark: String, items: [String: String])?
    private static var configDate: Date?

    /// 名前に使える文字: 空白・; 以外の半角の英数字・記号 (Windows 版の SnippetStore.IsNameChar と同じ)。
    static func isNameChar(_ c: Character) -> Bool {
        guard let a = c.asciiValue else { return false }
        return a > 0x20 && a <= 0x7E && c != ";"
    }

    static func isValidName(_ name: String) -> Bool { !name.isEmpty && name.allSatisfy(isNameChar) }

    static func load() -> [String: String] {
        guard let url = MacSettings.snippetsURL, let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        return object.filter { isValidName($0.key) && !$0.value.isEmpty }
            .mapValues { $0.replacingOccurrences(of: "\r\n", with: "\n") }
    }

    static func save(_ items: [String: String]) throws {
        guard let url = MacSettings.snippetsURL else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
        cache = nil
    }

    /// 今の定型文と記号 (ファイルが変わったときだけ読み直す)。記号が 1 文字でない・1 つも無いときは nil (使わない)。
    static func current() -> (mark: Character, items: [String: String])? {
        let fm = FileManager.default
        let snippetDate = MacSettings.snippetsURL.flatMap { try? fm.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date }
        let cDate = MacSettings.configURL.flatMap { try? fm.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date }
        if cache == nil || cache?.date != snippetDate || configDate != cDate {
            let mark = MacSettings.string("SnippetMark", default: ";", in: MacSettings.load())
            cache = (snippetDate, mark, load())
            configDate = cDate
        }
        guard let cache, cache.mark.count == 1, let mark = cache.mark.first, !cache.items.isEmpty else { return nil }
        return (mark, cache.items)
    }

    /// キャレットの前が「先頭か空白の直後の 記号+名前」なら、その名前 (記号を除く) を返す。
    static func trigger(before: String?, mark: Character) -> String? {
        guard let before else { return nil }
        var name = ""
        for c in before.reversed() {
            if c == mark {
                let rest = before.dropLast(name.count + 1)
                guard rest.last.map({ $0.isWhitespace }) ?? true else { return nil }
                return String(name.reversed())
            }
            guard isNameChar(c) else { return nil }
            name.append(c)
        }
        return nil
    }
}
