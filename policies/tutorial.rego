#-----------------------------------------------------------------------------
# High level policy for controlling access to Kafka.
#
# * Deny operations by default.
# * Allow operations if no explicit denial.
#
# The kafka-authorizer-opa plugin will query OPA for decisions at
# /kafka/authz/allow. If the policy decision is _true_ the request is allowed.
# If the policy decision is _false_ the request is denied.
#-----------------------------------------------------------------------------
package kafka.authz

import future.keywords.in

default allow := false

allow {
	not deny
}

deny {
	is_read_operation
	topic_contains_pii
	not consumer_is_allowlisted_for_pii
}

#-----------------------------------------------------------------------------
# Data structures for controlling access to topics. In real-world deployments,
# these data structures could be loaded into OPA as raw JSON data. The JSON
# data could be pulled from external sources like AD, Git, etc.
#-----------------------------------------------------------------------------

consumer_allowlist := {"pii": {"pii_consumer"}}

topic_metadata := {"credit-scores": {"tags": ["pii"]}}

#-----------------------------------
# Helpers for checking topic access.
#-----------------------------------

topic_contains_pii {
	"pii" in topic_metadata[topic_name].tags
}

consumer_is_allowlisted_for_pii {
	principal.name in consumer_allowlist.pii
}

#-----------------------------------------------------------------------------
# Helpers for processing Kafka operation input. This logic could be split out
# into a separate file and shared. For conciseness, we have kept it all in one
# place.
#-----------------------------------------------------------------------------

is_write_operation {
    input.action.operation == "WRITE"
}

is_read_operation {
	input.action.operation == "READ"
}

is_topic_resource {
	input.action.resourcePattern.resourceType == "TOPIC"
}

topic_name := input.action.resourcePattern.name {
	is_topic_resource
}

principal := {"fqn": parsed.CN, "name": cn_parts[0]} {
	parsed := parse_user(input.requestContext.principal.name)
	cn_parts := split(parsed.CN, ".")
}

# If client certificates aren't used for authentication
else := {"fqn": "", "name": input.requestContext.principal.name}

parse_user(user) := {key: value |
	parts := split(user, ",")
	[key, value] := split(parts[_], "=")
}