# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with docker-compose.yml or build'n'run by hand:
# docker build -t clubhouse3 .
# docker run -d -p 3000:3000 -e RAILS_MASTER_KEY=<value from config/master.key> --name clubhouse3 clubhouse3

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=4.0.9
ARG NODE_VERSION=24.2.0
FROM node:${NODE_VERSION}-slim AS node
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /app

# Install base packages. Docker Hub stops rebuilding a Ruby patch tag once a newer
# patch ships, so its Debian packages go stale: upgrade them here. A cached layer
# keeps the old ones, so build with --no-cache to pick up new fixes.
RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y && \
    apt-get install --no-install-recommends -y curl default-mysql-client libjemalloc2 libvips && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential default-libmysqlclient-dev git libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Node is a build-time dependency only: assets:precompile resolves the daisyUI
# Tailwind plugin from node_modules, and cssbundling-rails runs `npm run build:css`.
COPY --from=node /usr/local/bin /usr/local/bin
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules

# Install application gems
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Install node modules
COPY package.json package-lock.json ./
RUN npm ci

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# node_modules are not needed at runtime
RUN rm -rf node_modules

# Final stage for app image
FROM base

# Copy built artifacts: gems, application
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /app /app

# Run and own only the runtime files as a non-root user for security.
# log/, storage/ and tmp/pids/ are gitignored, so they may be absent from the build context.
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --shell /bin/bash && \
    mkdir -p log storage tmp/pids && \
    chown -R rails:rails db log storage tmp
USER 1000:1000

# Entrypoint enables jemalloc. It does not run migrations; see docker-compose.yml.
ENTRYPOINT ["/app/bin/docker-entrypoint"]

EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
