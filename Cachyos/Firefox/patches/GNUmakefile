srcdir := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

dirs =
patches = svg-rendering 0005-disable-pocket 0029-LTO-Only-enable-LTO-for-Rust-when-complete-build-use devtools-bypass JXL_enable_by_default llvmorg-19-init-7654-gc23135c5488f revert-llvmorg-18-init-5259-g5d7f84ee17f3 cargo-vendor-std-1.79 rust-vendor-std clang-8-missing-header clang-tidy-ci llvmorg-10-init-136-gb288d90b39f4 Remove-FlushViewOfFile-when-unmaping-gcda-files

include $(srcdir)/../../assets/patches.mk
