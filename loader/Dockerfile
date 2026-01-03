FROM alpine:3.20

# Install required packages as root
RUN apk add --no-cache \
    bash \
    curl \
    unzip \
    postgresql-client \
    ca-certificates \
    coreutils

# Create group and user
RUN addgroup -S geonames \
 && adduser  -S -G geonames geonames

# Application directory
WORKDIR /app

# Copy files
COPY create_table.sql /app/create_table.sql
COPY load_geonames.sh /app/load_geonames.sh

# Fix ownership and permissions
RUN chown -R geonames:geonames /app \
 && chmod +x /app/load_geonames.sh

# Switch to non-root user
USER geonames

ENTRYPOINT ["/app/load_geonames.sh"]