# 목표
- CI Workflow 구성
  ```
    # 소스 변경 => push => GitHub Actions => 이미지 생성 => 임시인증(OIDC) => ECR 업데이트 : devops 관련 
    # 최초 1회 인프라 구성(테라폼) => 변경시 반영됨
    devops_tf_k8s_ci -> GitHub Actions -> AWS ECR 
  ```
- 지금까지 구성한 인프라(aws 기반 테라폼 구성)와 플랫폼/서비스(쿠버네티스) 위에 DevOps 올려서 최종 형태 완성

- 세부적인 workflow
```
        개발자 Push
            │
            ▼
        GitHub Actions
            │
            ├─ Terraform fmt / validate / apply   # 인프라 구성/변경 사항 반영
            ├─ WEB Docker 이미지 빌드               # web, was 이미지 생성 병렬 구성 
            ├─ WEB /health 테스트
            ├─ WAS Python 문법 검사
            ├─ WAS Docker 이미지 빌드
            ├─ WAS /health 테스트
            ├─ GitHub OIDC로 AWS 임시 인증          # pem 사용, OIDC 임시 인증서로 발급받아서 로그인
            ├─ WEB 이미지 ECR Push                 # 이미지 푸시 -> 태그 수정(해시값, commit id 등) -> CD 작동의 근거가 됨 
            ├─ WAS 이미지 ECR Push
            └─ ECR 이미지 등록 확인
```

- devops_tf_k8s_ci는 CI/CD 구성에서 `CI 영역만 담당하는 소스 저장소(source repository)`임