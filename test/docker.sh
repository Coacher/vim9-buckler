#!/usr/bin/env bash
# Builds the test image for one base image and runs the suite inside it,
# the same way the GitHub workflow does.
#
# Usage: test/docker.sh BASE_IMAGE
#
# Environment:
#   DOCKER_NETWORK  network for the image build, default: the builder's own
#   RESULTS         directory for reports, default: test/results/<image>
#   CASES, MATRICES, CONFIGS, DISPLAYS, VERBOSE, TIMEOUT  passed to run.sh

set -eu

image=${1:?usage: test/docker.sh BASE_IMAGE}
test_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(dirname "$test_dir")
name=$(printf '%s' "$image" | tr -c 'a-zA-Z0-9_.\n-' '-')
tag="vim9-buckler-test:$name"
results=${RESULTS:-$test_dir/results/$name}

# BuildKit knows no "bridge" network, so the builder picks one unless told
docker build ${DOCKER_NETWORK:+--network "$DOCKER_NETWORK"} --build-arg "BASE=$image" \
    --tag "$tag" --file "$test_dir/Dockerfile" "$test_dir"

mkdir -p "$results"
# Xwayland admits local clients only when it can resolve their user name
passwd=$(mktemp)
trap 'rm -f "$passwd"' EXIT
printf 'root:x:0:0::/root:/bin/sh\nbuckler:x:%s:%s::/tmp:/bin/sh\n' "$(id -u)" "$(id -g)" >"$passwd"
docker run --rm --network none --user "$(id -u):$(id -g)" \
    --volume "$repo_dir:/src:ro" --volume "$results:/results" \
    --volume "$passwd:/etc/passwd:ro" \
    --env RESULTS=/results --env CASES --env MATRICES --env CONFIGS \
    --env DISPLAYS --env VERBOSE --env TIMEOUT \
    "$tag" bash -c '. /etc/buckler-test.env && export VIM_BIN GVIM_BIN && exec /src/test/run.sh'
