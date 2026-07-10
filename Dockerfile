# Stage 1: Build the backend with Gradle
FROM eclipse-temurin:21 AS backend-builder
WORKDIR /build
COPY code/gradlew ./gradlew
COPY code/gradle ./gradle
COPY code/build.gradle code/settings.gradle ./
COPY code/src ./src
RUN chmod +x gradlew && ./gradlew assemble --no-daemon

# Stage 2: Build the web app with Node.js
FROM node:22-alpine AS frontend-builder
WORKDIR /web
COPY code/traccar-web/package.json code/traccar-web/package-lock.json ./
RUN npm ci --legacy-peer-deps
COPY code/traccar-web/ ./
RUN npm run build

# Stage 3: Create minimal JRE
FROM eclipse-temurin:21-alpine AS jdk
RUN jlink --module-path $JAVA_HOME/jmods \
    --add-modules java.se,jdk.charsets,jdk.crypto.ec,jdk.unsupported \
    --strip-debug --no-header-files --no-man-pages --compress=2 --output /jre

# Stage 4: Final runtime image
FROM alpine:3.22

# Create required directories
RUN mkdir -p /opt/traccar/conf /opt/traccar/data /opt/traccar/logs /opt/traccar/web

# Copy JRE
COPY --from=jdk /jre /opt/traccar/jre

# Copy backend artifacts
COPY --from=backend-builder /build/target/tracker-server.jar /opt/traccar/tracker-server.jar
COPY --from=backend-builder /build/target/lib /opt/traccar/lib

# Copy frontend build
COPY --from=frontend-builder /web/build /opt/traccar/web

# Copy templates and schema
COPY code/templates /opt/traccar/templates
COPY code/schema /opt/traccar/schema

# Copy default configuration (can be overridden by volume mount)
COPY code/setup/traccar.xml /opt/traccar/conf/traccar.xml

WORKDIR /opt/traccar
EXPOSE 8082 5000-5150 5000-5150/udp

ENTRYPOINT ["/opt/traccar/jre/bin/java"]
CMD ["-jar", "tracker-server.jar", "conf/traccar.xml"]
