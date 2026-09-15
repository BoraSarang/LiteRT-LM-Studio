// swift-tools-version: 5.9
// EngineVendor — LiteRT-LM v0.17.0 바이너리 래퍼 (T-010, PLAN_v7).
// Swift 소스는 앱 타깃에 직접 포함 (LiteRTLMStudio/Core/LiteRTLM, 모듈 호환성 회피).
// 업그레이드 시: 바이너리 url/checksum + Sources 13종 교체 (upstream Package.swift 대조).
import PackageDescription

let package = Package(
    name: "LiteRTLMVendor",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CLiteRTLMmac", targets: ["CLiteRTLMmac"]),
    ],
    targets: [
        .binaryTarget(
            name: "CLiteRTLMmac",
            url: "https://github.com/google-ai-edge/LiteRT-LM/releases/download/v0.17.0/CLiteRTLM_mac.xcframework.zip",
            checksum: "83efd536485c9d58fcd7fb7d4556ddb16ca46bb775b0449d08d9825c6836c1a4"
        ),
    ]
)
