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
RUN sudo apt-get install -y ros-humble-mavros ros-humble-mavros-extras
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
RUN apt-get update && apt-get install -y ros-humble-rosbag2-storage-mcap

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
RUN pip3 install "numpy<2.0.0" scikit-learn ultralytics opencv-python

RUN sudo apt update && sudo apt install -y libsuitesparse-dev
RUN sudo apt install -y ros-$ROS_DISTRO-backward-ros
# glog: link dependency pulled in by g2o/ceres, required by dual_pose_graph (dps_slam)
RUN sudo apt install -y libgoogle-glog-dev
RUN apt-get update && apt-get install -y \
    ros-humble-libg2o \
    libceres-dev 
RUN curl -fsSL https://claude.ai/install.sh | bash

# --- Shell environment ---
RUN echo "source /opt/ros/$ROS_DISTRO/setup.bash" >> ~/.bashrc \
    && echo "source $HOME/workspace/install/setup.bash" >> ~/.bashrc \
    && echo "source $HOME/aerostack2_ws/install/setup.bash" >> ~/.bashrc \
    && echo 'export PATH="$PATH:$HOME/.local/bin"' >> ~/.bashrc \
    && echo "alias vim='nvim'" >> ~/.bashrc \
    && echo "export ROS_LOCALHOST_ONLY=1" >> ~/.bashrc

# USER $USERNAME
# WORKDIR /home/$USERNAME/
# # this folders are for nvim
RUN mkdir .config
RUN mkdir .local/share -p

CMD ["bash"]

