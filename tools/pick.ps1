<#
    Portable text helpers for a Windows agent shell.

    WHY THIS EXISTS
    ---------------
    The agent "Bash" tool on this project is NOT bash. It is cmd.exe on the
    PC and PowerShell 5.1 on the laptop. Neither has head, tail, cat, grep,
    ls, wc, sed or awk. Agents reflexively emit POSIX pipelines, they fail,
    and the run is wasted. These helpers give the common operations a name
    that exists on BOTH machines, so nobody has to translate a POSIX
    incantation into the right Windows dialect.

    PowerShell 5.1 compatible on purpose. Pure built-ins: nothing to
    install, no network, no admin.

    TWO DELIBERATE DESIGN CHOICES -- DO NOT "FIX" THEM
    --------------------------------------------------
    1. ARGV IS PARSED MANUALLY, NOT WITH A param() BLOCK.
       `powershell -File script.ps1 -n grep f.txt` tries to bind `-n` as a
       *named parameter* of a param block and dies with "A parameter cannot
       be found that matches parameter name 'n'". That is fatal here because
       grep patterns very often start with a dash. With no param block every
       argument lands in $args verbatim, dashes and all.

    2. LEADING POSIX FLAGS ARE ABSORBED, NOT REJECTED.
       The whole failure mode being defended against is a POSIX habit
       leaking in, so `pick grep -n -i "pat" file` is accepted rather than
       mis-bound. Line numbers (-n) and recursion (-r) are always on, so they
       are no-ops. An UNKNOWN flag is a hard error, never a silent
       mis-binding -- that is how a wrong command turns into a wrong result
       instead of a wrong answer.

    USAGE (identical from cmd.exe and from PowerShell)
    --------------------------------------------------
        tools\pick.bat head 20 file.txt
        tools\pick.bat tail 20 file.txt
        tools\pick.bat grep "pattern" file-or-glob
        tools\pick.bat lines file.txt
        tools\pick.bat find <name-wildcard> [dir]
        tools\pick.bat ls [dir]

    From PowerShell you may also call the script directly:
        powershell -NoProfile -File tools\pick.ps1 head 20 file.txt

    EXIT CODES
    ----------
        0  success (and, for grep/find, "matched something")
        1  no match / file not found / bad path
        2  bad usage
#>

$ErrorActionPreference = 'Stop'

$ignoreCase = $false
$countOnly = $false
$invert = $false
$cmd = ''
$tail = @()

if ($args.Count -ge 1 -and -not ([string]$args[0]).StartsWith('-')) {
    $cmd = ([string]$args[0]).ToLowerInvariant()
    # Everything after the command word is an argument; the command itself
    # must NOT be scanned as one, or it flips $seenPositional before the
    # leading flags are seen and `grep -n pat file` mis-binds -n as the
    # pattern.
    if ($args.Count -ge 2) { $tail = @($args[1..($args.Count - 1)]) }
}
else {
    $cmd = 'help'
}

$positional = @()
$seenPositional = $false
foreach ($raw in $tail) {
    $arg = [string]$raw
    if ($cmd -ne 'help' -and -not $seenPositional -and
        $arg.StartsWith('-') -and $arg.Length -gt 1 -and
        -not ($arg -match '^-\d+$')) {
        # Bundled POSIX short flags are the common form (`grep -rn`,
        # `ls -la`), so expand `-abc` into -a -b -c before validating.
        $flags = @($arg)
        if ($arg -match '^-[A-Za-z]{2,}$') {
            $flags = @()
            foreach ($ch in $arg.Substring(1).ToCharArray()) {
                $flags += ('-' + $ch)
            }
        }
        foreach ($f in $flags) {
            if ($f -eq '-i' -or $f -eq '--ignore-case') {
                $ignoreCase = $true
            }
            elseif ($f -eq '-c' -or $f -eq '--count') {
                $countOnly = $true
            }
            elseif ($f -eq '-v' -or $f -eq '--invert-match') {
                $invert = $true
            }
            elseif ($f -eq '-n' -or $f -eq '--line-number' -or
                    $f -eq '-r' -or $f -eq '--recursive' -or
                    $f -eq '-e' -or $f -eq '-a' -or
                    $f -eq '-l' -or $f -eq '--long') {
                # no-op: line numbers, recursion, GNU -e and ls -l are always on
            }
            else {
                Write-Error (("unsupported flag '{0}' -- pick accepts -n -i -r " +
                              "-c -v -e -a -l, and bundled forms such as -rn " +
                              "and -la; head/tail also accept -<count>") -f $f)
                exit 2
            }
        }
    }
    else {
        $seenPositional = $true
        $positional += $arg
    }
}

function Pos([int]$i) {
    if ($i -lt $positional.Count) { return [string]$positional[$i] }
    return ''
}

function Get-RealFile([string]$Path) {
    if (-not $Path) { throw 'missing <file> argument' }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ("no such file: {0}  -- pass an ABSOLUTE path; relative " +
               "paths fail silently in findstr") -f $Path
    }
    return $Path
}

function Get-RealDir([string]$Path) {
    if (-not $Path) { return '.' }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "no such dir: $Path"
    }
    return $Path
}

# Lines from <file>, or from STDIN when no file is given.
# The stdin branch is not a nicety: the single most common failure in this
# project is a POSIX pipeline such as `... | findstr "x" | head -n 10`,
# where head/tail/grep/wc filter a PIPE rather than a named file. Without
# this, that reflex fails on the missing file argument.
function Read-Lines([string]$File) {
    if ($File) { return @(Get-Content -LiteralPath $File) }
    $raw = [Console]::In.ReadToEnd()
    if ($null -eq $raw -or $raw.Length -eq 0) { return @() }
    $split = @($raw -split "\r?\n")
    # A trailing newline yields one empty final element; drop it so line
    # counts match what wc -l would say.
    if ($split.Count -gt 0 -and $split[-1] -eq '') {
        $split = $split[0..($split.Count - 2)]
    }
    return $split
}

function Show-Usage {
    @"
pick <command> [args]     portable head/tail/grep/ls for a Windows shell

  head  <n> <file>            first <n> lines            (default n=20)
  tail  <n> <file>            last <n> lines             (default n=20)
  cat   <file>                whole file
  grep  <pattern> <path>      matching lines as
                              file:lineno:text; <path> may be a
                              glob ('reports\parallel\*.log') or a
                              directory (searched recursively).
                              Exit 1 when nothing matches.
                              -i ignore case, -c count only,
                              -v invert (lines that do NOT match).
  lines <file>                line count
  find  <name> [dir]          recursive file-name search, absolute
                              paths out. Exit 1 when nothing matches.
  ls    [dir] [a]             directory listing; pass 'a' to include
                              hidden entries.
  help                        this text

Examples
  tools\pick.bat tail 40 _gdunit.txt
  tools\pick.bat grep "FAILED" "D:\AI Projects\UltraDrive\reports\parallel\logs\*.log"
  tools\pick.bat find test_perf_gate.gd tests

Tolerated POSIX-isms: -n, -r, -e are no-ops; -i is honoured;
head/tail accept -20 as well as 20. Arguments may start with '-'.
Avoid | < > & inside a pattern: cmd.exe eats them before we do.
"@
}

if ($cmd -eq '' -or $cmd -eq 'help' -or $cmd -eq '-h' -or
    $cmd -eq '--help' -or $cmd -eq '/?') {
    Show-Usage
    exit 0
}

try {
    if ($cmd -eq 'head' -or $cmd -eq 'tail') {
        $n = 20
        $first = (Pos 0)
        if ($first -match '^-?\d+$') {
            $n = [int] $first.TrimStart('-')
            $file = Pos 1
        }
        else {
            $file = $first
        }
        # No file argument means "filter stdin", so `... | head -n 10` works.
        $lines = Read-Lines $file
        if ($cmd -eq 'head') {
            $lines | Select-Object -First $n
        } else {
            if ($n -lt 1) { $n = 1 }
            $lines | Select-Object -Last $n
        }
    }
    elseif ($cmd -eq 'grep') {
        $pattern = Pos 0
        $path = Pos 1
        if ($pattern -eq '') { throw 'usage: pick grep <pattern> <path>' }
        $caseSensitive = -not $ignoreCase
        # No path argument means "filter stdin", so `cmd | grep pat` works.
        # The filename column becomes '-' to keep the file:lineno:text shape.
        if ($path -eq '') {
            $stdinLines = Read-Lines ''
            $shown = 0
            $ln = 0
            foreach ($line in $stdinLines) {
                $ln++
                $hit = if ($ignoreCase) { $line -match $pattern }
                       else { $line -cmatch $pattern }
                if ($hit -eq $invert) { continue }
                $shown++
                if ($countOnly) { continue }
                Write-Output ('{0}:{1}:{2}' -f '-', $ln, $line)
            }
            if ($countOnly) { Write-Output $shown }
            if ($shown -eq 0) { exit 1 }
            exit 0
        }
        if (-not (Test-Path -Path $path)) { throw "no such path: $path" }
        $caseSensitive = -not $ignoreCase
        # Three path shapes, one code path. A directory is searched
        # recursively; a glob is expanded first; anything else is one file.
        # Select-String cannot be handed a directory (it fails with "access
        # denied") and piping FileInfo objects into it searches their NAMES,
        # not their contents -- so always hand it a list of full paths.
        $targets = @()
        if ($path -match '[\*\?]') {
            $targets = @(Get-ChildItem -Path $path -File |
                         Select-Object -ExpandProperty FullName)
        }
        elseif (Test-Path -LiteralPath $path -PathType Container) {
            $targets = @(Get-ChildItem -LiteralPath $path -Recurse -File |
                         Select-Object -ExpandProperty FullName)
        }
        else {
            $targets = @((Get-RealFile $path))
        }
        if ($targets.Count -eq 0) { exit 1 }
        if ($invert) {
            # Line-level invert, per file, preserving file:lineno:text shape.
            # Uses the file's own lines rather than Select-String matches so
            # the output shape matches the non-inverted form exactly.
            $op = if ($ignoreCase) { '-notmatch' } else { '-cnotmatch' }
            $shown = 0
            foreach ($t in $targets) {
                $ln = 0
                foreach ($line in (Get-Content -LiteralPath $t)) {
                    $ln++
                    if ($line -notmatch $pattern) {
                        if (-not $countOnly) {
                            Write-Output ('{0}:{1}:{2}' -f $t, $ln, $line)
                        }
                        $shown++
                    }
                }
            }
            if ($countOnly) { Write-Output $shown }
            if ($shown -eq 0) { exit 1 }
            exit 0
        }
        $hits = @(Select-String -Path $targets -Pattern $pattern `
                                -CaseSensitive:$caseSensitive)
        if ($hits.Count -eq 0) { exit 1 }
        if ($countOnly) {
            Write-Output $hits.Count
            exit 0
        }
        foreach ($h in $hits) {
            '{0}:{1}:{2}' -f $h.Filename, $h.LineNumber, $h.Line
        }
    }
    elseif ($cmd -eq 'cat') {
        Read-Lines (Pos 0)
    }
    elseif ($cmd -eq 'lines') {
        Write-Output (Read-Lines (Pos 0)).Count
    }
    elseif ($cmd -eq 'find') {
        $name = Pos 0
        if ($name -eq '') { throw 'usage: pick find <name-wildcard> [dir]' }
        $dir = Get-RealDir (Pos 1)
        $items = @(Get-ChildItem -LiteralPath $dir -Filter $name -Recurse -File)
        if ($items.Count -eq 0) { exit 1 }
        foreach ($i in $items) { Write-Output $i.FullName }
    }
    elseif ($cmd -eq 'ls') {
        $dir = Get-RealDir (Pos 0)
        $items = Get-ChildItem -LiteralPath $dir
        if ((Pos 1) -eq 'a') { $items = Get-ChildItem -LiteralPath $dir -Force }
        foreach ($i in $items) {
            Write-Output ('{0,-10} {1,10}  {2}' -f $i.Mode, $i.Length, $i.Name)
        }
    }
    elseif ($cmd -eq 'debug') {
        Write-Output ("cmd=[{0}] argc={1} tailcount={2} positional={3}" -f `
                      $cmd, $args.Count, $tail.Count, $positional.Count)
        for ($i = 0; $i -lt $tail.Count; $i++) {
            Write-Output ("  tail[{0}]=[{1}]" -f $i, $tail[$i])
        }
        for ($i = 0; $i -lt $positional.Count; $i++) {
            Write-Output ("  pos[{0}]=[{1}]" -f $i, $positional[$i])
        }
        for ($i = 0; $i -lt 3; $i++) {
            Write-Output ("  Pos({0})=[{1}]" -f $i, (Pos $i))
        }
    }
    else {
        Write-Error ("unknown command '{0}' -- head/tail/cat/grep/ls/wc/" +
                     "sed/awk do NOT exist in this shell; use pick." -f $cmd)
        Show-Usage
        exit 2
    }
}
catch {
    Write-Error ("pick {0}: {1}" -f $cmd, $_.Exception.Message)
    exit 1
}

exit 0