#!/bin/bash
#
# findilos - Search a local network segment for iLOs
#            The iLO is the Integrated Lights-Out management processor
#            used on HP ProLiant and BladeSystem servers
#
scriptversion="1.3"
#
# Author: iggy@nachotech.com
#
# Website: http://blog.nachotech.com
#
# Requires: tr sed curl nmap mktemp
#
# Tested with: Nmap 4.20, curl 7.17.1, RHEL4
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
iloxml="$tmpdir/iloxml"
ilohwvers="$tmpdir/ilohwvers"

declare -i ilosfound=0

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

# check syntax - should have 1 and only 1 parameter on cmdline

if [ $# -ne 1 ]; then
  printf "%s %s ( http://blog.nachotech.com/ )\n" "$scriptname" "$scriptversion"
  printf "Usage: %s {target network specification}\n" "$scriptname"
  printf "TARGET NETWORK SPECIFICATION:\n"
  printf "  Can pass hostnames, IP addresses, networks, etc.\n"
  printf "  Ex: server1.company.com, company.com/24, 192.168.0.1/16, 10.0.0-255.1-254\n"
  printf "EXAMPLE:\n"
  printf "  %s 16.32.64.0/22\n" "$scriptname"
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
# scan a range of IP addresses looking for an
# open tcp port 17988 (the iLO virtual media port)
#

# a SYN scan needs root; fall back to a TCP connect scan otherwise

if [ "$(id -u)" -eq 0 ]; then
  scantype="-sS"
else
  scantype="-sT"
  printf "Not running as root, using a slower TCP connect scan.\n"
fi

printf "Scanning..."

nmap -n -Pn "$scantype" -p 17988 -oG - "$iprange" | grep -F /open/ | awk '{print $2}' > "$iloips"

printf "\n\n"

#
# open and read the list of IP addresses one at a time
#

exec 3< "$iloips"

echo "--------------- ------ -------- ------------ ------------------------- -------------------- -----------------------------"
echo "iLO IP Address  iLO HW iLO FW   Server S/N   Server Model              iLO Edition          iLO Licence Key"
echo "--------------- ------ -------- ------------ ------------------------- -------------------- -----------------------------"

while read -r iloip <&3 ; do
  ilosfound=$ilosfound+1
  #
  # attempt to read the xmldata from iLO, no password required
  #
  fetch_iloxml "$iloip" All

  #
  # parse out the Server model (server product name)
  # from the XML output
  #

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

  if [ "$sernum" == "" ]; then
    sernum="N/A"
  fi

  # add start
  fetch_iloxml "$iloip" CpqKey
  parseiloxml LNAME; ilomodel=$parsedstring
  parseiloxml KEY; ilokey=$parsedstring
  # add end

  printf "%-15s %-6s %-8s %-12s %-25s %-20s %-30s\n" "$iloip" "$ilohwver" "$ilofirmware" "$sernum" "$servermodel" "$ilomodel" "$ilokey"

done

printf "\n%d iLOs found on network target %s.\n\n" "$ilosfound" "$iprange"

exit 0
