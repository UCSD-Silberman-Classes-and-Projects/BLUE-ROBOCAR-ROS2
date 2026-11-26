#!/usr/bin/env bash
# run.sh — start the rover container without Docker Compose.
#
#   docker/run.sh                          shell in the container
#   docker/run.sh scripts/sensors.sh       run a launch script
#   IMAGE=rover:jazzy ROS_DOMAIN_ID=5 docker/run.sh scripts/bringup.sh
#
# Uses the prebuilt image from ghcr.io (pulled on first run). To use a local
# build instead: docker build -f docker/Dockerfile -t rover:jazzy . && IMAGE=rover:jazzy docker/run.sh
#
# Uses the NVIDIA runtime for GPU access; DOCKER_RUNTIME=runc runs without it.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${IMAGE:-${ROVER_IMAGE:-ghcr.io/ucsd-silberman-classes-and-projects/blue-robocar-ros2:latest}}"
mkdir -p /tmp/rover "$REPO_ROOT/bags"

exec docker run --rm -it --init \
    --runtime "${DOCKER_RUNTIME:-nvidia}" \
    --network host --ipc host --privileged \
    -v /dev:/dev \
    -v /tmp/rover:/tmp/rover \
    -v "$REPO_ROOT/bags:/opt/rover/bags" \
    -e ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}" \
    ${VESC_PORT:+-e VESC_PORT="$VESC_PORT"} \
    ${LIVOX_IP:+-e LIVOX_IP="$LIVOX_IP"} \
    "$IMAGE" "$@"
