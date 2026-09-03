data "aws_partition" "current" {}

resource "aws_iam_role" "instance" {
  name_prefix = "${var.name}-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Session Manager is the only access path: it gives shell access without SSH or
# any inbound TCP, and scripts/fetch-clients.sh uses it to read the generated
# client configs off the instance. Nothing else is needed - the instance never
# calls AWS APIs itself.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name_prefix = "${var.name}-"
  role        = aws_iam_role.instance.name
}
