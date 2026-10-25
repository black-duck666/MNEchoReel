# Repository metadata capture

`repository.har` contains an actual, unauthenticated response from
<https://api.github.com/repos/moonbitlang/core>, captured on 2026-10-25
at 07:49:55 UTC. The response was HTTP 200 with 6,228 body bytes.
It includes the public repository name, owner, description and other API fields.
No credentials or private infrastructure were used.

Acquisition command (from a directory with a `tmp` subdirectory):

```sh
curl -fL -H 'Accept-Encoding: identity' -H 'Accept: application/vnd.github+json' -H 'User-Agent: EchoReel-fixture' -D tmp/response.headers https://api.github.com/repos/moonbitlang/core -o tmp/response.json
```

Import the saved HTTP response from this repository root:

```sh
moon run tools/import_capture.mbtx tmp/response.headers tmp/response.json https://api.github.com/repos/moonbitlang/core 2026-10-25T07:49:55Z examples/repository.har
```

Use the actual acquisition time if recording a new response. The checked-in
recording is stable; tests never refresh it or contact GitHub.

The importer constructs the HAR envelope around the unchanged UTF-8 response
body and all response headers, in order. This is a curl capture imported into
HAR, not a browser-exported HAR. Request headers are the three explicit curl
headers; curl's implicit Host/transport headers were not captured. HAR timing
values are zero placeholders, with a comment; they are not measured latency.
`headersSize=-1` means unmeasured. The request is GET with no body.

The capture consists of public factual metadata supplied by GitHub. The API
response states no separate dataset license. The repository's reported
Apache-2.0 source-code license does not establish a license for the API payload.
Source attribution is retained here; see [GitHub's API documentation](https://docs.github.com/en/rest/repos/repos#get-a-repository)
and [terms](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service).
The HAR envelope and importer are project-authored under the root MIT license.
Synthetic unit-test recordings are separately authored under MIT.
