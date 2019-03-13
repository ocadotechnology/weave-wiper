# Weave wIPer

Mitigation container for leaking IP addresses by weave.

This container checks currently active IPs on the weave container running
on the same pod via an http call.

The node's docker socket file is mounted in a volume so another http call
can get the list of containers running.

Container IDs are compared and those that are in weave's list but not on
 docker's get deleted.

Copyright © 2019 Ocado