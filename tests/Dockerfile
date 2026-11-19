FROM ubuntu:24.04
RUN apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends bash ca-certificates curl wget jq openssl tar unzip procps util-linux iproute2 python3
RUN mkdir -p /opt/cores /results
RUN curl -fLsS https://github.com/SagerNet/sing-box/releases/download/v1.13.21/sing-box-1.13.21-linux-amd64.tar.gz -o /opt/sing-box.tar.gz && echo '24f9ef8e7234e13e71e74c3598a4164c5fe07b7b67ccc6e96cf68b54789f72cd  /opt/sing-box.tar.gz' | sha256sum -c - && tar -xzf /opt/sing-box.tar.gz -C /opt/cores --strip-components=1 sing-box-1.13.21-linux-amd64/sing-box
RUN curl -fLsS https://github.com/XTLS/Xray-core/releases/download/v26.11.9/Xray-linux-64.zip -o /opt/xray.zip && echo 'b651f7e1d9966ee2c1b1ee1bf8b52c72771824d3065dce96bbc8bcc19ed95f82  /opt/xray.zip' | sha256sum -c - && unzip -q /opt/xray.zip xray -d /opt/cores
RUN curl -fLsS https://github.com/mikefarah/yq/releases/download/v4.54.3/yq_linux_amd64 -o /usr/local/bin/yq && echo '129534601871538efe0ba4c5e62a34fb1d5f469bcb975c4fddeb467d82974973  /usr/local/bin/yq' | sha256sum -c -
RUN chmod +x /opt/cores/sing-box /opt/cores/xray /usr/local/bin/yq
COPY tests/core-wrapper.sh /usr/local/bin/sing-box
COPY tests/core-wrapper.sh /usr/local/bin/xray
RUN chmod +x /usr/local/bin/sing-box /usr/local/bin/xray
CMD ["sleep", "infinity"]
