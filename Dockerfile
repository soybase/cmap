FROM ubuntu:20.04

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

# configure httpd
RUN a2enmod headers \
  && ln -sf /proc/self/fd/1 /var/log/apache2/access.log \
  && ln -sf /proc/self/fd/2 /var/log/apache2/error.log \
  && ln -s /srv/cmap/httpd-cmap.conf /etc/apache2/conf-enabled/httpd-cmap.conf

COPY . /srv/cmap/

ENV CMAP_ROOT="/srv/cmap/"
ENV PATH="/srv/cmap/bin:${PATH}"
ENV PERL5LIB="/srv/cmap/lib/"

ENTRYPOINT ["apachectl", "-DFOREGROUND"]
