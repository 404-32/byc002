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

name = "404-32/mooncompat"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/404-32/byc002"

license = "Apache-2.0"

keywords = [ "moonbit", "api-compatibility", "semver", "developer-tools" ]

preferred_target = "wasm"

description = "A MoonBit-native public API compatibility checker for semver-aware package releases."

import {
  "moonbitlang/async@0.22.7",
}
