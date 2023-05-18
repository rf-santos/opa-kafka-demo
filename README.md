# Demo OPA policy enforcment on Kafka cluster
This demo recreates the steps defined here: [OPA Kafka Use Case](https://www.openpolicyagent.org/docs/latest/kafka-authorization).  
## Requirements
- [OPA](https://www.openpolicyagent.org/docs/latest/#running-opa)
- [JRE](https://docs.oracle.com/goldengate/1212/gg-winux/GDRAD/java.htm#BGBFJHAB)
- [OPA Kafka plugin](https://github.com/StyraInc/opa-kafka-plugin)
- [Docker Compose](https://docs.docker.com/compose/)

## Demo
The policies are defined in `policies/tutorial.rego`. If there are any modifications to the policies files we need to build it again using `opa build`.
```bash
opa build --bundle policies/ --output bundles/bundle.tar.gz
```

`input-example.json` is an example of the info OPA receives as input from Kafka + OPA Kafka plugin request for a decision.

Spin up the services required for the demo.
- NGINX - will serve the `bundle.tar.gz` file which holds all of our policies to enforce. This mimics a remote serving, showing that policies can be detached from the enforcer.
- OPA - will enforce the policies served in the NGINX server
- KAFKA - will hold the Kafka cluster with a single message broker.
- ZOOKEEPER - is required to manage KAFKA
```bash
docker compose -p opa-kafka-tutorial up
```
If not yet, create the CA certificates to mimic different kinds of users accessing the Kafka cluster.
```bash
bash ./create_cert.sh
```
Prepare 3 different bash sessions and run each command sepratelly

```bash
# using the annon_producer user to generate 10 messages on the credit-scores topic
docker run \  
-v $(pwd)/cert/client:/tmp/client \  
--rm \  
--network opa-kafka-tutorial_default \  
confluentinc/cp-kafka:6.2.1 bash -c \  
'for i in {1..10}; \  
do echo "{\"user\": \"ricardo\", \"score\": $i}"; \  
done | kafka-console-producer \  
--topic credit-scores \  
--broker-list broker:9093 \  
--producer.config /tmp/client/anon_producer.properties'
```

```bash
# using the pii_consumer user to consume the messages
docker run \  
-v $(pwd)/cert/client:/tmp/client \  
--rm \  
--network opa-kafka-tutorial_default \  
confluentinc/cp-kafka:6.2.1 kafka-console-consumer \  
--bootstrap-server broker:9093 \  
--topic credit-scores \  
--from-beginning \  
--consumer.config /tmp/client/pii_consumer.properties
```

```bash
# using the annon_conssumer user to try to consume the same messages, but gets blocked by OPA
docker run \  
-v $(pwd)/cert/client:/tmp/client \  
--rm \  
--network opa-kafka-tutorial_default \  
confluentinc/cp-kafka:6.2.1 kafka-console-consumer \  
--bootstrap-server broker:9093 \  
--topic credit-scores \  
--from-beginning \  
--consumer.config /tmp/client/anon_consumer.properties
```

This demonstrates that a user without the pii_consumer cert cannonc consume messages from topics defined in the following section of the policy file `tutorial.rego` as having PII information.
```
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
```