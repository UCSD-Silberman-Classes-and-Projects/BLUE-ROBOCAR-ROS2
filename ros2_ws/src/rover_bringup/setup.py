from glob import glob
import os

from setuptools import find_packages, setup

package_name = 'rover_bringup'

setup(
    name=package_name,
    version='0.0.0',
    packages=find_packages(exclude=['test']),
    data_files=[
        ('share/ament_index/resource_index/packages', ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
        (os.path.join('share', package_name, 'launch'), glob('launch/*.launch.py')),
        (os.path.join('share', package_name, 'rviz'), glob('rviz/*.rviz')),
        (os.path.join('share', package_name, 'urdf'), glob('urdf/*')),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='evanc',
    maintainer_email='evan.chou@live.com',
    description='Rover description (URDF/TF), sensor RViz layout, and the /cmd_vel -> /ackermann_cmd adapter.',
    license='Apache-2.0',
    extras_require={'test': ['pytest']},
    entry_points={
        'console_scripts': [
            'cmd_vel_to_ackermann_node = rover_bringup.cmd_vel_to_ackermann_node:main',
        ],
    },
)
