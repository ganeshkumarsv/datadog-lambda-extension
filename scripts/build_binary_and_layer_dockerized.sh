#!/bin/bash

# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2021 Datadog, Inc.

# Usage examples :
# ARCHITECTURE=amd64 VERSION=100 RACE_DETECTION_ENABLED=true ./scripts/build_binary_and_layer_dockerized.sh
# or
# VERSION=100 AGENT_VERSION=6.11.0 ./scripts/build_binary_and_layer_dockerized.sh

set -e

if [ -z "$VERSION" ]; then
    echo "Extension version not specified"
    echo ""
    echo "EXITING SCRIPT."
    exit 1
fi

AGENT_PATH="../datadog-agent"

# Move into the root directory, so this script can be called from any directory
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR=$SCRIPTS_DIR/..
cd $ROOT_DIR

EXTENSION_DIR=".layers"
TARGET_DIR=$(pwd)/$EXTENSION_DIR

# Make sure the folder does not exist
rm -rf $EXTENSION_DIR 2>/dev/null

mkdir -p $EXTENSION_DIR

# First prepare a folder with only *mod and *sum files to enable Docker caching capabilities
mkdir -p $ROOT_DIR/scripts/.src $ROOT_DIR/scripts/.cache
echo "Copy mod files to build a cache"
cp $AGENT_PATH/go.mod $ROOT_DIR/scripts/.cache
cp $AGENT_PATH/go.sum $ROOT_DIR/scripts/.cache

echo "Compressing all files to speed up docker copy"
touch $ROOT_DIR/scripts/.src/datadog-agent.tgz
cd $AGENT_PATH/..
tar --exclude=.git -czf $ROOT_DIR/scripts/.src/datadog-agent.tgz datadog-agent
cd $ROOT_DIR

BUILD_FILE=Dockerfile.build
if [ "$RACE_DETECTION_ENABLED" = "true" ]; then
    BUILD_FILE=Dockerfile.race.build
fi

function docker_build_zip {
    arch=$1

    docker buildx build --platform linux/${arch} \
        -t datadog/build-lambda-extension-${arch}:$VERSION \
        -f ./scripts/$BUILD_FILE \
        --build-arg EXTENSION_VERSION="${VERSION}" \
        --build-arg AGENT_VERSION="${AGENT_VERSION}" \
        . --load
    dockerId=$(docker create datadog/build-lambda-extension-${arch}:$VERSION)
    docker cp $dockerId:/datadog_extension.zip $TARGET_DIR/datadog_extension-${arch}.zip
    unzip $TARGET_DIR/datadog_extension-${arch}.zip -d $TARGET_DIR/datadog_extension-${arch}
}

if [ "$ARCHITECTURE" == "amd64" ]; then
    echo "Building for amd64 only"
    docker_build_zip amd64
elif [ "$ARCHITECTURE" == "arm64" ]; then
    echo "Building for arm64 only"
    docker_build_zip arm64
else
    echo "Building for both amd64 and arm64"
    docker_build_zip amd64
    docker_build_zip arm64
fi
