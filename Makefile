FLOW_COMMIT = 92bbb5e9dacb8185aa73ea343954d0434b42c40b
TEST262_COMMIT = 46f165ae490de7f1343165ab8d228db81eaa02c5
TYPESCRIPT_COMMIT = bbd9ff51f5fa5208b223bbb75a94e5e8184e3ffd

# Fix color output until TravisCI fixes https://github.com/travis-ci/travis-ci/issues/7967
export FORCE_COLOR = true

SOURCES = packages codemods eslint

COMMA := ,
EMPTY :=
SPACE := $(EMPTY) $(EMPTY)
COMMA_SEPARATED_SOURCES = $(subst $(SPACE),$(COMMA),$(SOURCES))

YARN := yarn
NODE := $(YARN) node


.PHONY: build build-dist watch lint fix clean test-clean test-only test test-ci publish bootstrap

build: build-no-bundle
ifneq ("$(BABEL_COVERAGE)", "true")
	$(MAKE) build-standalone
endif

build-bundle: clean clean-lib
	$(YARN) gulp build
	$(MAKE) build-flow-typings
	$(MAKE) build-dist

build-no-bundle-ci: bootstrap-only
	$(YARN) gulp build-dev
	$(MAKE) build-flow-typings
	$(MAKE) build-dist

build-no-bundle: clean clean-lib
	BABEL_ENV=development $(YARN) gulp build-dev
	$(MAKE) build-flow-typings
	$(MAKE) build-dist

generate-tsconfig:
	$(NODE) scripts/generators/tsconfig.js

generate-type-helpers:
	$(YARN) gulp generate-type-helpers

build-flow-typings:
	$(NODE) packages/babel-types/scripts/generators/flow.js > packages/babel-types/lib/index.js.flow

# For TypeScript older than 3.7
build-typescript-legacy-typings:
	$(NODE) packages/babel-types/scripts/generators/typescript-legacy.js > packages/babel-types/lib/index-legacy.d.ts

build-standalone: build-babel-standalone

build-standalone-ci: build-no-bundle-ci
	$(MAKE) build-standalone

build-babel-standalone:
	$(YARN) gulp build-babel-standalone

prepublish-build-standalone:
	BABEL_ENV=production IS_PUBLISH=true $(YARN) gulp build-babel-standalone

build-dist: build-plugin-transform-runtime-dist

build-plugin-transform-runtime-dist:
	cd packages/babel-plugin-transform-runtime; \
	$(NODE) scripts/build-dist.js

watch: build-no-bundle
	BABEL_ENV=development $(YARN) gulp watch

flowcheck-ci:
	$(MAKE) flow

code-quality: tscheck flow lint

tscheck: generate-tsconfig
	rm -rf dts
	$(YARN) tsc -b .

flow: build-flow-typings
	$(YARN) flow check --strip-root

lint-ci: lint check-compat-data-ci

check-compat-data-ci:
	$(MAKE) check-compat-data

lint:
	BABEL_ENV=test $(YARN) eslint scripts benchmark $(SOURCES) '*.{js,cjs,mjs,ts}' --format=codeframe --ext .js,.cjs,.mjs,.ts

fix: fix-json fix-js

fix-js:
	$(YARN) eslint scripts benchmark $(SOURCES) '*.{js,cjs,mjs,ts}' --format=codeframe --ext .js,.cjs,.mjs,.ts --fix

fix-json:
	$(YARN) prettier "{$(COMMA_SEPARATED_SOURCES)}/*/test/fixtures/**/options.json" --write --loglevel warn

check-compat-data:
	cd packages/babel-compat-data; CHECK_COMPAT_DATA=true $(YARN) run build-data

build-compat-data:
	cd packages/babel-compat-data; $(YARN) run build-data

clean: test-clean
	rm -f .npmrc
	rm -rf coverage
	rm -rf packages/*/npm-debug*
	rm -rf node_modules/.cache

test-clean:
	$(foreach source, $(SOURCES), \
		$(call clean-source-test, $(source)))

# Does not work on Windows; use "$(YARN) jest" instead
test-only:
	BABEL_ENV=test ./scripts/test.sh
	$(MAKE) test-clean

test: lint test-only

test-ci: build-standalone-ci
	BABEL_ENV=test $(YARN) jest --maxWorkers=4 --ci
	$(MAKE) test-clean

# Does not work on Windows
test-ci-coverage: SHELL:=/bin/bash
test-ci-coverage:
	BABEL_COVERAGE=true BABEL_ENV=test $(MAKE) bootstrap
	BABEL_ENV=test TEST_TYPE=cov ./scripts/test-cov.sh

bootstrap-flow:
	rm -rf build/flow
	mkdir -p build
	git clone --single-branch --shallow-since=2021-05-01 https://github.com/facebook/flow.git build/flow
	cd build/flow && git checkout -q $(FLOW_COMMIT)

test-flow:
	$(NODE) scripts/parser-tests/flow

test-flow-update-allowlist:
	$(NODE) scripts/parser-tests/flow --update-allowlist

bootstrap-typescript:
	rm -rf ./build/typescript
	mkdir -p ./build
	git clone --single-branch --shallow-since=2021-05-01 https://github.com/microsoft/TypeScript.git ./build/typescript
	cd build/typescript && git checkout -q $(TYPESCRIPT_COMMIT)

test-typescript:
	$(NODE) scripts/parser-tests/typescript

test-typescript-update-allowlist:
	$(NODE) scripts/parser-tests/typescript --update-allowlist

bootstrap-test262:
	rm -rf build/test262
	mkdir -p build
	git clone --single-branch --shallow-since=2021-05-01 https://github.com/tc39/test262.git build/test262
	cd build/test262 && git checkout -q $(TEST262_COMMIT)

test-test262:
	$(NODE) scripts/parser-tests/test262

test-test262-update-allowlist:
	$(NODE) scripts/parser-tests/test262 --update-allowlist

# Does not work on Windows
clone-license:
	./scripts/clone-license.sh

prepublish-build: clean-lib clean-runtime-helpers
	NODE_ENV=production BABEL_ENV=production STRIP_BABEL_8_FLAG=true $(MAKE) build-bundle
	STRIP_BABEL_8_FLAG=true $(MAKE) prepublish-build-standalone clone-license prepublish-prepare-dts

prepublish-prepare-dts:
	$(MAKE) tscheck
	$(YARN) gulp bundle-dts
	$(MAKE) build-typescript-legacy-typings

prepublish:
	$(MAKE) bootstrap-only
	$(MAKE) prepublish-build
	IS_PUBLISH=true $(MAKE) test

new-version-checklist:
	# @echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	# @echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	# @echo "!!!!!!                                                   !!!!!!"
	# @echo "!!!!!!         Write any message that should             !!!!!!"
	# @echo "!!!!!!            block the release here                 !!!!!!"
	# @echo "!!!!!!                                                   !!!!!!"
	# @echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	# @echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	# @exit 1

new-version:
	$(MAKE) new-version-checklist
	git pull --rebase
	$(YARN) release-tool version -f @babel/standalone

# NOTE: Run make new-version first
publish:
	@echo "Please confirm you have stopped make watch. (y)es, [N]o:"; \
	read CLEAR; \
	if [ "_$$CLEAR" != "_y" ]; then \
		exit 1; \
	fi
	$(MAKE) prepublish
	$(YARN) release-tool publish
	$(MAKE) clean

publish-test:
ifneq ("$(I_AM_USING_VERDACCIO)", "I_AM_SURE")
	echo "You probably don't know what you are doing"
	exit 1
endif
	$(YARN) release-tool version $(VERSION) --all --yes --tag-version-prefix="version-e2e-test-"
	$(MAKE) prepublish-build
	YARN_NPM_PUBLISH_REGISTRY=http://localhost:4873 $(YARN) release-tool publish --yes --tag-version-prefix="version-e2e-test-"
	$(MAKE) clean

bootstrap-only: clean-all
	$(YARN) install

bootstrap: bootstrap-only
	$(MAKE) generate-tsconfig build

clean-lib:
	$(foreach source, $(SOURCES), \
		$(call clean-source-lib, $(source)))

clean-runtime-helpers:
	rm -f packages/babel-runtime/helpers/**/*.js
	rm -f packages/babel-runtime-corejs2/helpers/**/*.js
	rm -f packages/babel-runtime-corejs3/helpers/**/*.js
	rm -f packages/babel-runtime/helpers/**/*.mjs
	rm -f packages/babel-runtime-corejs2/helpers/**/*.mjs
	rm -f packages/babel-runtime-corejs3/helpers/**/*.mjs
	rm -rf packages/babel-runtime-corejs2/core-js

clean-all:
	rm -rf node_modules
	rm -rf package-lock.json
	rm -rf .changelog

	$(foreach source, $(SOURCES), \
		$(call clean-source-all, $(source)))

	$(MAKE) clean

update-env-corejs-fixture:
	rm -rf packages/babel-preset-env/node_modules/core-js-compat
	$(YARN)
	$(MAKE) build-bundle
	OVERWRITE=true $(YARN) jest packages/babel-preset-env

define clean-source-lib
	rm -rf $(1)/*/lib

endef

define clean-source-test
	rm -rf $(1)/*/test/tmp
	rm -rf $(1)/*/test-fixtures.json

endef

define clean-source-all
	$(call clean-source-lib, $1)
	rm -rf $(1)/*/node_modules
	rm -rf $(1)/*/package-lock.json

endef
