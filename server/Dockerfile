FROM amazoncorretto:21-alpine

ARG MC_VERSION=1.21
ARG FABRIC_LOADER_VERSION=0.15.11
ARG INSTALLER_VERSION=1.0.1

# Setup image
RUN apk add --update curl
RUN mkdir -p /home/minecraft/server
WORKDIR /home/minecraft/server

# Setup minecraft server
RUN curl -J https://meta.fabricmc.net/v2/versions/loader/${MC_VERSION}/${FABRIC_LOADER_VERSION}/${INSTALLER_VERSION}/server/jar -o server.jar
COPY .defaults/ .

EXPOSE 25565

CMD java -Xmx2G -jar server.jar nogui