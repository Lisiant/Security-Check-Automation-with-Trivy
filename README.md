# 🖼️ Trivy를 통한 컨테이너 이미지 보안 스캔 및 CI/CD 보안 검사 자동화 적용

## 🔧 개요

![image](https://github.com/user-attachments/assets/3f42972a-a77c-45f5-bb47-ac85a188acd8)

**Trivy**는 오픈소스 보안 스캐너로, 컨테이너 이미지, 파일 시스템, 소스 코드, 인프라 구성 요소에서 취약점과 구성 오류를 탐지합니다. Docker와과 같은 컨테이너 이미지 스캔을 지원하며, IaC 도구인 Terraform, AWS CloudFormation 등에서 보안 취약점을 감지할 수 있습니다. 

Trivy는 DevSecOps 파이프라인에 통합되어 코드 배포 전에 자동으로 보안 검사를 수행해 보안 문제를 조기에 발견하고, 이를 통해 운영 비용 절감과 신뢰할 수 있는 클라우드 환경 구축을 돕습니다.

본 문서에서는 Trivy를 통해 **취약점이 존재하는 Docker Image를 분석**하고, **GitHub Actions를 통한 자동화된 워크플로우를 구축**하는 내용을 다루고 있습니다.

## 1️⃣ Docker Image 분석

### 구성 환경

- Apple Silicon M2
- Docker
- Spring Boot 3.3.4
- JDK17

### 🐜 Spring Boot Demo 프로젝트 생성

취약점이 존재하는 간단한 Spring Boot 프로젝트를 생성하였습니다.

**build.gradle**

```gradle
plugins {
	id 'java'
	id 'org.springframework.boot' version '3.3.4'
	id 'io.spring.dependency-management' version '1.1.6'
}

group = 'com.example'
version = '0.0.1-SNAPSHOT'

java {
	toolchain {
		languageVersion = JavaLanguageVersion.of(17)
	}
}

repositories {
	mavenCentral()
}

dependencies {
	// 취약점 없는 라이브러리 생략

	// Apache Commons Compress의 취약한 버전
	implementation 'org.apache.commons:commons-compress:1.18'

}

tasks.named('test') {
	useJUnitPlatform()
}
tasks.named('bootJar') {
	mainClass.set('com.example.trivydemo.TrivydemoApplication')
}
```

📝 **취약점 목록**

<img width="1028" alt="temp1" src="https://github.com/user-attachments/assets/33421f54-e2c0-4ac2-b585-8d40a8fbf2c2">

- `CVE-2019-12402`
- `CVE-2021-36090`
- `CVE-2021-35515`
- `CVE-2021-35516`
- `CVE-2021-35517`
- `CVE-2024-25710`

### ✏️ Dockerfile 작성

Trivy는 Docker 기반 image를 분석하는 도구이기 때문에 해당 프로젝트를 docker image로 생성하여 분석하고자 dockerfile을 생성하였습니다.

**Dockerfile**

```bash
FROM gradle:8.1.0-jdk8 AS build
WORKDIR /app

COPY build.gradle settings.gradle ./
RUN gradle build --no-daemon

COPY src ./src
RUN gradle bootJar --no-daemon

FROM openjdk:17-jdk-slim
WORKDIR /app

COPY --from=build /app/build/libs/*.jar app.jar

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```

`trivydemo` 라는 이름으로 Docker image를 생성하였습니다.

```bash
> docker build -t trivydemo .

> docker images
REPOSITORY      TAG       IMAGE ID       CREATED          SIZE
trivydemo       latest    3e5a7bf8f626   23 seconds ago   425MB
```

### 💿 Trivy 설치

Docker 환경 위에 trivy를 설치하고, 이미지를 분석하였습니다.

```bash
> sudo docker run --name trivydemo -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy image trivydemo
```
<img width="1216" alt="temp2" src="https://github.com/user-attachments/assets/565a2070-84a9-466f-82e3-78f5ee10b7af">


앞서 미리 파악한 보안 취약점이 존재하는 라이브러리를 찾아내고, 안전한 버전을 추천하는 것을 확인할 수 있습니다.

## 2️⃣ Github Actions로 분석 자동화

⭐ **개요**

GitHub Actions을 통해 Docker 이미지를 빌드하고, Trivy를 사용해 보안 스캔을 진행하는 자동화된 워크플로우를 구축하였습니다.

### 1. GitHub Repository 생성 및 Spring Boot 프로젝트 업로드

GitHub Repository에 앞서 제작한 demo 프로젝트를 push하였습니다.

### 2. GitHub Actions 워크플로우 설정

1. `.github/workflows/docker-trivy-config.yml` 파일 생성
    
    GitHub Actions를 사용하기 위해 yml 파일을 통해 워크플로우를 생성하였습니다.
    
    ```yaml
    name: Trivy demo with Spring Boot Application
    
    on:
      push:
        branches:
          - main
      pull_request:
        branches:
          - main
    
    jobs:
      build:
        runs-on: ubuntu-latest
    
        steps:
        - name: Checkout code
          uses: actions/checkout@v3
    
        - name: Set up Docker Buildx
          uses: docker/setup-buildx-action@v2
    
        - name: Login to DockerHub
          uses: docker/login-action@v2
          with:
            username: ${{ secrets.DOCKER_USERNAME }}
            password: ${{ secrets.DOCKER_PASSWORD }}
    
        - name: Build Docker image
          run: docker build -t trivydemo .
    
        - name: Trivy scan
          uses: aquasecurity/trivy-action@master
          with:
            image-ref: trivydemo:latest
            format: 'table'
            exit-code: '0'
            ignore-unfixed: true
            output: 'trivy-output.txt'
    
        - name: Upload scan result
          uses: actions/upload-artifact@v4
          with:
            name: trivy-scan-result
            path: trivy-output.txt
    ```
    
**주요 섹션 설명**
    
- Event trigger `on` : main branch에 `push`와 `pull request` 이벤트가 발생할 때 워크플로우가 실행되도록 지정했습니다.
- `jobs` 섹션 : GitHub Actions에서 실행할 작업들을 정의합니다. `build` 라는 작업을 정의했고, `runs-on: ubuntu-latest` 를 통해 Ubuntu 환경에서 실행하였습니다.
- `steps` 섹션: 각 단계를 지정하였습니다.

  1. `Checkout` : GitHub repo에서 코드를 체크아웃 합니다. 즉, 최신 버전의 코드를 가져와서 사용할 수 있도록 워크플로우 환경에 다운로드합니다.
  2. `Docker Buildx` : 여러 아키텍처에 대해 이미지를 빌드할 수 있도록 Docker Buildx를 설정합니다. 
  3. `DockerHub` 로그인: `secrets.DOCKER_USERNAME`과 `secrets.DOCKER_PASSWORD`를 사용하여 DockerHub에 로그인합니다. secret 설정은 아래에 설명하겠습니다.
  4. Docker 이미지 빌드: `docker build` 명령어를 통해 이미지를 build합니다.
  5. `Trivy scan` : Trivy를 통해 Docker 이미지를 스캔하고, 결과를 `trivy-output.txt` 파일로 저장합니다.
  6. 스캔 결과 업로드: Trivy 스캔 결과를 GitHub에 Artifact에 업로드합니다.

### 3. Secrets 추가

Repository로 이동하여 `Settings > Security > Secrets and Variables`탭에서 `Actions` 탭을 클릭합니다.
![temp10](https://github.com/user-attachments/assets/00afe954-339c-459a-ba95-531386b3d12e)

`New repository secret` 을 클릭하여 본인의 DockerHub username과 password를 입력합니다.

- 제목의 경우 yml 파일에서 설정했던 것과 같은 형식으로 설정합니다.
- 보안을 위해 DockerHub에 로그인 시 Access Token으로 설정하는 것을 추천합니다.

![temp3](https://github.com/user-attachments/assets/0cddac74-aeb6-48fa-867f-83d9bb94a4b2)

### 4. 코드 Push 및 워크플로우 실행

Repository의 main 브랜치에 코드를 푸시하거나 Pull Request를 생성하면 GitHub Actions 워크플로우가 자동으로 실행합니다. 이 워크플로우는 Docker 이미지 빌드, Trivy 보안 스캔, 스캔 결과 업로드의 과정을 자동으로 처리합니다.

스캔 결과는 Repository의 Actions의 Workflows 항목을 클릭하여 하단의 Artifacts에서 확인할 수 있습니다.

![temp11](https://github.com/user-attachments/assets/a8091350-8d94-4a8f-b249-38ddc442927f)

### **🔍 취약점 추가 테스트 및 결과**

이전 Spring Boot Application에서는  `'org.apache.commons:commons-compress:1.18'` 라이브러리에서만 취약점이 존재했습니다.

해당 프로젝트의 `build.gradle`에 다른 취약점이 존재하는 라이브러리를 추가하여 CI/CD 과정에서 Trivy를 통한 보안 스캔 워크플로우가 정상적으로 작동하는지 확인해보도록 하겠습니다.

**이전 버전의 trivy scan 결과**

<img width="1218" alt="temp4" src="https://github.com/user-attachments/assets/50308546-a9ec-4ec2-816f-f0918b750639">

**build.gradle에 취약점 라이브러리 추가**

```gradle
dependencies {
	// 취약점 존재하지 않는 다른 라이브러리 생략
	
	// Apache Commons Compress의 취약한 버전
	implementation 'org.apache.commons:commons-compress:1.18'
	
	// CVE-2023-33202
	implementation 'org.bouncycastle:bcprov-jdk15on:1.64'
}
```

- 취약점이 존재하는 Bouncy Castle 라이브러리를 추가하였습니다.
    - **버전**: `bcprov-jdk15on:1.64`
    - **취약점:** `CVE-2023-33202`

**Main branch에 push**

![temp7](https://github.com/user-attachments/assets/4c69e67d-e7a0-4a70-a8a3-66ff07893335)

main branch에 push가 이루어진 경우 워크플로우가 정상적으로 동작하는 것을 확인할 수 있었습니다.

**Trivy 분석 확인**

Artifacts 탭에서 결과를 다운받아 확인하였습니다.

<img width="1224" alt="1111" src="https://github.com/user-attachments/assets/ee6f8862-cafd-49ec-9063-112084ae94db">

추가한 라이브러리에 존재하는 취약점을 찾아낸 것을 확인할 수 있었습니다.

## 🏁 결론 및 회고

Trivy를 활용해 Docker 이미지를 스캔하고, GitHub Actions를 통해 이를 자동화하여 CI/CD 파이프라인에서 보안 검사를 자동화하는 과정을 성공적으로 진행했습니다. 

이 과정을 통해 Docker 이미지 분석과 GitHub Actions를 통한 CI/CD 파이프라인 구축에 대한 이해를 높였습니다.

DevSecOps의 일환으로 코드 배포 전에 자동으로 보안 취약점을 파악하여, 보안 문제를 조기에 발견하는 방법을 익힐 수 있었습니다.

## **🗒️ 참고자료**

https://faun.pub/how-to-scan-docker-images-e08a7b909ea0

https://betterprogramming.pub/static-analysis-of-container-images-with-trivy-8d297c4f1dd3

[https://velog.io/@nigasa12/Github-Actions와-Trivy를-이용한-Docker-Image-Build-시-취약점-검사](https://velog.io/@nigasa12/Github-Actions%EC%99%80-Trivy%EB%A5%BC-%EC%9D%B4%EC%9A%A9%ED%95%9C-Docker-Image-Build-%EC%8B%9C-%EC%B7%A8%EC%95%BD%EC%A0%90-%EA%B2%80%EC%82%AC)

[https://beann.tistory.com/entry/trivy를-활용한-Container-Image-취약점-스캔하기](https://beann.tistory.com/entry/%08trivy%EB%A5%BC-%ED%99%9C%EC%9A%A9%ED%95%9C-Container-Image-%EC%B7%A8%EC%95%BD%EC%A0%90-%EC%8A%A4%EC%BA%94%ED%95%98%EA%B8%B0)
