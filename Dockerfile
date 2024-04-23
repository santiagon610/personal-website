FROM        docker.io/alpine:3 AS build-phase
USER        root
RUN         apk add curl hugo tar
RUN         hugo version
RUN         mkdir -p /tmp/build && ls -al /tmp/build
COPY        --chown=1001:1001 ./ /tmp/build
WORKDIR     /tmp/build
RUN         hugo && cd public && tar zcvf /tmp/built-site.tgz ./*

FROM        docker.io/nginxinc/nginx-unprivileged:latest
USER        root
COPY        nginx.conf /etc/nginx/nginx.conf
COPY        --from=build-phase --chown=nginx:nginx /tmp/built-site.tgz /tmp/built-site.tgz
RUN         tar zxvf /tmp/built-site.tgz -C /usr/share/nginx/html \
  && chown -R nginx:nginx /usr/share/nginx/* \
  && rm -f /tmp/built-site.tgz
USER        nginx
EXPOSE      8080
ENTRYPOINT  [ "nginx" ]
