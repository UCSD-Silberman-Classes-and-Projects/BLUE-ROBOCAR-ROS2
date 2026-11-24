rover_bringup
=============

The robot-specific glue that isn't a sensor driver:

| Item | Purpose |
|------|---------|
| `urdf/robot.urdf.xacro` | `base_link` → `livox_frame`, `oakd_link` → `oakd_camera_optical_frame`, `oakd_imu_frame`. Mount offsets are estimates; measure them on your rover |
| `launch/rover.launch.py` | `robot_state_publisher` for the URDF. `use_rviz:=true` adds RViz with `rviz/sensors.rviz`; `use_cmd_vel:=true` adds `cmd_vel_to_ackermann_node` |
| `rviz/sensors.rviz` | Fixed frame `base_link`: TF, `/livox/lidar`, `/scan`, OAK-D color and depth |
| `cmd_vel_to_ackermann_node` | `/cmd_vel` (Twist) → `/ackermann_cmd` via the bicycle model (`steering = atan(wheelbase·ω / v)`, clamped to ±0.4 rad). A rotate-in-place Twist (v ≈ 0) is sent as a stop with a warning |

```bash
ros2 launch rover_bringup rover.launch.py                      # TF only
ros2 launch rover_bringup rover.launch.py use_rviz:=true       # + RViz
ros2 launch rover_bringup rover.launch.py use_cmd_vel:=true    # + Twist adapter for your autonomy stack
```

Sensor drivers (`livox_bringup`, `oakd_publisher`) and the VESC stack (`ucsd_robocar_control2_pkg`) are started separately; [`scripts/`](../../../scripts) combines them per test.
