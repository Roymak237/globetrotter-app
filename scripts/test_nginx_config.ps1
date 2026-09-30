# Validate frontend/deploy/nginx/conf.d/globetrotter.conf on the VPS.
#
# nginx location precedence is subtle enough that reading the config is not
# evidence: a regex location outranks a plain prefix, so adding an asset rule
# can silently capture /api/ unless every prefix that must win uses `^~`.
# This spins up a throwaway nginx with the real config and probes it.
#
# Docker is not installed locally, but it is on the VPS and `mc` is in the
# docker group, so the test runs there and cleans up after itself.

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$conf = [IO.File]::ReadAllText((Join-Path $repo "frontend\deploy\nginx\conf.d\globetrotter.conf")) -replace "`r", ""
$confB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($conf))

$script = @'
set -e
rm -rf /tmp/gttest && mkdir -p /tmp/gttest/html/app /tmp/gttest/conf
echo LANDING  > /tmp/gttest/html/index.html
echo APPSHELL > /tmp/gttest/html/app/index.html
echo CSSFILE  > /tmp/gttest/html/styles.css
base64 -d /tmp/gt.conf.b64 > /tmp/gttest/conf/default.conf

echo "--- nginx -t ---"
docker run --rm -v /tmp/gttest/conf:/etc/nginx/conf.d:ro --add-host backend:127.0.0.1 nginx:alpine nginx -t 2>&1 | sed "s/^/  /"

docker rm -f gttest >/dev/null 2>&1 || true
docker run -d --name gttest -p 18080:80 -v /tmp/gttest/conf:/etc/nginx/conf.d:ro -v /tmp/gttest/html:/usr/share/nginx/html:ro --add-host backend:127.0.0.1 nginx:alpine >/dev/null
sleep 2

echo ""
printf "%-22s %-5s %-26s %s\n" PATH CODE CONTENT-TYPE BODY
printf "%-22s %-5s %-26s %s\n" ---- ---- ------------ ----
for p in / /styles.css /missing.jpg /missing.css /some/route /app/ /app/deep/link /app/missing.js /api/destinations /api/destinations.json ; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:18080$p")
  ct=$(curl -s -o /dev/null -w "%{content_type}" "http://127.0.0.1:18080$p")
  body=$(curl -s "http://127.0.0.1:18080$p" | head -c 10 | tr -d "\n")
  printf "%-22s %-5s %-26s %s\n" "$p" "$code" "$ct" "$body"
done

docker rm -f gttest >/dev/null
rm -rf /tmp/gttest /tmp/gt.conf.b64
'@
$scriptB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($script -replace "`r", "")))

$key = "$env:USERPROFILE\.ssh\globetrotter_deploy"
ssh -i $key -o StrictHostKeyChecking=no mc@173.249.53.17 "echo $confB64 > /tmp/gt.conf.b64; echo $scriptB64 | base64 -d > /tmp/gt.sh; bash /tmp/gt.sh; rm -f /tmp/gt.sh"
