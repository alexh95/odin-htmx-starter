<#
.SYNOPSIS
  promote.ps1's own cases, on the local target (WSL's ~/promote-test), all -WhatIf: nothing is staged,
  pulled or started. Run from the repo root on the dev PC (the local target goes through wsl.exe):

    powershell -NoProfile -ExecutionPolicy Bypass -File deploy/promote-test.ps1

  Each case writes the target's .env, runs promote, and checks whether it went on or refused; the .env
  the target had is put back at the end. Exit 1 on a case that went the wrong way.

  -Snapshot adds the one case that really promotes Houston: -TagA to -TagB, the snapshot into /backups
  beside eight nightly backups, none in /data; back to -TagA past five older snapshots, which the pruner
  cuts to five while the nightlies stay (each kind keeps its own); then a /backups the old container
  can't write, which must stop the promote with nothing changed. It needs local/starter-full:<tag> for both,
  built with VERSION=<tag> (the smoke checks x-version), and leaves no container or volume behind:

    docker build --build-arg PROFILE=full --build-arg VERSION=pt-a -t local/starter-full:pt-a .
#>
param(
	[switch] $Snapshot,
	[string] $TagA = 'pt-a',
	[string] $TagB = 'pt-b'
)
$ErrorActionPreference = 'Stop'
$promote = Join-Path $PSScriptRoot 'promote.ps1'

function Env([string] $text) {
	$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($text))
	wsl.exe -e bash -lc "mkdir -p ~/promote-test && printf '%s' '$b64' | base64 -d > ~/promote-test/.env" | Out-Null
}

$cases = @(
	# The stack's own host paths sit beside the tags and are left alone (M4-12).
	@{ Name = 'tags, FULL_BACKUPS and FULL_TOTP_KEY'; Ok = $true; Env = "IMAGE_PREFIX=local/starter`nTAG_FULL=sha-0000000`nFULL_BACKUPS=/mnt/storage/odin-htmx-starter/backups`nFULL_TOTP_KEY=/srv/stack/totp-key`n" },
	@{ Name = 'a relative path'; Ok = $false; Env = "TAG_FULL=sha-0000000`nFULL_BACKUPS=backups`n" },
	@{ Name = 'a path with ..'; Ok = $false; Env = "TAG_FULL=sha-0000000`nFULL_TOTP_KEY=/srv/../etc/shadow`n" },
	@{ Name = 'a key promote does not know'; Ok = $false; Env = "TAG_FULL=sha-0000000`nSOMETHING=else`n" },
	@{ Name = 'a tag that is no tag'; Ok = $false; Env = "TAG_FULL=latest`n" }
)

function Wsl([string] $script) {
	$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("set -eu`n" + ($script -replace "`r", '')))
	$out = wsl.exe -e bash -lc "printf '%s' '$b64' | base64 -d | bash"
	if ($LASTEXITCODE -ne 0) { throw "wsl: $out" }
	return $out
}

# The test stack's containers, network and volumes, by compose's project label (compose.yaml names it;
# only WSL's ~/promote-test runs it here).
$TEARDOWN = @'
ids=$(docker ps -aq --filter label=com.docker.compose.project=odin-htmx-starter)
[ -z "$ids" ] || docker rm -f $ids >/dev/null
nets=$(docker network ls -q --filter label=com.docker.compose.project=odin-htmx-starter)
[ -z "$nets" ] || docker network rm $nets >/dev/null
vols=$(docker volume ls -q --filter label=com.docker.compose.project=odin-htmx-starter)
[ -z "$vols" ] || docker volume rm $vols >/dev/null
'@
$BUSYBOX = 'busybox:1.37.0@sha256:a7dbc319b1438115a207e11930dc4bb3e643dcb3ec0bdd694bb36cd8fad289ec'
function InData([string] $sh, [string] $user = '10001:10001') {
	Wsl "id=`$(docker ps -q --filter label=com.docker.compose.project=odin-htmx-starter --filter label=com.docker.compose.service=starter-full)
docker run --rm --volumes-from `"`$id`" --user $user --network none --entrypoint /bin/sh $BUSYBOX -c '$sh'"
}

function SnapshotCase {
	Wsl "$TEARDOWN
rm -f ~/promote-test/.env ~/promote-test/deployed.json
: > ~/promote-test/admin-hash" | Out-Null
	$p = { param($tag) & $promote -Target local -Tag $tag -Service starter-full -ImagePrefix local/starter *>&1 | Out-String }
	$log = & $p $TagA
	if ($LASTEXITCODE -ne 0) { return "the first deploy failed: $log" }
	if ((InData 'ls /backups | wc -l') -ne '0') { return "/backups isn't empty before the first snapshot" }
	# More nightlies than the job keeps (7): promote's pruner must leave every one.
	InData 'for i in 1 2 3 4 5 6 7 8; do touch -d "2020-02-0$i" /backups/backup-2020020$i-030000.db; done' | Out-Null

	$log = & $p $TagB
	if ($LASTEXITCODE -ne 0) { return "$TagA -> $TagB failed: $log" }
	if ((InData "head -c 15 /backups/pre-$TagB.db") -ne 'SQLite format 3') { return "no SQLite snapshot /backups/pre-$TagB.db" }
	if ((InData 'test -e /data/backups && echo yes || echo no') -ne 'no') { return "the snapshot made /data/backups" }

	InData 'for i in 1 2 3 4 5; do touch -d "2020-01-0$i" /backups/pre-old$i.db; done' | Out-Null
	$log = & $p $TagA
	if ($LASTEXITCODE -ne 0) { return "$TagB -> $TagA failed: $log" }
	$left = @(InData 'cd /backups && ls -1t pre-*.db')
	$want = @("pre-$TagA.db", "pre-$TagB.db", 'pre-old5.db', 'pre-old4.db', 'pre-old3.db')
	if (Compare-Object $left $want -SyncWindow 0) { return "the pruner left $($left -join ', ')" }
	if ((InData 'ls /backups/backup-*.db | wc -l') -ne '8') { return "promote's pruner touched the nightlies" }

	# A /backups 10001 can't write: refused before the snapshot, Houston left on -TagA.
	InData 'chown 0:0 /backups && chmod 755 /backups' '0:0' | Out-Null
	try { $log = & $p $TagB; $refused = $LASTEXITCODE -ne 0 } catch { $log = $_.Exception.Message; $refused = $true }
	if (-not $refused -or $log -notmatch "/backups isn't writable") { return "an unwritable /backups didn't stop the promote: $log" }
	if ((Wsl "grep '^TAG_FULL=' ~/promote-test/.env") -ne "TAG_FULL=$TagA") { return "the refused promote changed TAG_FULL" }
	return $null
}

$saved = (wsl.exe -e bash -lc 'if [ -f ~/promote-test/.env ]; then base64 -w0 ~/promote-test/.env; else echo NONE; fi') -join ''
$bad = 0
try {
	foreach ($c in $cases) {
		Env $c.Env
		$went = $true
		try { & $promote -Target local -WhatIf -Tag sha-0000000 -Service starter-full *> $null } catch { $went = $false }
		$pass = $went -eq $c.Ok
		if (-not $pass) { $bad++ }
		Write-Host ("{0} {1}: promote {2}" -f $(if ($pass) { 'PASS' } else { 'FAIL' }), $c.Name, $(if ($went) { 'went on' } else { 'refused' }))
	}
	if ($Snapshot) {
		try { $why = SnapshotCase } catch { $why = $_.Exception.Message } finally { Wsl $TEARDOWN | Out-Null }
		if ($why) { $bad++; Write-Host "FAIL the snapshot in /backups, each kind's prune, an unwritable /backups: $why" }
		else { Write-Host "PASS the snapshot in /backups, each kind's prune, an unwritable /backups: $TagA -> $TagB -> $TagA" }
	}
} finally {
	if ($saved -eq 'NONE') { wsl.exe -e bash -lc 'rm -f ~/promote-test/.env' | Out-Null }
	else { wsl.exe -e bash -lc "printf '%s' '$saved' | base64 -d > ~/promote-test/.env" | Out-Null }
}
Write-Host $(if ($bad) { "promote-test: $bad failed" } else { 'promote-test: all passed' })
exit $(if ($bad) { 1 } else { 0 })
