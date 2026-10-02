/*
 * Standalone harness for CodeFormatterEngine.
 *
 * The engine is intentionally free of AppKit/SwiftUI dependencies so it can be
 * compiled outside the app bundle. This file supplies the one type it borrows
 * from the app target and exercises each language against realistic input.
 */

import Foundation

// Shim mirroring DynamicIsland/enums/generic.swift
enum CodeFormatterLanguage: String, CaseIterable, Codable, Identifiable {
    case json
    case yaml
    case sql
    case html
    case css
    case javascript
    case xml

    var id: String { rawValue }
}

extension String {
    var trimmedEnds: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Harness helpers

var totalChecks = 0
var failedChecks: [String] = []

func check(_ name: String, _ condition: Bool, _ detail: String = "") {
    totalChecks += 1
    guard condition else {
        failedChecks.append("FAIL: \(name)\(detail.isEmpty ? "" : "\n     \(detail)")")
        return
    }
}

func show(_ title: String, _ text: String) {
    print("---- \(title) ----")
    print(text)
    print("")
}

func formatted(_ source: String, _ language: CodeFormatterLanguage, indent: Int = 2) -> String {
    let result = CodeFormatterEngine.format(source, language: language, indentWidth: indent)
    if !result.isValid, let message = result.message {
        print("!! \(language.rawValue) format failed: \(message)")
    }
    return result.output
}

func minified(_ source: String, _ language: CodeFormatterLanguage) -> String {
    let result = CodeFormatterEngine.minify(source, language: language)
    if !result.isValid, let message = result.message {
        print("!! \(language.rawValue) minify failed: \(message)")
    }
    return result.output
}

// MARK: - JSON

let jsonSource = """
{"name":"atoll","version":"2.3.3","deployment":{"replicas":2,"tags":["gpu","edge"]},"active":true,"score":9.5,"notes":null}
"""

let jsonOutput = formatted(jsonSource, .json)
show("JSON formatted", jsonOutput)

check("JSON opens pretty printed", jsonOutput.hasPrefix("{\n  \"name\""))
check(
    "JSON keeps key order",
    jsonOutput.range(of: "\"name\"")!.lowerBound < jsonOutput.range(of: "\"deployment\"")!.lowerBound
)
check("JSON indents nested object", jsonOutput.contains("\n    \"replicas\": 2"))
check("JSON renders true", jsonOutput.contains("\"active\": true"))
check("JSON renders null", jsonOutput.contains("\"notes\": null"))
check("JSON preserves float literal", jsonOutput.contains("\"score\": 9.5"))

let jsonMinified = minified(jsonSource, .json)
check(
    "JSON minifies",
    jsonMinified == "{\"name\":\"atoll\",\"version\":\"2.3.3\",\"deployment\":{\"replicas\":2,\"tags\":[\"gpu\",\"edge\"]},\"active\":true,\"score\":9.5,\"notes\":null}",
    jsonMinified
)

check("JSON empty object", formatted("{}", .json) == "{}")
check("JSON empty array", formatted("[]", .json) == "[]")
check("JSON re-format is stable", formatted(jsonOutput, .json) == jsonOutput)
check("JSON invalid reports failure", !CodeFormatterEngine.format("{\"a\": }", language: .json).isValid)

// MARK: - YAML

let yamlSource = """
apiVersion: apps/v1
kind: Deployment
metadata:
  name: atoll
labels:
    app: atoll
spec:
  replicas: 2
  template:
    containers:
      - name: worker
        image: nginx:1.25
        ports:
          - containerPort: 80
          protocol: TCP
"""

let yamlOutput = formatted(yamlSource, .yaml)
show("YAML formatted", yamlOutput)

check("YAML top level key stays flush", yamlOutput.hasPrefix("apiVersion: apps/v1"))
check("YAML keeps valid two space nesting", yamlOutput.contains("\n  name: atoll"))
check("YAML normalises 4 space indent", yamlOutput.contains("\n  app: atoll"))
check("YAML sequence owned by key", yamlOutput.contains("\n      - name: worker"))
check("YAML item continues past dash", yamlOutput.contains("\n        image: nginx:1.25"))
check("YAML preserves content text", yamlOutput.contains("kind: Deployment"))

// MARK: - SQL

let sqlSource = "select u.id, u.name, count(o.id) as orders from users u left join orders o on o.user_id = u.id where u.active = 1 and u.created_at > '2026-01-01' group by u.id, u.name having count(o.id) > 3 order by orders desc limit 20;"

let sqlOutput = formatted(sqlSource, .sql)
show("SQL formatted", sqlOutput)

check("SQL uppercases keywords when asked", sqlOutput.contains("SELECT"))
check("SQL breaks FROM", sqlOutput.contains("\nFROM "))
check("SQL breaks LEFT JOIN", sqlOutput.contains("\nLEFT JOIN "))
check("SQL indents ON under its join", sqlOutput.contains("\n  ON "))
check("SQL breaks WHERE", sqlOutput.contains("\nWHERE "))
check("SQL indents AND", sqlOutput.contains("\n  AND "))
check("SQL expands select list", sqlOutput.contains("\n  u.id,\n  u.name,"), sqlOutput)
check("SQL breaks GROUP BY", sqlOutput.contains("\nGROUP BY "))
check("SQL breaks ORDER BY", sqlOutput.contains("\nORDER BY "))
check("SQL breaks LIMIT", sqlOutput.contains("\nLIMIT 20"), sqlOutput)
check("SQL preserves string literal", sqlOutput.contains("'2026-01-01'"))
check("SQL minifies without newlines", !minified(sqlSource, .sql).contains("\n"))

// A zero-indented key is a sibling in real YAML, so output must not invent nesting.
let yamlSibling = formatted("server:\nport: 80", .yaml)
check("YAML treats flush keys as siblings", yamlSibling == "server:\nport: 80", yamlSibling)

let sqlLower = CodeFormatterEngine
    .format(sqlSource, language: .sql, indentWidth: 2, uppercaseSQLKeywords: false)
    .output
show("SQL lowercase mode", sqlLower)
check("SQL honours lowercase preference", sqlLower.contains("select") && !sqlLower.contains("SELECT"))

// MARK: - HTML

let htmlSource = """
<div class="card"><h1>Atoll</h1><p>Hello   world</p><img src="a.png"><br><ul><li>one</li><li>two</li></ul></div>
"""

let htmlOutput = formatted(htmlSource, .html)
show("HTML formatted", htmlOutput)

check("HTML breaks nested tags", htmlOutput.contains("\n  <h1>Atoll</h1>"))
check("HTML inline text stays on one line", htmlOutput.contains("<h1>Atoll</h1>"))
check("HTML collapses redundant spaces", htmlOutput.contains("Hello world"))
check("HTML void element stays single", htmlOutput.contains("<img src=\"a.png\">"))
check("HTML list indents", htmlOutput.contains("\n    <li>one</li>"))
check("HTML minifies to one line", !minified(htmlSource, .html).contains("\n"))

// MARK: - XML

let xmlSource = "<note><to>team</to><from>atoll</from><body>hello</body></note>"
let xmlOutput = formatted(xmlSource, .xml)
show("XML formatted", xmlOutput)
check("XML preserves element case", xmlOutput.contains("<note>") && xmlOutput.contains("<from>"))
check("XML indents children", xmlOutput.contains("\n  <to>team</to>"))

// MARK: - CSS

let cssSource = ".card{display:flex;color:#fff;}#hero,.hero{position:relative;top:0}@media (max-width:600px){.card{flex-direction:column}}"

let cssOutput = formatted(cssSource, .css)
show("CSS formatted", cssOutput)

check("CSS breaks after brace", cssOutput.contains(".card {"))
check("CSS indents declarations", cssOutput.contains("\n  display: flex;"))
check("CSS puts comma selectors on own lines", cssOutput.contains("#hero,") && cssOutput.contains("\n.hero {"))
check("CSS nests media query", cssOutput.contains("\n  .card {"))
check("CSS closes every block", cssOutput.hasSuffix("}"))

let cssMinified = minified(cssSource, .css)
show("CSS minified", cssMinified)
check("CSS minifies declarations", cssMinified.contains(".card{display:flex;"), cssMinified)

// MARK: - JavaScript

let jsSource = """
function mount(options={}){const {root,theme='dark'}=options;if(!root){throw new Error('root missing');}
const nodes=[1,2,3].map(n=>({id:n,theme}));for(const node of nodes){console.log(`mounting ${node.id}`);}
return nodes;}
"""

let jsOutput = formatted(jsSource, .javascript)
show("JS formatted", jsOutput)

check("JS breaks after function brace", jsOutput.contains("function mount(options = {}) {\n"))
check("JS indents body", jsOutput.contains("\n  const {"))
check("JS breaks if block", jsOutput.contains("\n  if (!root) {"))
check("JS keeps string literal intact", jsOutput.contains("'root missing'"))
check("JS keeps template literal intact", jsOutput.contains("`mounting ${node.id}`"))
check("JS keeps empty object literal inline", jsOutput.contains("options = {})"), jsOutput)
check("JS emits object literal entries", jsOutput.contains("id: n"))
check("JS minifies to something usable", !minified(jsSource, .javascript).isEmpty)

let jsEdge = formatted("const a = 'a } b { c'; // trailing\nconst b = /ab{2}c/g; if (a) { console.log(a); }", .javascript)
show("JS strings and comments", jsEdge)
check("JS does not break inside strings", jsEdge.contains("'a } b { c'"))
check("JS keeps regex literal", jsEdge.contains("/ab{2}c/g"))
check("JS keeps line comment", jsEdge.contains("// trailing"))

// MARK: - Report

print("==== \(totalChecks) checks run, \(failedChecks.count) failed ====")
for failure in failedChecks {
    print(failure)
}
fflush(__stdoutp)
exit(failedChecks.isEmpty ? 0 : 1)
