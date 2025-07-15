// swift-tools-version:5.7
import PackageDescription

let package = Package(
  name: "GameStreamKit",
  platforms: [
    .iOS(.v16),
    .macOS(.v13),
    .tvOS(.v16)
  ],
  products: [
    .library(name: "GameStreamKit", type: .static, targets: ["GameStreamKit"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/krzyzanowskim/OpenSSL-Package.git",
      from: "3.3.3001"
    ),
  ],
  targets: [
    .target(
      name: "GameStreamKit",
      dependencies: [
        .product(name: "OpenSSL", package: "OpenSSL-Package")
      ],
      path: "Sources/moonlight-common-c",
      exclude: [
        "enet/win32.c"
      ],
      sources: [
        "src",
        "reedsolomon",
        "enet/callbacks.c",
        "enet/compress.c", 
        "enet/host.c",
        "enet/list.c",
        "enet/packet.c",
        "enet/peer.c",
        "enet/protocol.c",
        "enet/unix.c"
      ],
      publicHeadersPath: "src",
      cSettings: [
        .headerSearchPath("reedsolomon"),
        .headerSearchPath("src"),
        .headerSearchPath("enet/include"),
        .define("__APPLE_USE_RFC_3542"),
        .define("HAS_FCNTL"), .define("HAS_IOCTL"), .define("HAS_POLL"),
        .define("HAS_GETADDRINFO"), .define("HAS_GETNAMEINFO"),
        .define("HAS_GETHOSTBYNAME_R"), .define("HAS_GETHOSTBYADDR_R"),
        .define("HAS_INET_PTON"), .define("HAS_INET_NTOP"),
        .define("HAS_MSGHDR_FLAGS"),
        .define("HAS_SOCKLEN_T"),
        .define("LC_DEBUG", .when(configuration: .debug)),
        .define("NDEBUG", .when(configuration: .release)),
        .unsafeFlags(["-Wno-unused-parameter"], .when(configuration: .release)),
        .unsafeFlags(["-Wno-incomplete-umbrella"])
      ]
    ),
  ]
)