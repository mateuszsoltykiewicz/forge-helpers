FROM python:3.11-alpine

# Set working directory
WORKDIR /app

# Copy requirements first for better layer caching
COPY requirements.txt .

# Install dependencies in single RUN layer to minimize image size
# Build deps are added, used for pip install, then removed in same layer
RUN apk add --no-cache --virtual .build-deps \
    gcc \
    musl-dev \
    libffi-dev \
    openssl-dev \
    cargo \
    && apk add --no-cache \
    libffi \
    openssl \
    && pip install --no-cache-dir -r requirements.txt \
    && apk del .build-deps

# Copy application code
COPY src/ ./src/

# Run as non-root user
RUN adduser -D -u 1000 chainer && \
    chown -R chainer:chainer /app
USER chainer

ENTRYPOINT ["python", "-u", "src/chainer.py"]
