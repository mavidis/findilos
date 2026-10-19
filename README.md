# findilos

Search a local network segment for HPE iLOs and list what each one reports
about itself: iLO generation and firmware, server serial number and model,
and iLO licence edition and key.

The iLO (Integrated Lights-Out) is the management processor used on HP and
HPE ProLiant and BladeSystem servers. findilos finds iLOs by their virtual
media port (17988) and reads the unauthenticated `xmldata` endpoint, so no
iLO password is needed.

## Requirements

`bash` 4.3 or newer, `nmap`, `curl`, `sed`, `tr`, `awk` and `mktemp`.

Run it as root for a fast SYN scan. Without root it falls back to a slower
TCP connect scan.

## Usage

```
findilos [-f table|csv|json] [-j jobs] [-p ports] [-c] TARGET
```

| Option | Meaning | Default |
| --- | --- | --- |
| `-f` | Output format: `table`, `csv` or `json` | `table` |
| `-j` | How many iLOs are queried at the same time | `16` |
| `-p` | Ports to scan, comma separated or ranges | `17988` |
| `-c` | Add a "Latest FW" column: the newer firmware version, or `up to date` | off |

`TARGET` is anything nmap accepts: hostnames, IP addresses, networks or
ranges such as `server1.company.com`, `192.168.0.0/24` or
`10.0.0-255.1-254`.

### Examples

```
sudo ./findilos.sh 192.168.0.0/24
sudo ./findilos.sh -f csv 10.0.0.0/22 > ilos.csv
sudo ./findilos.sh -f json -p 17988,443 10.0.0.0/24
sudo ./findilos.sh -c 10.0.0.0/24
```

```
--------------- ------ -------- ------------ ------------------------- -------------------- -----------------------------
iLO IP Address  iLO HW iLO FW   Server S/N   Server Model              iLO Edition          iLO Licence Key
--------------- ------ -------- ------------ ------------------------- -------------------- -----------------------------
192.168.0.21    iLO-5  2.72     CZ12345678   ProLiant DL380 Gen10      iLO Advanced         XXXXX-XXXXX-XXXXX-XXXXX-XXXXX
```

CSV and JSON go to standard output and progress messages go to standard
error, so the output can be redirected to a file directly.

## Notes

- If the virtual media port was changed from 17988, scan the new port or
  443 with `-p`. Hosts found on other ports are only listed when they answer
  like an iLO.
- If "XML Reply Data Return" is disabled on an iLO, it is still found but
  only its IP address is shown.
- The `xmldata` endpoint is tried over HTTP first, then HTTPS. iLO
  certificates are usually self-signed, so the HTTPS request does not
  verify them.
- `-c` compares against a list of the latest firmware per iLO generation
  that is built into the script, taken from
  https://pingtool.org/latest-hp-ilo-firmwares/ (2026-08-02). Newer
  firmware released after that date is not known to the script. The list
  is `fwlatest` near the top of `findilos.sh`.
- The licence key is printed in clear text. Treat the output accordingly.

## How it works

1. nmap scans the target for the iLO virtual media port, 17988 by default.
2. Each host with that port open is asked for `/xmldata?item=All`, which
   returns the server model, serial number and iLO firmware and hardware
   revision without a password. It is asked over HTTP first, then HTTPS.
3. `/xmldata?item=CpqKey` is read for the licence edition and key.
4. The iLO generation is taken from the iLO product name, for example
   "Integrated Lights-Out 5 (iLO 5)", or looked up from its ASIC revision
   when the name does not include it.

## Credits

findilos was written by **iggy** (iggy@nachotech.com,
http://blog.nachotech.com). This fork exists because of that work, and the
original author line is kept in the script.

- [osakanataro](https://github.com/osakanataro/findilos) added iLO 3, 4 and 5
  support and the licence key columns.
- This fork adds fixes, HTTPS, iLO 6, parallel queries and CSV/JSON output.

See [CHANGELOG.md](CHANGELOG.md) for what changed in each version.

## License

No licence has been specified, by the original authors or here.
