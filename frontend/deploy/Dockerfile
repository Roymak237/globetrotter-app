FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY backend/app ./app

# Seed data is kept separate from the runtime data directory, which is a Docker
# volume. The entrypoint decides what to refresh and what to preserve.
COPY backend/data ./seed

COPY backend/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
# Strip carriage returns so the script still runs when edited on Windows.
RUN sed -i 's/\r$//' /usr/local/bin/docker-entrypoint.sh \
    && chmod +x /usr/local/bin/docker-entrypoint.sh

# Run as an unprivileged user that owns the writable data directory.
RUN useradd --create-home --uid 10001 appuser \
    && mkdir -p /app/data \
    && chown -R appuser:appuser /app
USER appuser

EXPOSE 5000

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
# A single gevent worker, deliberately.
#
# Call signalling keeps its connection registry in process memory, so a second
# worker would split it: two people in the same call could land in different
# processes and never find each other. gevent makes one worker enough, since
# thousands of idle websockets cost greenlets rather than threads.
CMD ["gunicorn", \
     "--bind", "0.0.0.0:5000", \
     "--worker-class", "geventwebsocket.gunicorn.workers.GeventWebSocketWorker", \
     "--workers", "1", \
     "--timeout", "120", \
     "--access-logfile", "-", \
     "app.main:app"]