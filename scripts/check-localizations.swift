#!/usr/bin/env swift
// Checks Resources/*.lproj/Localizable.strings:
//   - every file passes `plutil -lint`
//   - every language has exactly the keys of en.lproj
//   - every translation uses the same format placeholders as English
//   - every key the code asks for exists, and every key exists for a reason
//
// Run from anywhere: swift scripts/check-localizations.swift
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
let sources = root.appendingPathComponent("Sources/Tappi")
let expectedLanguages = ["en", "de", "fr", "es", "it", "pt-BR", "nl", "ja", "zh-Hans", "ko"]

var problems: [String] = []

func table(_ language: String) -> URL {
    resources.appendingPathComponent("\(language).lproj/Localizable.strings")
}

/// `%@`, `%ld`, `%1$@` … normalised to positional form, so `%@ %ld` equals `%1$@ %2$ld`.
func placeholders(_ string: String) -> [String] {
    let pattern = try! NSRegularExpression(pattern: #"%(?:(\d+)\$)?([@dDiuUxXoOfeEgGcCsSp]|l{1,2}[diuxX]|%)"#)
    var result: [String] = []
    var position = 0
    for match in pattern.matches(in: string, range: NSRange(string.startIndex..., in: string)) {
        let conversion = String(string[Range(match.range(at: 2), in: string)!])
        if conversion == "%" { continue }
        position += 1
        let index = Range(match.range(at: 1), in: string).map { String(string[$0]) } ?? String(position)
        result.append("\(index)$\(conversion)")
    }
    return result.sorted()
}

// Every language folder is expected, and no unexpected one is present.
let present = (try? FileManager.default.contentsOfDirectory(atPath: resources.path))?
    .filter { $0.hasSuffix(".lproj") }.map { String($0.dropLast(6)) } ?? []
for missing in Set(expectedLanguages).subtracting(present).sorted() {
    problems.append("\(missing).lproj is missing")
}
for extra in Set(present).subtracting(expectedLanguages).sorted() {
    problems.append("\(extra).lproj is not in the list of supported languages")
}

var tables: [String: [String: String]] = [:]
for language in expectedLanguages {
    let url = table(language)
    let lint = Process()
    lint.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
    lint.arguments = ["-lint", "-s", url.path]
    try lint.run()
    lint.waitUntilExit()
    if lint.terminationStatus != 0 {
        problems.append("\(language): plutil -lint failed")
        continue
    }
    guard let data = try? Data(contentsOf: url),
          let strings = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
    else {
        problems.append("\(language): could not be read as a strings table")
        continue
    }
    tables[language] = strings
}

guard let english = tables["en"] else {
    print("en.lproj could not be read")
    exit(1)
}

for language in expectedLanguages where language != "en" {
    guard let strings = tables[language] else { continue }
    for key in Set(english.keys).subtracting(strings.keys).sorted() {
        problems.append("\(language): missing \(key)")
    }
    for key in Set(strings.keys).subtracting(english.keys).sorted() {
        problems.append("\(language): \(key) does not exist in English")
    }
    for (key, value) in strings where english[key] != nil {
        if value.trimmingCharacters(in: .whitespaces).isEmpty {
            problems.append("\(language): \(key) is empty")
        }
        if placeholders(value) != placeholders(english[key]!) {
            problems.append("\(language): \(key) has placeholders \(placeholders(value)), English has \(placeholders(english[key]!))")
        }
    }
}

// Keys in code: literals on lines that call tr( or name a descriptionKey.
let keyLiteral = try! NSRegularExpression(pattern: #""([a-z][A-Za-z]*(?:\.[A-Za-z]+)+)""#)
var used = Set<String>()
var allSource = ""
for file in (try? FileManager.default.contentsOfDirectory(atPath: sources.path)) ?? [] where file.hasSuffix(".swift") {
    let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
    allSource += text
    for line in text.split(separator: "\n") where line.contains("tr(") || line.contains("descriptionKey:") {
        let line = String(line)
        for match in keyLiteral.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
            used.insert(String(line[Range(match.range(at: 1), in: line)!]))
        }
    }
}
for key in used.subtracting(english.keys).sorted() {
    problems.append("code uses \(key), which en.lproj does not define")
}
for key in english.keys.sorted() where !allSource.contains("\"\(key)\"") {
    problems.append("en.lproj defines \(key), which no source file mentions")
}

if problems.isEmpty {
    print("OK: \(expectedLanguages.count) languages, \(english.count) keys each, all lint clean, placeholders consistent, \(used.count) keys referenced from code.")
} else {
    problems.forEach { print("✗ \($0)") }
    exit(1)
}
