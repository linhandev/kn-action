#!/bin/bash
# Copyright (c) 2024 Huawei Device Co., Ltd.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Merge Linux x86_64 OHOS bits into Darwin clang installs (no Windows; no extra OHOS/Linux AArch64 clang packages).
# CLANG_RESOURCE_VERSION must match lib/clang/<ver> in the toolchain (e.g. 19).

set -euo pipefail

: "${CLANG_RESOURCE_VERSION:=19}"

commit_id=""
date="$(date '+%Y-%m-%dT%H:%M:%S')"

clang_linux_x86_64_tar="clang-dev-linux-x86_64.tar.gz"
clang_darwin_arm64_tar="clang-dev-darwin-arm64.tar.gz"
clang_darwin_x86_64_tar="clang-dev-darwin-x86_64.tar.gz"
libcxx_ndk_linux_x86_64_tar="libcxx-ndk-dev-linux-x86_64.tar.gz"
libcxx_ndk_darwin_x86_64_tar="libcxx-ndk-dev-darwin-x86_64.tar.gz"
libcxx_ndk_darwin_arm64_tar="libcxx-ndk-dev-darwin-arm64.tar.gz"
libcxx_ndk_linux_aarch64_tar="libcxx-ndk-dev-linux-aarch64.tar.gz"

clang_linux_x86_64="clang_linux-x86_64-${commit_id}-${date}"
clang_darwin_arm64="clang_darwin-arm64-${commit_id}-${date}"
clang_darwin_x86_64="clang_darwin-x86_64-${commit_id}-${date}"
libcxx_ndk_linux_x86_64="libcxx-ndk_linux-x86_64-${commit_id}-${date}"
libcxx_ndk_darwin_x86_64="libcxx-ndk_darwin-x86_64-${commit_id}-${date}"
libcxx_ndk_darwin_arm64="libcxx-ndk_darwin-arm64-${commit_id}-${date}"
libcxx_ndk_ohos_arm64="libcxx_ndk_ohos-arm64-${commit_id}-${date}"
libcxx_ndk_linux_aarch64="libcxx-ndk_linux-aarch64-${commit_id}-${date}"
llvm_list=($clang_linux_x86_64 $clang_darwin_arm64 $clang_darwin_x86_64 $libcxx_ndk_linux_x86_64 $libcxx_ndk_darwin_x86_64 $libcxx_ndk_darwin_arm64 $libcxx_ndk_ohos_arm64 $libcxx_ndk_linux_aarch64)

V="${CLANG_RESOURCE_VERSION}"

# decompress file and rename
tar -xf ${clang_linux_x86_64_tar}
mv clang-dev ${clang_linux_x86_64}
tar -xf ${clang_darwin_arm64_tar}
mv clang-dev ${clang_darwin_arm64}
tar -xf ${clang_darwin_x86_64_tar}
mv clang-dev ${clang_darwin_x86_64}
tar -xf ${libcxx_ndk_linux_x86_64_tar}
mv libcxx-ndk ${libcxx_ndk_linux_x86_64}
tar -xf ${libcxx_ndk_darwin_x86_64_tar}
mv libcxx-ndk ${libcxx_ndk_darwin_x86_64}
tar -xf ${libcxx_ndk_darwin_arm64_tar}
mv libcxx-ndk ${libcxx_ndk_darwin_arm64}
cp -a ${libcxx_ndk_linux_x86_64} ${libcxx_ndk_ohos_arm64}
tar -xf ${libcxx_ndk_linux_aarch64_tar}
mv libcxx-ndk ${libcxx_ndk_linux_aarch64}

#clang-dev-darwin-arm64
cp -rf ${clang_linux_x86_64}/lib/aarch64-linux-ohos ${clang_darwin_arm64}/lib
cp -rf ${clang_linux_x86_64}/lib/arm-liteos-ohos ${clang_darwin_arm64}/lib
cp -rf ${clang_linux_x86_64}/include/libcxx-ohos ${clang_darwin_arm64}/include
cp -rf ${clang_linux_x86_64}/lib/arm-linux-ohos ${clang_darwin_arm64}/lib
if [ -d "${clang_linux_x86_64}/lib/loongarch64-linux-ohos" ]; then
	cp -rf ${clang_linux_x86_64}/lib/loongarch64-linux-ohos ${clang_darwin_arm64}/lib
fi
cp -rf ${clang_linux_x86_64}/lib/x86_64-linux-ohos ${clang_darwin_arm64}/lib
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/bin ${clang_darwin_arm64}/lib/clang/${V}
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/include/profile ${clang_darwin_arm64}/lib/clang/${V}/include
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/include/fuzzer ${clang_darwin_arm64}/lib/clang/${V}/include
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/share ${clang_darwin_arm64}/lib/clang/${V}
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/include/sanitizer ${clang_darwin_arm64}/lib/clang/${V}/include
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/lib ${clang_darwin_arm64}/lib/clang/${V}

#clang-dev-darwin-x86_64
cp -rf ${clang_linux_x86_64}/lib/aarch64-linux-ohos ${clang_darwin_x86_64}/lib
cp -rf ${clang_linux_x86_64}/lib/arm-liteos-ohos ${clang_darwin_x86_64}/lib
cp -rf ${clang_linux_x86_64}/lib/arm-linux-ohos ${clang_darwin_x86_64}/lib
cp -rf ${clang_linux_x86_64}/lib/x86_64-linux-ohos ${clang_darwin_x86_64}/lib
if [ -d "${clang_linux_x86_64}/lib/loongarch64-linux-ohos" ]; then
	cp -rf ${clang_linux_x86_64}/lib/loongarch64-linux-ohos ${clang_darwin_x86_64}/lib
fi
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/bin ${clang_darwin_x86_64}/lib/clang/${V}
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/share ${clang_darwin_x86_64}/lib/clang/${V}
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/lib ${clang_darwin_x86_64}/lib/clang/${V}
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/include/profile ${clang_darwin_x86_64}/lib/clang/${V}/include
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/include/fuzzer ${clang_darwin_x86_64}/lib/clang/${V}/include
cp -rf ${clang_linux_x86_64}/lib/clang/${V}/include/sanitizer ${clang_darwin_x86_64}/lib/clang/${V}/include
cp -rf ${clang_linux_x86_64}/include/libcxx-ohos ${clang_darwin_x86_64}/include

#archive
mkdir target_location
function package_llvm(){
for i in ${llvm_list[@]}
do
	tar zcf target_location/${i}.tar.gz ${i}
	sha256sum target_location/${i}.tar.gz |awk '{print $1}' > target_location/${i}.tar.gz.sha256
done
}

package_llvm
