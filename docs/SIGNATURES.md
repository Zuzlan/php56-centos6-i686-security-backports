# Integrity and signatures

All 33 PHP binary RPMs and the source RPM are signed by **Artem Loboda - [www.zuzlan.name](https://www.zuzlan.name)** using a dedicated, passphrase-protected RSA-4096 release key. RPM signatures use SHA-256 with the legacy header-and-payload signature required by EL6. Signing changes signature headers and file hashes, while preserving the previously tested main headers and compressed payloads. All 34 packages passed header and payload signature verification with both RPM 4.18.2 and EL6 RPM 4.8.0. [SIGNING_VERIFICATION.json](SIGNING_VERIFICATION.json) records the checks and package identities.

| Public key | Full fingerprint | Scope |
|---|---|---|
| `RPM-GPG-KEY-artem-loboda-php56` | `B07748530C39253A9E8520F56100DD2FE34B4B53` | 33 PHP RPMs, source RPM and release asset manifest, expires 2029-10-28 UTC |
| `RPM-GPG-KEY-remi` | `1EE04CCE88A4AE4AA29A5DF5004E6F4700F97F56` | Original signatures on the four external dependencies |
| `RPM-GPG-KEY-EPEL-6` | `8C3BE96AF2309184DA5C0DAE3B49DF2A0608B895` | EPEL 6 archive packages |

The maintainer public key is included in `keys/`, `dist/keys/` and the release downloads. The private key, its backup, passphrase and revocation certificate are excluded. The earlier temporary test signature has been replaced.

A valid signature proves possession of a key, not independent identity certification. Confirm the full fingerprint through an independent trusted channel before importing it. Downloading the key and signature together does not establish that trust. The maintainer can publish the fingerprint on their website as an additional verification channel.

## Download verification

Run these commands in the downloaded assets directory, after independently confirming the fingerprint:

```bash
gpg --show-keys --with-fingerprint RPM-GPG-KEY-artem-loboda-php56
gpg --import RPM-GPG-KEY-artem-loboda-php56
gpg --verify SHA256SUMS.asc SHA256SUMS
sha256sum --check SHA256SUMS
```

Require a good signature from the full fingerprint above, and no expiry or revocation error. GnuPG may report unknown owner trust for a manually imported public key, that does not replace the independent fingerprint check. `SHA256SUMS.asc` authenticates the outer asset manifest, which covers both archives, the public key and release notes. The manifests inside the archives provide file integrity and are covered transitively by the signed outer manifest.

From the extracted full release:

```bash
sha256sum --check SHA256SUMS
(cd dist && sha256sum --check SHA256SUMS)
```

On the target, after trusting the fingerprint, import the key and check the PHP RPMs before any installation:

```bash
sudo rpm --import keys/RPM-GPG-KEY-artem-loboda-php56
rpm -Kv dist/RPMS/i686/*.rpm dist/SRPMS/*.rpm
```

Require both header and payload RSA/SHA256 signatures to report `OK`, with key ID `e34b4b53`, stop on an unknown key or failed check. The external dependencies require their original Remi key. See [INSTALL_AND_ROLLBACK.md](INSTALL_AND_ROLLBACK.md) for installation scope.

For a local legacy compatibility check, `bash scripts/verify_el6_signatures.sh` uses a disposable offline 32-bit EL6 container, an empty RPM database and read-only release inputs. It requires local Docker access and the cached verifier image, or `PHP56_VERIFIER_IMAGE` identifying an available EL6 i686 image containing RPM 4.8 and GnuPG. It does not grant Docker access or modify host ACLs.

## Future signing and key custody

Keep the private key and revocation certificate outside the repository and release assets. Maintain an offline backup of the passphrase-protected secret key, keep the passphrase separately. Before expiry, renew the key and distribute the updated public key through trusted channels. If the key is compromised, revoke it and publish a replacement.

On the maintainer's signing workstation, set `signing_home` to the private GnuPG directory. This command replaces signatures on PHP builds only, do not re-sign the external dependency RPMs:

```bash
signing_home=/path/to/private-gnupg
fingerprint=B07748530C39253A9E8520F56100DD2FE34B4B53
GNUPGHOME="$signing_home" rpmsign --resign --rpmv3 \
  --define "__gpg $(command -v gpg)" \
  --define "_gpg_name $fingerprint" \
  --define "_gpg_path $signing_home" \
  --define '_gpg_digest_algo sha256' \
  dist/RPMS/i686/*.rpm dist/SRPMS/*.rpm
```

Enter the passphrase only in GnuPG's local prompt. After signing, verify signatures and payload identity, update provenance and all affected manifests, then create the archives. The packager intentionally produces an unsigned outer manifest. Sign that manifest last, from the assets directory:

```bash
gpg --homedir "$signing_home" --local-user "$fingerprint" \
  --digest-algo SHA256 --armor --detach-sign --output SHA256SUMS.asc SHA256SUMS
gpg --homedir "$signing_home" --verify SHA256SUMS.asc SHA256SUMS
```

Do not modify any covered asset after signing. See the official [RPM signing reference](https://rpm.org/docs/4.20.x/man/rpmsign.8) and [GnuPG key management reference](https://gnupg.org/documentation/manuals/gnupg/OpenPGP-Key-Management.html).
