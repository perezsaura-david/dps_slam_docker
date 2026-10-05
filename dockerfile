FROM aerostack2/nightly-humble:latest

# Gazebo Fortress clean uninstall
RUN apt remove ignition* -y
RUN apt autoremove -y

# Install Gazebo Harmonic
RUN apt-get install lsb-release wget gnupg && apt-get update
RUN wget https://packages.osrfoundation.org/gazebo.gpg -O /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg
RUN echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] http://packages.osrfoundation.org/gazebo/ubuntu-stable $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/gazebo-stable.list > /dev/null
RUN apt-get update && apt-get install -y -q gz-harmonic

# Install ros-gazebo dependencies
RUN apt update && apt install ros-humble-ros-gzharmonic -y

# Clone project gazebo
RUN git clone https://github.com/aerostack2/project_gazebo.git ../project_gazebo
RUN git clone https://github.com/aerostack2/as2_platform_mavlink.git /root/aerostack2_ws/src/as2_platform_mavlink
# mavros/mavros-extras are missing from the packages.ros.org main channel (only
# mavros-msgs is there) but are published in ros2-testing. Add testing for this
# install only, so nothing else is pulled from it.
RUN sed 's|packages.ros.org/ros2/|packages.ros.org/ros2-testing/|' \
      /etc/apt/sources.list.d/ros2.sources > /etc/apt/sources.list.d/ros2-testing.sources \
 && apt-get update && apt-get install -y ros-humble-mavros ros-humble-mavros-extras \
 && rm /etc/apt/sources.list.d/ros2-testing.sources && apt-get update
# Storage plugin for .mcap rosbags; without it `ros2 bag play` fails with
# "Could not load/open plugin with storage id 'mcap'".
RUN sudo apt-get update && sudo apt-get install -y ros-humble-rosbag2-storage-mcap
RUN /opt/ros/humble/lib/mavros/install_geographiclib_datasets.sh
RUN git clone https://github.com/MOCAP4ROS2-Project/mocap4ros2_optitrack.git /root/aerostack2_ws/src/mocap4ros2_optitrack
RUN git clone https://github.com/MOCAP4ROS2-Project/mocap4r2_msgs.git /root/aerostack2_ws/src/mocap4r2_msgs
RUN git clone https://github.com/MOCAP4ROS2-Project/mocap4r2.git /root/aerostack2_ws/src/mocap4r2

# Recompile Aerostack2
WORKDIR /root/aerostack2_ws
RUN rm -rf build/ install/ log/
RUN . /opt/ros/$ROS_DISTRO/setup.sh && colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release

WORKDIR /root

# --- Custom ---
# --- Neovim, Tmux, Linters ---
RUN add-apt-repository ppa:neovim-ppa/unstable && apt update 
RUN apt-get install apt-utils software-properties-common ca-certificates curl gnupg -y

# NODE JS and PYNVIM for use nvim
ARG NODE_MAJOR=20
RUN mkdir -p /etc/apt/keyrings
RUN curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
RUN echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list

RUN sudo apt-get update && sudo apt-get install -y \
    tmux \
    tmuxinator \
    neovim \
    nodejs \
    python3-pip \
    cpplint \
    cppcheck \
    xclip

RUN pip3 install pynvim cmakelint
# RUN pip3 install cmakelint -U
RUN pip3 install MAVProxy future

RUN sudo apt update && sudo apt install -y libsuitesparse-dev
RUN sudo apt install -y ros-$ROS_DISTRO-backward-ros
# glog: link dependency pulled in by g2o/ceres, required by dual_pose_graph (dps_slam)
RUN sudo apt install -y libgoogle-glog-dev
RUN apt-get update && apt-get install -y \
    ros-humble-libg2o \
    libceres-dev
RUN curl -fsSL https://claude.ai/install.sh | bash

# RTK - Rust Token Killer (https://github.com/rtk-ai/rtk)
RUN curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"
RUN rtk init -g

# Bind-mounted workspaces are owned by the host user (uid 1000) but the container
# runs as root -> git "dubious ownership". Trust all mounted repos (sandbox).
RUN git config --global --add safe.directory '*'

# --- Python deps: REMIND re-id tracker (torch, transformers, ultralytics) ---
# torch is installed first from an explicit CUDA index so ultralytics doesn't
# pull the latest PyPI wheel, whose CUDA build may not cover the host GPU's
# architecture (torch then silently falls back to CPU). Set the TORCH_* build
# args (docker-compose.yml) to a CUDA build that supports the host GPU.
# numpy is re-pinned LAST: opencv-python (an ultralytics dep) upgrades it to
# 2.x at the end of the install, and Ubuntu's scipy 1.8 is built against 1.x,
# so a 2.x numpy breaks every node importing scipy/sklearn with
# "numpy.core.multiarray failed to import".
ARG TORCH_VERSION=2.5.1
ARG TORCHVISION_VERSION=0.20.1
ARG TORCH_CUDA=cu121
RUN pip3 install --no-cache-dir \
      torch==${TORCH_VERSION} torchvision==${TORCHVISION_VERSION} \
      --index-url https://download.pytorch.org/whl/${TORCH_CUDA} \
 && pip3 install --no-cache-dir \
      opencv-python-headless tqdm transformers scikit-learn scipy psutil ultralytics \
 && pip3 install --no-cache-dir --force-reinstall "numpy<2"
# ultralytics also installs anyio, whose pytest plugin crashes the system pytest
# 6 (`No module named '_pytest.scope'`) and with it every `colcon test`.
ENV PYTEST_ADDOPTS="-p no:anyio"

# --- Entrypoint: shell setup, idempotent (the container restarts often) ---
RUN printf '%s\n' \
      '#!/bin/bash' \
      'add() { grep -qxF "$1" ~/.bashrc || echo "$1" >> ~/.bashrc; }' \
      "add 'source /opt/ros/$ROS_DISTRO/setup.bash'" \
      "add 'source /root/aerostack2_ws/install/setup.bash'" \
      "add '[ -f /root/workspace/install/setup.bash ] && source /root/workspace/install/setup.bash'" \
      "add 'export PATH=\"\$PATH:/root/.local/bin\"'" \
      "add \"alias vim='nvim'\"" \
      "add 'export ROS_LOCALHOST_ONLY=1'" \
      'exec "$@"' > /entrypoint.sh \
    && chmod a+x /entrypoint.sh

# USER $USERNAME
# WORKDIR /home/$USERNAME/
# # this folders are for nvim
RUN mkdir -p .config
RUN mkdir .local/share -p

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]

