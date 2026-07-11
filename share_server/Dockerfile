FROM dart:stable AS build
WORKDIR /app
COPY pubspec.yaml ./
RUN dart pub get
COPY . .
RUN dart pub get --offline && dart compile exe bin/pleya_share_server.dart -o /app/pleya_share_server

FROM debian:stable-slim
COPY --from=build /runtime/ /
COPY --from=build /app/pleya_share_server /usr/local/bin/pleya_share_server
VOLUME ["/data", "/media"]
EXPOSE 48634
ENV PLEYA_MEDIA=/media:mixed:Media \
    PLEYA_DATA=/data \
    PLEYA_NAME=Pleya-NAS
ENTRYPOINT ["pleya_share_server"]
