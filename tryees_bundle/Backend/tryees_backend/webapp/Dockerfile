# ── Stage 1: build ──────────────────────────────────────────
FROM node:20-alpine AS build
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install
COPY . .
# true = mostra gli account demo nella pagina di accesso (vedi .env.example)
ARG VITE_SHOW_DEMO_USERS=false
ENV VITE_SHOW_DEMO_USERS=$VITE_SHOW_DEMO_USERS
RUN npm run build

# ── Stage 2: serve con nginx ────────────────────────────────
FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
