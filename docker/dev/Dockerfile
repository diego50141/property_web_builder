# Development image for PropertyWebBuilder (isolated dev stack).
# Source code is bind-mounted at runtime; gems install into a named volume.
# This is intentionally separate from the production ./Dockerfile.
FROM ruby:3.4-slim-bookworm

# System deps: build tools for native gems (pg, ffi, nokogiri), libvips for
# ActiveStorage image processing, postgresql-client for pg_isready/psql, git.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential \
      git \
      curl \
      libpq-dev \
      libvips-dev \
      libyaml-dev \
      pkg-config \
      postgresql-client \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

WORKDIR /app

ENV RAILS_ENV=development \
    BUNDLE_PATH=/usr/local/bundle \
    LANG=C.UTF-8 \
    TZ=America/Bogota

EXPOSE 3000

CMD ["bash", "/app/docker/dev/entrypoint.sh"]
