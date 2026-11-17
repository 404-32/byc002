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

name = "404-32/griddiagnose"

version = "0.3.0"

readme = "README.md"

repository = "https://github.com/404-32/byc002"

license = "Apache-2.0"

keywords = [
  "power-systems",
  "outage-localization",
  "distribution-grid",
  "power-quality",
  "phase-loss",
  "fault-diagnosis",
  "edge-computing",
  "wasm",
]

preferred_target = "wasm-gc"

supported_targets = [ "wasm-gc", "js", "native" ]

description = "Multi-model low-voltage distribution diagnostic engine in MoonBit"

import {
  "moonbitlang/x@0.5.6",
}
