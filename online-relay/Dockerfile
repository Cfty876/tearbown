FROM node:24-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY server.mjs ./
USER node
ENV BIND=0.0.0.0
EXPOSE 8787
CMD ["node", "server.mjs"]
