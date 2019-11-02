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
    # printf might be more consistent
    # but i have no clue how to please shellcheck with printf
    echo -n "$((0 + RANDOM % 255))"
}

function get_random_ip() {
    echo "$(rand_byte).$(rand_byte).$(rand_byte).$(rand_byte)"
}

function clean_and_sort_data() {
    # sort and unique ips
    mv $data_path/ips.txt $data_path/tmp/ips.txt
    sort $data_path/tmp/ips.txt | uniq > $data_path/ips.txt
    # sort and unique known ips
    mv $data_path/known_ips.txt $data_path/tmp/known_ips.txt
    sort $data_path/tmp/known_ips.txt | uniq > $data_path/known_ips.txt
    # remove known ips from ips
    comm -23 $data_path/ips.txt $data_path/known_ips.txt > $data_path/tmp/ips.txt
    mv $data_path/tmp/ips.txt $data_path/ips.txt
}

function get_next_ip() {
    if [ ! -f $data_path/ips.txt ]
    then
        exit 1
    fi
    clean_and_sort_data
    tail -n1 $data_path/ips.txt
    head -n -1 $data_path/ips.txt > $data_path/tmp/ips.txt
    sort $data_path/tmp/ips.txt | uniq > $data_path/ips.txt
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
        if grep -q "$addr" "$data_path/known_ips.txt"
        then
            dbg "ignoring known address '$addr'"
        else
            echo "$m" >> $data_path/ips.txt
        fi
        if [ "${BASH_REMATCH[2]}" != "" ]
        then
            parse_line "${BASH_REMATCH[2]}"
        fi
    fi
}

function parse_file() {
    local file=$1
    while read -r line; do
        parse_line "$line"
    done < <(grep "https://" "$file")
}

function scrape_ip() {
    local addr=$1
    log "scraping address '$addr'"
    if grep -q "$addr" "$data_path/known_ips.txt"
    then
        log "skipping known address '$addr'"
    else
        current_file=$data_path/tmp/current_$(date +%s).txt
        wget -O "$current_file" --tries=1 --timeout=10 "$addr"
        parse_file "$current_file"
        rm "$current_file"
    fi
    # TODO: use a bash hash for known ips and increase number
    echo "$ip" >> $data_path/known_ips.txt
    mv $data_path/known_ips.txt $data_path/tmp/known_ips.txt
    sort $data_path/tmp/known_ips.txt | uniq > $data_path/known_ips.txt
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
    ip=$(get_next_ip)
    if [ "$ip" == "" ]
    then
        scrape_ip "$(get_random_ip)"
    else
        scrape_ip "$ip"
    fi
fi

