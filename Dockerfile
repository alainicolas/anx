###############################################################################
# Dockerfile pour construire l'image netconf-explorer sous Debian Bullseye,
# avec configuration dynamique du proxy APT & Maven via la variable HTTP_PROXY.
###############################################################################
FROM debian:bullseye-slim

LABEL maintainer="Steven Barth <stbarth@cisco.com>"

###############################################################################
# 1. Déclarer un ARG et l'exposer en ENV (optionnel si on veut l'utiliser en run)
###############################################################################
ARG HTTP_PROXY

ENV http_proxy=$HTTP_PROXY
ENV https_proxy=$HTTP_PROXY
ENV no_proxy="localhost,127.0.0.1"

###############################################################################
# 2. Configurer APT pour passer par le proxy s'il est défini
###############################################################################
RUN if [ -n "$HTTP_PROXY" ]; then \
      echo "Acquire::http::Proxy \"$HTTP_PROXY\";"  >> /etc/apt/apt.conf.d/00proxy; \
      echo "Acquire::https::Proxy \"$HTTP_PROXY\";" >> /etc/apt/apt.conf.d/00proxy; \
    fi

###############################################################################
# 3. Installer Java 11, Jetty 9, Maven
###############################################################################
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    openjdk-11-jdk-headless \
    jetty9 \
    maven \
 && rm -rf /var/lib/apt/lists/*

###############################################################################
# 4. Configurer Maven pour le proxy, si HTTP_PROXY est défini.
#    (Exemple simple: on parse l'hôte et le port via 'sed')
###############################################################################
RUN mkdir -p /root/.m2 \
 && if [ -n "$HTTP_PROXY" ]; then \
      MHOST="$(echo $HTTP_PROXY | sed -E 's|https?://([^:/]+).*|\1|')"; \
      MPORT="$(echo $HTTP_PROXY | sed -E 's|https?://[^:]+:([0-9]+).*|\1|')"; \
      echo "<settings>\n" \
           "  <proxies>\n" \
           "    <proxy>\n" \
           "      <id>my-corporate-proxy</id>\n" \
           "      <active>true</active>\n" \
           "      <protocol>http</protocol>\n" \
           "      <host>${MHOST}</host>\n" \
           "      <port>${MPORT}</port>\n" \
           "      <nonProxyHosts>localhost|127.0.0.1</nonProxyHosts>\n" \
           "    </proxy>\n" \
           "  </proxies>\n" \
           "</settings>" \
      > /root/.m2/settings.xml; \
    fi

###############################################################################
# 5. Copier les sources de votre projet dans /src
###############################################################################
COPY anc /src/anc/
COPY explorer /src/explorer/
COPY grpc /src/grpc/
COPY pom.xml /src/

###############################################################################
# 6. Construire le projet avec Maven, copier le WAR explorer dans Jetty,
#    et nettoyer (suppression de Maven, etc.)
###############################################################################
ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64

RUN mkdir -p /usr/share/man/man1 \
 && cd /src \
 && mvn package javadoc:javadoc \
 && cp /src/explorer/target/*.war /var/lib/jetty9/webapps/ROOT.war \
 && mkdir /usr/share/yangcache \
 && rm -rf /var/lib/jetty9/webapps/root \
 && cd / \
 && rm -r /src /root/.m2 \
 && apt-get remove -y openjdk-11-jdk-headless maven \
 && apt-get -y autoremove \
 && apt-get clean

###############################################################################
# 7. Configuration finale: on expose le port 8080 et on lance Jetty
###############################################################################
WORKDIR /
EXPOSE 8080
CMD ["/usr/share/jetty9/bin/jetty.sh", "run"]
