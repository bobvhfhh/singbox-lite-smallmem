ARG DISTRO=ubuntu:24.04
FROM ${DISTRO}
RUN if command -v apk >/dev/null; then apk add --no-cache bash curl ca-certificates; else apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends bash curl ca-certificates; fi
CMD ["sleep", "infinity"]
