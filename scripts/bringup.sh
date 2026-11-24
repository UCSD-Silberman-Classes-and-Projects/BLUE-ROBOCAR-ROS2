#!/usr/bin/env bash
# bringup.sh — the whole hardware layer: sensors + VESC + TF. Start this, then
# run your own perception/autonomy nodes in another terminal.
#
#   livox_bringup     → /livox/lidar, /livox/imu, /scan
#   oakd_publisher    → /oakd/color/image_raw, /oakd/depth/image_raw, /oakd/{color,depth}/camera_info, /oakd/imu
#   VESC stack        → drives the car from /ackermann_cmd; /vesc_odom, /sensors/core
#   rover_bringup     → static TF base_link → livox_frame, oakd_link, oakd_camera_optical_frame, oakd_imu_frame
#
# Your code drives the rover by publishing ackermann_msgs/AckermannDriveStamped on
# /ackermann_cmd, or geometry_msgs/Twist on /cmd_vel with --cmd-vel.
#
# Usage:
#   scripts/bringup.sh             headless: nothing publishes /ackermann_cmd but your nodes
#   scripts/bringup.sh --teleop    keyboard teleop in this terminal (hardware check while driving)
#   scripts/bringup.sh --joy       Logitech F710 gamepad teleop
#   scripts/bringup.sh --cmd-vel   also cmd_vel_to_ackermann_node: /cmd_vel (Twist) → /ackermann_cmd
#   scripts/bringup.sh --rviz      RViz on the Jetson display (CPU heavy)
#
# Teleop and your nodes both publish /ackermann_cmd; nothing arbitrates between
# them, so don't drive by hand while your autonomy is commanding the car.

_TAG=bringup
source "$(dirname "$0")/common.sh"

MODE=headless
USE_CMD_VEL=false
USE_RVIZ=false
for arg in "$@"; do
    case "$arg" in
        --teleop)  MODE=keyboard ;;
        --joy)     MODE=joy ;;
        --cmd-vel) USE_CMD_VEL=true ;;
        --rviz)    USE_RVIZ=true ;;
        *) err "Unknown flag: $arg  (valid: --teleop, --joy, --cmd-vel, --rviz)"; exit 1 ;;
    esac
done

log "Preflight..."
check_power_mode
check_lidar
check_oakd
[ "$MODE" = joy ] && check_f710
resolve_vesc_port
source_ws "$ROS_WS"

start_lidar
start_oakd
start_vesc
start_rover use_rviz:="$USE_RVIZ" use_cmd_vel:="$USE_CMD_VEL"

sleep 8
check_topic /livox/lidar 5 "/livox/lidar publishing" "/livox/lidar missing — see $LOG_DIR/lidar.log"
check_topic /scan 5 "/scan publishing" "/scan missing — see $LOG_DIR/lidar.log"
check_topic /oakd/color/image_raw 5 "/oakd/color/image_raw publishing" "no OAK-D color — see $LOG_DIR/oakd.log"
check_topic /oakd/imu 5 "/oakd/imu publishing" "/oakd/imu missing — calibration may still be running; see $LOG_DIR/oakd.log"
check_topic /sensors/core 5 "/sensors/core publishing (VESC telemetry)" \
    "/sensors/core not detected — check VESC USB, and that servo output is enabled in VESC Tool"
check_topic /vesc_odom 5 "/vesc_odom publishing" "/vesc_odom missing — see $LOG_DIR/vesc.log"

echo ""
if [ "$USE_CMD_VEL" = true ]; then
    log "Drive interface: /cmd_vel (geometry_msgs/Twist) → /ackermann_cmd"
else
    log "Drive interface: /ackermann_cmd (ackermann_msgs/AckermannDriveStamped)"
fi
log "RViz from a laptop (same ROS_DOMAIN_ID=${ROS_DOMAIN_ID:-0}):"
log "  rviz2 -d \$(ros2 pkg prefix rover_bringup)/share/rover_bringup/rviz/sensors.rviz"

case "$MODE" in
    keyboard)
        run_teleop_foreground ;;
    joy)
        start_joy
        sleep 2
        check_topic /joy 3 "/joy publishing (F710)" \
            "/joy not detected — check the receiver, the X/D switch, and $LOG_DIR/joy.log"
        run_joy_foreground ;;
    *)
        warn "Keep a hand on the power switch while your own nodes drive the rover."
        log "Ctrl+C to stop all nodes."
        wait ;;
esac
