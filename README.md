Boilerplate project for embedded c++ projects
=============================================

This project is intended to create a high quality C++ programming environment for micro controllers.

The goals for en environment are:
 * Correct (The implementation should comply to all applicable standards, like the C++ standard)
 * Zero overhead (a hand written should not be more efficient)
 * No effort (It should take no effort to start a new embedded C++ project based on this boilerplate project)

Currently the project is focused on ARM Cortex-M based micro controllers. In future other architectures should be included.


Design
------

The boilerplate project consists of a [development container](https://containers.dev) and the necessary files to include it in development containers compatible IDEs.

### Development container
A [development container](https://containers.dev) is a [docker](https://www.docker.com) or [podman](https://podman.io) container that contains everything necessary to build, run and test an application under development. It is accompanied by a definition that instruct a compatible IDE on how to use the container.

### Compiler toolchain
The compiler toolchain used in this project is [llvm](https://llvm.org) based. [Clang](https://clang.llvm.org) is used to compile source files and [lld](https://lld.llvm.org) is used to link everything together.
When compiling for ARM Cortex-M3 micro controllers clang can be invoked as `armv7m-none-eabi-clang` or `armv7m-none-eabi-clang++`. This name is similar to the name for GCC based cross compilers in various Linux distributions.

Compiler-RT is used as implementation of compiler intrinsics (buildins). However, at the moment sanitizer, xray, libfuzzer and profile support are disabled.

### C++ standard library
As the C++ standard library implementation LLVM's [libc++](https://libcxx.llvm.org) is used. However, as of now threading, monotonic clock, file system and localization support are disabled. Since localization support is a requirement for the streaming class implementations (like std::ostream, std::fstream, std::stringstream and instantiaions like std::cout), these are inaccessible as well.

### C standard library
Libc++ depends on C standard library implementation. For this [picolibc](https://keithp.com/picolibc) is used, with some small changes.

To simplify usage of this development container, picolibcpp.ld is always used as a linker script, without the user specifying it. Additionally some duplicate symbols with Compiler-RT are removed and instead of placing every function in its own section, link time optimization is enabled.
Furthermore the debug information printed by crt0 on a CPU exception is extended.

### Link time optimization
All components of both the C and C++ standard library are compiled with link time optimizations enabled. This allows the linker to only include the parts of the standard libraries that are actually used in the final program.

Unfortunately clang does not support emitting LLVM-IR for ARMv7m assembly input files. To support assembly file to still partake in link time optimization a wrapper for clang, called clang-wrapper, is included. This tool will check if one or more input files are assembly files and if so will convert them into c files, while preserving links to the original assembly source files (for debugging).

TODO
----

Contribution are more than welcome!. A few suggestions on what to work on are listed here, but this is by no means an exhaustive list. Any changes that make the project better are welcome.
Please, submit any open changes to [GerritHub](https://review.gerrithub.io/q/project:StevenvdSchoot/EmbeddedBoilerplate). A list of open changes can be found on [https://review.gerrithub.io/q/status:open+-is:wip+project:StevenvdSchoot/EmbeddedBoilerplate](https://review.gerrithub.io/q/status:open+-is:wip+project:StevenvdSchoot/EmbeddedBoilerplate)

### Add development container definition files

At the moment only the dockerfile for the development container is included, the definition file, that instruct an IDE how to use this container, is missing.

### Add example projects

Add at least one example project showing how to create a simple embedded C++ projects based on this boilerplate project.

### Add CI/CD

Container images should automatically be build for both docker and podman.

### clang-wrapper

This project relies on link time optimization to ensure the final program contains only the code necessary to run. At the moment upstream LLVM is plagued by [Issue 57207](https://github.com/llvm/llvm-project/issues/57207). In short, this results in linking with a static archive that contains both bitcode objects files and ELF object files may not work. In particular, linking with picolibc or libc++ where all object files compiled from assembly files are ELF file and compiled from c or c++ files are bitcode files does not work. To work around this issue small python script, clang-wrapper, is included that will convert assembly files into c (with gnu extensions) files and invokes clang on the generated c files. As a result object files generated from assembly file, that are compiled with the `-flto` of `-flto=thin` flags, are now bitcode files as well.

This workaround, however, is not ideal. This behaviour may be very unexpected for the end user. Also the implementation of this wrapper required some hacks that may have unintended consequences. Preferably we modify (upstream) clang to emit LLVM-IR when `-flto` is used.

### Testing

A lot of testing is needed. A wide range of test program should be included in this repository to test the toolchain in different modes, the c and c++ standard library (including runtime time information and exceptions). These test should be executed on an emulator (like [qemu](https://www.qemu.org/)) and be executed as part of a CI/CD pipeline.

### Support sanitizers

Currently clang does not include any sanitizers in its list of supported features for baremetal targets (`BareMetal` in [clang/lib/Driver/ToolChains/BareMetal.cpp](https://github.com/llvm/llvm-project/tree/main/clang/lib/Driver/ToolChains/BareMetal.cpp) does not overload `ToolChain::getSupportedSanitizers`). It is unclear whether they actually don't work.

### Exceptions

At the moment throwing (or catching) exceptions seems broken. It needs to be investigated what the issues is and how to solve it.

