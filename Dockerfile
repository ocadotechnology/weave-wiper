FROM alpine:3.9

RUN apk add --no-cache jq \
    curl \
    bash

COPY . /app
WORKDIR /app

ENTRYPOINT ["/app/wiper.bash"]
