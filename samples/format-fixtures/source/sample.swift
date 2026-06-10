import Foundation

struct Greeter {
    let name: String
    func greet() -> String { "Hello, \(name)!" }
}

print(Greeter(name: "OmniPreview").greet())
