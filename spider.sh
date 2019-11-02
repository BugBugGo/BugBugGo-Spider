#!/bin/bash

crash_include logger.sh

data_path=data
delete_downloads=0

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
        if [ -f "$data_path/known_ips.txt" ] && grep -q "$addr" "$data_path/known_ips.txt"
        then
            dbg "ignoring known address '$addr'"
        else
            if [ ! -d "$data_path" ]
            then
                err "data path does not exist '$data_path'"
                exit 1
            fi
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

function download_site() {
    local addr=$1
    local addr_path=""
    local addr_file=""
    local dir=$(pwd)
    if [ "$#" != "1" ]
    then
        err "download_site() failed:"
        err "invalid number of arguemnts"
        exit 1
    fi
    addr="${addr#https://}"
    addr="${addr#http://}"
    addr="${addr%%+(/)}"    # strip trailing slash
    addr_file="${addr##*/}" # get last word after slash
    if [[ ! "$addr" =~ / ]]
    then
        wrn "address does not include a slash"
        addr_path="$addr"
    else
        addr_path="${addr%/*}"
    fi
    dbg "addr='$addr' path='$addr_path' file='$addr_file' dir='$dir'"
    mkdir -p "$data_path/$addr_path" || exit 1
    cd "$data_path/$addr_path"
    wget_out="$(wget --tries=1 --timeout=10 "$addr" 2>&1)"
    wget_code="$?"
    if [ "$wget_code" != "0" ]
    then
        # only code 1, 2 and 3 are problematic
        # all the other error codes can be caused by invalid urls
        if [ "$wget_code" -gt 3 ]
        then
            wrn "wget exited with the error code $wget_code"
            return
        else
            err "download_site() failed:"
            err "wget failed with error code $wget_code"
            err "wget output:"
            echo "$wget_out"
            exit 1
        fi
    fi
    if [ "$wget_out" == "" ]
    then
        err "download_site() failed:"
        err "wget had no output"
        exit 1
    fi
    filename="$(echo "$wget_out" | tail -n1)"
    local pattern='^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2}[[:space:]]\(.*\)[[:space:]]-[[:space:]](.*)[[:space:]]saved[[:space:]]\[.*\]$'
    if [[ $filename =~ $pattern ]]
    then
        filename="${BASH_REMATCH[1]}"
    else
        err "download_site() failed:"
        err "pattern did not match filename='$filename'"
        exit 1
    fi
    if [ "$filename" == "" ] || [ "${#filename}" -lt 3 ]
    then
        err "download_site() failed:"
        err "invalid filname='$filename' wget output:"
        echo "$wget_out"
        exit 1
    fi
    filename="${filename:1:-1}"
    dbg "downloaded file='$filename'"
    parse_file "$filename"
    if [ "$delete_downloads" == "1" ]
    then
        wrn "deleting file '$filename' ..."
        rm "$filename"
    fi
    cd "$dir"
}

function scrape_ip() {
    local addr=$1
    log "scraping address '$addr'"
    if [ -f "$data_path/known_ips.txt" ] && grep -q "$addr" "$data_path/known_ips.txt"
    then
        log "skipping known address '$addr'"
    else
        download_site "$addr"
    fi
    # TODO: use a bash hash for known ips and increase number
    echo "$ip" >> $data_path/known_ips.txt
    mv $data_path/known_ips.txt $data_path/tmp/known_ips.txt
    sort $data_path/tmp/known_ips.txt | uniq > $data_path/known_ips.txt
    ip=$(get_next_ip)
    if [ "$ip" == "" ]
    then
        err "ip list is empty"
        exit 1
    fi
    scrape_ip "$ip"
}

# create data path and make it absolute
mkdir -p $data_path/tmp
if [[ $data_path =~ ^/.* ]]
then
    suc "using absolute data path '$data_path'"
else
    wrn "data path is relative '$data_path'"
    data_path="$(pwd)/$data_path"
    log "using absolute data path '$data_path'"
fi

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

