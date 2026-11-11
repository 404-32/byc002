// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "404-32/gridlatch"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/404-32/byc002"

license = "Apache-2.0"

keywords = [
  "power-systems",
  "outage-localization",
  "fault-diagnosis",
  "edge-computing",
  "wasm",
]

preferred_target = "wasm-gc"

supported_targets = [ "wasm-gc", "js", "native" ]

description = "Topology-aware low-voltage outage and fault-section localization engine in MoonBit"

import {
  "moonbitlang/x@0.5.6",
}
