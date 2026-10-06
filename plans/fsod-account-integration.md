# FSoD local account bridge (backend preserved)

## Delivery / boundaries

The original server remains authoritative and unmodified. These are local client
helpers, not an auth replacement or a backend installer:

- `scripts/fsod_account/bridge.py`: stdlib-only loopback HTTP POST helpers for
  **register, verify, char list**, and pure **CREATE/LOAD packet-body** encoders.
- `scripts/fsod_account/rsa_public.py`: offline JSON-stdin credential encryption
  for the original **HELLO.Read** format. Uses the actual upstream **public** key
  and the `cryptography` library; no raw-RSA fallback, private PEM, account token,
  server config secret or RC4 key is copied into the helper.
- `scripts/fsod_account/login_profile.py`: private ignored developer login
  profiles for the parent's Godot client launcher; no plaintext credentials.
- `tests/fsod-account.test.mjs`: verifier-compatible Node adapter that runs the
  real Python fixtures under isolated HOME; fixtures own/close ephemeral loopback
  HTTP servers. Python bytecode caching is disabled.

Source pinned to `6fd20aad4a7905b13f25389c68368a942a2b68cb` at
https://github.com/ossimc82/fabiano-swagger-of-doom. AGPLv3 license text copied
verbatim as `scripts/fsod_account/LICENSE`; provenance headers cite endpoint
files. Credits: ossimc82/Fabian Fischer, C453, Trapped, Donran, creepylava,
Krazyshank, Barm, Nilly, sebastianfra12, Kieron and other upstream contributors.
No upstream visual/binary assets are included in GRAVEBAG.

Exclusive account paths: `scripts/fsod_account/`, this note and
`tests/fsod-account.test.mjs`. Runtime provisioning remains with
`scripts/fsod_backend/` owner. Existing backend/frontend/game/cache files were
not edited. Earlier boss-math research is preserved only in prototype commit
`ed5f7cf`; cleanup `3075fed` removes all prototype files and its obsolete note
from the final tree. There is no simulated Godot boss backend or unused duplicate.

## HTTP API: source readback

`server/RequestHandlers.cs:21–35` parses URL-encoded form bodies (with URL query
fallback), not JSON. `server/Program.cs:117–157` dispatches by endpoint type name.
`RequestHandler.CheckAccount` at `RequestHandlers.cs:39–77`
rejects incorrect passwords, banned accounts and active account locks; it is
not bypassed. HTTP may return `<Error>` with status 200, so status alone cannot
prove login. UTF-8 XML may have the `rotmg` namespace.

1. **POST /account/register** (`server/account/register.cs:23–39`)
   requires exactly six keys: `ignore`, `guid`, `newGUID`, `newPassword`,
   `entrytag`, `isAgeVerified`. We send `ignore=true`, unique never-registered
   `fsod-guest-<uuidhex>` guest GUID, unique
   `fsod-dev-<same-uuidhex>@gmail.invalid` new GUID, password, blank entrytag,
   isAgeVerified=true. Both generated IDs are dev-only; `.invalid` is deliberately
   not a real mailbox. The source's simplistic domain-label whitelist accepts
   `gmail.invalid` (`register.cs:124–137`). Response must be `<Success/>`.
   The fresh-GUID path avoids the source's existing-account upgrade branch.
2. **POST /account/verify** (`server/account/verify.cs:21–35`)
   sends `guid`, `password`; receives `<Account>`. This verifies a password,
   **not email**. Passwords are raw form values; `Database.Verify:198` compares
   `password=SHA1(@password)` in MySQL. Do not prehash HTTP passwords.
3. **POST /char/list** (`server/char/list.cs:60–113`)
   sends the same `guid`, `password`; receives `<Chars nextCharId="..."
   maxNumChars="...">`, nested Account and zero or more Char records. Initial
   empty character list is valid. The source auto-creates guests for some bad
   GUIDs; the helper never falls back to guest after password rejection.

Only allowlisted numeric account/character IDs, slot counts, object types,
levels, verified-email presence and helper-generated dev GUID are returned.
Names, vaults, tokens, passwords, raw XML/errors, server DNS, payment/admin data
are dropped. Bootstrap verifies returned account IDs agree across endpoints.
Credentials are never put in URL query strings or CLI arguments.

## Safety and local commands

Only HTTP literal loopback addresses are accepted; localhost becomes 127.0.0.1
without DNS. Reject external hosts, wildcard/listener addresses, embedded auth,
URL suffixes, scoped/mapped IPv6 and alternative numeric IPv4 spellings. Disable
proxy environment handling and **all redirects**, even same-host redirects.
Bound network timeout to .1–30 seconds and response to 1 MiB. Reject DTD/entity
XML, unexpected schemas and duplicate numeric identifiers. Error output is fixed
codes only; never reflected backend text or exception details.

Runtime must be deliberately provisioned first. Default destination is
`http://127.0.0.1:8080`; specify the actual private listener if different. No
process discovery, service starts, schema writes, SMTP, external request,
payment/admin endpoints, migrations or account deletion are performed.

Examples (password prompt uses getpass on TTY; non-TTY must provide stdin):

```sh
python3 -B scripts/fsod_account/bridge.py --base-url http://127.0.0.1:8080 bootstrap --mail-disabled --local-server-list
python3 -B scripts/fsod_account/bridge.py --base-url http://127.0.0.1:8080 verify --guid '<generated dev GUID>'
python3 -B scripts/fsod_account/bridge.py --base-url http://127.0.0.1:8080 chars --guid '<generated dev GUID>' --local-server-list
python3 -B scripts/fsod_account/bridge.py create-body --class-type 782 --skin-type 0
python3 -B scripts/fsod_account/bridge.py load-body --character-id 1
```

For automation pass `--password-stdin` on bootstrap/verify/chars; stdin is one
password line. Do not put real passwords in shell history, argv, logs or docs.
The helper does not persist credentials. A successful bootstrap leaves one
isolated dev account in the isolated dev database (no cleanup/admin authority).

## Mail / email gating seam — explicit, no auth-off shortcut

`server/account/register.cs:74–82` calls `Program.SendEmail` only if HTTP
`verifyEmail` is true. This is the **exact pre-registration safe seam**: runtime
must set **server.verifyEmail=false** in its isolated local configuration before
bootstrap. `--mail-disabled` is mandatory operator attestation of that setting;
it does **not** change configuration and cannot independently prove SMTP disabled.
No registration against an unspecified listener was attempted.

`Database.Register:281` inserts `verified=0` and a new auth token; `/account/verify`
does not flip it. If `wServer.verifyEmail=true`, `Player.cs:621–627` sends an email
verification dialog and disconnects that unverified account. Runtime can either
use its existing **wServer.verifyEmail=false** option solely in the isolated dev
instance (password authentication still stays on), or mark exactly its designated
dev account verified during controlled DB provisioning. Do not disable general
authentication, bypass CheckAccount or call validateEmail with an exposed token.
The helper never calls sendVerifyEmail/validateEmail or returns auth tokens.

## Exact runtime/bootstrap schema prerequisites

`server/Program.cs:46–57` loads SimpleSettings id `server`, connects using
`db_host`, `db_database`, `db_user`, `db_auth`, and initializes XmlData. SimpleSettings
reads only **CWD/server.cfg** (`db/SimpleSettings.cs:26–43`); keys are `key:value`,
not JSON/INI, and only lines starting # are comments. Original HTTP `port` defaults
**80**; the helper's 8080 default is an explicit unprivileged local deployment
choice, requiring `port:8080`. The HttpListener prefix is **http://*:PORT/**
(`Program.cs:62`), not loopback-only. Runtime owner must contain that listener
to a private network namespace/restricted host boundary; our client rejecting
remote URLs does not fix server bind exposure.

`char/list.cs:136–155` geocodes nonempty `svr{i}Location` via Google and probes
`svr{i}Adr` with TCP2050. Before bootstrap/chars, configure either `svrNum:0`
(no server enumeration) or every entry's `svr{i}Location:` blank and
`svr{i}Adr:127.0.0.1` (plus required Name/Admin keys). **--local-server-list** is
mandatory attestation of this seam; it does not change backend settings. The
original GetUsage probe has no explicit timeout (`list.cs:158–174`); the helper
bounds its own HTTP wait, not that server thread. No external geocoding/probe
requests were triggered by the tests, which use a local fixture endpoint.

The original MySQL dump is `db/rotmgprod.sql`: database `rotmgprod`; accounts
31–61, characters 112–142, dailyquests 165–171, giftcodes 204–209, stats 332–343,
unlockedclasses 370–377, vaults 384–389 plus the other original tables. Merely
constructing `Database` does **not** bootstrap schema (`Database.cs:38–90`).

Registration uses account columns uuid, password (SQL SHA1), name, rank,
namechosen, verified, guild, guildRank, guildFame, vaultCount, maxCharSlot,
regTime, guest, banned, locked, ignored, gifts, isAgeVerified, authToken; then
inserts stats and initial vault (`Database.cs:272–312`). GetAccount subsequently
reads publicMuledump, petYardType, prodAcc, acceptedNewTos, ownedSkins and all
currency/stat fields, giftcodes and daily quest data (`397–446`). Char list uses
characters' `accId/charId/charType/dead/level/...`; default slots are 2, next ID
is MAX(charId)+1, and only nondead characters are listed (`619–665`). Therefore
a minimal handcrafted accounts table is insufficient.

Two concrete **upstream prerequisites**, not silently repaired by the client:
- `Database.cs:303` inserts stats without fortuneTokens/totalFortuneTokens, while
  dump `rotmgprod.sql:338–339` declares both NOT NULL with no default. Strict
  modern MySQL rejects that insert. Runtime/backend owner should add deliberate
  zero defaults/migration or fix the owning insert; do not globally turn strict
  SQL checks off as a bridge workaround.
- `Database.GetDailyQuest:214–246` uses table `dailyQuests`, but dump names it
  `dailyquests` at 165. Linux MySQL with case-sensitive table names needs a
  consistent owning query/schema repair before registration GetAccount works.
- The dump has no unique UUID index (`accounts:31–61`); existing registration
  checks are not atomic. The helper creates random isolated UUIDs but does not
  claim that repairs general concurrent backend registration.

## Character creation/load and RSA protocol

There are **no /char/create or /char/load HTTP endpoints** in RequestHandlers.
Creation/load are original authenticated game TCP packets, not HTTP requests:
- CREATE ID **78**: body network-order ushort classType, ushort skinType.
  `CreateHandler.cs` enforces free character slot and class data, enters target
  world, responds CREATE_SUCCESS ID33 with object/character IDs. Default helper
  class 782 is source Wizard; the server's class data remains authoritative.
- LOAD ID **8**: body network-order int32 characterId, boolean fromArena.
  `LoadHandler.cs` loads only the authenticated account's character, rejects
  dead/missing records, enters target world and returns CREATE_SUCCESS.

Returned body_hex has `transport=false`: **not a framed/encrypted packet and not
sent anywhere**. Full frame length/packet ID, persistent directional RC4 stream,
HELLO/map/ACK lifecycle, movement and hit reporting remain the Godot transport
owner's work. A create-body success is not a created character.

`HelloPacket.cs:30–46` reads BuildVersion, GameId, RSA-encrypted UTF guid, Int32,
RSA-encrypted UTF password, randomint1, Secret, KeyTime, Key bytes, MapInfo bytes,
obf1..obf5 strings. **Read is authoritative:** the upstream Write method
has the intervening Int32 in a different position. `Client.SERVER_VERSION` is
**27.3.2**, enforced in `HelloHandler.cs:26–39`.

`RSA.cs:53–61` decrypts Base64 PKCS#1 v1.5 ciphertext to UTF-8; the public key
comment at 35–40 matches the actual server key. rsa_public.py takes exactly
`{"guid": <string>, "password": <string>}` from JSON stdin and prints only
`guid_ciphertext/password_ciphertext`. The source key is 1024-bit, exponent65537;
each value has at most **117 UTF-8 bytes**. Padding is randomized by cryptography,
not Python random or handcrafted modular arithmetic. Empty string maps to empty
ciphertext, matching the source. The stdlib has no safe RSA implementation;
**RSA helper requires cryptography (tested 41.0.7)**. HTTP helper itself remains
stdlib-only. No private key is stored in this repo or printed in any artifact.

## Private profile / parent launcher contract

Add `--profile` to bootstrap to generate an ignored private profile for the new
account. Or use `profile --guid '<existing GUID>' --local-server-list` for an
existing verified/listed account; `--character-id N` must be in that account's
char list. Default character_id=-1 requests creation, class_type=782 (Wizard),
skin_type=0. Use stdin/getpass as above. Profile preflight checks RSA UTF-8 length
and the library dependency **before** any account mutation.

Profiles are exclusively created as
`scripts/fsod_account/.private/dev-<random uuid>.json`. The directory is 0700,
files 0600, final directory/file symlinks are refused, and existing profiles are
never overwritten. The owned `.gitignore` excludes this whole directory.
Ciphertext is reusable login material: no profile content is printed. CLI output
for profile operations drops the plaintext GUID too, returning only the absolute
profile_path and nonsecret account/character metadata.

Schema: host=127.0.0.1, port=2050, character_id, class_type, skin_type; `hello`
contains actual source properties BuildVersion="27.3.2", GameId=-2 (Nexus),
GUID/Password=RSA ciphertext, **IgnoredInt=0**, randomint1=0, Secret="", KeyTime=0,
Key=[], **MapInfo**=[], and obf1..obf5="". Key/MapInfo are numeric JSON byte arrays
(empty for a Nexus login); MapInfo is the original property name, not MapJSON.
`Hello.Read` discards an unnamed Int32 immediately **after GUID**; the profile's
IgnoredInt is an explicitly added codec key for that unnamed field, not an
original C# property. Write zero there, then Password, then separate randomint1.

The parent launcher contract is:
`-- --fsod-client --fsod-login-file=<absolute profile_path>`.
This worker does not edit the Godot reader/launcher and does not claim those
flags work on this unmerged account branch; the separate transport/frontend owner
must read the profile without printing it. Existing files remain private runtime
data, not receipt artifacts. Fixture profiles are removed by their test context.

## Proof / not tested

Fixture Node check exercises real loopback POST requests, exact register fields,
XML namespaces/errors, numeric-output allowlisting, proxy disablement, redirect
refusal, timeout/input guards, CLI password handling, packet-body byte layout and
RSA roundtrips with a freshly generated in-memory test key, private-profile
permissions/schema/CLI redaction and refusal of unlisted character IDs. The separate offline
proof compiled the original upstream RSA.cs with its original BouncyCastle DLL,
then successfully decrypted our public-key helper's arbitrary fixture ciphertext;
only PASS/exit status was logged (no secret or ciphertext output).

Original wServer build passed in a disposable source clone under Mono/xbuild.
**No live HTTP registration, MySQL account bootstrap, TCP login/create/load or
Godot game session was tested:** loopback 8080/8088/2050 had no listener during
this task. No real account/password/token, reusable live login profile or outbound mail was generated.
Tests cover fixtures, not a claim of runtime readiness.
