<#
.SYNOPSIS
  Promotes released images to apollo's stack, one service at a time (PLAN §20.5, D42).

.DESCRIPTION
  Run from the dev PC. GitHub's runners can't reach apollo behind NAT, so the release
  workflow publishes the images and this script moves the stack to them:

    1. stage compose.yaml, Caddyfile and seccomp-io-uring.json beside the stack's .env (X21);
    2. docker compose pull the services;
    3. snapshot any service with a database (--backup, the last 5 kept);
    4. per service: its tag in .env, `up -d --no-deps`, never a Caddy reload (lb_try_duration
       holds the gap), healthy within 60 s;
    5. smoke through the stack Caddy: /readyz, x-version == the tag, an SSE stream's first
       line and a WebSocket upgrade where the profile has them;
    6. on a failed smoke, the previous tag again, then the next service is left alone;
    7. deployed.json beside compose.yaml.

  -Status is a read-only inventory of the host. -WhatIf prints the plan and touches nothing.

  The host's SSH alias, the stack's directory and its LAN address are site values: they live in
  deploy/promote.local.psd1 (git-ignored), never in this file:

    @{ Ssh = '<APOLLO_SSH_ALIAS>'; Dir = '<APOLLO_DATA_DIR>/odin-htmx-starter'; Address = '<APOLLO_LAN_IP>' }

  `-Target local` runs the same steps against Docker in WSL (~/promote-test, images already
  built and tagged locally, nothing pulled): the script's own test.

.EXAMPLE
  ./deploy/promote.ps1 -Target apollo-lan -Tag v2.2.0
  ./deploy/promote.ps1 -Target apollo-lan -Tag v2.2.1 -Service starter-lab
  ./deploy/promote.ps1 -Target apollo-lan -Status
#>
[CmdletBinding()]
param(
	[ValidateSet('apollo-lan', 'apollo', 'local')] [string] $Target = 'apollo-lan',
	[string] $Tag,
	# Every service $SERVICES names (checked below); the default leaves Houston out: it goes only when named.
	[ValidateSet('starter-minimal', 'starter-streams', 'starter-skeleton', 'starter-lab', 'starter-full')]
	[string[]] $Service = @('starter-minimal', 'starter-streams', 'starter-skeleton', 'starter-lab'),
	[switch] $Status,
	[switch] $WhatIf,
	# local only: the prefix of the images built in WSL (local/starter-<profile>:<tag>).
	[string] $ImagePrefix = 'ghcr.io/alexh95/odin-htmx-starter'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

# ---- the services ------------------------------------------------------------------------

# Each service's .env key, its host behind the stack Caddy, and what its smoke opens. Only a
# service with a database is snapshotted (starter-full, from M4).
$SERVICES = [ordered]@{
	'starter-minimal'  = @{ Key = 'TAG_MINIMAL';  Host = 'starter-minimal.alexh95.com';   Sse = $null;           Ws = $null }
	'starter-streams'  = @{ Key = 'TAG_STREAMS';  Host = 'starter-streams.alexh95.com';   Sse = '/events';       Ws = $null }
	'starter-skeleton' = @{ Key = 'TAG_SKELETON'; Host = 'starter-skeleton.alexh95.com';  Sse = $null;           Ws = $null }
	'starter-lab'      = @{ Key = 'TAG_LAB';      Host = 'odin-htmx-starter.alexh95.com'; Sse = '/lab/sse/tick'; Ws = '/lab/ws/echo' }
	# Houston: promoted only when named (-Service starter-full), from the first release with its image.
	'starter-full'     = @{ Key = 'TAG_FULL';     Host = 'houston.alexh95.com';           Sse = $null;           Ws = $null }
}
$SNAPSHOT = @('starter-full') # its DB is /data/data.db

# -Service takes exactly the services above: fefd2e3 added starter-full here but not to the
# ValidateSet, and PowerShell refused -Service starter-full before anything ran.
$valid = (Get-Command $PSCommandPath).Parameters['Service'].Attributes |
	Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } | ForEach-Object { $_.ValidValues }
if (Compare-Object @($valid) @($SERVICES.Keys)) {
	throw "promote: -Service's ValidateSet ($($valid -join ', ')) and `$SERVICES ($($SERVICES.Keys -join ', ')) name different services"
}
$PORT = 8120

# ---- where the stack is ------------------------------------------------------------------

if ($Target -eq 'local') {
	$site = @{ Ssh = $null; Dir = '~/promote-test'; Address = '127.0.0.1' }
} else {
	$cfg = Join-Path $PSScriptRoot 'promote.local.psd1'
	if (-not (Test-Path $cfg)) { throw "no ${cfg}: it names the SSH alias, the stack's directory and its LAN address (see the help)" }
	$site = Import-PowerShellDataFile $cfg
	foreach ($k in 'Ssh', 'Dir', 'Address') { if (-not $site[$k]) { throw "$cfg has no $k" } }
}

# One bash script on the host: over SSH, or in WSL for -Target local. Its bytes go to bash's
# stdin as they are: Windows PowerShell's pipe to a native program adds a BOM and CRLFs.
function Invoke-Host([string] $script) {
	$bytes = [Text.Encoding]::UTF8.GetBytes("set -eu`n" + ($script -replace "`r", ''))
	$psi = New-Object Diagnostics.ProcessStartInfo
	if ($Target -eq 'local') { $psi.FileName = 'wsl.exe'; $psi.Arguments = '-e bash -s' }
	else { $psi.FileName = 'ssh'; $psi.Arguments = "-o BatchMode=yes $($site.Ssh) bash -s" }
	$psi.UseShellExecute = $false
	$psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
	$p = [Diagnostics.Process]::Start($psi)
	$p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length); $p.StandardInput.Close()
	$err = $p.StandardError.ReadToEndAsync()
	$out = $p.StandardOutput.ReadToEnd(); $p.WaitForExit()
	if ($p.ExitCode -ne 0) { throw "the host script failed ($($p.ExitCode)): $out$($err.Result)" }
	return ($out -replace "`r", '') -split "`n" | Where-Object { $_ -ne '' }
}

function Quote([string] $s) { "'" + ($s -replace "'", "'\''") + "'" }

$dir = $site.Dir
$dc = "docker compose --project-directory $dir -f $dir/compose.yaml --env-file $dir/.env"

# ---- -Status: read only ------------------------------------------------------------------

if ($Status) {
	Invoke-Host @"
echo "== host";      uname -srm; nproc; free -h | sed -n 1,2p
echo "== disk";      df -h $dir 2>/dev/null || df -h "`$(dirname $dir)"
echo "== docker";    docker version --format '{{.Server.Version}}'; systemctl show docker -p LimitNOFILE 2>/dev/null || true
echo "== npm";       docker ps --format '{{.Image}}' | grep -i 'nginx-proxy-manager' || echo "(no NPM container seen)"
echo "== games api"; curl -s -o /dev/null -m 3 -w '%{http_code} (000: unreachable)\n' http://$($site.Address):8111/ || true
echo "== stack";     if [ -f $dir/compose.yaml ]; then $dc ps --format '{{.Service}} {{.Image}} {{.Status}}'; cat $dir/deployed.json 2>/dev/null; else echo "(not deployed)"; fi
"@
	return
}

# A tag the release publishes, never a mutable one (`latest`): vX.Y.Z, its -rc.N, or the commit's sha-<7>.
# -Target local takes any lower-case name its images were tagged with. The previous tags read back from
# the host's .env meet the same rule before a rollback uses them (M3-08).
# ASCII digits and the string's very end: .NET's \d is any Unicode digit, and its $ also matches before a
# trailing newline (M3-14).
$TAG_RULE = if ($Target -eq 'local') { '\A[a-z0-9][a-z0-9._-]*\z' } else { '\Av[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?\z|\Asha-[0-9a-f]{7}\z' }
if (-not $Tag -or $Tag -cnotmatch $TAG_RULE -or $Tag -ceq 'latest') { throw "-Tag: a release's vX.Y.Z, vX.Y.Z-rc.N or sha-<7>" }

# ---- 1. stage ---------------------------------------------------------------------------

# The current .env (the previous tags), then the new one with this promote's services moved.
$prev = @{}
# Besides its tags and IMAGE_PREFIX, the .env holds the stack's own host paths (M4-12): Houston's
# backups' directory and its TOTP key's file. Promote leaves them as they are, absolute paths with
# no `..`; anything else it doesn't know is refused, as a bad tag is.
$tagKeys = @($SERVICES.Values | ForEach-Object { $_.Key })
$STACK_PATHS = @('FULL_BACKUPS', 'FULL_TOTP_KEY')
$PATH_RULE = '\A/[A-Za-z0-9._/-]+\z'
foreach ($line in @(Invoke-Host "cat $dir/.env 2>/dev/null || true")) {
	if ($line -match '^([A-Z_]+)=(.*)$') {
		$k, $v = $Matches[1], $Matches[2]
		if ($tagKeys -contains $k) {
			if ($v -cnotmatch $TAG_RULE -or $v -ceq 'latest') { throw "the host's .env has $k=$v, not a tag promote would set: fix it by hand first" }
		} elseif ($STACK_PATHS -contains $k) {
			if ($v -cnotmatch $PATH_RULE -or $v -match '(^|/)\.\.(/|$)') { throw "the host's .env has $k=$v, not an absolute host path: fix it by hand first" }
		} elseif ($k -ne 'IMAGE_PREFIX') {
			throw "the host's .env has $k, which promote doesn't know: fix it by hand first"
		}
		$prev[$k] = $v
	}
}
$prefix = if ($Target -eq 'local') { $ImagePrefix } elseif ($prev['IMAGE_PREFIX']) { $prev['IMAGE_PREFIX'] } else { 'ghcr.io/alexh95/odin-htmx-starter' }

function EnvText([hashtable] $tags) {
	$lines = @("IMAGE_PREFIX=$prefix")
	foreach ($s in $SERVICES.Keys) { $k = $SERVICES[$s].Key; $lines += "$k=$($tags[$k])" }
	($lines -join "`n") + "`n"
}
$next = @{}
foreach ($s in $SERVICES.Keys) {
	$k = $SERVICES[$s].Key
	$next[$k] = if ($Service -contains $s) { $Tag } elseif ($prev[$k]) { $prev[$k] } else { $Tag }
}

Write-Host "promote $Tag -> $Target ($($Service -join ', ')) in $dir"
foreach ($s in $Service) { $k = $SERVICES[$s].Key; Write-Host ("  {0,-17} {1} -> {2}" -f $s, ($(if ($prev[$k]) { $prev[$k] } else { '(new)' })), $Tag) }

# The deploy files come from this checkout, not from the tag: newer promote fixes reach every
# release, but a compose newer than its image can ask for what the image lacks (v2.4.0's /backups
# nearly did). Say so, so whoever runs it can look; a warning, never a refusal.
$deployFiles = @('deploy/compose.yaml', 'deploy/Caddyfile', 'docker/seccomp-io-uring.json')
git -C $root rev-parse --verify --quiet "$Tag^{commit}" *> $null
if ($LASTEXITCODE -eq 0) {
	$newer = git -C $root diff --stat $Tag -- @deployFiles
	if ($newer) {
		Write-Warning "the deploy files staged from this checkout differ from $Tag's:"
		$newer | ForEach-Object { Write-Host "  $_" }
	}
} else {
	Write-Host "  ($Tag is no git ref here: the deploy files can't be compared with it)"
}
$global:LASTEXITCODE = 0 # the check's git exit isn't the promote's
if ($WhatIf) { Write-Host "(-WhatIf: nothing staged)"; return }

$files = @{
	'compose.yaml'          = Join-Path $root 'deploy/compose.yaml'
	'Caddyfile'             = Join-Path $root 'deploy/Caddyfile'
	'seccomp-io-uring.json' = Join-Path $root 'docker/seccomp-io-uring.json'
}
$stage = "mkdir -p $dir`n"
foreach ($name in $files.Keys) {
	$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($files[$name]))
	$stage += "printf '%s' '$b64' | base64 -d > $dir/$name`n"
}
# Readable by the containers whatever the host's umask: the Caddy reads its Caddyfile as root without
# DAC_OVERRIDE (M3-13), and Docker reads the seccomp profile.
$stage += "chmod 644 $(($files.Keys | ForEach-Object { "$dir/$_" }) -join ' ')`n"
# A first deploy has no .env yet: every service starts at this tag.
$stage += "[ -f $dir/.env ] || printf '%s' $(Quote (EnvText $next)) > $dir/.env`n"
Invoke-Host $stage | Out-Null

# ---- 2. pull ----------------------------------------------------------------------------

if ($Target -ne 'local') {
	$keys = ($Service | ForEach-Object { "$($SERVICES[$_].Key)=$Tag" }) -join ' '
	Invoke-Host "env $keys $dc pull --quiet $($Service -join ' ')" | Out-Null
}

# ---- 3. snapshot --------------------------------------------------------------------------

# The snapshot goes where the nightly backups go, BACKUP_DIR's /backups (the image's, or FULL_BACKUPS'
# bind): an operator looks in one place, status shows its age beside the nightly's, and it is off the database's
# disk. Each kind keeps its own: promote the newest 5 `pre-*.db`, the nightly job its `backup-*.db`.
# The checks and the pruner run beside the database: busybox pinned by digest (1.37.0), as the app's
# user, with no network (M3-08, M4-12). The backup runs in the old container's binary, whose image has
# no shell and whose SQLite makes no directory, so busybox makes it first (v2.4.0's first snapshot found
# none). A /backups the old container can't write stops the promote, as a failed snapshot does.
$BUSYBOX = 'busybox:1.37.0@sha256:a7dbc319b1438115a207e11930dc4bb3e643dcb3ec0bdd694bb36cd8fad289ec'
foreach ($s in $Service | Where-Object { $SNAPSHOT -contains $_ }) {
	Invoke-Host @"
id=`$($dc ps -q $s)
if [ -n "`$id" ]; then
	docker run --rm --volumes-from "`$id" --user 10001:10001 --network none --entrypoint /bin/sh $BUSYBOX -c 'mkdir -p /backups && test -w /backups' ||
		{ echo "$s's /backups isn't writable by 10001 in the running container: no snapshot, nothing promoted"; exit 1; }
	docker exec "`$id" /app/bin --backup /backups/pre-$Tag.db
	docker run --rm --volumes-from "`$id" --user 10001:10001 --network none --entrypoint /bin/sh $BUSYBOX -c 'ls -1t /backups/pre-*.db | tail -n +6 | xargs -r rm -f' 2>/dev/null || true
fi
"@ | Out-Null
}

# ---- 4-6. one service at a time, smoke, roll back ------------------------------------------

function Smoke([string] $s, [string] $want) {
	$svc = $SERVICES[$s]
	$base = "http://$($svc.Host):$PORT"
	$to = @('--connect-to', "$($svc.Host):${PORT}:$($site.Address):$PORT")
	$code = & curl.exe -s -o NUL -m 5 -w '%{http_code}' @to "$base/readyz"
	if ($code -ne '200') { return "/readyz answered $code" }
	$ver = (& curl.exe -s -I -m 5 @to "$base/" | Where-Object { $_ -match '^x-version:' }) -replace '^x-version:\s*', ''
	if ($ver.Trim() -ne $want) { return "x-version is '$($ver.Trim())', not $want" }
	if ($svc.Sse) {
		$first = & curl.exe -s -N -m 3 @to "$base$($svc.Sse)" 2>$null | Select-Object -First 1
		if ($first -notmatch '^(: open|data:|event:|id:)') { return "$($svc.Sse) sent no SSE line ('$first')" }
	}
	if ($svc.Ws) {
		$up = & curl.exe -s -i -m 3 @to "ws://$($svc.Host):$PORT$($svc.Ws)" 2>$null | Select-Object -First 1
		if ($up -notmatch '^HTTP/1\.1 101') { return "$($svc.Ws) didn't upgrade ('$up')" }
	}
	return $null
}

function Up([string] $s, [string] $tag) {
	$k = $SERVICES[$s].Key
	Invoke-Host @"
sed -i 's|^$k=.*|$k=$tag|' $dir/.env
grep -q '^$k=' $dir/.env || echo '$k=$tag' >> $dir/.env
$dc up -d --no-deps $s 2>&1
for i in `$(seq 1 60); do
	st=`$(docker inspect -f '{{.State.Health.Status}}' "`$($dc ps -q $s)" 2>/dev/null || echo none)
	[ "`$st" = healthy ] && exit 0
	sleep 1
done
echo "$s isn't healthy after 60 s (`$st)"; exit 1
"@ | Out-Null
}

# The Caddy comes up with the first deploy and is never recreated by a promote.
Invoke-Host "$dc up -d --no-recreate caddy 2>&1" | Out-Null

$done = @(); $failed = $null
foreach ($s in $Service) {
	$k = $SERVICES[$s].Key
	$was = $prev[$k]
	Write-Host "-> $s $Tag"
	$why = $null
	try { Up $s $Tag; $why = Smoke $s $Tag } catch { $why = $_.Exception.Message }
	if (-not $why) { $done += $s; Write-Host "   ok"; continue }
	Write-Host "   FAILED: $why"
	if ($was -and $was -ne $Tag) {
		Write-Host "   rolling $s back to $was"
		Up $s $was
		$again = Smoke $s $was
		if ($again) { Write-Host "   the rollback's smoke failed too: $again" } else { Write-Host "   back on $was" }
	}
	$failed = "$s at ${Tag}: $why"
	break
}

# ---- 7. deployed.json ---------------------------------------------------------------------

$state = [ordered]@{ at = (Get-Date).ToUniversalTime().ToString('o'); target = $Target; services = [ordered]@{} }
foreach ($line in @(Invoke-Host "cat $dir/.env")) {
	foreach ($s in $SERVICES.Keys) { if ($line -match "^$($SERVICES[$s].Key)=(.*)$") { $state.services[$s] = $Matches[1] } }
}
$json = $state | ConvertTo-Json -Depth 4
Invoke-Host "printf '%s\n' $(Quote $json) > $dir/deployed.json" | Out-Null

if ($done) { Write-Host "promoted $($done -join ', ') to $Tag" }
# The streams' smoke leaves curl's timeout (28) in $LASTEXITCODE: the result is ours.
if ($failed) { Write-Host "promote stopped: $failed"; exit 1 }
exit 0
