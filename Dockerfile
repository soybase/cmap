FROM ubuntu:20.04 AS deps

RUN apt update && DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
  apache2 \
  libapache-htpasswd-perl \
  libapache2-mod-perl2 \
  libbit-vector-perl \
  libcache-cache-perl \
  libcgi-pm-perl \
  libcgi-session-perl \
  libclass-base-perl \
  libclone-perl \
  libconfig-general-perl \
  libdata-pageset-perl \
  libdbd-sqlite3-perl \
  libfilesys-df-perl \
  libfont-freetype-perl \
  libgd-perl \
  libgd-svg-perl \
  libio-tee-perl \
  libparams-validate-perl \
  libregexp-common-perl \
  libtemplate-perl \
  libtemplate-plugin-comma-perl \
  libtext-recordparser-perl \
  libtime-parsedate-perl \
  libxml-simple-perl \
  sqlite3 \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /srv/cmap

COPY ./lib ./lib

ENV CMAP_ROOT="/srv/cmap/"
ENV PERL5LIB="/srv/cmap/lib/"

FROM deps AS load

COPY ./bin/cmap_admin.pl ./bin/
COPY ./sql/cmap.create.sqlite ./sql/cmap.create.sqlite

ENV PATH="/srv/cmap/bin:${PATH}"

RUN mkdir ./db

COPY ./data/soytedb ./data/soytedb
COPY ./conf/soytedb.conf ./conf/
RUN cd db && ../data/soytedb/load.sh

COPY ./data/sequence_genetic3 ./data/sequence_genetic3
COPY ./conf/sequence_genetic3.conf ./conf/
RUN cd db && ../data/sequence_genetic3/load.sh

COPY ./data/sequence_genetic4 ./data/sequence_genetic4
COPY ./conf/sequence_genetic4.conf ./conf/
RUN cd db && ../data/sequence_genetic4/load.sh

FROM deps AS final

# configure httpd
RUN a2enmod headers rewrite \
  && ln -sf /proc/self/fd/1 /var/log/apache2/access.log \
  && ln -sf /proc/self/fd/2 /var/log/apache2/error.log

COPY --from=load /srv/cmap/db/ /srv/cmap/db/
COPY ./httpd-cmap.conf /etc/apache2/conf-enabled/httpd-cmap.conf
COPY ./cgi-bin ./cgi-bin
COPY ./conf ./conf
COPY ./htdocs ./htdocs
COPY ./templates ./templates

# cache_dir
RUN ln -s /tmp/cmap /srv/cmap/htdocs/tmp

ENTRYPOINT ["apachectl", "-DFOREGROUND"]
