FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential \
      libsdl1.2-dev \
      libglu1-mesa-dev \
      libvorbis-dev \
      libogg-dev \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
