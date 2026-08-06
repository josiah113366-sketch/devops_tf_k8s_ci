# ─────────────────────────────────────────────
# Github Action이 장기키(pem, access key)없이 임시 자격 증명(OIDC)을 이용 인증 역활,권한등 처리
# 발급받아서 WEB/WAS 이미지를 ECR에 PUSH 목적 -> 보안 관리 이슈 x (깃상에 변수등이라도 존재 x)
# 
# 누가 발급한 인증 토큰을 신뢰할것인가?(발급 기관), Github에서 어떤 실행를 할때 인증 허가할것인가?
# 이 2개의 대한 내용을 role에 반영하여 arn 구성
# ─────────────────────────────────────────────

# 현재 어떤 사용자(IAM)/역활등이 실행중이지 => data => 조회후 채움
data "aws_caller_identity" "current" {}
# AWS 영역 구분값 조회
data "aws_partition" "current" {}

locals {
  # 위의 값을 조회하여 oidc를 발급하는 공급자의 arn 생성
  github_actions_oidc_provider_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"

  # IAM Role에서 사용가능한 Github 저장소, 브런치 지정 (소유자, 저장소, 브런치)
  # 2026년 7월 이후 변경된 주소 체계때문에 이전과 같이 배치 -> 보안강화됨
  #github_actions_ci_subject = "repo:${var.github_owner}/${var.github_ci_repository}:ref:refs/heads/${var.github_ci_branch}"
  github_actions_ci_subject = "repo:${var.github_owner}@${var.github_owner_id}/${var.github_ci_repository}@${var.github_ci_repository_id}:ref:refs/heads/${var.github_ci_branch}"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  count = var.enable_github_actions_ci && var.create_github_oidc_provider ? 1 : 0

  url = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  tags = {
    Name = "github-actions-oidc"
  }
}

data "aws_iam_policy_document" "github_actions_ci_assume" {
  count = var.enable_github_actions_ci ? 1 : 0

  statement {
    sid = "GitHubActionsAssumeRole"
    effect = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type = "Federated"
      identifiers = [local.github_actions_oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [local.github_actions_ci_subject]
    }
  }
}


resource "aws_iam_role" "github_actions_ci" {
  count = var.enable_github_actions_ci ? 1 : 0

  name = "${local.cluster_name}-github-actions-ci-role"
  description = "GitHub Actions CI role for ECR image push"
  assume_role_policy = data.aws_iam_policy_document.github_actions_ci_assume[0].json
  max_session_duration = 3600
  depends_on = [aws_iam_openid_connect_provider.github_actions]
}

data "aws_iam_policy_document" "github_actions_ci" {
  count = var.enable_github_actions_ci ? 1 : 0

  statement {
    sid    = "ECRLogin"
    effect = "Allow"
    actions = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "PushApplicationImages"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart"
    ]
    resources = [
      aws_ecr_repository.web.arn,
      aws_ecr_repository.was.arn
    ]
  }
}

resource "aws_iam_role_policy" "github_actions_ci" {
  count = var.enable_github_actions_ci ? 1 : 0
  name = "${local.cluster_name}-ecr-push-policy"
  role = aws_iam_role.github_actions_ci[0].id
  policy = data.aws_iam_policy_document.github_actions_ci[0].json
}
