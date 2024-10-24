# syntax=docker/dockerfile:1

FROM --platform=linux/amd64 node:12.18.1
ENV NODE_ENV=production
ENV DOCKER_DEFAULT_PLATFORM=linux/amd64

WORKDIR /app

COPY ["package.json", "package-lock.json*", "./"]

RUN npm install --production

COPY . .

EXPOSE 8080
CMD [ "node", "server.js" ]