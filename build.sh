#!/bin/bash

set -eu -o pipefail

## Update fedora docker image tag, because kernel build is using `uname -r` when defining package version variable
RPMBUILD_PATH=/root/rpmbuild
FEDORA_KERNEL_VERSION=5.10.23-200.fc33      # https://bodhi.fedoraproject.org/updates/?search=&packages=kernel&releases=F33
REPO_PWD=$(pwd)

### Debug commands
echo "FEDORA_KERNEL_VERSION=$FEDORA_KERNEL_VERSION"

pwd
echo "CPU threads: $(nproc --all)"
grep 'model name' /proc/cpuinfo | uniq

### Dependencies
dnf install -y fedpkg fedora-packager rpmdevtools ncurses-devel pesign git libkcapi libkcapi-devel libkcapi-static libkcapi-tools zip curl

## Set home build directory
rpmdev-setuptree

## Install the kernel source and finish installing dependencies
cd ${RPMBUILD_PATH}/SOURCES
koji download-build --arch=src kernel-${FEDORA_KERNEL_VERSION}
rpm -Uvh kernel-${FEDORA_KERNEL_VERSION}.src.rpm

cd ${RPMBUILD_PATH}/SPECS
dnf -y builddep kernel.spec

### Create patch file with custom drivers
echo >&2 "===]> Info: Creating patch file... ";
FEDORA_KERNEL_VERSION=${FEDORA_KERNEL_VERSION} ${REPO_PWD}/patch_driver.sh

### Apply patches
echo >&2 "===]> Info: Applying patches... ";
[ ! -d ${REPO_PWD}/patches ] && { echo 'Patches directory not found!'; exit 1; }
while IFS= read -r file
do
  echo "adding $file"
  ${REPO_PWD}/patch_kernel.sh "$file"
done < <(find ${REPO_PWD}/patches -type f -name "*.patch" | sort)

### Change buildid to mbp
echo >&2 "===]> Info: Setting kernel name... ";
sed -i 's/%define buildid.*/%define buildid .mbp/' ${RPMBUILD_PATH}/SPECS/kernel.spec

### Build non-debug rpms
echo >&2 "===]> Info: Bulding kernel ... ";
# ./scripts/fast-build.sh x86_64 "$(find . -type f -name "*.src.rpm")"
rpmbuild --target x86_64 --without debug --without debuginfo --without perf --without tools --rebuild kernel-${FEDORA_KERNEL_VERSION}.src.rpm
rpmbuild_exitcode=$?

### Copy artifacts to shared volume
echo >&2 "===]> Info: Copying rpms and calculating SHA256 ... ";
cp -rfv /root/rpmbuild/RPMS/x86_64/*.rpm /tmp/artifacts/
sha256sum /root/rpmbuild/RPMS/x86_64/*.rpm > /tmp/artifacts/sha256

### Add patches to artifacts
cd ..
zip -r patches.zip patches/
cp -rfv patches.zip /tmp/artifacts/

exit $rpmbuild_exitcode
