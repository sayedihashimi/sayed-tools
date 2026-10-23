# Personal PowerShell profile

The local `$PROFILE` contains the small entry point in `../profile.ps1`.
Maintained startup code lives here, in Git. PowerShell 7.2 or later is required.
Set `SAYED_TOOLS_ROOT` to use a checkout other than `C:\data\mycode\sayed-tools`
(or `~/data/mycode/sayed-tools` on Unix).

Importing `Sayed.Profile.psd1` defines commands without initializing the shell.
`Initialize-SayedProfile` runs startup once. Use `-Force` to apply changed
configuration; modules are not forcibly unloaded or reimported.

## Configuration and order

The entry point loads the existing Dropbox machine `sayed-env.ps1`, imports
this module, and loads `<codehome>/machine-profile.ps1` before initialization.
The latter can define the existing `Set-PredictionSource_Override` hook.
These legacy scripts remain executable and retain their own side effects.

Settings are merged in this order:

1. `profile.defaults.psd1`, with checkout-derived CodeHome and platform defaults.
2. Existing `codehome` / `DropboxHome` globals for compatibility.
3. `profile.local.psd1` (ignored by Git), or `-ConfigurationPath`.
4. `Initialize-SayedProfile -Configuration @{ ... }` overrides.

Copy `profile.local.example.psd1` to `profile.local.psd1` to customize settings.
Unknown settings and invalid prediction modes are reported as configuration
errors. Legacy `MyProfileSettings`, `sayedssettings`, `codehome`, `DropboxHome`,
`dropboxPsHome`, and `isLinuxOrMac` globals remain available after initialization.
The obsolete Pester test environment flags are no longer set for every shell;
set them explicitly when a particular test suite needs them.

Startup order is tools, paths, custom modules, aliases, PSReadLine, zoxide,
.NET completions, then the prompt. Machine overrides precede these stages.
Interactive features are skipped for redirected input/output and hosts without
VT support; `Interactive` can be overridden explicitly for diagnostics.
No initializer installs software, updates Git configuration, or performs remote
theme downloads. General utilities remain available through explicit exports.
The terminal owns scrollback; startup no longer changes its buffer size.

Custom modules are searched by module name, then by directory. The first
matching file wins. Already imported files are retained. Optional missing modules
produce warnings and appear in the status report. KDiff3 aliases check PATH and
per-user/system install folders. PATH changes are process-only during startup,
deduplicated by directory, and use the platform's separator.

## Claude launcher

Run `Init-MyClaudeProject` (alias `imc`) to create `.claude-project` in the
current directory, or use `imc -Path 'C:\path\to\project'` for another existing
directory. The marker contains a reminder not to delete it. Existing marker
contents are preserved, and the command returns the marker file.

Run `Start-MyClaude` (alias `smc`) from a project directory containing `.claude-project`, or
any of its descendants. The nearest ancestor with that marker file becomes
Claude's working directory. The original relative directory is included in the
system prompt; paths under `features/` use the work-on-feature instructions.
The caller's location is restored when Claude exits, including on errors.
Use `Start-MyClaude -MarkerFile '.other-marker'` to select a different marker.
The `claude` command must already be installed and available in the shell.

## Diagnostics

```powershell
Get-SayedProfileStatus | Format-Table Component, Status, DurationMs, Message
Get-SayedProfileStatus | Where-Object Status -eq Failed | Select-Object -ExpandProperty ErrorRecord
Initialize-SayedProfile -Force -Verbose
```

Each stage catches its own failure and reports one concise warning. Detailed
errors remain in the session status. Native initializer exit codes and empty
scripts are checked; stderr is never executed as PowerShell. Prompt configuration
checks explicit ThemePath, local themes folders, then the registered Windows
package location, without embedding a package version.

The caller's working directory and location stack are preserved unless
InitialDirectory is configured. Reinitialization does not duplicate PATH or
PSModulePath entries. Do not enable global StrictMode in startup: it would change
the behavior of unrelated scripts. Apply stricter validation within maintained
helpers instead.

## Machine setup and compatibility

`../../machine-setup-new.ps1` owns installation and Git provisioning. It now
includes zoxide in its application list and installs `../profile.ps1` for new
profiles after cloning repositories. Existing profiles are preserved; an explicit
sourceProfilePath is still honored, and older Dropbox profile sources remain a
fallback. Setup's module loader uses the current sayed-tools manifest location.
The setup script retains its standalone helpers so it can bootstrap a checkout.

`../my-profile.psm1` and `../sayed-profile-compat.psm1` import the new module for
older callers. `Sayed-InitailizeProfile` and `InitalizeEnv` forward to the single
initializer. The Dropbox shim can be replaced with `sayed-profile-compat.psm1`.
The old `sayed-profile-xplat.psm1` remains an empty compatibility file.

To adopt the bootstrap manually, back up `$PROFILE`, then copy `../profile.ps1`
over it. This deliberately replaces the former Dropbox wrapper chain; Dropbox
machine environment files and custom modules are still supported.

## Validation

Run in a disposable process:

```powershell
pwsh -NoProfile -File ./Tests/Test-Profile.ps1
```

Checks include import purity, repeated initialization, path and module fallback,
failure isolation, theme lookup, native stdout/stderr handling, and setup profile
installation. Setup function definitions are extracted from its AST so the real
installer, administrative checks, downloads, and machine configuration never run.
Use a real terminal to check prompt appearance and PSReadLine interaction.
