// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DecisionReview",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "DecisionReview",
            path: "Sources/DecisionReview"
        )
    ]
)
