# T265 (TM2) support patch for realsense-ros 4.59.1

Restores support for the end-of-life Intel RealSense T265 tracking
camera to the `realsense2_camera` ROS 2 wrapper **4.59.1** (upstream
removed the T265 code paths after the last T265-capable release,
4.54.1).

| File | What it is |
|---|---|
| `t265-ros-port-v4.59.1.patch` | 11 source files (+150/−1); plain text; **no binaries** |
| `install-t265-patch.sh` | verifies the target is byte-identical to 4.59.1 (git tree hash) and applies the patch; optional `--build` (colcon) + node smoke test |

## What the patch adds

- `pose` stream handling: `PoseProfilesManager` (params `enable_pose`,
  `pose_fps`, `pose_qos`, `pose_info_qos`), `pose_sensor` registration,
  `pose_callback` publishing `~/pose/sample`
  (`nav_msgs/msg/Odometry`) and the `odom_frame -> <camera>_pose_frame`
  TF transform (param `publish_odom_tf`, default `true`).
- `fisheye1` / `fisheye2` stream constants and launch defaults
  (`enable_fisheye1`, `enable_fisheye2`, default `true`) — image +
  `camera_info` publishers come from the standard video-stream path.
- `SetBaseStream` priority becomes `{DEPTH, POSE}` so the T265 (which has
  no depth stream) gets valid transforms.

The IMU streams of the T265 (gyro/accel) keep working through the
existing motion-stream path.

## Where to apply it

On a pristine 4.59.1 checkout, **before** building:

```
checkout 4.59.1  →  APPLY PATCH HERE  →  build as documented upstream
```

Concretely:

```sh
git clone https://github.com/realsenseai/realsense-ros.git
cd realsense-ros && git checkout 4.59.1
bash /path/to/install-t265-patch.sh --repo . --patch
```

(or simply `git apply t265-ros-port-v4.59.1.patch`).

Everything after that is exactly as documented for the original
repository (https://github.com/realsenseai/realsense-ros).

## SDK requirement

The wrapper must be built and run against a **T265-capable librealsense
SDK** (the stock v2.59.1 SDK has no T265 device support and will not
see the camera). The companion patch kit `ntsarb/librealsense-t265-v2.59.1`
provides that SDK.

## Related projects

* [`ntsarb/librealsense-t265-v2.59.1`](https://github.com/ntsarb/librealsense-t265-v2.59.1) — restores T265 support to the librealsense v2.59.1 SDK (upstream removed it in v2.54.1).
* [`ntsarb/T265-demo`](https://github.com/ntsarb/T265-demo) — a Qt6 viewer for the T265 (3-D trajectory, fisheye images, IMU strips, CSV export); works directly with the SDK or with the wrapper's ROS 2 topics.

## Building the patched wrapper

```sh
bash install-t265-patch.sh --repo /path/to/realsense-ros --build
```

This sources the first `/opt/ros/*/setup.sh`, builds
`realsense2_camera_msgs`, `realsense2_description` and
`realsense2_camera` with colcon into a workspace next to the repo
(`--ws <dir>` to choose another), and runs a short node-startup smoke
test.

## Reverting

```sh
bash install-t265-patch.sh --repo /path/to/realsense-ros --unapply
```

## license
Apache License
Version 2.0, January 2004
http://www.apache.org/licenses/
