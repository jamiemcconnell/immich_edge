FROM openresty/openresty:1.25.3.1-alpine

RUN apk add --no-cache gettext

COPY templates/ /etc/nginx/templates/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
