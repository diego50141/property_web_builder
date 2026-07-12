# Development image for PropertyWebBuilder (isolated dev stack).
# Source code is bind-mounted at runtime; gems install into a named volume.
# This is intentionally separate from the production ./Dockerfile.
FROM ruby:3.4-slim-bookworm

# System deps: build tools for native gems (pg, ffi, nokogiri), imagemagick
# for ActiveStorage variants (variant_processor es :mini_magick — sin él las
# imágenes responden 500), postgresql-client for pg_isready/psql, git.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential \
      git \
      curl \
      imagemagick \
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
