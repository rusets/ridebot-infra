provider "aws" {
  region = var.aws_region
  # В GitHub Actions будем использовать OIDC-роль, локально — профиль/переменные окружения
}
