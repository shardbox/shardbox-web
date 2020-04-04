FROM crystallang/crystal:0.33.0-alpine AS builder

RUN apk add --no-cache --update-cache \
      libgit2-dev libsass-dev libssh2-static

WORKDIR /src
ADD shard.yml shard.lock ./
RUN shards install --production

ADD . ./

# TODO: Can't get static linking with libsass and libgit2 with openssl, so we're manually
# specifying the static libraries available
#RUN shards build \
#  --production \
RUN mkdir -p bin && crystal build src/app.cr -o bin/app \
  --no-debug --progress\
  --stats \
  --link-flags='/usr/lib/libyaml.a /usr/lib/libpcre.a /usr/lib/libm.a /usr/lib/libgc.a' \
  --link-flags='/usr/lib/libpthread.a /usr/lib/libevent.a /usr/lib/librt.a /usr/lib/libxml2.a /usr/lib/liblzma.a' \
  1>&2 \
  && shards build worker \
  --link-flags='/usr/lib/libyaml.a /usr/lib/libpcre.a /usr/lib/libm.a /usr/lib/libgc.a' \
  --link-flags='/usr/lib/libpthread.a /usr/lib/libevent.a /usr/lib/librt.a /usr/lib/libxml2.a /usr/lib/liblzma.a' \
  1>&2

FROM alpine:3.11 AS runtime
RUN apk add --no-cache --update-cache  \
# bash needed for dokku enter
      bash \
# executables needed at runtime
      git openssh \
# Couldn't get libsass and libgit2 with openssl to link statically, so they're
# needed as runtime dependencies
      libsass libgit2

RUN wget -qO /usr/local/bin/dbmate https://github.com/amacneil/dbmate/releases/download/v1.7.0/dbmate-linux-musl-amd64 \
  && chmod +x /usr/local/bin/dbmate

WORKDIR /app
COPY --from=builder /src /app
