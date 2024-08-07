output "access_url" {
  value = "http://${aws_lb.my_alb.dns_name}/${aws_api_gateway_deployment.private_api.stage_name}/${aws_api_gateway_resource.proxy.path_part} -H 'Host:${aws_api_gateway_rest_api.private_api.id}.execute-api.${var.region}.amazonaws.com'"
}
