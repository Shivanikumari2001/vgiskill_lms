# # Multi-stage Dockerfile for Frappe LMS
# FROM python:3.13-slim AS base

# # Set environment variables
# ENV DEBIAN_FRONTEND=noninteractive \
#     PYTHONUNBUFFERED=1 \
#     NODE_VERSION=20 \
#     BENCH_VERSION=5.27.0 \
#     FRAPPE_USER=frappe \
#     FRAPPE_HOME=/home/frappe \
#     BENCH_PATH=/home/frappe/frappe-bench

# # Install system dependencies
# RUN apt-get update && apt-get install -y \
#     curl \
#     wget \
#     git \
#     build-essential \
#     mariadb-client \
#     default-libmysqlclient-dev \
#     redis-tools \
#     redis-server \
#     sudo \
#     cron \
#     vim \
#     pkg-config \
#     libssl-dev \
#     libffi-dev \
#     libjpeg-dev \
#     zlib1g-dev \
#     libpng-dev \
#     libfreetype6-dev \
#     && rm -rf /var/lib/apt/lists/*

# # Install Node.js 20
# RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
#     && apt-get install -y nodejs \
#     && npm install -g yarn

# # Create frappe user
# RUN useradd -m -s /bin/bash ${FRAPPE_USER} \
#     && echo "${FRAPPE_USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# # Install bench CLI
# RUN pip3 install --no-cache-dir frappe-bench==${BENCH_VERSION}

# # Switch to frappe user
# USER ${FRAPPE_USER}
# WORKDIR ${FRAPPE_HOME}

# # Copy local frappe-bench structure (excluding files in .dockerignore)
# # This copies apps, config, sites structure, etc. but excludes:
# # - node_modules/ (will be installed in container)
# # - env/ (virtual environment, will be recreated)
# # - logs/ (runtime logs)
# # - __pycache__/ (Python cache)
# # - sites/assets/ (will be built in container)
# COPY --chown=${FRAPPE_USER}:${FRAPPE_USER} frappe-bench/ ${BENCH_PATH}/

# WORKDIR ${BENCH_PATH}

# # Ensure sites directory structure exists
# RUN mkdir -p sites

# # Ensure config/pids directory exists (needed for Redis)
# RUN mkdir -p config/pids

# # Ensure apps.txt exists (list of installed apps)
# RUN if [ ! -f "sites/apps.txt" ]; then \
#         echo -e "frappe\nlms\npayments" > sites/apps.txt; \
#     fi

# # Remove any existing env directory (in case it was partially copied)
# RUN rm -rf env

# # Recreate Python virtual environment (since we excluded env/ in .dockerignore)
# RUN python3 -m venv env

# # Initialize git repositories for apps that aren't already git repos
# # This is required because bench expects all apps to be git repositories
# RUN for app_dir in apps/*/; do \
#         if [ ! -d "${app_dir}.git" ]; then \
#             (cd "${app_dir}" && \
#             git init && \
#             git config user.email "docker@frappe.local" && \
#             git config user.name "Docker Build" && \
#             git add . 2>/dev/null || true && \
#             git commit -m "Initial commit" 2>/dev/null || true); \
#         fi; \
#     done

# # Install Python dependencies for all apps
# RUN bench setup requirements

# # Install Node.js dependencies for all apps (using existing lockfiles)
# RUN if [ -f "apps/frappe/yarn.lock" ]; then \
#         cd apps/frappe && yarn install --frozen-lockfile; \
#     fi
# RUN if [ -f "apps/lms/yarn.lock" ]; then \
#         cd apps/lms && yarn install --frozen-lockfile; \
#     fi
# RUN if [ -f "apps/payments/yarn.lock" ]; then \
#         cd apps/payments && yarn install --frozen-lockfile; \
#     fi

# # Fix workspace JSON source file to remove charts (prevents UI breakage)
# RUN python3 << 'PYEOF'
# import json
# import os

# workspace_file = "/home/frappe/frappe-bench/apps/lms/lms/lms/workspace/lms/lms.json"
# if os.path.exists(workspace_file):
#     with open(workspace_file, 'r') as f:
#         data = json.load(f)
    
#     # Remove charts array
#     if 'charts' in data:
#         data['charts'] = []
    
#     # Remove chart blocks from content
#     if 'content' in data and data['content']:
#         try:
#             content_blocks = json.loads(data['content'])
#             content_blocks = [b for b in content_blocks if b.get('type') != 'chart']
#             data['content'] = json.dumps(content_blocks)
#         except:
#             pass
    
#     with open(workspace_file, 'w') as f:
#         json.dump(data, f, indent=1)
#     print("Workspace JSON fixed in source")
# PYEOF

# # Build stage - Build assets
# FROM base AS builder

# WORKDIR ${BENCH_PATH}

# # Create sites/assets directory structure
# RUN mkdir -p sites/assets

# # Build assets using yarn build, then copy to sites/assets/ (Frappe's expected location)
# # Frappe assets
# RUN cd apps/frappe && yarn build 2>&1 || echo "Frappe build completed with warnings" && \
#     mkdir -p ../sites/assets/frappe && \
#     cp -r frappe/public/* ../sites/assets/frappe/ 2>/dev/null || true

# # LMS assets (includes frontend build)
# RUN cd apps/lms && yarn build 2>&1 || echo "LMS build completed with warnings" && \
#     mkdir -p ../sites/assets/lms/frontend && \
#     cp -r lms/public/frontend/* ../sites/assets/lms/frontend/ 2>/dev/null || true && \
#     echo "LMS assets copied to sites/assets/lms/frontend/"

# # Payments assets (if build script exists)
# RUN if [ -f "apps/payments/package.json" ] && grep -q '"build"' apps/payments/package.json; then \
#         cd apps/payments && yarn build 2>&1 || echo "Payments build completed with warnings" && \
#         mkdir -p ../sites/assets/payments && \
#         cp -r payments/public/* ../sites/assets/payments/ 2>/dev/null || true; \
#     else \
#         echo "Payments has no build script, skipping"; \
#     fi

# # Production stage
# FROM base AS production

# # Copy built assets from builder
# COPY --from=builder ${BENCH_PATH}/sites/assets ${BENCH_PATH}/sites/assets

# # Copy entrypoint script and SSL patch
# COPY --chown=${FRAPPE_USER}:${FRAPPE_USER} docker-entrypoint.sh /usr/local/bin/
# COPY --chown=${FRAPPE_USER}:${FRAPPE_USER} patch-ssl-disable.py /usr/local/bin/
# RUN chmod +x /usr/local/bin/docker-entrypoint.sh /usr/local/bin/patch-ssl-disable.py

# # Copy VariPhi logo to replace Frappe logos
# COPY --chown=${FRAPPE_USER}:${FRAPPE_USER} variphi-logo.png ${BENCH_PATH}/apps/frappe/frappe/public/images/variphi-logo.png

# # Apply SSL disable patch
# RUN BENCH_PATH=${BENCH_PATH} python3 /usr/local/bin/patch-ssl-disable.py

# # Create necessary directories
# RUN mkdir -p ${BENCH_PATH}/sites/localhost/private/files \
#     ${BENCH_PATH}/sites/localhost/public/files \
#     ${BENCH_PATH}/logs

# # Expose ports
# EXPOSE 8000 9000 11000 13000

# # Set working directory
# WORKDIR ${BENCH_PATH}

# # Health check
# HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
#     CMD curl -f http://localhost:8000 || exit 1

# # Entrypoint
# ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
# CMD ["bench", "start"]



# =========================
# Base Image
# =========================
FROM python:3.11-slim AS base

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    NODE_VERSION=20 \
    BENCH_VERSION=5.27.0 \
    FRAPPE_USER=frappe \
    FRAPPE_HOME=/home/frappe \
    BENCH_PATH=/home/frappe/frappe-bench

# -------------------------
# System dependencies
# -------------------------
RUN apt-get update && apt-get install -y \
    curl wget git build-essential \
    mariadb-client default-libmysqlclient-dev \
    sudo cron vim pkg-config \
    libssl-dev libffi-dev \
    libjpeg-dev zlib1g-dev \
    libpng-dev libfreetype6-dev \
    && rm -rf /var/lib/apt/lists/*

# -------------------------
# Node.js
# -------------------------
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g yarn \
    && npm cache clean --force

# -------------------------
# Frappe user
# -------------------------
RUN useradd -m -s /bin/bash ${FRAPPE_USER} \
    && echo "${FRAPPE_USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# -------------------------
# Bench CLI
# -------------------------
RUN pip install --no-cache-dir frappe-bench==${BENCH_VERSION}

USER ${FRAPPE_USER}
WORKDIR ${FRAPPE_HOME}

# -------------------------
# Copy bench
# -------------------------
COPY --chown=${FRAPPE_USER}:${FRAPPE_USER} frappe-bench/ ${BENCH_PATH}/
WORKDIR ${BENCH_PATH}

RUN mkdir -p sites config/pids logs \
    && rm -rf env \
    && python3 -m venv env

# -------------------------
# Ensure apps.txt
# -------------------------
RUN if [ ! -f sites/apps.txt ]; then \
      echo -e "frappe\nlms\npayments" > sites/apps.txt; \
    fi

# -------------------------
# Ensure git repos
# -------------------------
RUN for app in apps/*/; do \
      if [ ! -d "${app}.git" ]; then \
        cd "$app" && git init && \
        git config user.email docker@local && \
        git config user.name docker && \
        git add . && git commit -m "init" || true; \
      fi; \
    done

# -------------------------
# Python deps
# -------------------------
RUN bench setup requirements

# -------------------------
# Node deps
# -------------------------
RUN for app in frappe lms payments; do \
      if [ -f "apps/$app/yarn.lock" ]; then \
        cd apps/$app && yarn install --frozen-lockfile || true; \
      fi; \
    done

# =========================
# Build Assets
# =========================
FROM base AS builder

WORKDIR ${BENCH_PATH}
RUN mkdir -p sites/assets

RUN for app in frappe lms payments; do \
      if [ -f "apps/$app/package.json" ]; then \
        cd apps/$app && yarn build || true; \
      fi; \
    done

# =========================
# Production Image
# =========================
FROM base AS production

COPY --from=builder ${BENCH_PATH}/sites/assets ${BENCH_PATH}/sites/assets

COPY --chown=${FRAPPE_USER}:${FRAPPE_USER} docker-entrypoint.sh /usr/local/bin/
COPY --chown=${FRAPPE_USER}:${FRAPPE_USER} patch-ssl-disable.py /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

COPY --chown=${FRAPPE_USER}:${FRAPPE_USER} variphi-logo.png \
  ${BENCH_PATH}/apps/frappe/frappe/public/images/variphi-logo.png

RUN BENCH_PATH=${BENCH_PATH} python3 /usr/local/bin/patch-ssl-disable.py

EXPOSE 8000 9000

WORKDIR ${BENCH_PATH}

HEALTHCHECK --interval=30s --timeout=10s --start-period=120s \
  CMD curl -f http://localhost:8000 || exit 1

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["bench", "start"]
#  code test