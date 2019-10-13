FROM alpine:edge AS builder

# Workaround to install shards 0.8.1 from 3.9 because shards 9.0.0 is broken
RUN apk add --no-cache --update-cache --repository http://dl-cdn.alpinelinux.org/alpine/v3.9/community \
      shards==0.8.1-r0 \
      crystal libc-dev \
      libgit2-dev libsass-dev libssh2-static libressl-dev libxml2-dev yaml-dev zlib-static openssl-dev

WORKDIR /src
ADD shard.yml shard.yml
ADD shard.lock shard.lock
RUN shards install --production

ADD . ./

RUN rm -fr /root/.cache/crystal
# TODO: Can't get static linking with libsass and libgit2 with openssl, so we're manually
# specifying the static libraries available
#RUN shards build \
#  --production \
RUN mkdir -p bin && crystal build src/app.cr -o bin/app \
  --no-debug --verbose \
  --stats \
  --link-flags='/usr/lib/libyaml.a /usr/lib/libpcre.a /usr/lib/libm.a /usr/lib/libgc.a' \
  --link-flags='/usr/lib/libpthread.a /usr/lib/libevent.a /usr/lib/librt.a /usr/lib/libxml2.a' \
  && shards build worker \
  --link-flags='/usr/lib/libyaml.a /usr/lib/libpcre.a /usr/lib/libm.a /usr/lib/libgc.a' \
  --link-flags='/usr/lib/libpthread.a /usr/lib/libevent.a /usr/lib/librt.a /usr/lib/libxml2.a' 

FROM alpine:edge AS runtime
RUN apk add --no-cache --update-cache  \
# bash needed for dokku enter
      bash \
# executables needed at runtime
      git openssh \
# Couldn't get libsass and libgit2 with openssl to link statically, so they're
# needed as runtime dependencies
      libsass libgit2

RUN wget -O /usr/local/bin/dbmate https://github.com/amacneil/dbmate/releases/download/v1.7.0/dbmate-linux-amd64 \
  && chmod +x /usr/local/bin/dbmate

WORKDIR /app
COPY --from=builder /src /app
