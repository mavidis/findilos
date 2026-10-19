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
findilos [-f table|csv|json] [-j jobs] [-p ports] TARGET
```

| Option | Meaning | Default |
| --- | --- | --- |
| `-f` | Output format: `table`, `csv` or `json` | `table` |
| `-j` | How many iLOs are queried at the same time | `16` |
| `-p` | Ports to scan, comma separated or ranges | `17988` |

`TARGET` is anything nmap accepts: hostnames, IP addresses, networks or
ranges such as `server1.company.com`, `192.168.0.0/24` or
`10.0.0-255.1-254`.

### Examples

```
sudo ./findilos.sh 192.168.0.0/24
sudo ./findilos.sh -f csv 10.0.0.0/22 > ilos.csv
sudo ./findilos.sh -f json -p 17988,443 10.0.0.0/24
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
- The licence key is printed in clear text. Treat the output accordingly.

## Credits

- Original script by iggy (iggy@nachotech.com), http://blog.nachotech.com
- iLO 3, 4 and 5 support and licence key output by
  [osakanataro](https://github.com/osakanataro/findilos)

## License

No licence has been specified, by the original authors or here.
