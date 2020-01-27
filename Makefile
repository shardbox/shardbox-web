DATABASE_NAME ?= $(shell echo $(DATABASE_URL) | grep -o -P '[^/]+$$')
TEST_DATABASE_NAME ?= $(shell echo $(TEST_DATABASE_URL) | grep -o -P '[^/]+$$')
PG_USER ?= postgres
BIN ?= bin
SHARDS := shards

.PHONY: build
build: $(BIN)/app $(BIN)/worker

.PHONY: DATABASE_URL
DATABASE_URL:
	@test "${$@}" || (echo "$@ is undefined" && false)

.PHONY: TEST_DATABASE_URL
TEST_DATABASE_URL:
	@test "${$@}" || (echo "$@ is undefined" && false)

$(BIN)/worker: shard.lock
	$(SHARDS) build worker

$(BIN)/app: src/* shard.lock
	$(SHARDS) build app

shard.lock: shard.yml
	$(SHARDS) update

.PHONY: test
test:
	crystal spec

.PHONY: clean
clean:
	rm -rf $(BIN)/worker $(BIN)/app
