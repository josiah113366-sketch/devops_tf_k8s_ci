# 목표
- CI Workflow 구성
  ```
    # 소스 변경 => push => GitHub Actions => 이미지 생성 => 임시인증(OIDC) => ECR 업데이트 : devops관련
    # 최초 1회 인프라 구성(테라폼) => 변경시 반영됨
    devops_tf_k8s_ci -> GitHub Actions -> AWS ECR 
  ```
- 지금까지 구성한 인프라(aws 기반 테라폼구성)와 플랫폼/서비스(쿠버네티스) 위에 Devops 올려서 형태 최종 완성

- 세부적인 workflow
```
        개발자 Push/PR
            │
            ▼
        GitHub Actions
            │
            ├─ Terraform fmt / validate / apply  # 인프라 구성/변경사항 반영

            ├─ WEB Docker 이미지 빌드              # web, was 이미지 생성 병렬 구성
            ├─ WEB /health 테스트
            ├─ WAS Python 문법 검사
            ├─ WAS Docker 이미지 빌드
            ├─ WAS /health 테스트
            
            ├─ GitHub OIDC로 AWS 임시 인증         # pem 사용 x, OIDC 임시 인증서로 발급받아서 로그인
            
            ├─ WEB 이미지 ECR Push                # 이미지 푸시 -> 태그 수정(해시값,commit id등) -> CD 작동의 근거가됨
            ├─ WAS 이미지 ECR Push
            └─ ECR 이미지 등록 확인
```
- devops_tf_k8s_ci 는 CI/CD 구성에서 `CI 영역만 담당하는 소스 저장소(source repository)` 임

# 프로젝트 구조
```text
        devops-tf-k8s-ci/
        ├─ setup-ci.bat             # 신규 1회 수행 : Windows CI 전체 최초 설정
        ├─ setup-ci.sh              # 신규 1회 수행 : macOS/Linux/WSL CI 전체 최초 설정
        ├─ validate-ci.bat          # 신규 수시 수행 : Windows 로컬 CI 재검증 
        ├─ validate-ci.sh           # 신규 수시 수행 : macOS/Linux/WSL 로컬 CI 재검증
        ├─ project.bat              # 신규 인프라 구성시/변경되면 수행 : Windows 전체 명령 진입점
        ├─ project.sh               # 신규 인프라 구성시/변경되면 수행 : macOS/Linux/WSL 전체 명령 진입점
        ├─ .github/                 # 신규
        │  ├─ workflows/ci.yml      # 신규 GitHub Actions CI Workflow
        │  └─ dependabot.yml        # 신규 GitHub Actions 버전 점검
        ├─ apps/
        │  ├─ web/                  # Nginx 소스와 Dockerfile
        │  └─ was/                  # FastAPI 소스와 Dockerfile
        ├─ infra/
        │  ├─ github-actions-ci.tf  # 신규 GitHub OIDC, CI IAM Role, ECR Push 정책
        │  ├─ variables.tf          # 수정 CI 입력변수 추가 (OIDC, Git Action, Github 관련)
        │  ├─ outputs.tf            # GitHub Actions Role ARN 출력 추가
        │  └─ ...                   # 기존 인프라 구성 파일 동일
        ├─ scripts/
        │  ├─ ci/
        │  │  ├─ verify_ci_config.py # CI 파일과 terraform.tfvars 사전 검사
        │  │  ├─ linux/             # macOS/Linux/WSL CI 실행 로직
        │  │  └─ windows/           # Windows CMD CI 실행 로직
        │  ├─ deploy/               # 최초 수동 배포가 필요할 때 사용하는 로직
        │  ├─ ops/                  # 상태 확인과 전체 삭제
        │  └─ setup/                # 실습 환경 설치
        ├─ tools/
        └─ docs/
```

- 전체 저장소 배치
  ```
    devops_tf_k8s/
    L devops_tf_k8s_ci
    L devops_tf_k8s_cd
  ```


# 세팅
## OIDC 처리 (AWS 인증 방식 변경)
- 절차
  - 기존 : pem(엑세스키)
  - 변경 : `OIDC`
    - OIDC(OpenID Connect)는 ⁠OAuth 2.0 프로토콜을 바탕으로 만든 신원 인증 표준
    - 절차 : Git Action에서 ECR에 Push할때 단기 AWS 자격인증 발급받아서 로그인 수행 -> 보안 이슈
    - IAM 계정별 엑세스키(개발 PC는 사용), PEM 파일 (git 사용 x)

- workflow
```
    GitHub Actions
          │
          │ OIDC Token 발급
          ▼
    GitHub OIDC Provider
          │
          │ sts:AssumeRoleWithWebIdentity
          ▼
    GitHub Actions CI IAM Role
          │
          │ ECR Push 권한
          ▼
    WEB ECR / WAS ECR
```

- 수정 및 추가작업
  - infra/ 내 수정및 추가작업
    - terraform.tfvars
  - git 관련 id 조회
    ```
      # github_owner_id, github_ci_repository_id 값 획득
      # gh 명령어 사용
      # 설치
        # 윈도우        
          winget install --id GitHub.cli
        # 맥        
          brew install gh

      # 공통
        # 로그인
        gh auth login
        ---
        GitHub.com
        HTTPS
        Login with a web browser
        Press Enter to open https://github.com/login/device in your browser
        로그인 수행 > continue > 발급퇸 키 8자리 붙여넣기 > continue
        `Au... github` 버튼 클릭 > 설정완료

      # ID 조회
      gh api repos/ucoccto/devops_tf_k8s_ci --jq "{owner_id: .owner.id, repository_id: .id, created_at: .created_at}"
      ---
      {
        "created_at": "2026-08-05T23:51:38Z",
        "owner_id": 173376075,
        "repository_id": 1324570033
      }
    ```

## 전체 인프라 구성 및 최초 web/was 이미지 빌드 -> ECR Push : ci worlflow 진행
- 최초 (인프라구성) / 수정된 인프라 배포
```
./project.sh deploy
./project.bat deploy
```