-include Makefile.local # for optional local options

BUILD_TARGET ::= bin/app
WORKER_TARGET ::= bin/worker
BUILD_TARGETS ::= $(BUILD_TARGET) $(WORKER_TARGET)

# The shards command to use
SHARDS ?= shards
# The crystal command to use
CRYSTAL ?= crystal

SRC_SOURCES ::= $(shell find src -name '*.cr' 2>/dev/null)
LIB_SOURCES ::= $(shell find lib -name '*.cr' 2>/dev/null)
SPEC_SOURCES ::= $(shell find spec -name '*.cr' 2>/dev/null)

PG_USER ::= postgres
DATABASE_NAME ::= $(shell echo $(DATABASE_URL) | grep -o -P '[^/]+$$')
TEST_DATABASE_NAME ::= $(shell echo $(TEST_DATABASE_URL) | grep -o -P '[^/]+$$')

.PHONY: build
build: ## Build the application binary
build: $(BUILD_TARGETS)

$(BUILD_TARGET): $(SRC_SOURCES) $(LIB_SOURCES) lib
	mkdir -p $(shell dirname $(@))
	$(CRYSTAL) build src/cli.cr -o $(@)

$(WORKER_TARGET): $(SRC_SOURCES) $(LIB_SOURCES) lib
	mkdir -p $(shell dirname $(@))
	$(CRYSTAL) build lib/shardbox-core/src/worker.cr -o $(@)

.PHONY: test
test: ## Run the test suite
test: lib
	$(CRYSTAL) spec

.PHONY: format
format: ## Apply source code formatting
format: $(SRC_SOURCES) $(SPEC_SOURCES)
	$(CRYSTAL) tool format src spec

docs: ## Generate API docs
docs: $(SRC_SOURCES) lib
	$(CRYSTAL) docs -o docs

lib: shard.lock
	$(SHARDS) install
	# Touch is necessary because `shards install` always touches shard.lock
	touch lib

shard.lock: shard.yml
	$(SHARDS) update

.PHONY: public/assets
public/assets: $(BUILD_TARGET)
	$(BUILD_TARGET) assets:precompile

.PHONY: DATABASE_URL
DATABASE_URL:
	@test "${$@}" || (echo "$@ is undefined" && false)

.PHONY: TEST_DATABASE_URL
TEST_DATABASE_URL:
	@test "${$@}" || (echo "$@ is undefined" && false)

.PHONY: clean
clean: ## Remove application binary
clean:
	@rm -rf $(BUILD_TARGETS)
	@rm -rf public/assets/css/style.css

.PHONY: help
help: ## Show this help
	@echo
	@printf '\033[34mtargets:\033[0m\n'
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) |\
		sort |\
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo
	@printf '\033[34moptional variables:\033[0m\n'
	@grep -hE '^[a-zA-Z_-]+ \?=.*?## .*$$' $(MAKEFILE_LIST) |\
		sort |\
		awk 'BEGIN {FS = " \\?=.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo
	@printf '\033[34mrecipes:\033[0m\n'
	@grep -hE '^##.*$$' $(MAKEFILE_LIST) |\
		awk 'BEGIN {FS = "## "}; /^## [a-zA-Z_-]/ {printf "  \033[36m%s\033[0m\n", $$2}; /^##  / {printf "  %s\n", $$2}'
