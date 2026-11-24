# CLAUDE.md

Template repository for projects on one specific Ackermann rover: **Jetson Orin Nano** (JetPack 7.2 / Ubuntu 24.04 / ROS 2 Jazzy), **Livox Mid-360**, **OAK-D Pro**, **VESC**, optional **Logitech F710**. It holds only the hardware layer: sensor drivers, VESC driver, teleop, static TF, and scripts to bring up and check the hardware. Users add their own perception and autonomy on top.

## Scope

Keep this repo limited to:
- Sensor drivers and their launch/config (`livox_bringup`, `livox_ros_driver2`, `oakd_publisher`)
- The drive base (`vesc`, the teleop/VESC launch in `ucsd_robocar_control2_pkg`)
- Robot description and thin adapters (`rover_bringup`: URDF, sensor RViz layout, `/cmd_vel` → `/ackermann_cmd`)
- Scripts for testing, visualizing and recording the hardware (`scripts/`)
- The Docker dev environment

Localization (EKF), SLAM, Nav2, planners and perception are out of scope: they belong in the projects built from this template.

## Interfaces (keep stable; downstream projects depend on them)

| Topic | Type | Notes |
|-------|------|-------|
| `/livox/lidar` | `PointCloud2` | PointXYZRTLT with per-point timestamps (`xfer_format: 0`), `livox_frame`, 10 Hz |
| `/livox/imu` | `Imu` | 200 Hz, accel in g, `livox_frame` |
| `/scan` | `LaserScan` | ±0.1 m slice of the cloud, ~723 beams |
| `/oakd/color/image_raw`, `/oakd/depth/image_raw`, `/oakd/*/camera_info` | `Image`, `CameraInfo` | 1280×720 @ 15 Hz, depth aligned to color, `oakd_camera_optical_frame` |
| `/oakd/imu` | `Imu` | 200 Hz, gyro de-biased at startup (keep the rover still ~5 s), no orientation |
| `/ackermann_cmd` | `AckermannDriveStamped` | the drive command; + steering = left |
| `/cmd_vel` | `Twist` | only with `bringup.sh --cmd-vel` |
| `/vesc_odom` | `Odometry` | wheel odometry, `publish_tf: false` |

TF published here: only static `base_link → livox_frame, oakd_link → {oakd_camera_optical_frame, oakd_imu_frame}` from `rover_bringup/urdf/robot.urdf.xacro`. Never publish `odom → base_link` from this repo; that belongs to the user's localization.

## Repo layout

- `ros2_ws/src/`: `livox_bringup`, `livox_ros_driver2` (git submodule), `oakd_publisher`, `vesc` (`vesc_driver`, `vesc_ackermann`, `vesc_msgs`), `ucsd_robocar_control2_pkg` (trimmed to teleop), `rover_bringup`
- `scripts/`: `build.sh`, `sensors.sh`, `teleop.sh`, `bringup.sh`, `record.sh`, shared helpers in `common.sh`; logs go to `/tmp/rover/`
- `docker/`: image, Compose (`rover` and `dev` services), `dev.sh`
- `docs/`: `reproduction.md`, `docker.md`, `ros2_testing.md`, `software_systems.md`, `robot_hardware.md`

## Common commands

```bash
docker/dev.sh up && docker/dev.sh shell           # dev container on the Jetson
scripts/build.sh [--all]                          # --all also builds user packages in ros2_ws/src
scripts/sensors.sh [--lidar|--oakd] [--rviz]      # sensor bench check
scripts/teleop.sh [--joy]                         # VESC + keyboard / F710
scripts/bringup.sh [--teleop|--joy] [--cmd-vel]   # whole hardware layer
scripts/record.sh [--no-images]                   # MCAP bag into bags/
```

## Conventions

- Mount offsets live only in `rover_bringup/urdf/robot.urdf.xacro`.
- VESC calibration (speed→eRPM, steering→servo) lives in `ucsd_robocar_control2_pkg/config/keyboard_teleop_config.yaml`.
- Nothing arbitrates `/ackermann_cmd`; teleop and autonomy must not drive at the same time.
- Keep CUDA and GPU libraries inside Docker; never install them on the Jetson host.
- New scripts source `scripts/common.sh` and reuse its `start_*`/`check_*` helpers.
