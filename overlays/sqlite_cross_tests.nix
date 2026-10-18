final: prev:
prev.lib.optionalAttrs (prev.stdenv.buildPlatform != prev.stdenv.hostPlatform) {
  # SQLite's upstream test runner rebuilds testfixture using the build
  # platform's Tcl, then links it with the host compiler.  That cannot link
  # when cross compiling (for example, glibc Tcl with a musl target).  Keep
  # the source-integrity check, which is runnable on the build platform.
  sqlite = prev.sqlite.overrideAttrs (_: {
    checkTarget = "sourcetest";
  });

  # DBI's generated Makefile passes _FILE_OFFSET_BITS=64 while building its
  # XS module.  Unlike glibc, musl only exposes off64_t when
  # _LARGEFILE64_SOURCE is also defined; Perl's generated headers use that
  # type for Off_t.  This affects only DBI's cross-compiled XS build.
  perlPackages = prev.perlPackages.overrideScope (_: perlPrev: {
      DBI = perlPrev.DBI.overrideAttrs (old: {
        env = old.env // {
          NIX_CFLAGS_COMPILE = (old.env.NIX_CFLAGS_COMPILE or "") + " -D_LARGEFILE64_SOURCE";
        };
      });
    BitVector = perlPrev.BitVector.overrideAttrs (old: {
      env = old.env // {
        NIX_CFLAGS_COMPILE = (old.env.NIX_CFLAGS_COMPILE or "") + " -D_LARGEFILE64_SOURCE";
      };
    });
    DBDSQLite = perlPrev.DBDSQLite.overrideAttrs (old: {
      env = old.env // {
        NIX_CFLAGS_COMPILE = (old.env.NIX_CFLAGS_COMPILE or "") + " -D_LARGEFILE64_SOURCE";
      };
    });
    PadWalker = perlPrev.PadWalker.overrideAttrs (old: {
      env = old.env // {
        NIX_CFLAGS_COMPILE = (old.env.NIX_CFLAGS_COMPILE or "") + " -D_LARGEFILE64_SOURCE";
      };
    });
  });

  # `perlPackages` is a separate scope from `perl`'s passthru scope.  NixOS'
  # command-not-found uses `pkgs.perl.withPackages`, so make that interpreter
  # construct environments from the same overridden scope.
  perl = prev.perl.overrideAttrs (old: {
    passthru = old.passthru // {
      pkgs = final.perlPackages;
      withPackages = f: prev.perl.withPackages (_: f final.perlPackages);
    };
  });

  # NetBSD 11.0 now ships getent.c r1.21, while the pinned nixpkgs patch
  # predates formatting changes in that file.  Replace only that stale patch
  # with nixpkgs upstream b1b2a77e, which refreshes its context unchanged.
  netbsd = prev.netbsd // {
    getent = prev.netbsd.getent.overrideAttrs (_: {
      patches = [ ./getent-netbsd.patch ];
    });
  };

  # musl does not implement getpwent_r.  This is the conditional upstream
  # configure-time fallback used by Buildroot: serialize getpwent instead.
  trousers = prev.trousers.overrideAttrs (old: {
    patches = (old.patches or []) ++ [ ./trousers-musl-no-getpwent-r.patch ];
  });

  # Backport logrotate upstream 04b21743980c4e236ca5e8de18173fbd3848573b.
  # test-0112 checks strerror(ENOTSUP), whose spelling is libc/locale
  # dependent (musl does not use glibc's "Operation not supported").  Keep
  # the FIFO rotation test and require the diagnostic prefix instead.
  logrotate = prev.logrotate.overrideAttrs (old: {
    patches = (old.patches or []) ++ [ ./logrotate-test-0112-locale.patch ];
  });

  # musl has no netgroup API. nsncd upstream confirms there is no useful
  # netgroup/NSS use case on musl (twosigma/nsncd#152); keep every other
  # handler and make only the unavailable protocol requests return not-found.
  nsncd = prev.nsncd.overrideAttrs (old: {
    patches = (old.patches or []) ++ [ ./nsncd-musl-no-netgroup.patch ];
    # The upstream test hard-codes glibc's gethostbyaddr_r localhost result.
    # It is intentionally not portable to musl (the target test run returns a
    # different, valid hostent), like the existing upstream localhost skip.
    checkFlags = old.checkFlags ++ [ "--skip=handlers::test::test_handle_gethostbyaddr" ];
  });
}
