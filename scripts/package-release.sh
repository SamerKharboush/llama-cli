#!/usr/bin/env zsh

set -e
setopt NULL_GLOB

ROOT_DIR="${0:A:h:h}"
LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-/Users/macpro/llama.cpp}"
BUILD_BIN="$LLAMA_CPP_DIR/build/bin"
STAGE_DIR="$ROOT_DIR/.release-staging/llama-cpp-macpro"
VENDOR_TARBALL="$ROOT_DIR/vendor/llama-cpp-macpro.tar.gz"
RELEASE_TARBALL="$ROOT_DIR/releases/llama-cpp-macpro-optimized.tar.gz"
RELEASE_ZIP="$ROOT_DIR/releases/llama-cpp-macpro-optimized.zip"

required_bins=(llama-server llama-cli llama-bench llama-quantize llama-perplexity)

for bin in "${required_bins[@]}"; do
  if [[ ! -x "$BUILD_BIN/$bin" ]]; then
    echo "Missing required binary: $BUILD_BIN/$bin" >&2
    exit 1
  fi
done

rm -rf "$ROOT_DIR/.release-staging"
mkdir -p "$STAGE_DIR/bin" "$STAGE_DIR/lib" "$ROOT_DIR/vendor" "$ROOT_DIR/releases"

for bin in "${required_bins[@]}"; do
  cp "$BUILD_BIN/$bin" "$STAGE_DIR/bin/"
done

cp "$ROOT_DIR/src/llama-launcher.sh" "$STAGE_DIR/bin/llama-launcher.sh"
chmod +x "$STAGE_DIR/bin/"*

for lib in "$BUILD_BIN"/*.dylib; do
  cp -P "$lib" "$STAGE_DIR/lib/"
done

cat > "$STAGE_DIR/install.sh" <<'INSTALL'
#!/usr/bin/env zsh

set -e

INSTALL_DIR="${1:-/usr/local/llama-cpp}"
SCRIPT_DIR="${0:A:h}"

echo "Installing optimized llama.cpp to $INSTALL_DIR"
sudo mkdir -p "$INSTALL_DIR"
sudo cp -R "$SCRIPT_DIR/bin" "$INSTALL_DIR/"
sudo cp -R "$SCRIPT_DIR/lib" "$INSTALL_DIR/"
sudo chmod +x "$INSTALL_DIR/bin/"*

echo ""
echo "Installed."
echo "Add this to your shell profile if needed:"
echo "  export PATH=\"$INSTALL_DIR/bin:\$PATH\""
echo ""
echo "Run:"
echo "  $INSTALL_DIR/bin/llama-launcher.sh"
INSTALL
chmod +x "$STAGE_DIR/install.sh"

cat > "$STAGE_DIR/README.md" <<'README'
# intellama — Optimized llama.cpp Build for Intel Mac Pro

This archive contains a pinned llama.cpp build for the **intellama** package
(`npm install -g intellama`). Optimized for Intel x64 Mac Pro hardware.

Build flags:

```text
GGML_AVX=ON
GGML_AVX2=OFF
GGML_FMA=OFF
GGML_F16C=ON
GGML_METAL=OFF
GGML_BLAS=ON
GGML_BLAS_VENDOR=Apple
CFLAGS=-march=ivybridge -mtune=ivybridge
```

Install:

```bash
tar xzf llama-cpp-macpro-optimized.tar.gz
cd llama-cpp-macpro
./install.sh
```

Run the interactive launcher (it is launched via `intellama` once installed):

```bash
intellama
```

…or, if you installed the standalone archive only:

```bash
/usr/local/llama-cpp/bin/llama-launcher.sh
```

Models are not included. Put GGUF files in `~/models` or set `MODELS_DIR`.
README

(
  cd "$ROOT_DIR/.release-staging"
  tar czf "$VENDOR_TARBALL" llama-cpp-macpro
  tar czf "$RELEASE_TARBALL" llama-cpp-macpro
  rm -f "$RELEASE_ZIP"
  zip -qr "$RELEASE_ZIP" llama-cpp-macpro
)

rm -rf "$ROOT_DIR/.release-staging"

echo "Created:"
ls -lh "$VENDOR_TARBALL" "$RELEASE_TARBALL" "$RELEASE_ZIP"
