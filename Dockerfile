# Dockerfile for publishing sdk-ios to Nexus SPM
# Unlike npm packages, Swift packages are published as git archives
FROM alpine:latest

WORKDIR /app

# Install required tools
RUN apk add --no-cache git curl bash

# Copy the entire repository
COPY . .

# Build arguments for Nexus credentials
ARG REPOSITORY
ARG USERNAME
ARG PASSWORD
ARG VERSION

# Set as environment variables
ENV NEXUS_URL=$REPOSITORY
ENV NEXUS_USER=$USERNAME
ENV NEXUS_PASS=$PASSWORD
ENV VERSION=$VERSION

# Validate version is provided
RUN if [ -z "$VERSION" ]; then \
        echo "ERROR: VERSION build arg is required"; \
        echo "Usage: docker build --build-arg VERSION=1.0.0 ..."; \
        exit 1; \
    fi

# Extract repository name from NEXUS_URL (e.g., "swift-hosted" from URL)
# Assuming NEXUS_URL is like: https://nexus.example.com/repository/swift-hosted
ENV NEXUS_REPO=swift-hosted

# Initialize git if needed (for git archive)
RUN git config --global --add safe.directory /app || true && \
    if [ ! -d .git ]; then \
        git init && \
        git add -A && \
        git config user.email "ci@example.com" && \
        git config user.name "CI/CD" && \
        git commit -m "Release $VERSION" && \
        git tag -a "$VERSION" -m "Release $VERSION"; \
    fi

# Create archive
RUN ARCHIVE_NAME="RocsSDK-${VERSION}.zip" && \
    git archive --format=zip --prefix="RocsSDK-${VERSION}/" HEAD > "$ARCHIVE_NAME" && \
    echo "Created archive: $ARCHIVE_NAME ($(du -h $ARCHIVE_NAME | cut -f1))"

# Publish to Nexus
RUN ARCHIVE_NAME="RocsSDK-${VERSION}.zip" && \
    UPLOAD_URL="${NEXUS_URL}/RocsSDK/${VERSION}/${ARCHIVE_NAME}" && \
    echo "Publishing to: $UPLOAD_URL" && \
    curl -f -u "${NEXUS_USER}:${NEXUS_PASS}" \
        --upload-file "$ARCHIVE_NAME" \
        "$UPLOAD_URL" && \
    echo "Successfully published RocsSDK $VERSION to Nexus"

# Output success message
RUN echo "✅ RocsSDK ${VERSION} published successfully"
