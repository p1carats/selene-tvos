// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GameStreamKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .tvOS(.v18),
        .visionOS(.v2)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(name: "GameStreamKit", type: .static, targets: ["GameStreamKit"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/krzyzanowskim/OpenSSL-Package.git",
            from: "3.3.3001"
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "GameStreamKit",
            dependencies: ["moonlight-common-c"],
            path: "Sources/GameStreamKit"
        ),
        .target(
            name: "moonlight-common-c",
            dependencies: [
                .product(name: "OpenSSL", package: "OpenSSL-Package")
            ],
            path: "Sources/Limelight",
            sources: [
                "moonlight-common-c/src",
                "moonlight-common-c/reedsolomon",
                "moonlight-common-c/enet/callbacks.c",
                "moonlight-common-c/enet/compress.c",
                "moonlight-common-c/enet/host.c",
                "moonlight-common-c/enet/list.c",
                "moonlight-common-c/enet/packet.c",
                "moonlight-common-c/enet/peer.c",
                "moonlight-common-c/enet/protocol.c",
                "moonlight-common-c/enet/unix.c"
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("moonlight-common-c/src"),
                .headerSearchPath("moonlight-common-c/reedsolomon"),
                .headerSearchPath("moonlight-common-c/enet/include"),
                .define("__APPLE_USE_RFC_3542"),
                .define("HAS_FCNTL"),
                .define("HAS_IOCTL"),
                .define("HAS_POLL"),
                .define("HAS_GETADDRINFO"),
                .define("HAS_GETNAMEINFO"),
                .define("HAS_GETHOSTBYNAME_R"),
                .define("HAS_GETHOSTBYADDR_R"),
                .define("HAS_INET_PTON"),
                .define("HAS_INET_NTOP"),
                .define("HAS_MSGHDR_FLAGS"),
                .define("HAS_SOCKLEN_T"),
                .define("LC_DEBUG", .when(configuration: .debug)),
                .define("NDEBUG", .when(configuration: .release))
            ]
        ),
    ]
)
