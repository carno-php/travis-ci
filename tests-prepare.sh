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

    if [[ -e "$ext_cache/$ext_file" ]]; then
        echo extension = "$ext_cache/$ext_file" >> ${PHP_C}
    else
        mkdir -p ${ext_cache}
        if [[ -e ${ext_origin} ]]; then
            cp ${ext_origin} ${ext_cache}
        else
            echo "missing"
        fi
    fi
}
export -f cache_ext

swoole_ext() {
    local ver=$1
    local cfg=$2
    local ext="swoole.so"
    local tmp="/tmp/swoole-src-${ver}"

    if [[ `cache_ext ${ext}` == "missing" ]]; then
        wget -qO- https://github.com/swoole/swoole-src/archive/v${ver}.tar.gz | tar xz -C /tmp
        cd ${tmp}
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

alias composer='composer --no-progress --no-suggest --ansi'
alias composer.g='composer global'

# composer speedup
composer.g show hirak/prestissimo || composer.g require hirak/prestissimo

# composer global bins
which phpunit && phpunit --version | grep "7.3" || composer.g require phpunit/phpunit "7.3.x"
which php-coveralls || composer.g require php-coveralls/php-coveralls "2.1.x"

# swoole versions
if [[ "$PHP_V" == "7.3" ]]; then
    swoole_ext 4.3.3
    swoole_async 4.3.3
else
    swoole_ext 1.10.5
fi

tpecl protobuf-3.8.0 protobuf.so
tpecl apcu-5.1.17 apcu.so
tpecl ast-1.0.1 ast.so
