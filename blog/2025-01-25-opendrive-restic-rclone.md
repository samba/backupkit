# Automatic Backups on OpenDrive Unlimited

As of 2025-01, for my backup needs, OpenDrive Unlimited appears to be the most cost-effective option with reasonable security capabilities.

This outlines the process of setting up frequent (nightly) offsite backup, using `restic` and `rclone` with OpenDrive.

This method allows for double-encryption, leveraging native OpenDrive support in Rclone with its transparent crypt layer, and Restic using Rclone as its backend.


## Sign up for OpenDrive's Unlimited plan

Needless to say, you'll need an account on OpenDrive for this process.

OpenDrive's Unlimited plan [states][od-unlimited-policy] that total storage volume really is unlimited, but that they may throttle bandwidth above certain reasonable thresholds.
I consider this to be acceptable for my needs, namely incremental backup, with daily snapshots.

The annual subscription ($99/yr at present) would save you a bit of money. Currently I'm paying about $60/mo to another cloud storage solution, so this will be a nice change for me.

## Set up Rclone with Encryption on OpenDrive


**Important:** Note that Rclone encryption is *not* recoverable if you lose the password.

It may be simplest to just keep a copy of the rclone configuration file (`~/.config/rclone/rclone.conf`) in your password manager.
The file encodes multiple important values, and losing them will be catastrophic, so it's wise to retain a backup of the entire rclone config file.

We will *skip* config encryption in this guide. If you use config encryption, you should keep the password as well.
(You should evaluate whether your personal security habits necessitate config encryption.)

This process [obscures][rclone-obscure] the passwords to prevent onlookers from reading your true password, if you ever edit your rclone config directly.

```bash
PASSWD_OBSCURE="$(echo "MY_PASSWORD" | rclone obscure -)" ## TODO change your password here.
OPENDRIVE_USERNAME="email@domain.com" ## TODO set your account email here.
BACKUP_CRYPTO_KEY="$(echo "123password456" | rclone obscure -)"  ## TODO apply a better encryption key.
BACKUP_CRYPT_SALT="$(uuidgen | rclone obscure -)" # This is basically random...

rclone config create --non-interactive  opendrive_unsafe opendrive  --no-obscure \
    username="${OPENDRIVE_USERNAME}" password="${PASSWD_OBSCURE}" \
    --opendrive-chunk-size=32Mi

rclone mkdir opendrive_unsafe:Backup/crypt

rclone config create od-backup-raw alias remote=opendrive_unsafe:Backup/crypt

rclone config create od-backup crypt --no-obscure remote=od-backup-raw: \
    filename_encryption=standard directory_name_encryption=true \
    bits=256 password=${BACKUP_CRYPTO_KEY} password2=${BACKUP_CRYPT_SALT}

```

You'll end up with an `rclone.conf` with entries like this...

```config
[opendrive_unsafe]
type = opendrive
username = email@domain.com
password = **obscured password**

[od-backup-raw]
type = alias
remote = opendrive_unsafe:Backup/crypt

[od-backup]
type = crypt
bits = 256
password = **obscured password**
password2 = **obscured password**
remote = od-backup-raw:
filename_encryption = standard
directory_name_encryption = true
```

You can test this by copying a file into the crypt, and listing it from the unsafe path.

```bash
rclone copy ~/testfile.txt  od-backup:
rclone ls opendrive_unsafe:
```

You'll see a listing with a file like this:

```bash
   1200  Backup/crypt/e010349lkado8u23kl234u
```

You can check the encryption of the content by printing that file...

```bash
rclone cat opendrive_unsafe:Backup/crypt/e010349lkado8u23kl234u | less
```

You should also log into your OpenDrive portal and inspect the Backup folder yourself, to satisfy your own curiosity that the files are indeed encrypted, from that view.

## Set up Restic archive backed by Rclone


Initialize the backup repository for this host.

This process requires a password for Restic, saved to a file (`~/.restic/passord`).
You should keep a copy of this file in your password manager as well.

If you wish to use single-layer encryption, only that of `rclone` above, then you should add the argument `--insecure-no-password` to every `restic` command.



```bash
mkdir -p ~/.restic
echo "MY_RESTIC_PASSWORD" > ~/.restic/password

restic --repo rclone:od-backup:$(hostname) init \
    --password-file=~/.restic/password
```

To perform a backup snapshot:


```bash
restic -r rclone:od-backup:$(hostname) backup \
    --password-file=~/.restic/password \
    --pack-size=128Mi \
    --limit-upload=$((1024*100)) \
    -H $(hostname) -g hosts,paths,tags -t manual  ~/Documents
```

For recurrent snapshots, it may be useful to apply tags to make them easily found.

```bash
restic -r rclone:od-backup:$(hostname) backup [...] -t auto,daily  ~/Documents
```



To prune historical snapshots, keeping 10 hourly, 7 daily, 3 weekly, 6 monthly, and 2 yearly snapshots:

```bash
restic -r rclone:od-backup:$(hostname) forget --prune \
    --password-file=~/.restic/password \
    -H 10 -d 7 -w 3 -m 6 -y 2 \
    -g hosts,paths,tags
```


Rclone and Restic provide guides ([1][restic-rclone], [2][rclone-restic]) for this integration as well, for additional details.


[rclone-od]: https://rclone.org/opendrive/
[rclone-obscure]: https://rclone.org/commands/rclone_obscure/
[od-unlimited-policy]: https://www.opendrive.com/is-unlimited-storage-truly-unlimited
[restic-rclone]: https://restic.net/blog/2018-04-01/rclone-backend/
[rclone-restic]: https://rclone.org/commands/rclone_serve_restic/
