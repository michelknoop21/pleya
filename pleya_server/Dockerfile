# syntax=docker/dockerfile:1

# Pleya Server.
#
# De runtime is Debian en niet Alpine. Dat was in PS-0 een keuze voor later, en
# die later is nu: hoofdstuk 22 van de architectuur vraagt om een gepinde ffmpeg
# in de image, en de Intel-mediastack die de DS920+ nodig heeft (libva,
# intel-media-driver) is op glibc een pakket en op musl een project.

FROM golang:1.26.6-bookworm@sha256:116d58cbd88c1297624acc6e967a060012422bacf9930927e23fb719189c6f36 AS build

WORKDIR /src

# Afhankelijkheden apart, zodat een codewijziging de laag niet ongeldig maakt.
COPY go.mod go.sum ./
RUN go mod download

COPY cmd ./cmd
# internal/web/dist draagt de gebouwde Pleya Web-bundel. Die wordt hier niet
# gebouwd maar meegestuurd: de uitvoer is architectuurloos, dus een tweede
# toolchain in deze image zou hetzelfde resultaat opleveren voor meer tijd en
# meer geheugen, en op de NAS is dat een Celeron. Vullen doet
# pleya_web/scripts/build-into-server.sh, en deploy-nas.sh roept die zelf aan.
COPY internal ./internal

ARG VERSION=dev
ARG TARGETOS=linux
ARG TARGETARCH=amd64

# -tags release maakt de bundel verplicht. internal/web/release.go draagt een
# //go:embed naar dist/index.html, dus een release zonder gebouwde frontend
# faalt hier op de compiler in plaats van stil een lege pagina mee te nemen.
# Dat is acceptatiecriterium 2 van PS-3W, en dezelfde redenering als achter de
# harde ffmpeg-pin verderop.
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath -tags release -ldflags="-s -w -X main.version=${VERSION}" \
    -o /out/pleya-server ./cmd/pleya-server


# pg_dump en psql voor de back-ups (S25). Uit dezelfde postgres-image, op
# dezelfde digest, als de database in compose.yaml: een pg_dump moet minstens zo
# nieuw zijn als de server die hij dumpt, en Debian bookworm levert versie 15
# tegen een database op 18. Het PGDG-archief zou een tweede bron met een eigen
# sleutel en eigen pins zijn; deze laag is al gepind en al vertrouwd. Alleen de
# twee binaries en libpq gaan mee, de rest van de image niet: gemeten op
# linux/amd64 is dat 3,4 MiB (du -sx /, 575 668 naar 579 192 KiB).
FROM postgres:18.6-bookworm@sha256:7d2695c3aa88e792e8b3b233e7e4adb296a20412c6c0ca361e3edaaacfada108 AS pgclient


FROM debian:bookworm-slim@sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241

# ffmpeg op een exacte versie, want een mediaserver waarvan het gedrag afhangt
# van de ffmpeg van het hostsysteem is niet reproduceerbaar. Dat is dezelfde
# redenering als achter de MPVKit-pin in de app: een tag is een specifieke
# binary, en een zwevende versie wisselt de decoder onder het product vandaan.
#
# De pin is bewust hard. Verdwijnt deze versie van de spiegel omdat er een
# beveiligingsupdate overheen is gegaan, dan faalt de build luid in plaats van
# stil een andere ffmpeg mee te nemen. Bijwerken is dan het bewuste werk dat het
# hoort te zijn: versie hier omhoog, image opnieuw bouwen, afspelen verifiëren.
#
# Dit kost fors aan omvang: de image gaat van 81 MB naar 543 MB, gemeten met
# du -sx / op amd64. 159 MB daarvan is Mesa, LLVM, z3 en de DRI-drivers, die
# Pleya nergens voor gebruikt; ze komen mee via een keten van harde Depends
# (ffprobe -> libavdevice59 -> libgl1 -> ... -> libLLVM-15), dus
# --no-install-recommends verandert er niets aan. Zelf bouwen met
# --disable-avdevice haalt ze eruit; dat is niet gebeurd: PS-8 bleek geen eigen
# ffmpeg-bouw nodig te hebben, want de distributie-ffmpeg kent VAAPI. De
# drivers hieronder (iHD voor nieuwere, i965 voor oudere Intel-GPU's) en
# vainfo voor diagnose komen er alleen bij. Zie DEC-044 en DEC-158.
ARG FFMPEG_VERSION=7:5.1.9-0+deb12u1
RUN apt-get update \
 && apt-get install --no-install-recommends -y \
      ca-certificates \
      "ffmpeg=${FFMPEG_VERSION}" \
      intel-media-va-driver \
      i965-va-driver \
      vainfo \
      libldap-2.5-0 libgssapi-krb5-2 libzstd1 liblz4-1 libreadline8 \
 && rm -rf /var/lib/apt/lists/* \
 && ffprobe -version | head -1

# De vijf bibliotheken hierboven zijn wat pg_dump, psql en libpq 18 vragen
# bovenop wat de ffmpeg-stack al meebrengt. Ontbreekt er een, dan faalt de
# versieregel hieronder de build in plaats van de eerste back-up op de NAS.
COPY --from=pgclient /usr/lib/postgresql/18/bin/pg_dump /usr/lib/postgresql/18/bin/psql /usr/local/bin/
COPY --from=pgclient /usr/lib/*-linux-gnu/libpq.so.5* /usr/local/lib/
RUN ldconfig && pg_dump --version && psql --version

# Een non-root gebruiker in de image zelf, zodat "docker run" zonder compose
# ook niet als root draait. Compose overschrijft de uid/gid met die van de
# host, want op een NAS bepaalt de eigenaar van de bind mount wie mag lezen.
RUN groupadd --system --gid 1000 pleya \
 && useradd --system --uid 1000 --gid 1000 --no-create-home --shell /usr/sbin/nologin pleya

COPY --from=build /out/pleya-server /usr/local/bin/pleya-server

# De schrijfbare mappen bestaan in de image, zodat een start zonder mounts
# ook werkt. Ze horen los van elkaar gemount te worden: /config is duurzaam en
# is de back-up-eenheid, /cache is herbouwbaar, /transcode is vluchtig, en
# /backups hoort het liefst op een andere schijf dan /config (S25).
RUN mkdir -p /config /cache /transcode /backups /media \
 && chown pleya:pleya /config /cache /transcode /backups

USER 1000:1000
EXPOSE 8080

# De runtime bevat geen curl. Een volledige toolset toevoegen om één GET te doen
# staat niet in verhouding, dus doet de binary het zelf.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["/usr/local/bin/pleya-server", "healthcheck"]

# Exec-vorm, zodat SIGTERM rechtstreeks bij het Go-proces aankomt en niet bij
# een shell die hem opeet.
ENTRYPOINT ["/usr/local/bin/pleya-server"]
