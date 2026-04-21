# Operator runbook

Status: draft  
Related ADR: `ADR-0001-private-stealth-proxy-on-single-vps.md`  
Related plan: `private-stealth-proxy-implementation-plan.md`

## Goal

Provide the day-2 operational contract for a private single-VPS MTProto deployment.

## Operating model

This deployment is intentionally quiet by default:

- install output is summary-only;
- `status` and `list-links` are redacted;
- `share-links` is the only routine command that intentionally reveals final tg-links;
- secrets are stored as managed artifacts, not as normal console output.

## Core commands

### Install

```bash
sudo PUBLIC_DOMAIN=proxy.example.com ENGINE=stealth bash install-mtproxy.sh install
```

### Status and health

```bash
sudo bash install-mtproxy.sh status
sudo bash install-mtproxy.sh health
sudo bash install-mtproxy.sh acceptance-smoke
```

Use `acceptance-smoke` after install, migration, policy changes, or permission repairs. Set `ACCEPTANCE_RUN_REFRESH=1` only when you intentionally want the smoke check to execute a real refresh.

### Reveal links intentionally

```bash
sudo bash install-mtproxy.sh share-links
```

### Show redacted link inventory

```bash
sudo bash install-mtproxy.sh list-links
```

### Rotate one slot

```bash
sudo bash install-mtproxy.sh rotate-link reserve-ee
```

Replace the slot name with the active policy slot.

### Rotate all slots

```bash
sudo bash install-mtproxy.sh rotate-all-links
```

### Refresh Telegram upstream config

```bash
sudo bash install-mtproxy.sh refresh-telegram-config
```

### Restart runtime

```bash
sudo bash install-mtproxy.sh restart
```

### Decoy diagnostics

```bash
sudo bash install-mtproxy.sh test-decoy
```

### Legacy migration

```bash
sudo PUBLIC_DOMAIN=proxy.example.com bash install-mtproxy.sh migrate-install
```

### Remove installation

```bash
sudo bash install-mtproxy.sh uninstall
```

## Standard operating procedures

### 1. Fresh install

1. verify DNS for `PUBLIC_DOMAIN` before install;
2. run `install`;
3. run `health`;
4. run `acceptance-smoke`;
5. reveal links intentionally with `share-links` and add them to Telegram clients.

### 2. After policy changes

Examples: engine switch, profile change, decoy change, port change.

1. apply the change through `install` or `migrate-install` with updated parameters;
2. run `health`;
3. run `acceptance-smoke`;
4. if link semantics changed, reveal updated links with `share-links` and update the client bundle.

### 3. Burned primary link

1. rotate only the burned slot with `rotate-link <name>`;
2. run `health`;
3. optionally run `acceptance-smoke`;
4. reveal links intentionally with `share-links`;
5. update only the affected client entry.

### 4. Routine weekly check

```bash
sudo bash install-mtproxy.sh health
sudo bash install-mtproxy.sh acceptance-smoke
sudo bash install-mtproxy.sh status
```

### 5. Migration from legacy layout

1. run `migrate-install` with `PUBLIC_DOMAIN`;
2. verify that the old link was imported as `legacy-import...`;
3. run `health`;
4. run `acceptance-smoke`;
5. reveal the final bundle intentionally and update clients if required.

## Troubleshooting map

### `health` fails on DNS

Likely cause:

- the public domain does not point to the current VPS.

Action:

1. fix DNS;
2. rerun `check-domain`;
3. rerun `health`.

### `acceptance-smoke` fails on redaction

Likely cause:

- a command started printing tg-links or stored secrets.

Action:

1. inspect the failing command output;
2. compare against `list-links` and `status` expectations;
3. fix redaction before further rollout.

### `acceptance-smoke` fails on link definition drift

Likely cause:

- the stored link model no longer matches manifest policy.

Action:

1. rerun `install` with the intended policy values;
2. rerun `health`;
3. rerun `acceptance-smoke`.

### `acceptance-smoke` fails on permission drift

Likely cause:

- files or directories changed owner or mode.

Action:

1. rerun `install` to reconcile permissions;
2. rerun `acceptance-smoke`.

### `test-decoy` fails

Likely cause:

- upstream target unreachable;
- local HTTPS decoy not listening on loopback;
- certificate material missing or mismatched.

Action:

1. verify decoy parameters in the manifest;
2. rerun `health`;
3. rerun `test-decoy`.

## Security rules

- do not treat `share-links` output as normal logs;
- do not paste raw links into tickets or public chats;
- prefer `list-links` and `status` for routine inspection;
- rotate only the affected slot when one link is burned;
- keep the threat model honest: one VPS is still vulnerable to direct IP or ASN blocking.
