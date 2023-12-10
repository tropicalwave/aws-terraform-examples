locals {
  records_raw = csvdecode(file("${path.module}/records.csv"))
  zones       = toset(distinct(local.records_raw[*].Zone))

  record_groups = tomap({
    for row in local.records_raw :
    "${row.Name} ${row.Zone} ${row.Type}" => row...
  })
  recordsets = tomap({
    for group_key, group in local.record_groups : group_key => {
      name   = group[0].Name
      type   = group[0].Type
      zone   = group[0].Zone
      values = group[*].Value
    }
  })
}

resource "aws_route53_zone" "zone" {
  for_each = local.zones
  name     = each.value
}

resource "aws_route53_record" "records" {
  for_each = local.recordsets

  name    = "${each.value.name}${each.value.name == "" ? "" : "."}${each.value.zone}"
  type    = each.value.type
  zone_id = aws_route53_zone.zone[each.value.zone].zone_id
  ttl     = 3600
  records = each.value.values
}
