#!/usr/bin/env bash

set -e

MY_PATH="$(dirname -- "${BASH_SOURCE[0]}")"
cd ${MY_PATH}

# Local installation
BUNDLE_PATH=${BUNDLE_PATH:-"lib"}
mkdir -p ${BUNDLE_PATH}
BUNDLE_PATH=$(realpath ${BUNDLE_PATH})

touch .paths
source env.sh

RUBY_VERSION=$(ruby --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
echo "export GEM_PATH=\${GEM_PATH}:${BUNDLE_PATH}/ruby/${RUBY_VERSION}" > ./.paths
echo "export PATH=\${PATH}:$(realpath bin)" >> ./.paths

echo "Installing bundle"
bundle config set --local path "lib"
bundle install
gem install --install-dir ${BUNDLE_PATH}/ruby/${RUBY_VERSION} gli

echo "Downloading submodules"
git submodule update --init

echo "Installing ncn"
mkdir -p build/ncn
source gitmodules/ncn/env.sh
cd build/ncn
cmake -DBUILD_SHARED_LIBS=ON -DCMAKE_BUILD_TYPE=Release ../../gitmodules/ncn
make
cp ncn ../../bin
