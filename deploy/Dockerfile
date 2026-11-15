FROM node:22-bookworm-slim AS web-build
WORKDIR /app/web
COPY web/package*.json ./
RUN npm ci
COPY web/ ./
RUN npm run build

FROM node:22-bookworm-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-venv ca-certificates && rm -rf /var/lib/apt/lists/* \
    && python3 -m venv /opt/orbitcare-python
COPY deploy/requirements.txt /app/deploy/requirements.txt
RUN /opt/orbitcare-python/bin/pip install --no-cache-dir -r /app/deploy/requirements.txt
COPY backend/package*.json /app/backend/
RUN cd /app/backend && npm ci --omit=dev
COPY backend/ /app/backend/
COPY AI_training/ai_service.py AI_training/nasa_claude.py AI_training/thresholds.json /app/AI_training/
COPY AI_training/csm/ /app/AI_training/csm/
COPY --from=web-build /app/web/dist /app/web/dist
COPY deploy/start.sh /app/deploy/start.sh
ENV NODE_ENV=production WEB_DIST_DIR=/app/web/dist CSM_AI_SERVICE_URL=http://127.0.0.1:8000 PYTHONUNBUFFERED=1
CMD ["bash", "/app/deploy/start.sh"]
