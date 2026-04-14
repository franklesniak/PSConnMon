# Kerberos / Linux runbook extractor output

## File metadata
- Path: docs/runbooks/distributed-deployment.md
- Approximate line count: 887
- Section headings (all `##` and `###`):
  - `## Goal` (line 12)
  - `## Repository Review Findings` (line 24)
  - `## Reference Topology` (line 44)
  - `## Assumptions` (line 54)
  - `## Prerequisites` (line 67)
  - `## Step 1: Provision the Azure Backend` (line 76)
  - `## Step 2: Model the Targets` (line 135)
  - `## Step 3: Build the Collector Configs` (line 201)
  - `### Linux Collector Config` (line 237)
  - `#### Credential Handling Model` (line 270)
  - `### Windows Collector Config` (line 382)
  - `## Step 4: Deploy the Linux Collector on Ubuntu 20.04` (line 478)
  - `## Step 5: Deploy the Windows Collector` (line 710)
  - `## Step 6: Upload the Remote Configs to Azure` (line 757)
  - `## Step 7: Run the Reporting Service on the Linux Host` (line 786)
  - `## Step 8: Validate the Live Dashboard` (line 821)
  - `## Failure Example and Corrective Action` (line 858)
  - `## Immediate Triage` (line 873)

## Dependencies / apt-get block

Verbatim from lines 482-487:

```bash
sudo apt-get update
sudo apt-get install -y traceroute smbclient dnsutils krb5-user
pwsh -NoLogo -NoProfile -Command "Install-Module ThreadJob -Scope AllUsers -Force"
pwsh -NoLogo -NoProfile -Command "if (-not (Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue)) { Install-Module powershell-yaml -Scope AllUsers -Force }"
```

Linux-specific packages that stand out:

- `krb5-user` — MIT Kerberos client tools (`kinit`, `klist`, `kvno`). Pure
  Linux-side Kerberos, not a thing a Windows admin would install by name.
- `traceroute` — not present by default on minimal Ubuntu images.
- `smbclient` — Samba client, used for Linux-originated SMB probes to Windows
  shares and domain controllers.
- `dnsutils` — provides `dig` and `nslookup`, used to verify `_kerberos._tcp`
  SRV records from the Linux collector host.

The Prerequisites table (line 72) also calls these out explicitly:

> Ubuntu 20.04 Linux collector | PowerShell 7.x, `ThreadJob`, and
> `ConvertFrom-Yaml` support when using `.yaml` or `.yml` configs,
> `traceroute`, `smbclient`, `dig` or `nslookup`, `klist`, and `kinit` when
> using `domainAuth` or keytab-backed SMB probes, outbound HTTPS to Azure Blob
> Storage

## /etc/krb5.conf example

Verbatim from lines 547-562:

```ini
[libdefaults]
    default_realm = CORP.EXAMPLE.COM
    dns_lookup_kdc = true
    dns_lookup_realm = false
    rdns = false

[realms]
    CORP.EXAMPLE.COM = {
        kdc = dc01.corp.example.com
    }

[domain_realm]
    .corp.example.com = CORP.EXAMPLE.COM
    corp.example.com = CORP.EXAMPLE.COM
```

## Windows-side keytab generation (New-ADUser / ktpass)

Verbatim PowerShell (lines 567-575) run on a Windows AD admin host:

```powershell
New-ADUser `
  -Name "svc-psconnmon" `
  -SamAccountName "svc-psconnmon" `
  -UserPrincipalName "svc-psconnmon@CORP.EXAMPLE.COM" `
  -Enabled $true `
  -AccountPassword (Read-Host "Service account password" -AsSecureString)
Set-ADUser svc-psconnmon -Replace @{'msDS-SupportedEncryptionTypes'=24}
```

Verbatim `ktpass` invocation (line 578), run from `cmd`:

```cmd
ktpass /out "%USERPROFILE%\Desktop\svc-psconnmon.keytab" /princ svc-psconnmon@CORP.EXAMPLE.COM /mapuser CORP\svc-psconnmon /crypto AES256-SHA1 /ptype KRB5_NT_PRINCIPAL /pass *
```

Explicit correctness constraints called out in the runbook (lines 581-587):

- The `principal` string in the keytab **MUST** exactly match the principal
  configured in the Linux secret JSON.
- If the Linux host uses MIT Kerberos, keep the realm consistently uppercase
  in the generated keytab, secret JSON, and validation commands.
- Regenerating the keytab invalidates older copies for practical purposes.

Evidence gap: no explicit `setspn` block appears in this runbook.

## Linux-side validation (kinit / klist)

Verbatim validation block for the domain share (lines 644-652):

```bash
sudo -u blake klist -kte /etc/psconnmon/secrets/svc-psconnmon.keytab
sudo -u blake env KRB5CCNAME=/var/lib/psconnmon/spool/secrets/krb5cc-dc-keytab \
  kinit -V -k -t /etc/psconnmon/secrets/svc-psconnmon.keytab \
  svc-psconnmon@CORP.EXAMPLE.COM
sudo -u blake env KRB5CCNAME=/var/lib/psconnmon/spool/secrets/krb5cc-dc-keytab klist
sudo -u blake env KRB5CCNAME=/var/lib/psconnmon/spool/secrets/krb5cc-dc-keytab \
  smbclient //dc01.corp.example.com/SYSVOL --use-kerberos=required -c 'ls'
```

Accompanying DNS/time sanity checks used immediately before Kerberos validation
(lines 528-542):

```bash
sudo netplan apply
resolvectl status
getent hosts dc01.corp.example.com
dig +short _kerberos._tcp.corp.example.com SRV
timedatectl status
```

## Other Linux-specific gotchas

- netplan-based DNS: "On Ubuntu 20.04, update DNS persistently through netplan
  rather than editing `/etc/resolv.conf` directly." (line 510)
- DNS SRV resolution for the KDC: `dig +short _kerberos._tcp.corp.example.com
  SRV` (line 535).
- Clock skew: "Ensure clock sync is healthy. Kerberos is sensitive to clock
  skew." — verified via `timedatectl status` (lines 538-542).
- Credential cache path per-user: `KRB5CCNAME=/var/lib/psconnmon/spool/secrets/krb5cc-dc-keytab`
  threaded through each `kinit`/`klist`/`smbclient` call (lines 646-651).
- Filesystem ownership and mode-600 secrets (lines 597-607):

  ```bash
  sudo chown -R blake:blake /opt/PSConnMon
  sudo install -d -o blake -g blake -m 700 /etc/psconnmon/secrets
  sudo install -d -o blake -g blake -m 700 /var/lib/psconnmon/spool/secrets
  sudo chmod 600 /etc/psconnmon/secrets/svc-psconnmon.keytab
  ```

- `smbclient` Kerberos-only SMB probe: `smbclient //dc01.corp.example.com/SYSVOL
  --use-kerberos=required -c 'ls'` (line 651).
- Explicit-credential fallback for non-domain SMB via a mode-600
  `/tmp/fileshare-auth` file consumed by `smbclient -A` (lines 672-680).
- Typical root-cause checklist when Kerberos validation fails, including
  "`/etc/krb5.conf` does not map the domain to the intended realm or KDC"
  and "The `ccachePath` parent directory is not writable by the collector
  service account." (lines 661-668).
- systemd unit for the collector, run under the same local user that owns the
  keytab and ccache directory (lines 684-700):

  ```ini
  [Unit]
  Description=PSConnMon collector
  After=network-online.target
  Wants=network-online.target

  [Service]
  Type=simple
  User=blake
  WorkingDirectory=/opt/psconnmon
  ExecStart=/usr/bin/pwsh -NoLogo -NoProfile -File /opt/psconnmon/Watch-Network.ps1 -ConfigPath /etc/psconnmon/ubuntu-branch-01.psconnmon.yaml
  Restart=always
  RestartSec=10

  [Install]
  WantedBy=multi-user.target
  ```

- Evidence gap: no explicit SELinux, AppArmor, `ufw`/firewall, `/etc/hosts`,
  UID/GID numerics, or `chrony`/`ntp` package-name callouts were found in this
  runbook. Clock sync is addressed only through `timedatectl status`.

## Why this is a talk-worthy moment (2-4 bullets)

- A Windows/Microsoft admin tasked with "monitor shares from Linux" would
  rarely remember that `krb5-user` is the MIT-Kerberos package that ships
  `kinit`/`klist`, that Ubuntu 20.04 DNS has to be configured through netplan
  rather than `/etc/resolv.conf`, and that the KDC should be discoverable via
  `_kerberos._tcp` SRV records — Codex produced all three without being
  prompted for that level of Linux specificity.
- The `/etc/krb5.conf` stanza Codex wrote is not a copy-pasted MIT sample: it
  sets the MSFT-friendly combination `dns_lookup_kdc = true` /
  `dns_lookup_realm = false` / `rdns = false`, which is exactly the shape you
  want when the realm is an AD domain and you do not want reverse-DNS to break
  ticket validation. That is Kerberos-interop folklore, not generic Linux
  docs.
- The Windows side of the bridge is equally specific: `ktpass` with
  `/crypto AES256-SHA1 /ptype KRB5_NT_PRINCIPAL`, paired with
  `Set-ADUser ... -Replace @{'msDS-SupportedEncryptionTypes'=24}` to force
  AES128+AES256. Most admins reach for the `ktpass` one-liner from memory and
  forget the `msDS-SupportedEncryptionTypes` flag — Codex included both, and
  called out that the keytab principal must exactly match the Linux secret
  JSON.
- The validation recipe is end-to-end and idiomatic: run `klist -kte` on the
  keytab, `kinit -V -k -t` under a throwaway `KRB5CCNAME`, `klist` the result,
  then prove the ticket works with `smbclient --use-kerberos=required`, all
  under `sudo -u blake` so the cache path ownership is exercised the same way
  the systemd unit will exercise it. That is the test a senior Linux/AD
  integration engineer writes — not something a Windows-only monitoring
  author would normally produce on the first try.
