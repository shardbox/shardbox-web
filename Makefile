DATABASE_NAME ?= $(shell echo $(DATABASE_URL) | grep -o -P '[^/]+$$')
TEST_DATABASE_NAME ?= $(shell echo $(TEST_DATABASE_URL) | grep -o -P '[^/]+$$')
PG_USER ?= postgres
BIN ?= bin

worker_cr = lib/shardbox-core/src/worker.cr

.PHONY: build
build: $(BIN)/app $(BIN)/worker

.PHONY: DATABASE_URL
DATABASE_URL:
	@test "${$@}" || (echo "$@ is undefined" && false)

.PHONY: TEST_DATABASE_URL
TEST_DATABASE_URL:
	@test "${$@}" || (echo "$@ is undefined" && false)

.PHONY: $(BIN)/worker
$(BIN)/worker: $(worker_cr)
	crystal build $(worker_cr) -o $(@)

.PHONY: $(BIN)/app
$(BIN)/app: src/app.cr
	crystal build src/app.cr -o $(@)

.PHONY: test
test:
	crystal spec

.PHONY: clean
clean:
	rm -rf $(BIN)/worker $(BIN)/app
