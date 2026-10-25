# Native codec dependencies

These are required versioned source files, compiled into the app. No shared
Homebrew library or external save-editor executable is used.

- **Zstandard 1.5.7**: upstream `lib/common`, `lib/compress`, `lib/decompress`
  C sources and headers, plus public headers. Assembly is disabled for the
  portable C build. [Upstream release](https://github.com/facebook/zstd/releases/tag/v1.5.7).
  Release archive SHA-256:
  `eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3`.
  Upstream [LICENSE](zstd/LICENSE) and [COPYING](zstd/COPYING) are included.
- **CityHash** commit `f5dc54147fcce12cefd16548c8e760d68ac04226`:
  `city.cc`, `city.h`, and [COPYING](cityhash/COPYING) from
  [Google's source](https://github.com/google/cityhash/tree/f5dc54147fcce12cefd16548c8e760d68ac04226).
  The small local `config.h` selects compiler built-in branch prediction for
  little-endian Apple targets. No SSE4.2 CRC implementation is enabled.

The existing Python dependency builder is independent of these native targets.
