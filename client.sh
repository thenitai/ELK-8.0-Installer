#!/bin/bash
# Ensure the script is run as sudo
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit
fi

# Request for user input in bash script for password and save to PASSWORD variable
read -p "Please enter your elasticsearch password: " PASSWORD

# Encode the elastic user credentials
AUTHORIZATION=$(echo -n "elastic:$PASSWORD" | base64)
echo -n "elastic:$PASSWORD"
echo
echo "$AUTHORIZATION"

read -p "Please enter your elasticsearch server IP: " IP

# Function to wait for the dpkg lock
wait_for_dpkg_lock() {
  while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    echo "Waiting for other package manager to finish..."
    sleep 10
  done
}

# Stop unattended-upgrades service to prevent automatic updates
stop_unattended_upgrades() {
  sudo systemctl stop unattended-upgrades
  sudo systemctl disable unattended-upgrades
}

# Start unattended-upgrades service after script completion
start_unattended_upgrades() {
  sudo systemctl enable unattended-upgrades
  sudo systemctl start unattended-upgrades
}

stop_unattended_upgrades

wait_for_dpkg_lock
sudo apt update
wait_for_dpkg_lock
sudo apt install -y curl auditd jq

# Create Client policy using the provided curl command
curl --location 'http://'$IP'/api/fleet/agent_policies?sys_monitoring=true' \
  --header 'Accept: */*' \
  --header 'Authorization: Basic '$AUTHORIZATION'' \
  --header 'Content-Type: application/json' \
  --header 'Cache-Control: no-cache' \
  --header 'kbn-xsrf: xxx' \
  --header 'Connection: keep-alive' \
  --data '{"id":"agent-policy","name":"Client Policy","description":"Client policy generated by Kibana","namespace":"default","monitoring_enabled":["logs","metrics"]}'

sleep 40

# Get the Enrollment Token from the client policy
ENROLLMENT_TOKEN=$(curl --request GET \
  --url 'http://'$IP'/api/fleet/enrollment_api_keys' \
  --header 'Authorization: Basic '$AUTHORIZATION'' \
  --header 'Content-Type: application/json' \
  --header 'kbn-xsrf: xx' | jq -r '.list[] | select(.policy_id == "agent-policy") | .api_key')

cd /tmp
curl -L -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-8.14.3-linux-x86_64.tar.gz
tar xzvf elastic-agent-8.14.3-linux-x86_64.tar.gz
cd elastic-agent-8.14.3-linux-x86_64
sudo yes | sudo ./elastic-agent install --url=https://$IP:8220 --enrollment-token=$ENROLLMENT_TOKEN --insecure

sleep 5

# Installing the Auditd Log integration onto the fleet policy
curl --location 'http://'$IP'/api/fleet/package_policies' \
  --header 'Accept: */*' \
  --header 'Authorization: Basic '$AUTHORIZATION'' \
  --header 'Content-Type: application/json' \
  --header 'Cache-Control: no-cache' \
  --header 'kbn-xsrf: xxx' \
  --header 'Connection: keep-alive' \
  --data-raw '{
        "name":"auditd-1",
        "description":"",
        "namespace":"",
        "policy_id":"agent-policy",
        "enabled":true,
        "inputs":[
            {
                "type":"logfile",
                "policy_template":"auditd",
                "enabled":true,
                "streams":[
                    {
                        "enabled":true,
                        "data_stream":{
                            "type":"logs",
                            "dataset":"auditd.log"
                        },
                        "vars":{
                            "paths":{
                                "value":["/var/log/audit/audit.log*"],
                                "type":"text"
                            },
                            "tags":{
                                "value":["auditd-log"],
                                "type":"text"
                            },
                            "preserve_original_event":{
                                "value":false,
                                "type":"bool"
                            },
                            "processors":{
                                "type":"yaml"
                            }
                        }
                    }
                ]
            }
        ],
        "package":{
            "name":"auditd",
            "title":"Auditd Logs",
            "version":"3.19.2"
        },
        "force":false
    }'

echo
sleep 5

# Installing the Network Package Capture integration onto the fleet policy
curl --location 'http://'$IP'/api/fleet/package_policies' \
  --header 'Accept: */*' \
  --header 'Authorization: Basic '$AUTHORIZATION'' \
  --header 'Content-Type: application/json' \
  --header 'Cache-Control: no-cache' \
  --header 'kbn-xsrf: xxx' \
  --header 'Connection: keep-alive' \
  --data-raw '{
  "name": "network_traffic-1",
  "description": "",
  "namespace": "",
  "policy_id": "agent-policy",
  "enabled": true,
  "inputs": [
    {
      "type": "packet",
      "policy_template": "network",
      "enabled": true,
      "streams": [
        {
          "enabled": false,
          "data_stream": {
            "type": "logs",
            "dataset": "network_traffic.amqp"
          },
          "vars": {
            "port": {
              "value": [
                5672
              ],
              "type": "text"
            },
            "geoip_enrich": {
              "value": true,
              "type": "bool"
            },
            "monitor_processes": {
              "type": "bool"
            },
            "max_body_length": {
              "type": "integer"
            },
            "parse_headers": {
              "type": "bool"
            },
            "parse_arguments": {
              "type": "bool"
            },
            "hide_connection_information": {
              "type": "bool"
            },
            "send_request": {
              "type": "bool"
            },
            "send_response": {
              "type": "bool"
            },
            "keep_null": {
              "type": "bool"
            },
            "transaction_timeout": {
              "type": "text"
            },
            "processors": {
              "type": "yaml"
            },
            "tags": {
              "value": [],
              "type": "text"
            },
            "map_to_ecs": {
              "type": "bool"
            }
          }
        },
        {
          "enabled": false,
          "data_stream": {
            "type": "logs",
            "dataset": "network_traffic.cassandra"
          },
          "vars": {
            "port": {
              "value": [
                9042
              ],
              "type": "text"
            },
            "geoip_enrich": {
              "value": true,
              "type": "bool"
            },
            "monitor_processes": {
              "type": "bool"
            },
            "send_request": {
              "type": "bool"
            },
            "send_request_header": {
              "type": "bool"
            },
            "send_response": {
              "type": "bool"
            },
            "send_response_header": {
              "type": "bool"
            },
            "keep_null": {
              "type": "bool"
            },
            "compressor": {
              "type": "text"
            },
            "ignored_ops": {
              "value": [],
              "type": "text"
            },
            "processors": {
              "type": "yaml"
            },
            "tags": {
              "value": [],
              "type": "text"
            },
            "map_to_ecs": {
              "type": "bool"
            }
          }
        },
        {
          "enabled": true,
          "data_stream": {
            "type": "logs",
            "dataset": "network_traffic.dhcpv4"
          },
          "vars": {
            "port": {
              "value": [
                67,
                68
              ],
              "type": "text"
            },
            "geoip_enrich": {
              "value": true,
              "type": "bool"
            },
            "monitor_processes": {
              "type": "bool"
            },
            "keep_null": {
              "type": "bool"
            },
            "processors": {
              "type": "yaml"
            },
            "tags": {
              "value": [],
              "type": "text"
            },
            "map_to_ecs": {
              "type": "bool"
            }
          }
        },
        {
          "enabled": true,
          "data_stream": {
            "type": "logs",
            "dataset": "network_traffic.dns"
          },
          "vars": {
            "port": {
              "value": [
                53
              ],
              "type": "text"
            },
            "geoip_enrich": {
              "value": true,
              "type": "bool"
            },
            "monitor_processes": {
              "type": "bool"
            },
            "include_authorities": {
              "type": "bool"
            },
            "include_additionals": {
              "type": "bool"
            },
            "send_request": {
              "type": "bool"
            },
            "send_response": {
              "type": "bool"
            },
            "keep_null": {
              "type": "bool"
            },
            "transaction_timeout": {
              "type": "text"
            },
            "processors": {
              "type": "yaml"
            },
            "tags": {
              "value": [],
              "type": "text"
            },
            "map_to_ecs": {
              "type": "bool"
            }
          }
        },
        {
          "enabled": false,
          "data_stream": {
            "type": "logs",
            "dataset": "network_traffic.flow"
          },
          "vars": {
            "geoip_enrich": {
              "value": true,
              "type": "bool"
            },
            "monitor_processes": {
              "type": "bool"
            },
            "period": {
              "value": "10s",
              "type": "text"
            },
            "timeout": {
              "value": "30s",
              "type": "text"
            },
            "processors": {
              "type": "yaml"
            },
            "tags": {
              "value": [],
              "type": "text"
            },
            "map_to_ecs": {
              "type": "bool"
            }
          }
        },
        {
          "enabled": true,
          "data_stream": {
            "type": "logs",
            "dataset": "network_traffic.http"
          },
          "vars": {
            "port": {
              "value": [
                80,
                8080,
                8000,
                5000,
                8002
              ],
              "type": "text"
            },
            "monitor_processes": {
              "type": "bool"
            },
            "hide_keywords": {
              "value": [],
              "type": "text"
            },
            "send_headers": {
              "value": [],
              "type": "text"
            },
            "send_all_headers": {
              "type": "bool"
            },
            "redact_headers": {
              "value": [],
              "type": "text"
            },
            "include_body_for": {
              "value": [],
              "type": "text"
            },
            "include_request_body_for": {
              "value": [],
              "type": "text"
            },
            "include_response_body_for": {
              "value": [],
              "type": "text"
            },
            "decode_body": {
              "type": "bool"
            },
            "split_cookie": {
              "type": "bool"
            },
            "real_ip_header": {
              "type": "text"
            },
            "send_request": {
              "type": "bool"
            },
            "send_response": {
              "type": "bool"
            },
            "keep_null": {
              "type": "bool"
            },
            "transaction_timeout": {
              "type": "text"
            },
            "max_message_size": {
              "type": "integer"
            },
            "processors": {
              "type": "yaml"
            },
            "tags": {
              "value": [],
              "type": "text"
            },
            "map_to_ecs": {
              "type": "bool"
            }
          }
        },
        {
          "enabled": true,
          "data_stream": {
            "type": "logs",
            "dataset": "network_traffic.icmp"
          },
          "vars": {
            "geoip_enrich": {
              "value": true,
              "type": "bool"
            },
            "monitor_processes": {
              "type": "bool"
            },
            "keep_null": {
              "type": "bool"
            },
            "processors": {
              "type": "yaml"
            },
            "tags": {
              "value": [],
              "type": "text"
            },
            "map_to_ecs": {
              "type": "bool"
            }
          }
        },
        {
          "enabled": false,
          "data_stream": {
            "type": "logs",
            "dataset": "network_traffic.memcached"
          },
          "vars": {
            "port": {
              "value": [
                11211
              ],
              "type": "text"
            },
            "geoip_enrich": {
              "value": true,
              "type": "bool"
            },
            "monitor_processes": {
              "type": "bool"
            },
            "parseunknown": {
              "type": "bool"
            },
            "maxvalues": {
              "type": "integer"
            },
            "maxbytespervalue": {
              "type": "integer"
            },
            "udptransactiontimeout": {
              "type": "integer"
            },
            "send_request": {
              "type": "bool"
            },
            "send_response": {
              "type": "bool"
            },
            "keep_null": {
              "type": "bool"
            },
            "transaction_timeout": {
              "type": "text"
            },
            "processors": {
              "type": "yaml"
            },
            "tags": {
              "value": [],
              "type": "text"
            },
            "map_to_ecs": {
              "type": "bool"
            }
          }
        },
        {
          "enabled": true,
          "data_stream": {
            "type": "logs",
            "dataset": "network_traffic.mongodb"
          },
          "vars": {
            "port": {
              "value": [
                27017
              ],
              "type": "text"
            },
            "geoip_enrich": {
              "value": true,
              "type": "bool"
            },
            "monitor_processes": {
              "type": "bool"
            },
            "max_docs": {
              "type": "integer"
            },
            "max_doc_length": {
              "type": "integer"
            },
            "send_request": {
              "type": "bool"
            },
            "send_response": {
              "type": "bool"
            },
            "keep_null": {
              "type": "bool"
            },
            "transaction_timeout": {
              "type": "text"
            },
            "processors": {
              "type": "yaml"
            },
            "tags": {
              "value": [],
              "type": "text"
            },
            "map_to_ecs": {
              "type": "bool"
            }
          }
        },
        {
          "enabled": true,
          "data_stream": {
            "type": "logs",
            "dataset": "network_traffic.mysql"
          },
          "vars": {
            "port": {
              "value": [
                3306,
                3307
              ],
              "type": "text"
            },
            "geoip_enrich": {
              "value": true,
              "type": "bool"
            },
            "monitor_processes": {
              "type": "bool"
            },
            "send_request": {
              "type": "bool"
            },
            "send_response": {
              "type": "bool"
            },
            "keep_null": {
              "type": "bool"
            },
            "transaction_timeout": {
              "type": "text"
            },
            "processors": {
              "type": "yaml"
            },
            "tags": {
              "value": [],
              "type": "text"
            },
            "map_to_ecs": {
              "type": "bool"
            }
          }
        },
        {
          "enabled": true,
          "data_stream": {
            "type": "logs",
            "dataset": "network_traffic.nfs"
          },
          "vars": {
            "port": {
              "value": [
                2049
              ],
              "type": "text"
            },
            "geoip_enrich": {
              "value": true,
              "type": "bool"
            },
            "monitor_processes": {
              "type": "bool"
            },
            "send_request": {
              "type": "bool"
            },
            "send_response": {
              "type": "bool"
            },
            "keep_null": {
              "type": "bool"
            },
            "transaction_timeout": {
              "type": "text"
            },
            "processors": {
              "type": "yaml"
            },
            "tags": {
              "value": [],
              "type": "text"
            },
            "map_to_ecs": {
              "type": "bool"
            }
          }
        },
        {
          "enabled": true,
          "data_stream": {
            "type": "logs",
            "dataset": "network_traffic.pgsql"
          },
          "vars": {
            "port": {
              "value": [
                5432
              ],
              "type": "text"
            },
            "geoip_enrich": {
              "value": true,
              "type": "bool"
            },
            "monitor_processes": {
              "type": "bool"
            },
            "send_request": {
              "type": "bool"
            },
            "send_response": {
              "type": "bool"
            },
            "keep_null": {
              "type": "bool"
            },
            "transaction_timeout": {
              "type": "text"
            },
            "processors": {
              "type": "yaml"
            },
            "tags": {
              "value": [],
              "type": "text"
            },
            "map_to_ecs": {
              "type": "bool"
            }
          }
        },
        {
          "enabled": true,
          "data_stream": {
            "type": "logs",
            "dataset": "network_traffic.redis"
          },
          "vars": {
            "port": {
              "value": [
                6379
              ],
              "type": "text"
            },
            "geoip_enrich": {
              "value": true,
              "type": "bool"
            },
            "monitor_processes": {
              "type": "bool"
            },
            "send_request": {
              "type": "bool"
            },
            "send_response": {
              "type": "bool"
            },
            "keep_null": {
              "type": "bool"
            },
            "transaction_timeout": {
              "type": "text"
            },
            "queue_max_bytes": {
              "type": "integer"
            },
            "queue_max_messages": {
              "type": "integer"
            },
            "processors": {
              "type": "yaml"
            },
            "tags": {
              "value": [],
              "type": "text"
            },
            "map_to_ecs": {
              "type": "bool"
            }
          }
        },
        {
          "enabled": false,
          "data_stream": {
            "type": "logs",
            "dataset": "network_traffic.sip"
          },
          "vars": {
            "port": {
              "value": [
                5060
              ],
              "type": "text"
            },
            "geoip_enrich": {
              "value": true,
              "type": "bool"
            },
            "use_tcp": {
              "value": false,
              "type": "bool"
            },
            "monitor_processes": {
              "type": "bool"
            },
            "parse_authorization": {
              "type": "bool"
            },
            "parse_body": {
              "type": "bool"
            },
            "keep_original": {
              "type": "bool"
            },
            "processors": {
              "type": "yaml"
            },
            "tags": {
              "value": [],
              "type": "text"
            },
            "map_to_ecs": {
              "type": "bool"
            }
          }
        },
        {
          "enabled": false,
          "data_stream": {
            "type": "logs",
            "dataset": "network_traffic.thrift"
          },
          "vars": {
            "port": {
              "value": [
                9090
              ],
              "type": "text"
            },
            "geoip_enrich": {
              "value": true,
              "type": "bool"
            },
            "monitor_processes": {
              "type": "bool"
            },
            "transport_type": {
              "type": "text"
            },
            "protocol_type": {
              "type": "text"
            },
            "idl_files": {
              "value": [],
              "type": "text"
            },
            "string_max_size": {
              "type": "integer"
            },
            "collection_max_size": {
              "type": "integer"
            },
            "capture_reply": {
              "type": "bool"
            },
            "obfuscate_strings": {
              "type": "bool"
            },
            "drop_after_n_struct_fields": {
              "type": "integer"
            },
            "send_request": {
              "type": "bool"
            },
            "send_response": {
              "type": "bool"
            },
            "keep_null": {
              "type": "bool"
            },
            "transaction_timeout": {
              "type": "text"
            },
            "processors": {
              "type": "yaml"
            },
            "tags": {
              "value": [],
              "type": "text"
            },
            "map_to_ecs": {
              "type": "bool"
            }
          }
        },
        {
          "enabled": true,
          "data_stream": {
            "type": "logs",
            "dataset": "network_traffic.tls"
          },
          "vars": {
            "port": {
              "value": [
                443,
                993,
                995,
                5223,
                8443,
                8883,
                9243
              ],
              "type": "text"
            },
            "geoip_enrich": {
              "value": true,
              "type": "bool"
            },
            "monitor_processes": {
              "type": "bool"
            },
            "fingerprints": {
              "value": [],
              "type": "text"
            },
            "send_certificates": {
              "type": "bool"
            },
            "include_raw_certificates": {
              "type": "bool"
            },
            "keep_null": {
              "type": "bool"
            },
            "processors": {
              "type": "yaml"
            },
            "tags": {
              "value": [],
              "type": "text"
            },
            "map_to_ecs": {
              "type": "bool"
            }
          }
        }
      ],
      "vars": {
        "interface": {
          "type": "text"
        },
        "never_install": {
          "value": false,
          "type": "bool"
        },
        "with_vlans": {
          "value": false,
          "type": "bool"
        },
        "ignore_outgoing": {
          "value": false,
          "type": "bool"
        }
      }
    }
  ],
  "package": {
    "name": "network_traffic",
    "title": "Network Packet Capture",
    "version": "1.31.0"
  },
  "force": false
}'

sleep 10

# Define the target file path
AUDIT_RULES_FILE="/etc/audit/rules.d/audit.rules"

# Overwrite the audit.rules file with the desired content
cat <<EOF | sudo tee $AUDIT_RULES_FILE >/dev/null
## This file is automatically generated from /etc/audit/rules.d
-D
-b 8192
-f 1
--backlog_wait_time 60000
-a exit,always -F arch=b64 -S execve
-a exit,always -F arch=b32 -S execve
EOF

# Restart the auditd service to apply the changes
sudo systemctl restart auditd

# Enable the auditd service to start on boot
sudo systemctl enable auditd

# Installation completed
echo "Installation completed successfully"
