# SERVER_URL: base URL for "try it out" in the served Swagger UI (no trailing slash)
SERVER_URL ?= http://localhost:3030
PORT       ?= 8080
SERVE_DIR  := .serve

SWAGGER_VERSION := 5.18.2
SWAGGER_CDN     := https://unpkg.com/swagger-ui-dist@$(SWAGGER_VERSION)

.PHONY: all build build-admin serve serve-admin dist-onprem clean

all: build build-admin

# ── Standalone Redoc HTML (documentation-only, no try-it-out) ────────────────

build: dist/api.html

build-admin: dist/admin-api.html

dist/api.html: spec.yaml
	mkdir -p dist
	npx @redocly/cli build-docs spec.yaml -o $@

dist/admin-api.html: admin-spec.yaml
	mkdir -p dist
	npx @redocly/cli build-docs admin-spec.yaml -o $@

# ── On-prem customer bundle ───────────────────────────────────────────────────
# Generates two self-contained HTML files with the spec embedded as JSON and
# the server URL set to SERVER_URL.  No local server or Node.js required —
# customers can open the files directly in a browser or host them anywhere.
#
# Usage:
#   make dist-onprem SERVER_URL=https://your.dagshub.instance.com
#
# Output: dist/api-interactive.html  and  dist/admin-api-interactive.html

dist-onprem: dist/api-interactive.html dist/admin-api-interactive.html
	@echo ""
	@echo "  dist/api-interactive.html       — public API (server: $(SERVER_URL))"
	@echo "  dist/admin-api-interactive.html — admin API  (server: $(SERVER_URL))"
	@echo ""
	@echo "  Share these two files.  Open directly in a browser — no server needed."

dist/api-interactive.html: spec.yaml
	mkdir -p dist
	$(MAKE) _embed-swagger-html SRC=spec.yaml OUT=$@ TITLE="DagsHub API"

dist/admin-api-interactive.html: admin-spec.yaml
	mkdir -p dist
	$(MAKE) _embed-swagger-html SRC=admin-spec.yaml OUT=$@ TITLE="DagsHub Admin API"

# Converts SRC spec to JSON (via yq), patches the servers block with a
# {host} variable so the URL is editable in the Swagger UI "Servers" dropdown,
# then embeds everything into a single HTML file.
# Requires: yq (https://github.com/mikefarah/yq)
_embed-swagger-html:
	yq -o json '.' $(SRC) | \
	python3 -c "\
import sys, json;\
from urllib.parse import urlparse;\
parsed = urlparse('$(SERVER_URL)');\
scheme = parsed.scheme or 'https';\
host = parsed.netloc;\
data = json.loads(sys.stdin.read());\
data['servers'] = [{'url': scheme + '://{host}/api/v1', 'variables': {'host': {'default': host, 'description': 'Your DagsHub instance hostname (e.g. dagshub.com or your-company.dagshub.io)'}}}];\
spec_json = json.dumps(data);\
html = (\
'<!DOCTYPE html>\n'\
'<html lang=\"en\">\n'\
'<head>\n'\
'  <meta charset=\"utf-8\"/>\n'\
'  <meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"/>\n'\
'  <title>$(TITLE)</title>\n'\
'  <link rel=\"stylesheet\" href=\"$(SWAGGER_CDN)/swagger-ui.css\" integrity=\"sha384-rcbEi6xgdPk0iWkAQzT2F3FeBJXdG+ydrawGlfHAFIZG7wU6aKbQaRewysYpmrlW\" crossorigin=\"anonymous\"/>\n'\
'</head>\n'\
'<body>\n'\
'  <div id=\"swagger-ui\"></div>\n'\
'  <script src=\"$(SWAGGER_CDN)/swagger-ui-bundle.js\" integrity=\"sha384-NXtFPpN61oWCuN4D42K6Zd5Rt2+uxeIT36R7kpXBuY9tLnZorzrJ4ykpqwJfgjpZ\" crossorigin=\"anonymous\"></script>\n'\
'  <script src=\"$(SWAGGER_CDN)/swagger-ui-standalone-preset.js\" integrity=\"sha384-qr68CD0cvHa88PmVu7e1a58Ego4qvKtcvcLdS2a8Mo5zILI01gyIV9jVwJk7X2NU\" crossorigin=\"anonymous\"></script>\n'\
'  <script>\n'\
'    SwaggerUIBundle({\n'\
'      spec: ' + spec_json + ',\n'\
'      dom_id: \"#swagger-ui\",\n'\
'      deepLinking: true,\n'\
'      presets: [SwaggerUIBundle.presets.apis, SwaggerUIStandalonePreset],\n'\
'      layout: \"StandaloneLayout\"\n'\
'    })\n'\
'  </script>\n'\
'</body>\n'\
'</html>'\
);\
open('$(OUT)', 'w').write(html);\
print('wrote $(OUT)')\
"

# ── Local dev: Swagger UI served from disk (hot-reload friendly) ──────────────
# Patches the spec's servers block and serves spec + UI via python http.server.
# Open http://localhost:$(PORT) after running.

serve: _serve-setup-public
	@echo ""
	@echo "  Swagger UI → http://localhost:$(PORT)"
	@echo "  API calls  → $(SERVER_URL)/api/v1"
	@echo ""
	cd $(SERVE_DIR)/public && python3 -m http.server $(PORT)

serve-admin: _serve-setup-admin
	@echo ""
	@echo "  Swagger UI (admin) → http://localhost:$(PORT)"
	@echo "  API calls          → $(SERVER_URL)/api/v1"
	@echo ""
	cd $(SERVE_DIR)/admin && python3 -m http.server $(PORT)

_serve-setup-public:
	mkdir -p $(SERVE_DIR)/public
	python3 -c "import re; f='spec.yaml'; t=open(f).read(); t=re.sub(r'(?m)^servers:.*?(?=^\S)', 'servers:\n  - url: $(SERVER_URL)/api/v1\n\n', t, flags=re.DOTALL); open('$(SERVE_DIR)/public/spec.yaml','w').write(t)"
	$(MAKE) _swagger-html DIR=$(SERVE_DIR)/public TITLE="DagsHub API"

_serve-setup-admin:
	mkdir -p $(SERVE_DIR)/admin
	python3 -c "import re; f='admin-spec.yaml'; t=open(f).read(); t=re.sub(r'(?m)^servers:.*?(?=^\S)', 'servers:\n  - url: $(SERVER_URL)/api/v1\n\n', t, flags=re.DOTALL); open('$(SERVE_DIR)/admin/spec.yaml','w').write(t)"
	$(MAKE) _swagger-html DIR=$(SERVE_DIR)/admin TITLE="DagsHub Admin API"

# Writes a Swagger UI index.html that loads spec.yaml from the same directory.
# Uses CDN assets with SRI hashes pinned to SWAGGER_VERSION.
_swagger-html:
	@printf '<!DOCTYPE html>\n\
<html lang="en">\n\
<head>\n\
  <meta charset="utf-8" />\n\
  <meta name="viewport" content="width=device-width, initial-scale=1" />\n\
  <title>%s</title>\n\
  <link rel="stylesheet"\n\
    href="$(SWAGGER_CDN)/swagger-ui.css"\n\
    integrity="sha384-rcbEi6xgdPk0iWkAQzT2F3FeBJXdG+ydrawGlfHAFIZG7wU6aKbQaRewysYpmrlW"\n\
    crossorigin="anonymous" />\n\
</head>\n\
<body>\n\
  <div id="swagger-ui"></div>\n\
  <script src="$(SWAGGER_CDN)/swagger-ui-bundle.js"\n\
    integrity="sha384-NXtFPpN61oWCuN4D42K6Zd5Rt2+uxeIT36R7kpXBuY9tLnZorzrJ4ykpqwJfgjpZ"\n\
    crossorigin="anonymous"></script>\n\
  <script src="$(SWAGGER_CDN)/swagger-ui-standalone-preset.js"\n\
    integrity="sha384-qr68CD0cvHa88PmVu7e1a58Ego4qvKtcvcLdS2a8Mo5zILI01gyIV9jVwJk7X2NU"\n\
    crossorigin="anonymous"></script>\n\
  <script>\n\
    SwaggerUIBundle({\n\
      url: "spec.yaml",\n\
      dom_id: "#swagger-ui",\n\
      deepLinking: true,\n\
      presets: [SwaggerUIBundle.presets.apis, SwaggerUIStandalonePreset],\n\
      layout: "StandaloneLayout"\n\
    })\n\
  </script>\n\
</body>\n\
</html>\n' "$(TITLE)" > $(DIR)/index.html

# ── Cleanup ───────────────────────────────────────────────────────────────────

clean:
	rm -rf dist $(SERVE_DIR)
