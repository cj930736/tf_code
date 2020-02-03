whitelist = {
  for_http = ["0.0.0.0/0"]
  for_ssh   = ["0.0.0.0/0"]
}

availability_zones = [ 
  "us-east-2a",
  "us-east-2b",
  "us-east-2c"
]

min_web_instances    = 3
max_web_instances    = 6
