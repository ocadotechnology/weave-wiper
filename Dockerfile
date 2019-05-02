FROM alpine:3.7

RUN apk add --no-cache jq \
    curl \
    bash

COPY . /app
WORKDIR /app

ENTRYPOINT ["/app/wiper.bash"]
