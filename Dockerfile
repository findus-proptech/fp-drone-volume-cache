FROM alpine:3.4
MAINTAINER Arvid Petermann

COPY cacher.sh /usr/local/
RUN mkdir /cache && apk add --no-cache bash rsync findutils && chmod 755 /usr/local/cacher.sh
VOLUME /cache

ENTRYPOINT ["/usr/local/cacher.sh"]
