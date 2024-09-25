FROM gradle:8.1.0-jdk17 AS build
WORKDIR /app

COPY build.gradle settings.gradle ./
RUN gradle build --no-daemon

COPY src ./src
RUN gradle bootJar --no-daemon

FROM openjdk:17-jdk-alpine
WORKDIR /app

COPY --from=build /app/build/libs/*.jar app.jar

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
