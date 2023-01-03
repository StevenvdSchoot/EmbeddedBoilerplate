FROM fedora:37 as base

RUN dnf install -y \
	python \
	vim \
	git \
	llvm \
	clang \
	clang-tools-extra \
	lld \
	polly \
	clang-analyzer \
	cppcheck \
	american-fuzzy-lop-clang \
	git-clang-format \
	ninja-build \
	cmake \
	meson \
	gdb \
	qemu-system-arm \
	rpm-build \
	vcpkg \
	conan

COPY clang-wrapper /usr/bin/clang-wrapper

RUN ln -s clang-wrapper /usr/bin/armv7m-none-eabi-clang \
 && ln -s clang-wrapper /usr/bin/armv7m-none-eabi-clang++ \
 && ln -s clang-wrapper /usr/bin/thumb7m-none-eabi-clang \
 && ln -s clang-wrapper /usr/bin/thumb7m-none-eabi-clang++

FROM base as build

RUN mkdir /src

COPY cross-clang-thumbv7m-none-eabi.txt 0001-Fix-linking-with-clang-and-crt.patch 0001-Rewrite-__eabi_read_tp-in-c.patch 0001-Remove-duplicate-aliases.patch 0001-Disable-ffunction-sections.patch 0001-Modify-picolibc-.ld-to-support-embedded-env.patch 0001-Extend-debugging-prints-in-crt0.patch /src/

RUN cd /src \
 && git clone --depth 1 -b 1.8 https://github.com/picolibc/picolibc.git \
 && GIT_COMMITTER_NAME="Steven van der Schoot" GIT_COMMITTER_EMAIL="stevenvdschoot@gmail.com" git -C /src/picolibc am --committer-date-is-author-date /src/0001-Rewrite-__eabi_read_tp-in-c.patch /src/0001-Remove-duplicate-aliases.patch /src/0001-Disable-ffunction-sections.patch /src/0001-Modify-picolibc-.ld-to-support-embedded-env.patch /src/0001-Extend-debugging-prints-in-crt0.patch \
 && mkdir /src/picolibc/build \
 && cd /src/picolibc/build \
 && meson .. \
	--cross-file ../../cross-clang-thumbv7m-none-eabi.txt \
	-Dmultilib=false \
	-Db_staticpic=true \
	-Db_lto=true \
	-Db_lto_mode=thin \
	-Dbuildtype=release \
	-Ddebug=true \
	-Db_ndebug=false \
 && ninja \
 && DESTDIR=/src/picolibc/install ninja install \
 && mkdir -p /usr/lib/clang-runtimes/thumbv7m-none-eabi \
 && ln -s thumbv7m-none-eabi /usr/lib/clang-runtimes/armv7m-none-eabi \
 && cp -a ../install/usr/local/include/ /usr/lib/clang-runtimes/thumbv7m-none-eabi/include \
 && cp -a ../install/usr/local/lib/ /usr/lib/clang-runtimes/thumbv7m-none-eabi/lib \
 && mv /usr/lib/clang-runtimes/thumbv7m-none-eabi/lib/libc.a /usr/lib/clang-runtimes/thumbv7m-none-eabi/lib/actuallibc.a \
 && mv /usr/lib/clang-runtimes/thumbv7m-none-eabi/lib/picolibcpp.ld /usr/lib/clang-runtimes/thumbv7m-none-eabi/lib/libc.a \
 && find /src/picolibc/build/picocrt/ -mindepth 1 -maxdepth 1 -type d -name "crt0*" -exec basename {} \; | sed 's#\(.*\).p#cp /src/picolibc/build/picocrt/\1.p/*.o /usr/lib/clang-runtimes/armv7m-none-eabi/lib/\1#' | sh \
 && mkdir -p /install/usr/lib/clang-runtimes/armv7m-none-eabi \
 && ln -s armv7m-none-eabi /install/usr/lib/clang-runtimes/thumbv7m-none-eabi \
 && cp -a ../install/usr/local/include/ /install/usr/lib/clang-runtimes/armv7m-none-eabi/include \
 && cp -a ../install/usr/local/lib/ /install/usr/lib/clang-runtimes/armv7m-none-eabi/lib \
 && mv /install/usr/lib/clang-runtimes/armv7m-none-eabi/lib/libc.a /install/usr/lib/clang-runtimes/armv7m-none-eabi/lib/actuallibc.a \
 && mv /install/usr/lib/clang-runtimes/armv7m-none-eabi/lib/picolibcpp.ld /install/usr/lib/clang-runtimes/armv7m-none-eabi/lib/libc.a \
 && find /src/picolibc/build/picocrt/ -mindepth 1 -maxdepth 1 -type d -name "crt0*" -exec basename {} \; | sed 's#\(.*\).p#cp /src/picolibc/build/picocrt/\1.p/*.o /install/usr/lib/clang-runtimes/armv7m-none-eabi/lib/\1#' | sh

COPY 0001-fix-missing-alloca.h-include.patch 0002-Disable-LTO-for-libcxxabi-and-libunwind.patch 0001-Remove-fno-lto-for-compilerrt.patch /src/

RUN dnf install -y llvm-devel \
 && cd /src \
 && git clone --depth 1 -b llvmorg-$(llvm-tblgen --version | sed -n 's/^.*LLVM version \([0-9]*\)\.\([0-9]*\)\.\([0-9]*\).*$/\1.\2.\3/p') https://github.com/llvm/llvm-project.git \
 && GIT_COMMITTER_NAME="Steven van der Schoot" GIT_COMMITTER_EMAIL="stevenvdschoot@gmail.com" git -C /src/llvm-project am --committer-date-is-author-date /src/0001-fix-missing-alloca.h-include.patch /src/0001-Remove-fno-lto-for-compilerrt.patch


RUN cd /src/llvm-project \
 && cmake -S compiler-rt \
	-B build-compiler-rt \
	-G Ninja \
	-DCMAKE_BUILD_TYPE=RelWithDebInfo \
	-DCMAKE_C_FLAGS_RELWITHDEBINFO="-Oz -fno-lto -g -DNDEBUG" \
	-DCMAKE_ASM_FLAGS_RELWITHDEBINFO="-Oz -fno-lto -g -DNDEBUG" \
	-DCMAKE_SHARED_LINKER_FLAGS_MINSIZEREL="-Oz" \
	-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF \
	-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
	-DCOMPILER_RT_OS_DIR="baremetal" \
	-DCOMPILER_RT_BUILD_BUILTINS=ON \
	-DCOMPILER_RT_BUILD_SANITIZERS=ON \
	-DCOMPILER_RT_BUILD_XRAY=OFF \
	-DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
	-DCOMPILER_RT_BUILD_PROFILE=OFF \
	-DCOMPILER_RT_BAREMETAL_BUILD=ON \
	-DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
	-DLLVM_CONFIG_PATH=$(which llvm-config) \
	-DCMAKE_ASM_COMPILER=/usr/bin/armv7m-none-eabi-clang \
	-DCMAKE_C_COMPILER=/usr/bin/clang \
	-DCMAKE_C_COMPILER_TARGET=armv7m-none-eabi \
	-DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
	-DCMAKE_CXX_COMPILER_TARGET=armv7m-none-eabi \
	-DCMAKE_AR=/usr/bin/llvm-ar \
	-DCMAKE_NM=/usr/bin/llvm-nm \
	-DCMAKE_RANLIB=/usr/bin/llvm-ranlib \
 && cmake --build build-compiler-rt \
 && cp build-compiler-rt/lib/baremetal/libclang_rt.builtins-armv7m.a /usr/lib/clang-runtimes/armv7m-none-eabi/lib \
 && ln -s libclang_rt.builtins-armv7m.a /usr/lib/clang-runtimes/armv7m-none-eabi/lib/libclang_rt.builtins-thumb7m.a \
 && cp build-compiler-rt/lib/baremetal/libclang_rt.builtins-armv7m.a /install/usr/lib/clang-runtimes/armv7m-none-eabi/lib \
 && ln -s libclang_rt.builtins-armv7m.a /install/usr/lib/clang-runtimes/armv7m-none-eabi/lib/libclang_rt.builtins-thumb7m.a

COPY llvm-CMakeLists.txt /src/llvm-project/CMakeLists.txt
RUN cd /src/llvm-project \
 && cmake -B build-libcxx \
	-G Ninja \
	-DCMAKE_BUILD_TYPE=RelWithDebInfo \
	-DCMAKE_INSTALL_PREFIX=/usr/lib/clang-runtimes/armv7m-none-eabi \
	-DCMAKE_C_FLAGS_RELWITHDEBINFO="-Oz -g -DNDEBUG -D_GNU_SOURCE" \
	-DCMAKE_CXX_FLAGS_RELWITHDEBINFO="-Oz -g -DNDEBUG -D_GNU_SOURCE" \
	-DCMAKE_ASM_FLAGS_RELWITHDEBINFO="-Oz -flto=thin -g -DNDEBUG -D_GNU_SOURCE" \
	-DCMAKE_SHARED_LINKER_FLAGS_MINSIZEREL="-Oz" \
	-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
	-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
	-DCMAKE_MODULE_PATH=/usr/lib64/cmake/llvm/ \
	-DCMAKE_ASM_COMPILER=/usr/bin/armv7m-none-eabi-clang \
	-DCMAKE_C_COMPILER=/usr/bin/clang \
	-DCMAKE_C_COMPILER_TARGET=armv7m-none-eabi \
	-DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
	-DCMAKE_CXX_COMPILER_TARGET=armv7m-none-eabi \
	-DCMAKE_AR=/usr/bin/llvm-ar \
	-DCMAKE_NM=/usr/bin/llvm-nm \
	-DCMAKE_RANLIB=/usr/bin/llvm-ranlib \
	-DLIBCXX_INCLUDE_BENCHMARKS=OFF \
	-DLIBCXX_STATICALLY_LINK_ABI_IN_STATIC_LIBRARY=ON \
	-DLIBCXX_ENABLE_STATIC=ON \
	-DLIBCXX_ENABLE_SHARED=OFF \
	-DLIBCXX_ENABLE_THREADS=OFF \
	-DLIBCXX_ENABLE_MONOTONIC_CLOCK=OFF \
	-DLIBCXX_ENABLE_EXPERIMENTAL_LIBRARY=NO \
	-DLIBCXX_ENABLE_FILESYSTEM=OFF \
	-DLIBCXX_ENABLE_LOCALIZATION=OFF \
	-DLIBCXX_CXX_ABI=libcxxabi \
	-DLIBCXX_INCLUDE_TESTS=OFF \
	-DLIBCXX_INCLUDE_BENCHMARKS=OFF \
	-DLIBCXX_INCLUDE_DOCS=OFF \
	-DLIBCXXABI_BAREMETAL=ON \
	-DLIBCXXABI_SILENT_TERMINATE=ON \
	-DLIBCXXABI_ENABLE_STATIC=ON \
	-DLIBCXXABI_ENABLE_SHARED=OFF \
	-DLIBCXXABI_INCLUDE_TESTS=OFF \
	-DLIBCXXABI_ENABLE_THREADS=OFF \
	-DLIBUNWIND_IS_BAREMETAL=ON \
	-DLIBUNWIND_ENABLE_STATIC=ON \
	-DLIBUNWIND_ENABLE_SHARED=OFF \
	-DLIBUNWIND_ENABLE_THREADS=OFF \
	-DLIBUNWIND_USE_COMPILER_RT=ON \
	-DLIBUNWIND_INCLUDE_DOCS=OFF \
	-DLIBUNWIND_INCLUDE_TESTS=OFF \
 && cmake --build build-libcxx \
 && cmake --install build-libcxx \
 && DESTDIR=/install cmake --install build-libcxx

RUN cd /src \
 && git clone https://github.com/bnahill/PyCortexMDebug.git \
 && cd PyCortexMDebug \
 && dnf install -y pip \
 && python -m pip install --root=/install . \
 && mkdir -p /install/usr/share/gdb/auto-load/usr/lib64/ \
 && cp scripts/gdb.py /install/usr/share/gdb/auto-load/usr/lib64/pyCortexMDebug.py

RUN cd /src \
 && git clone https://github.com/ARM-software/CMSIS.git \
 && mkdir -p /install/usr/share/svd \
 && cp -a CMSIS/Device/ARM/SVD/*.svd /install/usr/share/svd

FROM base
LABEL dev.steveos.emb.authors="stevenvdschoot@gmail.com"

COPY --from=build /install /

