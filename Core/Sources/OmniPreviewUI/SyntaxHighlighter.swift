import AppKit

/// Token-based syntax highlighter.
/// Strategy: apply token colors in ascending priority — the last color written
/// wins, so high-priority spans (comments, strings) are applied last and
/// override any lower-priority color already set in that range.
struct SyntaxHighlighter {

    // MARK: Colors (system-adaptive)

    static let keywordColor  = NSColor.systemPurple
    static let stringColor   = NSColor.systemRed
    static let commentColor  = NSColor(name: nil) { traits in
        traits.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.42, green: 0.63, blue: 0.37, alpha: 1)
            : NSColor(calibratedRed: 0.18, green: 0.47, blue: 0.13, alpha: 1)
    }
    static let numberColor   = NSColor.systemBlue
    static let typeColor     = NSColor.systemCyan
    static let functionColor = NSColor.systemOrange
    static let tagColor      = NSColor.systemGreen
    static let attributeColor = NSColor.systemTeal
    static let keyColor      = NSColor.systemPurple
    static let operatorColor = NSColor.systemTeal

    // MARK: Public API

    static let maxHighlightBytes = 256 * 1024

    static func highlight(_ text: String, language: String?, fontSize: CGFloat = 12) -> NSAttributedString {
        let lang = language?.lowercased() ?? ""
        let source: String
        if text.utf8.count > maxHighlightBytes {
            let index = text.utf8.index(text.utf8.startIndex, offsetBy: maxHighlightBytes,
                                         limitedBy: text.utf8.endIndex) ?? text.utf8.endIndex
            source = String(text[..<index]) + "\n\n// ── syntax highlighting truncated ──"
        } else {
            source = text
        }

        let result = NSMutableAttributedString(string: source, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ])

        switch lang {
        case "json":            tokenizeJSON(source, into: result)
        case "xml", "html",
             "svg", "xhtml":   tokenizeXML(source, into: result)
        case "yaml":            tokenizeYAML(source, into: result)
        case "sql":             tokenizeSQL(source, into: result)
        default:                tokenizeGeneric(source, language: lang, into: result)
        }

        return result
    }

    // MARK: Regex helper

    private static func apply(_ pattern: String, to result: NSMutableAttributedString,
                               options: NSRegularExpression.Options = [],
                               group: Int = 0, color: NSColor) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let str = result.string
        let full = NSRange(location: 0, length: (str as NSString).length)
        regex.enumerateMatches(in: str, range: full) { match, _, _ in
            guard let match else { return }
            let range = group == 0 ? match.range : match.range(at: group)
            guard range.location != NSNotFound else { return }
            result.addAttribute(.foregroundColor, value: color, range: range)
        }
    }

    // MARK: JSON

    private static func tokenizeJSON(_ source: String, into result: NSMutableAttributedString) {
        // Apply ascending priority (last wins)
        apply(#"-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?"#,
              to: result, color: numberColor)
        apply(#"\b(?:true|false|null)\b"#,
              to: result, color: keywordColor)
        // String values (not followed by colon)
        apply(#""(?:[^"\\]|\\.)*"(?!\s*:)"#,
              to: result, color: stringColor)
        // String keys (followed by colon)
        apply(#""(?:[^"\\]|\\.)*"(?=\s*:)"#,
              to: result, color: keyColor)
    }

    // MARK: XML / HTML

    private static func tokenizeXML(_ source: String, into result: NSMutableAttributedString) {
        apply(#"<!--[\s\S]*?-->"#, to: result, options: [.dotMatchesLineSeparators], color: commentColor)
        apply(#"<!\[CDATA\[[\s\S]*?\]\]>"#, to: result, options: [.dotMatchesLineSeparators], color: stringColor)
        apply(#"<!DOCTYPE[^>]*>"#, to: result, options: [.caseInsensitive], color: commentColor)
        // Attribute values
        apply(#"(?<==)\s*(?:"[^"]*"|'[^']*')"#, to: result, color: stringColor)
        // Attribute names
        apply(#"(?<=\s)([a-zA-Z_:][a-zA-Z0-9_:.-]*)(?=\s*=)"#, to: result, color: attributeColor)
        // Tag names (both open and close)
        apply(#"</?([a-zA-Z_][a-zA-Z0-9_:.-]*)(?=[\s>/>]|$)"#, to: result, group: 1, color: tagColor)
        apply(#"<[/?!]?"#, to: result, color: NSColor.tertiaryLabelColor)
        apply(#"/?>"#, to: result, color: NSColor.tertiaryLabelColor)
    }

    // MARK: YAML

    private static func tokenizeYAML(_ source: String, into result: NSMutableAttributedString) {
        apply(#"-?[0-9]+(?:\.[0-9]+)?"#, to: result, color: numberColor)
        apply(#"\b(?:true|false|yes|no|null|~)\b"#, to: result, color: keywordColor)
        apply(#""(?:[^"\\]|\\.)*"|'[^']*'"#, to: result, color: stringColor)
        // Multi-document markers
        apply(#"^(?:---|\.\.\.)\s*$"#, to: result, options: [.anchorsMatchLines], color: keywordColor)
        // YAML anchors & aliases
        apply(#"[&*][a-zA-Z0-9_-]+"#, to: result, color: functionColor)
        // Keys: anything before a colon that isn't indented past list marker
        apply(#"(?m)^[ \t]*([a-zA-Z0-9_][a-zA-Z0-9_ -]*)(?=\s*:)"#,
              to: result, options: [.anchorsMatchLines], group: 1, color: keyColor)
        apply(#"(?m)^\s+-\s+([a-zA-Z0-9_][a-zA-Z0-9_ -]*)(?=\s*:)"#,
              to: result, options: [.anchorsMatchLines], group: 1, color: keyColor)
        apply(#"#.*"#, to: result, color: commentColor)
    }

    // MARK: SQL

    private static func tokenizeSQL(_ source: String, into result: NSMutableAttributedString) {
        let kws = "SELECT|FROM|WHERE|AND|OR|NOT|IN|IS|NULL|JOIN|LEFT|RIGHT|INNER|OUTER|" +
                  "FULL|ON|GROUP|BY|ORDER|HAVING|LIMIT|OFFSET|INSERT|INTO|VALUES|UPDATE|" +
                  "SET|DELETE|CREATE|TABLE|ALTER|DROP|INDEX|VIEW|TRIGGER|PROCEDURE|" +
                  "FUNCTION|BEGIN|END|COMMIT|ROLLBACK|TRANSACTION|PRIMARY|KEY|FOREIGN|" +
                  "REFERENCES|UNIQUE|CHECK|DEFAULT|NOT|NULL|AS|DISTINCT|CASE|WHEN|THEN|ELSE|" +
                  "UNION|ALL|EXISTS|WITH|RETURNING|EXPLAIN|ANALYZE"
        apply("(?i)\\b(?:\(kws))\\b", to: result, color: keywordColor)
        apply(#"-?[0-9]+(?:\.[0-9]+)?"#, to: result, color: numberColor)
        apply(#"'(?:[^'\\]|\\.)*'"#, to: result, color: stringColor)
        apply(#"--.*"#, to: result, color: commentColor)
        apply(#"/\*[\s\S]*?\*/"#, to: result, options: [.dotMatchesLineSeparators], color: commentColor)
    }

    // MARK: Generic (C-family, Python, Shell, …)

    private static func tokenizeGeneric(_ source: String, language: String,
                                         into result: NSMutableAttributedString) {
        // Low-priority: function calls and type names
        apply(#"\b([a-z_][a-zA-Z0-9_]*)\s*(?=[\(<])"#, to: result, group: 1, color: functionColor)
        apply(#"\b[A-Z][a-zA-Z0-9_]+\b"#, to: result, color: typeColor)

        // Numbers
        apply(#"\b0x[0-9a-fA-F][0-9a-fA-F_]*\b|\b0b[01][01_]*\b|\b-?[0-9][0-9_]*(?:\.[0-9][0-9_]*)?(?:[eEfF][+-]?[0-9]+)?[uUlLfF]?\b"#,
              to: result, color: numberColor)

        // Keywords (language-specific)
        let kws = keywords(for: language)
        if !kws.isEmpty {
            let pattern = "\\b(?:" + kws.joined(separator: "|") + ")\\b"
            apply(pattern, to: result, color: keywordColor)
        }

        // Strings — applied after keywords so they override inside quotes
        let stringPatterns = stringPatterns(for: language)
        for pattern in stringPatterns {
            apply(pattern, to: result, options: [.dotMatchesLineSeparators], color: stringColor)
        }

        // Comments — highest priority (override everything)
        for pattern in blockCommentPatterns(for: language) {
            apply(pattern, to: result, options: [.dotMatchesLineSeparators], color: commentColor)
        }
        if let linePattern = lineCommentPattern(for: language) {
            apply(linePattern, to: result, color: commentColor)
        }
    }

    // MARK: Language data

    private static func keywords(for language: String) -> [String] {
        switch language {
        case "swift":
            return ["import","class","struct","enum","protocol","extension","func","var","let",
                    "if","else","guard","switch","case","default","for","while","repeat","do",
                    "return","break","continue","throw","throws","rethrows","try","catch","in",
                    "is","as","nil","true","false","self","super","init","deinit",
                    "get","set","willSet","didSet","subscript","static","override","final",
                    "open","public","internal","private","fileprivate","mutating","lazy",
                    "weak","unowned","inout","defer","async","await","actor","nonisolated",
                    "some","any","where","associatedtype","typealias","operator"]
        case "objective-c", "objective-c++":
            return ["@interface","@implementation","@end","@property","@synthesize",
                    "@protocol","@required","@optional","@class","@selector","@encode",
                    "if","else","for","while","do","switch","case","default","return",
                    "break","continue","nil","NULL","YES","NO","self","super","id",
                    "void","int","float","double","BOOL","NSInteger","NSUInteger",
                    "IBOutlet","IBAction","strong","weak","nonatomic","atomic","copy","assign"]
        case "python":
            return ["and","as","assert","async","await","break","class","continue","def",
                    "del","elif","else","except","finally","for","from","global","if",
                    "import","in","is","lambda","nonlocal","not","or","pass","raise",
                    "return","try","while","with","yield","True","False","None"]
        case "javascript", "typescript":
            return ["async","await","break","case","catch","class","const","continue",
                    "debugger","default","delete","do","else","export","extends","false",
                    "finally","for","from","function","if","import","in","instanceof","let",
                    "new","null","of","return","static","super","switch","this","throw","true",
                    "try","typeof","undefined","var","void","while","with","yield",
                    "interface","type","enum","implements","declare","abstract","readonly",
                    "override","as","satisfies","keyof","infer","never","unknown","any"]
        case "go":
            return ["break","case","chan","const","continue","default","defer","else","fallthrough",
                    "for","func","go","goto","if","import","interface","map","package","range",
                    "return","select","struct","switch","type","var","true","false","nil",
                    "int","int8","int16","int32","int64","uint","uint8","uint16","uint32","uint64",
                    "float32","float64","complex64","complex128","string","bool","byte","rune","error",
                    "make","new","len","cap","append","copy","close","delete","panic","recover",
                    "print","println","iota"]
        case "rust":
            return ["as","break","const","continue","crate","else","enum","extern","false","fn",
                    "for","if","impl","in","let","loop","match","mod","move","mut","pub","ref",
                    "return","self","Self","static","struct","super","trait","true","type",
                    "unsafe","use","where","while","async","await","dyn","abstract","become",
                    "box","do","final","macro","override","priv","typeof","unsized","virtual","yield",
                    "i8","i16","i32","i64","i128","isize","u8","u16","u32","u64","u128","usize",
                    "f32","f64","bool","char","str","String","Vec","Option","Result","Some","None","Ok","Err"]
        case "java":
            return ["abstract","assert","boolean","break","byte","case","catch","char","class",
                    "const","continue","default","do","double","else","enum","extends","false",
                    "final","finally","float","for","goto","if","implements","import","instanceof",
                    "int","interface","long","native","new","null","package","private","protected",
                    "public","return","short","static","strictfp","super","switch","synchronized",
                    "this","throw","throws","transient","true","try","void","volatile","while",
                    "record","sealed","permits","yield","var"]
        case "kotlin":
            return ["abstract","actual","annotation","as","break","by","catch","class","companion",
                    "const","constructor","continue","crossinline","data","do","dynamic","else","enum",
                    "expect","external","false","final","finally","for","fun","if","import","in",
                    "infix","init","inline","inner","interface","internal","is","it","lateinit",
                    "noinline","null","object","open","operator","out","override","package","private",
                    "protected","public","reified","return","sealed","super","suspend","tailrec","this",
                    "throw","true","try","typealias","typeof","val","var","vararg","when","where","while"]
        case "c", "c++", "objective-c":
            return ["auto","break","case","char","const","continue","default","do","double","else",
                    "enum","extern","float","for","goto","if","inline","int","long","register",
                    "return","short","signed","sizeof","static","struct","switch","typedef","union",
                    "unsigned","void","volatile","while","true","false","nullptr","NULL",
                    "bool","class","new","delete","namespace","using","public","private","protected",
                    "virtual","override","final","template","typename","explicit","operator",
                    "friend","constexpr","consteval","constinit","co_await","co_yield","co_return"]
        case "c#":
            return ["abstract","as","base","bool","break","byte","case","catch","char","checked",
                    "class","const","continue","decimal","default","delegate","do","double","else",
                    "enum","event","explicit","extern","false","finally","fixed","float","for",
                    "foreach","goto","if","implicit","in","int","interface","internal","is","lock",
                    "long","namespace","new","null","object","operator","out","override","params",
                    "private","protected","public","readonly","ref","return","sbyte","sealed","short",
                    "sizeof","stackalloc","static","string","struct","switch","this","throw","true",
                    "try","typeof","uint","ulong","unchecked","unsafe","ushort","using","virtual",
                    "void","volatile","while","async","await","var","dynamic","record","with"]
        case "ruby":
            return ["__ENCODING__","__LINE__","__FILE__","BEGIN","END","alias","and","begin","break",
                    "case","class","def","defined?","do","else","elsif","end","ensure","false","for",
                    "if","in","module","next","nil","not","or","redo","rescue","retry","return","self",
                    "super","then","true","undef","unless","until","when","while","yield",
                    "attr_accessor","attr_reader","attr_writer","require","require_relative","include","extend"]
        case "php":
            return ["abstract","and","array","as","break","callable","case","catch","class","clone",
                    "const","continue","declare","default","die","do","echo","else","elseif","empty",
                    "enddeclare","endfor","endforeach","endif","endswitch","endwhile","eval","exit",
                    "extends","false","final","finally","fn","for","foreach","function","global","goto",
                    "if","implements","include","include_once","instanceof","insteadof","interface",
                    "isset","list","match","namespace","new","null","or","print","private","protected",
                    "public","readonly","require","require_once","return","static","switch","throw",
                    "trait","true","try","unset","use","var","while","xor","yield"]
        case "shell", "bash", "zsh":
            return ["if","then","else","elif","fi","for","in","do","done","while","until","case",
                    "esac","function","return","exit","export","local","readonly","declare","typeset",
                    "unset","shift","source","alias","echo","printf","read","test","true","false",
                    "break","continue","exec","eval","trap","wait","jobs","kill","bg","fg",
                    "cd","ls","mkdir","rm","cp","mv","cat","grep","sed","awk","find","sort","uniq"]
        case "lua":
            return ["and","break","do","else","elseif","end","false","for","function","goto","if",
                    "in","local","nil","not","or","repeat","return","then","true","until","while"]
        case "scss", "sass", "less":
            return ["@import","@use","@forward","@mixin","@include","@extend",
                    "@if","@else","@for","@each","@while","@function","@return",
                    "@media","@keyframes","@supports","@layer","@property",
                    "from","to","true","false","null","not","and","or"]
        case "graphql", "gql":
            return ["query","mutation","subscription","fragment","on","type","interface",
                    "union","enum","input","scalar","schema","directive","extend",
                    "true","false","null","implements","repeatable"]
        case "dart":
            return ["abstract","as","assert","async","await","break","case","catch",
                    "class","const","continue","covariant","default","deferred","do",
                    "dynamic","else","enum","export","extends","extension","external",
                    "factory","false","final","finally","for","Function","get","hide",
                    "if","implements","import","in","interface","is","late","library",
                    "mixin","new","null","on","operator","part","required","rethrow",
                    "return","set","show","static","super","switch","sync","this",
                    "throw","true","try","typedef","var","void","while","with","yield"]
        case "scala":
            return ["abstract","case","catch","class","def","do","else","extends",
                    "false","final","finally","for","forSome","if","implicit","import",
                    "lazy","macro","match","new","null","object","override","package",
                    "private","protected","return","sealed","super","this","throw","trait",
                    "true","try","type","val","var","while","with","yield"]
        default:
            return []
        }
    }

    private static func stringPatterns(for language: String) -> [String] {
        switch language {
        case "python", "ruby":
            // Triple quotes first (longer match), then single
            return [#""""[\s\S]*?""""#, #"'''[\s\S]*?'''"#,
                    #""(?:[^"\\]|\\.)*""#, #"'(?:[^'\\]|\\.)*'"#]
        case "javascript", "typescript":
            return [#"`(?:[^`\\]|\\.)*`"#, // template literals
                    #""(?:[^"\\]|\\.)*""#, #"'(?:[^'\\]|\\.)*'"#]
        case "shell", "bash", "zsh":
            return [#""(?:[^"\\]|\\.)*""#, #"'[^']*'"#, #"`[^`]*`"#]
        default:
            return [#""(?:[^"\\]|\\.)*""#, #"'(?:[^'\\]|\\.)*'"#]
        }
    }

    private static func lineCommentPattern(for language: String) -> String? {
        switch language {
        case "python","ruby","shell","bash","zsh","fish","toml","ini","cfg","conf",
             "yaml","r","nim","elixir","crystal","graphql","gql":
            return "#.*"
        case "lua","haskell","hs","sql": return "--.*"
        case "scss","sass","less","css","html","xml","svg": return nil  // block-only
        default: return "//.*"  // C-family and everything else
        }
    }

    private static func blockCommentPatterns(for language: String) -> [String] {
        switch language {
        case "python","ruby","shell","bash","zsh","toml","ini","cfg","conf","yaml":
            return []
        case "lua":
            return [#"--\[\[[\s\S]*?\]\]"#]
        case "html","xml","svg","xhtml":
            return [#"<!--[\s\S]*?-->"#]
        default:
            return [#"/\*[\s\S]*?\*/"#]  // C-family
        }
    }
}
