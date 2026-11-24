"""Rover base bringup: robot_state_publisher (+ optional RViz and /cmd_vel adapter).

Sensor drivers (livox_bringup, oakd_publisher) and the VESC stack are started
separately by the scripts in scripts/.

    ros2 launch rover_bringup rover.launch.py                        # TF only
    ros2 launch rover_bringup rover.launch.py use_rviz:=true         # + RViz sensor layout
    ros2 launch rover_bringup rover.launch.py use_cmd_vel:=true      # + /cmd_vel -> /ackermann_cmd
"""
import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.conditions import IfCondition
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description():
    pkg = get_package_share_directory('rover_bringup')

    use_sim_time = LaunchConfiguration('use_sim_time')
    use_rviz = LaunchConfiguration('use_rviz')
    use_cmd_vel = LaunchConfiguration('use_cmd_vel')
    rviz_config = LaunchConfiguration('rviz_config')

    with open(os.path.join(pkg, 'urdf', 'robot.urdf.xacro')) as f:
        robot_description = f.read()

    return LaunchDescription([
        DeclareLaunchArgument(
            'use_sim_time',
            default_value='false',
            description='Use simulated clock',
        ),
        DeclareLaunchArgument(
            'use_rviz',
            default_value='false',
            description='Launch RViz with the sensor layout (CPU heavy on the Jetson)',
        ),
        DeclareLaunchArgument(
            'use_cmd_vel',
            default_value='false',
            description='Start cmd_vel_to_ackermann_node: /cmd_vel (Twist) -> /ackermann_cmd. '
                        'Use when your autonomy stack (e.g. Nav2) outputs Twist.',
        ),
        DeclareLaunchArgument(
            'rviz_config',
            default_value=os.path.join(pkg, 'rviz', 'sensors.rviz'),
            description='Path to the RViz config file',
        ),

        # Static TF base_link -> livox_frame, oakd_link, oakd_camera_optical_frame, oakd_imu_frame.
        Node(
            package='robot_state_publisher',
            executable='robot_state_publisher',
            parameters=[
                {'robot_description': robot_description},
                {'use_sim_time': use_sim_time},
            ],
        ),

        # Ackermann base: ackermann_to_vesc listens on /ackermann_cmd, not /cmd_vel.
        Node(
            package='rover_bringup',
            executable='cmd_vel_to_ackermann_node',
            name='cmd_vel_to_ackermann_node',
            output='screen',
            condition=IfCondition(use_cmd_vel),
        ),

        Node(
            package='rviz2',
            executable='rviz2',
            name='rviz2',
            arguments=['-d', rviz_config],
            parameters=[{'use_sim_time': use_sim_time}],
            output='screen',
            condition=IfCondition(use_rviz),
        ),
    ])
