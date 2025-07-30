#!/bin/bash

# source ~/.config/bash/uv.sh

if command -v uv &>/dev/null; then
  export UV_COMPILE_BYTECODE=1
  export UV_NATIVE_TLS=1
  export UV_CONCURRENT_BUILDS=$(nproc)
  export UV_CONCURRENT_DOWNLOADS=$(( $(nproc) / 2 ))
  export UV_CONCURRENT_INSTALLS=$(nproc)
fi
