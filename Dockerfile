from ubuntu:bionic
MAINTAINER Carson Harmon <carson.harmon@trailofbits.com>

##########################################################
# Build clang, and then build libcxx/libcxx abi with gclang
# Having our own repo lets us pull from llvm mainstream ez 
# It also debloats other codebases that use this 
##########################################################

# Build clang libs, cxx libs. Export the bin, and cxx libs? 
RUN DEBIAN_FRONTEND=noninteractive apt-get -y update  \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y \
      git                                             \
      ninja-build                                     \
      wget                                            \
      python3.7-dev                                   \
      python3-distutils                               \
      golang                                          \
      clang-10                                        

RUN wget https://github.com/Kitware/CMake/releases/download/v3.19.2/cmake-3.19.2-Linux-x86_64.sh
RUN mkdir -p /usr/bin/cmake-3.19
RUN chmod +x cmake-3.19.2-Linux-x86_64.sh && ./cmake-3.19.2-Linux-x86_64.sh --skip-license --prefix=/usr/bin/cmake-3.19
ENV PATH="/usr/bin/cmake-3.19/bin:${PATH}"
ENV LLVM_CXX_DIR=/polytracker-llvm/llvm

RUN go get github.com/SRI-CSL/gllvm/cmd/...
ENV PATH="$PATH:/root/go/bin"

COPY . /polytracker-llvm
ENV LLVM_DIR=/polytracker-llvm/llvm 

RUN mkdir /cxx_libs && mkdir /polytracker_clang

WORKDIR /polytracker_clang
RUN cmake -GNinja ${LLVM_DIR} \
  -DLLVM_TARGETS_TO_BUILD="X86" \
  -DLLVM_ENABLE_PROJECTS="compiler-rt" \
  -DCMAKE_BUILD_TYPE="Release"

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
  -DCMAKE_BUILD_TYPE="Release" \
  -DLLVM_TARGETS_TO_BUILD="X86" \
  -DLLVM_ENABLE_LIBCXX=ON \
  -DLIBCXXABI_ENABLE_SHARED=NO \
  -DLIBCXX_ENABLE_SHARED=NO \
  -DLIBCXX_CXX_ABI="libcxxabi" \
  -DLLVM_ENABLE_PROJECTS="libcxx;libcxxabi"

ENV WLLVM_BC_STORE=$BITCODE
RUN ninja cxx cxxabi

WORKDIR $CXX_DIR

ENV BITCODE=/cxx_poly_bitcode
RUN mkdir -p $POLY_CXX_DIR && mkdir -p $BITCODE

WORKDIR  $POLY_CXX_DIR

RUN cmake -GNinja ${LLVM_CXX_DIR} \
  -DCMAKE_BUILD_TYPE="Release" \
  -DLLVM_TARGETS_TO_BUILD="X86" \
  -DLLVM_ENABLE_LIBCXX=ON \
  -DLIBCXX_ABI_NAMESPACE="__p" \
  -DLIBCXXABI_ENABLE_SHARED=NO \
  -DLIBCXX_ENABLE_SHARED=NO \
  -DLIBCXX_ABI_VERSION=2 \
  -DLIBCXX_CXX_ABI="libcxxabi" \
  -DLIBCXX_HERMETIC_STATIC_LIBRARY=ON \
  -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
  -DLLVM_ENABLE_PROJECTS="libcxx;libcxxabi"

ENV WLLVM_BC_STORE=$BITCODE
RUN ninja cxx cxxabi



