# ucsd_robocar_control2_pkg

Trimmed from the [UCSD RoboCar Hub2](https://github.com/UCSD-ECEMAE-148/ucsd_robocar_control2_pkg) control package. Only manual driving is kept:

| File | Purpose |
|------|---------|
| `launch/keyboard_teleop.launch.py` | The VESC stack: `vesc_driver_node`, `ackermann_to_vesc_node` (`/ackermann_cmd` → VESC) and `vesc_to_odom_node` (`/vesc_odom`). Despite the name it starts no teleop node; `scripts/teleop.sh` runs `keyboard_teleop_node` in the foreground |
| `launch/f710_teleop.launch.py` | Logitech F710: `joy` `game_controller_node` + `f710_teleop_node` → `/ackermann_cmd` |
| `config/keyboard_teleop_config.yaml` | VESC port, speed→eRPM and steering→servo calibration, driver limits |
| `config/f710_teleop_config.yaml` | Gamepad axis/button mapping and speed limits |
