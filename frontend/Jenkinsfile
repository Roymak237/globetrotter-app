// Deployment pipeline for the KamerGo travel app.
//
// This file lives in the frontend repository, so `checkout scm` puts the
// Flutter app at the workspace root. The backend is a separate repository and
// is checked out into a subdirectory during the build.
//
// Jenkins runs on the VPS with the host Docker socket mounted, so build
// toolchains run in sibling containers and no SDK is installed into Jenkins
// itself. The live deployment directory is bind mounted at the same absolute
// path it has on the host, which keeps Compose bind mounts valid on both sides.
pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        timestamps()
        timeout(time: 75, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '15'))
        skipDefaultCheckout(true)
    }

    triggers {
        pollSCM('H/5 * * * *')
    }

    environment {
        APP_DIR        = '/home/mc/project/globetrotter-app'
        DOMAIN         = 'kamer-go.duckdns.org'
        APP_PORT       = '6003'
        JENKINS_VOLUME = 'kamergo-ci_jenkins_home'
        // Must match the SDK the app is developed against. Older images ship a
        // Dart version that the dependency tree rejects.
        FLUTTER_IMAGE  = 'ghcr.io/cirruslabs/flutter:3.41.6'
        PYTHON_IMAGE   = 'python:3.11-slim'
        BACKEND_REPO   = 'https://github.com/Roymak237/kamer-go-backend.git'
        BACKEND_BRANCH = 'shadow'
    }

    stages {
        stage('Checkout') {
            steps {
                // The frontend repository supplies the Flutter app, this
                // Jenkinsfile and everything under deploy/.
                checkout scm

                dir('backend') {
                    git url: env.BACKEND_REPO, branch: env.BACKEND_BRANCH
                }

                sh '''#!/usr/bin/env bash
set -euo pipefail
echo "frontend $(git rev-parse --short HEAD)"
echo "backend  $(git -C backend rev-parse --short HEAD)"
'''
            }
        }

        stage('Backend checks') {
            steps {
                sh '''#!/usr/bin/env bash
set -euo pipefail

# Runs against a throwaway data directory so neither the checkout nor the live
# volume is touched by test writes.
docker run --rm \
    -v "${JENKINS_VOLUME}:/var/jenkins_home" \
    -w "${WORKSPACE}" \
    -e PIP_DISABLE_PIP_VERSION_CHECK=1 \
    "${PYTHON_IMAGE}" \
    bash -c '
set -euo pipefail
pip install --quiet --no-cache-dir -r backend/requirements.txt
python - <<"PY"
import os, secrets, shutil, sys, tempfile
from pathlib import Path

source = Path("backend").resolve()
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    shutil.copytree(source / "app", root / "app",
                    ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    (root / "data").mkdir()
    shutil.copyfile(source / "data/destinations.json", root / "data/destinations.json")
    for name in ("users", "itineraries", "shares"):
        (root / f"data/{name}.json").write_text("[]", encoding="utf-8")

    sys.path.insert(0, str(root))
    os.environ["SECRET_KEY"] = secrets.token_hex(32)
    from app import create_app, models

    assert Path(models.DATA_DIR).resolve() == root / "data", "Test data isolation failed"

    app = create_app()
    app.config["TESTING"] = True
    client = app.test_client()

    assert client.get("/healthz").get_json() == {"status": "ok"}

    listing = client.get("/api/destinations")
    assert listing.status_code == 200 and len(listing.get_json()) > 0

    assert client.get("/api/auth/me").status_code == 401

    creds = {"username": "ci_check", "password": secrets.token_urlsafe(20)}
    assert client.post("/api/auth/register", json=creds).status_code == 201
    login = client.post("/api/auth/login", json=creds)
    assert login.status_code == 200
    token = login.get_json()["token"]
    assert client.get("/api/auth/me",
                      headers={"Authorization": "Bearer " + token}).status_code == 200

print("Backend checks passed.")
PY
'
'''
            }
        }

        stage('Frontend build') {
            steps {
                sh '''#!/usr/bin/env bash
set -euo pipefail

# The API base URL is compiled in, so the deployed app calls its own domain
# instead of the localhost default used during development.
docker run --rm \
    -v "${JENKINS_VOLUME}:/var/jenkins_home" \
    -w "${WORKSPACE}" \
    -e PUB_CACHE=/var/jenkins_home/.pub-cache \
    "${FLUTTER_IMAGE}" \
    bash -c "
set -euo pipefail
git config --global --add safe.directory /sdks/flutter
git config --global --add safe.directory ${WORKSPACE}
flutter --version
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build web --release --base-href /app/ --dart-define=BACKEND_BASE_URL=https://${DOMAIN}
"

# The build ran as root inside the container. Flutter writes outside build/
# too (.dart_tool, .flutter-plugins, caches), and anything left owned by root
# blocks both publishing and the workspace cleanup, so reclaim the whole tree.
docker run --rm \
    -v "${JENKINS_VOLUME}:/var/jenkins_home" \
    "${PYTHON_IMAGE}" \
    chown -R "$(id -u):$(id -g)" "${WORKSPACE}"

test -f "${WORKSPACE}/build/web/index.html"
'''
            }
        }

        stage('Android package') {
            steps {
                // The web app is the primary artefact. A broken Android
                // toolchain should surface as UNSTABLE rather than block a
                // deployment that is otherwise good.
                catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
                    sh '''#!/usr/bin/env bash
set -euo pipefail

docker run --rm \
    -v "${JENKINS_VOLUME}:/var/jenkins_home" \
    -w "${WORKSPACE}" \
    -e PUB_CACHE=/var/jenkins_home/.pub-cache \
    -e GRADLE_USER_HOME=/var/jenkins_home/.gradle \
    "${FLUTTER_IMAGE}" \
    bash -c "
set -euo pipefail
git config --global --add safe.directory /sdks/flutter
git config --global --add safe.directory ${WORKSPACE}
yes | flutter doctor --android-licenses >/dev/null 2>&1 || true
flutter build apk --release --dart-define=BACKEND_BASE_URL=https://${DOMAIN}
"

# Gradle and the Android SDK also write as root inside the container.
docker run --rm \
    -v "${JENKINS_VOLUME}:/var/jenkins_home" \
    "${PYTHON_IMAGE}" \
    chown -R "$(id -u):$(id -g)" "${WORKSPACE}"

test -f "${WORKSPACE}/build/app/outputs/flutter-apk/app-release.apk"
'''
                }
            }
        }

        stage('Publish release') {
            steps {
                sh '''#!/usr/bin/env bash
set -euo pipefail

# The signing key lives only on the server. Losing it would invalidate every
# issued token, so its absence is a hard failure rather than a regeneration.
test -f "${APP_DIR}/.env" || { echo "ERROR: ${APP_DIR}/.env is missing." >&2; exit 1; }

backup="${APP_DIR}/.rollback"
rm -rf "${backup}"
mkdir -p "${backup}"

# Keep the previous release so a failed health check can be reverted.
if [ -d "${APP_DIR}/site" ]; then
    cp -a "${APP_DIR}/site" "${backup}/site"
fi
if [ -d "${APP_DIR}/backend" ]; then
    cp -a "${APP_DIR}/backend" "${backup}/backend"
fi

mkdir -p "${APP_DIR}/backend/data" "${APP_DIR}/nginx/conf.d" \
         "${APP_DIR}/site/app" "${APP_DIR}/site/downloads" "${APP_DIR}/site/media"

# --delete stops files removed upstream from lingering in the release.
rsync -a --delete --exclude '__pycache__' backend/app/ "${APP_DIR}/backend/app/"

# The document root is assembled here: landing page at the top level, the
# Flutter app under app/, release artefacts under downloads/. app/ and
# downloads/ are excluded from the landing sync so they survive it.
rsync -a --delete --exclude 'app/' --exclude 'downloads/' --exclude 'media/' \
    landing/ "${APP_DIR}/site/"
rsync -a --delete build/web/ "${APP_DIR}/site/app/"

# The Flutter web build writes asset filenames percent-encoded on disk, which
# makes them unusable from plain HTML. The landing page therefore reads the
# photo library from media/, synced straight from source with names intact.
rsync -a --delete assets/images/ "${APP_DIR}/site/media/"

# Published only when the Android stage produced one, so an UNSTABLE build
# keeps serving the previous APK instead of a broken link.
if [ -f build/app/outputs/flutter-apk/app-release.apk ]; then
    install -m 0644 build/app/outputs/flutter-apk/app-release.apk \
        "${APP_DIR}/site/downloads/kamer-go.apk"
fi

install -m 0644 backend/requirements.txt "${APP_DIR}/backend/requirements.txt"
install -m 0755 backend/docker-entrypoint.sh "${APP_DIR}/backend/docker-entrypoint.sh"
install -m 0644 backend/data/destinations.json "${APP_DIR}/backend/data/destinations.json"

install -m 0644 deploy/Dockerfile "${APP_DIR}/Dockerfile"
install -m 0644 deploy/docker-compose.yml "${APP_DIR}/docker-compose.yml"
install -m 0644 deploy/nginx/conf.d/globetrotter.conf "${APP_DIR}/nginx/conf.d/globetrotter.conf"
'''
            }
        }

        stage('Deploy and verify') {
            steps {
                sh '''#!/usr/bin/env bash
set -euo pipefail

cd "${APP_DIR}"
docker compose build
docker compose up -d

# Jenkins runs in its own network namespace, so the host loopback that
# publishes ${APP_PORT} is unreachable from here. The container healthcheck
# is authoritative and is readable through the shared Docker socket.
ok=0
for _ in $(seq 1 45); do
    state=$(docker inspect -f '{{.State.Health.Status}}' globetrotter_backend 2>/dev/null || echo unknown)
    if [ "${state}" = "healthy" ]; then
        ok=1
        break
    fi
    sleep 2
done
if [ "${ok}" != "1" ]; then
    echo "ERROR: the backend never became healthy (last state: ${state})." >&2
    docker compose logs --tail 50 backend >&2 || true
    exit 1
fi

# Confirms the public routes are serving, not just the container.
curl -fsS "https://${DOMAIN}/" | grep -qi 'kamer-go'
curl -fsS -o /dev/null "https://${DOMAIN}/app/"
curl -fsS "https://${DOMAIN}/healthz" | grep -q '"status"'
count=$(curl -fsS "https://${DOMAIN}/api/destinations" | grep -o '"id"' | wc -l)
[ "${count}" -gt 0 ] || { echo "ERROR: the destination catalogue came back empty." >&2; exit 1; }
echo "Deployed successfully: ${count} destinations live at https://${DOMAIN}"
'''
            }
        }
    }

    post {
        failure {
            sh '''#!/usr/bin/env bash
set -uo pipefail

backup="${APP_DIR}/.rollback"
[ -d "${backup}" ] || exit 0

echo "Deployment failed; restoring the previous release."
[ -d "${backup}/site" ] && rsync -a --delete "${backup}/site/" "${APP_DIR}/site/"
[ -d "${backup}/backend" ] && rsync -a --delete "${backup}/backend/" "${APP_DIR}/backend/"

cd "${APP_DIR}" && docker compose up -d --build
'''
        }
        success {
            sh 'rm -rf "${APP_DIR}/.rollback"'
        }
        unstable {
            // An unstable run still deployed and verified; only an optional
            // artefact was missing, so the snapshot has served its purpose.
            sh 'rm -rf "${APP_DIR}/.rollback"'
        }
        always {
            // deleteDir is a core step, so the workspace is still cleaned even
            // if the optional ws-cleanup plugin is unavailable. Housekeeping
            // must never decide the outcome of an otherwise good deployment,
            // so a stubborn leftover file is reported rather than thrown.
            catchError(buildResult: 'SUCCESS', stageResult: 'SUCCESS') {
                deleteDir()
            }
        }
    }
}
