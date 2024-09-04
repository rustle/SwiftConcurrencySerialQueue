// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftConcurrencySerialQueue",
    products: [
        .library(
            name: "SwiftConcurrencySerialQueue",
            targets: ["SwiftConcurrencySerialQueue"]
        ),
    ],
    targets: [
        .target(name: "SwiftConcurrencySerialQueue"),
        .testTarget(
            name: "SwiftConcurrencySerialQueueTests",
            dependencies: ["SwiftConcurrencySerialQueue"]
        ),
    ]
)
