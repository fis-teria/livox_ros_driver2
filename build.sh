#!/bin/bash
set -e

readonly VERSION_ROS1="ROS1"
readonly VERSION_ROS2="ROS2"
readonly VERSION_HUMBLE="humble"

determine_memsafe_jobs() {
    if [[ -n "${AMARANTHUS_BUILD_JOBS:-}" ]]; then
        echo "${AMARANTHUS_BUILD_JOBS}"
        return
    fi

    local cpu_count available_kb available_mb jobs
    cpu_count="$(nproc)"
    available_kb="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null)"

    if [[ -z "${available_kb}" ]]; then
        echo 1
        return
    fi

    available_mb=$((available_kb / 1024))

    if (( available_mb < 3072 )); then
        jobs=1
    else
        jobs=$(((available_mb - 1024) / 2048))
        if (( jobs < 1 )); then
            jobs=1
        fi
    fi

    if (( jobs > cpu_count )); then
        jobs="${cpu_count}"
    fi

    if (( jobs > 4 )); then
        jobs=4
    fi

    echo "${jobs}"
}

pushd "$(pwd)" > /dev/null
cd "$(dirname "$0")"
echo "Working Path: $(pwd)"

ROS_VERSION=""
ROS_HUMBLE=""

# Set working ROS version
if [ "$1" = "ROS2" ]; then
    ROS_VERSION=${VERSION_ROS2}
elif [ "$1" = "humble" ]; then
    ROS_VERSION=${VERSION_ROS2}
    ROS_HUMBLE=${VERSION_HUMBLE}
elif [ "$1" = "ROS1" ]; then
    ROS_VERSION=${VERSION_ROS1}
else
    echo "Invalid Argument"
    exit
fi
echo "ROS version is: "$ROS_VERSION

BUILD_JOBS="$(determine_memsafe_jobs)"
BUILD_LOAD_LIMIT="${AMARANTHUS_BUILD_LOAD_LIMIT:-${BUILD_JOBS}}"
COLCON_PARALLEL_WORKERS="${AMARANTHUS_COLCON_PARALLEL_WORKERS:-1}"

export MAKEFLAGS="-j${BUILD_JOBS} -l${BUILD_LOAD_LIMIT}"

echo "Using memory-safe build settings: parallel workers=${COLCON_PARALLEL_WORKERS}, make jobs=${BUILD_JOBS}, load limit=${BUILD_LOAD_LIMIT}"

# clear `build/` folder.
# TODO: Do not clear these folders, if the last build is based on the same ROS version.
rm -rf ../../build/
rm -rf ../../devel/
rm -rf ../../install/
# clear src/CMakeLists.txt if it exists.
if [ -f ../CMakeLists.txt ]; then
    rm -f ../CMakeLists.txt
fi

# exit

# substitute the files/folders: CMakeList.txt, package.xml(s)
if [ ${ROS_VERSION} = ${VERSION_ROS1} ]; then
    if [ -f package.xml ]; then
        rm package.xml
    fi
    cp -f package_ROS1.xml package.xml
elif [ ${ROS_VERSION} = ${VERSION_ROS2} ]; then
    if [ -f package.xml ]; then
        rm package.xml
    fi
    cp -f package_ROS2.xml package.xml
    cp -rf launch_ROS2/ launch/
fi

# build
pushd "$(pwd)" > /dev/null
if [ $ROS_VERSION = ${VERSION_ROS1} ]; then
    cd ../../
    catkin_make -DROS_EDITION=${VERSION_ROS1} -j"${BUILD_JOBS}" -l"${BUILD_LOAD_LIMIT}"
elif [ $ROS_VERSION = ${VERSION_ROS2} ]; then
    cd ../../../
    colcon build \
        --executor sequential \
        --parallel-workers "${COLCON_PARALLEL_WORKERS}" \
        --symlink-install \
        --cmake-args -DROS_EDITION=${VERSION_ROS2} -DHUMBLE_ROS=${ROS_HUMBLE} -DCMAKE_BUILD_TYPE=Release
fi
popd > /dev/null

# remove the substituted folders/files
if [ $ROS_VERSION = ${VERSION_ROS2} ]; then
    rm -rf launch/
fi

popd > /dev/null
