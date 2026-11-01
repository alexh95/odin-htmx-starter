<#
.SYNOPSIS
  promote.ps1's own cases, on the local target (WSL's ~/promote-test), all -WhatIf: nothing is staged,
  pulled or started. Run from the repo root on the dev PC (the local target goes through wsl.exe):

    powershell -NoProfile -ExecutionPolicy Bypass -File deploy/promote-test.ps1

  Each case writes the target's .env, runs promote, and checks whether it went on or refused; the .env
  the target had is put back at the end. Exit 1 on a case that went the wrong way.
#>
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
} finally {
	if ($saved -eq 'NONE') { wsl.exe -e bash -lc 'rm -f ~/promote-test/.env' | Out-Null }
	else { wsl.exe -e bash -lc "printf '%s' '$saved' | base64 -d > ~/promote-test/.env" | Out-Null }
}
Write-Host $(if ($bad) { "promote-test: $bad failed" } else { 'promote-test: all passed' })
exit $(if ($bad) { 1 } else { 0 })
