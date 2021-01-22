# Sandbox for Chrome to attach via rdp

FROM fedora:33 as basebuild

MAINTAINER lee.staples@gmail.com

# Update to latest pataches
RUN dnf update -y

# Create a User to run stuff as 
RUN useradd apps
RUN mkdir -p /home/apps/ && \ 
    chown apps:apps /home/apps -R

# Install google-chrome 
COPY ./google-chrome.repo /etc/yum.repos.d/google-chrome.repo
RUN dnf install google-chrome -y

# Install xrdp, pulse audio and openbox window manager
RUN dnf install xrdp xorgxrdp pulseaudio pulseaudio-libs openbox nano -y

# Configure User to Autostart chrome
RUN echo 'apps:Password123!' | chpasswd && \
    mkdir -p /home/apps/.config/openbox && \
    echo 'pulseaudio --daemonize=no --high-priority=no --realtime=no --disable-shm=yes --disallow-exit=yes &' > /home/apps/.config/openbox/autostart && \
    echo 'google-chrome --no-sandbox --full-screen &' >> /home/apps/.config/openbox/autostart && \
    echo 'exec openbox-session' > /home/apps/.xsession && \
    chmod +x /home/apps/.xsession && \
    chown apps:apps /home/apps -R && \
    groupmems --group audio --add apps && \
    systemctl --global disable pulseaudio.service pulseaudio.socket && \
    systemctl enable xrdp

# Clean up DNF
RUN dnf clean all

FROM basebuild as builder

# Install Pre-Requistes to build
RUN dnf groupinstall "Development Tools" -y && \
    dnf install rpmdevtools yum-utils -y && \
    rpmdev-setuptree

WORKDIR /root/

# Prepare pulse-audio devel lib for build
RUN dnf install pulseaudio pulseaudio-libs pulseaudio-libs-devel -y && \
    dnf builddep pulseaudio -y

# Download and build pulse audio source
RUN dnf download --source pulseaudio && \
    rpm --install pulseaudio*.src.rpm
RUN rpmbuild -bb --noclean /root/rpmbuild/SPECS/pulseaudio.spec

# Download and build pulse-audio module fr xrdp
RUN git clone --branch v0.5 https://github.com/neutrinolabs/pulseaudio-module-xrdp.git
WORKDIR /root/pulseaudio-module-xrdp/
RUN ./bootstrap && \
    ./configure PULSE_DIR=$(ls /root/rpmbuild/BUILD/pulseaudio* -d) && \
    make -j$(nproc)

FROM basebuild

COPY --from=builder /root/pulseaudio-module-xrdp /root/pulseaudio-module-xrdp
WORKDIR /root/pulseaudio-module-xrdp/src/
RUN /usr/bin/install -c .libs/module-xrdp-sink.so /usr/lib64/pulse-14.0/modules/module-xrdp-sink.so && \
    /usr/bin/install -c .libs/module-xrdp-sink.lai /usr/lib64/pulse-14.0/modules/module-xrdp-sink.la && \
    /usr/bin/install -c .libs/module-xrdp-source.so /usr/lib64/pulse-14.0/modules/module-xrdp-source.so && \
    /usr/bin/install -c .libs/module-xrdp-source.lai /usr/lib64/pulse-14.0/modules/module-xrdp-source.la && \
    PATH="/root/.local/bin:/root/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/sbin" ldconfig -n /usr/lib64/pulse-14.0/modules
WORKDIR /root
RUN rm /root/pulseaudio-module-xrdp -rf

# As this is running systemd need to change stop signal for clean exit 
# not needed for Podman as Podman plays nice with systemd
STOPSIGNAL SIGRTMIN+3

#Start Systemd
CMD [ "/sbin/init" ]
