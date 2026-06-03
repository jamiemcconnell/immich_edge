FROM alpine:3.19

RUN apk add --no-cache rsync

COPY seed.sh /seed.sh
COPY watch.sh /watch.sh
RUN chmod +x /seed.sh /watch.sh

CMD ["/watch.sh"]
