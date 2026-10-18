# x86_64 musl cross-build runbook

## Canonical build command

Run from the repository root without piping its output:

```sh
nix build --impure --expr '((builtins.getFlake (toString ./.)).nixosConfigurations.iris.extendModules { modules = [({ lib, ... }: { nixpkgs.buildPlatform = "x86_64-linux"; nixpkgs.hostPlatform = lib.mkForce { config = "x86_64-unknown-linux-musl"; }; })]; }).config.system.build.toplevel'
```

## Iteration 1

The canonical command was run on 2026-10-18. It exited non-zero. The first
failing derivation was
`/nix/store/7dwxnk1qcfw3490m4mzngy802zzn2wrg-perl5.42.3-DBI-1.653-x86_64-unknown-linux-musl.drv`.
Its XS compilation used `x86_64-unknown-linux-musl-gcc` with
`-D_FILE_OFFSET_BITS=64`, then Perl headers defined `Off_t` as `off64_t`.
musl did not expose `off64_t`, producing `unknown type name 'off64_t'`.

The cross-only overlay retains SQLite's `sourcetest` check target: SQLite's
normal Tcl runner mixes a build-platform Tcl with host objects and cannot
link in this cross build. The retained `sourcetest` target still verifies
source integrity on the build platform.

SQLite was concretely verified after the overlay:

* effective output: `/nix/store/ga0mcjx6wx50gcdn24ck3vj70kp9wyqh-sqlite-x86_64-unknown-linux-musl-3.53.3-bin`
* effective derivation: `/nix/store/v3afp63a30s6cwrg3pv9cfpgzzd6kji9-sqlite-x86_64-unknown-linux-musl-3.53.3.drv`
* derivation environment: `checkTarget=sourcetest`
* `nix build /nix/store/v3afp63a30s6cwrg3pv9cfpgzzd6kji9-sqlite-x86_64-unknown-linux-musl-3.53.3.drv --no-link` exited 0.

## Iteration 2

Added a cross-only DBI fix. DBI now gets `_LARGEFILE64_SOURCE` in its compile
flags, which is the musl feature-test macro required to declare `off64_t`.
This is limited to the DBI XS package and preserves its test configuration.

Verification and the next canonical toplevel result are pending this
iteration's targeted DBI build and full rerun.

The first targeted DBI attempt exposed an overlay construction error (the
derivation already carries `NIX_CFLAGS_COMPILE` in `env`). The overlay was
corrected to extend `old.env` rather than set a duplicate derivation
attribute. A targeted DBI build then exited 0 for
`/nix/store/zy6fixlw2rzm9l56wmi4vm1mf4736858-perl5.42.3-DBI-1.653-x86_64-unknown-linux-musl.drv`.

The subsequent full rerun nevertheless selected the original DBI derivation
and exited non-zero. The package-set replacement has therefore been changed
to `overrideScope` so dependent Perl packages (including Nix's DBD-SQLite
closure) receive the DBI override. This corrected scope still requires a
targeted build and canonical toplevel rerun.

An initial use of `overrideScope'` was invalid for this package set (only
`overrideScope` is provided); it was corrected before the next attempt.

The scoped DBI override was targeted successfully again (exit 0, derivation
`/nix/store/zy6fixlw2rzm9l56wmi4vm1mf4736858-perl5.42.3-DBI-1.653-x86_64-unknown-linux-musl.drv`).
The canonical command was then rerun and exited 1. DBI was no longer the
failure; it proceeded to the new DBD-SQLite derivation. The first failing
derivation is now
`/nix/store/a2vchs2qwmy165diphnaa8cxzvnm6pnr-nsncd-x86_64-unknown-linux-musl-1.5.3.drv`.
Its linker reports undefined `setnetgrent`, `getnetgrent_r`, `endnetgrent`,
and `innetgr`; musl does not implement the netgroup API used by nsncd.

## Current status and remaining work

The top-level musl build is not successful (latest canonical exit status:
1), and no toplevel store output is claimed. The next work item is a narrow
nsncd musl configuration/patch that disables only unsupported netgroup
handling while retaining its other cache handlers, followed by a targeted
nsncd build and another canonical rerun. The canonical command's complete
latest output is retained at `/tmp/opencode/musl-toplevel-3.log`; the nsncd
derivation log is `/tmp/opencode/nsncd.log`.

## Iteration 3: nsncd netgroups

The actual failing derivation was
`/nix/store/a2vchs2qwmy165diphnaa8cxzvnm6pnr-nsncd-x86_64-unknown-linux-musl-1.5.3.drv`.
Its build log showed that the final link failed on exactly `setnetgrent`,
`getnetgrent_r`, `endnetgrent`, and `innetgr`.

Source inspection of nsncd v1.5.3 (`src/handlers.rs`) found these functions
in one hand-written `extern "C"` block (lines 68--95). They are used only by
`InNetGroup::lookup`, `NetgroupWithName::lookup`, and the `INNETGR` and
`GETNETGRENT` request arms (lines 244--403 and 694--714); the remaining
service, passwd, group, host, and address handlers do not use them. Existing
serialization and request-parsing tests for netgroup protocol data remain
compiled and run.

Upstream investigation found the identical linker failure in
[twosigma/nsncd#152](https://github.com/twosigma/nsncd/issues/152). The
maintainer explained that musl does not implement loadable NSS or netgroups,
so nsncd has no useful netgroup/NSS use case on musl; the issue was closed
without an upstream implementation. `main` still has the same unconditional
extern declarations. This supports disabling only the unsupported request
handlers on musl rather than adding fake libc symbols.

`overlays/nsncd-musl-no-netgroup.patch` therefore cfg-gates the netgroup
extern declarations, their lookup implementations, and the two dispatch arms
with `not(target_env = "musl")`. Source inspection corrected the initial
fallback: an empty byte vector is not an NSCD not-found response. nsncd's
`protocol.rs` explicitly requires an `InNetgroupResponseHeader` or
`NetgroupResponseHeader` even when the service is disabled or no record is
found. On musl `INNETGR` now returns the default header (`found = 0`,
`result = 0`) and `GETNETGRENT` returns the default header (`found = 0`,
`nresults = 0`, `result_len = 0`); all other handlers are unchanged. The
overlay is cross-only. It also skips exactly
`handlers::test::test_handle_gethostbyaddr` only for cross/musl: its expected
bytes encode glibc's localhost `gethostbyaddr_r` result, while musl returns a
different valid hostent. This is analogous to nixpkgs' existing localhost
skip and leaves 25 targeted tests running.

The exact targeted nsncd build command (run from the repository root) is:

```sh
nix build --impure --expr '((builtins.getFlake (toString ./.)).nixosConfigurations.iris.extendModules { modules = [({ lib, ... }: { nixpkgs.buildPlatform = "x86_64-linux"; nixpkgs.hostPlatform = lib.mkForce { config = "x86_64-unknown-linux-musl"; }; })]; }).pkgs.nsncd'
```

After the wire-format correction, that exact command exited 0 and produced:

* derivation: `/nix/store/afvy3q14sg17jjhl6hkqmz4wzhzm9s86-nsncd-x86_64-unknown-linux-musl-1.5.3.drv`
* output: `/nix/store/6cjczhc3z85h1pn50f4zz8c4ch45skrg-nsncd-x86_64-unknown-linux-musl-1.5.3`
* target tests: `25 passed; 0 failed; 10 filtered out` (with only
  `handlers::test::test_handle_gethostbyaddr` added to nsncd's pre-existing
  cross skips).

The canonical toplevel command is rerun next without a pipe; its actual
outcome follows in this runbook.

* derivation: `/nix/store/k818l4hpgqblrjqhx4qmf54sbjz2yx4h-nsncd-x86_64-unknown-linux-musl-1.5.3.drv`
* output: `/nix/store/nn7xw28n1g7ixsr8hi2r293mjpn20hhh-nsncd-x86_64-unknown-linux-musl-1.5.3`
* target test result: `25 passed; 0 failed; 10 filtered out`.

The canonical toplevel command is rerun next without a pipe; its actual
outcome follows in this runbook.

## Iteration 4

The unpiped canonical command was run after the nsncd build and exited 1.
It did not select the prior nsncd failure, so the nsncd fix is active in the
toplevel closure. Its first concrete new source failure was
`perl5.42.3-Bit-Vector-7.4`: its XS compile command included
`-D_FILE_OFFSET_BITS=64`, and Perl's `perl.h` consequently selected
`Off_t = off64_t`; musl had not declared `off64_t`.

Added the same documented musl feature-test macro narrowly to the `BitVector`
Perl package. Targeted validation exited 0 for
`/nix/store/sszrrjpkgay1ivd1gv096l3rxvqc9pc6-perl5.42.3-Bit-Vector-7.4-x86_64-unknown-linux-musl.drv`,
with outputs
`/nix/store/29jvbrlj4x1mplgamq6szsmabrjq2270-perl5.42.3-Bit-Vector-7.4-x86_64-unknown-linux-musl`
and its `-devdoc` output. Its upstream test suite passed: `Files=23,
Tests=91963, Result: PASS`. The toplevel has not been rerun after this
 follow-up repair.

## Iteration 5: Perl scope used by command-not-found

The preceding statement is historical: the canonical command was subsequently
run unpiped after the BitVector repair and exited 1.

Pinned nixpkgs constructs command-not-found with
`pkgs.perl.withPackages (p: [ p.DBDSQLite p.StringShellQuote ])`
(`nixos/modules/programs/command-not-found/command-not-found.nix`, lines
15--25).  `perlPackages` is a separate top-level scope from this interpreter
passthru scope, explaining the stale closure.  Before the fix:

```sh
nix why-depends --derivation \
  /nix/store/idw7fhcws6bffia45pcwzzrc2cpaa795-nixos-system-iris-26.11.20261014.55bfb4d.drv \
  /nix/store/7dwxnk1qcfw3490m4mzngy802zzn2wrg-perl5.42.3-DBI-1.653-x86_64-unknown-linux-musl.drv
```

reported `system-path -> command-not-found -> perl-...-env -> 7dwx...DBI`.
The cross-only overlay now makes `perl`'s `pkgs` and `withPackages` passthru
use the overlaid `perlPackages` scope, preserving the package-local DBI and
BitVector flags without global CFLAGS.

Exact post-fix closure proof:

```sh
nix why-depends --derivation \
  /nix/store/kbfhblm4m4yim4y3hr6h5wsbgmq2hgcr-nixos-system-iris-26.11.20261014.55bfb4d.drv \
  /nix/store/7dwxnk1qcfw3490m4mzngy802zzn2wrg-perl5.42.3-DBI-1.653-x86_64-unknown-linux-musl.drv
# ... does not depend ...
nix why-depends --derivation \
  /nix/store/kbfhblm4m4yim4y3hr6h5wsbgmq2hgcr-nixos-system-iris-26.11.20261014.55bfb4d.drv \
  /nix/store/zy6fixlw2rzm9l56wmi4vm1mf4736858-perl5.42.3-DBI-1.653-x86_64-unknown-linux-musl.drv
```

The latter reports `system-path -> command-not-found -> perl-...-env ->
zy6...DBI`. The focused command-not-found build exited 0:

```sh
nix build --no-link /nix/store/771rwhh4qn0zfy7r9sszqjj8397lbixh-command-not-found.drv
```

The unpiped canonical command then exited 1 after passing stale DBI selection.
Its first new failure was `perl5.42.3-DBD-SQLite-1.74`
(`/nix/store/586bjmvlvmq9m4wsg509vq0q0yqrf76v-...drv`): `SQLite.o` hit the
same Perl `Off_t = off64_t` error. The same package-local
`_LARGEFILE64_SOURCE` flag is now added to `DBDSQLite`; it still needs a
focused build and canonical rerun.

## Iteration 6: DBD-SQLite

The cross-only `DBDSQLite` override was validated before another toplevel
attempt. The exact focused command, run from the repository root, was:

```sh
nix build --impure --expr '((builtins.getFlake (toString ./.)).nixosConfigurations.iris.extendModules { modules = [({ lib, ... }: { nixpkgs.buildPlatform = "x86_64-linux"; nixpkgs.hostPlatform = lib.mkForce { config = "x86_64-unknown-linux-musl"; }; })]; }).pkgs.perlPackages.DBDSQLite' --print-out-paths
```

It exited 0. It built derivation
`/nix/store/0amrdhnh8841zm6fcf6vjmbplkv2r0jq-perl5.42.3-DBD-SQLite-1.74-x86_64-unknown-linux-musl.drv`
and produced
`/nix/store/v72m3vknlcgv11xzrzqnxf29kb48sl3h-perl5.42.3-DBD-SQLite-1.74-x86_64-unknown-linux-musl`.
The unpiped canonical toplevel command is run next; its outcome is recorded
below rather than inferred from this focused build.

## Iteration 7: trousers

The unpiped canonical toplevel command after the DBD-SQLite validation exited
1. DBD-SQLite was no longer the failure. The first new concrete failure was
`/nix/store/7dq46ffbm4aad58j3nc5f5nf4gqhgmdq-trousers-x86_64-unknown-linux-musl-0.3.15.drv`:
`src/tspi/ps/tspps.c` called `getpwent_r`, which musl does not provide.

The fix is intentionally limited to trousers. It is the existing Buildroot
musl patch ([Buildroot mailing list, 2016-08-26](https://lists.buildroot.org/pipermail/buildroot/2016-August/158683.html)):
at configure time it detects `getpwent_r`; when unavailable it uses
`getpwent` while holding the source's existing `user_ps_path` mutex. This
preserves the reentrant implementation on platforms that provide it and does
not change unrelated trousers code.

Focused verification was run from the repository root:

```sh
nix build --impure --expr '((builtins.getFlake (toString ./.)).nixosConfigurations.iris.extendModules { modules = [({ lib, ... }: { nixpkgs.buildPlatform = "x86_64-linux"; nixpkgs.hostPlatform = lib.mkForce { config = "x86_64-unknown-linux-musl"; }; })]; }).pkgs.trousers' --print-out-paths
```

It exited 0, built
`/nix/store/hh2h1375j7cfc69r7snmficzs6lwa4wx-trousers-x86_64-unknown-linux-musl-0.3.15.drv`,
and produced
`/nix/store/59j2nl8bkd2r59l5r72zqbinwpm2d219-trousers-x86_64-unknown-linux-musl-0.3.15`.
The next canonical command is run unpiped; its outcome is recorded below.

## Iteration 8: logrotate test blocker

The unpiped canonical command after the trousers verification exited 1. It
advanced past trousers; the first new failure is
`/nix/store/14famk4mj7h5hkjinx0ys86yw38darq8-logrotate-x86_64-unknown-linux-musl-3.22.0.drv`.
This is not a compilation failure: its test suite reported `TOTAL: 107`,
`PASS: 98`, `SKIP: 8`, and `FAIL: 1`. The sole failure is `test-0112.sh`,
which expects gzip compression of a FIFO to emit the exact diagnostic
`test_fifo.log.1 (read-only) compression: Operation not supported`; on this
musl build it emits no such diagnostic. The complete canonical log is
`/tmp/opencode/musl-toplevel-7.log` and the derivation log is
`/tmp/opencode/logrotate-musl.log`.

No test was disabled: this is a behavioural difference that needs an
upstream-supported test expectation or implementation repair, rather than a
broad check suppression. The top-level musl build remains unsuccessful; its
latest canonical exit status is 1 and its failed output candidate is
`/nix/store/xhzad0v4lza2ji54v4yxv35m2fz1qsd9-nixos-system-iris-26.11.20261014.55bfb4d`.

## Iteration 9: logrotate FIFO diagnostic

The exact failure is test `test-0112.sh`: before the fix its test suite had
`TOTAL: 107`, `PASS: 98`, `SKIP: 8`, and `FAIL: 1`; the only failure printed
`No error printed, but there should be one.` The test's functional FIFO
checks are otherwise the intended regression coverage: a FIFO must not hang
logrotate, it must be rotated, and the regular log files must be compressed.

Upstream already fixed this test's nonportable assertion in commit
[`04b21743980c4e236ca5e8de18173fbd3848573b`](https://github.com/logrotate/logrotate/commit/04b21743980c4e236ca5e8de18173fbd3848573b),
`test: avoid locale dependent errno string`. The 3.22.0 test compared the
glibc English `strerror(ENOTSUP)` text `Operation not supported`; the
upstream commit instead checks the stable `error: unable to open ... for
compression:` diagnostic prefix. The upstream commit's only change is this
one test assertion, and current upstream retains it. This is the correct
musl behavior: the error has been diagnosed, but its libc/locale-rendered
errno text must not be asserted. No production code and no test are skipped.

`overlays/logrotate-test-0112-locale.patch` is that upstream commit applied
only in the existing cross-build overlay. Focused verification used:

```sh
nix build --impure --expr '((builtins.getFlake (toString ./.)).nixosConfigurations.iris.extendModules { modules = [({ lib, ... }: { nixpkgs.buildPlatform = "x86_64-linux"; nixpkgs.hostPlatform = lib.mkForce { config = "x86_64-unknown-linux-musl"; }; })]; }).pkgs.logrotate' --print-out-paths
```

It exited 0, built
`/nix/store/ns4j6d4v6kfas9nm3b8xg1f80p68xcci-logrotate-x86_64-unknown-linux-musl-3.22.0.drv`,
and produced
`/nix/store/gplq5qs6b4cckd35w2awscpa0rbm398w-logrotate-x86_64-unknown-linux-musl-3.22.0`
(plus its man output). Its build log records `PASS: test-0112.sh` and
`TOTAL: 107`, `PASS: 99`, `SKIP: 8`, `FAIL: 0`.

The canonical unpiped toplevel command is rerun next; its exact result is
recorded below rather than inferred from this focused package build.

## Iteration 10: subsequent canonical result

The canonical command was then rerun unpiped, with its complete output saved
at `/tmp/opencode/musl-toplevel-8.log`. It exited 1, but logrotate was no
longer a failed derivation. The first new concrete failure is
`/nix/store/i8i3mzcvihwq0n7rkzfpg1y7kly7zq4q-getent-netbsd-x86_64-unknown-linux-musl-11.0.drv`.
It fails in `patchPhase`, before compilation: Nix applies
`getent.patch` to `usr.bin/getent/getent.c`, but hunk 8 (at line 361) and
hunk 9 (at line 623) fail, leaving `usr.bin/getent/getent.c.rej`.

This is the next blocker, not a logrotate regression. The top-level build
therefore remains unsuccessful; its current failed system derivation is
`/nix/store/265j1w388h9xkqiz07fwdycspiwq69r7-nixos-system-iris-26.11.20261014.55bfb4d.drv`
with candidate output
`/nix/store/76jwkmbz50jp0w0fpyb4pnd1wairxjlr-nixos-system-iris-26.11.20261014.55bfb4d`.

## Iteration 11: NetBSD getent patch alignment

The Iteration 10 failure was a patch-context failure, not a musl source/API
failure. The pinned package (`netbsd.getent`, NetBSD 11.0) filters in
`usr.bin/getent/getent.c` at NetBSD r1.21 (2024-11-21), but pinned nixpkgs
55bfb4d still carried the old `getent.patch` with 2018 timestamps and context.
That patch removes NetBSD-only databases unsupported by the compatibility
headers (`disktab`, `ethers`, `gettytab`, `netgroup`, `printcap`, and `rpc`),
and adjusts the NetBSD address-size constants; it is otherwise unchanged.

Current nixpkgs repaired this exact drift in upstream commit
[`b1b2a77e1054d3d2a379f77364430f7d78dae1c4`](https://github.com/NixOS/nixpkgs/commit/b1b2a77e1054d3d2a379f77364430f7d78dae1c4),
`netbsd.getent: fix outdated patch`, after it was broken by
`a870c0a31ac75bddb5a19853f6f8099a82241678`. Its repair refreshes only patch
context/whitespace (including the two rejected regions), retaining the same
semantic removals. `overlays/getent-netbsd.patch` is that upstream refreshed
patch, and the existing cross-only overlay replaces only
`netbsd.getent.patches` with it; no package or source version is replaced.

Focused validation, run from the repository root:

```sh
nix build --impure --expr '((builtins.getFlake (toString ./.)).nixosConfigurations.iris.extendModules { modules = [({ lib, ... }: { nixpkgs.buildPlatform = "x86_64-linux"; nixpkgs.hostPlatform = lib.mkForce { config = "x86_64-unknown-linux-musl"; }; })]; }).pkgs.netbsd.getent' --print-out-paths
```

exited 0. It built
`/nix/store/snr0jpkh3pmmbwp35a72r6irdpaqjdpz-getent-netbsd-x86_64-unknown-linux-musl-11.0.drv`
and produced
`/nix/store/jiwlwzdya1rhaysyilhds73y4mddyxhn-getent-netbsd-x86_64-unknown-linux-musl-11.0`.
Before vendoring it, the refreshed upstream patch also passed
`patch -p1 --dry-run` against the exact filtered source from the failed
pinned derivation. The canonical command is rerun unpiped next; its actual
outcome is recorded below.

## Iteration 12: post-getent canonical result

The exact canonical command above was rerun unpiped after the getent repair;
its complete output is `/tmp/opencode/musl-toplevel-9.log` and it exited 1.
It built the revised `getent-getent-netbsd` wrapper
(`/nix/store/25s5a79r5l9yd9ilgiqqzjhwqahm678n-getent-getent-netbsd-x86_64-unknown-linux-musl-11.0.drv`)
without repeating the getent patch failure. The first new concrete source
failure was
`/nix/store/q1mkf0ykjzzkprh52qk7pq0jwgyf7rpg-perl5.42.3-PadWalker-2.5-x86_64-unknown-linux-musl.drv`:
its XS compile includes `_FILE_OFFSET_BITS=64`, and Perl consequently defines
`Off_t` as `off64_t`, which musl exposes only with `_LARGEFILE64_SOURCE`.

The same package-local, cross-only feature-test macro used for the prior Perl
XS failures was added only to `PadWalker`. Focused validation:

```sh
nix build --impure --expr '((builtins.getFlake (toString ./.)).nixosConfigurations.iris.extendModules { modules = [({ lib, ... }: { nixpkgs.buildPlatform = "x86_64-linux"; nixpkgs.hostPlatform = lib.mkForce { config = "x86_64-unknown-linux-musl"; }; })]; }).pkgs.perlPackages.PadWalker' --print-out-paths
```

exited 0, building
`/nix/store/zkz0svnnizkvdshfq15sk14my6136p4v-perl5.42.3-PadWalker-2.5-x86_64-unknown-linux-musl.drv`
and producing
`/nix/store/q21dxr0cgmz8vi9sqxm1nshi1kzf47lw-perl5.42.3-PadWalker-2.5-x86_64-unknown-linux-musl`.
No further canonical rerun was made after this follow-up repair. The real last
canonical result remains exit 1, not a toplevel store result.

## Iteration 13: post-PadWalker canonical result

The PadWalker focused validation above was followed by the exact canonical
command, run unpiped. Its complete output is
`/tmp/opencode/musl-toplevel-10.log`; it exited `1` (recorded in
`/tmp/opencode/musl-toplevel-10.status`). PadWalker was accepted into this
closure: the new build plan did not request its prior failing derivation
`q1mkf0ykjzzkprh52qk7pq0jwgyf7rpg`, and it built dependent Perl packages
including `Test-Warnings`, `File-Copy-Recursive`, and `URI` before the new
failure.

The first new concrete failure is not another leaf package: it is
`/nix/store/973qldkzprbmjiv6pci94vvx1di6ph54-glibc-nolibgcc-x86_64-unknown-linux-musl-2.44-25.drv`.
Its glibc build tries to compile glibc itself with
`x86_64-unknown-linux-musl-gcc` and fails in `string/memrchr.os`:

```
../include/libc-symbols.h:475:33: error: '__EI___memrchr' aliased to undefined symbol '__GI___memrchr'
make[2]: *** [.../string/memrchr.os] Error 1
```

The full derivation log is `/tmp/opencode/glibc-nolibgcc-musl.log`. This is a
libc/toolchain-closure issue rather than an individual target package's
unsupported musl API, so no broad or package-local workaround was added.
The toplevel remains unsuccessful. The failed system derivation is
`/nix/store/frf1ncgvck0aakz3g4ls0ixf27qs2i3p-nixos-system-iris-26.11.20261014.55bfb4d.drv`,
with candidate output
`/nix/store/lvcs0fnin9aa9ly2d6vpg1n851sndc5f-nixos-system-iris-26.11.20261014.55bfb4d`.

## Iteration 14: `glibc-nolibgcc` root-cause and reproducible roadblock

This blocker is **not** caused by a mixed platform record in the canonical
module override, nor by one of this repository's cross-only package overlays.
The configuration must remain unpatched until the pinned nixpkgs bootstrap
failure is fixed upstream or the input is advanced with its verified fix.

### Effective canonical platform and compiler

The following evaluation was run against the exact canonical `extendModules`
expression and the locked nixpkgs revision `55bfb4d7437bd4e09ab7cba58a43bd68eb310044`:

```sh
nix eval --impure --json --expr 'let pkgs =
  ((builtins.getFlake (toString ./.)).nixosConfigurations.iris.extendModules {
    modules = [({ lib, ... }: {
      nixpkgs.buildPlatform = "x86_64-linux";
      nixpkgs.hostPlatform = lib.mkForce { config = "x86_64-unknown-linux-musl"; };
    })];
  }).pkgs;
in {
  build = pkgs.stdenv.buildPlatform.config;
  host = pkgs.stdenv.hostPlatform.config;
  target = pkgs.stdenv.targetPlatform.config;
  canExecute = pkgs.stdenv.buildPlatform.canExecute pkgs.stdenv.hostPlatform;
  cc = pkgs.stdenv.cc.name;
  libc = pkgs.stdenv.cc.libc.name;
}'
```

It returned `build = x86_64-unknown-linux-gnu`,
`host = target = x86_64-unknown-linux-musl`, `canExecute = true`,
`cc = x86_64-unknown-linux-musl-gcc-wrapper-16.2.0`, and
`libc = musl-x86_64-unknown-linux-musl-1.2.6`.  Thus `buildPlatform =
"x86_64-linux"` was parsed to the expected GNU build triple and the host
record selected musl; it did not leave a missing libc or select a native
compiler.

### Minimal pinned comparison

The same locked input was imported without this repository's NixOS modules or
overlays:

```sh
nix build --no-link --impure --expr 'let
  f = builtins.getFlake (toString ./.) ;
  pkgs = import f.inputs.nixpkgs {
    localSystem = "x86_64-linux";
    crossSystem = "x86_64-unknown-linux-musl";
  };
in pkgs.glibc'
```

Its evaluated build/host/target triples, compiler, libc, and `canExecute`
value were byte-for-byte the values above.  More importantly, it selected the
same bootstrap closure:

```text
glibc-nolibgcc-x86_64-unknown-linux-musl-2.44-25.drv
  -> libgcc-x86_64-unknown-linux-musl-16.2.0.drv
  -> glibc-x86_64-unknown-linux-musl-2.44-25.drv
```

The focused build was run on 2026-10-18 and exited `1` at exactly
`/nix/store/973qldkzprbmjiv6pci94vvx1di6ph54-glibc-nolibgcc-x86_64-unknown-linux-musl-2.44-25.drv`,
with builder exit status `2`; it reproduces independently of the system
closure.

### Dependency path from the canonical toplevel

`nix why-depends --derivation` from the failed canonical system derivation
`frf1ncgvck0aakz3g4ls0ixf27qs2i3p-nixos-system-iris-26.11.20261014.55bfb4d.drv`
to the failed derivation reports:

```text
nixos-system-iris
  -> etc
  -> system-units
  -> unit-suid-sgid-wrappers.service
  -> unit-script-suid-sgid-wrappers-start
  -> security-wrapper-su-x86_64-unknown-linux-musl
  -> glibc-2.44-25-source-x86_64-unknown-linux-musl-unsecvars
  -> libgcc-x86_64-unknown-linux-musl-16.2.0
  -> glibc-nolibgcc-x86_64-unknown-linux-musl-2.44-25
```

This is the normal cyclic-bootstrap edge, not a dependency introduced by
SQLite, Perl, nsncd, trousers, logrotate, or NetBSD getent overrides.  The
pinned nixpkgs source explicitly constructs this shape: `pkgs/stdenv/cross/
default.nix` sets `buildPlatform = localSystem` and `hostPlatform =
targetPlatform = crossSystem` (lines 43--46), and the glibc expression names
this pre-libgcc bootstrap package `-nolibgcc` when `libgcc == null`
(`pkgs/development/libraries/glibc/default.nix`, lines 31--34).  That
expression also documents the glibc/libgcc bootstrap recursion and why it
uses build-platform glibc tools (lines 128--140).

### Failure classification and safe next step

The derivation compiles glibc itself with the expected
`x86_64-unknown-linux-musl-gcc`; its command line uses the nolibc GCC headers
and Linux headers, then fails at glibc's x86 multiarch IFUNC alias:

```text
../include/libc-symbols.h:475:33: error: '__EI___memrchr' aliased to undefined symbol '__GI___memrchr'
```

`-Wno-error=attribute-alias` is already present in the derivation environment;
this is an alias-to-an-undefined-symbol compiler error, not that warning.  It
therefore cannot be made safe by adding warning flags or by pretending that
musl provides a missing API.  Glibc upstream has previously fixed the same
IFUNC/hidden-alias failure mode by changing the relevant source to use
`libc_ifunc_hidden` (for example, the documented powerpc fix
[648c3b574d](https://sourceware.org/git/?p=glibc.git;a=commit;h=648c3b574d4465042116db6016c13bf6cc53db54)).  A local source patch selected
by analogy would be unsafe without an upstream x86 fix and bootstrap testing.

Accordingly no glibc patch, compiler-flag suppression, or closure substitution
was added.  The exact platform construction is coherent—it is equivalent to
the minimal canonical nixpkgs musl cross import—but the locked nixpkgs
`glibc-2.44`/GCC-16 bootstrap cannot build.  The reproducible roadblock is to
advance/pin nixpkgs only after identifying an upstream fix and validating the
minimal command above, then rerun the exact canonical command.  Until then,
the canonical toplevel cannot finish at this bootstrap dependency.
