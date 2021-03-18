FROM alpine:latest
USER root
ARG PYTHON_VERSION=3.9.2
ENV PYTHON_VERSION $PYTHON_VERSION
RUN echo "http://dl-cdn.alpinelinux.org/alpine/edge/main" > /etc/apk/repositories && \
  echo "http://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories && \
  echo "http://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories && \
  apk upgrade --no-cache -U -a && \
  apk add --no-cache sudo bash
RUN apk add --no-cache --upgrade \
  ca-certificates curl perl wget aria2 util-linux gnupg rng-tools-extra \
  git build-base make openssl-dev libffi-dev \
  ncurses ncurses-dev \
  bash bash-completion \
  sudo shadow libcap \
  coreutils findutils binutils grep gawk \
  jq yq yj yq-bash-completion \
  htop bzip2 \
  yarn nodejs \
  bat glow \
  ripgrep ripgrep-bash-completion \
  tokei exa starship nushell just

# [ NOTE ] => set timezone info
RUN ln -fs /usr/share/zoneinfo/Etc/UTC /etc/localtime
ENV USER=gitpod
SHELL ["bash","-c"]
RUN getent group sudo > /dev/null || sudo addgroup sudo
RUN getent passwd "${USER}" > /dev/null && userdel --remove "${USER}" -f || true
RUN useradd --user-group --create-home --shell /bin/bash --uid 33333 "${USER}"
RUN sed -i \
  -e 's/# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/g' \
  -e 's/%sudo\s\+ALL=(ALL\(:ALL\)\?)\s\+ALL/%sudo ALL=NOPASSWD:ALL/g' \
  /etc/sudoers
RUN usermod -aG wheel,root,sudo "${USER}"

# python dev tools
ENV PYTHON_BUILD_PACKAGES="\
  bzip2-dev \
  coreutils \
  dpkg-dev dpkg \
  expat-dev \
  findutils \
  gcc \
  gdbm-dev \
  libc-dev \
  libffi-dev \
  libnsl-dev \
  libtirpc-dev \
  linux-headers \
  make \
  ncurses-dev \
  libressl-dev \
  pax-utils \
  readline-dev \
  sqlite-dev \
  tcl-dev \
  tk \
  tk-dev \
  util-linux-dev \
  xz-dev \
  zlib-dev \
  git \
  "
ENV PYTHON_PATH=/usr/local/bin/
ENV PATH="${PATH}:/usr/local/lib/python${PYTHON_VERSION}/bin"
ENV PATH="${PATH}:/usr/local/lib/pyenv/versions/${PYTHON_VERSION}/bin:${PATH}"
RUN set -ex ;\
  export PYTHON_MAJOR_VERSION=$(echo "${PYTHON_VERSION}" | rev | cut -d"." -f3-  | rev) ;\
  export PYTHON_MINOR_VERSION=$(echo "${PYTHON_VERSION}" | rev | cut -d"." -f2-  | rev) ;\
  apk add \
  --no-cache \
  --virtual \
  .build-deps ${PYTHON_BUILD_PACKAGES} || \
  (sed -i -e 's/dl-cdn/dl-4/g' /etc/apk/repositories && apk add \
  --no-cache \
  --virtual .build-deps \
  ${PYTHON_BUILD_PACKAGES}) 
ENV PYENV_ROOT="/usr/local/lib/pyenv"
ENV CONFIGURE_OPTS="--enable-shared"
ENV CONFIGURE_OPTS="${CONFIGURE_OPTS} --with-system-expat"
ENV CONFIGURE_OPTS="${CONFIGURE_OPTS} --with-system-ffi"
ENV CONFIGURE_OPTS="${CONFIGURE_OPTS} --without-ensurepip"
ENV CONFIGURE_OPTS="${CONFIGURE_OPTS} --enable-optimizations"

# ENV CONFIGURE_OPTS="${CONFIGURE_OPTS} --enable-loadable-sqlite-extensions"
RUN set -ex ;\
  git clone --depth 1 https://github.com/pyenv/pyenv /usr/local/lib/pyenv ;\
  export GNU_ARCH="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)" ;\
  export CONFIGURE_OPTS="${CONFIGURE_OPTS} --build=${GNU_ARCH}" ;\
  /usr/local/lib/pyenv/bin/pyenv install ${PYTHON_VERSION}
RUN set -ex ;\
  find /usr/local \
  -type f \
  -executable \
  -not \( -name '*tkinter*' \) \
  -exec scanelf \
  --needed \
  --nobanner \
  --format '%n#p' '{}' ';' \
  | tr ',' '\n' \
  | sort -u \
  | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
  | grep -ve 'libpython' \
  | xargs -rt apk add --no-cache --virtual .python-rundeps 
RUN set -ex ;\ 
  find /usr/local/lib/pyenv \
  -mindepth 1 \
  -name versions \
  -prune \
  -o -exec rm -rf {} \; || true ;\
  find "/usr/local/lib/pyenv/versions/${PYTHON_VERSION}" \
  -depth \
  -name '*.pyo' \
  -o -name '*.pyc' \
  -o -name 'test' \
  -o -name 'tests' \
  -exec rm -rf '{}' + ;\
  ln -s /usr/local/lib/pyenv/versions/${PYTHON_VERSION}/bin/* "${PYTHON_PATH}"
USER ${USER}
SHELL ["bash","-c"]
ENV HOME="/home/${USER}"
RUN python3 --version && \
  sudo chown "$(id -u):$(id -g)" "${HOME}" -R && \
  echo 'eval "$(starship init bash)"' | tee -a ~/.bashrc > /dev/null && \
  sudo rm -rf /var/cache/apk/*
ENV PATH="${PATH}:${HOME}/.local/bin"
ENV PATH="${PATH}:${HOME}/.poetry/bin"
RUN mkdir -p "${HOME}/.local/bin" && \
  mkdir -p "${HOME}/.poetry/bin" && \ 
  curl -fsSL \
  https://raw.githubusercontent.com/python-poetry/poetry/master/get-poetry.py | python3 && \
  poetry --version
RUN nu -c 'config set path $nu.path' && \
  nu -c 'config set env  $nu.env' && \
  nu -c 'config set prompt "starship prompt"'
RUN sudo usermod --shell /usr/bin/nu "${USER}"
RUN python3 -m pip install detect-secrets pex dephell[full]
RUN detect-secrets --version && \
  dephell --version && \
  pex --version
WORKDIR "/workspace/detect-secrets"
