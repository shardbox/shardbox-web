FROM alpine:3.11 AS builder

RUN apk add --no-cache --update-cache \
      crystal libc-dev \
      libgit2-dev libsass-dev libssh2-static libressl-dev libxml2-dev yaml-dev zlib-static openssl-dev

# Workaround to install shards 0.8.1 from official package because shards 9.0.0
# provided by apk is broken
RUN wget -qO- https://github.com/crystal-lang/crystal/releases/download/0.31.1/crystal-0.31.1-1-linux-x86_64.tar.gz \
  | tar -xz \
  && ln -s /crystal-0.31.1-1/bin/shards /usr/local/bin/shards \
  && apk add --no-cache git

WORKDIR /src
ADD shard.yml shard.yml
ADD shard.lock shard.lock
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
