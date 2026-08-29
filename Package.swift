// swift-tools-version: 5.9
// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import PackageDescription

let package = Package(
    name: "LyriaFlow",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LyriaFlowSpike", targets: ["LyriaFlowSpike"]),
        .executable(name: "LyriaFlow", targets: ["LyriaFlow"]),
        .library(name: "LyriaFlowKit", targets: ["LyriaFlowKit"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "LyriaFlowKit",
            path: "Sources/LyriaFlowKit"
        ),
        .executableTarget(
            name: "LyriaFlowSpike",
            dependencies: ["LyriaFlowKit"],
            path: "Sources/LyriaFlowSpike"
        ),
        .executableTarget(
            name: "LyriaFlow",
            dependencies: ["LyriaFlowKit"],
            path: "Sources/LyriaFlow"
        ),
        .testTarget(
            name: "LyriaFlowTests",
            dependencies: ["LyriaFlowKit"],
            path: "Tests/LyriaFlowTests"
        )
    ]
)
