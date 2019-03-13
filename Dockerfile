FROM mirror-internal.docker.tech.lastmile.com/internal-open-source/alpine-3.9:1.1.1

RUN apk add --no-cache jq \
    curl

COPY . /app
WORKDIR /app

ENTRYPOINT ["/app/wiper.bash"]
