name = "moonbit-community/testdock"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/moonbit-community/testdock"

license = "Apache-2.0"

keywords = [ "docker", "test", "e2e", "web" ]

preferred_target = "wasm"

description = "Disposable Docker Compose environments for MoonBit tests"

import {
  "moonbitlang/async@0.22.5",
  "moonbit-community/yaml@0.0.8",
  "tonyfettes/url@0.3.5",
}
