# Test image for one distribution: every packaged Vim variant that differs
# in the features the suite sees, the display servers and clipboard tools
# the suite starts and nothing from the repository, which is mounted at run
# time.
ARG BASE=debian:stable
FROM $BASE

RUN set -eu; \
    if command -v apt-get >/dev/null; then \
        apt-get update; \
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
            vim-tiny vim vim-gtk3 xvfb sway xwayland wl-clipboard xclip wtype fonts-dejavu-core; \
        rm -rf /var/lib/apt/lists/*; \
        printf 'VIM_BIN="vim.tiny vim.basic vim.gtk3"\nGVIM_BIN="vim.gtk3"\n' >/etc/buckler-test.env; \
    elif command -v dnf >/dev/null; then \
        dnf -y install vim-minimal vim-enhanced vim-X11 \
            xorg-x11-server-Xvfb sway xorg-x11-server-Xwayland wl-clipboard xclip wtype dejavu-sans-mono-fonts; \
        dnf clean all; \
        # the packaged sway carries a file capability an unprivileged container cannot grant
        setcap -r /usr/bin/sway; \
        printf 'VIM_BIN="vi vim vimx"\nGVIM_BIN="gvim"\n' >/etc/buckler-test.env; \
    else \
        echo "unsupported base image" >&2; exit 1; \
    fi

RUN mkdir -p /results /tmp/.X11-unix && chmod 1777 /results /tmp /tmp/.X11-unix
WORKDIR /src
