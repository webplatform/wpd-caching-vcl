
#
# Fastly (Varnish) configuration for docs.webplatform.org
#
# Service: www, v #24 (16, 21)
#
# Backend configs:
#   - Max connections: 600
#   - Error treshold: 2
#   - Connection (ms): 15000
#   - First byte (ms): 15000
#   - Between bytes (ms): 10000
#
# Assuming it is using Varnish 2.1.5 syntax
#
# Ref:
#  - https://www.varnish-cache.org/docs/2.1/tutorial/vcl.html
#  - https://www.varnish-software.com/static/book/VCL_functions.html
#  - http://docs.fastly.com/guides/22958207/27123847
#  - http://docs.fastly.com/guides/22958207/23206371
#  - https://www.varnish-cache.org/docs/2.1/tutorial/increasing_your_hitrate.html
#


    # Doc: Called at the beginning of a request, after the complete request
    #      has been received and parsed. Its purpose is to
    #      decide whether or not to serve the request, how to
    #      do it, and, if applicable, which backend to use.
sub vcl_recv {
#FASTLY recv

  set client.identity = req.http.Fastly-Client-IP;

  # No need for cookie, at all!
  remove req.http.Cookie;

  # Header overwrite XFF
  if (!req.http.X-Forwarded-For) {
    set req.http.X-Forwarded-For = req.http.Fastly-Client-IP;
  }

  #
  # Handle grace periods for where we will serve a stale response
  #     source: https://github.com/python/psf-fastly/blob/master/vcl/pypi.vcl
  if (!req.backend.healthy) {
      # The backend is unhealthy which means we want to serve the stale
      #   response long enough (hopefully) for us to fix the problem.
      set req.grace = 24h;

      # The backend is unhealthy which means we want to serve responses as
      #   if the user was not logged in. This means they will be eligible
      #   for the cached pages.
      remove req.http.Authenticate;
      remove req.http.Authorization;
      remove req.http.Cookie;
  }
  else {
      # Avoid a request pileup by serving stale content if required.
      set req.grace = 15s;
  }


  # normalize Accept-Encoding to reduce vary
  if (req.http.Accept-Encoding) {
    if (req.http.User-Agent ~ "MSIE 6") {
      unset req.http.Accept-Encoding;
    } elsif (req.http.Accept-Encoding ~ "gzip") {
      set req.http.Accept-Encoding = "gzip";
    } elsif (req.http.Accept-Encoding ~ "deflate") {
      set req.http.Accept-Encoding = "deflate";
    } else {
      unset req.http.Accept-Encoding;
    }
  }

  ## Fastly BOILERPLATE ========
  if (req.request != "HEAD" && req.request != "GET" && req.request != "PURGE") {
      return(pass);
  }
  return(lookup);  # Default outcome, keep at the end
  ## /Fastly BOILERPLATE ========
}




    # Doc: Called after a document has been successfully retrieved from the backend
sub vcl_fetch {
#FASTLY fetch

  # Set the maximum grace period on an object
  set beresp.grace = 24h;

  # Debug notes
  if(!beresp.http.X-Cache-Note) {
    set beresp.http.X-Cache-Note = "Debugging notes: ";
  }

  # Gzip
  if (beresp.status == 200 && (beresp.http.content-type ~ "^(text/html|application/x-javascript|text/css|application/javascript|text/javascript)\s*($|;)" || req.url ~ "\.(js|css|html)($|\?)" ) ) {
    # always set vary to make sure uncompressed versions dont always win
    if (!beresp.http.Vary ~ "Accept-Encoding") {
      if (beresp.http.Vary) {
        set beresp.http.Vary = beresp.http.Vary ", Accept-Encoding";
      } else {
         set beresp.http.Vary = "Accept-Encoding";
      }
    }
    if (req.http.Accept-Encoding == "gzip") {
      set beresp.gzip = true;
    }
  }

  # Enforce static asset Cache
  if (
    beresp.http.content-type ~ "^(text/css|image|application/javascript|text/javascript)\s*($|;)"
  ) {
      set beresp.http.X-Cache-Note = beresp.http.X-Cache-Note ", Forced static asset cache";
      set beresp.ttl = 86400s;
      set beresp.grace = 864000s;
      return(deliver);
  }

  ## Fastly BOILERPLATE ========
  if ((beresp.status == 500 || beresp.status == 503) && req.restarts < 1 && (req.request == "GET" || req.request == "HEAD")) {
    restart;
  }
  if(req.restarts > 0 ) {
    set beresp.http.Fastly-Restarts = req.restarts;
  }
  if (beresp.http.Set-Cookie) {
    set beresp.http.X-Cache-Note = beresp.http.X-Cache-Note ", Has Set-Cookie";
    set req.http.Fastly-Cachetype = "SETCOOKIE";
    return (pass);
  }
  if (beresp.http.Cache-Control ~ "private") {
    set beresp.http.X-Cache-Note = beresp.http.X-Cache-Note ", Cache-Control private";
    set req.http.Fastly-Cachetype = "PRIVATE";
    return (pass);
  }
  if (beresp.status == 500 || beresp.status == 503) {
    set beresp.http.X-Cache-Note = beresp.http.X-Cache-Note ", Error document";
    set req.http.Fastly-Cachetype = "ERROR";
    set beresp.ttl = 1s;
    set beresp.grace = 5s;
    return (deliver);
  }
  if (beresp.http.Expires || beresp.http.Surrogate-Control ~ "max-age" || beresp.http.Cache-Control ~"(s-maxage|max-age)") {
    set beresp.http.X-Cache-Note = beresp.http.X-Cache-Note ", Has either max-age,Expires,Cache-control";
    # keep the ttl here
  } else {
    # apply the default ttl
    set beresp.http.X-Cache-Note = beresp.http.X-Cache-Note ", Had no max-age,expires,cache-control; setting default ttl";
    set beresp.ttl = 3600s;
  }
  return(deliver); # Default outcome, keep at the end
  ## /Fastly BOILERPLATE =======
}




    # Doc: Called before a cached object is delivered to the client
sub vcl_deliver {
#FASTLY deliver

  # Always send this instead of using meta tags in markup
  if (resp.http.Content-Type ~ "html") {
    set resp.http.X-UA-Compatible = "IE=edge,chrome=1";
  }

  # Debug, Advise backend
  set resp.http.X-Backend-Key = req.backend;

  # Debug, change version string
  set resp.http.X-Config-Serial = "2015031100";

  if (!req.http.Fastly-Debug) {
      remove resp.http.X-Cache-Note;
      remove resp.http.X-Backend-Key;
      remove resp.http.Server;
      remove resp.http.Via;
      remove resp.http.X-Served-By;
      remove resp.http.X-Cache;
      remove resp.http.X-Cache-Hits;
      remove resp.http.X-Timer;
  }

  ## Fastly BOILERPLATE ========
  return(deliver);
  ## /Fastly BOILERPLATE =======
}
