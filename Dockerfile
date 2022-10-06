FROM ubuntu:jammy AS builder-base
##########################################################
# Build clang, and then build libcxx/libcxx abi with gclang
# Having our own repo lets us pull from llvm mainstream ez
# It also debloats other codebases that use this
##########################################################

ARG BUILD_TYPE="Release"
ARG PARALLEL_LINK_JOBS=1
ARG TARGETARCH


# ARM64/AArch64 platform specific settings
FROM builder-base AS builder-arm64
ARG LLVM_TARGET_NAME=AArch64
ARG CMAKE_FILENAME_ARCH=aarch64
ARG DFSAN_FILENAME_ARCH=aarch64

# AMD64/X86_64 platform specific settings
FROM builder-base AS builder-amd64
ARG LLVM_TARGET_NAME=X86
ARG CMAKE_FILENAME_ARCH=x86_64
ARG DFSAN_FILENAME_ARCH=x86_64

FROM builder-$TARGETARCH AS builder

# Build clang libs, cxx libs. Export the bin, and cxx libs?
RUN DEBIAN_FRONTEND=noninteractive apt-get -y update  \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y \
      git                                             \
      ninja-build                                     \
      wget                                            \
      python3.8-dev                                   \
      python3-distutils                               \
      golang                                          \
      clang-11

RUN wget https://github.com/Kitware/CMake/releases/download/v3.20.5/cmake-3.20.5-Linux-${CMAKE_FILENAME_ARCH}.sh
RUN mkdir -p /usr/bin/cmake-3.20
RUN chmod +x cmake-3.20.5-Linux-${CMAKE_FILENAME_ARCH}.sh && ./cmake-3.20.5-Linux-${CMAKE_FILENAME_ARCH}.sh --skip-license --prefix=/usr/bin/cmake-3.20
ENV PATH="/usr/bin/cmake-3.20/bin:${PATH}"
ENV LLVM_CXX_DIR=/polytracker-llvm/llvm

RUN GO111MODULE=off go get github.com/SRI-CSL/gllvm/cmd/...
ENV PATH="$PATH:/root/go/bin"

COPY . /polytracker-llvm
ENV LLVM_DIR=/polytracker-llvm/llvm

RUN mkdir /cxx_libs && mkdir /polytracker_clang

WORKDIR /polytracker_clang
RUN cmake -GNinja ${LLVM_DIR} \
  -DLLVM_TARGETS_TO_BUILD="${LLVM_TARGET_NAME}" \
  -DLLVM_ENABLE_PROJECTS="clang;llvm;compiler-rt" \
  -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
  -DLLVM_PARALLEL_LINK_JOBS=${PARALLEL_LINK_JOBS}

RUN ninja install
ENV PATH="$PATH:/polytracker_clang/bin"
RUN clang --version
# Build two copies of cxx lib
ENV CXX_DIR=/cxx_libs
ENV LLVM_CXX_DIR=/polytracker-llvm/llvm
ENV CLEAN_CXX_DIR=$CXX_DIR/clean_build
ENV BITCODE=/cxx_clean_bitcode
ENV POLY_CXX_DIR=$CXX_DIR/poly_build
ENV CC="gclang"
ENV CXX="gclang++"

RUN mkdir -p $CXX_DIR
WORKDIR $CXX_DIR

RUN mkdir -p $CLEAN_CXX_DIR && mkdir -p $BITCODE
WORKDIR $CLEAN_CXX_DIR

RUN cmake -GNinja ${LLVM_CXX_DIR} \
  -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
  -DLLVM_TARGETS_TO_BUILD="${LLVM_TARGET_NAME}" \
  -DLLVM_ENABLE_LIBCXX=ON \
  -DLIBCXXABI_ENABLE_SHARED=NO \
  -DLIBCXX_ENABLE_SHARED=NO \
  -DLIBCXX_CXX_ABI="libcxxabi" \
  -DLLVM_ENABLE_PROJECTS="libcxx;libcxxabi" \
  -DLLVM_PARALLEL_LINK_JOBS=${PARALLEL_LINK_JOBS}

ENV WLLVM_BC_STORE=$BITCODE
RUN ninja cxx cxxabi

WORKDIR $CXX_DIR

ENV BITCODE=/cxx_poly_bitcode
RUN mkdir -p $POLY_CXX_DIR && mkdir -p $BITCODE

WORKDIR  $POLY_CXX_DIR

RUN cmake -GNinja ${LLVM_CXX_DIR} \
  -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
  -DLLVM_TARGETS_TO_BUILD="${LLVM_TARGET_NAME}" \
  -DLLVM_ENABLE_LIBCXX=ON \
  -DLIBCXX_ABI_NAMESPACE="__p" \
  -DLIBCXXABI_ENABLE_SHARED=NO \
  -DLIBCXX_ENABLE_SHARED=NO \
  -DLIBCXX_ABI_VERSION=2 \
  -DLIBCXX_CXX_ABI="libcxxabi" \
  -DLIBCXX_HERMETIC_STATIC_LIBRARY=ON \
  -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
  -DLLVM_ENABLE_PROJECTS="libcxx;libcxxabi" \
  -DLLVM_PARALLEL_LINK_JOBS=${PARALLEL_LINK_JOBS}

ENV WLLVM_BC_STORE=$BITCODE
RUN ninja cxx cxxabi

# We don't need the test directory, and it is large
RUN rm -rf /polytracker-llvm/llvm/test


# Inherit from builder-$TARGETARCH for DFSAN_FILENAME_ARCH arg. Not inheriting the build artifacts in builder.
FROM builder-$TARGETARCH AS polytracker-llvm
MAINTAINER Evan Sultanik <evan.sultanik@trailofbits.com>
MAINTAINER Carson Harmon <carson.harmon@trailofbits.com>

RUN DEBIAN_FRONTEND=noninteractive apt-get -y update  \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y \
      cmake                                           \
      git                                             \
      golang

RUN GO111MODULE=off go get github.com/SRI-CSL/gllvm/cmd/...

# Clang and LLVM binaries with our DFSan mods
COPY --from=builder /polytracker_clang /polytracker_clang
# Contains libcxx for target, and polytracker private libcxx
COPY --from=builder /cxx_libs /cxx_libs
# Contains gclang produced bitcode for libcxx. For libcxx instrumentation
COPY --from=builder /cxx_clean_bitcode /cxx_clean_bitcode
# Contains LLVM headers used to build polytracker
COPY --from=builder /polytracker-llvm/llvm /polytracker-llvm/llvm

WORKDIR /
RUN mkdir /build_artifacts

ENV DFSAN_LIB_PATH=/polytracker_clang/lib/clang/13.0.0/lib/linux/libclang_rt.dfsan-${DFSAN_FILENAME_ARCH}.a
ENV CXX_LIB_PATH=/cxx_libs
ENV WLLVM_BC_STORE=/cxx_clean_bitcode
ENV WLLVM_ARTIFACT_STORE=/build_artifacts
ENV POLYTRACKER_CAN_RUN_NATIVELY=1
ENV PATH="/polytracker_clang/bin:/root/go/bin:${PATH}"
