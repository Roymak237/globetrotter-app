# End-to-end probe of the avatar flow against a locally running backend.
#
# Start the API first (port 5099, isolated DATA_DIR) then run this. It proves
# what the endpoint actually accepts rather than what the code appears to say.

$b = "http://127.0.0.1:5099/api"

function Invoke-Api($method, $path, $body, $token) {
    $headers = @{}
    if ($token) { $headers["Authorization"] = "Bearer $token" }
    try {
        $r = Invoke-WebRequest "$b$path" -Method $method -Headers $headers `
            -ContentType "application/json" -Body $body -UseBasicParsing -TimeoutSec 20
        return [pscustomobject]@{ Code = $r.StatusCode; Body = $r.Content }
    } catch {
        $resp = $_.Exception.Response
        $text = ""
        if ($resp) {
            $reader = New-Object IO.StreamReader($resp.GetResponseStream())
            $text = $reader.ReadToEnd().Trim()
        }
        return [pscustomobject]@{ Code = $(if ($resp) { $resp.StatusCode.value__ } else { 0 }); Body = $text }
    }
}

Invoke-Api POST "/auth/register" '{"username":"avatartest","password":"Passw0rd!x","display_name":"Avatar Test"}' $null | Out-Null
$login = Invoke-Api POST "/auth/login" '{"username":"avatartest","password":"Passw0rd!x"}' $null
$token = ($login.Body | ConvertFrom-Json).token

Write-Output "=== PUT /api/me/avatar ==="
foreach ($candidate in @(
        @{ label = "public https URL (what the dialog asks for)"; url = "https://example.com/me.jpg" },
        @{ label = "local path, file does not exist"; url = "/api/media/" + ("a" * 32) + ".jpg" },
        @{ label = "path traversal attempt"; url = "/api/media/../../etc/passwd" },
        @{ label = "clear the avatar"; url = "" })) {
    $body = @{ avatar_url = $candidate.url } | ConvertTo-Json -Compress
    $r = Invoke-Api PUT "/me/avatar" $body $token
    Write-Output ("  {0,-45} -> {1}  {2}" -f $candidate.label, $r.Code, $r.Body)
}

Write-Output ""
Write-Output "=== the flow that should work: upload, then set ==="

# A minimal valid PNG, so the upload is a real image rather than junk bytes.
$pngB64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
$pngPath = Join-Path $env:TEMP "avatar_probe.png"
[IO.File]::WriteAllBytes($pngPath, [Convert]::FromBase64String($pngB64))

$form = @{ file = Get-Item $pngPath }
try {
    # Windows PowerShell 5.1 has no -Form, so the multipart body is assembled
    # by hand. Bytes are written through Latin-1 so the PNG survives intact.
    $boundary = [Guid]::NewGuid().ToString()
    $enc = [Text.Encoding]::GetEncoding("iso-8859-1")
    $bytes = [IO.File]::ReadAllBytes($pngPath)
    $lines = "--$boundary",
    'Content-Disposition: form-data; name="file"; filename="avatar.png"',
    "Content-Type: image/png",
    "",
    $enc.GetString($bytes),
    "--$boundary--",
    ""
    $body = $enc.GetBytes(($lines -join "`r`n"))

    $up = Invoke-RestMethod "$b/media" -Method Post `
        -Headers @{ Authorization = "Bearer $token" } `
        -ContentType "multipart/form-data; boundary=$boundary" `
        -Body $body -TimeoutSec 30
    Write-Output ("  upload            -> 201  url=$($up.url)  kind=$($up.kind)  size=$($up.size)")
    $r = Invoke-Api PUT "/me/avatar" (@{ avatar_url = $up.url } | ConvertTo-Json -Compress) $token
    Write-Output ("  set avatar        -> $($r.Code)  $($r.Body)")
    $me = Invoke-Api GET "/auth/me" $null $token
    $avatar = ($me.Body | ConvertFrom-Json).avatar_url
    Write-Output ("  persisted as      -> '$avatar'")
    Write-Output ("  absolute?         -> " + $(if ($avatar -match '^https?://') { "yes" } else { "NO - relative, Image.network needs a scheme on mobile" }))
} catch {
    Write-Output ("  upload FAILED: " + $_.Exception.Message)
}

Remove-Item $pngPath -ErrorAction SilentlyContinue
