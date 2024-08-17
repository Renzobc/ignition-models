ARG UBUNTU_VERSION=jammy
ARG ROS_VERSION=humble
ARG FROM_IMAGE=ros:$ROS_VERSION
ARG OVERLAY_WS=/app

# MAKE SOME BASIC MODIFICATION TO THE BASE IMAGE
FROM $FROM_IMAGE AS dependencies_setter

# Set ignition variable for simulation
ENV IGN_PARTITION=renzobc
ENV IGNITION_VERSION=fortress
ENV IGN_VERBOSE=1

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
  apt-get update \
  && apt-get install -y -q --no-install-recommends\
  openssh-server \
  x11-apps \ 
  cmake \
  curl \
  wget \
  python3-pip \
  nano \ 
  gnupg2 \
  gdb \
  xcb \
  libqt5gui5 \
  libqt5core5a \
  libqt5widgets5 \
  wayland-protocols \
  libwayland-client0 \
  libwayland-server0 \
  git \
  sudo \
  clang \
  clang-tidy \
  build-essential \
  dirmngr \
  && pip install -U autopep8 \
  && rm -rf /var/lib/apt/lists/*

ENV CMAKE_MAKE_PROGRAM=/usr/bin/make
ENV CMAKE_CXX_COMPILER=/usr/bin/clang
ENV RMW_IMPLEMENTATION=rmw_fastrtps_cpp

RUN sudo sh -c 'echo "deb http://packages.osrfoundation.org/gazebo/ubuntu-stable `lsb_release -cs` main" > /etc/apt/sources.list.d/gazebo-stable.list' && \
wget http://packages.osrfoundation.org/gazebo.key -O - | sudo apt-key add - && \
sudo apt-get update -y && \
sudo apt-get install libignition-gazebo6-dev -y

# MAKE THE DEVELOPER VERSION OF THE IMAGE
FROM dependencies_setter as developer

# Set timezone
ENV TZ=Europe/Copenhagen 

# Set dds vendor environment variable
ENV RMW_IMPLEMENTATION=rmw_fastrtps_cpp

# Set access control
ARG USERNAME=renzobc
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USERNAME \
  && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME -s /bin/bash \
  && mkdir -p /home/$USERNAME/.vscode-server /home/$USERNAME/.vscode-server-insiders \
  && chown ${USER_UID}:${USER_GID} /home/$USERNAME/.vscode-server* \
  && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
  && chmod 0440 /etc/sudoers.d/$USERNAME

# Set main directory for start-up
WORKDIR /home/$USERNAME

USER $USERNAME

ARG ROS_SETUP
ARG WORKSPACE
ARG OVERLAY_WS


# MULTI-STAGE FOR CACHING
FROM dependencies_setter AS cacher

# copy sdf files
COPY ./models /app

# copy overlay source   
ARG OVERLAY_WS
WORKDIR $OVERLAY_WS/

# CMD ["tail", "-f", "/dev/null"]

# MULTI-STAGE FOR BUILDING DEPENDENCIES FROM SOURCE
FROM dependencies_setter AS prebuilder
ARG DEBIAN_FRONTEND=noninteractive

# install overlay dependencies
ARG OVERLAY_WS
WORKDIR $OVERLAY_WS

# install CI dependencies
RUN apt-get update && apt-get install -q -y --no-install-recommends \
  ccache \
  lcov \
  && mkdir src \
  && rm -rf /var/lib/apt/lists/*


# build overlay source
COPY --from=cacher $OVERLAY_WS ./
ARG OVERLAY_MIXINS="release ccache"

# BUILD CURRENT PROJECT WITH COLCON (CMAKE)
FROM dependencies_setter AS builder
ARG OVERLAY_WS
WORKDIR $OVERLAY_WS

RUN apt update \
  && apt install -y -q --no-install-recommends \
  clang-tidy \
  && rm -rf /var/lib/apt/lists/*


COPY --from=prebuilder $OVERLAY_WS/ ./
RUN rm -rf ./src/project_folder/build


# MULTI-STAGE FOR RUNNING   
FROM dependencies_setter AS runner

COPY --from=cacher $OVERLAY_WS/ ./

ENV IGN_RESOURCE_PATH=$OVERLAY_WS

ARG OVERLAY_WS
WORKDIR $OVERLAY_WS

# Run the ignition server with the correct sdf
# ENTRYPOINT [ "ign" ]
# CMD ["gazebo", "-sr" ,"/app/worlds/skuid_world_origin-server.sdf"]

CMD [ "tail", "-f", "/dev/null" ]
####################################################################

