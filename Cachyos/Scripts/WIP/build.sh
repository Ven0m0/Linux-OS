cargo pgo instrument build -r
hyperfine --prepare "rm -f default_*.profraw" --runs 10 "./target/release/myapp --some-use-case"
cargo pgo merge
cargo pgo optimize build --release
perf merge -o pgo.merged.perf pgo.*.data   # multiple runs

perf record \
  -e cycles:u \
  -g dwarf               \   # DWARF‐based stack unwinding (higher fidelity than frame‐pointer)
  -j any,u               \
  -c 100000              \   # sample every ~100 K cycles for density
  --call-graph dwarf
  --call-graph lbr       \   # use last‑branch‑record (if supported) for precise branch history
  -o pgo-perf.data \
  -- ./target/release/your_app <realistic‑args>
