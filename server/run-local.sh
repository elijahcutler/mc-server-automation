#!/bin/bash
docker build -t mc-fabric-server .
docker volume create --name mc-world
docker run -dit -p 25565:25565 -v mc-world:/home/minecraft/server/world -t mc-fabric-server