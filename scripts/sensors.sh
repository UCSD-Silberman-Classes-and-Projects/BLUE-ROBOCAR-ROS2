#!/usr/bin/env bash
# sensors.sh — bring up only the sensors (Livox Mid-360 + OAK-D Pro) for bench checks.
#
#   livox_bringup  → /livox/lidar (PointCloud2), /livox/imu, /scan (LaserScan)
#   oakd_publisher → /oakd/color/image_raw, /oakd/depth/image_raw, /oakd/imu
#   rover_bringup  → static TF base_link → livox_frame, oakd_* (robot_state_publisher)
#
# Usage:
#   scripts/sensors.sh             both sensors, Ctrl+C to stop
#   scripts/sensors.sh --lidar     LiDAR only
#   scripts/sensors.sh --oakd      OAK-D only
#   scripts/sensors.sh --rviz      also RViz with rover_bringup/rviz/sensors.rviz (Jetson display, CPU heavy;
#                                  or run rviz2 on a laptop with the same ROS_DOMAIN_ID)

_TAG=sensors
source "$(dirname "$0")/common.sh"

USE_LIDAR=true
USE_OAKD=true
USE_RVIZ=false
for arg in "$@"; do
    case "$arg" in
        --lidar) USE_OAKD=false ;;
        --oakd)  USE_LIDAR=false ;;
        --rviz)  USE_RVIZ=true ;;
        *) err "Unknown flag: $arg  (valid: --lidar, --oakd, --rviz)"; exit 1 ;;
    esac
done

log "Preflight..."
[ "$USE_LIDAR" = true ] && check_lidar
[ "$USE_OAKD" = true ] && check_oakd
source_ws "$ROS_WS"

[ "$USE_LIDAR" = true ] && start_lidar
[ "$USE_OAKD" = true ] && start_oakd
start_rover use_rviz:="$USE_RVIZ"
sleep 8

if [ "$USE_LIDAR" = true ]; then
    check_topic /livox/lidar 5 "/livox/lidar publishing" "/livox/lidar not detected — see $LOG_DIR/lidar.log"
    check_topic /livox/imu 5 "/livox/imu publishing" "/livox/imu not detected — see $LOG_DIR/lidar.log"
    check_topic /scan 5 "/scan publishing" "/scan not detected — see $LOG_DIR/lidar.log"
fi
if [ "$USE_OAKD" = true ]; then
    check_topic /oakd/color/image_raw 5 "/oakd/color/image_raw publishing" "no OAK-D color — see $LOG_DIR/oakd.log"
    check_topic /oakd/imu 5 "/oakd/imu publishing" "no /oakd/imu — calibration may still be running; see $LOG_DIR/oakd.log"
fi

log "Sensors running. View them from a laptop (same ROS_DOMAIN_ID=${ROS_DOMAIN_ID:-0}):"
log "  rviz2 -d \$(ros2 pkg prefix rover_bringup)/share/rover_bringup/rviz/sensors.rviz"
log "Ctrl+C to stop."
wait
