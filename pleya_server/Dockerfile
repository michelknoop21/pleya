# syntax=docker/dockerfile:1

# Pleya Server, PS-0 Docker Foundation.
#
# De runtime is Debian en niet Alpine. Dat is een keuze voor later: hoofdstuk 22
# van de architectuur vraagt om een gepinde ffmpeg in de image, en de
# Intel-mediastack die de DS920+ nodig heeft (libva, intel-media-driver) is op
# glibc een pakket en op musl een project. Er zit in deze fase nog geen ffmpeg
# in; de basis moet hem alleen later kunnen dragen.

FROM golang:1.26.6-bookworm@sha256:116d58cbd88c1297624acc6e967a060012422bacf9930927e23fb719189c6f36 AS build

WORKDIR /src

# Afhankelijkheden apart, zodat een codewijziging de laag niet ongeldig maakt.
COPY go.mod go.sum ./
RUN go mod download

COPY cmd ./cmd
COPY internal ./internal

ARG VERSION=dev
ARG TARGETOS=linux
ARG TARGETARCH=amd64

RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath -ldflags="-s -w -X main.version=${VERSION}" \
    -o /out/pleya-server ./cmd/pleya-server


FROM debian:bookworm-slim@sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241

# ca-certificates en verder niets. Elk pakket meer is straks een pakket dat
# meegepatcht moet worden zonder dat iemand weet waarom het er staat.
RUN apt-get update \
 && apt-get install --no-install-recommends -y ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Een non-root gebruiker in de image zelf, zodat "docker run" zonder compose
# ook niet als root draait. Compose overschrijft de uid/gid met die van de
# host, want op een NAS bepaalt de eigenaar van de bind mount wie mag lezen.
RUN groupadd --system --gid 1000 pleya \
 && useradd --system --uid 1000 --gid 1000 --no-create-home --shell /usr/sbin/nologin pleya

COPY --from=build /out/pleya-server /usr/local/bin/pleya-server

# De drie schrijfbare mappen bestaan in de image, zodat een start zonder mounts
# ook werkt. Ze horen los van elkaar gemount te worden: /config is duurzaam en
# is de back-up-eenheid, /cache is herbouwbaar, /transcode is vluchtig.
RUN mkdir -p /config /cache /transcode /media \
 && chown pleya:pleya /config /cache /transcode

USER 1000:1000
EXPOSE 8080

# De runtime bevat geen curl. Een volledige toolset toevoegen om één GET te doen
# staat niet in verhouding, dus doet de binary het zelf.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["/usr/local/bin/pleya-server", "healthcheck"]

# Exec-vorm, zodat SIGTERM rechtstreeks bij het Go-proces aankomt en niet bij
# een shell die hem opeet.
ENTRYPOINT ["/usr/local/bin/pleya-server"]
