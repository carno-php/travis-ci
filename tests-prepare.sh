#!/usr/bin/env bash

# global vars
export PHP_V=$TRAVIS_PHP_VERSION

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
    local ext_name=$1
    local ext_file=$2
    local php_ini=~/.phpenv/versions/$PHP_V/etc/conf.d/carno.ini
    local ext_dir=$(php -r "echo ini_get('extension_dir');")
    local ext_cache=~/.php-ext/$(basename $ext_dir)/$ext_name
    if [[ -e $ext_cache/$ext_file ]]; then
        echo extension = $ext_cache/$ext_file >> $php_ini
    else
        rm ~/.pearrc /tmp/pear 2>/dev/null || true
        mkdir -p $ext_cache
        tfold "Install EXT <$ext_name>" "printf \"$3\" | pecl install -f $ext_name"
        cp $ext_dir/$ext_file $ext_cache
    fi
}
export -f tpecl

testing () {
    tfold "Running TESTS" phpunit
}
export -f testing

coveralls () {
    tfold "Coveralls submit" php-coveralls -x coverage-clover.xml -o coveralls.io.json -v
}
export -f coveralls

# features setup

shopt -s expand_aliases

# composer aliases

export PATH="$HOME/.composer/vendor/bin:$PATH"

alias composer='composer --no-progress --no-suggest --ansi'
alias composer.g='composer global'

# composer global bins

which phpunit && phpunit --version | grep "7.3" || composer.g require phpunit/phpunit "7.3.x"
which php-coveralls || composer.g require php-coveralls/php-coveralls "2.1.x"

# extensions
if dpkg -l libhiredis-dev; then
  SW_CONF="\n\nyes\n\nyes\nyes\n\n"
else
  SW_CONF="\n\nyes\n\n\nyes\n\n"
fi

tpecl swoole-1.10.5 swoole.so ${SW_CONF}
tpecl protobuf-3.6.1 protobuf.so
tpecl apcu-5.1.12 apcu.so
tpecl ast-0.1.7 ast.so
