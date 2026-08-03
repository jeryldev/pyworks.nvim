# Reproduce the environment from issue #10 as closely as we can:
# Linux, Neovim 0.12.x, uv-managed Python 3.13, ipykernel 7, molten-nvim,
# and a notebook whose path is non-ASCII.
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git tar xz-utils locales \
    && sed -i 's/# ru_RU.UTF-8/ru_RU.UTF-8/' /etc/locale.gen \
    && locale-gen en_US.UTF-8 ru_RU.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# Neovim from the official release tarball (matches their 0.12.x)
ARG NVIM_VERSION=stable
RUN arch="$(uname -m)" \
    && case "$arch" in \
         x86_64)  asset=nvim-linux-x86_64 ;; \
         aarch64) asset=nvim-linux-arm64 ;; \
         *) echo "unsupported arch $arch" && exit 1 ;; \
       esac \
    && curl -fsSL "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/${asset}.tar.gz" \
       | tar xz -C /opt \
    && ln -s "/opt/${asset}/bin/nvim" /usr/local/bin/nvim

# uv, then the exact interpreter they run
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"
RUN uv python install 3.13

# molten-nvim
# The forks pyworks actually ships (see lazy.lua). The molten fork carries
# fixes for dict-iteration safety and MoltenTick reentrancy that upstream lacks,
# and the reentrancy one is directly relevant to notebook reload freezes - so
# testing against upstream would not be testing what users run.
RUN git clone --depth 1 https://github.com/jeryldev/molten-nvim /opt/molten-nvim \
    && git clone --depth 1 https://github.com/jeryldev/image.nvim /opt/image.nvim

# A project shaped like theirs: venv at the project root, notebook in a
# Cyrillic-named subdirectory
WORKDIR /work/project
RUN uv venv --python 3.13 .venv \
    && uv pip install --python .venv/bin/python \
         pynvim ipykernel jupyter_client jupytext \
    && .venv/bin/python -m ipykernel install --user --name mypjs_python \
         --display-name "Python (project)"

# molten writes its connection file here; without the directory MoltenInit
# fails with ENOENT and the kernel never starts
RUN mkdir -p /root/.local/share/jupyter/runtime

# jupyterlab is in pyworks' default essentials; install it up front so the
# scenario is not racing an install
RUN uv pip install --python /work/project/.venv/bin/python jupyterlab numpy pandas matplotlib

RUN mkdir -p "/work/project/нейророботика"
COPY notebook.ipynb "/work/project/нейророботика/нейророботика_экзамен.ipynb"
COPY run_scenario.lua init.lua /work/
COPY entrypoint.sh /work/entrypoint.sh
RUN chmod +x /work/entrypoint.sh

ENTRYPOINT ["/work/entrypoint.sh"]
