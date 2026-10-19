# Changelog

findilos was written by iggy (iggy@nachotech.com, http://blog.nachotech.com).
Every version below builds on that original work.

## 2.0 (unreleased)

- iLOs are queried in parallel (`-j`, default 16). The results are still
  printed in scan order.
- New `-f csv` and `-f json` output formats. Progress messages go to
  standard error, so the output can be redirected to a file.
- New `-p` option for scanning ports other than 17988. Hosts found on other
  ports are listed only when they answer like an iLO.
- New README and this changelog.

## 1.3

- `xmldata` is tried over HTTPS when HTTP fails. Self-signed iLO
  certificates are accepted.
- The iLO generation is read from the product name, e.g. "(iLO 5)". The
  ASIC table is only a fallback, now uses exact matching, and lists iLO 6
  (ASIC 27 and 28, not yet confirmed on real hardware).
- Fixed: the `PN` tag also matched inside `SPN`.
- Temp files are created with `mktemp` and removed on exit, including when
  the script is interrupted.
- Without root the script uses a TCP connect scan instead of failing.
- Deprecated `fgrep`, `which` and `expr match` were replaced. The script is
  shellcheck clean.

## 1.2 (2019-05-07, osakanataro)

- iLO 5 support (ASIC 19 and 21).

## 1.1 (2019-01-09, osakanataro)

- iLO 3 and iLO 4 support.
- Licence edition and key columns, read from `xmldata?item=CpqKey`.

## 1.0 (iggy, nachotech.com)

- The original findilos: finds iLOs by the virtual media port 17988 and
  lists iLO generation and firmware, server serial number and model, read
  from the unauthenticated `xmldata` endpoint.
