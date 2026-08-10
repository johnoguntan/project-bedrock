# =============================================================================
# TLS certificate for the ALB — Bonus 5.2.
#
# The exam brief allows "a custom domain or magic DNS like nip.io if you do
# not own a domain." nip.io works for routing (it resolves *.<ip>.nip.io to
# <ip> with no DNS records to manage), but you can't get ACM to
# DNS-validate a certificate for a domain you don't control in Route 53 —
# nip.io isn't yours. So instead of a DNS-validated cert (which would
# require owning a real domain), this generates a self-signed certificate
# and imports it into ACM as an IMPORTED certificate. That's still "a
# certificate from ACM" terminating TLS at the ALB, which is what the
# brief asks for — it just won't be trusted by browsers without manually
# accepting the warning, since there's no real CA behind it.
#
# If you own a real domain: skip this file, create a Route 53 hosted zone
# + `aws_acm_certificate` with `validation_method = "DNS"` +
# `aws_route53_record` for validation instead, and pass its ARN into the
# helm_release below.
# =============================================================================

resource "tls_private_key" "ui" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "ui" {
  private_key_pem = tls_private_key.ui.private_key_pem

  subject {
    common_name  = var.tls_dns_name
    organization = "InnovateMart Project Bedrock (self-signed, exam use only)"
  }

  dns_names = [var.tls_dns_name]

  validity_period_hours = 24 * 90 # 90 days — reissue if the exam runs longer

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "ui" {
  private_key      = tls_private_key.ui.private_key_pem
  certificate_body = tls_self_signed_cert.ui.cert_pem

  lifecycle {
    create_before_destroy = true
  }
}
