FROM golang:1.21-alpine AS builder
WORKDIR /src
COPY go.mod .
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /auth .

FROM alpine:3.19
RUN apk add --no-cache ca-certificates wget && adduser -D -u 1001 appuser
COPY --from=builder /auth /auth
USER appuser
ENTRYPOINT ["/auth"]
