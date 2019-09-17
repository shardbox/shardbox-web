DATABASE_NAME ?= $(shell echo $(DATABASE_URL) | grep -o -P '[^/]+$$')
TEST_DATABASE_NAME ?= $(shell echo $(TEST_DATABASE_URL) | grep -o -P '[^/]+$$')
PG_USER ?= postgres
BIN ?= bin

.PHONY: DATABASE_URL
DATABASE_URL:
	@test "${$@}" || (echo "$@ is undefined" && false)

.PHONY: TEST_DATABASE_URL
TEST_DATABASE_URL:
	@test "${$@}" || (echo "$@ is undefined" && false)

.PHONY: $(BIN)/worker
$(BIN)/worker: src/worker.cr
	crystal build src/worker.cr -o $(@)

.PHONY: $(BIN)/app
$(BIN)/app: src/app.cr
	crystal build src/app.cr -o $(@)

.PHONY: test
test:
	crystal spec
