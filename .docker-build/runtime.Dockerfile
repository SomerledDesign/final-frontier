FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libsdl1.2debian \
      libglu1-mesa \
      libvorbisfile3 \
      libgl1 \
      libgl1-mesa-dri \
      libx11-6 \
      libxext6 \
      mesa-utils \
      xvfb \
      xauth \
      x11vnc \
      xdotool \
      novnc \
      websockify \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /game
COPY frontier fe2.s.bin start.sh ./
COPY sfx ./sfx
COPY music ./music
RUN chmod +x frontier start.sh
ENV LIBGL_ALWAYS_SOFTWARE=1
ENV SDL_VIDEODRIVER=x11
ENV DISPLAY=:99
EXPOSE 5900 6080
CMD ["./start.sh"]
