# Validation checklist

Status: draft  
Related ADR: `ADR-0001-private-stealth-proxy-on-single-vps.md`  
Related plan: `private-stealth-proxy-implementation-plan.md`

## Goal

Provide a repeatable acceptance checklist for:

- fresh install on a clean VPS;
- upgrade from legacy layout;
- routine operator validation after changes;
- proof that the private stealth deployment still matches the intended contract.

## Preconditions

- public DNS record already points to the target VPS;
- operator has root access;
- the selected domain and decoy values are known before install;
- VPS outbound access is available for package installation and Telegram config refresh.

## Acceptance gates

The installation is acceptable only if all of the following are true:

1. install requires `PUBLIC_DOMAIN`;
2. the generated links use the configured domain, not an auto-detected IP;
3. the link model matches the selected policy:
   - stealth bundle: `primary-ee`, `reserve-ee`, `fallback-dd`;
   - official `dd` bundle: `primary-dd`, `reserve-dd`, `fallback-classic`;
   - official/classic bundle: `primary-classic`, `reserve-classic`, `fallback-dd`;
   - per-device strategy: `<device>-<primary-profile>` plus one shared fallback;
4. routine commands do not reveal secrets by default;
5. refresh automation is enabled when the engine requires Telegram upstream files;
6. only the intended public entrypoint is exposed publicly;
7. migration preserves the old client secret as a managed fallback slot.

## A. Fresh install validation

### A1. Install

Example:

```bash
sudo PUBLIC_DOMAIN=proxy.example.com ENGINE=stealth bash install-mtproxy.sh install
```

Expected result:

- install succeeds;
- post-install output prints summary only;
- install does not print raw secrets or `tg://proxy?...` links.

### A2. Runtime health

```bash
sudo bash install-mtproxy.sh health
sudo bash install-mtproxy.sh acceptance-smoke
```

Expected result:

- both commands succeed;
- `acceptance-smoke` confirms redaction, link model, permissions, refresh contract, and decoy checks when applicable.

### A3. Link inspection

```bash
sudo bash install-mtproxy.sh list-links
sudo bash install-mtproxy.sh share-links
```

Expected result:

- `list-links` prints labels/profiles and redacted secrets only;
- `share-links` intentionally reveals the final tg-links.

### A4. Public surface

```bash
sudo ss -ltnp
sudo ufw status numbered
```

Expected result:

- only the intended public port is exposed publicly for proxy traffic;
- loopback-only ports stay non-public.

## B. Legacy migration validation

### B1. Migrate

```bash
sudo PUBLIC_DOMAIN=proxy.example.com bash install-mtproxy.sh migrate-install
```

Expected result:

- migration succeeds without losing connectivity;
- the legacy secret is imported as a managed `legacy-import...` slot.

### B2. Post-migration checks

```bash
sudo bash install-mtproxy.sh list-links
sudo bash install-mtproxy.sh acceptance-smoke
```

Expected result:

- the migrated legacy slot is present;
- the active bundle still matches the selected policy;
- health and acceptance smoke both pass.

## C. Rotation validation

Run this only when intentional secret rotation is acceptable.

```bash
sudo bash install-mtproxy.sh rotate-link reserve-ee
sudo bash install-mtproxy.sh share-links
sudo bash install-mtproxy.sh health
```

Adapt the slot name to the active policy.

Expected result:

- only the targeted slot changes;
- runtime restarts cleanly;
- health remains green;
- unchanged slots remain valid.

## D. Refresh validation

Applicable when the engine uses Telegram upstream files.

```bash
sudo bash install-mtproxy.sh refresh-telegram-config
systemctl status mtproxy-refresh.timer --no-pager
```

Expected result:

- refresh command succeeds;
- timer remains enabled;
- service returns to active state after refresh.

## E. Decoy validation

Applicable only for `ENGINE=stealth` with decoy enabled.

```bash
sudo bash install-mtproxy.sh test-decoy
sudo bash install-mtproxy.sh acceptance-smoke
```

Expected result:

- `test-decoy` succeeds;
- `acceptance-smoke` confirms the decoy checks again without secret leakage.

## F. Telegram client workflow

Manual client validation:

1. reveal links intentionally with `share-links`;
2. add the full bundle to Telegram clients;
3. verify that the client can switch to another configured proxy when the primary link is unavailable;
4. verify that the compatibility fallback link remains usable.

## Exit criteria

The rollout is acceptable when:

- fresh install or migration succeeds;
- `health` passes;
- `acceptance-smoke` passes;
- operator can intentionally reveal links and selectively rotate a slot;
- Telegram clients can use the bundle as intended.
