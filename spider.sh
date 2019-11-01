#!/bin/bash

crash_include logger.sh

data_path=data

if [ "$1" == "--help" ] || [ "$1" == "-h" ]
then
    echo "usage: $0 [ip]"
    echo "description: collects urls and stores them"
    echo "             either starting from provided addres or randomly generated one"
    exit 0
fi

function rand_byte() {
    printf "$((0 + RANDOM % 255))"
}

function get_random_ip() {
    echo "$(rand_byte).$(rand_byte).$(rand_byte).$(rand_byte)"
}

function get_next_ip() {
    if [ ! -f $data_path/ips.txt ]
    then
        exit 1
    fi
    tail -n1 $data_path/ips.txt
    head -n -1 $data_path/ips.txt > $data_path/tmp/ips.txt
    cat $data_path/tmp/ips.txt | sort | uniq > $data_path/ips.txt
}

function parse_line() {
    # TODO: support http not only https
    # TODO: prefer quoted url to get the whole url not only base
    local line=$1
    log "line: $line"
    if [[ "$line" =~ (\"https://[a-zA-Z0-9\./%-]{3,256}\")(.*)+ ]]
    then
        m="${BASH_REMATCH[1]}"
        m=${m:1:-1} # chop off quotes
        dbg "match: $m"
        echo "$m" >> $data_path/ips.txt
        if [ "${BASH_REMATCH[2]}" != "" ]
        then
            parse_line "${BASH_REMATCH[2]}"
        fi
    fi
}

function parse_file() {
    local file=$1
    while read line; do
        parse_line "$line"
    done < <(grep "https://" $file)
}

function scrape_ip() {
    local addr=$1
    log "scraping address '$addr'"
    current_file=$data_path/tmp/current_$(date +%s).txt
    wget -O $current_file --tries=1 --timeout=10 $addr
    parse_file $current_file
    rm $current_file
    # TODO: use a bash hash for known ips and increase number
    echo "$ip" >> $data_path/known_ips.txt
    ip=$(get_next_ip)
    if [ "$ip" == "" ]
    then
        err "ip list is empty"
        cat $data_path/ips.txt
        exit 1
    fi
    scrape_ip "$ip"
}

mkdir -p $data_path/tmp

if [ $# -gt 0 ]
then
    scrape_ip "$1"
else
    scrape_ip "$(get_random_ip)"
fi

