
FROM --platform=linux/amd64 ghcr.io/cirruslabs/flutter:3.29.3 AS build
WORKDIR /app
COPY admin/ .
RUN flutter pub get
RUN flutter build web --release

# ---------- runtime stage ----------
FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
