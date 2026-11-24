# <div align="center">Blue RoboCar ROS2 Container: Jetson Orin Nano + Livox Mid-360 + OAK-D Pro + VESC</div>

<p align="center">
  <img alt="ROS 2 Jazzy" src="https://img.shields.io/badge/ROS%202-Jazzy-22314E?style=flat-square&logo=ros&logoColor=white">
  <img alt="NVIDIA Jetson" src="https://img.shields.io/badge/Jetson%20Orin%20Nano-JetPack%207.2-76B900?style=flat-square&logo=nvidia&logoColor=white">
  <img alt="Docker" src="https://img.shields.io/badge/Docker-dev%20container-2496ED?style=flat-square&logo=docker&logoColor=white">
  <img alt="VESC" src="https://img.shields.io/badge/VESC-motor%20control-2E7D32?style=flat-square">
  <img alt="DepthAI OAK-D" src="https://img.shields.io/badge/DepthAI%20OAK--D%20Pro-RGB--D%20%2B%20IMU-00A3E0?style=flat-square">
</p>

![image](docs/media/car.jpg)

A starting point for projects on the Blue RoboCar. It holds only the hardware layer: sensor drivers, the VESC motor/steering driver, keyboard and gamepad teleop, the robot's static TF, and one-command scripts to bring all of it up and check that it works. Localization, mapping, planning and perception are left for your project.

Clone it, get every test in [docs/ros2_testing.md](docs/ros2_testing.md) passing on your rover, then add your own packages on top.

## Hardware

| Component | Interface | ROS 2 topics |
|-----------|-----------|--------------|
| NVIDIA Jetson Orin Nano | JetPack 7.2 (Ubuntu 24.04), ROS 2 Jazzy | |
| Livox Mid-360 LiDAR | Ethernet (`192.168.1.124`, Jetson `192.168.1.50`) | `/livox/lidar`, `/livox/imu`, `/scan` |
| Luxonis OAK-D Pro | USB 3 | `/oakd/color/image_raw`, `/oakd/depth/image_raw`, `/oakd/*/camera_info`, `/oakd/imu` |
| VESC (drive motor + steering servo) | USB serial (`/dev/vesc`) | `/ackermann_cmd` (in), `/vesc_odom`, `/sensors/core` |
| Logitech F710 gamepad (optional) | USB receiver | `/joy` |

Full parts list, mount frames and wiring notes: [docs/robot_hardware.md](docs/robot_hardware.md).

## Quick start

```bash
git clone <this-repo-url> && cd <this-repo-url>
git submodule update --init ros2_ws/src/livox_ros_driver2

# Host setup once (udev rules, Livox network, Docker + NVIDIA Container Toolkit): docs/docker.md §1
docker/dev.sh up && docker/dev.sh shell       # persistent dev container on the Jetson
scripts/build.sh

scripts/sensors.sh                            # LiDAR + OAK-D, with topic checks
scripts/teleop.sh                             # keyboard driving (--joy for the F710)
scripts/bringup.sh --teleop                   # everything at once, driving by hand
```

Prefer a native install? Follow [docs/reproduction.md](docs/reproduction.md) instead of the Docker steps.

## Scripts

| Script | Starts |
|--------|--------|
| `scripts/build.sh [--all] [--clean]` | `colcon build` of `ros2_ws` with the Livox driver workarounds (`--all` includes your own packages) |
| `scripts/sensors.sh [--lidar\|--oakd] [--rviz]` | Livox Mid-360, OAK-D Pro (RGB-D + IMU), static TF |
| `scripts/teleop.sh [--joy]` | VESC stack + keyboard teleop (`--joy`: Logitech F710) |
| `scripts/bringup.sh [--teleop\|--joy] [--cmd-vel] [--rviz]` | Sensors + VESC + static TF. Headless by default, for your own nodes; `--cmd-vel` adds a `/cmd_vel` (Twist) → `/ackermann_cmd` adapter |
| `scripts/record.sh [--no-images] [--no-compress]` | MCAP bag of the raw sensor topics into `bags/` |

Logs go to `/tmp/rover/<component>.log`. Overrides: `VESC_PORT`, `LIVOX_IP`, `ROS_DOMAIN_ID`, `LOG_DIR`.

## Adding your project

1. Put your packages in `ros2_ws/src/` (or a separate workspace overlaid on this one) and build with `scripts/build.sh --all`.
2. Start the hardware with `scripts/bringup.sh` (add `--cmd-vel` if your stack outputs `geometry_msgs/Twist`).
3. Run your nodes in another shell (`docker/dev.sh shell`). Subscribe to the sensor topics above and drive by publishing `ackermann_msgs/AckermannDriveStamped` on `/ackermann_cmd`.
4. Add apt/pip dependencies to [docker/Dockerfile](docker/Dockerfile) or your `package.xml`.

What's provided and what isn't:

- **TF:** only the static `base_link → livox_frame, oakd_link → oakd_camera_optical_frame, oakd_imu_frame`. Your localization owns `odom → base_link` (and `map → odom`). `/vesc_odom` publishes wheel odometry without TF.
- **Command arbitration:** none. Teleop and your nodes both publish `/ackermann_cmd`, and the last message wins. Add a mux if you need teleop to override autonomy.

Interfaces in detail: [docs/software_systems.md](docs/software_systems.md#interfaces-for-your-code).

## Repository layout

```
ros2_ws/src/
  livox_bringup/              Mid-360 launch + config (driver: livox_ros_driver2 submodule)
  livox_ros_driver2/          git submodule (Livox-SDK/livox_ros_driver2)
  oakd_publisher/             OAK-D Pro RGB-D + IMU driver (DepthAI v3)
  vesc/                       VESC driver, Ackermann ↔ VESC conversion, odometry
  ucsd_robocar_control2_pkg/  keyboard + F710 teleop, VESC stack launch
  rover_bringup/              URDF/TF, sensor RViz layout, /cmd_vel adapter
scripts/                      one-command launchers (see above)
docker/                       image, Compose services, dev container helper
udev/99-rover.rules           stable /dev/vesc, OAK-D and F710 permissions
docs/                         setup, testing and reference guides
```

## Documentation

- [Reproduction guide](docs/reproduction.md): native setup from a fresh Jetson (JetPack, ROS 2, Livox SDK, udev, VESC, calibration).
- [Docker guide](docs/docker.md): building and running everything in a container on the Jetson, and the dev container workflow.
- [ROS 2 testing guide](docs/ros2_testing.md): what to check for each sensor, teleop, full bringup, and troubleshooting.
- [Software systems](docs/software_systems.md): drivers, data flow, TF, and the interfaces your code plugs into.
- [Robot hardware](docs/robot_hardware.md): parts list, sensor frames, USB and network assignments.

## Acknowledgements

Built from Evan Chou's UCSD ECE Honors project rover (advised by Prof. Truong Nguyen and Prof. Jack Silberman). Teleop and VESC packages are adapted from the [UCSD RoboCar Hub2](https://github.com/UCSD-ECEMAE-148) and [f1tenth/vesc](https://github.com/f1tenth/vesc).
