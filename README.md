AFNetworking-ProxyQueue
=======================

AFNetworking with multiple operation queue support, to separate download operations from affecting too much on main network request.


```objective-c

// Original
[[YourHTTPClient sharedClient] enqueueHTTPRequestOperation:usualNetworkOperation];

// Dispatch to another shared queue for download operation
[[YourHTTPClient sharedClient] proxyQueueNamed:@"downloadQueue"] enqueueHTTPRequestOperation:downloadOperation];

```
