---
applyTo: "**/*.rs"
---

# Rust Conventions

## General
- **Std**: Idiomatic Rust; strict typing; memory safe.
- **Err**: `Result<T,E>` > `panic!`; custom errors (`thiserror`).
- **Async**: `async/await` w/ `tokio`.
- **Parallel**: `rayon` for data parallelism.
- **Ownership**: Borrow `&T` pref to `clone()`; `Arc` for thread-safe shared.

## Style & Patterns
- **Fmt**: `rustfmt`; `cargo clippy` (0 warnings).
- **Docs**: `///` on pub items; examples included.
- **Traits**: Impl `Debug`, `Display`, `Default`, `From`.
- **Avoid**: `unwrap()`/`expect()` in lib code; unnecessary `unsafe`.

## Organization
- **Struct**: `mod` for encapsulation; `pub` interface; `tests/` dir for integ.
- **Config**: SemVer in Cargo.toml; complete metadata.

## Checklist
- [ ] Naming (RFC 430)?
- [ ] `unwrap` removed?
- [ ] Docs on pub API?
- [ ] Clippy clean?
- [ ] Tests cover edges?
