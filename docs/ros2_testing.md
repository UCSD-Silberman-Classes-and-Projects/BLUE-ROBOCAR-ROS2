# ROS 2 Testing Guide

How to build, bring up and verify each piece of hardware on the rover: the Livox Mid-360, the OAK-D Pro camera and IMU, and the VESC with keyboard or gamepad teleop. Each test builds on the one before it, so work through them in order the first time. Once all of them pass, the hardware-software integration is good and you can start on your own perception and autonomy code.

| Test | Command |
|------|---------|
| Sensors only | `scripts/sensors.sh` (`--lidar`, `--oakd`, `--rviz`) |
| Teleop only (VESC, no sensors) | `scripts/teleop.sh` (keyboard) or `scripts/teleop.sh --joy` (F710 gamepad) |
| Everything, driving by hand | `scripts/bringup.sh --teleop` or `scripts/bringup.sh --joy` |
| Everything, for your own nodes | `scripts/bringup.sh` (`--cmd-vel` for a Twist interface) |
| Record a bag | `scripts/record.sh` (in a second terminal, while one of the above runs) |

Every script writes one log per component to `/tmp/rover/` (override with `LOG_DIR`) and stops everything on Ctrl+C or when teleop quits.

Environment overrides (all scripts): `VESC_PORT` (default `/dev/vesc`, else the ttyACM with the VESC's USB ID), `LIVOX_IP` (default `192.168.1.124`), `ROS_DISTRO_NAME` (default `$ROS_DISTRO`, else `jazzy`), `LOG_DIR` (default `/tmp/rover`). Any machine that should see the rover's topics (for example a laptop running RViz) must use the same `ROS_DOMAIN_ID`. The scripts print the one in use.

---

## 1. Build

On the rover (Jetson Orin Nano, ROS 2 Jazzy), natively or inside the container ([docker.md](docker.md)):

```bash
git submodule update --init ros2_ws/src/livox_ros_driver2
scripts/build.sh
```

`scripts/build.sh` builds only the packages the scripts use; `--all` builds everything in `ros2_ws/src`, including packages you add. It also handles a quirk of the Livox driver: `livox_ros_driver2` ships `package_ROS2.xml` but no `package.xml`, so a plain `colcon build` skips it. The script copies the manifest into place and passes `-DROS_EDITION=ROS2 -DDISTRO_ROS=jazzy`. Don't use the driver's own `build.sh`, because it deletes the whole workspace's `build/` and `install/`.

Builds use `--symlink-install`, so edits to Python nodes, launch files and YAML take effect without rebuilding. C++ packages still need a rebuild. Never edit `build/` or `install/` directly.

For a manual shell outside the container, source both layers:

```bash
source /opt/ros/jazzy/setup.bash
source ros2_ws/install/setup.bash
```

---

## 2. Sensor tests

```bash
scripts/sensors.sh            # LiDAR + OAK-D + static TF
scripts/sensors.sh --lidar    # LiDAR only
scripts/sensors.sh --oakd     # OAK-D only
scripts/sensors.sh --rviz     # also RViz on the Jetson display
```

`sensors.sh` also starts `rover_bringup`'s `robot_state_publisher`, so the static TF `base_link → livox_frame, oakd_link → oakd_camera_optical_frame, oakd_imu_frame` is available for RViz.

### Viewing the sensors in RViz

Prefer running RViz on a laptop with the same `ROS_DOMAIN_ID` (it saves Jetson CPU):

```bash
rviz2 -d ros2_ws/src/rover_bringup/rviz/sensors.rviz
```

The layout uses fixed frame `base_link` and shows TF, the Livox point cloud (`/livox/lidar`), the 2D scan (`/scan`), and the OAK-D color and depth images. All displays use Best Effort reliability, which matches both best-effort and reliable publishers.

### LiDAR (Livox Mid-360)

The Mid-360 connects over Ethernet: the sensor is at `192.168.1.124` and the Jetson is statically `192.168.1.50` (see [robot_hardware.md](robot_hardware.md)). `livox_bringup` starts `livox_ros_driver2` and flattens its 3D point cloud into a 2D `LaserScan`:

```
livox_ros_driver2 → /livox/lidar (PointCloud2, livox_frame, per-point timestamps)
                  → /livox/imu   (Imu, ~200 Hz, in g, livox_frame)
pointcloud_to_laserscan (±0.1 m Z slice) → /scan (LaserScan, ~723 beams, -π..π)
```

Verify:

```bash
ping -c 1 192.168.1.124
ros2 topic hz /livox/lidar     # ~10 Hz
ros2 topic hz /livox/imu       # ~200 Hz
ros2 topic hz /scan            # ~10 Hz
ros2 topic echo /scan --once --field angle_min   # ≈ -3.14
```

**Forward-direction check:** put a box about 1 m directly in front of the rover. In RViz it should appear on the +X axis of `base_link`. If it appears somewhere else, the sensor is mounted rotated: fix the `rpy` of `lidar_joint` in `rover_bringup/urdf/robot.urdf.xacro`. (Without `robot_state_publisher` running, use fixed frame `livox_frame`; any other frame shows nothing and logs `Message Filter dropping message: frame 'livox_frame'`.)

**Self-hits:** if the chassis or camera mast shows up as a ring of points close to the sensor, raise `range_min` (for example `ros2 launch livox_bringup livox_mid360.launch.py range_min:=0.3`) or move the Z slice with `scan_height_min`/`scan_height_max`.

### OAK-D Pro camera

`oakd_publisher` is the OAK-D Pro driver. It uses the DepthAI v3 API: RGB comes from `CAM_A` and stereo depth from `CAM_B`/`CAM_C`, aligned on the device to the color image.

```bash
ros2 launch oakd_publisher oakd_publisher.launch.py
ros2 topic hz /oakd/color/image_raw   # ~15 Hz, 1280x720
ros2 topic hz /oakd/depth/image_raw   # ~15 Hz, 1280x720
```

The OAK-D Pro's active IR is off by default. To enable it for dark or textureless scenes:

```bash
ros2 launch oakd_publisher oakd_publisher.launch.py ir_dot_projector_ma:=200.0 ir_flood_light_ma:=100.0
```

Only one process can own the device. Don't run a DepthAI demo or another OAK driver at the same time.

### OAK-D Pro IMU

The same node publishes the camera's onboard IMU (BMI270 on current units, BNO086 on early ones) on `/oakd/imu` at about 200 Hz. Only angular velocity and linear acceleration are published. Orientation is not published (`orientation_covariance[0] = -1`) because there is no magnetometer to give absolute heading.

**Keep the rover still for the first ~5 s after launch.** The node averages the gyro to estimate its bias and doesn't publish `/oakd/imu` until that finishes. Look for this in the log:

```
[oakd_publisher_node]: Gyro bias calibrated: [0.0012, -0.0008, 0.0003] rad/s
```

Samples are rotated into `oakd_imu_frame`, which is axis-aligned with `oakd_link` (x forward, y left, z up). The rotation comes from the IMU extrinsics in the device EEPROM. If those are missing, the node logs `Falling back to the imu_rpy parameter` and uses `imu_rpy` instead.

**Axis check (do this once per camera mount):**

```bash
ros2 topic echo /oakd/imu --field linear_acceleration
```

1. Rover flat and still: `z ≈ +9.8` and `x, y ≈ 0`.
2. Lift the front of the rover: `x` goes **negative** (gravity tilts toward the back).

```bash
ros2 topic echo /oakd/imu --field angular_velocity
```

3. Turn the rover counter-clockwise when viewed from above: `z` goes **positive**.

If any of these fail, override the IMU-to-camera rotation (roll, pitch, yaw in radians) until all three checks pass, then copy the values into `oakd_publisher.launch.py`:

```bash
ros2 run oakd_publisher oakd_publisher_node --ros-args \
  -p imu_rotation_source:=manual -p "imu_rpy:=[0.0, 0.0, 1.5708]"
```

If the camera itself is mounted tilted, put that tilt in the URDF `oakd_joint` instead.

---

## 3. Keyboard teleop

```bash
scripts/teleop.sh
```

```
keyboard_teleop_node → /ackermann_cmd → ackermann_to_vesc_node → commands/motor/speed + commands/servo/position
                                                                 → vesc_driver_node → VESC
vesc_driver_node → /sensors/core → vesc_to_odom_node → /vesc_odom
```

The throttle latches and the steering springs back:

| Key | Action |
|-----|--------|
| `w` / `s` (Up / Down) | drive forward / reverse at the top speed; keeps going without holding. The opposite key stops (one press back to 0 m/s) |
| `a` / `d` (Left / Right) | steer left / right while held; wheels re-center on release. Steering never changes the throttle |
| `space` | stop: zero speed, center the wheels |
| `r` / `f` | top speed up / down (`speed_scale` × 0.5 m/s, default 0.25 m/s), applied immediately |
| `t` / `g` | steering angle up / down (`steer_scale` × 0.4 rad, default 0.3 rad) |
| `q` | quit and stop everything |

Why the throttle latches: a terminal reports key presses but not releases, and only auto-repeats the most recently pressed key. Hold `w` and tap `a`, and `w` stops repeating even though it's still down, so a hold-to-drive throttle cuts out every time you steer. Steering counts as held while its key keeps auto-repeating: 0.7 s after the first press (`initial_hold`, which must be longer than your terminal's key-repeat delay), then 0.25 s after the last repeat (`release_timeout`). Tune with `ros2 run ucsd_robocar_control2_pkg keyboard_teleop_node --ros-args -p initial_hold:=1.0`. If the terminal or SSH session drops, the node sends a stop before exiting. For true hold-to-drive, use the F710 (`--joy`).

Verify:

```bash
ros2 topic hz /sensors/core      # ~50 Hz VESC telemetry
ros2 topic echo /vesc_odom --field twist.twist.linear.x   # tracks commanded speed while driving
```

**VESC port:** the scripts use `/dev/vesc` if it exists (from [`udev/99-rover.rules`](../udev/99-rover.rules)), otherwise the ttyACM device with the VESC's USB ID (`0483:5740`), falling back to `/dev/ttyACM0`. Override with `VESC_PORT=/dev/ttyACM1 scripts/teleop.sh`.

**First-time setup:** servo output must be enabled in VESC Tool (App Settings → General → Use Servo Output → Write App Configuration).

### Steering calibration

Tune these values in `ucsd_robocar_control2_pkg/config/keyboard_teleop_config.yaml`:

```yaml
steering_angle_to_servo_gain: -0.6    # flip sign if steering is reversed
steering_angle_to_servo_offset: 0.5   # servo value (0–1) that centers the wheels
```

To find the offset, publish straight to the servo:

```bash
ros2 run vesc_driver vesc_driver_node --ros-args -p port:=/dev/vesc
ros2 topic pub /commands/servo/position std_msgs/msg/Float64 "data: 0.5" --once
# adjust until the wheels are straight → that value is the offset
```

Then `gain = (servo_full_left - offset) / max_steering_angle_radians`. Positive `steering_angle` must turn **left** (REP-103), which `cmd_vel_to_ackermann_node` and any standard autonomy stack assume.

### Speed (eRPM gain)

Drive a measured 2 m with teleop and compare it with the distance integrated from `/vesc_odom`. Scale `speed_to_erpm_gain` in the same YAML by `odom_distance / true_distance`.

### Gamepad teleop (Logitech F710)

```bash
scripts/teleop.sh --joy
scripts/bringup.sh --joy       # same, with all sensors running
```

```
F710 → game_controller_node (joy) → /joy → f710_teleop_node → /ackermann_cmd → (VESC stack as above)
```

The mapping follows DonkeyCar's `LogitechJoystickController`:

| Control | Action |
|---------|--------|
| Left stick ←/→ | Steer (full stick = `max_steer`, 0.4 rad) |
| Right stick ↑/↓ | Throttle forward / reverse (full stick = `speed_scale × max_speed`) |
| A | Emergency stop. Zero speed, constant throttle off. Stays stopped until the throttle stick is back at center |
| Back | Constant throttle on/off (cruise at `speed_scale × max_speed`) |
| D-pad ↑ / ↓ | `speed_scale` ± 0.05 (starts at 0.5, so 0.25 m/s top speed) |
| LB | Optional deadman: set `deadman_button: 9` to require holding it |

**Setup:** plug the nano receiver into the Jetson and slide the switch on the back of the controller to **X** (XInput). `--joy` warns if the receiver shows up in D mode (`046d:c219`). If the LED doesn't light up, press the Logitech button to wake the controller. To read the gamepad without being in the `input` group, install [`udev/99-rover.rules`](../udev/99-rover.rules).

**Safety:** `f710_teleop_node` publishes only while a stick is moved or cruise is on. When everything returns to neutral it sends one zero command and goes quiet. If `/joy` stops for 0.5 s (controller out of range, asleep, or receiver unplugged), it stops the car. Nothing arbitrates `/ackermann_cmd`: moving a stick while your own node is driving competes with it.

Verify the layout before driving with the wheels off the ground:

```bash
ros2 topic echo /joy             # left stick X = axes[0] (left +), right stick Y = axes[3] (up +), A = buttons[0]
ros2 topic echo /ackermann_cmd   # follows the sticks
```

If an axis or button is wrong for your controller, change the indices or `invert_*` flags in `ucsd_robocar_control2_pkg/config/f710_teleop_config.yaml`. Logs go to `/tmp/rover/joy.log`.

---

## 4. Full bringup (the base for your own code)

```bash
scripts/bringup.sh              # headless: start your own nodes in another terminal
scripts/bringup.sh --teleop     # drive by keyboard with everything running
scripts/bringup.sh --cmd-vel    # also accept geometry_msgs/Twist on /cmd_vel
```

This starts the LiDAR, OAK-D, VESC stack and `rover_bringup` (static TF; `cmd_vel_to_ackermann_node` with `--cmd-vel`), checks every topic, and reports which drive interface is live. Driving by hand with everything running (`--teleop` or `--joy`) is the final integration check: all sensor rates should hold while the motor and servo are loaded.

Your code drives the rover through one of:

| Interface | Message | Notes |
|-----------|---------|-------|
| `/ackermann_cmd` | `ackermann_msgs/AckermannDriveStamped` | `drive.speed` (m/s), `drive.steering_angle` (rad, + = left, clamped by the VESC config) |
| `/cmd_vel` (with `--cmd-vel`) | `geometry_msgs/Twist` | Converted with the bicycle model `δ = atan(L·ω / v)`, L = 0.34 m, clamped to ±0.4 rad. An Ackermann car can't rotate in place: a Twist with v ≈ 0 and ω ≠ 0 becomes a stop with a warning. For Nav2, use a controller that never asks for that (e.g. Regulated Pure Pursuit with `use_rotate_to_heading: false`) |

Wheel odometry is on `/vesc_odom` (`nav_msgs/Odometry`, `odom` → `base_link`, **no TF published**: your localization should own `odom → base_link`).

---

## 5. Recording bags

```bash
scripts/record.sh                 # in a second terminal, after sensors.sh or bringup.sh is up
scripts/record.sh --no-images     # LiDAR/IMU/odom/TF only
scripts/record.sh --no-compress   # if zstd can't keep up
```

Bags go to `bags/rover_<date>_<time>` (MCAP, `zstd_fast` chunk compression). They include `/livox/lidar`, `/livox/imu`, `/oakd/imu`, `/vesc_odom`, `/tf`, `/tf_static`, and, unless `--no-images`, the OAK-D color/depth images and camera infos. RGB-D is ~70 MB/s raw, so keep an eye on disk space. Start the stack before recording so the latched `/tf_static` is captured.

---

## 6. Diagnostics

### Logs and nodes

| Component | Log file |
|-----------|----------|
| LiDAR (`livox_bringup`) | `/tmp/rover/lidar.log` |
| OAK-D (`oakd_publisher`) | `/tmp/rover/oakd.log` |
| VESC stack | `/tmp/rover/vesc.log` |
| F710 gamepad | `/tmp/rover/joy.log` |
| `rover_bringup` (TF, RViz, cmd_vel adapter) | `/tmp/rover/rover.log` |

```bash
grep -E "ERROR|process has died|Caught exception" /tmp/rover/*.log
ros2 node list
```

Expected nodes for `scripts/bringup.sh`: `/livox_lidar_publisher`, `/livox_pointcloud_to_laserscan`, `/oakd_publisher_node`, `/ackermann_to_vesc_node`, `/vesc_driver_node`, `/vesc_to_odom_node`, `/robot_state_publisher` (plus `/cmd_vel_to_ackermann_node` with `--cmd-vel`).

### All topic rates at once

```bash
for t in /livox/lidar /livox/imu /scan /oakd/color/image_raw /oakd/depth/image_raw /oakd/imu /sensors/core /vesc_odom; do
  rate=$(timeout 4 ros2 topic hz $t 2>&1 | grep "average rate" | awk '{print $3}')
  echo "  $t: ${rate:-NOT PUBLISHING}"
done
```

Expected: `/livox/lidar` and `/scan` ~10 Hz, `/livox/imu` and `/oakd/imu` ~200 Hz, color/depth ~15 Hz (1280×720), `/sensors/core` and `/vesc_odom` ~50 Hz.

### TF tree

```
base_link ──(robot_state_publisher, static)──▶ livox_frame
          └──▶ oakd_link ──▶ oakd_camera_optical_frame
                        └──▶ oakd_imu_frame
```

```bash
ros2 run tf2_tools view_frames      # writes frames.pdf
```

Nothing publishes `odom → base_link` or `map → odom`; that's your localization's job.

### No `/scan` or `/livox/lidar` from the Livox

- `ping 192.168.1.124` fails: check the cable, the sensor's own 9–27 V supply, and the Jetson's static IP (`nmcli con show livox`, `ip -br addr`).
- `ip -br addr` shows no `192.168.1.50` on the wired interface, or the address disappears a minute after `ip addr add`: a NetworkManager DHCP profile (usually "Wired connection 1") owns the port and resets it while DHCP times out. Create the static `livox` profile on the **host** ([reproduction.md §6](reproduction.md#6-livox-mid-360--network-setup-and-sdk)) and remove the DHCP one; the container has no `nmcli`. To find the sensor's IP, sniff the port: it broadcasts from `192.168.1.1XX:65000` to `255.255.255.255:55000`.
- Driver logs `bind failed` / `Init lds lidar fail!`: the host IP is missing (above), or an orphaned `livox_ros_driver2_node` from an earlier run still holds UDP 56101–56401 (`pgrep -a livox_ros_drive`). A driver whose init failed ignores SIGINT and has to be killed by hand.
- Ping works but there's no data: the host IPs in `livox_bringup/config/MID360_config.json` must match the Jetson's address, and a firewall must not block UDP 56100–56501.
- `/livox/lidar` publishes but `/scan` is empty: the ±0.1 m Z slice may miss everything if the sensor is tilted. Widen it with `scan_height_min`/`scan_height_max`.

### OAK-D not found / `/oakd/imu` silent

- `lsusb | grep 03e7` shows nothing: re-seat the cable, use a USB 3 port, and install the udev rule.
- `X_LINK_DEVICE_NOT_FOUND` or `device already in use`: another process owns the camera (a DepthAI demo, another driver). Kill it.
- Color works but there's no IMU: wait for `Gyro bias calibrated` in `/tmp/rover/oakd.log`. If the log shows an IMU sensor error, the requested report types or rate aren't supported by that IMU chip. Try `imu_rate_hz:=50`.

### VESC not connecting

```bash
ls -l /dev/vesc /dev/ttyACM*
python3 -c "from serial.tools import list_ports; [print(p.device, hex(p.vid or 0), hex(p.pid or 0)) for p in list_ports.comports()]"
# VESC shows as vid=0x483 pid=0x5740
```

If `/sensors/core` publishes but the wheels don't steer, servo output isn't enabled in VESC Tool.
