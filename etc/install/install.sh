#!/bin/bash

# Script to set up a Django project on Vagrant.

# Installation settings

PROJECT_NAME=$1

LOCAL_LOCALE=en_AU.UTF-8
COUNTRY=au

DB_NAME=${PROJECT_NAME}
VIRTUALENV_NAME=${PROJECT_NAME}

PROJECT_DIR=/home/vagrant/${PROJECT_NAME}
VIRTUALENV_DIR=/home/vagrant/.virtualenvs/${PROJECT_NAME}

PGSQL_VERSION=9.1
POSTGIS_VERSION=2.0.4
GEOS_VERSION=3.3.9
NODE_VERSION=0.10.25

# Need to fix locale so that Postgres creates databases in UTF-8
cp -p ${PROJECT_DIR}/etc/install/etc-bash.bashrc /etc/bash.bashrc
locale-gen ${LOCAL_LOCALE}
dpkg-reconfigure locales

export LANGUAGE=${LOCAL_LOCALE}
export LANG=${LOCAL_LOCALE}
export LC_ALL=${LOCAL_LOCALE}

# Change to local mirror
# from https://github.com/Tokutek/vagrant-tokutek-builder/commit/b88e5543e6eb6bc8291d0599d017c8a918fca84d
if ! grep -q ${COUNTRY}'\.archive\.ubuntu\.com' /etc/apt/sources.list; then
    sed -i'' -e 's/[a-z]*\.archive\.ubuntu\.com/'${COUNTRY}'.archive.ubuntu.com/g' /etc/apt/sources.list
fi


# Install essential packages from Apt
apt-get update -y
# Python dev packages
apt-get install -y build-essential python python-dev
# python-setuptools being installed manually
wget https://bitbucket.org/pypa/setuptools/raw/bootstrap/ez_setup.py -O - | python
# Dependencies for image processing with Pillow (drop-in replacement for PIL)
# supporting: jpeg, tiff, png, freetype, littlecms
# (pip install pillow to get pillow itself, it is not in requirements.txt)
apt-get install -y libjpeg62-dev libtiff4-dev zlib1g-dev libfreetype6-dev liblcms2-dev
#apt-get install -y imagemagick xsltproc libxml2-utils dblatex libcunit1 libcunit1-dev
# Git (we'd rather avoid people keeping credentials for git commits in the repo, but sometimes we need it for pip requirements that aren't in PyPI)
apt-get install -y git

# Postgresql
if ! command -v psql; then
    # Install postgresql and postgis with dependencies
    apt-get install -y libgdal1-1.7.0 libgdal1-dev python-gdal binutils gdal-bin
    apt-get install -y build-essential postgresql-${PGSQL_VERSION} postgresql-server-dev-${PGSQL_VERSION} libxml2-dev libproj-dev libjson0-dev xsltproc docbook-xsl docbook-mathml libpq-dev libgdal1-dev

    wget http://download.osgeo.org/geos/geos-${GEOS_VERSION}.tar.bz2
    tar xfj geos-${GEOS_VERSION}.tar.bz2
    cd geos-${GEOS_VERSION}
    ./configure && make && make install
    cd ..
    rm -rf geos-${GEOS_VERSION}/ geos-${GEOS_VERSION}.tar.bz2

    wget http://download.osgeo.org/postgis/source/postgis-${POSTGIS_VERSION}.tar.gz
    tar xfz postgis-${POSTGIS_VERSION}.tar.gz
    cd postgis-${POSTGIS_VERSION}
    ./configure && make && make install
    ldconfig
    make comments-install
    cd ..
    rm -rf postgis-${POSTGIS_VERSION}/ postgis-${POSTGIS_VERSION}.tar.gz

    ln -sf /usr/share/postgresql-common/pg_wrapper /usr/local/bin/shp2pgsql
    ln -sf /usr/share/postgresql-common/pg_wrapper /usr/local/bin/pgsql2shp
    ln -sf /usr/share/postgresql-common/pg_wrapper /usr/local/bin/raster2pgsql

    cp ${PROJECT_DIR}/etc/install/pg_hba.conf /etc/postgresql/${PGSQL_VERSION}/main/
    /etc/init.d/postgresql reload
fi

# virtualenv global setup
if ! command -v pip; then
    easy_install -U pip
fi
if [[ ! -f /usr/local/bin/virtualenv ]]; then
    pip install virtualenv virtualenvwrapper stevedore virtualenv-clone
fi

# bash environment global setup
cp -p ${PROJECT_DIR}/etc/install/bashrc /home/vagrant/.bashrc
su - vagrant -c "mkdir -p /home/vagrant/.pip_download_cache"

# Node.js, CoffeeScript and LESS
if ! command -v npm; then
    wget http://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}.tar.gz
    tar xzf node-v${NODE_VERSION}.tar.gz
    cd node-v${NODE_VERSION}/
    ./configure && make && make install
    cd ..
    rm -rf node-v${NODE_VERSION}/ node-v${NODE_VERSION}.tar.gz
fi
if ! command -v coffee; then
    npm install -g coffee-script
fi
if ! command -v lessc; then
    npm install -g less
fi

# ---

# postgresql setup for project
createdb -Upostgres ${DB_NAME}
psql -Upostgres -d ${DB_NAME} -c "CREATE EXTENSION postgis;"
psql -Upostgres -d ${DB_NAME} -c "CREATE EXTENSION postgis_topology;"

# virtualenv setup for project
su - vagrant -c "/usr/local/bin/virtualenv ${VIRTUALENV_DIR} && \
    echo ${PROJECT_DIR} > ${VIRTUALENV_DIR}/.project && \
    PIP_DOWNLOAD_CACHE=/home/vagrant/.pip_download_cache ${VIRTUALENV_DIR}/bin/pip install -r ${PROJECT_DIR}/requirements.txt --pre"

echo "workon ${VIRTUALENV_NAME}" >> /home/vagrant/.bashrc

# Set execute permissions on manage.py, as they get lost if we build from a zip file
chmod a+x ${PROJECT_DIR}/manage.py

# Django project setup
su - vagrant -c "source ${VIRTUALENV_DIR}/bin/activate && cd ${PROJECT_DIR} && ./manage.py syncdb --noinput && ./manage.py migrate"
