# <div align="center">Software Systems</div>

## Overview

This repository is the hardware layer for the rover: sensor drivers, the VESC motor/steering driver, manual teleop, the robot's static TF, and launch scripts that bring them up and check them. It contains no localization, mapping, planning or perception. Those are left for your project, which plugs in through the topics listed under [Interfaces for your code](#interfaces-for-your-code).

Everything runs on the Jetson Orin Nano (JetPack 7.2 / Ubuntu 24.04) with ROS 2 Jazzy, natively or in the provided Docker image ([docker.md](docker.md)).

| Package | Role |
|---------|------|
| `livox_bringup` | Launches `livox_ros_driver2` (git submodule) for the Mid-360 and `pointcloud_to_laserscan` |
| `oakd_publisher` | OAK-D Pro driver (DepthAI v3): aligned RGB-D + onboard IMU |
| `vesc` (`vesc_driver`, `vesc_ackermann`, `vesc_msgs`) | VESC serial driver, `/ackermann_cmd` → motor/servo, wheel odometry |
| `ucsd_robocar_control2_pkg` | Keyboard and Logitech F710 teleop, and the VESC stack launch file |
| `rover_bringup` | URDF + `robot_state_publisher`, sensor RViz layout, `/cmd_vel` → `/ackermann_cmd` adapter |

Each test has its own launch script in [`scripts/`](../scripts); see [ros2_testing.md](ros2_testing.md).

---

## Sensors

### Livox Mid-360 (`livox_bringup`)

`livox_ros_driver2` (built against Livox-SDK2) publishes `/livox/lidar` as a `PointCloud2` with Livox's `PointXYZRTLT` fields (x, y, z, intensity, tag, line, per-point `timestamp`; `xfer_format: 0`) at 10 Hz in `livox_frame`. The per-point timestamps let LiDAR-inertial odometry deskew each scan. `pointcloud_to_laserscan` flattens a ±0.1 m Z slice of that cloud into `/scan`: a 360° `LaserScan` with a fixed `angle_increment` of 0.0087 rad (~723 beams), for 2D consumers such as slam_toolbox or Nav2 costmaps.

The Mid-360's own IMU is on `/livox/imu` (200 Hz, linear acceleration in **g**, not m/s², frame hard-coded to `livox_frame` by the driver). It shares the LiDAR's clock and housing, so it's the natural choice for tightly coupled LiDAR-inertial methods.

### OAK-D Pro (`oakd_publisher`)

A single DepthAI v3 pipeline on the OAK-D Pro produces:

| Topic | Type | Frame | Rate |
|-------|------|-------|------|
| `/oakd/color/image_raw` | `sensor_msgs/Image` (bgr8, 1280×720, undistorted on device) | `oakd_camera_optical_frame` | 15 Hz |
| `/oakd/depth/image_raw` | `sensor_msgs/Image` (16UC1 mm, 1280×720, aligned to color) | `oakd_camera_optical_frame` | 15 Hz |
| `/oakd/{color,depth}/camera_info` | `sensor_msgs/CameraInfo` (same intrinsics for both) | `oakd_camera_optical_frame` | 15 Hz |
| `/oakd/imu` | `sensor_msgs/Imu` | `oakd_imu_frame` | 200 Hz |

**RGB-D pipeline.** Stereo depth (640×400 mono pair) is aligned on the device to the color camera (CAM_A) and scaled to the color resolution, so a depth pixel and a color pixel at the same (u, v) see the same point and share one `CameraInfo`. A depthai `Sync` node pairs color and depth by device timestamp, and both messages are stamped with the color capture time shifted onto the ROS clock (not the publish time), so a tf lookup at the image stamp gives the camera pose at capture. Intrinsics come from each frame's `ImgTransformation`, which accounts for the device-side crop, scale and undistortion. For repeatable runs, lock exposure and white balance (`rgb_exposure_us`, `rgb_white_balance_k`).

**IMU pipeline.** The node requests `ACCELEROMETER_RAW` and `GYROSCOPE_RAW` reports, the subset shared by the BMI270 (current OAK-D Pro) and the BNO086 (early units). Neither chip has a magnetometer, so no orientation is published (`orientation_covariance[0] = -1`). Each sample is:

1. **Rotated** into `oakd_imu_frame`, which is axis-aligned with the camera body `oakd_link` (REP-103: x forward, y left, z up). The rotation is the IMU→`CAM_A` extrinsic stored in the device EEPROM, composed with the optical→body rotation. If the EEPROM has no IMU extrinsics, the `imu_rpy` parameter is used instead. The URDF then only needs the camera mount pose.
2. **De-biased.** For the first `gyro_bias_calibration_s` (5 s), samples are averaged into a gyro bias and nothing is published. The rover must be stationary during this window.
3. **Stamped** with the device's host-synced capture time, shifted onto the ROS clock, rather than the time it was dequeued.

The OAK-D Pro's IR dot projector and flood light are off by default (`ir_dot_projector_ma`, `ir_flood_light_ma`).

---

## Driving

```
keyboard_teleop_node ───────────────────────────┐
f710_teleop_node ───────────────────────────────┤
your node ──────────────────────────────────────┼→ /ackermann_cmd → ackermann_to_vesc_node → vesc_driver_node ⇄ VESC
your node → /cmd_vel → cmd_vel_to_ackermann_node┘                                                   │ /sensors/core
                                                                                vesc_to_odom_node ◀─┘ → /vesc_odom
```

`keyboard_teleop.launch.py` (in `ucsd_robocar_control2_pkg`) starts the VESC stack: `ackermann_to_vesc_node`, `vesc_driver_node` and `vesc_to_odom_node`. Despite its name, it starts no teleop node; the scripts run `keyboard_teleop_node` in the foreground. `vesc_to_odom_node` remaps `/odom` to `/vesc_odom` with `publish_tf: false`, so whatever localization you add can own `odom → base_link`. The `vesc_port` launch argument overrides the port in `keyboard_teleop_config.yaml`, which also holds the speed→eRPM and steering→servo calibration.

`f710_teleop.launch.py` starts `joy`'s `game_controller_node` and `f710_teleop_node` from `f710_teleop_config.yaml`. The controls follow DonkeyCar: left stick steers, right stick drives, A is an emergency stop, Back toggles constant throttle, and the D-pad changes the max speed. The node only publishes while it's being driven, and it stops the car if `/joy` goes silent.

There is no command multiplexer: every publisher on `/ackermann_cmd` is obeyed. If your project needs teleop to override autonomy, add a mux (for example `ackermann_mux`) in front of `ackermann_to_vesc_node`.

---

## TF

```
base_link ──▶ livox_frame
          └──▶ oakd_link ──▶ oakd_camera_optical_frame
                        └──▶ oakd_imu_frame
```

`rover_bringup/urdf/robot.urdf.xacro` holds the mount offsets (estimates; measure them on your rover). `robot_state_publisher` publishes them as static TF. Nothing in this repo publishes `odom → base_link` or `map → odom`.

---

## Interfaces for your code

| Direction | Topic | Type |
|-----------|-------|------|
| In (sensor) | `/livox/lidar` | `sensor_msgs/PointCloud2` (PointXYZRTLT, 10 Hz) |
| In (sensor) | `/livox/imu` | `sensor_msgs/Imu` (200 Hz, accel in g) |
| In (sensor) | `/scan` | `sensor_msgs/LaserScan` (10 Hz) |
| In (sensor) | `/oakd/color/image_raw`, `/oakd/depth/image_raw` | `sensor_msgs/Image` (15 Hz, aligned) |
| In (sensor) | `/oakd/color/camera_info`, `/oakd/depth/camera_info` | `sensor_msgs/CameraInfo` |
| In (sensor) | `/oakd/imu` | `sensor_msgs/Imu` (200 Hz, gyro de-biased, no orientation) |
| In (sensor) | `/vesc_odom` | `nav_msgs/Odometry` (wheel odometry, no TF) |
| In (sensor) | `/sensors/core` | `vesc_msgs/VescStateStamped` (VESC telemetry) |
| Out (command) | `/ackermann_cmd` | `ackermann_msgs/AckermannDriveStamped` |
| Out (command) | `/cmd_vel` | `geometry_msgs/Twist` (only with `scripts/bringup.sh --cmd-vel`) |

Add your packages under `ros2_ws/src/` and build with `scripts/build.sh --all`, or keep them in a separate workspace overlaid on this one.
