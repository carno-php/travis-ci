#!/usr/bin/env bash

# global vars
export PHP_V=$TRAVIS_PHP_VERSION
export PHP_C=~/.phpenv/versions/${PHP_V}/etc/conf.d/carno.ini

# functions

nanoseconds () {
    local cmd="date"
    local format="+%s%N"
    local os=$(uname)
    if hash gdate > /dev/null 2>&1; then
    cmd="gdate"
    elif [[ "$os" = Darwin ]]; then
    format="+%s000000000"
    fi
    $cmd -u $format
}
export -f nanoseconds

tfold () {
    local title="🤔 $1"
    shift
    local fold=$(echo $title | sed -r 's/[^-_A-Za-z0-9]+/./g')
    local id=$(printf %08x $(( RANDOM * RANDOM )))
    local start=$(nanoseconds)
    echo -e "travis_fold:start:$fold"
    echo -e "travis_time:start:$id"
    echo -e "\\e[1;34m$title\\e[0m"
    bash -xc "$*" 2>&1
    local ok=$?
    local end=$(nanoseconds)
    echo -e "\\ntravis_time:end:$id:start=$start,finish=$end,duration=$(($end-$start))"
    (exit $ok) &&
        echo -e "\\e[32mOK\\e[0m $title\\n\\ntravis_fold:end:$fold" ||
        echo -e "\\e[41mKO\\e[0m $title\\n"
    (exit $ok)
}
export -f tfold

tpecl () {
    if [[ `cache_ext $2` == "missing" ]]; then
        tfold "Install EXT <$1>" "printf \"$3\" | pecl install -f $1"
        rm ~/.pearrc /tmp/pear 2>/dev/null || true
        cache_ext $2
    fi
}
export -f tpecl

cache_ext() {
    local ext_dir=$(php -r "echo ini_get('extension_dir');")
    local ext_file=$1
    local ext_cache=~/.php-ext/$(basename ${ext_dir})/${ext_file}
    local ext_origin=${ext_dir}/${ext_file}

    if [[ -e ${ext_cache} ]]; then
        php --ri ${ext_file%.*} || echo extension = "$ext_cache" >> ${PHP_C}
    else
        mkdir -p $(dirname ${ext_cache})
        if [[ -e ${ext_origin} ]]; then
            cp ${ext_origin} ${ext_cache} && \
            php --ri ${ext_file%.*} || echo extension = "$ext_cache" >> ${PHP_C}
        else
            echo "missing"
        fi
    fi
}
export -f cache_ext

swoole_ext() {
    local ver=$1
    local cfg=${@:2}
    local ext="swoole.so"
    local tmp="/tmp/swoole-src-${ver}"

    if [[ `cache_ext ${ext}` == "missing" ]]; then
        wget -qO- https://github.com/swoole/swoole-src/archive/v${ver}.tar.gz | tar xz -C /tmp
        cd ${tmp}
        if [[ -e "swoole_coroutine.cc" ]]; then
            sed -i '/Xdebug/d' swoole_coroutine.cc
        fi
        phpize && ./configure ${cfg} && \
        make -j $(nproc) && make install
        cache_ext ${ext}
        cd -
    fi
}
export -f swoole_ext

swoole_async() {
    local ver=$1
    local ext="swoole_async.so"
    local tmp="/tmp/ext-async-${ver}"

    if [[ `cache_ext ${ext}` == "missing" ]]; then
        wget -qO- https://github.com/swoole/ext-async/archive/v${ver}.tar.gz | tar xz -C /tmp
        cd ${tmp}
        phpize && ./configure && \
        make -j $(nproc) && make install
        cache_ext ${ext}
        cd -
    fi
}
export -f swoole_async

testing () {
    tfold "Running TESTS" phpunit
}
export -f testing

coveralls () {
    tfold "Coveralls submit" php-coveralls -x 'coverage*.xml' -o coveralls.io.json -v
}
export -f coveralls

codecov () {
    tfold "Codecov submit" bash <(curl -s https://codecov.io/bash)
}
export -f codecov

# features setup

shopt -s expand_aliases

# composer aliases

export PATH="$HOME/.composer/vendor/bin:$PATH"

composer_g() {
    composer global $@
}
export -f composer_g

# composer speedup
tfold "Installing <hirak.prestissimo>" "composer_g show hirak/prestissimo || composer_g require hirak/prestissimo"

# composer global bins
which phpunit && phpunit --version | grep "7.3" || tfold "Installing <phpunit>" composer_g require phpunit/phpunit "7.3.x"
which php-coveralls || tfold "Installing <coveralls>" composer_g require php-coveralls/php-coveralls "2.1.x"

# ext versions
EV_swoole1="1.10.5"
EV_swoole4="4.4.2"
EV_sw_async="4.3.3"
EV_protobuf="3.9.0"
EV_apcu="5.1.17"
EV_ast="1.0.3"

# swoole
SW_VER=$([[ "$PHP_V" == "7.3" ]] && echo "$EV_swoole4" || echo "$EV_swoole1")
SW_FLAGS="--enable-openssl --enable-mysqlnd"

if [[ "$PHP_V" != "7.3" ]]; then
    if dpkg -l libhiredis-dev; then
        SW_FLAGS="$SW_FLAGS --enable-async-redis"
    fi
fi

tfold "Install swoole core <$SW_VER>" "swoole_ext $SW_VER $SW_FLAGS"

if [[ "$PHP_V" == "7.3" ]]; then
    tfold "Install swoole async <$EV_sw_async>" "swoole_async $EV_sw_async"
fi

# extensions
tpecl protobuf-${EV_protobuf} protobuf.so
tpecl apcu-${EV_apcu} apcu.so
tpecl ast-${EV_ast} ast.so
