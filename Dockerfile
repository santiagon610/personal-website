FROM        git.iwcg.io:5050/hlv/dockerfiles/hlv-hugo-aws:latest AS build-phase
RUN         mkdir -p /tmp/build && ls -al /tmp/build
COPY        --chown=hlvadmin:hlvadmin ./ /tmp/build
WORKDIR     /tmp/build
RUN         hugo && cd public && tar zcvf /tmp/built-site.tgz ./*

FROM        git.iwcg.io:5050/hlv/dockerfiles/nginx:latest
USER        root
COPY        nginx.conf /etc/nginx/nginx.conf
COPY        --from=build-phase --chown=nginx:nginx /tmp/built-site.tgz /tmp/built-site.tgz
RUN         tar zxvf /tmp/built-site.tgz -C /usr/share/nginx/html \
  && chown -R nginx:nginx /usr/share/nginx/* \
  && rm -f /tmp/built-site.tgz
USER        nginx
EXPOSE      8080
ENTRYPOINT  [ "nginx" ]
