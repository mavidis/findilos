#!/bin/bash
#
# findilos - Search a local network segment for iLOs
#            The iLO is the Integrated Lights-Out management processor
#            used on HP ProLiant and BladeSystem servers
#
scriptversion="2.0"
#
# Author: iggy@nachotech.com - the original findilos (1.0)
#
# Website: http://blog.nachotech.com
#
# Contributors:
#   osakanataro (https://github.com/osakanataro/findilos)
#     - iLO 3, 4 and 5 support, licence key output (1.1, 1.2)
#   mavidis (https://github.com/mavidis/findilos)
#     - fixes, HTTPS, iLO 6, parallel queries, csv/json output (1.3, 2.0)
#   See CHANGELOG.md for details.
#
# Requires: bash 4.3+, tr sed awk curl nmap mktemp
#
# Originally tested with: Nmap 4.20, curl 7.17.1, RHEL4
#
# Note: Discovery of an iLO is dependent upon the Virtual Media port
#       being set to the default of 17988.  If this has been changed
#       by the iLO administrator, then this script will NOT find it.
#
#       Also, if the iLO XML Reply Data Return has been Disabled by
#       the iLO administrator, this script will not be able to
#       gather any information about the server.  It will still be
#       discovered, but all you will see is its IP address.
#

# GLOBAL VARIABLES

scriptname="findilos"
tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/findilos.XXXXXX") || exit 255
trap 'rm -rf "$tmpdir"' EXIT
iloips="$tmpdir/ilos"
ilohwvers="$tmpdir/ilohwvers"

# defaults, see usage
format="table"
declare -i maxjobs=16
ports="17988"

# FUNCTIONS

function parseiloxml {
  # look for the opening tag itself, so that e.g. PN does not match SPN
  if ! grep -qF "<$1>" "$iloxml" 2>/dev/null
  then
    # tag not found in xml output
    parsedstring="N/A"
  else
    # tag was found - now we parse it from the output
    parsedstring=$(tr -d -c '[:print:]' < "$iloxml" | sed -e "s/^.*<$1>//" -e "s/<\/$1>.*//" \
      -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    if [ -z "$parsedstring" ]; then
      parsedstring="N/A"
    fi
  fi
}

function fetch_iloxml {
  # try HTTP first, then HTTPS (iLO certificates are usually self-signed)
  if ! curl --proxy "" --fail --silent --max-time 3 "http://$1/xmldata?item=$2" > "$iloxml" 2>/dev/null \
     || [ ! -s "$iloxml" ]; then
    curl --proxy "" --fail --silent --insecure --max-time 3 "https://$1/xmldata?item=$2" > "$iloxml" 2>/dev/null
  fi
}

function is_installed {
  if ! command -v "$1" > /dev/null 2>&1
  then
    printf "\nERROR: %s not installed.\n\n" "$1"
    exit 255
  fi
}

# MAIN

# check for tools that we depend upon

is_installed tr
is_installed sed
is_installed curl
is_installed nmap

function usage {
  printf "%s %s ( http://blog.nachotech.com/ )\n" "$scriptname" "$scriptversion"
  printf "Usage: %s [-f table|csv|json] [-j jobs] [-p ports] {target network specification}\n" "$scriptname"
  printf "OPTIONS:\n"
  printf "  -f FORMAT  output format: table (default), csv or json\n"
  printf "  -j JOBS    number of iLOs queried in parallel (default 16)\n"
  printf "  -p PORTS   ports to scan, comma separated (default 17988, the iLO virtual media port)\n"
  printf "             with other ports, only hosts that answer as an iLO are listed\n"
  printf "TARGET NETWORK SPECIFICATION:\n"
  printf "  Can pass hostnames, IP addresses, networks, etc.\n"
  printf "  Ex: server1.company.com, company.com/24, 192.168.0.1/16, 10.0.0-255.1-254\n"
  printf "EXAMPLE:\n"
  printf "  %s 16.32.64.0/22\n" "$scriptname"
  printf "  %s -f csv -p 17988,443 10.0.0.0/24 > ilos.csv\n" "$scriptname"
  exit 255
}

#
# query one iLO and print its fields as one tab separated line:
# ip, hw, fw, serial, model, edition, key
# runs in its own subshell, so it gets its own xml file
#

function query_ilo {
  local iloip=$1
  iloxml="$tmpdir/xml.$2"

  #
  # attempt to read the xmldata from iLO, no password required
  #
  fetch_iloxml "$iloip" All

  if [ "$ports" != "17988" ] && ! grep -qF "<RIMP>" "$iloxml" 2>/dev/null; then
    # found through another port and does not answer like an iLO
    return
  fi

  parseiloxml SPN;  servermodel=$parsedstring
  parseiloxml SBSN; sernum=$parsedstring
  parseiloxml PN;   ilotype=$parsedstring
  parseiloxml FWRI; ilofirmware=$parsedstring
  parseiloxml HWRI; ilohardware=$parsedstring

  # the product name usually names the generation, e.g. "Integrated Lights-Out 4 (iLO 4)"
  ilohwver=$(printf "%s" "$ilotype" | sed -n 's/.*(iLO \([0-9]\{1,\}\)).*/iLO-\1/p')
  if [ -z "$ilohwver" ]; then
    # otherwise look the hardware revision up, matching it exactly
    hwkey=$(printf "%s" "$ilohardware" | tr -s ' ')
    ilohwver=$(awk -v key="$hwkey" '{gen=$1; $1=""; sub(/^ /, ""); if ($0 == key) {print gen; exit}}' "$ilohwvers")
  fi
  if [ -z "$ilohwver" ]; then
    ilohwver="N/A"
  fi

  # licence information
  fetch_iloxml "$iloip" CpqKey
  parseiloxml LNAME; ilomodel=$parsedstring
  parseiloxml KEY; ilokey=$parsedstring

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$iloip" "$ilohwver" "$ilofirmware" "$sernum" "$servermodel" "$ilomodel" "$ilokey"
}

function csv_field {
  # quote every field, doubling any quotes inside it
  printf '"%s"' "${1//\"/\"\"}"
}

function json_string {
  local str=${1//\\/\\\\}
  printf '"%s"' "${str//\"/\\\"}"
}

# parse options

while getopts ":f:j:p:h" opt; do
  case $opt in
    f) format=$OPTARG ;;
    j) maxjobs=$OPTARG ;;
    p) ports=$OPTARG ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))

# check syntax - should have 1 and only 1 target left on cmdline

if [ $# -ne 1 ]; then
  usage
fi

case $format in
  table|csv|json) ;;
  *) printf "ERROR: unknown format %s\n" "$format" >&2; exit 255 ;;
esac

if [ "$maxjobs" -lt 1 ]; then
  printf "ERROR: -j needs a positive number\n" >&2
  exit 255
fi

if ! printf "%s" "$ports" | grep -qE '^[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$'; then
  printf "ERROR: invalid port list %s\n" "$ports" >&2
  exit 255
fi

iprange=$1

# prepare lookup file for iLO hardware versions

cat > "$ilohwvers" << EOF
iLO-1 ASIC: 2
iLO-2 ASIC: 7
iLO-3 ASIC: 8
iLO-3 ASIC: 9
iLO-4 ASIC: 12
iLO-4 ASIC: 16
iLO-5 ASIC: 19
iLO-5 ASIC: 21
iLO-6 ASIC: 27
iLO-6 ASIC: 28
i-iLO T0
EOF

#
# scan a range of IP addresses looking for the open port(s),
# by default tcp port 17988 (the iLO virtual media port)
# progress messages go to stderr so csv/json output stays clean
#

# a SYN scan needs root; fall back to a TCP connect scan otherwise

if [ "$(id -u)" -eq 0 ]; then
  scantype="-sS"
else
  scantype="-sT"
  printf "Not running as root, using a slower TCP connect scan.\n" >&2
fi

printf "Scanning..." >&2

nmap -n -Pn "$scantype" -p "$ports" -oG - "$iprange" | grep -F /open/ | awk '{print $2}' > "$iloips"

printf "\n\n" >&2

#
# query the iLOs in parallel, each into its own result file,
# then print the results in scan order
#

declare -i n=0
while read -r iloip; do
  n=$n+1
  if [ "$(jobs -rp | wc -l)" -ge "$maxjobs" ]; then
    wait -n
  fi
  query_ilo "$iloip" "$n" > "$tmpdir/res.$n" &
done < "$iloips"
wait

declare -i ilosfound=0

case $format in
  table)
    echo "--------------- ------ -------- ------------ ------------------------- -------------------- -----------------------------"
    echo "iLO IP Address  iLO HW iLO FW   Server S/N   Server Model              iLO Edition          iLO Licence Key"
    echo "--------------- ------ -------- ------------ ------------------------- -------------------- -----------------------------"
    ;;
  csv)
    echo "ip,ilo_hw,ilo_fw,serial,model,ilo_edition,ilo_key"
    ;;
  json)
    printf "["
    ;;
esac

for ((i = 1; i <= n; i++)); do
  while IFS=$'\t' read -r iloip ilohwver ilofirmware sernum servermodel ilomodel ilokey; do
    ilosfound=$ilosfound+1
    case $format in
      table)
        printf "%-15s %-6s %-8s %-12s %-25s %-20s %-30s\n" "$iloip" "$ilohwver" "$ilofirmware" "$sernum" "$servermodel" "$ilomodel" "$ilokey"
        ;;
      csv)
        csv_field "$iloip"; printf ","; csv_field "$ilohwver"; printf ","; csv_field "$ilofirmware"; printf ","
        csv_field "$sernum"; printf ","; csv_field "$servermodel"; printf ","; csv_field "$ilomodel"; printf ","
        csv_field "$ilokey"; printf "\n"
        ;;
      json)
        if [ "$ilosfound" -gt 1 ]; then printf ","; fi
        printf '\n  {"ip": %s, "ilo_hw": %s, "ilo_fw": %s, "serial": %s, "model": %s, "ilo_edition": %s, "ilo_key": %s}' \
          "$(json_string "$iloip")" "$(json_string "$ilohwver")" "$(json_string "$ilofirmware")" "$(json_string "$sernum")" \
          "$(json_string "$servermodel")" "$(json_string "$ilomodel")" "$(json_string "$ilokey")"
        ;;
    esac
  done < "$tmpdir/res.$i"
done

if [ "$format" = "json" ]; then
  if [ "$ilosfound" -gt 0 ]; then printf "\n"; fi
  printf "]\n"
fi

if [ "$format" = "table" ]; then
  printf "\n%d iLOs found on network target %s.\n\n" "$ilosfound" "$iprange"
else
  printf "%d iLOs found on network target %s.\n" "$ilosfound" "$iprange" >&2
fi

exit 0
